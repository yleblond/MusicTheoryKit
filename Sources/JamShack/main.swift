import Foundation
import AppCore
import MusicTheoryKit
import PieceModel

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
// still resolves correctly no matter where `swift run` is invoked from — `Sources/JamShack/
// main.swift` is 4 levels below the project root that holds `Pieces`/`SoundFonts`/
// `LLMConnections` as siblings of `MusicTheoryKit/`. `try?`: silently skipped if a folder
// doesn't exist (e.g. a different checkout) rather than failing startup.
let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // JamShack
    .deletingLastPathComponent() // Sources
    .deletingLastPathComponent() // MusicTheoryKit
    .deletingLastPathComponent() // Music
try? session.listPieceFiles(in: projectRoot.appendingPathComponent("Pieces").path)
try? session.listSampleFiles(in: projectRoot.appendingPathComponent("SoundFonts").path)
try? session.listLLMConnections(in: projectRoot.appendingPathComponent("LLMConnections").path)
try? FileManager.default.createDirectory(at: projectRoot.appendingPathComponent("SoundTracks"), withIntermediateDirectories: true)
try? session.listSoundTrackFiles(in: projectRoot.appendingPathComponent("SoundTracks").path)
try? FileManager.default.createDirectory(at: projectRoot.appendingPathComponent("Sequences"), withIntermediateDirectories: true)
try? session.listGuideFiles(in: projectRoot.appendingPathComponent("Sequences").path)
try? FileManager.default.createDirectory(at: projectRoot.appendingPathComponent("Scenes"), withIntermediateDirectories: true)
try? session.listSceneFiles(in: projectRoot.appendingPathComponent("Scenes").path)
try? session.setPromptsFolder(projectRoot.appendingPathComponent("Composition IA").path) // creates its fixed subfolders if absent
try? session.loadOrCreateColorPalettes(fromJSONFile: projectRoot.appendingPathComponent("palettes.json").path)

// If any scenes are already sitting in the default folder, offer to load one right away —
// picking up a known instrument setup (e.g. "piano solo") shouldn't require knowing the
// `use-scene`/menu path exists on a first launch. Purely optional: leaving the prompt blank
// (or any answer that doesn't resolve) just moves on to the normal REPL with nothing loaded.
if !session.sceneFiles.isEmpty {
    print("\nScenes disponibles dans \(session.sceneFolder ?? "?"):")
    for (index, name) in session.sceneFiles.enumerated() { print("  \(index + 1). \(name)") }
    if let choice = promptLine("Charger quelle scene au demarrage ? (numero, ou vide pour aucune): "), !choice.isEmpty {
        do {
            if let index = Int(choice) {
                try session.loadScene(atIndex: index - 1)
            } else {
                try session.loadScene(named: choice)
            }
        } catch {
            print("Erreur: \(error)")
        }
    }
}

func printHelp() {
    print("""
    Commandes (par categorie) :

    (un nom de fichier contenant des espaces doit etre entoure de guillemets, ex: use-sample "The Fox and The Crow General MIDI SoundFont Ultimate.sf2")

    General
      help                       affiche cette aide
      status                     affiche l'etat courant (piece, pistes actives, accord/mode)
      run                        ecran fixe: activite musicale en direct (claviers, accords) — Ctrl+C pour revenir
      config                     ecran fixe: configuration active et detail du morceau — Ctrl+C pour revenir
      guide                      ecran fixe: sequence de modes a parcourir en jouant (fleches gauche/droite) — Ctrl+C pour revenir
      web-console [port]         demarre la console web (miroir de 'run' dans un navigateur, defaut port 8080)
      web-console stop           arrete la console web
      virtual-keyboard [port]    demarre le clavier virtuel (piano interactif souris/tactile/clavier dans un navigateur, piste 'clavier-web', defaut port 8081)
      virtual-keyboard stop      arrete le clavier virtuel
      use-palette <n ou nom>     choisit la palette de couleur active (console web + clavier virtuel, propre a cette instance)
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

    Scene (lecture du morceau)
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
      prompts <dossier>          pointe le dossier de composition IA (sous-dossiers crees si absents), liste chacun
      use-description <n|nom>   charge une description (remplace titre/texte/indications en cours)
      save-description-as <nom> sauvegarde la description en cours sous un nouveau nom
      save-description          resauvegarde la description en cours
      show-text-framing / show-soundtrack-framing  affiche la phrase de cadrage active (avant le schema JSON)
      set-text-framing / set-soundtrack-framing     colle une nouvelle phrase de cadrage, termine par une ligne vide
      save-text-framing <nom> / save-soundtrack-framing <nom>  sauvegarde la phrase de cadrage active
      use-text-framing <n|nom> / use-soundtrack-framing <n|nom>  charge une phrase de cadrage sauvegardee
      reset-text-framing / reset-soundtrack-framing  revient a la phrase de cadrage par defaut
      show-soundtrack-instructions      affiche les indications de style actives (soundtrack)
      set-soundtrack-instructions [texte]  indications de style pour la soundtrack (vide efface)
      save-soundtrack-instructions <nom>   sauvegarde les indications de style actives
      use-soundtrack-instructions <n|nom>  charge des indications de style sauvegardees
      reset-soundtrack-instructions        efface les indications de style (aucune)
      show-text-prompt / show-soundtrack-prompt  affiche le prompt complet qui serait envoye maintenant
      export-text-prompt <nom> / export-soundtrack-prompt <nom>  exporte le prompt complet (jamais recharge)

    Guide Musicaux (sequence de modes a parcourir en jouant)
      guide-new <titre>          demarre une sequence de guide vierge
      guide-add-mode <tonique> <id-gamme>  ajoute une etape (ex: guide-add-mode D dorian)
      guides <dossier>           liste les fichiers .json (sequences de guide) du dossier
      use-guide <n ou nom>       charge une sequence (numero de la liste ou nom de fichier)
      save-guide                 resauvegarde la sequence courante
      save-guide-as <nom>        sauvegarde sous un nouveau nom
      guide-start [n]            demarre le guide a l'etape n (1-based, defaut 1)
      guide-stop                 arrete le guide

    Session collaborative (reseau)
      pseudo [nom]               affiche/change le pseudo affiche aux autres participants (defaut "player")
      server [port]              demarre un serveur collaboratif (defaut port 7777)
      stop-server                arrete le serveur
      client [host] [port]       rejoint un serveur (defaut localhost:7777)
      discover                   recherche des serveurs sur le reseau local et propose de rejoindre
      disconnect                 se deconnecte du serveur
    """)
}

