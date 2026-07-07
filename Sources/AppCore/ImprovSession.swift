import Foundation
import Observation
import MusicTheoryKit
import PieceModel
import SoundTrackModel
import AudioEngine
import MIDIEngine
import RecognitionEngine
import LLMEngine
import NetEngine
import WebConsole

/// The whole app's state and behavior, independent of any presentation layer. A CLI
/// front-end drives this today by calling its methods and reading its published state;
/// a future SwiftUI front-end can bind to the same instance directly (it's `@Observable`)
/// without any of this logic moving or changing.
// `@unchecked Sendable`: mutated from the CLI's main thread and from the MIDI/playback
// callback threads, but never truly concurrently for this tool's single-user REPL usage
// (worst case is an interleaved log line, not corrupted state).
@Observable
public final class ImprovSession: @unchecked Sendable {
    public private(set) var piece: Piece?
    public private(set) var isPlaying = false
    /// The most recent MIDI-shaped event across every track — purely diagnostic (see the
    /// "Dernier evt MIDI" status field); per-track recognition state lives in `tracks`.
    public private(set) var lastMIDIEvent: MIDINoteEvent?
    /// Whether MIDI is currently heard as one merged stream or as one track per visible
    /// port — see `setMIDIFusionMode`. Changing it rebuilds `tracks`.
    public private(set) var midiFusionMode: MIDIFusionMode = .merged
    /// Every live-input track — MIDI (merged or one per port, per `midiFusionMode`), the
    /// computer keyboard, and the microphone — each with its own independent listening/
    /// sound/recognition state. Rebuilt by `refreshTracks()` (also called automatically
    /// whenever `midiFusionMode` changes), which preserves each surviving track's state.
    public private(set) var tracks: [TrackInfo] = []
    /// Whether this session is currently standalone, hosting a collaborative session, or
    /// connected as a client to one — see `startServer`/`connectToServer`.
    public private(set) var networkRole: NetworkRole = .standalone
    /// This participant's identity for the lifetime of this process, sent as `clientID` in
    /// every network message and used to tell participants' tracks apart. Deliberately a
    /// fresh random UUID per launch rather than cached to disk: a machine running both a
    /// server and one or more clients from the same user account (the most likely way to
    /// first try this out — two Terminal windows on one Mac) must not have them collide on
    /// identity, which persisting to a fixed, `$HOME`-wide file would cause. A relaunched
    /// client is simply a "new" participant in this first version.
    public let localClientID: String
    public var localClientName: String = "player"
    /// The current piece's chord progression, flattened to absolute seconds — computed
    /// once when `play()` starts, so a UI can show "where we are" without recomputing it
    /// every frame. Empty when nothing has ever been played.
    public private(set) var playbackTimeline: [TimedChordEvent] = []
    /// Which entry of `playbackTimeline` is sounding right now, updated live while playing;
    /// `nil` before/after playback (or if the piece has no chords at all).
    public private(set) var playbackCurrentChordIndex: Int?
    /// Every pitch currently sounding because of `play()` — the piece-playback counterpart
    /// to each track's `heldPitches` (which only reflects live input), so a UI can draw a
    /// separate keyboard for "what the composition is playing right now".
    public private(set) var playbackHeldPitches: Set<Int> = []
    /// Human-readable status/event lines, oldest first. A CLI prints new entries as they
    /// arrive; a future UI could bind this straight to a scrolling console view.
    public private(set) var log: [String] = []
    /// The folder last listed with `listSampleFiles`, and the `.sf2`/`.dls`/`.aupreset`
    /// files found in it — kept here (not just returned) so a future UI could show a
    /// picker over `sampleFiles` without re-scanning the folder itself. This instrument
    /// list is shared by every track (each picks by name from the same folder) and by the
    /// piece-playback sampler (`use-sample`).
    public private(set) var sampleFolder: String?
    public private(set) var sampleFiles: [String] = []
    /// The folder last listed with `listPieceFiles`, and the `.json` piece files found in
    /// it — mirrors `sampleFolder`/`sampleFiles`.
    public private(set) var pieceFolder: String?
    public private(set) var pieceFiles: [String] = []
    /// Full path the current `piece` was last loaded from or saved to — what a bare
    /// `savePiece()` (no name) re-saves to. `nil` until a load/save-as has happened once.
    public private(set) var currentPieceFilePath: String?
    /// A pasted text (e.g. a poem) to compose a piece from — see `composeFromText()`.
    public private(set) var sourceText: String?
    /// Free-form style guidance (e.g. "romantique, mode mineur") layered on top of
    /// `sourceText` — see `setAdditionalCompositionInstructions`/`currentTextCompositionPrompt`.
    public private(set) var additionalCompositionInstructions: String?
    /// The title set by the "Decrire le morceau..." wizard (or the `title` command) —
    /// purely for display (`show-description`) and for the wizard to pass along to
    /// `compose`/`composeFromText(title:)`; independent of whatever title a *previous*
    /// composition ended up with.
    public private(set) var compositionTitle: String?
    /// The folder last listed with `listLLMConnections`, and the `.json` connection
    /// descriptors found in it — mirrors `sampleFolder`/`sampleFiles`.
    public private(set) var llmConnectionsFolder: String?
    public private(set) var llmConnections: [String] = []
    public private(set) var currentLLMConnection: LLMConnection?
    /// Root folder for saved/loadable composition prompts (see `setPromptsFolder`) — holds
    /// two fixed subfolders, `Texte` and `Soundtrack`, one per composition kind (a piece
    /// composed from pasted text vs. from a `SoundTrack` recording use differently-shaped
    /// prompts, see `LLMPieceComposer.buildPrompt`/`buildPrompt(fromSoundTrack:)`).
    public private(set) var promptsFolder: String?
    public private(set) var textPromptFiles: [String] = []
    public private(set) var soundTrackPromptFiles: [String] = []
    /// A prompt loaded via `useTextCompositionPrompt`/`useSoundTrackCompositionPrompt`,
    /// used verbatim by `composeFromText`/`composeSoundTrackToPieces` instead of building a
    /// fresh one from `sourceText`/`currentSoundTrack` — `nil` (the default) means "build
    /// the prompt normally," reset by `resetTextCompositionPrompt`/`resetSoundTrackCompositionPrompt`.
    public private(set) var activeTextCompositionPrompt: String?
    public private(set) var activeSoundTrackCompositionPrompt: String?
    /// Whether a `SoundTrack` recording is currently underway — see `startRecording`/
    /// `stopRecording`. Deliberately independent of `isPlaying` (that's the *other*,
    /// measure-based playback mode — see `SoundTrack`'s doc comment for why the two don't mix).
    public private(set) var isRecording = false
    /// The most recently recorded or loaded `SoundTrack` — the temporal-recording
    /// counterpart to `piece`. `nil` until a recording finishes or a file is loaded once.
    public private(set) var currentSoundTrack: SoundTrack?
    /// Full path `currentSoundTrack` was last loaded from or saved to — mirrors
    /// `currentPieceFilePath`.
    public private(set) var currentSoundTrackFilePath: String?
    /// The folder last listed with `listSoundTrackFiles`, and the `.json` soundtrack files
    /// found in it — mirrors `pieceFolder`/`pieceFiles`.
    public private(set) var soundTrackFolder: String?
    public private(set) var soundTrackFiles: [String] = []
    /// Whether `playSoundTrack()` is currently playing back `currentSoundTrack` — the
    /// temporal-mode counterpart to `isPlaying` (`Piece` playback). The two are independent
    /// and could in principle run at once, though nothing stops them from clashing audibly
    /// if you actually try that.
    public private(set) var isPlayingSoundTrack = false
    /// Every pitch currently sounding because of `playSoundTrack()` — mirrors
    /// `playbackHeldPitches` for the temporal-recording playback mode.
    public private(set) var soundTrackHeldPitches: Set<Int> = []

    private let player = PiecePlayer()
    private let soundTrackPlayer = SoundTrackPlayer()
    private var midiListeners: [TrackID: MIDIInputListener] = [:]
    private var microphoneListener: MicrophonePitchListener?
    /// One independent chord/mode recognizer per track — created the first time a track
    /// starts listening, kept (not discarded) across a stop so `reset()` on the next start
    /// is the only thing that clears its history.
    private var recognizers: [TrackID: RecognitionEngine] = [:]
    /// One independent sampler per track with sound enabled — see `setSoundEnabled`. Never
    /// present for `.microphone` (enforced there, not here).
    private var samplers: [TrackID: SamplerUnit] = [:]
    /// The microphone's last reported pitches, so `handleDetectedPitches` knows which are
    /// new (need a note-on) and which dropped out (need a note-off) on the next detection
    /// round, instead of resending the same held notes every ~93ms.
    private var lastDetectedMIDIPitches: [TrackID: Set<Int>] = [:]
    /// Serializes every track's recognition-state mutation regardless of which thread calls
    /// in. It used to run wherever the caller happened to be — fine while callers were
    /// effectively serial in practice. The computer-keyboard track's auto-release timers
    /// broke that assumption: typing several notes in quick succession schedules several independent
    /// `DispatchQueue.global()` releases, which can then fire concurrently with each other
    /// and with a fresh `pressKey` — genuine concurrent mutation from multiple threads, and
    /// crashed with a bad pointer dereference in `RecognitionEngine.noteOff` in the field,
    /// not just in testing this time.
    private let liveInputQueue = DispatchQueue(label: "ImprovSession.liveInput")
    /// Bumped on every `play()` call; each playback's scheduled callbacks capture the value
    /// current at the time and check it before mutating state, so a stale callback from an
    /// earlier (or interrupted) playback can never clobber a newer one's `playbackHeldPitches`
    /// / `playbackCurrentChordIndex` / `isPlaying`.
    private var playbackGeneration = 0
    /// Every `play()`-scheduled UI-state update (`playbackHeldPitches`/`playbackCurrentChordIndex`
    /// /`isPlaying`) runs on this one serial queue instead of `.global()`. A piece routinely
    /// has several notes starting at the exact same deadline (a whole chord struck at once),
    /// which `.global()`'s concurrent worker threads would then mutate `playbackHeldPitches`
    /// (a `Set`) from in parallel with no synchronization — a genuine data race that crashed
    /// with memory corruption in testing, not just a benign "worst case interleaved log line"
    /// like the single-threaded live-input writes elsewhere in this class.
    private let playbackStateQueue = DispatchQueue(label: "ImprovSession.playbackState")
    private var netServer: NetworkServer?
    private var netClient: NetworkClient?
    private var syncTimer: DispatchSourceTimer?
    private var webConsoleServer: HTTPServer?
    private var webConsoleRefreshTimer: DispatchSourceTimer?
    /// Guards `webConsoleStateCache` only — a dedicated queue rather than reusing
    /// `liveInputQueue`/`playbackStateQueue`, since this value is written by
    /// `refreshWebConsoleStateSoon()` (its own timer thread) and read by `HTTPServer`'s
    /// internal queue (a request can arrive at any moment) — two threads unrelated to either
    /// of those two, so it needs its own synchronization rather than borrowing theirs.
    private let webConsoleStateQueue = DispatchQueue(label: "ImprovSession.webConsoleState")
    private var webConsoleStateCache = Data("{}".utf8)
    /// `nil` when inactive — the port the web console is currently listening on, for display
    /// (`status`/`config`) and to guard against starting it twice.
    public private(set) var webConsolePort: Int?
    /// Server-side only: which participant (`clientID`) each live TCP connection belongs
    /// to, learned from that connection's `hello` message — needed because `onDisconnect`
    /// only ever reports the connection's own transient id, not the participant identity.
    private var connectionIDToClientID: [String: String] = [:]
    /// Server-side only: each connected participant's chosen display name (`hello`'s
    /// `clientName`) — kept separately from `connectionIDToClientID` because it needs to
    /// survive lookup *by* `clientID` (in `broadcastSyncSoon()`, resolving the owner of every
    /// track, local or remote), not just by connection.
    private var clientIDToClientName: [String: String] = [:]
    /// When set, `startRecording` is underway — the moment it started (a monotonic
    /// `DispatchTime`, not a wall-clock `Date`, since only elapsed time matters) and the
    /// title/track filter given at the time. All touched from `updateRecognitionState`'s
    /// per-event capture (see there), so mutated only inside `liveInputQueue.sync`, same
    /// contract as every other piece of state that function touches.
    private var recordingStartTime: DispatchTime?
    private var recordingTitle: String?
    /// `nil` means "every currently-listening local track" — see `startRecording`.
    private var recordingTrackFilter: Set<TrackID>?
    private var recordingEvents: [RecordedNoteEvent] = []
    /// Same role as `playbackGeneration`, for `playSoundTrack()` — guards against a second
    /// `playSoundTrack()` call's scheduled callbacks clobbering a newer call's state.
    private var soundTrackPlaybackGeneration = 0

