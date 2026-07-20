import Foundation
import AppCore
import Localization
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

// Default working folders, so `pieces`/`samples`/`guides` don't need to be re-typed on every
// launch. Derived from this source file's own path (baked in at compile time via `#filePath`)
// rather than assumed from the current working directory, so it still resolves correctly no
// matter where `swift run` is invoked from — `Sources/JamShack/main.swift` is 4 levels below
// the project root that holds `Settings`/`User`/`Library` as siblings of `MusicTheoryKit/`.
// Three top-level buckets, not one flat pile of folders: `Settings` (palettes, chord
// progression templates, LLM connections — one unit, see `setSettingsFolder`'s doc comment),
// `User` (the user's own musical material — pieces, scenes, guide sequences, soundtracks,
// AI-composition folders — each still independently redirectable, exactly as before, just a
// new default location), `Library` (reusable assets not tied to any particular piece — for
// now just SoundFonts). `try?`: silently skipped if a folder doesn't exist (e.g. a different
// checkout) rather than failing startup.
let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // JamShack
    .deletingLastPathComponent() // Sources
    .deletingLastPathComponent() // MusicTheoryKit
    .deletingLastPathComponent() // Music
let settingsFolder = projectRoot.appendingPathComponent("Settings")
let userFolder = projectRoot.appendingPathComponent("User")
let libraryFolder = projectRoot.appendingPathComponent("Library")
try? session.setSettingsFolder(settingsFolder.path) // palettes.json, chordprogressions.json, LLMConnections/ — creates them if absent
try? session.listPieceFiles(in: userFolder.appendingPathComponent("Pieces").path)
try? session.listSampleFiles(in: libraryFolder.appendingPathComponent("SoundFonts").path)
try? FileManager.default.createDirectory(at: userFolder.appendingPathComponent("SoundTracks"), withIntermediateDirectories: true)
try? session.listSoundTrackFiles(in: userFolder.appendingPathComponent("SoundTracks").path)
try? FileManager.default.createDirectory(at: userFolder.appendingPathComponent("Sequences"), withIntermediateDirectories: true)
try? session.listGuideFiles(in: userFolder.appendingPathComponent("Sequences").path)
try? FileManager.default.createDirectory(at: userFolder.appendingPathComponent("Scenes"), withIntermediateDirectories: true)
try? session.listSceneFiles(in: userFolder.appendingPathComponent("Scenes").path)
try? session.setPromptsFolder(userFolder.appendingPathComponent("Composition IA").path) // creates its fixed subfolders if absent