/// Every line describing the current piece's structure and instruments — shared by
/// `show-piece` (plain `print`) and the `config` screen (redrawn-in-place `line`), so the
/// two never drift apart.
func pieceDetailLines() -> [String] {
    guard let piece = session.piece else {
        return [TextStyle.placeholder("(aucun morceau charge)")]
    }
    var lines: [String] = []
    let keyName = ScaleLibrary.byID(piece.key.scaleID)?.popularName ?? piece.key.scaleID
    lines.append(TextStyle.heading(piece.title) + (piece.composer.map { " — \($0)" } ?? ""))
    lines.append(TextStyle.field("Tempo", "\(Int(piece.tempoBPM)) BPM"))
    lines.append(TextStyle.field("Tonalite", "\(PitchClass(piece.key.tonic).name()) \(keyName)"))
    if piece.sections.isEmpty {
        lines.append(TextStyle.placeholder("(pas encore de section)"))
    }
    for (sectionIndex, section) in piece.sections.enumerated() {
        let modeName = ScaleLibrary.byID(section.mode.scaleID)?.popularName ?? section.mode.scaleID
        lines.append("")
        lines.append(TextStyle.heading("Section \(sectionIndex + 1): \(section.name)") + " (\(section.lengthInMeasures) mesures, \(PitchClass(section.mode.tonic).name()) \(modeName))")
        let chordInstrumentText = section.chordInstrument.map { "'\($0)'" } ?? "par defaut"
        lines.append("  accords (instrument \(chordInstrumentText)):")
        for chordEvent in section.chordProgression.sorted(by: { $0.measure < $1.measure }) {
            let name = "\(PitchClass(chordEvent.chord.root).name())\(chordEvent.chord.chordTemplateID)"
            lines.append("    mesure \(chordEvent.measure): \(name)")
        }
        for (trackIndex, track) in section.tracks.enumerated() where !track.melodyEvents.isEmpty {
            let instrumentText = track.instrument.isEmpty ? "par defaut" : "'\(track.instrument)'"
            lines.append("  piste \(trackIndex + 1) '\(track.name)' (instrument \(instrumentText)): \(track.melodyEvents.count) notes")
        }
    }
    return lines
}