    public enum SessionError: Error, CustomStringConvertible {
        case noPieceLoaded
        case noSampleFolderListed
        case invalidSampleIndex
        case noPieceFolderListed
        case invalidPieceIndex
        case noCurrentPieceFile
        case noLLMConnectionsFolderListed
        case invalidLLMConnectionIndex
        case noSourceText
        case noLLMConnectionSelected
        case llmComposeFailed([String])
        case unknownTrack(String)
        case trackCannotHaveSound
        case remoteTrackListeningIsNotLocal
        case networkRoleAlreadyActive
        case alreadyRecording
        case notRecording
        case noSoundTrackRecorded
        case noSoundTrackFolderListed
        case invalidSoundTrackIndex
        case noCurrentSoundTrackFile
        case invalidPieceSectionIndex
        case invalidPieceTrackIndex
        case noPromptsFolderListed
        case invalidTextPromptIndex
        case invalidSoundTrackPromptIndex
        case webConsoleAlreadyActive
        public var description: String {
            switch self {
            case .noPieceLoaded: return "no piece loaded — try 'load-demo' or 'load <path>'"
            case .noSampleFolderListed: return "no sample folder listed yet — try 'samples <folder>' first"
            case .invalidSampleIndex: return "no sample at that index"
            case .noPieceFolderListed: return "no piece folder listed yet — try 'pieces <folder>' first"
            case .invalidPieceIndex: return "no piece at that index"
            case .noCurrentPieceFile: return "this piece was never loaded from or saved to a file — try 'save-as <name>'"
            case .noLLMConnectionsFolderListed: return "no LLM connections folder listed yet — try 'llm-connections <folder>' first"
            case .invalidLLMConnectionIndex: return "no LLM connection at that index"
            case .noSourceText: return "no source text set — try 'paste-text' first"
            case .noLLMConnectionSelected: return "no LLM connection selected — try 'use-llm <n|name>' first"
            case .llmComposeFailed(let warnings): return "composition failed: \(warnings.joined(separator: "; "))"
            case .unknownTrack(let text): return "no such track '\(text)' — try 'tracks' first"
            case .trackCannotHaveSound: return "this track can't produce sound (the microphone is never sounded through the app, to avoid feedback)"
            case .remoteTrackListeningIsNotLocal: return "this track belongs to another participant — its listening state is controlled on their machine, not this one"
            case .networkRoleAlreadyActive: return "already running as a server or connected as a client — disconnect/stop first"
            case .alreadyRecording: return "already recording — try 'stopRecording' first"
            case .notRecording: return "not currently recording"
            case .noSoundTrackRecorded: return "no soundtrack recorded or loaded yet — try 'startRecording' or load one"
            case .noSoundTrackFolderListed: return "no soundtrack folder listed yet — try 'listSoundTrackFiles' first"
            case .invalidSoundTrackIndex: return "no soundtrack at that index"
            case .noCurrentSoundTrackFile: return "this soundtrack was never loaded from or saved to a file — try saving with an explicit name"
            case .invalidPieceSectionIndex: return "no section at that index — try 'show-piece' first"
            case .invalidPieceTrackIndex: return "no track at that index in that section — try 'show-piece' first"
            case .noPromptsFolderListed: return "no prompts folder listed yet — try 'prompts <folder>' first"
            case .invalidTextPromptIndex: return "no text prompt at that index"
            case .invalidSoundTrackPromptIndex: return "no soundtrack prompt at that index"
            case .webConsoleAlreadyActive: return "web console already running — stop it first"
            }
        }
    }

    public init() {
        localClientID = UUID().uuidString
        refreshTracks()
    }

    public func start() throws {
        try player.start()
        try soundTrackPlayer.start()
        append("Audio engine started.")
    }

    public func loadDemoPiece() {
        piece = Self.iiVIDemoPiece()
        append("Loaded demo piece: \(piece!.title)")
    }

    /// Starts a blank piece (no sections yet) — the entry point for composing one, by hand
    /// or via `composeFromText()`, rather than loading an existing file.
    public func newPiece(title: String, tempoBPM: Double = 100, key: ModeReference = ModeReference(tonic: 0, scaleID: "ionian")) {
        piece = Piece(title: title, tempoBPM: tempoBPM, key: key)
        currentPieceFilePath = nil
        append("New piece created: \(title)")
    }

    public func setSourceText(_ text: String) {
        sourceText = text
        append("Source text set (\(text.count) characters).")
    }

    /// `nil`/empty clears it — same "no lingering half-set state" convention as every other
    /// optional session field cleared by passing an empty string through the CLI.
    public func setAdditionalCompositionInstructions(_ text: String?) {
        additionalCompositionInstructions = (text?.isEmpty ?? true) ? nil : text
        append(additionalCompositionInstructions == nil
            ? "Indications de style effacees."
            : "Indications de style: \(additionalCompositionInstructions!)")
    }

    /// `nil`/empty clears it — same convention as `setAdditionalCompositionInstructions`.
    public func setCompositionTitle(_ text: String?) {
        compositionTitle = (text?.isEmpty ?? true) ? nil : text
        append(compositionTitle == nil ? "Titre du morceau efface." : "Titre du morceau: \(compositionTitle!)")
    }

    private static let supportedLLMConnectionExtensions: Set<String> = ["json"]

    /// Scans `folderPath` for `.json` LLM connection descriptors — mirrors `listSampleFiles`.
    public func listLLMConnections(in folderPath: String) throws {
        let folderURL = URL(fileURLWithPath: folderPath)
        let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        llmConnectionsFolder = folderPath
        llmConnections = contents
            .filter { Self.supportedLLMConnectionExtensions.contains($0.pathExtension.lowercased()) }
            .map(\.lastPathComponent)
            .sorted()
        append(llmConnections.isEmpty
            ? "No .json LLM connection files found in \(folderPath)."
            : "Found \(llmConnections.count) LLM connection(s) in \(folderPath).")
    }

    public func useLLMConnection(named name: String) throws {
        guard let llmConnectionsFolder else { throw SessionError.noLLMConnectionsFolderListed }
        let url = URL(fileURLWithPath: llmConnectionsFolder).appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        let connection = try JSONDecoder().decode(LLMConnection.self, from: data)
        currentLLMConnection = connection
        append("Using LLM connection: \(connection.name) (\(connection.provider), model \(connection.model))")
    }

    /// Convenience over `useLLMConnection(named:)` using the 0-based position in `llmConnections`.
    public func useLLMConnection(atIndex index: Int) throws {
        guard llmConnections.indices.contains(index) else { throw SessionError.invalidLLMConnectionIndex }
        try useLLMConnection(named: llmConnections[index])
    }

    // MARK: - Composition prompts (preview, save/load)

    private static let promptsTextSubfolder = "Texte"
    private static let promptsSoundTrackSubfolder = "Soundtrack"

    /// The exact prompt `composeFromText()` would send right now: `activeTextCompositionPrompt`
    /// if one was loaded via `useTextCompositionPrompt`, otherwise freshly built from
    /// `sourceText` (plus `additionalCompositionInstructions`, if any) — the same resolution
    /// `composeFromText()` itself uses, exposed so a caller (e.g. "show the prompt" in the
    /// UI) can see it without triggering a real network call. A loaded override is used
    /// verbatim — `additionalCompositionInstructions` only ever layers onto a freshly built
    /// prompt, same as `sourceText` itself doesn't apply once an override is active.
    public func currentTextCompositionPrompt() throws -> String {
        if let activeTextCompositionPrompt { return activeTextCompositionPrompt }
        guard let sourceText else { throw SessionError.noSourceText }
        return LLMPieceComposer.buildPrompt(sourceText: sourceText, additionalInstructions: additionalCompositionInstructions)
    }

    /// The `composeSoundTrackToPieces()` counterpart of `currentTextCompositionPrompt()`.
    public func currentSoundTrackCompositionPrompt() throws -> String {
        if let activeSoundTrackCompositionPrompt { return activeSoundTrackCompositionPrompt }
        guard let currentSoundTrack else { throw SessionError.noSoundTrackRecorded }
        return LLMPieceComposer.buildPrompt(fromSoundTrack: currentSoundTrack)
    }

