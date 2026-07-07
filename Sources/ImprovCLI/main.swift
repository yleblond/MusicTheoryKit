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

// Default working folders, so `pieces`/`samples`/`llm-connections` don't need to be
// re-typed on every launch. Derived from this source file's own path (baked in at compile
// time via `#filePath`) rather than assumed from the current working directory, so it
// still resolves correctly no matter where `swift run` is invoked from — `Sources/ImprovCLI/
// main.swift` is 4 levels below the project root that holds `Pieces`/`SoundFonts`/
// `LLMConnections` as siblings of `MusicTheoryKit/`. `try?`: silently skipped if a folder
// doesn't exist (e.g. a different checkout) rather than failing startup.
let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // ImprovCLI
    .deletingLastPathComponent() // Sources
    .deletingLastPathComponent() // MusicTheoryKit
    .deletingLastPathComponent() // Music
try? session.listPieceFiles(in: projectRoot.appendingPathComponent("Pieces").path)
try? session.listSampleFiles(in: projectRoot.appendingPathComponent("SoundFonts").path)
try? session.listLLMConnections(in: projectRoot.appendingPathComponent("LLMConnections").path)

func printHelp() {
    print("""
    Commandes:
      help                       affiche cette aide
      load-demo                  charge le morceau de demonstration (ii-V-I)
      pieces <dossier>           liste les fichiers .json (morceaux) du dossier
      use-piece <n ou nom>       charge un morceau (numero de la liste ou nom de fichier)
      load <path.json>           charge un Piece depuis un fichier JSON (chemin explicite)
      save                       resauvegarde le Piece courant (meme fichier qu'au chargement)
      save-as <nom>              sauvegarde sous un nouveau nom, dans le dossier de morceaux
      play                       joue le Piece courant
      tracks                     liste les pistes d'entree (MIDI/clavier/micro) et leur etat
      midi-mode <fusionne|individuel>  MIDI en une piste fusionnee, ou une piste par port
      track <id> on|off          demarre/arrete l'ecoute d'une piste (id: midi, midi:<n>, clavier, micro)
      track <id> son on|off      active/desactive le son d'une piste (impossible pour 'micro')
      track <id> instrument <n|nom>  charge un instrument sur cette piste (active son son)
      press <pitch>              simule l'appui d'une touche (0-127) sur la piste 'clavier'
      release <pitch>            simule le relachement d'une touche sur la piste 'clavier'
      samples <dossier>          liste les fichiers .sf2/.dls/.aupreset du dossier
      use-sample <n ou nom>      charge l'instrument de lecture du morceau (numero ou nom)
      new-piece <titre>          demarre un morceau vierge
      paste-text                 colle un texte (poeme...), termine par une ligne vide
      llm-connections <dir>      liste les connexions LLM (.json) du dossier
      use-llm <n ou nom>         choisit une connexion LLM
      compose                    demande a l'IA de composer a partir du texte colle
      show-piece                 affiche la structure du morceau courant
      status                     affiche l'etat courant (piece, pistes actives, accord/mode)
      console                    ecran fixe qui se met a jour en direct (Ctrl+C pour revenir)
      quit                       quitte
    """)
}

func printPieceDetail() {
    guard let piece = session.piece else {
        print(TextStyle.placeholder("(aucun morceau charge)"))
        return
    }
    let keyName = ScaleLibrary.byID(piece.key.scaleID)?.popularName ?? piece.key.scaleID
    print(TextStyle.heading(piece.title) + (piece.composer.map { " — \($0)" } ?? ""))
    print(TextStyle.field("Tempo", "\(Int(piece.tempoBPM)) BPM"))
    print(TextStyle.field("Tonalite", "\(PitchClass(piece.key.tonic).name()) \(keyName)"))
    if piece.sections.isEmpty {
        print(TextStyle.placeholder("(pas encore de section)"))
    }
    for section in piece.sections {
        let modeName = ScaleLibrary.byID(section.mode.scaleID)?.popularName ?? section.mode.scaleID
        print()
        print(TextStyle.heading("Section \(section.name)") + " (\(section.lengthInMeasures) mesures, \(PitchClass(section.mode.tonic).name()) \(modeName))")
        for chordEvent in section.chordProgression.sorted(by: { $0.measure < $1.measure }) {
            let name = "\(PitchClass(chordEvent.chord.root).name())\(chordEvent.chord.chordTemplateID)"
            print("  mesure \(chordEvent.measure): \(name)")
        }
        for track in section.tracks where !track.melodyEvents.isEmpty {
            print("  melodie (\(track.name)): \(track.melodyEvents.count) notes")
        }
    }
}