func printPieceDetail() {
    for row in pieceDetailLines() { print(row) }
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
/// "clavier" (computer keyboard), "clavier-web:<clientID>" (one connected browser's virtual
/// keyboard, see `ImprovSession.startVirtualKeyboard`/`ensureWebKeyboardTrack` — copy/paste
/// the exact id shown by `tracks`, its `clientID` is a UUID not meant to be typed from
/// scratch, same convention as `remote:` just below), "micro" (microphone),
/// "remote:<clientID>@<trackID>" (a participant's own track in a collaborative session —
/// copy/paste the exact id shown by `tracks`, its `clientID` is a UUID not meant to be typed
/// from scratch).
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
        if text.hasPrefix("clavier-web:") {
            let clientID = String(text.dropFirst("clavier-web:".count))
            guard !clientID.isEmpty else { return nil }
            return .webKeyboard(clientID: clientID)
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

/// Parses a note name ("C", "F#", "Bb"...) into a `PitchClass` for `guide-add-mode` — a
/// small local parser rather than reusing `LLMEngine`'s own note-name parser, to avoid
/// wiring up a cross-module dependency for a need this localized.
func parseTonicPitchClass(_ text: String) -> PitchClass? {
    let naturals: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
    guard let letter = text.first, let base = naturals[Character(letter.uppercased())] else { return nil }
    switch text.dropFirst() {
    case "": return PitchClass(base)
    case "#", "♯": return PitchClass(base + 1)
    case "b", "♭": return PitchClass(base - 1)
    default: return nil
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
    case .webKeyboard(let clientID): return "clavier-web:\(clientID)"
    case .microphone: return "micro"
    case .remote(let clientID, let trackID): return "remote:\(clientID)@\(trackID)"
    }
}

/// " — Bob" for a `.remote` track whose owner sent a pseudo, "" otherwise (including every
/// local track — no need to label your own tracks with your own name). Shared by every place
/// that shows a track heading, so "qui joue quoi" reads the same everywhere.
func ownerSuffix(_ track: TrackInfo) -> String {
    track.ownerName.map { " — \($0)" } ?? ""
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

/// "(inactive)" / "http://localhost:<port>" — shared by `status`/`config`.
func webConsoleStatusText() -> String {
    session.webConsolePort.map { "http://localhost:\($0)" } ?? TextStyle.placeholder("(inactive)")
}

func virtualKeyboardStatusText() -> String {
    session.virtualKeyboardPort.map { "http://localhost:\($0)" } ?? TextStyle.placeholder("(inactif)")
}

/// One line per track — shared by the `tracks` command and the Source/Reseau menus'
/// prompts, so picking a track id to act on always shows the same up-to-date list first.
func printTracks() {
    print(TextStyle.field("Reseau", networkRoleText()))
    print(TextStyle.field("Mode MIDI", session.midiFusionMode == .merged ? "fusionne" : "individuel"))
    for track in session.tracks {
        var line = "  [\(trackIDText(track.id))] \(track.label)\(ownerSuffix(track)) — ecoute: \(TextStyle.flag(track.isListening))"
        if track.canHaveSound {
            line += ", son: \(TextStyle.flag(track.soundEnabled))"
            if let instrument = track.instrumentName { line += " (\(instrument))" }
        }
        print(line)
    }
}

/// A numbered version of `printTracks`'s per-track lines, for menu actions that need the
/// user to *pick* a track rather than just see its state — same "numero ou nom" convention as
/// `sampleFiles`/`pieceFiles`/`llmConnections` pickers elsewhere, via `resolvedTrackIDText`.
func printNumberedTracks() {
    for (index, track) in session.tracks.enumerated() {
        print("  \(index + 1). [\(trackIDText(track.id))] \(track.label)\(ownerSuffix(track))")
    }
}

/// The 7 classic "Major Modes" (family 1), in degree order — the common case for a guide
/// step, and the only family the circle-of-fifths wheel understands (see
/// `CircleOfFifths.parentTonic(for:)`). Printed as a numbered pick-list before prompting for
/// a scale id, so typing a bare number meant for this list (instead of the id itself) still
/// resolves — that exact mistake used to silently save an unresolvable guide step (see
/// `resolvedScaleID`).
func printNumberedScales() {
    for (index, scale) in ScaleLibrary.scales(inFamily: 1).enumerated() {
        print("  \(index + 1). \(scale.id) (\(scale.popularName))")
    }
}

/// Resolves a "<n|id>" argument against the family-1 pick-list `printNumberedScales()` just
/// printed — a number picks by 1-based position, anything else (e.g. a family-2+ id like
/// "melodic_minor", or a correctly-typed family-1 id) is passed through literally.
func resolvedScaleID(_ text: String) -> String {
    let familyOne = ScaleLibrary.scales(inFamily: 1)
    if let index = Int(text), familyOne.indices.contains(index - 1) {
        return familyOne[index - 1].id
    }
    return text
}

/// Resolves a "<n|id>" argument against `session.tracks` — a number picks by 1-based
/// position (mirrors `resolvedSampleName`'s convention), anything else is passed through
/// literally so a typed raw id ("midi:2", "remote:...") still works untouched.
func resolvedTrackIDText(_ text: String) -> String {
    if let index = Int(text), session.tracks.indices.contains(index - 1) {
        return trackIDText(session.tracks[index - 1].id)
    }
    return text
}

/// Prompts to pick a sample from `session.sampleFiles` and load it onto `resolvedTrackID` —
/// shared by "Choisir un son pour un instrument..." and the post-activation prompt in
/// "Activer un instrument...", so both stay in sync.
func promptChooseSoundForTrack(_ resolvedTrackID: String) throws {
    guard !session.sampleFiles.isEmpty else { print("Choisis d'abord un dossier de sons (menu JamShack)."); return }
    for (index, name) in session.sampleFiles.enumerated() { print("  \(index + 1). \(name)") }
    guard let sampleChoice = promptLine("Quel son (numero ou nom): "), !sampleChoice.isEmpty else { return }
    try executeCommand("track", [resolvedTrackID, "instrument", sampleChoice])
}

func printStatus() {
    print(TextStyle.field("Piece", session.piece.map { $0.title } ?? TextStyle.placeholder("(aucun)")))
    print(TextStyle.field("Fichier", session.currentPieceFilePath ?? TextStyle.placeholder("(jamais sauvegarde)")))
    print(TextStyle.field("Playing", TextStyle.flag(session.isPlaying)))
    print(TextStyle.field("Recording", TextStyle.flag(session.isRecording)))
    print(TextStyle.field("Soundtrack", session.currentSoundTrack.map { $0.title } ?? TextStyle.placeholder("(aucune)")))
    print(TextStyle.field("Playing (soundtrack)", TextStyle.flag(session.isPlayingSoundTrack)))
    print(TextStyle.field("Console Web", webConsoleStatusText()))
    print(TextStyle.field("Clavier virtuel", virtualKeyboardStatusText()))
    print(TextStyle.field("Palette de couleur", session.activeColorPalette.name))
    print()
    printTracks()
    print()
    for track in session.tracks where track.isListening {
        print(TextStyle.heading("[\(trackIDText(track.id))] \(track.label)\(ownerSuffix(track))"))
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

/// Builds a `renderKeyboard(modeMarker:)` closure from a `Mode` — shared by every keyboard
/// that draws a role-line (per-track, playback, and the `.guide` screen), so "which color
/// and degree number goes with this pitch class" is computed in exactly one place. `nil`
/// mode draws no markers at all (same as `renderKeyboard`'s own default).
///
/// `KeyboardColor.degreeColors` only has 7 entries — plenty for every 7-note scale (the
/// overwhelming majority: all of families 1-4), but some recognized scales have more (the
/// "Diminished Modes" family is 8 notes) or fewer (whole tone/augmented are 6). Degrees past
/// the 7th used to index `degreeColors` out of bounds and crash the whole process the moment
/// a track's live recognition landed on one of those scales mid-performance — now they just
/// draw no marker for that note instead (still correct for degrees 1-7, silently skipped
/// beyond that) rather than taking the app down.
func degreeMarker(for mode: Mode?) -> (Int) -> (degree: Int, color: String)? {
    guard let mode else { return { _ in nil } }
    let ordered = mode.pitchClasses.map(\.value)
    return { semitone in
        guard let index = ordered.firstIndex(of: semitone), KeyboardColor.degreeColors.indices.contains(index) else { return nil }
        return (index + 1, KeyboardColor.degreeColors[index])
    }
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
    let trackMode = topScale.map { Mode(tonic: $0.0.tonic, scale: $0.1) }

    return renderKeyboard(
        startMIDI: 48,
        octaveCount: 3,
        blackZoneRows: 2,
        whiteZoneRows: 1,
        modeMarker: degreeMarker(for: trackMode),
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
/// instead of one `print` per line — fewer separate writes per redraw (10/s) means less
/// chance of a terminal visibly painting a frame in more than one pass. Safe to do with a
/// plain buffered `print` (not a raw `write`) now that stdin/stdout can no longer end up
/// sharing a non-blocking file descriptor — see `readKey`'s doc comment in `Menu.swift` for
/// the real, deeper bug that turned out to be behind both the original flicker report and a
/// later crash.
/// The three screens `console`-style redraw-in-place mode can show — one shared menu
/// bar/dropdown/redraw mechanism (`runConsoleScreen`/`renderConsoleFrame`), different body
/// content per mode, so each screen stays focused and short rather than one ever-growing
/// dashboard. `.command` isn't rendered by this function at all — it's the plain REPL
/// prompt, the state you're in whenever `console`-mode isn't active. `CaseIterable` backs
/// Tab's 3-way cycle in `runConsoleScreen`.
enum ConsoleScreenMode: CaseIterable {
    /// Live musical activity only: the last MIDI event, every listening track's own
    /// keyboard/chord/mode, and a playback keyboard while a `Piece` or `SoundTrack` plays —
    /// nothing about setup/config, so this screen stays minimal while actually playing.
    case run
    /// Session setup/state and the active piece's full structure — nothing that updates
    /// note-by-note, so this screen stays calm to read even while `run` is busy elsewhere.
    case config
    /// A user-driven mode sequence (see `ImprovSession.startGuide`/`advanceGuideStep`):
    /// the sequence, the current step's neighbors on the circle of fifths, and a role-line
    /// keyboard for the current step's mode — independent of any track's own recognized
    /// mode, which keeps showing on `.run` unaffected.
    case guide

    var label: String {
        switch self {
        case .run: return "Run"
        case .config: return "Config"
        case .guide: return "Guide Musical"
        }
    }
}

/// A persistent tab-bar-style indicator of which of the 3 screens is currently showing —
/// always rendered (menu open or not), so it stays visible regardless of anything else
/// changing on screen. Deliberately styled nothing like `renderMenuBar` (no underlined
/// mnemonic, no reverse-video-on-open) — a bracketed bold-yellow active tab against a dim
/// "Ecran:" label reads as a status indicator, not a 4th menu to click into.
func renderScreenTabs(_ mode: ConsoleScreenMode) -> String {
    let tabs = ConsoleScreenMode.allCases.map { candidate -> String in
        candidate == mode ? "\u{1B}[1;33m[\(candidate.label)]\u{1B}[0m" : "\u{1B}[2m\(candidate.label)\u{1B}[0m"
    }.joined(separator: "  ")
    return "\u{1B}[2mEcran:\u{1B}[0m  \(tabs)"
}

func renderConsoleFrame(mode: ConsoleScreenMode) {
    var output = "\u{1B}[H"
    func line(_ text: String = "") {
        output += "\u{1B}[K" + text + "\n"
    }
    line(renderScreenTabs(mode))
    line(renderMenuBar(menuCategories))
    if let openIndex = openMenuIndex {
        for row in renderDropdown(menuCategories[openIndex]) { line(row) }
    } else {
        // Only shown while no menu is open — once a dropdown is on screen the controls are
        // self-evident, and the hint would just be one more thing to visually parse next to it.
        line(TextStyle.placeholder("(lettre: ouvre un menu, fleches, Entree, Echap, Tab: change d'ecran, q: quitte l'ecran)"))
    }
    line()

    switch mode {
    case .config:
        line(TextStyle.field("Piece", session.piece.map { $0.title } ?? TextStyle.placeholder("(aucun)")))
        line(TextStyle.field("Fichier", session.currentPieceFilePath ?? TextStyle.placeholder("(jamais sauvegarde)")))
        line(TextStyle.field("Playing", TextStyle.flag(session.isPlaying)))
        line(TextStyle.field("Recording", TextStyle.flag(session.isRecording)))
        line(TextStyle.field("Soundtrack", session.currentSoundTrack.map { $0.title } ?? TextStyle.placeholder("(aucune)")))
        line(TextStyle.field("Reseau", networkRoleText()))
        line(TextStyle.field("Console Web", webConsoleStatusText()))
        line(TextStyle.field("Clavier virtuel", virtualKeyboardStatusText()))
        line(TextStyle.field("Palette de couleur", session.activeColorPalette.name))
        line(TextStyle.field("Mode MIDI", session.midiFusionMode == .merged ? "fusionne" : "individuel"))
        line()
        line(TextStyle.heading("Detail du morceau actif:"))
        for row in pieceDetailLines() { line(row) }

    case .run:
        let lastEventText = session.lastMIDIEvent.map { "\($0.kind == .noteOn ? "on " : "off")pitch=\($0.pitch) vel=\($0.velocity)" } ?? "-"
        line(TextStyle.field("Dernier evt", lastEventText))

        let listeningTracks = session.tracks.filter { $0.isListening }
        if listeningTracks.isEmpty {
            line()
            line(TextStyle.placeholder("(aucune piste en ecoute — menu Scene pour en activer une)"))
        }
        for track in listeningTracks {
            line()
            line(TextStyle.heading("[\(trackIDText(track.id))] \(track.label)\(ownerSuffix(track))"))
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
            let playbackMode: Mode? = currentSegment.flatMap { segment in
                ScaleLibrary.byID(segment.mode.scaleID).map { scale in Mode(tonic: PitchClass(segment.mode.tonic), scale: scale) }
            }
            let playbackHeld = session.playbackHeldPitches

            line()
            line(TextStyle.heading("Clavier compose, en cours de jeu (C3-B5):"))
            for row in renderKeyboard(
                startMIDI: 48,
                octaveCount: 3,
                blackZoneRows: 2,
                whiteZoneRows: 1,
                modeMarker: degreeMarker(for: playbackMode),
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
                startMIDI: 48, octaveCount: 3, blackZoneRows: 2, whiteZoneRows: 1,
                colorFor: { pitch in soundTrackHeld.contains(pitch) ? KeyboardColor.heldNoChord : nil }
            ) { line(row) }
        }

    case .guide:
        guard let currentGuide = session.currentGuide else {
            line(TextStyle.placeholder("(aucune sequence de guide — menu Guide Musicaux)"))
            break
        }
        line(TextStyle.heading("Sequence: \(currentGuide.title)"))
        if currentGuide.steps.isEmpty {
            line(TextStyle.placeholder("(sequence vide — menu Guide Musicaux > Ajouter un mode au guide musical)"))
        } else {
            let items = currentGuide.steps.enumerated().map { index, reference -> (display: String, plainWidth: Int) in
                let name = reference.resolve()?.displayName ?? "?"
                if index == session.currentGuideStepIndex {
                    return ("\(KeyboardColor.chordRoot)[\(name)]\(KeyboardColor.reset)", name.count + 2)
                }
                return (name, name.count)
            }
            for wrapped in wrapItems(items) { line(wrapped) }
        }
        line()
        guard let guideMode = session.currentGuideStepMode() else {
            // Distinguish "not started yet" from "started, but this step's mode reference
            // doesn't resolve" (shouldn't happen for a step added via `addGuideStep` since
            // it now validates up front, but a hand-edited or older save file could still
            // have one) — the two used to show the same misleading "not started" message.
            if session.currentGuideStepIndex != nil {
                line(TextStyle.placeholder("(l'etape courante ne resout pas — tonique/gamme invalide dans le fichier)"))
            } else {
                line(TextStyle.placeholder("(guide non demarre — barre d'espace, ou menu Guide Musicaux > Demarrer le guide musical)"))
            }
            break
        }
        if let parentTonic = CircleOfFifths.parentTonic(for: guideMode) {
            let wheel = CircleOfFifths.wheel(tonic: parentTonic)
            // Ordered by "brightness" (Lydian...Locrian), not by the wheel's physical fifths
            // order — the two happen to coincide for 5 of the 7 modes, but wrapping the
            // physical array would make Lydian and Locrian (the two extremes, not actually
            // adjacent) look like each other's neighbor.
            let brightnessOffsets = [5, 0, 7, 2, 9, 4, 11] // Lydian,Ionian,Mixolydian,Dorian,Aeolian,Phrygian,Locrian
            let orderedColumns = brightnessOffsets.map { offset in
                wheel.columns.first { ($0.pitchClass.value - parentTonic.value + 12) % 12 == offset }!
            }
            let activeIndex = orderedColumns.firstIndex { $0.pitchClass == guideMode.tonic } ?? 0
            let previous = activeIndex > 0 ? orderedColumns[activeIndex - 1].modeName : nil
            let next = activeIndex < orderedColumns.count - 1 ? orderedColumns[activeIndex + 1].modeName : nil
            line("\u{25C2} \(previous ?? "—") — [\(orderedColumns[activeIndex].modeName ?? "?")] — \(next ?? "—") \u{25B8}")
        } else {
            line(TextStyle.placeholder("(roue non disponible pour cette famille de gamme)"))
        }
        line()
        line(TextStyle.heading("Clavier (fleches gauche/droite: etape precedente/suivante):"))
        let guideHeldPitches = Set(session.tracks.filter(\.isListening).flatMap(\.heldPitches))
        for row in renderKeyboard(
            startMIDI: 48, octaveCount: 3, blackZoneRows: 2, whiteZoneRows: 1,
            modeMarker: degreeMarker(for: guideMode),
            colorFor: { pitch in guideHeldPitches.contains(pitch) ? KeyboardColor.heldNoChord : nil }
        ) { line(row) }
    }

    output += "\u{1B}[J" // erase any leftover lines below from a previous, taller frame
    print(output, terminator: "") // one write for the whole frame instead of one per line
}

/// Takes over the terminal with a fixed, redrawn-in-place status screen until the user
/// hits Ctrl+C — a `DispatchSourceSignal` catches SIGINT asynchronously (safe to act on,
/// unlike a raw C signal handler) so the redraw loop can exit cleanly instead of the
/// whole process dying.
func runConsoleScreen(mode initialMode: ConsoleScreenMode) {
    var mode = initialMode
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
    while !consoleShouldStop {
        if let key = readKey() {
            switch key {
            case .tab:
                // Cycle through the three screens (.run -> .config -> .guide -> .run) without
                // going back through Command — deliberately doesn't touch `openMenuIndex`: an
                // open dropdown is the same shared menu system in every mode, so there's no
                // reason to close it just because the content area underneath switched.
                let allModes = ConsoleScreenMode.allCases
                let nextIndex = (allModes.firstIndex(of: mode)! + 1) % allModes.count
                mode = allModes[nextIndex]
            case .left where mode == .guide && openMenuIndex == nil:
                session.advanceGuideStep(by: -1)
            case .right where mode == .guide && openMenuIndex == nil:
                session.advanceGuideStep(by: 1)
            case .char(" ") where mode == .guide && openMenuIndex == nil && !computerKeyboardSourceActive:
                if session.currentGuideStepIndex != nil {
                    session.stopGuide()
                } else {
                    try? session.startGuide()
                }
            case .char("q") where !computerKeyboardSourceActive:
                // A calmer way out than Ctrl+C — same effect as the SIGINT handler below
                // (just sets the same flag), kept as a fallback rather than replaced: it's
                // the only way out while "Source clavier" has every letter intercepted for
                // note-playing (this case's own guard steps aside for that, same as every
                // other letter — falls through to the note lookup right below).
                consoleShouldStop = true
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
        renderConsoleFrame(mode: mode)
        Thread.sleep(forTimeInterval: 0.1)
    }
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
    session.stopWebConsole()
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
    case "pseudo":
        if args.isEmpty {
            print(TextStyle.field("Pseudo", session.localClientName))
        } else {
            session.localClientName = args.joined(separator: " ")
            print(TextStyle.field("Pseudo", session.localClientName))
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
    case "web-console":
        switch args.first {
        case "stop":
            session.stopWebConsole()
        default:
            let port = args.first.flatMap(Int.init) ?? 8080
            try session.startWebConsole(port: port)
        }
    case "virtual-keyboard":
        switch args.first {
        case "stop":
            session.stopVirtualKeyboard()
        default:
            let port = args.first.flatMap(Int.init) ?? 8081
            try session.startVirtualKeyboard(port: port)
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
    case "indications":
        session.setAdditionalCompositionInstructions(args.isEmpty ? nil : args.joined(separator: " "))
    case "title":
        session.setCompositionTitle(args.isEmpty ? nil : args.joined(separator: " "))
    case "show-description":
        printCompositionDescription()
    case "use-description":
        guard let arg = args.first else { print("usage: use-description <numero ou nom de fichier>"); break }
        if let index = Int(arg) {
            try session.loadCompositionDescription(atIndex: index - 1)
        } else {
            try session.loadCompositionDescription(named: arg)
        }
    case "save-description":
        try session.saveCompositionDescription()
    case "save-description-as":
        guard let name = args.first else { print("usage: save-description-as <nom>"); break }
        try session.saveCompositionDescription(as: name)
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
    case "use-palette":
        guard let arg = args.first else { print("usage: use-palette <numero ou nom>"); break }
        if let index = Int(arg) {
            try session.selectColorPalette(atIndex: index - 1)
        } else {
            try session.selectColorPalette(named: arg)
        }
    case "compose":
        try session.composeFromText(title: args.isEmpty ? nil : args.joined(separator: " "))
    case "show-piece":
        printPieceDetail()
    case "prompts":
        guard let folder = args.first else { print("usage: prompts <dossier>"); break }
        try session.setPromptsFolder(folder)
        drainLog() // flush "Dossier de composition IA: ..." before the numbered lists
        print("Descriptions:")
        for (index, name) in session.compositionFiles.enumerated() { print("  \(index + 1). \(name)") }
        print("Indications soundtrack:")
        for (index, name) in session.soundTrackInstructionsFiles.enumerated() { print("  \(index + 1). \(name)") }
        print("Cadrage (texte):")
        for (index, name) in session.textFramingFiles.enumerated() { print("  \(index + 1). \(name)") }
        print("Cadrage (soundtrack):")
        for (index, name) in session.soundTrackFramingFiles.enumerated() { print("  \(index + 1). \(name)") }
    case "show-text-prompt":
        print(try session.currentTextCompositionPrompt())
    case "show-soundtrack-prompt":
        print(try session.currentSoundTrackCompositionPrompt())
    case "export-text-prompt":
        guard let name = args.first else { print("usage: export-text-prompt <nom>"); break }
        try session.exportTextCompositionPrompt(as: name)
    case "export-soundtrack-prompt":
        guard let name = args.first else { print("usage: export-soundtrack-prompt <nom>"); break }
        try session.exportSoundTrackCompositionPrompt(as: name)
    case "show-soundtrack-instructions":
        print(session.currentSoundTrackCompositionInstructions() ?? TextStyle.placeholder("(aucune)"))
    case "set-soundtrack-instructions":
        session.setSoundTrackCompositionInstructions(args.isEmpty ? nil : args.joined(separator: " "))
    case "save-soundtrack-instructions":
        guard let name = args.first else { print("usage: save-soundtrack-instructions <nom>"); break }
        try session.saveSoundTrackCompositionInstructions(as: name)
    case "use-soundtrack-instructions":
        guard let arg = args.first else { print("usage: use-soundtrack-instructions <numero ou nom de fichier>"); break }
        if let index = Int(arg) {
            try session.useSoundTrackCompositionInstructions(atIndex: index - 1)
        } else {
            try session.useSoundTrackCompositionInstructions(named: arg)
        }
    case "reset-soundtrack-instructions":
        session.resetSoundTrackCompositionInstructions()
    case "show-text-framing":
        print(session.currentTextFramingSentence())
    case "show-soundtrack-framing":
        print(session.currentSoundTrackFramingSentence())
    case "set-text-framing":
        print("Colle la phrase de cadrage (termine par une ligne vide) :")
        var lines: [String] = []
        while let textLine = readLine(), !textLine.isEmpty { lines.append(textLine) }
        session.setTextFramingSentence(lines.joined(separator: "\n"))
    case "set-soundtrack-framing":
        print("Colle la phrase de cadrage (termine par une ligne vide) :")
        var lines: [String] = []
        while let textLine = readLine(), !textLine.isEmpty { lines.append(textLine) }
        session.setSoundTrackFramingSentence(lines.joined(separator: "\n"))
    case "save-text-framing":
        guard let name = args.first else { print("usage: save-text-framing <nom>"); break }
        try session.saveTextFramingSentence(as: name)
    case "save-soundtrack-framing":
        guard let name = args.first else { print("usage: save-soundtrack-framing <nom>"); break }
        try session.saveSoundTrackFramingSentence(as: name)
    case "use-text-framing":
        guard let arg = args.first else { print("usage: use-text-framing <numero ou nom de fichier>"); break }
        if let index = Int(arg) {
            try session.useTextFramingSentence(atIndex: index - 1)
        } else {
            try session.useTextFramingSentence(named: arg)
        }
    case "use-soundtrack-framing":
        guard let arg = args.first else { print("usage: use-soundtrack-framing <numero ou nom de fichier>"); break }
        if let index = Int(arg) {
            try session.useSoundTrackFramingSentence(atIndex: index - 1)
        } else {
            try session.useSoundTrackFramingSentence(named: arg)
        }
    case "reset-text-framing":
        session.resetTextFramingSentence()
    case "reset-soundtrack-framing":
        session.resetSoundTrackFramingSentence()
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
    case "run":
        runConsoleScreen(mode: .run)
    case "config":
        runConsoleScreen(mode: .config)
    case "guide":
        runConsoleScreen(mode: .guide)
    case "guides":
        guard let folder = args.first else { print("usage: guides <dossier>"); break }
        try session.listGuideFiles(in: folder)
        drainLog()
        for (index, name) in session.guideFiles.enumerated() { print("  \(index + 1). \(name)") }
    case "guide-new":
        guard let title = args.first else { print("usage: guide-new <titre>"); break }
        session.newGuideSequence(title: title)
    case "guide-add-mode":
        guard args.count >= 2, let tonic = parseTonicPitchClass(args[0]) else {
            print("usage: guide-add-mode <tonique> <id-gamme>"); break
        }
        try session.addGuideStep(ModeReference(tonic: tonic.value, scaleID: args[1]))
    case "use-guide":
        guard let arg = args.first else { print("usage: use-guide <numero ou nom de fichier>"); break }
        if let index = Int(arg) {
            try session.loadGuideSequence(atIndex: index - 1)
        } else {
            try session.loadGuideSequence(named: arg)
        }
    case "save-guide":
        if let path = args.first {
            try session.saveGuideSequence(toJSONFile: path)
        } else {
            try session.saveGuideSequence()
        }
    case "save-guide-as":
        guard let name = args.first else { print("usage: save-guide-as <nom>"); break }
        try session.saveGuideSequence(as: name)
    case "guide-start":
        let index = args.first.flatMap(Int.init).map { $0 - 1 } ?? 0
        try session.startGuide(atStepIndex: index)
    case "guide-stop":
        session.stopGuide()
    case "scenes":
        guard let folder = args.first else { print("usage: scenes <dossier>"); break }
        try session.listSceneFiles(in: folder)
        drainLog()
        for (index, name) in session.sceneFiles.enumerated() { print("  \(index + 1). \(name)") }
    case "use-scene":
        guard let arg = args.first else { print("usage: use-scene <numero ou nom de fichier>"); break }
        if let index = Int(arg) {
            try session.loadScene(atIndex: index - 1)
        } else {
            try session.loadScene(named: arg)
        }
    case "save-scene":
        guard let name = args.first else { print("usage: save-scene <nom>"); break }
        try session.saveScene(title: name, as: name)
    case "quit", "exit":
        stopAllTracks()
        drainLog()
        setRawMode(false) // harmless no-op if we were never in raw mode
        print("\u{1B}[?25h", terminator: "") // ditto for the cursor
        exit(0)
    default:
        print("Commande inconnue: \(command). Tape 'help'.")
    }
}

/// Prompts for a display pseudo before hosting/joining/discovering a Jam Session (shared by
/// the three menu items that do) — leaving it blank keeps whatever `localClientName` already
/// is (the default "player" the first time, or a name set earlier this session/via `pseudo`).
/// Without this, every participant shows up as "player" to everyone else, which is exactly
/// the ambiguity this was added to fix — see the `ownerName` field threaded through
/// `TrackInfo`/`RemoteTrackSnapshot`.
func promptForPseudo() {
    let text = promptLine("Ton pseudo (defaut '\(session.localClientName)'): ") ?? ""
    if !text.isEmpty { session.localClientName = text }
}

/// The `console` screen's dropdown menus — each item just calls `executeCommand`, prompting
/// first for a folder/name/choice where needed. Defined after `executeCommand` (which they
/// all call) but before it's used in `runConsoleScreen`.
nonisolated(unsafe) let menuCategories: [MenuCategory] = [
    // Mnemonic "S" (not the first letter) to avoid colliding with "Jam Session"'s "J" — same
    // trick already used for "IA" vs "Instrument", see renderMenuBar's doc comment.
    MenuCategory(mnemonic: "S", title: "JamShack", items: [
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
        MenuItem(label: "Choisir dossier de guides musicaux...") {
            guard let folder = promptLine("Dossier de guides musicaux: "), !folder.isEmpty else { return }
            try executeCommand("guides", [folder])
        },
        MenuItem(label: "Choisir dossier de scenes...") {
            guard let folder = promptLine("Dossier de scenes: "), !folder.isEmpty else { return }
            try executeCommand("scenes", [folder])
        },
        MenuItem(label: "Choisir dossier de connexions LLM...") {
            guard let folder = promptLine("Dossier de connexions LLM: "), !folder.isEmpty else { return }
            try executeCommand("llm-connections", [folder])
        },
        MenuItem(label: "Choisir dossier de composition IA...") {
            guard let folder = promptLine("Dossier de composition IA (sous-dossiers crees si absents): "), !folder.isEmpty else { return }
            try executeCommand("prompts", [folder])
        },
        MenuItem.separator,
        MenuItem(label: "Choisir une connexion LLM...") {
            guard !session.llmConnections.isEmpty else { print("Choisis d'abord un dossier de connexions LLM."); return }
            for (index, name) in session.llmConnections.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Utiliser quelle connexion (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-llm", [choice])
        },
        MenuItem.separator,
        MenuItem(label: "Choisir palette de couleur...") {
            for (index, palette) in session.colorPalettes.enumerated() {
                let marker = index == session.activeColorPaletteIndex ? " (active)" : ""
                print("  \(index + 1). \(palette.name)\(marker)")
            }
            guard let choice = promptLine("Utiliser quelle palette (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-palette", [choice])
        },
        MenuItem.separator,
        MenuItem(label: "Mode MIDI: fusionne") { try executeCommand("midi-mode", ["fusionne"]) },
        MenuItem(label: "Mode MIDI: individuel") { try executeCommand("midi-mode", ["individuel"]) },
        MenuItem.separator,
        MenuItem(label: "Demarrer la console web...") {
            let portText = promptLine("Port (defaut 8080): ") ?? ""
            try executeCommand("web-console", [portText.isEmpty ? "8080" : portText])
        },
        MenuItem(label: "Arreter la console web") { try executeCommand("web-console", ["stop"]) },
        MenuItem.separator,
        MenuItem(label: "Demarrer le clavier virtuel...") {
            let portText = promptLine("Port (defaut 8081): ") ?? ""
            try executeCommand("virtual-keyboard", [portText.isEmpty ? "8081" : portText])
        },
        MenuItem(label: "Arreter le clavier virtuel") { try executeCommand("virtual-keyboard", ["stop"]) },
        MenuItem.separator,
        MenuItem(label: "Quitter") { try executeCommand("quit", []) },
    ]),
    MenuCategory(mnemonic: "n", title: "Scene", items: [
        MenuItem(label: "Lister les instruments") { try executeCommand("tracks", []) },
        MenuItem(label: "Activer un instrument...") {
            printNumberedTracks()
            guard let choice = promptLine("Activer quel instrument (numero ou id): "), !choice.isEmpty else { return }
            let resolvedID = resolvedTrackIDText(choice)
            try executeCommand("track", [resolvedID, "on"])
            let soundAnswer = promptLine("Activer aussi le son de cet instrument ? (o/n): ") ?? ""
            if soundAnswer.lowercased().hasPrefix("o") {
                try promptChooseSoundForTrack(resolvedID)
            }
        },
        MenuItem(label: "Arreter un instrument...") {
            printNumberedTracks()
            guard let choice = promptLine("Arreter quel instrument (numero ou id): "), !choice.isEmpty else { return }
            try executeCommand("track", [resolvedTrackIDText(choice), "off"])
        },
        MenuItem.separator,
        MenuItem(label: "Activer le son d'un instrument...") {
            printNumberedTracks()
            guard let choice = promptLine("Activer le son de quel instrument (numero ou id): "), !choice.isEmpty else { return }
            try executeCommand("track", [resolvedTrackIDText(choice), "son", "on"])
        },
        MenuItem(label: "Desactiver le son d'un instrument...") {
            printNumberedTracks()
            guard let choice = promptLine("Desactiver le son de quel instrument (numero ou id): "), !choice.isEmpty else { return }
            try executeCommand("track", [resolvedTrackIDText(choice), "son", "off"])
        },
        MenuItem.separator,
        MenuItem(label: "Choisir un son pour un instrument...") {
            printNumberedTracks()
            guard let trackChoice = promptLine("Pour quel instrument (numero ou id): "), !trackChoice.isEmpty else { return }
            try promptChooseSoundForTrack(resolvedTrackIDText(trackChoice))
        },
        MenuItem.separator,
        MenuItem.header("Scene"),
        MenuItem(label: "Sauvegarder scene...") {
            guard let name = promptLine("Nom de la scene: "), !name.isEmpty else { return }
            try executeCommand("save-scene", [name])
        },
        MenuItem(label: "Charger scene...") {
            guard !session.sceneFiles.isEmpty else { print("Choisis d'abord un dossier de scenes (menu JamShack)."); return }
            for (index, name) in session.sceneFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Charger quelle scene (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-scene", [choice])
        },
    ]),
    MenuCategory(mnemonic: "G", title: "Guide Musicaux", items: [
        MenuItem(label: "Voir le Guide Musical") { try executeCommand("guide", []) },
        MenuItem.separator,
        MenuItem(label: "Nouveau guide musical...") {
            guard let title = promptLine("Titre de la sequence: "), !title.isEmpty else { return }
            try executeCommand("guide-new", [title])
            // Keep prompting for one more step until the user leaves the tonic blank,
            // instead of a single add-then-back-to-menu round trip — building a sequence of
            // several modes otherwise means reopening this same menu item repeatedly.
            while true {
                guard let tonicText = promptLine("Tonique (ex: D, F#, Bb ; vide pour terminer): "), !tonicText.isEmpty else { break }
                printNumberedScales()
                guard let scaleText = promptLine("Id de gamme (numero ci-dessus, ou id ecrit, ex: ionian): "), !scaleText.isEmpty else { break }
                do {
                    try executeCommand("guide-add-mode", [tonicText, resolvedScaleID(scaleText)])
                } catch {
                    print("Erreur: \(error)")
                }
            }
        },
        MenuItem(label: "Ajouter un mode au guide musical...") {
            guard let tonicText = promptLine("Tonique (ex: D, F#, Bb): "), !tonicText.isEmpty else { return }
            printNumberedScales()
            guard let scaleText = promptLine("Id de gamme (numero ci-dessus, ou id ecrit, ex: ionian): "), !scaleText.isEmpty else { return }
            try executeCommand("guide-add-mode", [tonicText, resolvedScaleID(scaleText)])
        },
        MenuItem.separator,
        MenuItem(label: "Charger un guide musical...") {
            guard !session.guideFiles.isEmpty else { print("Choisis d'abord un dossier de guides musicaux."); return }
            for (index, name) in session.guideFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Charger quelle sequence (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-guide", [choice])
        },
        MenuItem(label: "Sauvegarder le guide musical") { try executeCommand("save-guide", []) },
        MenuItem(label: "Sauvegarder le guide musical sous...") {
            guard let name = promptLine("Nom de sauvegarde: "), !name.isEmpty else { return }
            try executeCommand("save-guide-as", [name])
        },
        MenuItem.separator,
        MenuItem(label: "Demarrer le guide musical") { try executeCommand("guide-start", []) },
        MenuItem(label: "Arreter le guide musical") { try executeCommand("guide-stop", []) },
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
            guard !session.soundTrackFiles.isEmpty else { print("Choisis d'abord un dossier de soundtracks (menu JamShack)."); return }
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
        MenuItem(label: "Voir la phrase de cadrage...") { try executeCommand("show-soundtrack-framing", []) },
        MenuItem(label: "Modifier la phrase de cadrage...") { try executeCommand("set-soundtrack-framing", []) },
        MenuItem(label: "Sauvegarder la phrase de cadrage...") {
            guard let name = promptLine("Nom de sauvegarde de la phrase de cadrage: "), !name.isEmpty else { return }
            try executeCommand("save-soundtrack-framing", [name])
        },
        MenuItem(label: "Charger une phrase de cadrage...") {
            guard !session.soundTrackFramingFiles.isEmpty else { print("Choisis d'abord un dossier de composition IA (menu JamShack)."); return }
            for (index, name) in session.soundTrackFramingFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Charger quelle phrase de cadrage (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-soundtrack-framing", [choice])
        },
        MenuItem(label: "Revenir a la phrase de cadrage par defaut") { try executeCommand("reset-soundtrack-framing", []) },
        MenuItem.separator,
        MenuItem(label: "Voir les indications de style...") { try executeCommand("show-soundtrack-instructions", []) },
        MenuItem(label: "Modifier les indications de style...") {
            let text = promptLine("Indications de style, optionnel (ex: romantique, mode mineur — vide pour aucune): ") ?? ""
            try executeCommand("set-soundtrack-instructions", text.isEmpty ? [] : [text])
        },
        MenuItem(label: "Sauvegarder les indications de style...") {
            guard let name = promptLine("Nom de sauvegarde des indications: "), !name.isEmpty else { return }
            try executeCommand("save-soundtrack-instructions", [name])
        },
        MenuItem(label: "Charger des indications de style...") {
            guard !session.soundTrackInstructionsFiles.isEmpty else { print("Choisis d'abord un dossier de composition IA (menu JamShack)."); return }
            for (index, name) in session.soundTrackInstructionsFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Charger quelles indications (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-soundtrack-instructions", [choice])
        },
        MenuItem(label: "Revenir aux indications de style par defaut (aucune)") { try executeCommand("reset-soundtrack-instructions", []) },
        MenuItem.separator,
        MenuItem(label: "Voir le prompt de composition...") { try executeCommand("show-soundtrack-prompt", []) },
        MenuItem(label: "Exporter le prompt de composition...") {
            guard let name = promptLine("Nom d'export du prompt: "), !name.isEmpty else { return }
            try executeCommand("export-soundtrack-prompt", [name])
        },
    ]),
    MenuCategory(mnemonic: "M", title: "Morceaux", items: [
        MenuItem(label: "Ecouter le morceau") { try executeCommand("play", []) },
        MenuItem(label: "Voir le morceau (structure et instruments)") { try executeCommand("show-piece", []) },
        MenuItem.separator,
        MenuItem(label: "Choisir le son de lecture du morceau...") {
            guard !session.sampleFiles.isEmpty else { print("Choisis d'abord un dossier de sons (menu JamShack)."); return }
            for (index, name) in session.sampleFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Charger quel son (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-sample", [choice])
        },
        MenuItem(label: "Choisir le son d'une piste...") {
            printPieceDetail()
            guard let sectionText = promptLine("Quelle section (numero): "), !sectionText.isEmpty else { return }
            guard let trackText = promptLine("Quelle piste (numero): "), !trackText.isEmpty else { return }
            if session.sampleFiles.isEmpty { print("(Astuce: choisis d'abord un dossier de sons, menu JamShack.)") }
            for (index, name) in session.sampleFiles.enumerated() { print("  \(index + 1). \(name)") }
            let instrumentText = promptLine("Quel son (numero, nom, ou vide pour le son par defaut): ") ?? ""
            try executeCommand("set-track-instrument", [sectionText, trackText, instrumentText])
        },
        MenuItem(label: "Choisir le son des accords d'une section...") {
            printPieceDetail()
            guard let sectionText = promptLine("Quelle section (numero): "), !sectionText.isEmpty else { return }
            if session.sampleFiles.isEmpty { print("(Astuce: choisis d'abord un dossier de sons, menu JamShack.)") }
            for (index, name) in session.sampleFiles.enumerated() { print("  \(index + 1). \(name)") }
            let instrumentText = promptLine("Quel son (numero, nom, ou vide pour le son par defaut): ") ?? ""
            try executeCommand("set-chord-instrument", [sectionText, instrumentText])
        },
        MenuItem.separator,
        MenuItem(label: "Charger demo") { try executeCommand("load-demo", []) },
        MenuItem(label: "Charger morceau...") {
            guard !session.pieceFiles.isEmpty else { print("Choisis d'abord un dossier de morceaux (menu JamShack)."); return }
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
        MenuItem(label: "Charger une description...") {
            guard !session.compositionFiles.isEmpty else { print("Choisis d'abord un dossier de composition IA (menu JamShack)."); return }
            for (index, name) in session.compositionFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Charger quelle description (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-description", [choice])
        },
        MenuItem(label: "Sauvegarder la description sous...") {
            guard let name = promptLine("Nom de sauvegarde: "), !name.isEmpty else { return }
            try executeCommand("save-description-as", [name])
        },
        MenuItem(label: "Sauvegarder la description") { try executeCommand("save-description", []) },
        MenuItem.separator,
        MenuItem(label: "Voir la phrase de cadrage...") { try executeCommand("show-text-framing", []) },
        MenuItem(label: "Modifier la phrase de cadrage...") { try executeCommand("set-text-framing", []) },
        MenuItem(label: "Sauvegarder la phrase de cadrage...") {
            guard let name = promptLine("Nom de sauvegarde de la phrase de cadrage: "), !name.isEmpty else { return }
            try executeCommand("save-text-framing", [name])
        },
        MenuItem(label: "Charger une phrase de cadrage...") {
            guard !session.textFramingFiles.isEmpty else { print("Choisis d'abord un dossier de composition IA (menu JamShack)."); return }
            for (index, name) in session.textFramingFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine("Charger quelle phrase de cadrage (numero ou nom): "), !choice.isEmpty else { return }
            try executeCommand("use-text-framing", [choice])
        },
        MenuItem(label: "Revenir a la phrase de cadrage par defaut") { try executeCommand("reset-text-framing", []) },
        MenuItem.separator,
        MenuItem(label: "Voir le prompt de composition...") { try executeCommand("show-text-prompt", []) },
        MenuItem(label: "Exporter le prompt de composition...") {
            guard let name = promptLine("Nom d'export du prompt: "), !name.isEmpty else { return }
            try executeCommand("export-text-prompt", [name])
        },
    ]),
    MenuCategory(mnemonic: "J", title: "Jam Session", items: [
        MenuItem(label: "Demarrer une jam session...") {
            promptForPseudo()
            let portText = promptLine("Port (defaut 7777): ") ?? ""
            try executeCommand("server", [portText.isEmpty ? "7777" : portText])
        },
        MenuItem(label: "Arreter la jam session") { try executeCommand("stop-server", []) },
        MenuItem(label: "Rejoindre une jam session...") {
            promptForPseudo()
            let host = promptLine("Serveur (defaut localhost): ") ?? ""
            let portText = promptLine("Port (defaut 7777): ") ?? ""
            try executeCommand("client", [host.isEmpty ? "localhost" : host, portText.isEmpty ? "7777" : portText])
        },
        MenuItem(label: "Trouver une jam session...") {
            promptForPseudo()
            try executeCommand("discover", [])
        },
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

// Straight into the run screen at launch (right after the scene prompt above) rather than
// dropping into the plain Command REPL first — the run screen is where playing actually
// happens, so it shouldn't need an extra `run` command every time. Ctrl+C/`q` falls back
// to this same Command REPL exactly as it always has when leaving `run` explicitly.
runConsoleScreen(mode: .run)

print("JamShack — mode Command")
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