    /// Points at a root folder for saved prompts, creating its two fixed subfolders
    /// (`Texte`/`Soundtrack`) if they don't exist yet, and lists whatever's already in each.
    public func setPromptsFolder(_ folderPath: String) throws {
        let root = URL(fileURLWithPath: folderPath)
        let textURL = root.appendingPathComponent(Self.promptsTextSubfolder)
        let soundTrackURL = root.appendingPathComponent(Self.promptsSoundTrackSubfolder)
        try FileManager.default.createDirectory(at: textURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: soundTrackURL, withIntermediateDirectories: true)
        promptsFolder = folderPath
        textPromptFiles = try FileManager.default.contentsOfDirectory(at: textURL, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent).sorted()
        soundTrackPromptFiles = try FileManager.default.contentsOfDirectory(at: soundTrackURL, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent).sorted()
        append("Dossier de prompts: \(folderPath) (\(textPromptFiles.count) texte, \(soundTrackPromptFiles.count) soundtrack).")
    }

    /// Saves `currentTextCompositionPrompt()` (whatever would actually be sent right now) as
    /// a new file under the `Texte` subfolder.
    public func saveTextCompositionPrompt(as name: String) throws {
        guard let promptsFolder else { throw SessionError.noPromptsFolderListed }
        let prompt = try currentTextCompositionPrompt()
        let fileName = name.hasSuffix(".txt") ? name : name + ".txt"
        let url = URL(fileURLWithPath: promptsFolder).appendingPathComponent(Self.promptsTextSubfolder).appendingPathComponent(fileName)
        try prompt.write(to: url, atomically: true, encoding: .utf8)
        if !textPromptFiles.contains(fileName) { textPromptFiles = (textPromptFiles + [fileName]).sorted() }
        append("Prompt (texte) sauvegarde: \(url.path).")
    }

    /// The `Soundtrack` subfolder counterpart of `saveTextCompositionPrompt(as:)`.
    public func saveSoundTrackCompositionPrompt(as name: String) throws {
        guard let promptsFolder else { throw SessionError.noPromptsFolderListed }
        let prompt = try currentSoundTrackCompositionPrompt()
        let fileName = name.hasSuffix(".txt") ? name : name + ".txt"
        let url = URL(fileURLWithPath: promptsFolder).appendingPathComponent(Self.promptsSoundTrackSubfolder).appendingPathComponent(fileName)
        try prompt.write(to: url, atomically: true, encoding: .utf8)
        if !soundTrackPromptFiles.contains(fileName) { soundTrackPromptFiles = (soundTrackPromptFiles + [fileName]).sorted() }
        append("Prompt (soundtrack) sauvegarde: \(url.path).")
    }

    /// Loads a previously saved text prompt and makes it `activeTextCompositionPrompt` —
    /// `composeFromText()` will send it verbatim (no `sourceText` involved) until
    /// `resetTextCompositionPrompt()` is called.
    public func useTextCompositionPrompt(named name: String) throws {
        guard let promptsFolder else { throw SessionError.noPromptsFolderListed }
        let url = URL(fileURLWithPath: promptsFolder).appendingPathComponent(Self.promptsTextSubfolder).appendingPathComponent(name)
        activeTextCompositionPrompt = try String(contentsOf: url, encoding: .utf8)
        append("Prompt (texte) charge depuis \(url.path) — utilise pour la prochaine composition.")
    }

    /// Convenience over `useTextCompositionPrompt(named:)` using the 0-based position in `textPromptFiles`.
    public func useTextCompositionPrompt(atIndex index: Int) throws {
        guard textPromptFiles.indices.contains(index) else { throw SessionError.invalidTextPromptIndex }
        try useTextCompositionPrompt(named: textPromptFiles[index])
    }

    /// The `Soundtrack` subfolder counterpart of `useTextCompositionPrompt(named:)`.
    public func useSoundTrackCompositionPrompt(named name: String) throws {
        guard let promptsFolder else { throw SessionError.noPromptsFolderListed }
        let url = URL(fileURLWithPath: promptsFolder).appendingPathComponent(Self.promptsSoundTrackSubfolder).appendingPathComponent(name)
        activeSoundTrackCompositionPrompt = try String(contentsOf: url, encoding: .utf8)
        append("Prompt (soundtrack) charge depuis \(url.path) — utilise pour la prochaine composition.")
    }

    /// Convenience over `useSoundTrackCompositionPrompt(named:)` using the 0-based position in `soundTrackPromptFiles`.
    public func useSoundTrackCompositionPrompt(atIndex index: Int) throws {
        guard soundTrackPromptFiles.indices.contains(index) else { throw SessionError.invalidSoundTrackPromptIndex }
        try useSoundTrackCompositionPrompt(named: soundTrackPromptFiles[index])
    }

    /// Clears `activeTextCompositionPrompt` — `composeFromText()` goes back to building a
    /// fresh prompt from `sourceText` every time.
    public func resetTextCompositionPrompt() {
        activeTextCompositionPrompt = nil
        append("Prompt (texte) : retour au prompt par defaut.")
    }

    /// The `composeSoundTrackToPieces()` counterpart of `resetTextCompositionPrompt()`.
    public func resetSoundTrackCompositionPrompt() {
        activeSoundTrackCompositionPrompt = nil
        append("Prompt (soundtrack) : retour au prompt par defaut.")
    }

    /// Sends `sourceText` to the selected LLM connection and, if the response survives
    /// theory-library validation (see `LLMPieceComposer`), replaces `piece` with the
    /// composed result. Any dropped/invalid parts of the response are logged as warnings
    /// either way — this never injects an unvalidated suggestion into the piece model.
    ///
    /// `generate` defaults to the real network call; tests pass a fake to exercise the
    /// parsing/validation/piece-assignment logic without hitting any actual LLM. `title`,
    /// when given, overrides the LLM's own chosen title — the "Nouveau morceau" wizard
    /// (title → text → indications → compose, all in one flow) uses this so the piece ends
    /// up named exactly what was typed, not whatever the LLM decided to call it.
    public func composeFromText(title: String? = nil, generate: (String, LLMConnection) throws -> String = LLMClient.generate) throws {
        let prompt = try currentTextCompositionPrompt()
        guard let connection = currentLLMConnection else { throw SessionError.noLLMConnectionSelected }

        append("Sending text to \(connection.name)...")
        let responseText = try generate(prompt, connection)

        let (composedPieceOpt, warnings) = LLMPieceComposer.parseAndValidate(responseText: responseText)
        for warning in warnings { append("Compose warning: \(warning)") }
        guard var composedPiece = composedPieceOpt else { throw SessionError.llmComposeFailed(warnings) }
        if let title { composedPiece.title = title }

        piece = composedPiece
        currentPieceFilePath = nil
        append("Composed '\(composedPiece.title)' from text (\(composedPiece.sections.count) section(s)).")
    }

    public func loadPiece(fromJSONFile path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try JSONDecoder().decode(Piece.self, from: data)
        piece = decoded
        currentPieceFilePath = path
        append("Loaded piece from \(path): \(decoded.title)")
    }

    public func savePiece(toJSONFile path: String) throws {
        guard let piece else { throw SessionError.noPieceLoaded }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(piece)
        try data.write(to: URL(fileURLWithPath: path))
        currentPieceFilePath = path
        append("Saved piece to \(path).")
    }

    private static let supportedPieceExtensions: Set<String> = ["json"]

    /// Scans `folderPath` for `.json` piece files and remembers both the folder and the
    /// match list (in `pieceFiles`) so they can be picked by index afterwards — mirrors
    /// `listSampleFiles`.
    public func listPieceFiles(in folderPath: String) throws {
        let folderURL = URL(fileURLWithPath: folderPath)
        let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        pieceFolder = folderPath
        pieceFiles = contents
            .filter { Self.supportedPieceExtensions.contains($0.pathExtension.lowercased()) }
            .map(\.lastPathComponent)
            .sorted()
        append(pieceFiles.isEmpty
            ? "No .json piece files found in \(folderPath)."
            : "Found \(pieceFiles.count) piece file(s) in \(folderPath).")
    }

    /// Loads a piece by name from the last-listed folder (see `listPieceFiles`).
    public func loadPiece(named name: String) throws {
        guard let pieceFolder else { throw SessionError.noPieceFolderListed }
        try loadPiece(fromJSONFile: URL(fileURLWithPath: pieceFolder).appendingPathComponent(name).path)
    }

    /// Convenience over `loadPiece(named:)` using the 0-based position in `pieceFiles`.
    public func loadPiece(atIndex index: Int) throws {
        guard pieceFiles.indices.contains(index) else { throw SessionError.invalidPieceIndex }
        try loadPiece(named: pieceFiles[index])
    }

    /// Re-saves the current piece to wherever it was last loaded from or saved to. Fails
    /// if that's never happened yet — use `savePiece(as:)` for a first save.
    public func savePiece() throws {
        guard let currentPieceFilePath else { throw SessionError.noCurrentPieceFile }
        try savePiece(toJSONFile: currentPieceFilePath)
    }

    /// Saves under a new name/path — "Save As". `nameOrPath` containing a "/" is used
    /// as-is (an explicit path); a bare name is resolved against `pieceFolder` (set via
    /// `listPieceFiles`). Adds a ".json" extension if missing either way.
    public func savePiece(as nameOrPath: String) throws {
        let resolvedPath: String
        if nameOrPath.contains("/") {
            resolvedPath = nameOrPath
        } else {
            guard let pieceFolder else { throw SessionError.noPieceFolderListed }
            resolvedPath = URL(fileURLWithPath: pieceFolder).appendingPathComponent(nameOrPath).path
        }
        try savePiece(toJSONFile: resolvedPath.hasSuffix(".json") ? resolvedPath : resolvedPath + ".json")
    }

    /// Sets one melodic track's instrument (a sample file name, resolved against
    /// `sampleFolder` at play time — see `resolvedInstrumentURLs`) within the current
    /// piece's `sectionIndex`-th section. Pass `nil`/empty to revert to the default sound.
    /// Doesn't persist by itself — follow with `save()`/`saveAs(_:)` to keep the change.
    public func setPieceTrackInstrument(sectionIndex: Int, trackIndex: Int, instrumentName: String?) throws {
        guard var piece else { throw SessionError.noPieceLoaded }
        guard piece.sections.indices.contains(sectionIndex) else { throw SessionError.invalidPieceSectionIndex }
        guard piece.sections[sectionIndex].tracks.indices.contains(trackIndex) else { throw SessionError.invalidPieceTrackIndex }
        piece.sections[sectionIndex].tracks[trackIndex].instrument = instrumentName ?? ""
        self.piece = piece
        append("Piste '\(piece.sections[sectionIndex].tracks[trackIndex].name)' (section '\(piece.sections[sectionIndex].name)') : instrument \(instrumentName.map { "'\($0)'" } ?? "par defaut").")
    }