/// Parses a track id as typed in commands — the inverse of `trackIDText`: "midi" (the
/// merged stream), "midi:<n>" (one-based port index, only meaningful in individual mode),
/// "clavier" (computer keyboard), "micro" (microphone).
func parseTrackID(_ text: String) -> TrackID? {
    let lower = text.lowercased()
    switch lower {
    case "midi": return .midiMerged
    case "clavier": return .computerKeyboard
    case "micro": return .microphone
    default:
        guard lower.hasPrefix("midi:"), let n = Int(lower.dropFirst(5)), n >= 1 else { return nil }
        return .midiSource(n - 1)
    }
}

/// What the user should type to refer to this track — the inverse of `parseTrackID`.
func trackIDText(_ id: TrackID) -> String {
    switch id {
    case .midiMerged: return "midi"
    case .midiSource(let index): return "midi:\(index + 1)"
    case .computerKeyboard: return "clavier"
    case .microphone: return "micro"
    }
}

/// A MIDI pitch number as a note name + octave (e.g. 60 -> "C4"), matching `Keyboard.swift`'s
/// octave numbering (octave 4 starts at C4 = pitch 60).
func noteNameWithOctave(_ pitch: Int) -> String {
    let pitchClass = ((pitch % 12) + 12) % 12
    return "\(PitchClass(pitchClass).name())\(pitch / 12 - 1)"
}

/// "(coupee)" when a not-yet-listening microphone track, else every currently-detected note
/// (one or several — see `FFTPitchAnalyzer.dominantFrequencies`) or "(silence)" when
/// listening but hearing nothing right now. The raw input level is always included, even in
/// silence — the only way to tell "nothing is reaching the microphone at all" (permission/
/// device problem: stays near 0) apart from "receiving audio, just no clear pitch in it"
/// (clearly above 0) without guessing.
func microphoneStatusText(_ track: TrackInfo) -> String {
    guard track.isListening else { return TextStyle.placeholder("(coupee)") }
    let level = String(format: "%.4f", track.microphoneInputLevel)
    guard !track.lastDetectedPitches.isEmpty else { return TextStyle.placeholder("(silence, niveau \(level))") }
    let notesText = track.lastDetectedPitches
        .sorted { $0.frequencyHz < $1.frequencyHz }
        .map { noteNameWithOctave($0.midiPitch) }
        .joined(separator: " ")
    return "\(notesText) (niveau \(level))"
}

/// One line per track — shared by the `tracks` command and the Source menu's prompts, so
/// picking a track id to act on always shows the same up-to-date list first.
func printTracks() {
    print(TextStyle.field("Mode MIDI", session.midiFusionMode == .merged ? "fusionne" : "individuel"))
    for track in session.tracks {
        var line = "  [\(trackIDText(track.id))] \(track.label) — ecoute: \(TextStyle.flag(track.isListening))"
        if track.canHaveSound {
            line += ", son: \(TextStyle.flag(track.soundEnabled))"
            if let instrument = track.instrumentName { line += " (\(instrument))" }
        }
        print(line)
    }
}