// If any scenes are already sitting in the default folder, offer to load one right away —
// picking up a known instrument setup (e.g. "piano solo") shouldn't require knowing the
// `use-scene`/menu path exists on a first launch. Purely optional: leaving the prompt blank
// (or any answer that doesn't resolve) just moves on to the normal REPL with nothing loaded.
if !session.sceneFiles.isEmpty {
    print("\nScenes disponibles dans \(session.sceneFolder ?? "?"):")
    for (index, name) in session.sceneFiles.enumerated() { print("  \(index + 1). \(name)") }
    if let choice = promptLine(L10n.string(.promptChargerSceneDemarrage, session.currentLanguage)), !choice.isEmpty {
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
      lumi-guide <tonique> <gamme> <rootR> <rootG> <rootB> <scaleR> <scaleG> <scaleB> [luminosite]
                                 envoie une carte de couleurs statique (racine + gamme) a un clavier ROLI LUMI Keys BLOCK connecte en USB
      lumi-run <rootR> <rootG> <rootB> <scaleR> <scaleG> <scaleB> [luminosite]
                                 mode run LUMI : suit le mode reconnu en jouant (racine/gamme), sinon affichage piano natif du LUMI
      lumi-run stop              arrete le mode run LUMI
      lumi-guide-sync <rootR> <rootG> <rootB> <scaleR> <scaleG> <scaleB> [luminosite]
                                 suit l'etape active de l'ecran Guide Musical (racine/gamme), sinon affichage piano natif si la gamme n'est pas geree par LUMI
      lumi-guide-sync stop       arrete la synchronisation LUMI avec le Guide Musical
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
      scene-tree                 plan de scene en arbre (instruments, consoles, clients connectes)
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
      settings <dir>             pointe le dossier de reglages (palettes, progressions d'accords, connexions LLM)
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
      guide-add-mode <tonique> <id-gamme> [progression]  ajoute une etape, avec une progression d'accords optionnelle (ex: guide-add-mode D dorian, ou guide-add-mode C ionian "Blues 12 mesures")
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
    let lang = session.currentLanguage
    guard let piece = session.piece else {
        return [TextStyle.placeholder(L10n.string(.placeholderAucunMorceauCharge, lang))]
    }
    var lines: [String] = []
    let keyName = ScaleLibrary.byID(piece.key.scaleID)?.popularName ?? piece.key.scaleID
    lines.append(TextStyle.heading(piece.title) + (piece.composer.map { " — \($0)" } ?? ""))
    lines.append(TextStyle.field(L10n.string(.fieldTempo, lang), "\(Int(piece.tempoBPM)) BPM"))
    lines.append(TextStyle.field(L10n.string(.fieldTonalite, lang), "\(PitchClass(piece.key.tonic).name()) \(keyName)"))
    if piece.sections.isEmpty {
        lines.append(TextStyle.placeholder(L10n.string(.placeholderAucuneSectionEncore, lang)))
    }
    for (sectionIndex, section) in piece.sections.enumerated() {
        let modeName = ScaleLibrary.byID(section.mode.scaleID)?.popularName ?? section.mode.scaleID
        lines.append("")
        lines.append(TextStyle.heading(L10n.string(.formatSection, lang, sectionIndex + 1, section.name)) + " (\(section.lengthInMeasures) mesures, \(PitchClass(section.mode.tonic).name()) \(modeName))")
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
    let lang = session.currentLanguage
    guard let soundTrack = session.currentSoundTrack else {
        print(TextStyle.placeholder(L10n.string(.placeholderAucuneSoundtrack, lang)))
        return
    }
    print(TextStyle.heading(soundTrack.title))
    print(TextStyle.field(L10n.string(.fieldFichier, lang), session.currentSoundTrackFilePath ?? TextStyle.placeholder(L10n.string(.placeholderJamaisSauvegardee, lang))))
    print(TextStyle.field(L10n.string(.fieldDuree, lang), String(format: "%.1fs", soundTrack.durationSeconds)))
    print(TextStyle.field(L10n.string(.fieldEvenements, lang), "\(soundTrack.events.count)"))
    print(TextStyle.field(L10n.string(.fieldPistes, lang), soundTrack.trackIDs.sorted().joined(separator: ", ")))
}

/// Everything the "Decrire le morceau..." wizard collects before composing — title,
/// description (`sourceText`), and style indications — shown together so it's easy to
/// check what's about to be sent before actually calling `compose`.
func printCompositionDescription() {
    let lang = session.currentLanguage
    print(TextStyle.field(L10n.string(.fieldTitre, lang), session.compositionTitle ?? TextStyle.placeholder(L10n.string(.placeholderAucun, lang))))
    print(TextStyle.field(L10n.string(.fieldIndications, lang), session.additionalCompositionInstructions ?? TextStyle.placeholder(L10n.string(.placeholderAucune, lang))))
    if let sourceText = session.sourceText {
        print(TextStyle.field(L10n.string(.fieldDescription, lang), ""))
        print(sourceText)
    } else {
        print(TextStyle.field(L10n.string(.fieldDescription, lang), TextStyle.placeholder(L10n.string(.placeholderAucune, lang))))
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
    guard track.isListening else { return TextStyle.placeholder(L10n.string(.placeholderCoupee, session.currentLanguage)) }
    let level = String(format: "%.4f", track.microphoneInputLevel)
    guard !track.lastDetectedPitches.isEmpty else { return TextStyle.placeholder("(silence, niveau \(level))") }
    let notesText = track.lastDetectedPitches
        .sorted { $0.frequencyHz < $1.frequencyHz }
        .map { noteNameWithOctave($0.midiPitch) }
        .joined(separator: " ")
    return "\(notesText) (niveau \(level))"
}

/// Localized display text for a microphone track's current `MicrophoneRecognitionMode` — the
/// `N`/`K` window count is always shown numerically (not localized) since it's a plain count,
/// same convention as every other numeric field in this app.
func microphoneRecognitionModeText(_ mode: MicrophoneRecognitionMode) -> String {
    let lang = session.currentLanguage
    switch mode {
    case .monophonicHeuristic: return L10n.string(.optionMonoHeuristique, lang)
    case .monophonicHPS: return L10n.string(.optionMonoHPS, lang)
    case .polyphonicLatched(let windows): return "\(L10n.string(.optionPolyLatched, lang)) (N=\(windows))"
    case .polyphonicSliding(let windows): return "\(L10n.string(.optionPolySliding, lang)) (K=\(windows))"
    }
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
    return TextStyle.placeholder(L10n.string(.placeholderAucun, session.currentLanguage))
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
    case .standalone: return TextStyle.placeholder(L10n.string(.placeholderSolo, session.currentLanguage))
    case .server(let port): return "serveur sur le port \(port)"
    case .client(let description): return "connecte a \(description)"
    }
}

/// "(inactive)" / "http://localhost:<port>" — shared by `status`/`config`.
func webConsoleStatusText() -> String {
    session.webConsolePort.map { "http://localhost:\($0)" } ?? TextStyle.placeholder(L10n.string(.placeholderInactive, session.currentLanguage))
}

func virtualKeyboardStatusText() -> String {
    session.virtualKeyboardPort.map { "http://localhost:\($0)" } ?? TextStyle.placeholder(L10n.string(.placeholderInactif, session.currentLanguage))
}

/// One line per track — shared by the `tracks` command and the Source/Reseau menus'
/// prompts, so picking a track id to act on always shows the same up-to-date list first.
/// The MIDI channel to show for `track` (see `TrackInfo.lastChannel`'s doc comment): the
/// real, actually-observed-through-listening value if there is one, else the passive
/// sniffer's own observation (`ImprovSession.observedChannel(forMIDISourceIndex:)`) for a
/// `.midiSource` track — meaningless (so always `nil`) for anything else, including
/// `.midiMerged`, which has no single physical source of its own to sniff.
func displayedChannel(for track: TrackInfo) -> Int? {
    if let channel = track.lastChannel { return channel }
    guard case .midiSource(let index) = track.id else { return nil }
    return session.observedChannel(forMIDISourceIndex: index)
}

func printTracks() {
    let lang = session.currentLanguage
    print(TextStyle.field(L10n.string(.fieldReseau, lang), networkRoleText()))
    print(TextStyle.field(L10n.string(.fieldModeMidi, lang), session.midiFusionMode == .merged ? "fusionne" : "individuel"))
    for track in session.tracks {
        var line = "  [\(trackIDText(track.id))] \(track.label)\(ownerSuffix(track)) — ecoute: \(TextStyle.flag(track.isListening))"
        if track.canHaveSound {
            line += ", son: \(TextStyle.flag(track.soundEnabled))"
            if let instrument = track.instrumentName { line += " (\(instrument))" }
        }
        if let channel = displayedChannel(for: track) {
            line += ", canal: \(channel + 1)" // 1-indexed for display, matching how MIDI channels are conventionally shown to musicians
        }
        print(line)
    }
    let unassigned = session.unassignedInstruments()
    if !unassigned.isEmpty {
        print(TextStyle.placeholder(L10n.string(.formatInstrumentsNonAttaches, lang, unassigned.count)))
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

/// One line of a box-drawn tree (see `printSceneTree`) — `ancestorIsLast[i]` says whether the
/// i-th ancestor level was itself the LAST child at its own level (draws a blank continuation
/// there instead of "│", the standard box-drawing-tree convention), `isLast` decides THIS
/// line's own connector ("└─" vs "├─").
func printTreeLine(_ text: String, ancestorIsLast: [Bool], isLast: Bool) {
    let prefix = ancestorIsLast.map { $0 ? "   " : "│  " }.joined()
    print(prefix + (isLast ? "└─ " : "├─ ") + text)
}

/// "Le menu Scene qui fait lister les instruments... l'etendre pour representer l'appli et
/// tous les instruments connectes, ainsi que la console si elle est active [...] en mode
/// serveur, la liste des clients, et pour chaque client la liste des instruments" — a fuller
/// picture than `printTracks`' flat list: local instruments, the two HTTP servers' own
/// active/inactive state, and (only while hosting) every connected participant with their own
/// instruments nested underneath, even a participant who hasn't announced any track yet (see
/// `ImprovSession.connectedClients()`'s doc comment for why that needs its own accessor rather
/// than just scanning `tracks` for `.remote` entries).
func printSceneTree() {
    let lang = session.currentLanguage
    let isServer: Bool
    if case .server = session.networkRole { isServer = true } else { isServer = false }
    print("JamShack — mode: \(networkRoleText())")

    // The scene/roles concept as its own clearly-labeled branch, shown even with no active
    // scene ("(aucune)") so the concept itself is always visible in the tree, not just when
    // it happens to be in use — placed BEFORE "Instruments locaux" since a scene/role is the
    // declarative concept an instrument then gets attached to, not the other way around.
    // Mirrors the web console's own `renderSceneTree`, kept in sync by hand.
    if let scene = session.currentScene {
        printTreeLine("\(L10n.string(.labelSceneTree, lang))\(scene.title)", ancestorIsLast: [], isLast: false)
        if scene.roles.isEmpty {
            printTreeLine(TextStyle.placeholder(L10n.string(.placeholderAucunRoleDeclare, lang)), ancestorIsLast: [false], isLast: true)
        } else {
            for (index, role) in scene.roles.enumerated() {
                let attachedText = role.attachedTrackID.flatMap { id in session.tracks.first { $0.id == id }?.label } ?? TextStyle.placeholder(L10n.string(.placeholderLibre, lang))
                var line = "\(role.name) — \(attachedText)"
                if let soundName = role.soundName { line += " [\(soundName)]" }
                printTreeLine(line, ancestorIsLast: [false], isLast: index == scene.roles.count - 1)
            }
        }
    } else {
        printTreeLine("\(L10n.string(.labelSceneTree, lang))\(TextStyle.placeholder(L10n.string(.placeholderAucune, lang)))", ancestorIsLast: [], isLast: false)
    }

    let localTracks = session.tracks.filter { track -> Bool in
        if case .remote = track.id { return false }
        return true
    }
    printTreeLine(L10n.string(.labelInstrumentsLocaux, lang), ancestorIsLast: [], isLast: false)
    if localTracks.isEmpty {
        printTreeLine(TextStyle.placeholder(L10n.string(.placeholderAucun, lang)), ancestorIsLast: [false], isLast: true)
    } else {
        for (index, track) in localTracks.enumerated() {
            var line = "[\(trackIDText(track.id))] \(track.label) — ecoute: \(TextStyle.flag(track.isListening))"
            if track.canHaveSound {
                line += ", son: \(TextStyle.flag(track.soundEnabled))"
                if let instrument = track.instrumentName { line += " (\(instrument))" }
            }
            if let channel = displayedChannel(for: track) {
                line += ", canal: \(channel + 1)"
            }
            printTreeLine(line, ancestorIsLast: [false], isLast: index == localTracks.count - 1)
        }
    }

    printTreeLine("\(L10n.string(.fieldConsoleWeb, lang)): \(webConsoleStatusText())", ancestorIsLast: [], isLast: false)
    printTreeLine("\(L10n.string(.fieldClavierVirtuel, lang)): \(virtualKeyboardStatusText())", ancestorIsLast: [], isLast: !isServer)

    guard isServer else { return }
    let clients = session.connectedClients()
    printTreeLine(L10n.string(.formatClientsConnectes, lang, clients.count), ancestorIsLast: [], isLast: true)
    if clients.isEmpty {
        printTreeLine(TextStyle.placeholder(L10n.string(.placeholderAucun, lang)), ancestorIsLast: [true], isLast: true)
        return
    }
    for (index, client) in clients.enumerated() {
        let clientIsLast = index == clients.count - 1
        printTreeLine(client.name, ancestorIsLast: [true], isLast: clientIsLast)
        let clientTracks = session.tracks.filter { track -> Bool in
            if case .remote(let clientID, _) = track.id { return clientID == client.clientID }
            return false
        }
        if clientTracks.isEmpty {
            printTreeLine(TextStyle.placeholder(L10n.string(.labelAucunInstrumentEncore, lang)), ancestorIsLast: [true, clientIsLast], isLast: true)
        } else {
            for (trackIndex, track) in clientTracks.enumerated() {
                let line = "[\(trackIDText(track.id))] \(track.label) — ecoute: \(TextStyle.flag(track.isListening))"
                printTreeLine(line, ancestorIsLast: [true, clientIsLast], isLast: trackIndex == clientTracks.count - 1)
            }
        }
    }
}

/// All 33 scales of `ScaleLibrary.all`, grouped under a family-name heading — `.all`'s
/// declaration order is already family-then-degree (see `ScaleLibrary.swift`), so no
/// re-sorting is needed, just a heading printed whenever the family changes. Printed as a
/// numbered pick-list before prompting for a scale id, so typing a bare number meant for this
/// list (instead of the id itself) still resolves — that exact mistake used to silently save
/// an unresolvable guide step (see `resolvedScaleID`). Previously only family 1 (the 7
/// classic "Major Modes") was listed here, leaving the other 26 scales undiscoverable in this
/// menu even though `guide-add-mode`/`ScaleLibrary.byID` already accepted any of them by id.
/// The circle-of-fifths wheel still only understands family 1 for its own display (see
/// `CircleOfFifths.parentTonic(for:)`) — unrelated to this pick-list, not something to "fix"
/// here: a non-family-1 mode simply shows on the wheel without its diatonic contour.
func printNumberedScales() {
    var currentFamilyID = -1
    for (index, scale) in ScaleLibrary.all.enumerated() {
        if scale.familyID != currentFamilyID {
            currentFamilyID = scale.familyID
            print("  -- \(ScaleFamilies.family(currentFamilyID).name) --")
        }
        print("  \(index + 1). \(scale.id) (\(scale.popularName) / \(scale.systematicName))")
    }
}

/// Resolves a "<n|id>" argument against the full `ScaleLibrary.all` pick-list
/// `printNumberedScales()` just printed — a number picks by 1-based position, anything else
/// (a correctly-typed id) is passed through literally.
func resolvedScaleID(_ text: String) -> String {
    if let index = Int(text), ScaleLibrary.all.indices.contains(index - 1) {
        return ScaleLibrary.all[index - 1].id
    }
    return text
}

func printNumberedChordProgressionTemplates() {
    for (index, template) in session.chordProgressionTemplates.enumerated() {
        print("  \(index + 1). \(template.name) (\(template.degrees.joined(separator: "-")))")
    }
}

/// Resolves a "<n|nom>" argument against `session.chordProgressionTemplates` — a number
/// picks by 1-based position (mirrors `resolvedScaleID`'s convention), anything else matches
/// by name, case-insensitively. `nil` for a blank/unmatched argument (no progression).
func resolvedChordProgressionTemplate(_ text: String) -> ChordProgressionTemplate? {
    guard !text.isEmpty else { return nil }
    if let index = Int(text), session.chordProgressionTemplates.indices.contains(index - 1) {
        return session.chordProgressionTemplates[index - 1]
    }
    return session.chordProgressionTemplates.first { $0.name.lowercased() == text.lowercased() }
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

/// The 4 fixed recognition-mode presets offered by the menu — arbitrary `N`/`K` window counts
/// stay reachable only via the typed `track micro mode poly-latched:N`/`poly-glissant:K`
/// command, same "convenient list vs. power-user typed form" split already used throughout
/// this app (e.g. `use-piece <n>` vs. `load <path.json>`).
private let recognitionModePresets: [MicrophoneRecognitionMode] = [
    .monophonicHeuristic, .monophonicHPS, .default, .polyphonicSliding(windows: 3),
]

func promptChooseRecognitionModeForTrack(_ resolvedTrackID: String) throws {
    let lang = session.currentLanguage
    for (index, mode) in recognitionModePresets.enumerated() {
        print("  \(index + 1). \(microphoneRecognitionModeText(mode))")
    }
    guard let choice = promptLine(L10n.string(.promptQuelModeDeReconnaissance, lang)), !choice.isEmpty else { return }
    let mode: MicrophoneRecognitionMode?
    if let index = Int(choice), recognitionModePresets.indices.contains(index - 1) {
        mode = recognitionModePresets[index - 1]
    } else {
        mode = MicrophoneRecognitionMode(wireValueText: choice)
    }
    guard let mode else { print("Choix invalide."); return }
    try executeCommand("track", [resolvedTrackID, "mode", mode.wireValueText])
}

/// Resolves a "<n|nom>" argument against `session.currentScene?.roles` — a number picks by
/// 1-based position (mirrors `resolvedChordProgressionTemplate`'s convention), anything else
/// matches by name, case-insensitively. `nil` if there's no active scene or nothing matches.
func resolvedSceneRoleID(_ text: String) -> SceneRole.ID? {
    guard let roles = session.currentScene?.roles else { return nil }
    if let index = Int(text), roles.indices.contains(index - 1) {
        return roles[index - 1].id
    }
    return roles.first { $0.name.lowercased() == text.lowercased() }?.id
}

/// A numbered list of the active scene's roles, each showing what's attached (or "(libre)")
/// and its own sound, if any — the pick-list `scene-role-*` commands/menu items show before
/// prompting for a role.
func printNumberedSceneRoles() {
    guard let roles = session.currentScene?.roles else {
        print(TextStyle.placeholder(L10n.string(.placeholderAucuneSceneActive, session.currentLanguage)))
        return
    }
    if roles.isEmpty {
        print(TextStyle.placeholder(L10n.string(.placeholderAucunRolePourEnAjouter, session.currentLanguage)))
        return
    }
    for (index, role) in roles.enumerated() {
        let attachedText = role.attachedTrackID.flatMap { id in session.tracks.first { $0.id == id }?.label }
        var line = "  \(index + 1). \(role.name) — \(attachedText ?? TextStyle.placeholder(L10n.string(.placeholderLibre, session.currentLanguage)))"
        if let soundName = role.soundName { line += " [\(soundName)]" }
        print(line)
    }
}

/// If a scene is active and the just-started track isn't attached to any role yet, offers to
/// claim a free one (or create a new one on the fly) — satisfies "when connecting an
/// instrument, choose which role to take" for the interactive terminal case (`track <id> on`'s
/// own case calls this right after starting the track).
func promptClaimFreeSceneRoleIfNeeded(for trackID: TrackID) {
    let lang = session.currentLanguage
    guard session.currentScene != nil, session.unassignedInstruments().contains(where: { $0.id == trackID }) else { return }
    print(TextStyle.placeholder("Cette piste n'est attachee a aucun role de la scene active."))
    let freeRoles = session.freeSceneRoles()
    if freeRoles.isEmpty {
        guard let name = promptLine(L10n.string(.promptNomNouveauRole1, lang)), !name.isEmpty else { return }
        if let roleID = try? session.addSceneRole(name: name) {
            try? session.attachInstrument(trackID, toRole: roleID)
        }
        return
    }
    for (index, role) in freeRoles.enumerated() { print("  \(index + 1). \(role.name)") }
    print("  n. Nouveau role...")
    guard let choice = promptLine(L10n.string(.promptAttacherAQuelRole, lang)), !choice.isEmpty else { return }
    if choice.lowercased() == "n" {
        guard let name = promptLine(L10n.string(.promptNomNouveauRole2, lang)), !name.isEmpty else { return }
        if let roleID = try? session.addSceneRole(name: name) {
            try? session.attachInstrument(trackID, toRole: roleID)
        }
    } else if let index = Int(choice), freeRoles.indices.contains(index - 1) {
        try? session.attachInstrument(trackID, toRole: freeRoles[index - 1].id)
    }
}

func printStatus() {
    let lang = session.currentLanguage
    print(TextStyle.field(L10n.string(.fieldPiece, lang), session.piece.map { $0.title } ?? TextStyle.placeholder(L10n.string(.placeholderAucun, lang))))
    print(TextStyle.field(L10n.string(.fieldFichier, lang), session.currentPieceFilePath ?? TextStyle.placeholder(L10n.string(.placeholderJamaisSauvegarde, lang))))
    print(TextStyle.field(L10n.string(.fieldPlaying, lang), TextStyle.flag(session.isPlaying)))
    print(TextStyle.field(L10n.string(.fieldRecording, lang), TextStyle.flag(session.isRecording)))
    print(TextStyle.field(L10n.string(.fieldSoundtrack, lang), session.currentSoundTrack.map { $0.title } ?? TextStyle.placeholder(L10n.string(.placeholderAucune, lang))))
    print(TextStyle.field(L10n.string(.fieldPlayingSoundtrack, lang), TextStyle.flag(session.isPlayingSoundTrack)))
    print(TextStyle.field(L10n.string(.fieldConsoleWeb, lang), webConsoleStatusText()))
    print(TextStyle.field(L10n.string(.fieldClavierVirtuel, lang), virtualKeyboardStatusText()))
    print(TextStyle.field(L10n.string(.fieldPaletteDeCouleur, lang), session.activeColorPalette.name))
    print()
    printTracks()
    print()
    for track in session.tracks where track.isListening {
        print(TextStyle.heading("[\(trackIDText(track.id))] \(track.label)\(ownerSuffix(track))"))
        if track.id == .microphone {
            print(TextStyle.field(L10n.string(.fieldMicro, lang), microphoneStatusText(track)))
            print(TextStyle.field(L10n.string(.fieldModeReconnaissance, lang), microphoneRecognitionModeText(track.microphoneRecognitionMode)))
            if track.microphoneInputLevel < 0.0005 {
                print(TextStyle.placeholder("  (niveau quasi nul: le micro ne semble rien recevoir. Verifie qu'il n'est pas coupe/mute, que c'est le bon peripherique d'entree, et que ce terminal a la permission microphone dans Reglages Systeme > Confidentialite et securite > Microphone)"))
            }
        }
        print(TextStyle.field(L10n.string(.fieldChord, lang), chordDisplayText(track)))
        print(TextStyle.field(L10n.string(.fieldModes, lang), modesDisplayText(track)))
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
/// that draws a degree-line (per-track, playback, and the `.guide` screen), so "which color
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
    /// the sequence, the current step's neighbors on the circle of fifths, and a degree-line
    /// keyboard for the current step's mode — independent of any track's own recognized
    /// mode, which keeps showing on `.run` unaffected.
    case guide

    var label: String {
        let lang = session.currentLanguage
        switch self {
        case .run: return L10n.string(.tabRun, lang)
        case .config: return L10n.string(.tabConfig, lang)
        case .guide: return L10n.string(.tabGuideMusical, lang)
        }
    }

    /// What `ImprovSession.notifyActiveScreen` needs to know to auto-propagate the LUMI
    /// display — `AppCore` shouldn't know about this terminal's own screen enum, so this is
    /// the one place that translates between the two.
    var lumiAutoPropagationScreen: ImprovSession.LumiAutoPropagationScreen {
        switch self {
        case .run: return .run
        case .guide: return .guide
        case .config: return .other
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
    return "\u{1B}[2m\(L10n.string(.labelEcranPrefix, session.currentLanguage))\u{1B}[0m  \(tabs)"
}

func renderConsoleFrame(mode: ConsoleScreenMode) {
    let lang = session.currentLanguage
    var output = "\u{1B}[H"
    func line(_ text: String = "") {
        output += "\u{1B}[K" + text + "\n"
    }
    line(renderScreenTabs(mode))
    let menuCategories = buildMenuCategories(for: lang)
    line(renderMenuBar(menuCategories))
    if let openIndex = openMenuIndex {
        for row in renderDropdown(menuCategories[openIndex]) { line(row) }
    } else {
        // Only shown while no menu is open — once a dropdown is on screen the controls are
        // self-evident, and the hint would just be one more thing to visually parse next to it.
        line(TextStyle.placeholder(L10n.string(.hintMenuControls, lang)))
    }
    line()

    // While a menu is open, the screen-mode content below is entirely hidden rather than just
    // pushed down by the dropdown — with many connected instruments/tracks that content can run
    // long, and having it shift and peek out under an open dropdown is uncomfortable to read; it
    // reappears as soon as the menu closes (see `renderDropdown`'s own doc comment: the dropdown
    // itself is never an absolute-position overlay, so this is the only way to keep it from
    // sharing the screen with stale content).
    if openMenuIndex == nil {
        switch mode {
        case .config:
            line(TextStyle.field(L10n.string(.fieldPiece, lang), session.piece.map { $0.title } ?? TextStyle.placeholder(L10n.string(.placeholderAucun, lang))))
            line(TextStyle.field(L10n.string(.fieldFichier, lang), session.currentPieceFilePath ?? TextStyle.placeholder(L10n.string(.placeholderJamaisSauvegarde, lang))))
            line(TextStyle.field(L10n.string(.fieldPlaying, lang), TextStyle.flag(session.isPlaying)))
            line(TextStyle.field(L10n.string(.fieldRecording, lang), TextStyle.flag(session.isRecording)))
            line(TextStyle.field(L10n.string(.fieldSoundtrack, lang), session.currentSoundTrack.map { $0.title } ?? TextStyle.placeholder(L10n.string(.placeholderAucune, lang))))
            line(TextStyle.field(L10n.string(.fieldReseau, lang), networkRoleText()))
            line(TextStyle.field(L10n.string(.fieldConsoleWeb, lang), webConsoleStatusText()))
            line(TextStyle.field(L10n.string(.fieldClavierVirtuel, lang), virtualKeyboardStatusText()))
            line(TextStyle.field(L10n.string(.fieldPaletteDeCouleur, lang), session.activeColorPalette.name))
            line(TextStyle.field(L10n.string(.fieldModeMidi, lang), session.midiFusionMode == .merged ? "fusionne" : "individuel"))
            line(TextStyle.field(L10n.string(.fieldLumiCouleurRacine, lang), session.lumiSettings.rootColorHex))
            line(TextStyle.field(L10n.string(.fieldLumiCouleurGamme, lang), session.lumiSettings.scaleColorHex))
            line(TextStyle.field(L10n.string(.fieldLumiLuminosite, lang), "\(session.lumiSettings.brightnessPercentage)%"))
            line(TextStyle.field(L10n.string(.fieldLumiAutoRun, lang), TextStyle.flag(session.lumiSettings.autoPropagateRunMode)))
            line(TextStyle.field(L10n.string(.fieldLumiAutoGuide, lang), TextStyle.flag(session.lumiSettings.autoPropagateGuideMode)))
            line()
            line(TextStyle.heading(L10n.string(.headingDetailMorceauActif, lang)))
            for row in pieceDetailLines() { line(row) }

        case .run:
            let lastEventText = session.lastMIDIEvent.map { "\($0.kind == .noteOn ? "on " : "off")pitch=\($0.pitch) vel=\($0.velocity)" } ?? "-"
            line(TextStyle.field(L10n.string(.fieldDernierEvt, lang), lastEventText))

            let listeningTracks = session.tracks.filter { $0.isListening }
            if listeningTracks.isEmpty {
                line()
                line(TextStyle.placeholder(L10n.string(.placeholderAucunePisteEnEcoute, lang)))
            }
            for track in listeningTracks {
                line()
                line(TextStyle.heading("[\(trackIDText(track.id))] \(track.label)\(ownerSuffix(track))"))
                if track.id == .microphone {
                    line(TextStyle.field(L10n.string(.fieldMicro, lang), microphoneStatusText(track)))
                    line(TextStyle.field(L10n.string(.fieldModeReconnaissance, lang), microphoneRecognitionModeText(track.microphoneRecognitionMode)))
                } else if track.canHaveSound {
                    let soundText = TextStyle.flag(track.soundEnabled) + (track.instrumentName.map { " (\($0))" } ?? "")
                    line(TextStyle.field(L10n.string(.fieldSon, lang), soundText))
                }
                line(TextStyle.field(L10n.string(.fieldChord, lang), chordDisplayText(track)))
                line(TextStyle.field(L10n.string(.fieldModes, lang), modesDisplayText(track)))
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
                line(TextStyle.heading(L10n.string(.headingDerouleComposition, lang)))
                if timeline.isEmpty {
                    line(TextStyle.placeholder(L10n.string(.placeholderPasAccordMorceau, lang)))
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
                line(TextStyle.heading(L10n.string(.headingClavierComposeEnCours, lang)))
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
                line(TextStyle.heading(L10n.string(.headingClavierSoundtrackEnCours, lang)))
                for row in renderKeyboard(
                    startMIDI: 48, octaveCount: 3, blackZoneRows: 2, whiteZoneRows: 1,
                    colorFor: { pitch in soundTrackHeld.contains(pitch) ? KeyboardColor.heldNoChord : nil }
                ) { line(row) }
            }
    
        case .guide:
            guard let currentGuide = session.currentGuide else {
                line(TextStyle.placeholder(L10n.string(.placeholderAucuneSequenceGuide, lang)))
                break
            }
            line(TextStyle.heading(L10n.string(.headingSequence, lang, currentGuide.title)))
            if currentGuide.steps.isEmpty {
                line(TextStyle.placeholder(L10n.string(.placeholderSequenceVideGuide, lang)))
            } else {
                let items = currentGuide.steps.enumerated().map { index, step -> (display: String, plainWidth: Int) in
                    let name = step.mode.resolve()?.displayName ?? "?"
                    if index == session.currentGuideStepIndex {
                        return ("\(KeyboardColor.chordRoot)[\(name)]\(KeyboardColor.reset)", name.count + 2)
                    }
                    return (name, name.count)
                }
                for wrapped in wrapItems(items) { line(wrapped) }
            }
            if let currentIndex = session.currentGuideStepIndex,
               currentGuide.steps.indices.contains(currentIndex),
               let progression = currentGuide.steps[currentIndex].chordProgression,
               !progression.isEmpty {
                let name = currentGuide.steps[currentIndex].chordProgressionName
                let chords = progression.map { $0.resolve()?.displayName ?? "?" }.joined(separator: " - ")
                line(TextStyle.field(name.map { L10n.string(.formatSuiteAccordsNamed, lang, $0) } ?? L10n.string(.fieldSuiteAccords, lang), chords))
            }
            line()
            guard let guideMode = session.currentGuideStepMode() else {
                // Distinguish "not started yet" from "started, but this step's mode reference
                // doesn't resolve" (shouldn't happen for a step added via `addGuideStep` since
                // it now validates up front, but a hand-edited or older save file could still
                // have one) — the two used to show the same misleading "not started" message.
                if session.currentGuideStepIndex != nil {
                    line(TextStyle.placeholder(L10n.string(.placeholderEtapeNeResoutPas, lang)))
                } else {
                    line(TextStyle.placeholder(L10n.string(.placeholderGuideNonDemarre, lang)))
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
                line(TextStyle.placeholder(L10n.string(.placeholderRoueNonDisponible, lang)))
            }
            line()
            line(TextStyle.heading(L10n.string(.headingClavierGuide, lang)))
            let guideHeldPitches = Set(session.tracks.filter(\.isListening).flatMap(\.heldPitches))
            for row in renderKeyboard(
                startMIDI: 48, octaveCount: 3, blackZoneRows: 2, whiteZoneRows: 1,
                modeMarker: degreeMarker(for: guideMode),
                colorFor: { pitch in guideHeldPitches.contains(pitch) ? KeyboardColor.heldNoChord : nil }
            ) { line(row) }
        }
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
    // Auto-propagate the LUMI display for whichever screen we're opening on (usually `.run`,
    // per the top-level call site's own comment) — without this, LUMI stays whatever it last
    // showed until the user happens to Tab through screens once.
    session.notifyActiveScreen(mode.lumiAutoPropagationScreen)
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
                session.notifyActiveScreen(mode.lumiAutoPropagationScreen)
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
                handleMenuKey(key, categories: buildMenuCategories(for: session.currentLanguage))
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
    case "scene-tree":
        session.refreshTracks()
        printSceneTree()
    case "midi-mode":
        guard let arg = args.first?.lowercased() else { print("usage: midi-mode fusionne|individuel"); break }
        switch arg {
        case "fusionne", "merged": session.setMIDIFusionMode(.merged)
        case "individuel", "individual": session.setMIDIFusionMode(.individual)
        default: print("usage: midi-mode fusionne|individuel")
        }
    case "lumi-set-root-color":
        guard let hex = args.first else { print("usage: lumi-set-root-color <#RRGGBB>"); break }
        try session.setLumiRootColor(hex: hex)
    case "lumi-set-scale-color":
        guard let hex = args.first else { print("usage: lumi-set-scale-color <#RRGGBB>"); break }
        try session.setLumiScaleColor(hex: hex)
    case "lumi-set-brightness":
        guard let percentage = args.first.flatMap(Int.init) else { print("usage: lumi-set-brightness <0-100>"); break }
        try session.setLumiBrightness(percentage)
    case "lumi-auto-run":
        guard let arg = args.first?.lowercased() else { print("usage: lumi-auto-run on|off"); break }
        try session.setLumiAutoPropagateRunMode(arg == "on")
    case "lumi-auto-guide":
        guard let arg = args.first?.lowercased() else { print("usage: lumi-auto-guide on|off"); break }
        try session.setLumiAutoPropagateGuideMode(arg == "on")
    case "refresh-midi":
        session.refreshTracks()
        print("Liste des instruments MIDI rafraichie.")
        printTracks()
    case "track":
        guard args.count >= 2, let id = parseTrackID(args[0]) else {
            print("usage: track <id> on|off | track <id> son on|off | track <id> instrument <n|nom> | track <id> mode <mode>")
            print("   id: midi, midi:<n> (mode individuel), clavier, micro")
            break
        }
        switch args[1].lowercased() {
        case "on":
            try session.startTrack(id)
            if id == .computerKeyboard { computerKeyboardSourceActive = true }
            pollLogWhileListening()
            promptClaimFreeSceneRoleIfNeeded(for: id)
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
        case "mode":
            guard args.count >= 3, let mode = MicrophoneRecognitionMode(wireValueText: args[2]) else {
                print("usage: track micro mode mono-heuristique|mono-hps|poly-latched[:N]|poly-glissant[:K]")
                break
            }
            try session.setMicrophoneRecognitionMode(mode, for: id)
        default:
            print("usage: track <id> on|off | track <id> son on|off | track <id> instrument <n|nom> | track <id> mode <mode>")
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
    case "lumi-guide":
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        guard args.count >= 8,
              let tonic = noteNames.firstIndex(where: { $0.caseInsensitiveCompare(args[0]) == .orderedSame }),
              let rootR = UInt8(args[2]), let rootG = UInt8(args[3]), let rootB = UInt8(args[4]),
              let scaleR = UInt8(args[5]), let scaleG = UInt8(args[6]), let scaleB = UInt8(args[7])
        else {
            print("usage: lumi-guide <tonique C..B> <gamme, ex: ionian> <rootR> <rootG> <rootB> <scaleR> <scaleG> <scaleB> [luminosite 0-100]")
            break
        }
        let brightness = args.count >= 9 ? (Int(args[8]) ?? 100) : 100
        try session.pushLumiGuideMap(
            mode: ModeReference(tonic: tonic, scaleID: args[1]),
            rootColor: (red: rootR, green: rootG, blue: rootB),
            scaleColor: (red: scaleR, green: scaleG, blue: scaleB),
            brightnessPercentage: brightness
        )
    case "lumi-run":
        if args.first == "stop" {
            session.stopLumiLiveDisplay()
            break
        }
        guard args.count >= 6,
              let rootR = UInt8(args[0]), let rootG = UInt8(args[1]), let rootB = UInt8(args[2]),
              let scaleR = UInt8(args[3]), let scaleG = UInt8(args[4]), let scaleB = UInt8(args[5])
        else {
            print("usage: lumi-run <rootR> <rootG> <rootB> <scaleR> <scaleG> <scaleB> [luminosite 0-100]")
            print("       lumi-run stop")
            break
        }
        let brightness = args.count >= 7 ? (Int(args[6]) ?? 100) : 100
        try session.startLumiLiveDisplay(
            rootColor: (red: rootR, green: rootG, blue: rootB),
            scaleColor: (red: scaleR, green: scaleG, blue: scaleB),
            brightnessPercentage: brightness
        )
    case "lumi-guide-sync":
        if args.first == "stop" {
            session.stopLumiGuideDisplay()
            break
        }
        guard args.count >= 6,
              let rootR = UInt8(args[0]), let rootG = UInt8(args[1]), let rootB = UInt8(args[2]),
              let scaleR = UInt8(args[3]), let scaleG = UInt8(args[4]), let scaleB = UInt8(args[5])
        else {
            print("usage: lumi-guide-sync <rootR> <rootG> <rootB> <scaleR> <scaleG> <scaleB> [luminosite 0-100]")
            print("       lumi-guide-sync stop")
            break
        }
        let brightness = args.count >= 7 ? (Int(args[6]) ?? 100) : 100
        try session.startLumiGuideDisplay(
            rootColor: (red: rootR, green: rootG, blue: rootB),
            scaleColor: (red: scaleR, green: scaleG, blue: scaleB),
            brightnessPercentage: brightness
        )
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
        print(L10n.string(.pastePasteText, session.currentLanguage))
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
    case "settings":
        guard let folder = args.first else { print("usage: settings <dossier>"); break }
        try session.setSettingsFolder(folder)
        drainLog() // flush "Dossier de reglages: ..." before the numbered lists
        print("Connexions LLM:")
        for (index, name) in session.llmConnections.enumerated() { print("  \(index + 1). \(name)") }
        print("Palettes de couleur:")
        for (index, palette) in session.colorPalettes.enumerated() { print("  \(index + 1). \(palette.name)") }
        print("Progressions d'accords:")
        for (index, template) in session.chordProgressionTemplates.enumerated() { print("  \(index + 1). \(template.name)") }
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
        print(L10n.string(.pastePasteFraming, session.currentLanguage))
        var lines: [String] = []
        while let textLine = readLine(), !textLine.isEmpty { lines.append(textLine) }
        session.setTextFramingSentence(lines.joined(separator: "\n"))
    case "set-soundtrack-framing":
        print(L10n.string(.pastePasteFraming, session.currentLanguage))
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
            print("usage: guide-add-mode <tonique> <id-gamme> [progression d'accords: n ou nom]"); break
        }
        let reference = ModeReference(tonic: tonic.value, scaleID: args[1])
        let progression = args.count >= 3 ? resolvedChordProgressionTemplate(args[2]) : nil
        try session.addGuideStep(reference, chordProgression: progression)
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
    case "scene-new":
        guard !args.isEmpty else { print("usage: scene-new <titre>"); break }
        session.newScene(title: args.joined(separator: " "))
    case "scene-roles":
        printNumberedSceneRoles()
    case "scene-role-add":
        guard !args.isEmpty else { print("usage: scene-role-add <nom>"); break }
        _ = try session.addSceneRole(name: args.joined(separator: " "))
    case "scene-role-sound":
        guard let roleID = args.first.flatMap(resolvedSceneRoleID) else {
            print("usage: scene-role-sound <role> <son|vide>"); break
        }
        try session.setSceneRoleSound(roleID, soundName: args.count >= 2 ? args[1] : nil)
    case "scene-role-listen":
        guard args.count >= 2, let roleID = resolvedSceneRoleID(args[0]) else {
            print("usage: scene-role-listen <role> on|off"); break
        }
        try session.setSceneRoleListening(roleID, isListening: args[1].lowercased() == "on")
    case "scene-role-attach":
        guard args.count >= 2, let roleID = resolvedSceneRoleID(args[0]),
              let trackID = parseTrackID(resolvedTrackIDText(args[1]))
        else {
            print("usage: scene-role-attach <role> <id-instrument>"); break
        }
        try session.attachInstrument(trackID, toRole: roleID)
    case "scene-role-detach":
        guard let roleID = args.first.flatMap(resolvedSceneRoleID) else {
            print("usage: scene-role-detach <role>"); break
        }
        try session.detachInstrument(fromRole: roleID)
    case "scene-role-remove":
        guard let roleID = args.first.flatMap(resolvedSceneRoleID) else {
            print("usage: scene-role-remove <role>"); break
        }
        try session.removeSceneRole(roleID)
    case "language":
        guard let arg = args.first?.lowercased(), let lang = AppLanguage(rawValue: arg) else {
            print("usage: language fr|en|de"); break
        }
        try session.setLanguage(lang)
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
    let text = promptLine(L10n.string(.promptTonPseudo, session.currentLanguage, session.localClientName)) ?? ""
    if !text.isEmpty { session.localClientName = text }
}

/// The `console` screen's dropdown menus — each item just calls `executeCommand`, prompting
/// first for a folder/name/choice where needed. Defined after `executeCommand` (which they
/// all call) but before it's used in `runConsoleScreen`. A function of the current language
/// (not a stored `let`) so every redraw tick rebuilds it from whatever `session.currentLanguage`
/// currently is — see `L10n`/`L10nTable` (`AppCore`) for the FR/EN/DE text itself; this is the
/// single source of truth the web console's `MENU_ACTIONS` also looks up into (see
/// `WebConsole/StaticAssets.swift`), so a label never needs hand-copying per surface per
/// language. Business-logic wiring (which action a label triggers, what it prompts for) is
/// untouched — only the label/header/prompt STRINGS now come from `L10n.string` instead of a
/// literal.
func buildMenuCategories(for lang: AppLanguage) -> [MenuCategory] {
    [
    // Mnemonic "S" (not the first letter) to avoid colliding with "Jam Session"'s "J" — same
    // trick already used for "IA" vs "Instrument", see renderMenuBar's doc comment.
    MenuCategory(mnemonic: "S", title: L10n.string(.catJamShack, lang), items: [
        MenuItem(label: L10n.string(.menuInfos, lang)) { try executeCommand("status", []) },
        MenuItem(label: L10n.string(.menuAide, lang)) { try executeCommand("help", []) },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuChoisirDossierMorceaux, lang)) {
            guard let folder = promptLine(L10n.string(.promptDossierMorceaux, lang)), !folder.isEmpty else { return }
            try executeCommand("pieces", [folder])
        },
        MenuItem(label: L10n.string(.menuChoisirDossierSons, lang)) {
            guard let folder = promptLine(L10n.string(.promptDossierSons, lang)), !folder.isEmpty else { return }
            try executeCommand("samples", [folder])
        },
        MenuItem(label: L10n.string(.menuChoisirDossierSoundtracks, lang)) {
            guard let folder = promptLine(L10n.string(.promptDossierSoundtracks, lang)), !folder.isEmpty else { return }
            try executeCommand("soundtracks", [folder])
        },
        MenuItem(label: L10n.string(.menuChoisirDossierGuides, lang)) {
            guard let folder = promptLine(L10n.string(.promptDossierGuides, lang)), !folder.isEmpty else { return }
            try executeCommand("guides", [folder])
        },
        MenuItem(label: L10n.string(.menuChoisirDossierScenes, lang)) {
            guard let folder = promptLine(L10n.string(.promptDossierScenes, lang)), !folder.isEmpty else { return }
            try executeCommand("scenes", [folder])
        },
        MenuItem(label: L10n.string(.menuChoisirDossierReglages, lang)) {
            guard let folder = promptLine(L10n.string(.promptDossierReglages, lang)), !folder.isEmpty else { return }
            try executeCommand("settings", [folder])
        },
        MenuItem(label: L10n.string(.menuChoisirDossierCompositionIA, lang)) {
            guard let folder = promptLine(L10n.string(.promptDossierCompositionIA, lang)), !folder.isEmpty else { return }
            try executeCommand("prompts", [folder])
        },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuChoisirConnexionLLM, lang)) {
            guard !session.llmConnections.isEmpty else { print("Choisis d'abord un dossier de reglages (menu JamShack)."); return }
            for (index, name) in session.llmConnections.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine(L10n.string(.promptUtiliserQuelleConnexion, lang)), !choice.isEmpty else { return }
            try executeCommand("use-llm", [choice])
        },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuChoisirPalette, lang)) {
            for (index, palette) in session.colorPalettes.enumerated() {
                let marker = index == session.activeColorPaletteIndex ? " (active)" : ""
                print("  \(index + 1). \(palette.name)\(marker)")
            }
            guard let choice = promptLine(L10n.string(.promptUtiliserQuellePalette, lang)), !choice.isEmpty else { return }
            try executeCommand("use-palette", [choice])
        },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuMidiModeFusionne, lang)) { try executeCommand("midi-mode", ["fusionne"]) },
        MenuItem(label: L10n.string(.menuMidiModeIndividuel, lang)) { try executeCommand("midi-mode", ["individuel"]) },
        MenuItem(label: L10n.string(.menuRefreshMidi, lang)) { try executeCommand("refresh-midi", []) },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuDemarrerConsoleWeb, lang)) {
            let portText = promptLine(L10n.string(.promptPortDefaut8080, lang)) ?? ""
            try executeCommand("web-console", [portText.isEmpty ? "8080" : portText])
        },
        MenuItem(label: L10n.string(.menuArreterConsoleWeb, lang)) { try executeCommand("web-console", ["stop"]) },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuDemarrerClavierVirtuel, lang)) {
            let portText = promptLine(L10n.string(.promptPortDefaut8081, lang)) ?? ""
            try executeCommand("virtual-keyboard", [portText.isEmpty ? "8081" : portText])
        },
        MenuItem(label: L10n.string(.menuArreterClavierVirtuel, lang)) { try executeCommand("virtual-keyboard", ["stop"]) },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuLangueFr, lang)) { try executeCommand("language", ["fr"]) },
        MenuItem(label: L10n.string(.menuLangueEn, lang)) { try executeCommand("language", ["en"]) },
        MenuItem(label: L10n.string(.menuLangueDe, lang)) { try executeCommand("language", ["de"]) },
        MenuItem.separator,
        MenuItem.header(L10n.string(.headerReglagesLumi, lang)),
        MenuItem(label: L10n.string(.menuLumiCouleurRacine, lang)) {
            guard let hex = promptLine(L10n.string(.promptLumiCouleurRacineHex, lang)), !hex.isEmpty else { return }
            try executeCommand("lumi-set-root-color", [hex])
        },
        MenuItem(label: L10n.string(.menuLumiCouleurGamme, lang)) {
            guard let hex = promptLine(L10n.string(.promptLumiCouleurGammeHex, lang)), !hex.isEmpty else { return }
            try executeCommand("lumi-set-scale-color", [hex])
        },
        MenuItem(label: L10n.string(.menuLumiLuminosite, lang)) {
            guard let text = promptLine(L10n.string(.promptLumiLuminosite0100, lang)), !text.isEmpty else { return }
            try executeCommand("lumi-set-brightness", [text])
        },
        MenuItem(label: L10n.string(.menuLumiAutoRunActiver, lang)) { try executeCommand("lumi-auto-run", ["on"]) },
        MenuItem(label: L10n.string(.menuLumiAutoRunDesactiver, lang)) { try executeCommand("lumi-auto-run", ["off"]) },
        MenuItem(label: L10n.string(.menuLumiAutoGuideActiver, lang)) { try executeCommand("lumi-auto-guide", ["on"]) },
        MenuItem(label: L10n.string(.menuLumiAutoGuideDesactiver, lang)) { try executeCommand("lumi-auto-guide", ["off"]) },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuQuitter, lang)) { try executeCommand("quit", []) },
    ]),
    MenuCategory(mnemonic: "n", title: L10n.string(.catScene, lang), items: [
        MenuItem(label: L10n.string(.menuListerInstruments, lang)) { try executeCommand("scene-tree", []) },
        MenuItem(label: L10n.string(.menuActiverInstrument, lang)) {
            printNumberedTracks()
            guard let choice = promptLine(L10n.string(.promptActiverQuelInstrument, lang)), !choice.isEmpty else { return }
            let resolvedID = resolvedTrackIDText(choice)
            try executeCommand("track", [resolvedID, "on"])
            let soundAnswer = promptLine(L10n.string(.promptActiverAussiSon, lang)) ?? ""
            if soundAnswer.lowercased().hasPrefix("o") {
                try promptChooseSoundForTrack(resolvedID)
            }
        },
        MenuItem(label: L10n.string(.menuArreterInstrument, lang)) {
            printNumberedTracks()
            guard let choice = promptLine(L10n.string(.promptArreterQuelInstrument, lang)), !choice.isEmpty else { return }
            try executeCommand("track", [resolvedTrackIDText(choice), "off"])
        },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuActiverSonInstrument, lang)) {
            printNumberedTracks()
            guard let choice = promptLine(L10n.string(.promptActiverSonQuelInstrument, lang)), !choice.isEmpty else { return }
            try executeCommand("track", [resolvedTrackIDText(choice), "son", "on"])
        },
        MenuItem(label: L10n.string(.menuDesactiverSonInstrument, lang)) {
            printNumberedTracks()
            guard let choice = promptLine(L10n.string(.promptDesactiverSonQuelInstrument, lang)), !choice.isEmpty else { return }
            try executeCommand("track", [resolvedTrackIDText(choice), "son", "off"])
        },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuChoisirSonPourInstrument, lang)) {
            printNumberedTracks()
            guard let trackChoice = promptLine(L10n.string(.promptPourQuelInstrument, lang)), !trackChoice.isEmpty else { return }
            try promptChooseSoundForTrack(resolvedTrackIDText(trackChoice))
        },
        MenuItem(label: L10n.string(.menuChoisirModeReconnaissanceMicro, lang)) {
            printNumberedTracks()
            guard let trackChoice = promptLine(L10n.string(.promptPourQuelInstrument, lang)), !trackChoice.isEmpty else { return }
            try promptChooseRecognitionModeForTrack(resolvedTrackIDText(trackChoice))
        },
        MenuItem.header(L10n.string(.headerFichierDeScene, lang)),
        MenuItem(label: L10n.string(.menuSauvegarderScene, lang)) {
            guard let name = promptLine(L10n.string(.promptNomDeLaScene, lang)), !name.isEmpty else { return }
            try executeCommand("save-scene", [name])
        },
        MenuItem(label: L10n.string(.menuChargerScene, lang)) {
            guard !session.sceneFiles.isEmpty else { print("Choisis d'abord un dossier de scenes (menu JamShack)."); return }
            for (index, name) in session.sceneFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine(L10n.string(.promptChargerQuelleScene, lang)), !choice.isEmpty else { return }
            try executeCommand("use-scene", [choice])
        },
        MenuItem.header(L10n.string(.headerRoles, lang)),
        MenuItem(label: L10n.string(.menuNouvelleScene, lang)) {
            guard let title = promptLine(L10n.string(.promptTitreDeLaScene, lang)), !title.isEmpty else { return }
            try executeCommand("scene-new", [title])
        },
        MenuItem(label: L10n.string(.menuListerRoles, lang)) { try executeCommand("scene-roles", []) },
        MenuItem(label: L10n.string(.menuAjouterRole, lang)) {
            guard let name = promptLine(L10n.string(.promptNomDuRole, lang)), !name.isEmpty else { return }
            try executeCommand("scene-role-add", [name])
        },
        MenuItem(label: L10n.string(.menuAttacherInstrumentARole, lang)) {
            printNumberedSceneRoles()
            guard let roleChoice = promptLine(L10n.string(.promptQuelRole, lang)), !roleChoice.isEmpty else { return }
            printNumberedTracks()
            guard let trackChoice = promptLine(L10n.string(.promptQuelInstrument, lang)), !trackChoice.isEmpty else { return }
            try executeCommand("scene-role-attach", [roleChoice, resolvedTrackIDText(trackChoice)])
        },
        MenuItem(label: L10n.string(.menuDetacherRole, lang)) {
            printNumberedSceneRoles()
            guard let roleChoice = promptLine(L10n.string(.promptQuelRole, lang)), !roleChoice.isEmpty else { return }
            try executeCommand("scene-role-detach", [roleChoice])
        },
        MenuItem(label: L10n.string(.menuChoisirSonDunRole, lang)) {
            printNumberedSceneRoles()
            guard let roleChoice = promptLine(L10n.string(.promptQuelRole, lang)), !roleChoice.isEmpty else { return }
            guard !session.sampleFiles.isEmpty else { print("Choisis d'abord un dossier de sons (menu JamShack)."); return }
            for (index, name) in session.sampleFiles.enumerated() { print("  \(index + 1). \(name)") }
            let soundChoice = promptLine(L10n.string(.promptQuelSonVideAucun, lang)) ?? ""
            let soundName = soundChoice.isEmpty ? nil : (Int(soundChoice).flatMap { session.sampleFiles.indices.contains($0 - 1) ? session.sampleFiles[$0 - 1] : nil } ?? soundChoice)
            try executeCommand("scene-role-sound", soundName.map { [roleChoice, $0] } ?? [roleChoice])
        },
    ]),
    MenuCategory(mnemonic: "G", title: L10n.string(.catGuideMusicaux, lang), items: [
        MenuItem(label: L10n.string(.menuVoirGuideMusical, lang)) { try executeCommand("guide", []) },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuNouveauGuideMusical, lang)) {
            guard let title = promptLine(L10n.string(.promptTitreDeLaSequence, lang)), !title.isEmpty else { return }
            try executeCommand("guide-new", [title])
            // Keep prompting for one more step until the user leaves the tonic blank,
            // instead of a single add-then-back-to-menu round trip — building a sequence of
            // several modes otherwise means reopening this same menu item repeatedly.
            while true {
                guard let tonicText = promptLine(L10n.string(.promptTonique1, lang)), !tonicText.isEmpty else { break }
                printNumberedScales()
                guard let scaleText = promptLine(L10n.string(.promptIdGamme, lang)), !scaleText.isEmpty else { break }
                printNumberedChordProgressionTemplates()
                let progressionText = promptLine(L10n.string(.promptProgressionAccords, lang)) ?? ""
                do {
                    try executeCommand("guide-add-mode", [tonicText, resolvedScaleID(scaleText), progressionText])
                } catch {
                    print("Erreur: \(error)")
                }
            }
        },
        MenuItem(label: L10n.string(.menuAjouterModeAuGuide, lang)) {
            guard let tonicText = promptLine(L10n.string(.promptTonique2, lang)), !tonicText.isEmpty else { return }
            printNumberedScales()
            guard let scaleText = promptLine(L10n.string(.promptIdGamme, lang)), !scaleText.isEmpty else { return }
            printNumberedChordProgressionTemplates()
            let progressionText = promptLine(L10n.string(.promptProgressionAccords, lang)) ?? ""
            try executeCommand("guide-add-mode", [tonicText, resolvedScaleID(scaleText), progressionText])
        },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuChargerGuideMusical, lang)) {
            guard !session.guideFiles.isEmpty else { print("Choisis d'abord un dossier de guides musicaux."); return }
            for (index, name) in session.guideFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine(L10n.string(.promptChargerQuelleSequence, lang)), !choice.isEmpty else { return }
            try executeCommand("use-guide", [choice])
        },
        MenuItem(label: L10n.string(.menuSauvegarderGuideMusical, lang)) { try executeCommand("save-guide", []) },
        MenuItem(label: L10n.string(.menuSauvegarderGuideMusicalSous, lang)) {
            guard let name = promptLine(L10n.string(.promptNomDeSauvegarde, lang)), !name.isEmpty else { return }
            try executeCommand("save-guide-as", [name])
        },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuDemarrerGuideMusical, lang)) { try executeCommand("guide-start", []) },
        MenuItem(label: L10n.string(.menuArreterGuideMusical, lang)) { try executeCommand("guide-stop", []) },
    ]),
    MenuCategory(mnemonic: "E", title: L10n.string(.catEnregistrement, lang), items: [
        MenuItem(label: L10n.string(.menuDemarrerEnregistrement, lang)) {
            try executeCommand("tracks", [])
            let idsText = promptLine(L10n.string(.promptPistesAEnregistrer, lang)) ?? ""
            try executeCommand("record", ["start"] + idsText.split(separator: " ").map(String.init))
        },
        MenuItem(label: L10n.string(.menuArreterEnregistrement, lang)) { try executeCommand("record", ["stop"]) },
        MenuItem(label: L10n.string(.menuVoirEnregistrement, lang)) { try executeCommand("show-soundtrack", []) },
        MenuItem(label: L10n.string(.menuJouerEnregistrement, lang)) { try executeCommand("play-soundtrack", []) },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuChargerEnregistrement, lang)) {
            guard !session.soundTrackFiles.isEmpty else { print("Choisis d'abord un dossier de soundtracks (menu JamShack)."); return }
            for (index, name) in session.soundTrackFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine(L10n.string(.promptChargerQuelEnregistrement, lang)), !choice.isEmpty else { return }
            try executeCommand("use-soundtrack", [choice])
        },
        MenuItem(label: L10n.string(.menuSauvegarderEnregistrement, lang)) { try executeCommand("save-soundtrack", []) },
        MenuItem(label: L10n.string(.menuSauvegarderEnregistrementSous, lang)) {
            guard let name = promptLine(L10n.string(.promptNomDeSauvegarde, lang)), !name.isEmpty else { return }
            try executeCommand("save-soundtrack-as", [name])
        },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuComposerDepuisEnregistrement, lang)) {
            let titleText = promptLine(L10n.string(.promptNomDuMorceauIA, lang)) ?? ""
            let countText = promptLine(L10n.string(.promptCombienDeCandidats, lang)) ?? ""
            var cmdArgs = [countText.isEmpty ? "1" : countText]
            if !titleText.isEmpty { cmdArgs.append(titleText) }
            try executeCommand("compose-piece-from-soundtrack", cmdArgs)
        },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuVoirPhraseDeCadrage, lang)) { try executeCommand("show-soundtrack-framing", []) },
        MenuItem(label: L10n.string(.menuModifierPhraseDeCadrage, lang)) { try executeCommand("set-soundtrack-framing", []) },
        MenuItem(label: L10n.string(.menuSauvegarderPhraseDeCadrage, lang)) {
            guard let name = promptLine(L10n.string(.promptNomSauvegardePhraseDeCadrage, lang)), !name.isEmpty else { return }
            try executeCommand("save-soundtrack-framing", [name])
        },
        MenuItem(label: L10n.string(.menuChargerPhraseDeCadrage, lang)) {
            guard !session.soundTrackFramingFiles.isEmpty else { print("Choisis d'abord un dossier de composition IA (menu JamShack)."); return }
            for (index, name) in session.soundTrackFramingFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine(L10n.string(.promptChargerQuellePhraseDeCadrage, lang)), !choice.isEmpty else { return }
            try executeCommand("use-soundtrack-framing", [choice])
        },
        MenuItem(label: L10n.string(.menuRevenirPhraseDeCadrageParDefaut, lang)) { try executeCommand("reset-soundtrack-framing", []) },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuVoirIndicationsStyle, lang)) { try executeCommand("show-soundtrack-instructions", []) },
        MenuItem(label: L10n.string(.menuModifierIndicationsStyle, lang)) {
            let text = promptLine(L10n.string(.promptIndicationsDeStyle, lang)) ?? ""
            try executeCommand("set-soundtrack-instructions", text.isEmpty ? [] : [text])
        },
        MenuItem(label: L10n.string(.menuSauvegarderIndicationsStyle, lang)) {
            guard let name = promptLine(L10n.string(.promptNomSauvegardeIndications, lang)), !name.isEmpty else { return }
            try executeCommand("save-soundtrack-instructions", [name])
        },
        MenuItem(label: L10n.string(.menuChargerIndicationsStyle, lang)) {
            guard !session.soundTrackInstructionsFiles.isEmpty else { print("Choisis d'abord un dossier de composition IA (menu JamShack)."); return }
            for (index, name) in session.soundTrackInstructionsFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine(L10n.string(.promptChargerQuellesIndications, lang)), !choice.isEmpty else { return }
            try executeCommand("use-soundtrack-instructions", [choice])
        },
        MenuItem(label: L10n.string(.menuRevenirIndicationsStyleParDefaut, lang)) { try executeCommand("reset-soundtrack-instructions", []) },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuVoirPromptComposition, lang)) { try executeCommand("show-soundtrack-prompt", []) },
        MenuItem(label: L10n.string(.menuExporterPromptComposition, lang)) {
            guard let name = promptLine(L10n.string(.promptNomExportPrompt, lang)), !name.isEmpty else { return }
            try executeCommand("export-soundtrack-prompt", [name])
        },
    ]),
    MenuCategory(mnemonic: "M", title: L10n.string(.catMorceaux, lang), items: [
        MenuItem(label: L10n.string(.menuEcouterMorceau, lang)) { try executeCommand("play", []) },
        MenuItem(label: L10n.string(.menuVoirMorceau, lang)) { try executeCommand("show-piece", []) },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuChoisirSonLectureMorceau, lang)) {
            guard !session.sampleFiles.isEmpty else { print("Choisis d'abord un dossier de sons (menu JamShack)."); return }
            for (index, name) in session.sampleFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine(L10n.string(.promptChargerQuelSon, lang)), !choice.isEmpty else { return }
            try executeCommand("use-sample", [choice])
        },
        MenuItem(label: L10n.string(.menuChoisirSonDunePiste, lang)) {
            printPieceDetail()
            guard let sectionText = promptLine(L10n.string(.promptQuelleSection, lang)), !sectionText.isEmpty else { return }
            guard let trackText = promptLine(L10n.string(.promptQuellePiste, lang)), !trackText.isEmpty else { return }
            if session.sampleFiles.isEmpty { print("(Astuce: choisis d'abord un dossier de sons, menu JamShack.)") }
            for (index, name) in session.sampleFiles.enumerated() { print("  \(index + 1). \(name)") }
            let instrumentText = promptLine(L10n.string(.promptQuelSonOuVide, lang)) ?? ""
            try executeCommand("set-track-instrument", [sectionText, trackText, instrumentText])
        },
        MenuItem(label: L10n.string(.menuChoisirSonAccordsSection, lang)) {
            printPieceDetail()
            guard let sectionText = promptLine(L10n.string(.promptQuelleSection, lang)), !sectionText.isEmpty else { return }
            if session.sampleFiles.isEmpty { print("(Astuce: choisis d'abord un dossier de sons, menu JamShack.)") }
            for (index, name) in session.sampleFiles.enumerated() { print("  \(index + 1). \(name)") }
            let instrumentText = promptLine(L10n.string(.promptQuelSonOuVide, lang)) ?? ""
            try executeCommand("set-chord-instrument", [sectionText, instrumentText])
        },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuChargerDemo, lang)) { try executeCommand("load-demo", []) },
        MenuItem(label: L10n.string(.menuChargerMorceau, lang)) {
            guard !session.pieceFiles.isEmpty else { print("Choisis d'abord un dossier de morceaux (menu JamShack)."); return }
            for (index, name) in session.pieceFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine(L10n.string(.promptChargerQuelMorceau, lang)), !choice.isEmpty else { return }
            try executeCommand("use-piece", [choice])
        },
        MenuItem(label: L10n.string(.menuSauvegarderMorceau, lang)) { try executeCommand("save", []) },
        MenuItem(label: L10n.string(.menuSauvegarderMorceauSous, lang)) {
            guard let name = promptLine(L10n.string(.promptNomDeSauvegarde, lang)), !name.isEmpty else { return }
            try executeCommand("save-as", [name])
        },
        MenuItem.separator,
        MenuItem.header(L10n.string(.headerAssistantIA, lang)),
    ]),
    MenuCategory(mnemonic: "C", title: L10n.string(.catComposition, lang), items: [
        MenuItem(label: L10n.string(.menuDecrireMorceau, lang)) {
            guard let title = promptLine(L10n.string(.promptTitreDuMorceau, lang)), !title.isEmpty else { return }
            session.setCompositionTitle(title)
            print(L10n.string(.pastePasteDescription, lang))
            var lines: [String] = []
            while let textLine = readLine(), !textLine.isEmpty { lines.append(textLine) }
            session.setSourceText(lines.joined(separator: "\n"))
            let indicationsText = promptLine(L10n.string(.promptIndicationsDeStyle, lang)) ?? ""
            session.setAdditionalCompositionInstructions(indicationsText.isEmpty ? nil : indicationsText)
            try executeCommand("compose", [title])
        },
        MenuItem(label: L10n.string(.menuComposerDepuisDescription, lang)) { try executeCommand("compose", []) },
        MenuItem(label: L10n.string(.menuVoirDescription, lang)) { try executeCommand("show-description", []) },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuChargerDescription, lang)) {
            guard !session.compositionFiles.isEmpty else { print("Choisis d'abord un dossier de composition IA (menu JamShack)."); return }
            for (index, name) in session.compositionFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine(L10n.string(.promptChargerQuelleDescription, lang)), !choice.isEmpty else { return }
            try executeCommand("use-description", [choice])
        },
        MenuItem(label: L10n.string(.menuSauvegarderDescriptionSous, lang)) {
            guard let name = promptLine(L10n.string(.promptNomDeSauvegarde, lang)), !name.isEmpty else { return }
            try executeCommand("save-description-as", [name])
        },
        MenuItem(label: L10n.string(.menuSauvegarderDescription, lang)) { try executeCommand("save-description", []) },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuVoirPhraseDeCadrage, lang)) { try executeCommand("show-text-framing", []) },
        MenuItem(label: L10n.string(.menuModifierPhraseDeCadrage, lang)) { try executeCommand("set-text-framing", []) },
        MenuItem(label: L10n.string(.menuSauvegarderPhraseDeCadrage, lang)) {
            guard let name = promptLine(L10n.string(.promptNomSauvegardePhraseDeCadrage, lang)), !name.isEmpty else { return }
            try executeCommand("save-text-framing", [name])
        },
        MenuItem(label: L10n.string(.menuChargerPhraseDeCadrage, lang)) {
            guard !session.textFramingFiles.isEmpty else { print("Choisis d'abord un dossier de composition IA (menu JamShack)."); return }
            for (index, name) in session.textFramingFiles.enumerated() { print("  \(index + 1). \(name)") }
            guard let choice = promptLine(L10n.string(.promptChargerQuellePhraseDeCadrage, lang)), !choice.isEmpty else { return }
            try executeCommand("use-text-framing", [choice])
        },
        MenuItem(label: L10n.string(.menuRevenirPhraseDeCadrageParDefaut, lang)) { try executeCommand("reset-text-framing", []) },
        MenuItem.separator,
        MenuItem(label: L10n.string(.menuVoirPromptComposition, lang)) { try executeCommand("show-text-prompt", []) },
        MenuItem(label: L10n.string(.menuExporterPromptComposition, lang)) {
            guard let name = promptLine(L10n.string(.promptNomExportPrompt, lang)), !name.isEmpty else { return }
            try executeCommand("export-text-prompt", [name])
        },
    ]),
    MenuCategory(mnemonic: "J", title: L10n.string(.catJamSession, lang), items: [
        MenuItem(label: L10n.string(.menuDemarrerJamSession, lang)) {
            promptForPseudo()
            let portText = promptLine(L10n.string(.promptPortDefaut7777, lang)) ?? ""
            try executeCommand("server", [portText.isEmpty ? "7777" : portText])
        },
        MenuItem(label: L10n.string(.menuArreterJamSession, lang)) { try executeCommand("stop-server", []) },
        MenuItem(label: L10n.string(.menuRejoindreJamSession, lang)) {
            promptForPseudo()
            let host = promptLine(L10n.string(.promptServeurDefautLocalhost, lang)) ?? ""
            let portText = promptLine(L10n.string(.promptPortDefaut7777, lang)) ?? ""
            try executeCommand("client", [host.isEmpty ? "localhost" : host, portText.isEmpty ? "7777" : portText])
        },
        MenuItem(label: L10n.string(.menuTrouverJamSession, lang)) {
            promptForPseudo()
            try executeCommand("discover", [])
        },
        MenuItem(label: L10n.string(.menuQuitterJamSession, lang)) { try executeCommand("disconnect", []) },
    ]),
    ]
}

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

print(L10n.string(.replModeCommand, session.currentLanguage))
print(L10n.string(.replTapeAide, session.currentLanguage))
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