    /// Sets a section's chord-progression instrument — the harmonic-accompaniment
    /// counterpart to `setPieceTrackInstrument`, since chords have no track of their own.
    public func setPieceChordInstrument(sectionIndex: Int, instrumentName: String?) throws {
        guard var piece else { throw SessionError.noPieceLoaded }
        guard piece.sections.indices.contains(sectionIndex) else { throw SessionError.invalidPieceSectionIndex }
        piece.sections[sectionIndex].chordInstrument = instrumentName
        self.piece = piece
        append("Accords de la section '\(piece.sections[sectionIndex].name)' : instrument \(instrumentName.map { "'\($0)'" } ?? "par defaut").")
    }

    public func play() throws {
        guard let piece else { throw SessionError.noPieceLoaded }
        let notes = piece.renderedNotes()
        let timeline = piece.harmonicTimeline()
        let duration = PiecePlayer.totalDuration(of: notes)
        let warnings = player.play(notes, instrumentURLs: resolvedInstrumentURLs(for: notes))
        for warning in warnings { append("Instrument: \(warning)") }

        playbackGeneration += 1
        let generation = playbackGeneration
        isPlaying = true
        playbackTimeline = timeline
        playbackCurrentChordIndex = timeline.isEmpty ? nil : 0
        playbackHeldPitches = []
        append("Playing '\(piece.title)': \(notes.count) notes, \(String(format: "%.1f", duration))s.")

        // Mirrors PiecePlayer's own note-on/off scheduling, but drives `playbackHeldPitches`
        // / `playbackCurrentChordIndex` (UI state) instead of the sampler (audio) — kept
        // separate from AudioEngine since this is presentation state, not sound. Scheduled
        // on `playbackStateQueue` (serial), not `.global()` (concurrent) — see that
        // property's doc comment for why.
        let now = DispatchTime.now()
        for note in notes {
            playbackStateQueue.asyncAfter(deadline: now + note.startSeconds) { [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                self.playbackHeldPitches.insert(note.pitch)
            }
            playbackStateQueue.asyncAfter(deadline: now + note.startSeconds + note.durationSeconds) { [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                self.playbackHeldPitches.remove(note.pitch)
            }
        }
        for (index, segment) in timeline.enumerated() {
            playbackStateQueue.asyncAfter(deadline: now + segment.startSeconds) { [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                self.playbackCurrentChordIndex = index
            }
        }

        // Same serial queue as above, not `.global()`/`.main` — a blocking-readLine REPL
        // never pumps the main run loop (a `.main` timer would simply never fire), and this
        // must not race the per-note/per-chord updates scheduled above.
        playbackStateQueue.asyncAfter(deadline: .now() + duration + 0.2) { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            self.isPlaying = false
            self.playbackHeldPitches = []
            self.playbackCurrentChordIndex = nil
            self.append("Playback finished.")
        }
    }

    /// Resolves every distinct `RenderedNote.instrumentName` used by `notes` to an actual
    /// sample file in `sampleFolder` (same folder/lookup `use-sample`/`loadSample(named:)`
    /// already use for the piece-playback default sound) — a name with no matching file is
    /// simply left out, letting `PiecePlayer.play` fall back to (and warn about) its
    /// per-instrument default sound instead.
    private func resolvedInstrumentURLs(for notes: [RenderedNote]) -> [String: URL] {
        guard let sampleFolder else { return [:] }
        let folderURL = URL(fileURLWithPath: sampleFolder)
        var result: [String: URL] = [:]
        for name in Set(notes.compactMap(\.instrumentName)) {
            let url = folderURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                result[name] = url
            }
        }
        return result
    }

    public func availableMIDISources() -> [String] {
        MIDIInputListener.sourceNames()
    }

    // MARK: - Tracks

    /// Switches between hearing MIDI as one merged stream and hearing it as one
    /// independent track per visible port, then rebuilds `tracks` to match. Any MIDI
    /// track(s) currently listening are stopped first (a fusion-mode change genuinely
    /// changes what "the MIDI track" means, so there's no sensible way to carry a live
    /// listener across it) — the computer-keyboard and microphone tracks are untouched.
    public func setMIDIFusionMode(_ mode: MIDIFusionMode) {
        guard mode != midiFusionMode else { return }
        for track in tracks where isMIDITrack(track.id) && track.isListening {
            stopTrack(track.id)
        }
        midiFusionMode = mode
        refreshTracks()
        append("Mode MIDI : \(mode == .merged ? "fusionne" : "individuel").")
    }

    /// Rebuilds `tracks` from `midiFusionMode` and the currently-visible MIDI sources,
    /// preserving every surviving track's listening/sound/recognition state by identity
    /// (`TrackID`) — called at `init` and after `setMIDIFusionMode`, and exposed as the
    /// `tracks` command so a newly plugged-in MIDI device can be picked up on demand (this
    /// app doesn't watch for CoreMIDI hot-plug notifications).
    public func refreshTracks() {
        var updated: [TrackInfo] = []
        switch midiFusionMode {
        case .merged:
            updated.append(preservedOrNewTrack(.midiMerged, label: "MIDI (fusionne)"))
        case .individual:
            for (index, name) in availableMIDISources().enumerated() {
                updated.append(preservedOrNewTrack(.midiSource(index), label: "MIDI : \(name)"))
            }
        }
        updated.append(preservedOrNewTrack(.computerKeyboard, label: "Clavier ordinateur"))
        updated.append(preservedOrNewTrack(.microphone, label: "Microphone", canHaveSound: false))
        tracks = updated
    }

    private func preservedOrNewTrack(_ id: TrackID, label: String, canHaveSound: Bool = true) -> TrackInfo {
        if var existing = tracks.first(where: { $0.id == id }) {
            existing.label = label
            return existing
        }
        return TrackInfo(id: id, label: label, canHaveSound: canHaveSound)
    }

    private func isMIDITrack(_ id: TrackID) -> Bool {
        switch id {
        case .midiMerged, .midiSource: return true
        case .computerKeyboard, .microphone, .remote: return false
        }
    }

    private func trackIndex(_ id: TrackID) throws -> Int {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else {
            throw SessionError.unknownTrack(String(describing: id))
        }
        return index
    }

    /// Starts listening on one track: connects a `MIDIInputListener` for a MIDI track,
    /// starts `MicrophonePitchListener` for the microphone, or (for the computer keyboard)
    /// simply marks it listening — `pressKey`/`releaseKey` already drive it directly, there
    /// being no separate hardware connection step for typed keys.
    public func startTrack(_ id: TrackID) throws {
        let index = try trackIndex(id)
        guard !tracks[index].isListening else { return }
        switch id {
        case .remote:
            throw SessionError.remoteTrackListeningIsNotLocal
        case .midiMerged, .midiSource:
            let newListener = try MIDIInputListener { [weak self] event in
                self?.handleIncomingMIDIEvent(event, track: id)
            }
            if case .midiSource(let sourceIndex) = id {
                newListener.connectSource(atIndex: sourceIndex)
            } else {
                newListener.connectAllSources()
            }
            midiListeners[id] = newListener
        case .computerKeyboard:
            break
        case .microphone:
            let newListener = MicrophonePitchListener { [weak self] detected, level in
                self?.handleDetectedPitches(detected, level: level, track: id)
            }
            try newListener.start()
            microphoneListener = newListener
        }
        if recognizers[id] == nil { recognizers[id] = RecognitionEngine() }
        tracks[index].isListening = true
        append("Piste '\(tracks[index].label)' : ecoute demarree.")
        announceTrackToServerIfClient(tracks[index])
    }

    /// Stops listening on one track and clears its recognition state (held notes,
    /// recognized chord/mode) — but not its sound/instrument choice, which survives a
    /// stop/restart of the same track.
    public func stopTrack(_ id: TrackID) {
        guard let index = tracks.firstIndex(where: { $0.id == id }), tracks[index].isListening else { return }
        switch id {
        case .remote:
            // Not locally controllable — a remote track's listening state is driven by
            // `sync` messages (as server) or by the owning client itself, never by a
            // local `track <id> off`. See `removeRemoteTrack` for actual teardown.
            return
        case .midiMerged, .midiSource:
            midiListeners[id] = nil
        case .computerKeyboard:
            break
        case .microphone:
            microphoneListener?.stop()
            microphoneListener = nil
        }
        liveInputQueue.sync {
            recognizers[id]?.reset()
            tracks[index].heldPitches = []
            tracks[index].recognizedChord = nil
            tracks[index].recognizedModes = []
            tracks[index].lastDetectedPitches = []
            tracks[index].microphoneInputLevel = 0
        }
        lastDetectedMIDIPitches[id] = nil
        tracks[index].isListening = false
        append("Piste '\(tracks[index].label)' : ecoute arretee.")
        unannounceTrackToServerIfClient(id)
    }

    /// Turns a track's own sampler on or off — never allowed for `.microphone` (see
    /// `TrackInfo.canHaveSound`'s doc comment). Turning sound back on after it was
    /// disabled reuses whatever instrument was previously loaded on this track, if any.
    public func setSoundEnabled(_ enabled: Bool, for id: TrackID) throws {
        let index = try trackIndex(id)
        guard tracks[index].canHaveSound else { throw SessionError.trackCannotHaveSound }
        if enabled {
            if let existing = samplers[id] {
                try existing.start()
            } else {
                let unit = SamplerUnit()
                try unit.start()
                samplers[id] = unit
            }
        } else {
            samplers[id]?.stop()
        }
        tracks[index].soundEnabled = enabled
        append("Piste '\(tracks[index].label)' : son \(enabled ? "active" : "desactive").")
    }

    /// Loads a sample-based instrument by name from `sampleFolder` (see `listSampleFiles`)
    /// onto one track's own sampler, enabling its sound if it wasn't already — each track
    /// can carry a different instrument, sounding at the same time as any other track's.
    public func setInstrument(named name: String, for id: TrackID) throws {
        let index = try trackIndex(id)
        guard tracks[index].canHaveSound else { throw SessionError.trackCannotHaveSound }
        guard let sampleFolder else { throw SessionError.noSampleFolderListed }
        let url = URL(fileURLWithPath: sampleFolder).appendingPathComponent(name)
        let unit: SamplerUnit
        if let existing = samplers[id] {
            unit = existing
        } else {
            unit = SamplerUnit()
            try unit.start()
            samplers[id] = unit
        }
        try unit.loadSample(at: url)
        tracks[index].soundEnabled = true
        tracks[index].instrumentName = name
        append("Piste '\(tracks[index].label)' : instrument '\(name)' charge, son active.")
    }

    /// Convenience over `setInstrument(named:for:)` using the 0-based position in `sampleFiles`.
    public func setInstrument(atIndex sampleIndex: Int, for id: TrackID) throws {
        guard sampleFiles.indices.contains(sampleIndex) else { throw SessionError.invalidSampleIndex }
        try setInstrument(named: sampleFiles[sampleIndex], for: id)
    }

    private static let supportedSampleExtensions: Set<String> = ["sf2", "dls", "aupreset"]

    /// Scans `folderPath` for `.sf2`/`.dls`/`.aupreset` files and remembers both the folder
    /// and the match list (in `sampleFiles`) so they can be picked by index afterwards.
    public func listSampleFiles(in folderPath: String) throws {
        let folderURL = URL(fileURLWithPath: folderPath)
        let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        sampleFolder = folderPath
        sampleFiles = contents
            .filter { Self.supportedSampleExtensions.contains($0.pathExtension.lowercased()) }
            .map(\.lastPathComponent)
            .sorted()
        append(sampleFiles.isEmpty
            ? "No .sf2/.dls/.aupreset files found in \(folderPath)."
            : "Found \(sampleFiles.count) sample file(s) in \(folderPath).")
    }

    /// Loads a sample-based instrument by name from the last-listed folder (see
    /// `listSampleFiles`), replacing the piece-playback sampler's current sound (the
    /// default sine synth, or whatever was loaded before) — used by `play()`, entirely
    /// separate from any live-input track's own instrument (see `setInstrument(named:for:)`).
    public func loadSample(named name: String) throws {
        guard let sampleFolder else { throw SessionError.noSampleFolderListed }
        let url = URL(fileURLWithPath: sampleFolder).appendingPathComponent(name)
        try player.loadSample(at: url)
        append("Loaded instrument: \(name)")
    }

    /// Convenience over `loadSample(named:)` using the 0-based position in `sampleFiles`.
    public func loadSample(atIndex index: Int) throws {
        guard sampleFiles.indices.contains(index) else { throw SessionError.invalidSampleIndex }
        try loadSample(named: sampleFiles[index])
    }

    /// Simulates a key press/release without real MIDI hardware — useful for testing and
    /// demoing, and the same entry point the computer-keyboard track's typed-piano feature
    /// and a future on-screen/touch virtual keyboard both use. Defaults to `.computerKeyboard`
    /// since that's what a simulated key press most naturally represents; pass a different
    /// track to simulate other hardware without it being physically present.
    public func pressKey(pitch: Int, velocity: Int = 100, channel: Int = 0, track: TrackID = .computerKeyboard) {
        handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: pitch, velocity: velocity, channel: channel), track: track)
    }

