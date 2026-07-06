import Foundation
import AppCore
import MusicTheoryKit

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
      press <pitch>           simule l'appui d'une touche (0-127), sans materiel MIDI
      release <pitch>         simule le relachement d'une touche
      samples <dossier>       liste les fichiers .sf2/.dls/.aupreset du dossier
      use-sample <n ou nom>   charge l'instrument (numero de la liste ou nom de fichier)
      status                  affiche l'etat courant (piece, accord et mode detectes)
      watch                   ecran fixe qui se met a jour en direct (Ctrl+C pour revenir)
      quit                    quitte
    """)
}

func printStatus() {
    print(TextStyle.field("Piece", session.piece.map { $0.title } ?? TextStyle.placeholder("(aucun)")))
    print(TextStyle.field("Playing", TextStyle.flag(session.isPlaying)))
    let listeningValue = TextStyle.flag(session.isListening) + (session.isListening ? (session.listenOnly ? " (listen-only)" : " (son via l'appli)") : "")
    print(TextStyle.field("Listening", listeningValue))
    if session.isListening {
        let chordText = session.recognizedChord.map { "\($0.root.name())\($0.chordTemplateID)" } ?? TextStyle.placeholder("(aucun)")
        print(TextStyle.field("Chord", chordText))
        let modesText = session.recognizedModes.isEmpty
            ? TextStyle.placeholder("(aucun)")
            : session.recognizedModes.map { "\($0.tonic.name()) \($0.scaleID)" }.joined(separator: ", ")
        print(TextStyle.field("Modes", modesText))
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

nonisolated(unsafe) var watchShouldStop = false

/// Redraws one frame in place: cursor to top-left (no full clear, to avoid flicker),
/// each line cleared to end-of-line before being (re)printed so a shorter new value
/// doesn't leave stray characters from the previous, longer one, then clears any leftover
/// lines below in case this frame is shorter than the last.
func renderWatchFrame() {
    func line(_ text: String = "") {
        print("\u{1B}[K" + text)
    }
    print("\u{1B}[H", terminator: "")
    line(TextStyle.heading("Music Improv Assistant — écran de suivi (Ctrl+C pour revenir au prompt)"))
    line()
    line(TextStyle.field("Piece", session.piece.map { $0.title } ?? TextStyle.placeholder("(aucun)")))
    line(TextStyle.field("Playing", TextStyle.flag(session.isPlaying)))
    let listeningValue = TextStyle.flag(session.isListening) + (session.isListening ? (session.listenOnly ? " (listen-only)" : " (son via l'appli)") : "")
    line(TextStyle.field("Listening", listeningValue))
    line()
    let chordText = session.recognizedChord.map { chord -> String in
        let slash = chord.bass != chord.root ? "/\(chord.bass.name())" : ""
        return "\(chord.root.name())\(chord.chordTemplateID)\(slash) (\(Int(chord.confidence * 100))%)"
    } ?? TextStyle.placeholder("(aucun)")
    line(TextStyle.field("Chord", chordText))
    let modesText = session.recognizedModes.isEmpty
        ? TextStyle.placeholder("(aucun)")
        : session.recognizedModes.prefix(3).map { "\($0.tonic.name()) \($0.scaleID) (\(Int($0.confidence * 100))%)" }.joined(separator: "  |  ")
    line(TextStyle.field("Modes", modesText))
    line()
    let lastEventText = session.lastMIDIEvent.map { "\($0.kind == .noteOn ? "on " : "off")pitch=\($0.pitch) vel=\($0.velocity)" } ?? "-"
    line(TextStyle.field("Dernier evt MIDI", lastEventText))
    if !session.isListening {
        line()
        line(TextStyle.placeholder("(tape 'listen' avant 'watch' pour voir l'accord/mode se mettre a jour)"))
    }

    // Flattened mode display: just the scale's notes in order, not a second keyboard —
    // the keyboard below also gets a one-row marker of the same notes (point 1).
    line()
    let topScale = session.recognizedModes.first.flatMap { mode in ScaleLibrary.byID(mode.scaleID).map { (mode, $0) } }
    if let (topMode, scale) = topScale {
        let notes = Mode(tonic: topMode.tonic, scale: scale).pitchClasses.map { $0.name() }.joined(separator: " ")
        line(TextStyle.field("Notes du mode", "(\(topMode.tonic.name()) \(scale.popularName)) \(notes)"))
    } else {
        line(TextStyle.field("Notes du mode", TextStyle.placeholder("(aucun mode detecte)")))
    }

    // Fixed 3-octave window (C3–B5): covers most of what's played on a physical keyboard
    // while staying simple — no dynamic re-centering, so the octave zones stay put.
    let heldPitches = session.heldPitches
    let chord = session.recognizedChord
    let chordPitchClasses: Set<Int>? = chord.flatMap { c in
        ChordVocabulary.byID(c.chordTemplateID).map { template in
            Set(template.intervalsFromRoot.map { (c.root.value + $0) % 12 })
        }
    }
    let modeScaleSet: Set<PitchClass>? = topScale.map { Mode(tonic: $0.0.tonic, scale: $0.1).pitchClassSet }

    line()
    line(TextStyle.heading("Clavier joue (C3-B5):"))
    // 4 rows instead of 2: closer to how a real keyboard reads, black keys occupying only
    // the top half, white keys running the full height. Plus a marker row above it all
    // (point 1) showing which columns belong to the current mode, regardless of octave.
    for row in renderKeyboard(
        startMIDI: 48,
        octaveCount: 3,
        blackZoneRows: 2,
        whiteZoneRows: 2,
        modeMarker: modeScaleSet.map { scaleSet in { semitone in scaleSet.contains(PitchClass(semitone)) } },
        colorFor: { pitch in
            guard heldPitches.contains(pitch) else { return nil }
            guard let chord, let chordPitchClasses else { return KeyboardColor.heldNoChord }
            let pitchClass = ((pitch % 12) + 12) % 12
            if pitchClass == chord.root.value { return KeyboardColor.chordRoot }
            return chordPitchClasses.contains(pitchClass) ? KeyboardColor.chordTone : KeyboardColor.heldOutsideChord
        }
    ) { line(row) }

    print("\u{1B}[J", terminator: "") // erase any leftover lines below from a previous, taller frame
}

/// Takes over the terminal with a fixed, redrawn-in-place status screen until the user
/// hits Ctrl+C — a `DispatchSourceSignal` catches SIGINT asynchronously (safe to act on,
/// unlike a raw C signal handler) so the redraw loop can exit cleanly instead of the
/// whole process dying.
func runWatchScreen() {
    watchShouldStop = false
    signal(SIGINT, SIG_IGN)
    let sigSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    sigSource.setEventHandler { watchShouldStop = true }
    sigSource.resume()

    print("\u{1B}[?25l", terminator: "") // hide cursor
    print("\u{1B}[2J", terminator: "")   // clear once up front
    while !watchShouldStop {
        renderWatchFrame()
        Thread.sleep(forTimeInterval: 0.2)
    }
    sigSource.cancel()
    signal(SIGINT, SIG_DFL)
    print("\u{1B}[?25h") // restore cursor, then a newline to leave the frame behind
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
            case "press":
                guard let pitch = args.first.flatMap(Int.init) else { print("usage: press <pitch 0-127>"); break }
                session.pressKey(pitch: pitch)
            case "release":
                guard let pitch = args.first.flatMap(Int.init) else { print("usage: release <pitch 0-127>"); break }
                session.releaseKey(pitch: pitch)
            case "stop-listen":
                session.stopListening()
            case "samples":
                guard let folder = args.first else { print("usage: samples <dossier>"); break }
                try session.listSampleFiles(in: folder)
                drainLog() // flush "Found N sample file(s)..." before the numbered list
                for (index, name) in session.sampleFiles.enumerated() { print("  \(index + 1). \(name)") }
            case "use-sample":
                guard let arg = args.first else { print("usage: use-sample <numero ou nom de fichier>"); break }
                if let index = Int(arg) {
                    try session.loadSample(atIndex: index - 1)
                } else {
                    try session.loadSample(named: arg)
                }
            case "status":
                printStatus()
            case "watch":
                runWatchScreen()
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