func printStatus() {
    print(TextStyle.field("Piece", session.piece.map { $0.title } ?? TextStyle.placeholder("(aucun)")))
    print(TextStyle.field("Fichier", session.currentPieceFilePath ?? TextStyle.placeholder("(jamais sauvegarde)")))
    print(TextStyle.field("Playing", TextStyle.flag(session.isPlaying)))
    print()
    printTracks()
    print()
    for track in session.tracks where track.isListening {
        print(TextStyle.heading("[\(trackIDText(track.id))] \(track.label)"))
        if track.id == .microphone {
            print(TextStyle.field("Micro", microphoneStatusText(track)))
            if track.microphoneInputLevel < 0.0005 {
                print(TextStyle.placeholder("  (niveau quasi nul: le micro ne semble rien recevoir. Verifie qu'il n'est pas coupe/mute, que c'est le bon peripherique d'entree, et que ce terminal a la permission microphone dans Reglages Systeme > Confidentialite et securite > Microphone)"))
            }
        }
        let chordText = track.recognizedChord.map { "\($0.root.name())\($0.chordTemplateID)" } ?? TextStyle.placeholder("(aucun)")
        print(TextStyle.field("Chord", chordText))
        let modesText = track.recognizedModes.isEmpty
            ? TextStyle.placeholder("(aucun)")
            : track.recognizedModes.map { "\($0.tonic.name()) \($0.scaleID)" }.joined(separator: ", ")
        print(TextStyle.field("Modes", modesText))
        print()
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

nonisolated(unsafe) var isInConsoleMode = false

/// Whether the computer's own keyboard is currently acting as a "piste clavier" (a virtual
/// piano typed on the physical keyboard) — kept in lockstep with the `clavier` track's
/// `isListening` state by the `track` command below, and consulted only by
/// `runConsoleScreen`'s key-dispatch loop, which disables the menu's letter mnemonics while
/// it's on (they'd otherwise collide with note-playing keys like F/L/A).
nonisolated(unsafe) var computerKeyboardSourceActive = false

/// Maps a typed character to a MIDI pitch, mirroring GarageBand's "Musical Typing" layout
/// (a real, widely-known Apple product with this exact key arrangement) so it's immediately
/// familiar rather than an invented scheme: the "ASDFGHJKL;" row plays the white keys of one
/// octave starting at C4, "WE_TYU_OP" fills in the black keys above the gaps.
let computerKeyboardNoteMap: [Character: Int] = [
    "a": 60, "w": 61, "s": 62, "e": 63, "d": 64, "f": 65, "t": 66, "g": 67,
    "y": 68, "h": 69, "u": 70, "j": 71, "k": 72, "o": 73, "l": 74, "p": 75, ";": 76,
]

/// Sounds one note then releases it shortly after. A plain terminal in raw mode only ever
/// delivers "this character was typed" — there is no key-up event to detect an actual
/// release — so a typed note is necessarily a short tap rather than a true sustain-while-
/// held; 300ms reads as a natural, comfortably audible pluck without the note visibly
/// hanging around on the keyboard display.
func triggerComputerKeyboardNote(_ pitch: Int) {
    session.pressKey(pitch: pitch)
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
        session.releaseKey(pitch: pitch)
    }
}

/// While any track is listening, prints new log lines (incoming notes, recognized chords/
/// modes) as they happen, instead of waiting for the user to press Enter again. Skips
/// printing while `console` is active: its own cursor-positioned redraw already shows
/// chord/mode/last-event live, and these plain `print`s would otherwise interleave with
/// (and visually corrupt) that redraw — keeps ticking regardless, so it resumes the instant
/// `console` exits.
func pollLogWhileListening() {
    guard session.tracks.contains(where: { $0.isListening }) else { return }
    if !isInConsoleMode {
        drainLog()
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.25, execute: pollLogWhileListening)
}

nonisolated(unsafe) var consoleShouldStop = false

/// Wraps a list of already-colored display strings into as many lines as needed to stay
/// under `maxWidth` *visible* columns each — `plainWidth` is measured separately from the
/// ANSI-decorated `display` string because color codes must not count toward the wrap
/// width. A long chord progression joined onto a single line, left to the terminal's own
/// auto-wrap, is exactly the kind of near-80-column line that previously broke this
/// renderer's line-by-line cursor positioning (see `Keyboard.swift`'s width comment) —
/// wrapping explicitly here means we control how many terminal rows it occupies instead.
func wrapItems(_ items: [(display: String, plainWidth: Int)], separator: String = "  ", maxWidth: Int = 70) -> [String] {
    guard !items.isEmpty else { return [""] }
    var lines: [String] = []
    var current = ""
    var currentWidth = 0
    for item in items {
        if currentWidth == 0 {
            current = item.display
            currentWidth = item.plainWidth
        } else if currentWidth + separator.count + item.plainWidth <= maxWidth {
            current += separator + item.display
            currentWidth += separator.count + item.plainWidth
        } else {
            lines.append(current)
            current = item.display
            currentWidth = item.plainWidth
        }
    }
    lines.append(current)
    return lines
}

/// Renders one track's keyboard (its own held pitches / recognized chord+mode, not any
/// other track's) — the console screen shows one of these per currently-listening track.
func renderTrackKeyboard(_ track: TrackInfo) -> [String] {
    let heldPitches = track.heldPitches
    let chord = track.recognizedChord
    let chordPitchClasses: Set<Int>? = chord.flatMap { c in
        ChordVocabulary.byID(c.chordTemplateID).map { template in
            Set(template.intervalsFromRoot.map { (c.root.value + $0) % 12 })
        }
    }
    let topScale = track.recognizedModes.first.flatMap { mode in ScaleLibrary.byID(mode.scaleID).map { (mode, $0) } }
    let modeScaleSet: Set<PitchClass>? = topScale.map { Mode(tonic: $0.0.tonic, scale: $0.1).pitchClassSet }

    return renderKeyboard(
        startMIDI: 48,
        octaveCount: 3,
        blackZoneRows: 2,
        whiteZoneRows: 2,
        modeMarker: { semitone in modeScaleSet?.contains(PitchClass(semitone)) ?? false },
        colorFor: { pitch in
            guard heldPitches.contains(pitch) else { return nil }
            guard let chord, let chordPitchClasses else { return KeyboardColor.heldNoChord }
            let pitchClass = ((pitch % 12) + 12) % 12
            if pitchClass == chord.root.value { return KeyboardColor.chordRoot }
            return chordPitchClasses.contains(pitchClass) ? KeyboardColor.chordTone : KeyboardColor.heldOutsideChord
        }
    )
}

/// Redraws one frame in place: cursor to top-left (no full clear, to avoid flicker),
/// each line cleared to end-of-line before being (re)printed so a shorter new value
/// doesn't leave stray characters from the previous, longer one, then clears any leftover
/// lines below in case this frame is shorter than the last.
func renderConsoleFrame() {
    func line(_ text: String = "") {
        print("\u{1B}[K" + text)
    }
    print("\u{1B}[H", terminator: "")
    line(renderMenuBar(menuCategories) + "   " + TextStyle.placeholder("(lettre: ouvre un menu, fleches, Entree, Echap — Ctrl+C: quitte l'ecran)"))
    if let openIndex = openMenuIndex {
        for row in renderDropdown(menuCategories[openIndex]) { line(row) }
    }
    line()
    line(TextStyle.field("Piece", session.piece.map { $0.title } ?? TextStyle.placeholder("(aucun)")))
    line(TextStyle.field("Fichier", session.currentPieceFilePath ?? TextStyle.placeholder("(jamais sauvegarde)")))
    line(TextStyle.field("Playing", TextStyle.flag(session.isPlaying)))
    line(TextStyle.field("Mode MIDI", session.midiFusionMode == .merged ? "fusionne" : "individuel"))
    let lastEventText = session.lastMIDIEvent.map { "\($0.kind == .noteOn ? "on " : "off")pitch=\($0.pitch) vel=\($0.velocity)" } ?? "-"
    line(TextStyle.field("Dernier evt", lastEventText))

    let listeningTracks = session.tracks.filter { $0.isListening }
    if listeningTracks.isEmpty {
        line()
        line(TextStyle.placeholder("(aucune piste en ecoute — menu Source pour en activer une)"))
    }
    for track in listeningTracks {
        line()
        line(TextStyle.heading("[\(trackIDText(track.id))] \(track.label)"))
        if track.id == .microphone {
            line(TextStyle.field("Micro", microphoneStatusText(track)))
        } else if track.canHaveSound {
            let soundText = TextStyle.flag(track.soundEnabled) + (track.instrumentName.map { " (\($0))" } ?? "")
            line(TextStyle.field("Son", soundText))
        }
        let chordText = track.recognizedChord.map { chord -> String in
            let slash = chord.bass != chord.root ? "/\(chord.bass.name())" : ""
            return "\(chord.root.name())\(chord.chordTemplateID)\(slash) (\(Int(chord.confidence * 100))%)"
        } ?? TextStyle.placeholder("(aucun)")
        line(TextStyle.field("Chord", chordText))
        let modesText = track.recognizedModes.isEmpty
            ? TextStyle.placeholder("(aucun)")
            : track.recognizedModes.prefix(3).map { "\($0.tonic.name()) \($0.scaleID) (\(Int($0.confidence * 100))%)" }.joined(separator: "  |  ")
        line(TextStyle.field("Modes", modesText))
        for row in renderTrackKeyboard(track) { line(row) }
    }

    // Playback position + a keyboard for "what the composition is playing right now" —
    // only shown while actually playing, mirroring how each track's own fields/keyboard
    // above only appear while that track is listening.
    if session.isPlaying {
        let timeline = session.playbackTimeline
        let currentIndex = session.playbackCurrentChordIndex
        let currentSegment = currentIndex.flatMap { timeline.indices.contains($0) ? timeline[$0] : nil }

        line()
        line(TextStyle.heading("Deroule de la composition:"))
        if timeline.isEmpty {
            line(TextStyle.placeholder("(pas d'accord dans ce morceau)"))
        } else {
            let items = timeline.enumerated().map { index, event -> (display: String, plainWidth: Int) in
                let name = "\(PitchClass(event.chord.root).name())\(event.chord.chordTemplateID)"
                if index == currentIndex {
                    return ("\(KeyboardColor.chordRoot)[\(name)]\(KeyboardColor.reset)", name.count + 2)
                }
                return (name, name.count)
            }
            for wrapped in wrapItems(items) { line(wrapped) }
        }

        let playbackChordPitchClasses: Set<Int>? = currentSegment.map { segment in
            guard let template = ChordVocabulary.byID(segment.chord.chordTemplateID) else { return [] }
            return Set(template.intervalsFromRoot.map { (segment.chord.root + $0) % 12 })
        }
        let playbackModeSet: Set<PitchClass>? = currentSegment.flatMap { segment in
            ScaleLibrary.byID(segment.mode.scaleID).map { scale in Mode(tonic: PitchClass(segment.mode.tonic), scale: scale).pitchClassSet }
        }
        let playbackHeld = session.playbackHeldPitches

        line()
        line(TextStyle.heading("Clavier compose, en cours de jeu (C3-B5):"))
        for row in renderKeyboard(
            startMIDI: 48,
            octaveCount: 3,
            blackZoneRows: 2,
            whiteZoneRows: 2,
            modeMarker: { semitone in playbackModeSet?.contains(PitchClass(semitone)) ?? false },
            colorFor: { pitch in
                guard playbackHeld.contains(pitch) else { return nil }
                guard let currentSegment, let playbackChordPitchClasses else { return KeyboardColor.heldNoChord }
                let pitchClass = ((pitch % 12) + 12) % 12
                if pitchClass == currentSegment.chord.root { return KeyboardColor.chordRoot }
                return playbackChordPitchClasses.contains(pitchClass) ? KeyboardColor.chordTone : KeyboardColor.heldOutsideChord
            }
        ) { line(row) }
    }

    print("\u{1B}[J", terminator: "") // erase any leftover lines below from a previous, taller frame
}

/// Takes over the terminal with a fixed, redrawn-in-place status screen until the user
/// hits Ctrl+C — a `DispatchSourceSignal` catches SIGINT asynchronously (safe to act on,
/// unlike a raw C signal handler) so the redraw loop can exit cleanly instead of the
/// whole process dying.
func runConsoleScreen() {
    consoleShouldStop = false
    isInConsoleMode = true
    openMenuIndex = nil
    selectedItemIndex = 0
    signal(SIGINT, SIG_IGN)
    let sigSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    sigSource.setEventHandler { consoleShouldStop = true }
    sigSource.resume()

    print("\u{1B}[?25l", terminator: "") // hide cursor
    print("\u{1B}[2J", terminator: "")   // clear once up front
    setRawMode(true)
    setStdinNonBlocking(true)
    while !consoleShouldStop {
        if let key = readKey() {
            switch key {
            case .char(let c) where computerKeyboardSourceActive:
                // "piste clavier" intercepts every character key itself — including
                // while a menu is open, where a letter would otherwise switch categories
                // by mnemonic (the exact conflict this mode exists to avoid). Escape (and
                // arrows, unaffected below) remain the way in and out of the menu.
                if openMenuIndex == nil, let pitch = computerKeyboardNoteMap[Character(c.lowercased())] {
                    triggerComputerKeyboardNote(pitch)
                }
            default:
                handleMenuKey(key, categories: menuCategories)
            }
        }
        renderConsoleFrame()
        Thread.sleep(forTimeInterval: 0.1)
    }
    setStdinNonBlocking(false)
    setRawMode(false)
    isInConsoleMode = false
    sigSource.cancel()
    signal(SIGINT, SIG_DFL)
    print("\u{1B}[?25h") // restore cursor, then a newline to leave the frame behind
    drainLog() // flush anything the log poller skipped printing while console was active
}

/// Stops every currently-listening track — used by `quit`/`exit` and at end of the REPL
/// loop, mirroring the old single `stopListening()`'s cleanup but across however many
/// tracks happen to be active now.
func stopAllTracks() {
    for track in session.tracks where track.isListening {
        session.stopTrack(track.id)
    }
    computerKeyboardSourceActive = false
}

/// Every command the REPL and the `console` menu both dispatch through — kept as one
/// switch so the menu can trigger exactly the same logic (e.g. "Jouer" just calls
/// `executeCommand("play", [])`) instead of duplicating it.
func executeCommand(_ command: String, _ args: [String]) throws {
    switch command {
    case "help":
        printHelp()
    case "load-demo":
        session.loadDemoPiece()
    case "pieces":
        guard let folder = args.first else { print("usage: pieces <dossier>"); break }
        try session.listPieceFiles(in: folder)
        drainLog() // flush "Found N piece file(s)..." before the numbered list
        for (index, name) in session.pieceFiles.enumerated() { print("  \(index + 1). \(name)") }
    case "use-piece":
        guard let arg = args.first else { print("usage: use-piece <numero ou nom de fichier>"); break }
        if let index = Int(arg) {
            try session.loadPiece(atIndex: index - 1)
        } else {
            try session.loadPiece(named: arg)
        }
    case "load":
        guard let path = args.first else { print("usage: load <path.json>"); break }
        try session.loadPiece(fromJSONFile: path)
    case "save":
        if let path = args.first {
            try session.savePiece(toJSONFile: path)
        } else {
            try session.savePiece()
        }
    case "save-as":
        guard let name = args.first else { print("usage: save-as <nom>"); break }
        try session.savePiece(as: name)
    case "play":
        try session.play()
    case "tracks":
        session.refreshTracks()
        printTracks()
    case "midi-mode":
        guard let arg = args.first?.lowercased() else { print("usage: midi-mode fusionne|individuel"); break }
        switch arg {
        case "fusionne", "merged": session.setMIDIFusionMode(.merged)
        case "individuel", "individual": session.setMIDIFusionMode(.individual)
        default: print("usage: midi-mode fusionne|individuel")
        }
    case "track":
        guard args.count >= 2, let id = parseTrackID(args[0]) else {
            print("usage: track <id> on|off | track <id> son on|off | track <id> instrument <n|nom>")
            print("   id: midi, midi:<n> (mode individuel), clavier, micro")
            break
        }
        switch args[1].lowercased() {
        case "on":
            try session.startTrack(id)
            if id == .computerKeyboard { computerKeyboardSourceActive = true }
            pollLogWhileListening()
        case "off":
            session.stopTrack(id)
            if id == .computerKeyboard { computerKeyboardSourceActive = false }
        case "son":
            guard let onOff = args.count >= 3 ? args[2].lowercased() : nil else { print("usage: track <id> son on|off"); break }
            switch onOff {
            case "on": try session.setSoundEnabled(true, for: id)
            case "off": try session.setSoundEnabled(false, for: id)
            default: print("usage: track <id> son on|off")
            }
        case "instrument":
            guard args.count >= 3 else { print("usage: track <id> instrument <n|nom>"); break }
            if let index = Int(args[2]) {
                try session.setInstrument(atIndex: index - 1, for: id)
            } else {
                try session.setInstrument(named: args[2], for: id)
            }
        default:
            print("usage: track <id> on|off | track <id> son on|off | track <id> instrument <n|nom>")
        }
    case "press":
        guard let pitch = args.first.flatMap(Int.init) else { print("usage: press <pitch 0-127>"); break }
        session.pressKey(pitch: pitch)
    case "release":
        guard let pitch = args.first.flatMap(Int.init) else { print("usage: release <pitch 0-127>"); break }
        session.releaseKey(pitch: pitch)
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
    case "new-piece":
        guard !args.isEmpty else { print("usage: new-piece <titre>"); break }
        session.newPiece(title: args.joined(separator: " "))
    case "paste-text":
        print("Colle ton texte (termine par une ligne vide) :")
        var lines: [String] = []
        while let textLine = readLine(), !textLine.isEmpty { lines.append(textLine) }
        session.setSourceText(lines.joined(separator: "\n"))
    case "llm-connections":
        guard let folder = args.first else { print("usage: llm-connections <dossier>"); break }
        try session.listLLMConnections(in: folder)
        drainLog() // flush "Found N LLM connection(s)..." before the numbered list
        for (index, name) in session.llmConnections.enumerated() { print("  \(index + 1). \(name)") }
    case "use-llm":
        guard let arg = args.first else { print("usage: use-llm <numero ou nom de fichier>"); break }
        if let index = Int(arg) {
            try session.useLLMConnection(atIndex: index - 1)
        } else {
            try session.useLLMConnection(named: arg)
        }
    case "compose":
        try session.composeFromText()
    case "show-piece":
        printPieceDetail()
    case "status":
        printStatus()
    case "console":
        runConsoleScreen()
    case "quit", "exit":
        stopAllTracks()
        drainLog()
        // Harmless no-ops if we were never in raw/non-blocking mode. Important either
        // way: `exec`-inherited stdin can share its underlying open-file-description with
        // the parent shell, so leaving O_NONBLOCK set could leak into the shell afterward.
        setStdinNonBlocking(false)
        setRawMode(false)
        print("\u{1B}[?25h", terminator: "") // ditto for the cursor
        exit(0)
    default:
        print("Commande inconnue: \(command). Tape 'help'.")
    }
}

/// The `console` screen's dropdown menus — each item just calls `executeCommand`, prompting
/// first for a folder/name/choice where needed. Defined after `executeCommand` (which they
/// all call) but before it's used in `runConsoleScreen`.
nonisolated(unsafe) let menuCategories: [MenuCategory] = [
    MenuCategory(mnemonic: "F", title: "Fichier", items: [
        MenuItem(label: "Charger demo") { try executeCommand("load-demo", []) },
        MenuItem(label: "Choisir dossier de morceaux...") {
            guard let folder = promptLine("Dossier de morceaux: "), !folder.isEmpty else { return }
            try executeCommand("pieces", [folder])
        },
        MenuItem(label: "Charger morceau...") {
            guard !session.pieceFiles.isEmpty else { print("Choisis d'abord un dossier de morceaux."); return }
            for (index, name) in session.pieceFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Charger quel morceau (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-piece", [choice])
        },
        MenuItem(label: "Sauvegarder") { try executeCommand("save", []) },
        MenuItem(label: "Sauvegarder sous...") {
            guard let name = promptLine("Nom de sauvegarde: "), !name.isEmpty else { return }
            try executeCommand("save-as", [name])
        },
        MenuItem(label: "Quitter") { try executeCommand("quit", []) },
    ]),
    MenuCategory(mnemonic: "L", title: "Lecture", items: [
        MenuItem(label: "Jouer") { try executeCommand("play", []) },
    ]),
    MenuCategory(mnemonic: "S", title: "Source", items: [
        MenuItem(label: "Lister les pistes") { try executeCommand("tracks", []) },
        MenuItem(label: "Mode MIDI: fusionne") { try executeCommand("midi-mode", ["fusionne"]) },
        MenuItem(label: "Mode MIDI: individuel") { try executeCommand("midi-mode", ["individuel"]) },
        MenuItem(label: "Activer une piste...") {
            try executeCommand("tracks", [])
            guard let choice = promptLine("Activer quelle piste (ex: midi, midi:1, clavier, micro): "), !choice.isEmpty else { return }
            try executeCommand("track", [choice, "on"])
        },
        MenuItem(label: "Arreter une piste...") {
            try executeCommand("tracks", [])
            guard let choice = promptLine("Arreter quelle piste: "), !choice.isEmpty else { return }
            try executeCommand("track", [choice, "off"])
        },
        MenuItem(label: "Activer le son d'une piste...") {
            try executeCommand("tracks", [])
            guard let choice = promptLine("Activer le son de quelle piste: "), !choice.isEmpty else { return }
            try executeCommand("track", [choice, "son", "on"])
        },
        MenuItem(label: "Desactiver le son d'une piste...") {
            try executeCommand("tracks", [])
            guard let choice = promptLine("Desactiver le son de quelle piste: "), !choice.isEmpty else { return }
            try executeCommand("track", [choice, "son", "off"])
        },
        MenuItem(label: "Choisir un instrument pour une piste...") {
            guard !session.sampleFiles.isEmpty else { print("Choisis d'abord un dossier de sons (menu Instrument)."); return }
            try executeCommand("tracks", [])
            for (index, name) in session.sampleFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let trackChoice = promptLine("Pour quelle piste: "), !trackChoice.isEmpty else { return }
            guard let sampleChoice = promptLine("Quel instrument (numero ou nom): "), !sampleChoice.isEmpty else { return }
            try executeCommand("track", [trackChoice, "instrument", sampleChoice])
        },
    ]),
    MenuCategory(mnemonic: "I", title: "Instrument", items: [
        MenuItem(label: "Choisir dossier de sons...") {
            guard let folder = promptLine("Dossier de sons: "), !folder.isEmpty else { return }
            try executeCommand("samples", [folder])
        },
        MenuItem(label: "Choisir le son de lecture du morceau...") {
            guard !session.sampleFiles.isEmpty else { print("Choisis d'abord un dossier de sons."); return }
            for (index, name) in session.sampleFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Charger quel son (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-sample", [choice])
        },
    ]),
    MenuCategory(mnemonic: "A", title: "IA", items: [
        MenuItem(label: "Nouveau morceau...") {
            guard let title = promptLine("Titre du nouveau morceau: "), !title.isEmpty else { return }
            try executeCommand("new-piece", [title])
        },
        MenuItem(label: "Coller un texte...") { try executeCommand("paste-text", []) },
        MenuItem(label: "Choisir dossier de connexions LLM...") {
            guard let folder = promptLine("Dossier de connexions LLM: "), !folder.isEmpty else { return }
            try executeCommand("llm-connections", [folder])
        },
        MenuItem(label: "Choisir une connexion LLM...") {
            guard !session.llmConnections.isEmpty else { print("Choisis d'abord un dossier de connexions LLM."); return }
            for (index, name) in session.llmConnections.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Utiliser quelle connexion (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-llm", [choice])
        },
        MenuItem(label: "Composer a partir du texte") { try executeCommand("compose", []) },
        MenuItem(label: "Voir le morceau") { try executeCommand("show-piece", []) },
    ]),
]

print("Music Improv Assistant — mode Command")
print("Tape 'help' pour la liste des commandes.")
drainLog() // flush the "Audio engine started." line logged by session.start() above
printPrompt()
while let line = readLine() {
    let parts = line.split(separator: " ").map(String.init)
    if let command = parts.first {
        let args = Array(parts.dropFirst())
        do {
            try executeCommand(command, args)
        } catch {
            print("Erreur: \(error)")
        }
    }
    drainLog()
    printPrompt()
}
stopAllTracks()