    public func releaseKey(pitch: Int, channel: Int = 0, track: TrackID = .computerKeyboard) {
        handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOff, pitch: pitch, velocity: 0, channel: channel), track: track)
    }

    /// Everything a note on/off does to one track's recognition state: logging,
    /// `heldPitches`, feeding that track's own recognizer, and — unless this is the
    /// microphone (which never sounds through the app, to avoid feedback) or this track's
    /// sound is off — its own sampler. Must run inside `liveInputQueue.sync` — this touches
    /// `recognizers`/`tracks` without its own synchronization, relying on the caller for that.
    private func updateRecognitionState(pitch: Int, isNoteOn: Bool, velocity: Int, channel: Int, track: TrackID) {
        guard let index = tracks.firstIndex(where: { $0.id == track }) else { return }
        lastMIDIEvent = MIDINoteEvent(kind: isNoteOn ? .noteOn : .noteOff, pitch: pitch, velocity: isNoteOn ? velocity : 0, channel: channel)
        append("\(tracks[index].label) \(isNoteOn ? "on " : "off")pitch=\(pitch) vel=\(isNoteOn ? velocity : 0) ch=\(channel)")

        let recognizer = recognizers[track] ?? RecognitionEngine()
        recognizers[track] = recognizer
        if isNoteOn {
            recognizer.noteOn(pitch: pitch)
            tracks[index].heldPitches.insert(pitch)
        } else {
            recognizer.noteOff(pitch: pitch)
            tracks[index].heldPitches.remove(pitch)
        }
        refreshRecognition(for: track, recognizer: recognizer)
        forwardNoteEventToServerIfClient(track: track, isNoteOn: isNoteOn, pitch: pitch, velocity: velocity, channel: channel)
        captureRecordingEventIfRecording(track: track, isNoteOn: isNoteOn, pitch: pitch, velocity: velocity)

        guard tracks[index].soundEnabled, let sampler = samplers[track] else { return }
        if isNoteOn {
            sampler.startNote(pitch: pitch, velocity: velocity, channel: channel)
        } else {
            sampler.stopNote(pitch: pitch, channel: channel)
        }
    }

    /// Everything that happens per incoming MIDI event for one track: logging, feeding
    /// that track's recognizer, and sounding it through that track's own sampler if its
    /// sound is on. Extracted out of the `MIDIInputListener` closure so it's directly
    /// callable from tests without needing real CoreMIDI input. Runs on `liveInputQueue`
    /// (see its doc comment) so concurrent callers are serialized regardless of which
    /// thread each one happens to call in on; `.sync`, not `.async`, so existing callers
    /// that check state right after `pressKey`/`releaseKey` keep seeing it updated by the
    /// time the call returns.
    func handleIncomingMIDIEvent(_ event: MIDINoteEvent, track: TrackID) {
        liveInputQueue.sync {
            updateRecognitionState(pitch: event.pitch, isNoteOn: event.kind == .noteOn, velocity: event.velocity, channel: event.channel, track: track)
        }
    }

    /// Turns a stream of "here are the pitches right now, or empty for silence" reports
    /// into discrete note-on/note-off transitions: a note-off for every previously-held
    /// pitch that dropped out, a note-on for every new one that appeared — the same shape
    /// as how MIDI note-on/note-off events already drive `heldPitches`/the recognizer, so
    /// several simultaneously-detected pitches naturally feed the same chord recognition
    /// real MIDI chords already use. Runs on whichever thread `MicrophonePitchListener`
    /// calls back on.
    private func handleDetectedPitches(_ detected: [DetectedPitch], level: Float, track: TrackID) {
        liveInputQueue.sync {
            guard let index = tracks.firstIndex(where: { $0.id == track }) else { return }
            tracks[index].microphoneInputLevel = level
            tracks[index].lastDetectedPitches = detected
            let newPitches = Set(detected.map(\.midiPitch))
            let oldPitches = lastDetectedMIDIPitches[track] ?? []
            for droppedPitch in oldPitches.subtracting(newPitches) {
                updateRecognitionState(pitch: droppedPitch, isNoteOn: false, velocity: 0, channel: 0, track: track)
            }
            for newPitch in newPitches.subtracting(oldPitches) {
                updateRecognitionState(pitch: newPitch, isNoteOn: true, velocity: 100, channel: 0, track: track)
            }
            lastDetectedMIDIPitches[track] = newPitches
        }
    }

    /// Re-runs one track's chord/mode recognition and logs a line only when the result
    /// actually changed, so holding a chord down doesn't spam the log on every repeated note.
    private func refreshRecognition(for track: TrackID, recognizer: RecognitionEngine) {
        guard let index = tracks.firstIndex(where: { $0.id == track }) else { return }
        let label = tracks[index].label

        let chord = recognizer.recognizeChord()
        if chord != tracks[index].recognizedChord {
            tracks[index].recognizedChord = chord
            append("\(label) - Chord: \(chord.map(Self.describe) ?? "(none)")")
        }

        let modes = recognizer.recognizeModes()
        if modes != tracks[index].recognizedModes {
            tracks[index].recognizedModes = modes
            if !modes.isEmpty {
                append("\(label) - Mode candidates: " + modes.map(Self.describe).joined(separator: ", "))
            }
        }
    }

    private static func describe(_ chord: RecognizedChord) -> String {
        let slash = chord.bass != chord.root ? "/\(chord.bass.name())" : ""
        return "\(chord.root.name())\(chord.chordTemplateID)\(slash) (\(Int(chord.confidence * 100))%)"
    }

    private static func describe(_ mode: RecognizedMode) -> String {
        let name = ScaleLibrary.byID(mode.scaleID)?.popularName ?? mode.scaleID
        return "\(mode.tonic.name()) \(name) (\(Int(mode.confidence * 100))%)"
    }

    // MARK: - Collaborative session (server/client)

    /// Starts hosting a collaborative session on `port`: any client that connects is
    /// accepted (no allow-list in this first version — purely collaborative, matching the
    /// "the server doesn't gatekeep" design), its announced tracks are merged into `tracks`
    /// as `.remote(clientID:trackID:)` entries, and the full merged track list (this
    /// server's own local tracks plus every connected client's) is broadcast back to every
    /// client every ~150ms and right after any track joins/leaves.
    public func startServer(port: Int) throws {
        guard networkRole == .standalone else { throw SessionError.networkRoleAlreadyActive }
        guard let uPort = UInt16(exactly: port) else { throw NetworkError.invalidPort }
        let server = NetworkServer(
            onMessage: { [weak self] connectionID, message in self?.handleServerMessage(connectionID, message) },
            onDisconnect: { [weak self] connectionID in self?.handleClientDisconnected(connectionID) }
        )
        // Always advertised via Bonjour/mDNS under this participant's name — see
        // `discoverServers()` — a server that only ever accepts a manually-typed host:port
        // is strictly a subset of what advertising already covers, so there's no separate
        // "advertise or not" toggle to expose in this first version.
        try server.start(port: uPort, advertisedAs: localClientName)
        netServer = server
        networkRole = .server(port: port)
        startSyncBroadcastTimer()
        append("Serveur demarre sur le port \(port).")
    }

    /// Searches the local network for servers advertising themselves (see `startServer`)
    /// for up to `timeout` seconds and returns whatever was found — empty if none, which
    /// isn't an error (Bonjour visibility depends on both sides being on the same network
    /// segment and macOS's Local Network permission having been granted; see the user
    /// guide's troubleshooting section if this never finds anything).
    public func discoverServers(timeout: TimeInterval = 2.0) -> [DiscoveredServer] {
        ServiceBrowser.discover(timeout: timeout)
    }

    public func stopServer() {
        guard case .server = networkRole else { return }
        syncTimer?.cancel()
        syncTimer = nil
        netServer?.stop()
        netServer = nil
        liveInputQueue.sync {
            removeAllRemoteTracks()
            connectionIDToClientID.removeAll()
            clientIDToClientName.removeAll()
        }
        networkRole = .standalone
        append("Serveur arrete.")
    }

    // MARK: - Web console (read-only browser view of `run`)

    /// Starts a small hand-rolled HTTP server (see `WebConsole`) that serves a browser page
    /// mirroring the `run` screen — a static page + script on first load, then just answering
    /// `GET /state` with whatever `refreshWebConsoleStateSoon()` last computed. Independent of
    /// `networkRole`/`startServer`: this is a read-only *display* for one machine's own
    /// activity, not another way to join/host a collaborative session, so both can run at
    /// the same time without conflict.
    public func startWebConsole(port: Int) throws {
        guard webConsolePort == nil else { throw SessionError.webConsoleAlreadyActive }
        guard let uPort = UInt16(exactly: port) else { throw HTTPServerError.invalidPort }
        let server = HTTPServer(onRequest: { [weak self] request in
            self?.handleWebConsoleRequest(request) ?? .notFound()
        })
        try server.start(port: uPort)
        webConsoleServer = server
        webConsolePort = port
        refreshWebConsoleStateSoon() // don't leave the cache empty until the first tick
        startWebConsoleRefreshTimer()
        append("Console web demarree sur http://localhost:\(port)")
    }

    public func stopWebConsole() {
        guard webConsolePort != nil else { return }
        webConsoleRefreshTimer?.cancel()
        webConsoleRefreshTimer = nil
        webConsoleServer?.stop()
        webConsoleServer = nil
        webConsolePort = nil
        append("Console web arretee.")
    }

    private func handleWebConsoleRequest(_ request: HTTPRequest) -> HTTPResponse {
        switch request.path {
        case "/": return .text(webConsoleIndexHTML, contentType: "text/html; charset=utf-8")
        case "/app.js": return .text(webConsoleAppJS, contentType: "application/javascript")
        case "/state": return HTTPResponse(contentType: "application/json", body: webConsoleStateQueue.sync { webConsoleStateCache })
        default: return .notFound()
        }
    }

    private func startWebConsoleRefreshTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + .milliseconds(150), repeating: .milliseconds(150))
        timer.setEventHandler { [weak self] in self?.refreshWebConsoleStateSoon() }
        timer.resume()
        webConsoleRefreshTimer = timer
    }

    /// Recomputes the whole `WebConsoleState` snapshot and caches its JSON encoding — the
    /// same "compute periodically, serve the cached result" split the user asked for, so a
    /// `GET /state` never recomputes anything itself, and any number of browser tabs polling
    /// at whatever rate they like all just read the same cached bytes. Reads `tracks` via
    /// `liveInputQueue.sync` (same discipline `broadcastSyncSoon()` already uses for the same
    /// reason: it's mutated from MIDI/microphone/keyboard-release callbacks) and the playback
    /// fields via `playbackStateQueue.sync` (mutated from `play()`'s scheduled callbacks).
    private func refreshWebConsoleStateSoon() {
        let state = buildWebConsoleState()
        guard let data = try? JSONEncoder().encode(state) else { return }
        webConsoleStateQueue.sync { webConsoleStateCache = data }
    }

    private func buildWebConsoleState() -> WebConsoleState {
        let lastEvent = lastMIDIEvent.map { "\($0.kind == .noteOn ? "on " : "off")pitch=\($0.pitch) vel=\($0.velocity)" }

        let trackStates: [WebConsoleTrackState] = liveInputQueue.sync {
            tracks.filter { $0.isListening }.map(Self.webConsoleTrackState)
        }

        let playback: WebConsolePlaybackState? = playbackStateQueue.sync {
            guard isPlaying else { return nil }
            let currentIndex = playbackCurrentChordIndex
            let currentSegment = currentIndex.flatMap { playbackTimeline.indices.contains($0) ? playbackTimeline[$0] : nil }
            let timelineSegments = playbackTimeline.enumerated().map { index, event in
                WebConsoleTimelineSegment(
                    label: "\(PitchClass(event.chord.root).name())\(event.chord.chordTemplateID)",
                    isCurrent: index == currentIndex
                )
            }
            let (chordTones, modeTones) = Self.pitchClassSets(forChordRoot: currentSegment?.chord.root, chordTemplateID: currentSegment?.chord.chordTemplateID, modeTonic: currentSegment?.mode.tonic, scaleID: currentSegment?.mode.scaleID)
            return WebConsolePlaybackState(
                timeline: timelineSegments, heldPitches: Array(playbackHeldPitches),
                chordRoot: currentSegment?.chord.root, chordTones: chordTones, modeTones: modeTones
            )
        }

        let soundTrackPlayback: WebConsoleSoundTrackPlaybackState? = playbackStateQueue.sync {
            isPlayingSoundTrack ? WebConsoleSoundTrackPlaybackState(heldPitches: Array(soundTrackHeldPitches)) : nil
        }

        return WebConsoleState(lastEvent: lastEvent, tracks: trackStates, playback: playback, soundTrackPlayback: soundTrackPlayback)
    }

    /// One listening track's state, transposed from `TrackInfo`'s structured recognition into
    /// the flat pitch-class sets/labels the browser needs — same computation
    /// `renderTrackKeyboard`/`chordDisplayText`/`modesDisplayText` do in `ImprovCLI/main.swift`
    /// for the terminal's own keyboard, just producing data instead of ANSI text.
    private static func webConsoleTrackState(_ track: TrackInfo) -> WebConsoleTrackState {
        let (chordTones, modeTones) = pitchClassSets(
            forChordRoot: track.recognizedChord?.root.value, chordTemplateID: track.recognizedChord?.chordTemplateID,
            modeTonic: track.recognizedModes.first?.tonic.value, scaleID: track.recognizedModes.first?.scaleID
        )
        let chordLabel = track.recognizedChord.map(describe) ?? (track.remoteChordDisplay)
        let modesLabel = !track.recognizedModes.isEmpty ? track.recognizedModes.map(describe).joined(separator: ", ") : track.remoteModesDisplay
        return WebConsoleTrackState(
            id: webConsoleTrackIDText(track.id), label: track.label, owner: track.ownerName,
            heldPitches: Array(track.heldPitches),
            chordRoot: track.recognizedChord?.root.value, chordTones: chordTones, modeTones: modeTones,
            chordLabel: chordLabel, modesLabel: modesLabel,
            microphoneLevel: track.id == .microphone ? track.microphoneInputLevel : nil
        )
    }

    private static func webConsoleTrackIDText(_ id: TrackID) -> String {
        if case .remote(let clientID, let trackID) = id { return "remote:\(clientID)@\(trackID)" }
        return id.wireIDText ?? "?"
    }

    /// Shared by `buildWebConsoleState()`'s two call sites (a live track, and the piece
    /// currently playing) — the pitch classes (0...11) of a recognized chord's template and
    /// of the top recognized mode's scale, or empty sets when there's nothing to show. All
    /// four inputs are `nil` together or not at all in both call sites, so a single combined
    /// helper avoids duplicating the two independent `ChordVocabulary`/`ScaleLibrary` lookups.
    private static func pitchClassSets(forChordRoot chordRoot: Int?, chordTemplateID: String?, modeTonic: Int?, scaleID: String?) -> (chordTones: [Int], modeTones: [Int]) {
        var chordTones: [Int] = []
        if let chordRoot, let chordTemplateID, let template = ChordVocabulary.byID(chordTemplateID) {
            chordTones = template.intervalsFromRoot.map { (chordRoot + $0) % 12 }
        }
        var modeTones: [Int] = []
        if let modeTonic, let scaleID, let scale = ScaleLibrary.byID(scaleID) {
            modeTones = Mode(tonic: PitchClass(modeTonic), scale: scale).pitchClassSet.map(\.value)
        }
        return (chordTones, modeTones)
    }

    /// Connects to a collaborative session at a known host/port. Every local track already
    /// listening is announced right away (in addition to `hello`), so joining mid-session
    /// doesn't require re-toggling anything already active.
    public func connectToServer(host: String, port: Int) throws {
        guard networkRole == .standalone else { throw SessionError.networkRoleAlreadyActive }
        guard let uPort = UInt16(exactly: port) else { throw NetworkError.invalidPort }
        let client = makeNetworkClient()
        try client.connect(host: host, port: uPort, sendOnReady: initialClientMessages())
        netClient = client
        networkRole = .client(description: "\(host):\(port)")
        append("Connexion au serveur \(host):\(port)...")
    }

    /// Connects to a server found via `discoverServers()` — same behavior as
    /// `connectToServer(host:port:)`, just resolved by Bonjour instead of a typed address.
    public func connectToServer(discovered server: DiscoveredServer) throws {
        guard networkRole == .standalone else { throw SessionError.networkRoleAlreadyActive }
        let client = makeNetworkClient()
        client.connect(to: server.endpoint, sendOnReady: initialClientMessages())
        netClient = client
        networkRole = .client(description: server.name)
        append("Connexion au serveur '\(server.name)'...")
    }

    private func makeNetworkClient() -> NetworkClient {
        NetworkClient(
            onMessage: { [weak self] message in self?.handleClientMessage(message) },
            onDisconnect: { [weak self] in self?.handleServerDisconnected() }
        )
    }

    /// `hello` followed by one `trackAnnounce` per already-listening local track — shared by
    /// both `connectToServer` overloads.
    private func initialClientMessages() -> [NetMessage] {
        var messages = [NetMessage(kind: .hello, clientID: localClientID, clientName: localClientName)]
        for track in tracks where track.isListening {
            if let wireID = track.id.wireIDText {
                messages.append(NetMessage(
                    kind: .trackAnnounce, clientID: localClientID, trackID: wireID,
                    label: track.label, canHaveSound: track.canHaveSound
                ))
            }
        }
        return messages
    }

    public func disconnectFromServer() {
        guard case .client = networkRole else { return }
        netClient?.disconnect()
        netClient = nil
        liveInputQueue.sync { removeAllRemoteTracks() }
        networkRole = .standalone
        append("Deconnecte du serveur.")
    }

    private func handleServerDisconnected() {
        netClient = nil
        liveInputQueue.sync { removeAllRemoteTracks() }
        networkRole = .standalone
        append("Connexion au serveur perdue.")
    }

    // MARK: Server-side message handling

    private func handleServerMessage(_ connectionID: String, _ message: NetMessage) {
        liveInputQueue.sync {
            switch message.kind {
            case .hello:
                guard let clientID = message.clientID else { return }
                connectionIDToClientID[connectionID] = clientID
                clientIDToClientName[clientID] = message.clientName
                append("Client connecte: \(message.clientName ?? clientID).")
            case .trackAnnounce:
                guard let clientID = message.clientID, let trackID = message.trackID else { return }
                addOrUpdateRemoteTrack(clientID: clientID, trackID: trackID, label: message.label ?? trackID, canHaveSound: message.canHaveSound ?? true, ownerName: clientIDToClientName[clientID])
            case .trackUnannounce:
                guard let clientID = message.clientID, let trackID = message.trackID else { return }
                removeRemoteTrack(clientID: clientID, trackID: trackID)
            case .noteEvent:
                guard let clientID = message.clientID, let trackID = message.trackID,
                      let isNoteOn = message.isNoteOn, let pitch = message.pitch else { return }
                let remoteID = TrackID.remote(clientID: clientID, trackID: trackID)
                if !tracks.contains(where: { $0.id == remoteID }) {
                    addOrUpdateRemoteTrack(clientID: clientID, trackID: trackID, label: trackID, canHaveSound: true, ownerName: clientIDToClientName[clientID])
                }
                updateRecognitionState(pitch: pitch, isNoteOn: isNoteOn, velocity: message.velocity ?? 100, channel: message.channel ?? 0, track: remoteID)
            case .helloAck, .sync:
                break // a server never receives these — they're server -> client only
            }
        }
        broadcastSyncSoon()
    }

    private func handleClientDisconnected(_ connectionID: String) {
        liveInputQueue.sync {
            guard let clientID = connectionIDToClientID.removeValue(forKey: connectionID) else { return }
            clientIDToClientName.removeValue(forKey: clientID)
            removeAllRemoteTracks(forClientID: clientID)
            append("Client deconnecte: \(clientID).")
        }
        broadcastSyncSoon()
    }

    /// Adds a new remote-track entry, or updates its label/listening flag if it already
    /// exists (idempotent — a client may re-announce the same track). Must run inside
    /// `liveInputQueue.sync`, same contract as `updateRecognitionState`.
    private func addOrUpdateRemoteTrack(clientID: String, trackID: String, label: String, canHaveSound: Bool, ownerName: String?) {
        let id = TrackID.remote(clientID: clientID, trackID: trackID)
        if let index = tracks.firstIndex(where: { $0.id == id }) {
            tracks[index].label = label
            tracks[index].isListening = true
            tracks[index].ownerName = ownerName
        } else {
            tracks.append(TrackInfo(id: id, label: label, isListening: true, canHaveSound: canHaveSound, ownerName: ownerName))
        }
    }

    /// Removes one remote track entirely — a departed track shouldn't linger in the list
    /// the way a merely-stopped local track does. Must run inside `liveInputQueue.sync`.
    private func removeRemoteTrack(clientID: String, trackID: String) {
        let id = TrackID.remote(clientID: clientID, trackID: trackID)
        tracks.removeAll { $0.id == id }
        recognizers[id] = nil
        samplers[id]?.stop()
        samplers[id] = nil
    }

    /// Removes every remote track belonging to one participant — used when their
    /// connection drops. Must run inside `liveInputQueue.sync`.
    private func removeAllRemoteTracks(forClientID clientID: String) {
        let idsToRemove = tracks.compactMap { track -> TrackID? in
            guard case .remote(let owner, _) = track.id, owner == clientID else { return nil }
            return track.id
        }
        for id in idsToRemove {
            recognizers[id] = nil
            samplers[id]?.stop()
            samplers[id] = nil
        }
        tracks.removeAll { idsToRemove.contains($0.id) }
    }

    /// Removes every remote track regardless of owner — used when this session itself
    /// stops being a server or disconnects as a client (either way, every `.remote` entry
    /// in `tracks` stops being meaningful). Must run inside `liveInputQueue.sync`.
    private func removeAllRemoteTracks() {
        tracks.removeAll { if case .remote = $0.id { return true }; return false }
    }

    /// The (clientID, wire trackID) a track should be announced as in a `sync` broadcast —
    /// this server's own local tracks are reported under `localClientID` (so every client
    /// can tell "the server's own input" apart from another participant's track), a track
    /// already `.remote` is reported under its true owner.
    private func ownerAndWireID(of id: TrackID) -> (clientID: String, trackID: String)? {
        if case .remote(let clientID, let trackID) = id { return (clientID, trackID) }
        guard let wireID = id.wireIDText else { return nil }
        return (localClientID, wireID)
    }

    private func startSyncBroadcastTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + .milliseconds(150), repeating: .milliseconds(150))
        timer.setEventHandler { [weak self] in self?.broadcastSyncSoon() }
        timer.resume()
        syncTimer = timer
    }

    private func broadcastSyncSoon() {
        guard case .server = networkRole, let netServer else { return }
        let snapshot: [RemoteTrackSnapshot] = liveInputQueue.sync {
            tracks.compactMap { track -> RemoteTrackSnapshot? in
                guard let (clientID, wireTrackID) = ownerAndWireID(of: track.id) else { return nil }
                // A `.remote` track already carries its owner's name (set once, in
                // `addOrUpdateRemoteTrack`); a local track's owner is this server itself.
                let ownerName: String? = { if case .remote = track.id { return track.ownerName }; return localClientName }()
                return RemoteTrackSnapshot(
                    clientID: clientID, trackID: wireTrackID, label: track.label, clientName: ownerName,
                    isListening: track.isListening, canHaveSound: track.canHaveSound,
                    heldPitches: Array(track.heldPitches),
                    chordName: track.recognizedChord.map(Self.describe),
                    modesText: track.recognizedModes.isEmpty ? nil : track.recognizedModes.map(Self.describe).joined(separator: ", ")
                )
            }
        }
        netServer.broadcast(NetMessage(kind: .sync, tracks: snapshot))
    }

    // MARK: Client-side message handling

    private func handleClientMessage(_ message: NetMessage) {
        guard message.kind == .sync else { return } // a client only ever receives `sync`
        mergeRemoteSnapshot(message.tracks ?? [])
    }

    /// Replaces every `.remote` entry in `tracks` with a fresh copy built from the server's
    /// latest broadcast, preserving each one's local sound/instrument choice by identity
    /// (mirrors `refreshTracks`'s preserve-by-id pattern) — excludes any entry whose
    /// `clientID` is this participant's own (that track is already present locally, driven
    /// by real local recognition, not as a read-only `.remote` mirror of itself).
    private func mergeRemoteSnapshot(_ snapshot: [RemoteTrackSnapshot]) {
        liveInputQueue.sync {
            let previousRemote = Dictionary(uniqueKeysWithValues: tracks.compactMap { track -> (TrackID, TrackInfo)? in
                guard case .remote = track.id else { return nil }
                return (track.id, track)
            })
            tracks.removeAll { if case .remote = $0.id { return true }; return false }
            for entry in snapshot where entry.clientID != localClientID {
                let id = TrackID.remote(clientID: entry.clientID, trackID: entry.trackID)
                var info = previousRemote[id] ?? TrackInfo(id: id, label: entry.label, canHaveSound: entry.canHaveSound)
                info.label = entry.label
                info.isListening = entry.isListening
                info.heldPitches = Set(entry.heldPitches)
                info.remoteChordDisplay = entry.chordName
                info.remoteModesDisplay = entry.modesText
                info.ownerName = entry.clientName
                tracks.append(info)
            }
        }
    }

    // MARK: Client-side outbound forwarding (called from startTrack/stopTrack/updateRecognitionState)

    private func announceTrackToServerIfClient(_ track: TrackInfo) {
        guard case .client = networkRole, let netClient, let wireID = track.id.wireIDText else { return }
        netClient.send(NetMessage(kind: .trackAnnounce, clientID: localClientID, trackID: wireID, label: track.label, canHaveSound: track.canHaveSound))
    }

    private func unannounceTrackToServerIfClient(_ id: TrackID) {
        guard case .client = networkRole, let netClient, let wireID = id.wireIDText else { return }
        netClient.send(NetMessage(kind: .trackUnannounce, clientID: localClientID, trackID: wireID))
    }

    private func forwardNoteEventToServerIfClient(track: TrackID, isNoteOn: Bool, pitch: Int, velocity: Int, channel: Int) {
        guard case .client = networkRole, let netClient, let wireID = track.wireIDText else { return }
        netClient.send(NetMessage(
            kind: .noteEvent, clientID: localClientID, trackID: wireID,
            isNoteOn: isNoteOn, pitch: pitch, velocity: velocity, channel: channel
        ))
    }

    // MARK: - Recording (SoundTrack — purely event-based, real seconds)

    /// Appends one event to the in-progress recording, if any — called from
    /// `updateRecognitionState`, so already inside `liveInputQueue.sync`. Silently does
    /// nothing for a `.remote` track (its `wireIDText` is `nil`): recording only ever
    /// captures this participant's own local tracks, not another participant's, in this
    /// first version.
    private func captureRecordingEventIfRecording(track: TrackID, isNoteOn: Bool, pitch: Int, velocity: Int) {
        guard isRecording, let recordingStartTime else { return }
        guard recordingTrackFilter == nil || recordingTrackFilter!.contains(track) else { return }
        guard let wireID = track.wireIDText else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- recordingStartTime.uptimeNanoseconds) / 1_000_000_000
        recordingEvents.append(RecordedNoteEvent(timeSeconds: elapsed, trackID: wireID, isNoteOn: isNoteOn, pitch: pitch, velocity: velocity))
    }

    /// Starts recording note on/off events from one or more local tracks in real time —
    /// deliberately incompatible with `Piece`'s measure-based model, see `SoundTrack`'s doc
    /// comment. `tracks` empty (the default) means "every track currently listening";
    /// naming specific tracks restricts capture to just those, even if others are also
    /// listening at the same time.
    public func startRecording(title: String, tracks: Set<TrackID> = []) throws {
        try liveInputQueue.sync {
            guard !isRecording else { throw SessionError.alreadyRecording }
            recordingTitle = title
            recordingTrackFilter = tracks.isEmpty ? nil : tracks
            recordingEvents = []
            recordingStartTime = DispatchTime.now()
            isRecording = true
        }
        append("Enregistrement '\(title)' demarre.")
    }

    /// Stops the in-progress recording and stores the result as `currentSoundTrack` (also
    /// returned, for a caller that wants it immediately without re-reading the property).
    @discardableResult
    public func stopRecording() throws -> SoundTrack {
        let soundTrack: SoundTrack = try liveInputQueue.sync {
            guard isRecording, let recordingStartTime else { throw SessionError.notRecording }
            let duration = Double(DispatchTime.now().uptimeNanoseconds &- recordingStartTime.uptimeNanoseconds) / 1_000_000_000
            let result = SoundTrack(title: recordingTitle ?? "Enregistrement", durationSeconds: duration, events: recordingEvents)
            isRecording = false
            self.recordingStartTime = nil
            recordingTrackFilter = nil
            recordingTitle = nil
            return result
        }
        currentSoundTrack = soundTrack
        currentSoundTrackFilePath = nil
        append("Enregistrement arrete : \(soundTrack.events.count) evenement(s), \(String(format: "%.1f", soundTrack.durationSeconds))s.")
        return soundTrack
    }

    private static let supportedSoundTrackExtensions: Set<String> = ["json"]

    /// Scans `folderPath` for `.json` soundtrack files — mirrors `listPieceFiles`.
    public func listSoundTrackFiles(in folderPath: String) throws {
        let folderURL = URL(fileURLWithPath: folderPath)
        let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        soundTrackFolder = folderPath
        soundTrackFiles = contents
            .filter { Self.supportedSoundTrackExtensions.contains($0.pathExtension.lowercased()) }
            .map(\.lastPathComponent)
            .sorted()
        append(soundTrackFiles.isEmpty
            ? "No .json soundtrack files found in \(folderPath)."
            : "Found \(soundTrackFiles.count) soundtrack file(s) in \(folderPath).")
    }

    public func loadSoundTrack(fromJSONFile path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try JSONDecoder().decode(SoundTrack.self, from: data)
        currentSoundTrack = decoded
        currentSoundTrackFilePath = path
        append("Loaded soundtrack from \(path): \(decoded.title)")
    }

    /// Loads a soundtrack by name from the last-listed folder (see `listSoundTrackFiles`).
    public func loadSoundTrack(named name: String) throws {
        guard let soundTrackFolder else { throw SessionError.noSoundTrackFolderListed }
        try loadSoundTrack(fromJSONFile: URL(fileURLWithPath: soundTrackFolder).appendingPathComponent(name).path)
    }

    /// Convenience over `loadSoundTrack(named:)` using the 0-based position in `soundTrackFiles`.
    public func loadSoundTrack(atIndex index: Int) throws {
        guard soundTrackFiles.indices.contains(index) else { throw SessionError.invalidSoundTrackIndex }
        try loadSoundTrack(named: soundTrackFiles[index])
    }

    public func saveSoundTrack(toJSONFile path: String) throws {
        guard let currentSoundTrack else { throw SessionError.noSoundTrackRecorded }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(currentSoundTrack)
        try data.write(to: URL(fileURLWithPath: path))
        currentSoundTrackFilePath = path
        append("Saved soundtrack to \(path).")
    }

    /// Re-saves `currentSoundTrack` to wherever it was last loaded from or saved to. Fails
    /// if that's never happened yet — use `saveSoundTrack(as:)` for a first save.
    public func saveSoundTrack() throws {
        guard let currentSoundTrackFilePath else { throw SessionError.noCurrentSoundTrackFile }
        try saveSoundTrack(toJSONFile: currentSoundTrackFilePath)
    }

    /// Saves under a new name/path — mirrors `savePiece(as:)`.
    public func saveSoundTrack(as nameOrPath: String) throws {
        let resolvedPath: String
        if nameOrPath.contains("/") {
            resolvedPath = nameOrPath
        } else {
            guard let soundTrackFolder else { throw SessionError.noSoundTrackFolderListed }
            resolvedPath = URL(fileURLWithPath: soundTrackFolder).appendingPathComponent(nameOrPath).path
        }
        try saveSoundTrack(toJSONFile: resolvedPath.hasSuffix(".json") ? resolvedPath : resolvedPath + ".json")
    }

    /// Plays back `currentSoundTrack` in real time — the temporal-mode counterpart to
    /// `play()`. Mirrors `play()`'s own UI-state scheduling (`playbackStateQueue`, a
    /// generation counter guarding against a stale earlier call's callbacks), just driving
    /// `soundTrackHeldPitches`/`isPlayingSoundTrack` instead of `playbackHeldPitches`/`isPlaying`.
    public func playSoundTrack() throws {
        guard let currentSoundTrack else { throw SessionError.noSoundTrackRecorded }
        soundTrackPlayer.play(currentSoundTrack)

        soundTrackPlaybackGeneration += 1
        let generation = soundTrackPlaybackGeneration
        isPlayingSoundTrack = true
        soundTrackHeldPitches = []
        append("Lecture de la soundtrack '\(currentSoundTrack.title)': \(currentSoundTrack.events.count) evenement(s), \(String(format: "%.1f", currentSoundTrack.durationSeconds))s.")

        let now = DispatchTime.now()
        for event in currentSoundTrack.events {
            playbackStateQueue.asyncAfter(deadline: now + event.timeSeconds) { [weak self] in
                guard let self, self.soundTrackPlaybackGeneration == generation else { return }
                if event.isNoteOn {
                    self.soundTrackHeldPitches.insert(event.pitch)
                } else {
                    self.soundTrackHeldPitches.remove(event.pitch)
                }
            }
        }
        playbackStateQueue.asyncAfter(deadline: now + currentSoundTrack.durationSeconds + 0.2) { [weak self] in
            guard let self, self.soundTrackPlaybackGeneration == generation else { return }
            self.isPlayingSoundTrack = false
            self.soundTrackHeldPitches = []
            self.append("Lecture de la soundtrack terminee.")
        }
    }

    /// Asks the AI module to reverse-engineer a measure-based `Piece` structure out of
    /// `currentSoundTrack`'s purely temporal recording — tempo, key, chord progression — and
    /// saves each candidate that survives validation as its own new piece file in
    /// `pieceFolder` (reusing `LLMPieceComposer.parseAndValidate`, exactly the same
    /// validation `composeFromText()` already relies on: an invalid response is dropped
    /// with a warning, never trusted outright). Returns every path actually written — at
    /// least one, or throws if none survived. The last successful candidate becomes the
    /// current `piece` (ready for `show-piece`/`play`), same as `composeFromText()` does;
    /// every candidate, including earlier ones, stays on disk to inspect via `pieces`/`use-piece`.
    /// `title`, when given, overrides the LLM's own chosen title (and therefore the saved
    /// file's base name too) — every candidate gets the same title, distinguished only by
    /// the usual `-candidat-N` suffix, same as an unnamed run.
    @discardableResult
    public func composeSoundTrackToPieces(
        candidateCount: Int = 1, title: String? = nil, generate: (String, LLMConnection) throws -> String = LLMClient.generate
    ) throws -> [String] {
        guard let connection = currentLLMConnection else { throw SessionError.noLLMConnectionSelected }
        guard let pieceFolder else { throw SessionError.noPieceFolderListed }
        let prompt = try currentSoundTrackCompositionPrompt()

        let count = max(1, candidateCount)
        var savedPaths: [String] = []
        for index in 1...count {
            append("Generation du candidat \(index)/\(count) a partir de la soundtrack...")
            let responseText = try generate(prompt, connection)
            let (candidatePiece, warnings) = LLMPieceComposer.parseAndValidate(responseText: responseText)
            for warning in warnings { append("Compose warning (candidat \(index)): \(warning)") }
            guard var candidatePiece else {
                append("Candidat \(index): echec, rien d'utilisable dans la reponse.")
                continue
            }
            if let title { candidatePiece.title = title }
            let suffix = count > 1 ? "-candidat-\(index)" : ""
            let path = URL(fileURLWithPath: pieceFolder).appendingPathComponent("\(candidatePiece.title)\(suffix).json").path
            try writePieceToDisk(candidatePiece, at: path)
            savedPaths.append(path)
            append("Candidat \(index) sauvegarde: \(path)")
            if index == count {
                piece = candidatePiece
                currentPieceFilePath = path
            }
        }
        guard !savedPaths.isEmpty else { throw SessionError.llmComposeFailed(["no candidate survived validation"]) }
        return savedPaths
    }

    /// Encodes and writes an arbitrary `Piece` value directly — unlike `savePiece(toJSONFile:)`,
    /// doesn't read/require `self.piece`, since `composeSoundTrackToPieces` needs to write
    /// several candidate pieces to disk without each one having to first become "the"
    /// current piece.
    private func writePieceToDisk(_ piece: Piece, at path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(piece)
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func append(_ message: String) {
        log.append(message)
    }

    /// A minimal ii-V-I in C major — Dm7-G7-Cmaj7 with an arpeggio melody — used as a
    /// ready-to-play piece without needing a JSON file on hand.
    public static func iiVIDemoPiece() -> Piece {
        let key = ModeReference(tonic: 0, scaleID: "ionian")

        let chordProgression = [
            ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 2, chordTemplateID: "mi7")),
            ChordEvent(measure: 2, beat: 1, durationBeats: 4, chord: ChordReference(root: 7, chordTemplateID: "7")),
            ChordEvent(measure: 3, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma7"), playingStyle: .arpeggioUp),
        ]

        let melodyEvents = [
            MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 62),
            MelodyEvent(measure: 1, beat: 2, durationBeats: 1, pitch: 65),
            MelodyEvent(measure: 1, beat: 3, durationBeats: 1, pitch: 69),
            MelodyEvent(measure: 1, beat: 4, durationBeats: 1, pitch: 72),
            MelodyEvent(measure: 2, beat: 1, durationBeats: 1, pitch: 55),
            MelodyEvent(measure: 2, beat: 2, durationBeats: 1, pitch: 59),
            MelodyEvent(measure: 2, beat: 3, durationBeats: 1, pitch: 62),
            MelodyEvent(measure: 2, beat: 4, durationBeats: 1, pitch: 65),
            MelodyEvent(measure: 3, beat: 1, durationBeats: 1, pitch: 60),
            MelodyEvent(measure: 3, beat: 2, durationBeats: 1, pitch: 64),
            MelodyEvent(measure: 3, beat: 3, durationBeats: 1, pitch: 67),
            MelodyEvent(measure: 3, beat: 4, durationBeats: 2, pitch: 72),
        ]

        let melodyTrack = Track(name: "melody", instrument: "", melodyEvents: melodyEvents)
        let section = Section(name: "A", lengthInMeasures: 3, mode: key, chordProgression: chordProgression, tracks: [melodyTrack])
        return Piece(title: "ii-V-I demo", tempoBPM: 96, key: key, sections: [section])
    }
}
