import Foundation
import AppCore

setvbuf(stdout, nil, _IONBF, 0)

// A blocking `readLine()` REPL never pumps the main run loop / main dispatch queue, so
// anything that needs to run on a genuinely different thread (the live log poller below,
// MIDI/playback callbacks in AppCore) must not be routed through `@MainActor` — it would
// simply queue forever until the user hits Enter. `ImprovSession` is `@unchecked Sendable`
// so it's usable as-is from any thread; `printedLogCount` below still needs
// `nonisolated(unsafe)` since a plain `Int` isn't automatically Sendable-safe to mutate.
let session = ImprovSession()
try session.start()

func printHelp() {
    print("""
    Commandes:
      help                    affiche cette aide
      load-demo               charge le morceau de demonstration (ii-V-I)
      load <path.json>        charge un Piece depuis un fichier JSON
      save <path.json>        sauvegarde le Piece courant en JSON
      play                    joue le Piece courant
      sources                 liste les sources MIDI visibles
      listen [--listen-only]  ecoute le MIDI (avec ou sans son produit par l'appli)
      stop-listen             arrete l'ecoute MIDI
      status                  affiche l'etat courant (piece, accord et mode detectes)
      quit                    quitte
    """)
}

func printStatus() {
    print("Piece: \(session.piece?.title ?? "(aucun)")")
    print("Playing: \(session.isPlaying)")
    print("Listening: \(session.isListening)\(session.isListening ? (session.listenOnly ? " (listen-only)" : " (son via l'appli)") : "")")
    if session.isListening {
        print("Chord: \(session.recognizedChord.map { "\($0.root.name())\($0.chordTemplateID)" } ?? "(aucun)")")
        print("Modes: \(session.recognizedModes.isEmpty ? "(aucun)" : session.recognizedModes.map { "\($0.tonic.name()) \($0.scaleID)" }.joined(separator: ", "))")
    }
}

nonisolated(unsafe) var printedLogCount = 0
let logLock = NSLock()

/// Prints any log lines appended since the last call. Called both from the REPL loop
/// (after each command) and from the live poller below (while listening) — locked so the
/// two never interleave their read-then-increment of `printedLogCount`.
func drainLog() {
    logLock.lock()
    defer { logLock.unlock() }
    while printedLogCount < session.log.count {
        print(session.log[printedLogCount])
        printedLogCount += 1
    }
}

func printPrompt() {
    print("> ", terminator: "")
}

/// While listening, prints new log lines (incoming MIDI notes, recognized chords/modes)
/// as they happen, instead of waiting for the user to press Enter again.
func pollLogWhileListening() {
    guard session.isListening else { return }
    drainLog()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.25, execute: pollLogWhileListening)
}

print("Music Improv Assistant — mode ligne de commande")
print("Tape 'help' pour la liste des commandes.")
drainLog() // flush the "Audio engine started." line logged by session.start() above
printPrompt()
while let line = readLine() {
    let parts = line.split(separator: " ").map(String.init)
    if let command = parts.first {
        let args = Array(parts.dropFirst())
        do {
            switch command {
            case "help":
                printHelp()
            case "load-demo":
                session.loadDemoPiece()
            case "load":
                guard let path = args.first else { print("usage: load <path.json>"); break }
                try session.loadPiece(fromJSONFile: path)
            case "save":
                guard let path = args.first else { print("usage: save <path.json>"); break }
                try session.savePiece(toJSONFile: path)
            case "play":
                try session.play()
            case "sources":
                let sources = session.availableMIDISources()
                print(sources.isEmpty ? "Aucune source MIDI visible." : sources.map { "- \($0)" }.joined(separator: "\n"))
            case "listen":
                try session.startListening(listenOnly: args.contains("--listen-only"))
                pollLogWhileListening()
            case "stop-listen":
                session.stopListening()
            case "status":
                printStatus()
            case "quit", "exit":
                session.stopListening()
                drainLog()
                exit(0)
            default:
                print("Commande inconnue: \(command). Tape 'help'.")
            }
        } catch {
            print("Erreur: \(error)")
        }
    }
    drainLog()
    printPrompt()
}
session.stopListening()
