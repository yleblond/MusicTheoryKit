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
try? FileManager.default.createDirectory(at: projectRoot.appendingPathComponent("SoundTracks"), withIntermediateDirectories: true)
try? session.listSoundTrackFiles(in: projectRoot.appendingPathComponent("SoundTracks").path)
try? session.setPromptsFolder(projectRoot.appendingPathComponent("Prompts").path) // creates Texte/Soundtrack if absent

func printHelp() {
    print("""
    Commandes (par categorie) :

    (un nom de fichier contenant des espaces doit etre entoure de guillemets, ex: use-sample "The Fox and The Crow General MIDI SoundFont Ultimate.sf2")

    General
      help                       affiche cette aide
      status                     affiche l'etat courant (piece, pistes actives, accord/mode)
      console                    ecran fixe qui se met a jour en direct (Ctrl+C pour revenir)
      quit                       quitte

    Morceaux (Piece Model — mesures/accords)
      load-demo                  charge le morceau de demonstration (ii-V-I)
      pieces <dossier>           liste les fichiers .json (morceaux) du dossier
      use-piece <n ou nom>       charge un morceau (numero de la liste ou nom de fichier)
      load <path.json>           charge un Piece depuis un fichier JSON (chemin explicite)
      save                       resauvegarde le Piece courant (meme fichier qu'au chargement)
      save-as <nom>              sauvegarde sous un nouveau nom, dans le dossier de morceaux
      play                       joue le Piece courant
      show-piece                 affiche la structure du morceau courant
      new-piece <titre>          demarre un morceau vierge

    Pistes d'entree
      tracks                     liste les pistes d'entree (MIDI/clavier/micro) et leur etat
      midi-mode <fusionne|individuel>  MIDI en une piste fusionnee, ou une piste par port
      track <id> on|off          demarre/arrete l'ecoute d'une piste (id: midi, midi:<n>, clavier, micro)
      track <id> son on|off      active/desactive le son d'une piste (impossible pour 'micro')
      track <id> instrument <n|nom>  charge un instrument sur cette piste (active son son)
      press <pitch>              simule l'appui d'une touche (0-127) sur la piste 'clavier'
      release <pitch>            simule le relachement d'une touche sur la piste 'clavier'

    Instruments (lecture du morceau)
      samples <dossier>          liste les fichiers .sf2/.dls/.aupreset du dossier
      use-sample <n ou nom>      charge le son par defaut de la lecture (pistes/accords sans instrument propre)
      set-track-instrument <section> <piste> <nom-sample|numero|vide>  instrument d'une piste melodique
      set-chord-instrument <section> <nom-sample|numero|vide>          instrument des accords d'une section
      (numeros de section/piste affiches par 'show-piece'; nom-sample = fichier dans le dossier 'samples'; 'vide' = son par defaut; penser a 'save'/'save-as' pour garder le changement)

    Soundtrack (enregistrement — evenementiel, secondes)
      record start [<id> ...]    demarre l'enregistrement (toutes les pistes en ecoute, ou celles listees)
      record stop                arrete l'enregistrement en cours
      play-soundtrack            joue la soundtrack courante (mode temporel)
      soundtracks <dossier>      liste les fichiers .json (soundtracks) du dossier
      use-soundtrack <n ou nom>  charge une soundtrack
      save-soundtrack            resauvegarde la soundtrack courante
      save-soundtrack-as <nom>   sauvegarde sous un nouveau nom
      show-soundtrack            affiche les infos de la soundtrack courante (duree, pistes...)
      compose-piece-from-soundtrack [n] [titre]  demande a l'IA d'en deduire n Piece Model (defaut 1), nomme <titre> s'il est donne

    Composition (texte -> morceau, soundtrack -> morceau)
      paste-text                 colle un texte (description du morceau), termine par une ligne vide
      title [texte]              titre du morceau a composer (vide efface); voir 'show-description'
      indications [texte]        indications de style additionnelles (vide efface); voir aussi le menu Composition
      show-description           affiche le titre, la description et les indications en cours
      llm-connections <dir>      liste les connexions LLM (.json) du dossier
      use-llm <n ou nom>         choisit une connexion LLM
      compose [titre]            demande a l'IA de composer a partir de la description, nomme <titre> s'il est donne
      prompts <dossier>          pointe le dossier de prompts (sous-dossiers Texte/ et Soundtrack/, crees si absents)
      show-text-prompt           affiche le prompt de composition a partir du texte colle
      show-soundtrack-prompt     affiche le prompt de composition a partir de la soundtrack
      save-text-prompt <nom>     sauvegarde le prompt (texte) affiche par show-text-prompt
      save-soundtrack-prompt <nom>  idem pour le prompt (soundtrack)
      use-text-prompt <n ou nom>     charge un prompt (texte) sauvegarde, utilise par le prochain 'compose'
      use-soundtrack-prompt <n ou nom>  idem pour 'compose-piece-from-soundtrack'
      reset-text-prompt / reset-soundtrack-prompt  revient au prompt par defaut (reconstruit a chaque fois)

    Session collaborative (reseau)
      server [port]              demarre un serveur collaboratif (defaut port 7777)
      stop-server                arrete le serveur
      client [host] [port]       rejoint un serveur (defaut localhost:7777)
      discover                   recherche des serveurs sur le reseau local et propose de rejoindre
      disconnect                 se deconnecte du serveur
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
        let chordInstrumentText = section.chordInstrument.map { "'\($0)'" } ?? "par defaut"
        print("  accords (instrument \(chordInstrumentText)):")
        for chordEvent in section.chordProgression.sorted(by: { $0.measure < $1.measure }) {
            let name = "\(PitchClass(chordEvent.chord.root).name())\(chordEvent.chord.chordTemplateID)"
            print("    mesure \(chordEvent.measure): \(name)")
        }
        for (trackIndex, track) in section.tracks.enumerated() where !track.melodyEvents.isEmpty {
            let instrumentText = track.instrument.isEmpty ? "par defaut" : "'\(track.instrument)'"
            print("  piste \(trackIndex + 1) '\(track.name)' (instrument \(instrumentText)): \(track.melodyEvents.count) notes")
        }
    }
}

func printSoundTrackDetail() {
    guard let soundTrack = session.currentSoundTrack else {
        print(TextStyle.placeholder("(aucune soundtrack enregistree ou chargee)"))
        return
    }
    print(TextStyle.heading(soundTrack.title))
    print(TextStyle.field("Fichier", session.currentSoundTrackFilePath ?? TextStyle.placeholder("(jamais sauvegardee)")))
    print(TextStyle.field("Duree", String(format: "%.1fs", soundTrack.durationSeconds)))
    print(TextStyle.field("Evenements", "\(soundTrack.events.count)"))
    print(TextStyle.field("Pistes", soundTrack.trackIDs.sorted().joined(separator: ", ")))
}

/// Everything the "Decrire le morceau..." wizard collects before composing — title,
/// description (`sourceText`), and style indications — shown together so it's easy to
/// check what's about to be sent before actually calling `compose`.
func printCompositionDescription() {
    print(TextStyle.field("Titre", session.compositionTitle ?? TextStyle.placeholder("(aucun)")))
    print(TextStyle.field("Indications", session.additionalCompositionInstructions ?? TextStyle.placeholder("(aucune)")))
    if let sourceText = session.sourceText {
        print(TextStyle.field("Description", ""))
        print(sourceText)
    } else {
        print(TextStyle.field("Description", TextStyle.placeholder("(aucune)")))
    }
}

/// Parses a track id as typed in commands — the inverse of `trackIDText`: "midi" (the
/// merged stream), "midi:<n>" (one-based port index, only meaningful in individual mode),
/// "clavier" (computer keyboard), "micro" (microphone), "remote:<clientID>@<trackID>" (a
/// participant's own track in a collaborative session — copy/paste the exact id shown by
/// `tracks`, its `clientID` is a UUID not meant to be typed from scratch).
func parseTrackID(_ text: String) -> TrackID? {
    let lower = text.lowercased()
    switch lower {
    case "midi": return .midiMerged
    case "clavier": return .computerKeyboard
    case "micro": return .microphone
    default:
        if lower.hasPrefix("midi:"), let n = Int(lower.dropFirst(5)), n >= 1 {
            return .midiSource(n - 1)
        }
        if text.hasPrefix("remote:"), let atIndex = text.firstIndex(of: "@") {
            let clientID = String(text[text.index(text.startIndex, offsetBy: 7)..<atIndex])
            let trackID = String(text[text.index(after: atIndex)...])
            guard !clientID.isEmpty, !trackID.isEmpty else { return nil }
            return .remote(clientID: clientID, trackID: trackID)
        }
        return nil
    }
}

/// Resolves a "<n|nom|vide>"-style argument against `session.sampleFiles` — the same
/// convention `use-sample`/`track <id> instrument <n|nom>` already use, shared here so
/// `set-track-instrument`/`set-chord-instrument` (and their menu items) behave the same way.
/// Empty means "no instrument" (`nil`); a number resolves by 1-based position (throwing
/// `invalidSampleIndex` if out of range, same as every other numbered picker in this app);
/// anything else is taken as a literal file name.
func resolvedSampleName(_ text: String) throws -> String? {
    if text.isEmpty { return nil }
    if let index = Int(text) {
        guard session.sampleFiles.indices.contains(index - 1) else { throw ImprovSession.SessionError.invalidSampleIndex }
        return session.sampleFiles[index - 1]
    }
    return text
}

/// What the user should type to refer to this track — the inverse of `parseTrackID`.
func trackIDText(_ id: TrackID) -> String {
    switch id {
    case .midiMerged: return "midi"
    case .midiSource(let index): return "midi:\(index + 1)"
    case .computerKeyboard: return "clavier"
    case .microphone: return "micro"
    case .remote(let clientID, let trackID): return "remote:\(clientID)@\(trackID)"
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

/// "(aucun)" / the real recognized chord, whichever applies — real structured recognition
/// (`recognizedChord`) for a track this machine actually runs a recognizer for (every local
/// track, or any track at all if this machine is the server), or the pre-formatted string
/// the server already sent (`remoteChordDisplay`) for a `.remote` track mirrored on a client
/// (a client never re-derives recognition itself, see `ImprovSession.mergeRemoteSnapshot`).
func chordDisplayText(_ track: TrackInfo) -> String {
    // Real structured recognition always wins when present — a `.remote` track has one
    // too on whichever machine is acting as server (it runs a real recognizer for every
    // track, local or remote). Only a client, which never re-derives recognition for a
    // track it doesn't own, falls back to the display string the server already sent.
    if let chord = track.recognizedChord {
        let slash = chord.bass != chord.root ? "/\(chord.bass.name())" : ""
        return "\(chord.root.name())\(chord.chordTemplateID)\(slash) (\(Int(chord.confidence * 100))%)"
    }
    if case .remote = track.id, let display = track.remoteChordDisplay {
        return display
    }
    return TextStyle.placeholder("(aucun)")
}

/// Same idea as `chordDisplayText`, for mode candidates.
func modesDisplayText(_ track: TrackInfo) -> String {
    if !track.recognizedModes.isEmpty {
        return track.recognizedModes.prefix(3).map { "\($0.tonic.name()) \($0.scaleID) (\(Int($0.confidence * 100))%)" }.joined(separator: "  |  ")
    }
    if case .remote = track.id, let display = track.remoteModesDisplay {
        return display
    }
    return TextStyle.placeholder("(aucun)")
}

/// "solo" / "serveur sur le port N" / "connecte a host:port" — shared by `tracks`/`status`/
/// `console`.
func networkRoleText() -> String {
    switch session.networkRole {
    case .standalone: return TextStyle.placeholder("(solo)")
    case .server(let port): return "serveur sur le port \(port)"
    case .client(let description): return "connecte a \(description)"
    }
}

/// One line per track — shared by the `tracks` command and the Source/Reseau menus'
/// prompts, so picking a track id to act on always shows the same up-to-date list first.
func printTracks() {
    print(TextStyle.field("Reseau", networkRoleText()))
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
    print(TextStyle.field("Recording", TextStyle.flag(session.isRecording)))
    print(TextStyle.field("Soundtrack", session.currentSoundTrack.map { $0.title } ?? TextStyle.placeholder("(aucune)")))
    print(TextStyle.field("Playing (soundtrack)", TextStyle.flag(session.isPlayingSoundTrack)))
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
        print(TextStyle.field("Chord", chordDisplayText(track)))
        print(TextStyle.field("Modes", modesDisplayText(track)))
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
/// A `.remote` track mirrored on a client only carries `heldPitches` plus display-string
/// chord/mode summaries (`remoteChordDisplay`/`remoteModesDisplay`, see `chordDisplayText`)
/// — not the structured `recognizedChord`/`recognizedModes` this function colors by, since
/// a client never re-derives recognition itself. Its keyboard still lights up the held keys
/// (plain "held" white), just without root/tone coloring or a mode-marker row — a known,
/// accepted degradation rather than reconstructing a fake chord from a string.
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
///
/// The whole frame is built into one string and written with a single `print` at the end
/// (see the matching comment by the final `print`) rather than one `print` per line — a
/// real fix, not cosmetic: a taller frame (e.g. the `Enregistrement` dropdown, now 15+
/// lines with its prompt sub-section) means more separate flushes per redraw at 10/s, and
/// a terminal can visibly paint those one at a time, which is exactly the jumpiness this
/// was reported as ("sautillement... quand le menu est deploye") — worse the taller the
/// open dropdown, matching the symptom.
func renderConsoleFrame() {
    var output = "\u{1B}[H"
    func line(_ text: String = "") {
        output += "\u{1B}[K" + text + "\n"
    }
    line(renderMenuBar(menuCategories) + "   " + TextStyle.placeholder("(lettre: ouvre un menu, fleches, Entree, Echap — Ctrl+C: quitte l'ecran)"))
    if let openIndex = openMenuIndex {
        for row in renderDropdown(menuCategories[openIndex]) { line(row) }
    }
    line()
    line(TextStyle.field("Piece", session.piece.map { $0.title } ?? TextStyle.placeholder("(aucun)")))
    line(TextStyle.field("Fichier", session.currentPieceFilePath ?? TextStyle.placeholder("(jamais sauvegarde)")))
    line(TextStyle.field("Playing", TextStyle.flag(session.isPlaying)))
    line(TextStyle.field("Recording", TextStyle.flag(session.isRecording)))
    line(TextStyle.field("Soundtrack", session.currentSoundTrack.map { $0.title } ?? TextStyle.placeholder("(aucune)")))
    line(TextStyle.field("Reseau", networkRoleText()))
    line(TextStyle.field("Mode MIDI", session.midiFusionMode == .merged ? "fusionne" : "individuel"))
    let lastEventText = session.lastMIDIEvent.map { "\($0.kind == .noteOn ? "on " : "off")pitch=\($0.pitch) vel=\($0.velocity)" } ?? "-"
    line(TextStyle.field("Dernier evt", lastEventText))

    let listeningTracks = session.tracks.filter { $0.isListening }
    if listeningTracks.isEmpty {
        line()
        line(TextStyle.placeholder("(aucune piste en ecoute — menu Instruments pour en activer une)"))
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
        line(TextStyle.field("Chord", chordDisplayText(track)))
        line(TextStyle.field("Modes", modesDisplayText(track)))
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

    // Soundtrack playback (temporal, purely evenementiel mode) — a third, independent
    // keyboard, only shown while playing back a recording. No chord/mode analysis here:
    // a SoundTrack is raw events, not a theory-modeled Piece, so held notes are shown
    // plain (no root/tone coloring) rather than inventing an analysis that wasn't asked for.
    if session.isPlayingSoundTrack {
        let soundTrackHeld = session.soundTrackHeldPitches
        line()
        line(TextStyle.heading("Clavier soundtrack, en cours de jeu (C3-B5):"))
        for row in renderKeyboard(
            startMIDI: 48, octaveCount: 3, blackZoneRows: 2, whiteZoneRows: 2,
            colorFor: { pitch in soundTrackHeld.contains(pitch) ? KeyboardColor.heldNoChord : nil }
        ) { line(row) }
    }

    output += "\u{1B}[J" // erase any leftover lines below from a previous, taller frame
    print(output, terminator: "") // one single write for the whole frame — see the doc comment above
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

/// Stops every currently-listening track (a no-op for any `.remote` one — not locally
/// controllable) and tears down any active server/client role — used by `quit`/`exit` and
/// at end of the REPL loop, mirroring the old single `stopListening()`'s cleanup but across
/// however many tracks (and whichever network role) happen to be active now.
func stopAllTracks() {
    for track in session.tracks where track.isListening {
        session.stopTrack(track.id)
    }
    computerKeyboardSourceActive = false
    session.stopServer()
    session.disconnectFromServer()
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
    case "server":
        let port = args.first.flatMap(Int.init) ?? 7777
        try session.startServer(port: port)
    case "stop-server":
        session.stopServer()
    case "client":
        let host = args.count >= 1 ? args[0] : "localhost"
        let port = args.count >= 2 ? (Int(args[1]) ?? 7777) : 7777
        try session.connectToServer(host: host, port: port)
    case "disconnect":
        session.disconnectFromServer()
    case "discover":
        print("Recherche de serveurs sur le reseau local...")
        let found = session.discoverServers()
        if found.isEmpty {
            print("Aucun serveur trouve. Verifie que 'server' tourne bien de l'autre cote, sur le meme reseau, et que la permission 'Reseau local' est accordee (Reglages Systeme > Confidentialite et securite > Reseau local).")
            break
        }
        for (index, server) in found.enumerated() { print("  \(index + 1). \(server.name)") }
        guard let choice = promptLine("Rejoindre quel serveur (numero, vide pour abandonner): "), let index = Int(choice), found.indices.contains(index - 1) else {
            print("Abandon.")
            break
        }
        try session.connectToServer(discovered: found[index - 1])
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
    case "indications":
        session.setAdditionalCompositionInstructions(args.isEmpty ? nil : args.joined(separator: " "))
    case "title":
        session.setCompositionTitle(args.isEmpty ? nil : args.joined(separator: " "))
    case "show-description":
        printCompositionDescription()
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
        try session.composeFromText(title: args.isEmpty ? nil : args.joined(separator: " "))
    case "show-piece":
        printPieceDetail()
    case "prompts":
        guard let folder = args.first else { print("usage: prompts <dossier>"); break }
        try session.setPromptsFolder(folder)
        drainLog() // flush "Dossier de prompts: ..." before the numbered lists
        print("Texte:")
        for (index, name) in session.textPromptFiles.enumerated() { print("  \(index + 1). \(name)") }
        print("Soundtrack:")
        for (index, name) in session.soundTrackPromptFiles.enumerated() { print("  \(index + 1). \(name)") }
    case "show-text-prompt":
        print(try session.currentTextCompositionPrompt())
    case "show-soundtrack-prompt":
        print(try session.currentSoundTrackCompositionPrompt())
    case "save-text-prompt":
        guard let name = args.first else { print("usage: save-text-prompt <nom>"); break }
        try session.saveTextCompositionPrompt(as: name)
    case "save-soundtrack-prompt":
        guard let name = args.first else { print("usage: save-soundtrack-prompt <nom>"); break }
        try session.saveSoundTrackCompositionPrompt(as: name)
    case "use-text-prompt":
        guard let arg = args.first else { print("usage: use-text-prompt <numero ou nom de fichier>"); break }
        if let index = Int(arg) {
            try session.useTextCompositionPrompt(atIndex: index - 1)
        } else {
            try session.useTextCompositionPrompt(named: arg)
        }
    case "use-soundtrack-prompt":
        guard let arg = args.first else { print("usage: use-soundtrack-prompt <numero ou nom de fichier>"); break }
        if let index = Int(arg) {
            try session.useSoundTrackCompositionPrompt(atIndex: index - 1)
        } else {
            try session.useSoundTrackCompositionPrompt(named: arg)
        }
    case "reset-text-prompt":
        session.resetTextCompositionPrompt()
    case "reset-soundtrack-prompt":
        session.resetSoundTrackCompositionPrompt()
    case "set-track-instrument":
        guard args.count >= 3, let section = Int(args[0]), let track = Int(args[1]) else {
            print("usage: set-track-instrument <section> <piste> <nom-sample|numero|vide>")
            break
        }
        try session.setPieceTrackInstrument(sectionIndex: section - 1, trackIndex: track - 1, instrumentName: try resolvedSampleName(args[2]))
    case "set-chord-instrument":
        guard args.count >= 1, let section = Int(args[0]) else {
            print("usage: set-chord-instrument <section> <nom-sample|numero|vide>")
            break
        }
        try session.setPieceChordInstrument(sectionIndex: section - 1, instrumentName: try resolvedSampleName(args.count >= 2 ? args[1] : ""))
    case "record":
        guard let sub = args.first else { print("usage: record start [<id> ...] | record stop"); break }
        switch sub {
        case "start":
            var trackSet: Set<TrackID> = []
            for idText in args.dropFirst() {
                guard let id = parseTrackID(idText) else { print("piste inconnue: \(idText)"); return }
                trackSet.insert(id)
            }
            try session.startRecording(title: "Enregistrement", tracks: trackSet)
        case "stop":
            let soundTrack = try session.stopRecording()
            print("Enregistrement termine : \(soundTrack.events.count) evenement(s), \(String(format: "%.1f", soundTrack.durationSeconds))s.")
        default:
            print("usage: record start [<id> ...] | record stop")
        }
    case "play-soundtrack":
        try session.playSoundTrack()
    case "soundtracks":
        guard let folder = args.first else { print("usage: soundtracks <dossier>"); break }
        try session.listSoundTrackFiles(in: folder)
        drainLog() // flush "Found N soundtrack file(s)..." before the numbered list
        for (index, name) in session.soundTrackFiles.enumerated() { print("  \(index + 1). \(name)") }
    case "use-soundtrack":
        guard let arg = args.first else { print("usage: use-soundtrack <numero ou nom de fichier>"); break }
        if let index = Int(arg) {
            try session.loadSoundTrack(atIndex: index - 1)
        } else {
            try session.loadSoundTrack(named: arg)
        }
    case "save-soundtrack":
        if let path = args.first {
            try session.saveSoundTrack(toJSONFile: path)
        } else {
            try session.saveSoundTrack()
        }
    case "save-soundtrack-as":
        guard let name = args.first else { print("usage: save-soundtrack-as <nom>"); break }
        try session.saveSoundTrack(as: name)
    case "show-soundtrack":
        printSoundTrackDetail()
    case "compose-piece-from-soundtrack":
        // usage: compose-piece-from-soundtrack [<n-candidats>] [<titre...>] — a leading
        // integer is the candidate count; everything after (or everything, if the first
        // token isn't a number) is the title, joined back with spaces.
        var count = 1
        var titleArgs = args[...]
        if let first = args.first, let parsedCount = Int(first) {
            count = parsedCount
            titleArgs = args.dropFirst()
        }
        let title = titleArgs.isEmpty ? nil : titleArgs.joined(separator: " ")
        let paths = try session.composeSoundTrackToPieces(candidateCount: count, title: title)
        for path in paths { print("  -> \(path)") }
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
    // Mnemonic "L" (not the first letter) to avoid colliding with "Morceaux"'s "M" — same
    // trick already used for "IA" vs "Instrument", see renderMenuBar's doc comment.
    MenuCategory(mnemonic: "L", title: "MusicLab", items: [
        MenuItem(label: "Infos") { try executeCommand("status", []) },
        MenuItem(label: "Aide") { try executeCommand("help", []) },
        MenuItem.separator,
        MenuItem(label: "Choisir dossier de morceaux...") {
            guard let folder = promptLine("Dossier de morceaux: "), !folder.isEmpty else { return }
            try executeCommand("pieces", [folder])
        },
        MenuItem(label: "Choisir dossier de sons...") {
            guard let folder = promptLine("Dossier de sons: "), !folder.isEmpty else { return }
            try executeCommand("samples", [folder])
        },
        MenuItem(label: "Choisir dossier de soundtracks...") {
            guard let folder = promptLine("Dossier de soundtracks: "), !folder.isEmpty else { return }
            try executeCommand("soundtracks", [folder])
        },
        MenuItem(label: "Choisir dossier de connexions LLM...") {
            guard let folder = promptLine("Dossier de connexions LLM: "), !folder.isEmpty else { return }
            try executeCommand("llm-connections", [folder])
        },
        MenuItem(label: "Choisir dossier de prompts...") {
            guard let folder = promptLine("Dossier de prompts (sous-dossiers Texte/Soundtrack crees si absents): "), !folder.isEmpty else { return }
            try executeCommand("prompts", [folder])
        },
        MenuItem(label: "Choisir une connexion LLM...") {
            guard !session.llmConnections.isEmpty else { print("Choisis d'abord un dossier de connexions LLM."); return }
            for (index, name) in session.llmConnections.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Utiliser quelle connexion (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-llm", [choice])
        },
        MenuItem.separator,
        MenuItem(label: "Mode MIDI: fusionne") { try executeCommand("midi-mode", ["fusionne"]) },
        MenuItem(label: "Mode MIDI: individuel") { try executeCommand("midi-mode", ["individuel"]) },
        MenuItem.separator,
        MenuItem(label: "Quitter") { try executeCommand("quit", []) },
    ]),
    MenuCategory(mnemonic: "I", title: "Instruments", items: [
        MenuItem(label: "Lister les instruments") { try executeCommand("tracks", []) },
        MenuItem(label: "Activer un instrument...") {
            try executeCommand("tracks", [])
            guard let choice = promptLine("Activer quel instrument (ex: midi, midi:1, clavier, micro): "), !choice.isEmpty else { return }
            try executeCommand("track", [choice, "on"])
        },
        MenuItem(label: "Arreter un instrument...") {
            try executeCommand("tracks", [])
            guard let choice = promptLine("Arreter quel instrument: "), !choice.isEmpty else { return }
            try executeCommand("track", [choice, "off"])
        },
        MenuItem.separator,
        MenuItem(label: "Activer le son d'un instrument...") {
            try executeCommand("tracks", [])
            guard let choice = promptLine("Activer le son de quel instrument: "), !choice.isEmpty else { return }
            try executeCommand("track", [choice, "son", "on"])
        },
        MenuItem(label: "Desactiver le son d'un instrument...") {
            try executeCommand("tracks", [])
            guard let choice = promptLine("Desactiver le son de quel instrument: "), !choice.isEmpty else { return }
            try executeCommand("track", [choice, "son", "off"])
        },
        MenuItem(label: "Choisir un son pour un instrument...") {
            guard !session.sampleFiles.isEmpty else { print("Choisis d'abord un dossier de sons (menu MusicLab)."); return }
            try executeCommand("tracks", [])
            for (index, name) in session.sampleFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let trackChoice = promptLine("Pour quel instrument: "), !trackChoice.isEmpty else { return }
            guard let sampleChoice = promptLine("Quel son (numero ou nom): "), !sampleChoice.isEmpty else { return }
            try executeCommand("track", [trackChoice, "instrument", sampleChoice])
        },
    ]),
    MenuCategory(mnemonic: "M", title: "Morceaux", items: [
        MenuItem(label: "Ecouter le morceau") { try executeCommand("play", []) },
        MenuItem(label: "Voir le morceau (structure et instruments)") { try executeCommand("show-piece", []) },
        MenuItem.separator,
        MenuItem(label: "Choisir le son de lecture du morceau...") {
            guard !session.sampleFiles.isEmpty else { print("Choisis d'abord un dossier de sons (menu MusicLab)."); return }
            for (index, name) in session.sampleFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Charger quel son (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-sample", [choice])
        },
        MenuItem(label: "Choisir le son d'une piste...") {
            printPieceDetail()
            guard let sectionText = promptLine("Quelle section (numero): "), !sectionText.isEmpty else { return }
            guard let trackText = promptLine("Quelle piste (numero): "), !trackText.isEmpty else { return }
            if session.sampleFiles.isEmpty { print("(Astuce: choisis d'abord un dossier de sons, menu MusicLab.)") }
            for (index, name) in session.sampleFiles.enumerated() { print("  \(index + 1). \(name)") }
            let instrumentText = promptLine("Quel son (numero, nom, ou vide pour le son par defaut): ") ?? ""
            try executeCommand("set-track-instrument", [sectionText, trackText, instrumentText])
        },
        MenuItem(label: "Choisir le son des accords d'une section...") {
            printPieceDetail()
            guard let sectionText = promptLine("Quelle section (numero): "), !sectionText.isEmpty else { return }
            if session.sampleFiles.isEmpty { print("(Astuce: choisis d'abord un dossier de sons, menu MusicLab.)") }
            for (index, name) in session.sampleFiles.enumerated() { print("  \(index + 1). \(name)") }
            let instrumentText = promptLine("Quel son (numero, nom, ou vide pour le son par defaut): ") ?? ""
            try executeCommand("set-chord-instrument", [sectionText, instrumentText])
        },
        MenuItem.separator,
        MenuItem(label: "Charger demo") { try executeCommand("load-demo", []) },
        MenuItem(label: "Charger morceau...") {
            guard !session.pieceFiles.isEmpty else { print("Choisis d'abord un dossier de morceaux (menu MusicLab)."); return }
            for (index, name) in session.pieceFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Charger quel morceau (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-piece", [choice])
        },
        MenuItem(label: "Sauvegarder le morceau") { try executeCommand("save", []) },
        MenuItem(label: "Sauvegarder le morceau sous...") {
            guard let name = promptLine("Nom de sauvegarde: "), !name.isEmpty else { return }
            try executeCommand("save-as", [name])
        },
        MenuItem.separator,
        MenuItem.header("Assistant IA"),
    ]),
    MenuCategory(mnemonic: "E", title: "Enregistrement", items: [
        MenuItem(label: "Demarrer un enregistrement...") {
            try executeCommand("tracks", [])
            let idsText = promptLine("Pistes a enregistrer (separees par un espace, vide = toutes celles en ecoute): ") ?? ""
            try executeCommand("record", ["start"] + idsText.split(separator: " ").map(String.init))
        },
        MenuItem(label: "Arreter l'enregistrement") { try executeCommand("record", ["stop"]) },
        MenuItem(label: "Voir l'enregistrement") { try executeCommand("show-soundtrack", []) },
        MenuItem(label: "Jouer l'enregistrement") { try executeCommand("play-soundtrack", []) },
        MenuItem.separator,
        MenuItem(label: "Charger un enregistrement...") {
            guard !session.soundTrackFiles.isEmpty else { print("Choisis d'abord un dossier de soundtracks (menu MusicLab)."); return }
            for (index, name) in session.soundTrackFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Charger quel enregistrement (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-soundtrack", [choice])
        },
        MenuItem(label: "Sauvegarder l'enregistrement") { try executeCommand("save-soundtrack", []) },
        MenuItem(label: "Sauvegarder l'enregistrement sous...") {
            guard let name = promptLine("Nom de sauvegarde: "), !name.isEmpty else { return }
            try executeCommand("save-soundtrack-as", [name])
        },
        MenuItem.separator,
        MenuItem(label: "Composer un morceau a partir de l'enregistrement...") {
            let titleText = promptLine("Nom du morceau (vide = laisser l'IA choisir): ") ?? ""
            let countText = promptLine("Combien de candidats (defaut 1): ") ?? ""
            var cmdArgs = [countText.isEmpty ? "1" : countText]
            if !titleText.isEmpty { cmdArgs.append(titleText) }
            try executeCommand("compose-piece-from-soundtrack", cmdArgs)
        },
        MenuItem.separator,
        MenuItem(label: "Voir le prompt de composition...") { try executeCommand("show-soundtrack-prompt", []) },
        MenuItem(label: "Sauvegarder le prompt de composition...") {
            guard let name = promptLine("Nom de sauvegarde du prompt: "), !name.isEmpty else { return }
            try executeCommand("save-soundtrack-prompt", [name])
        },
        MenuItem(label: "Charger un prompt de composition...") {
            guard !session.soundTrackPromptFiles.isEmpty else { print("Choisis d'abord un dossier de prompts (menu MusicLab)."); return }
            for (index, name) in session.soundTrackPromptFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Charger quel prompt (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-soundtrack-prompt", [choice])
        },
        MenuItem(label: "Revenir au prompt de composition par defaut") { try executeCommand("reset-soundtrack-prompt", []) },
    ]),
    MenuCategory(mnemonic: "C", title: "Composition", items: [
        MenuItem(label: "Decrire le morceau...") {
            guard let title = promptLine("Titre du morceau: "), !title.isEmpty else { return }
            session.setCompositionTitle(title)
            print("Colle la description du morceau (termine par une ligne vide) :")
            var lines: [String] = []
            while let textLine = readLine(), !textLine.isEmpty { lines.append(textLine) }
            session.setSourceText(lines.joined(separator: "\n"))
            let indicationsText = promptLine("Indications de style, optionnel (ex: romantique, mode mineur — vide pour aucune): ") ?? ""
            session.setAdditionalCompositionInstructions(indicationsText.isEmpty ? nil : indicationsText)
            try executeCommand("compose", [title])
        },
        MenuItem(label: "Composer a partir de la description") { try executeCommand("compose", []) },
        MenuItem(label: "Voir la description") { try executeCommand("show-description", []) },
        MenuItem.separator,
        MenuItem(label: "Voir le prompt de composition...") { try executeCommand("show-text-prompt", []) },
        MenuItem(label: "Sauvegarder le prompt de composition...") {
            guard let name = promptLine("Nom de sauvegarde du prompt: "), !name.isEmpty else { return }
            try executeCommand("save-text-prompt", [name])
        },
        MenuItem(label: "Charger un prompt de composition...") {
            guard !session.textPromptFiles.isEmpty else { print("Choisis d'abord un dossier de prompts (menu MusicLab)."); return }
            for (index, name) in session.textPromptFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Charger quel prompt (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-text-prompt", [choice])
        },
        MenuItem(label: "Revenir au prompt de composition par defaut") { try executeCommand("reset-text-prompt", []) },
    ]),
    MenuCategory(mnemonic: "J", title: "Jam Session", items: [
        MenuItem(label: "Demarrer une jam session...") {
            let portText = promptLine("Port (defaut 7777): ") ?? ""
            try executeCommand("server", [portText.isEmpty ? "7777" : portText])
        },
        MenuItem(label: "Arreter la jam session") { try executeCommand("stop-server", []) },
        MenuItem(label: "Rejoindre une jam session...") {
            let host = promptLine("Serveur (defaut localhost): ") ?? ""
            let portText = promptLine("Port (defaut 7777): ") ?? ""
            try executeCommand("client", [host.isEmpty ? "localhost" : host, portText.isEmpty ? "7777" : portText])
        },
        MenuItem(label: "Trouver une jam session...") { try executeCommand("discover", []) },
        MenuItem(label: "Quitter la jam session") { try executeCommand("disconnect", []) },
    ]),
]

/// Splits a typed command line into tokens on whitespace, except inside a `"..."` quoted
/// span — needed for filenames with spaces (a real soundfont/piece file can be named e.g.
/// "The Fox and The Crow General MIDI SoundFont Ultimate.sf2"), which a plain
/// `split(separator: " ")` would tear into several bogus tokens. Not a full shell-style
/// parser (no escaping a literal quote) — this app only ever needs one quoted filename per
/// command, not arbitrary shell syntax.
func tokenizeCommandLine(_ line: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var insideQuotes = false
    for character in line {
        if character == "\"" {
            insideQuotes.toggle()
        } else if character == " " && !insideQuotes {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        } else {
            current.append(character)
        }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}

print("Music Improv Assistant — mode Command")
print("Tape 'help' pour la liste des commandes.")
drainLog() // flush the "Audio engine started." line logged by session.start() above
printPrompt()
while let line = readLine() {
    let parts = tokenizeCommandLine(line)
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
