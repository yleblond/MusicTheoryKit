import Foundation
import Observation
import SwiftData
import CoreData
import Localization
import MusicTheoryKit
import PieceModel
import SoundTrackModel
import AudioEngine
import MIDIEngine
import SoundFontModel
import RecognitionEngine
import LLMEngine
import NetEngine
import WebConsole
import GameKit

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
    /// port — see `setMIDIFusionMode`. Changing it rebuilds `tracks`. Defaults to
    /// `.individual`: a per-port track is what lets `ImprovSession.LumiLiveModeLastState
    /// .current` single out the LUMI's own track by name when other MIDI devices are also
    /// attached, rather than guessing from "whichever track happens to be listening".
    public private(set) var midiFusionMode: MIDIFusionMode = .individual
    /// Whether the physical/hardware computer keyboard currently plays notes (see
    /// `JamShackUI.computerKeyboardNoteMap`) — off by default, unlike a MIDI keyboard (which
    /// only ever sends a note message when actually played): every letter key typed ANYWHERE
    /// in the app would otherwise double as a note trigger, colliding with ordinary typing
    /// (aliasing a sound, naming a piece, searching...) and with other screens' own keyboard
    /// shortcuts (e.g. the Guide's arrow-key navigation). Toggled explicitly from a dedicated
    /// "Clavier ordinateur" sub-tab (see `setComputerKeyboardInputEnabled`) — session-only, not
    /// persisted, same "starts at a safe default every launch" convention as `midiFusionMode`.
    public private(set) var computerKeyboardInputEnabled = false
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
    /// User-assigned alias/favorite metadata, keyed by the same relative-path strings as
    /// `sampleFiles` — see `SoundEntry`/`setSoundAlias`/`setSoundFavorite`/`favoriteSampleFiles`.
    /// Persisted to `sound-settings.json`, only entries the user has actually touched.
    public private(set) var soundEntries: [SoundEntry] = []
    /// Every soundfont known to this device — indexed by content hash (see `SoundFontEntry`),
    /// backed by `SoundFontRecord` in the same shared CloudKit-synced store as everything else.
    /// Unlike `sampleFiles` (a raw folder scan, still used by the CLI), an entry here can exist
    /// even when its bytes aren't downloaded on THIS device yet (`soundFontPath(forHash:)`
    /// returns `nil` in that case) — see `startSoundFontLibrary`.
    public private(set) var soundFonts: [SoundFontEntry] = []
    /// Every piece's title currently in the SwiftData store, sorted — mirrors
    /// `guideSequenceNames`. Refreshed after every migrate/insert/update/delete.
    public private(set) var pieceNames: [String] = []
    /// The `PieceRecord.id` `piece` was last loaded from/saved to — what a bare `savePiece()`
    /// (no name) re-saves to. `nil` until a load/save-as has happened once. Replaces the old
    /// file-path-based `currentPieceFilePath` now that pieces live in SwiftData, not files.
    public private(set) var currentPieceRecordID: String?
    /// The currently authored/loaded mode sequence for the Guide screen (see `startGuide`/
    /// `advanceGuideStep`) — independent of `piece`: a guide step is only "which mode",
    /// never a timed composition.
    public private(set) var currentGuide: GuideSequence?
    /// The `GuideSequenceRecord.id` `currentGuide` was last loaded from/saved to — `nil` for a
    /// brand-new guide never saved to the store yet. Replaces the old file-path-based
    /// `currentGuideFilePath` now that guide sequences live in SwiftData, not files (see
    /// `useGuideSequence`/`saveGuideSequence`).
    public private(set) var currentGuideRecordID: String?
    /// `nil` means the guide is loaded (or absent) but not started — see `startGuide`/`stopGuide`.
    public private(set) var currentGuideStepIndex: Int?
    /// Which chord of the current step's `chordProgression` is "proposed" right now — `nil`
    /// whenever the guide isn't running, the current step has no progression attached, or no
    /// chord has been navigated to yet. See `advanceGuideChord`/`currentGuideChordReference`.
    /// Deliberately a separate axis from `currentGuideStepIndex` (up/down moves steps/modes,
    /// left/right moves chords within one) rather than one flat "position in the whole
    /// guide" — a step with no chords still needs to be a normal stop for up/down navigation.
    public private(set) var currentGuideChordIndex: Int?
    /// The active scene — an ongoing document (declared roles + which live instrument each
    /// one is attached to, see `Sources/AppCore/Scene.swift`'s own doc comments), mirroring
    /// `currentGuide`/`currentGuideRecordID`'s shape rather than the one-shot "snapshot
    /// tracks, write once" model this used to be.
    public private(set) var currentScene: Scene?
    /// Set only by the raw `loadScene(fromJSONFile:)`/`saveScene(title:toJSONFile:)` pair —
    /// used by `SceneFileView`'s single-file export/import feature (and its own "Recharger"
    /// reload button), completely independent of `currentSceneRecordID` below.
    public private(set) var currentSceneFilePath: String?
    /// The `SceneRecord.id` `currentScene` was last saved to via `saveScene(title:as:)`/
    /// loaded from via `useScene` — `nil` for a brand-new scene never saved to the store yet.
    public private(set) var currentSceneRecordID: String?
    /// Every palette loaded from the SwiftData store (see
    /// `migrateColorPalettesFromJSONIfNeeded`) — always at least one entry
    /// (`MusicTheoryKit.PitchClassPalette.hex` as "Default" until migration/seeding runs).
    public private(set) var colorPalettes: [ColorPalette] = [ColorPalette.builtInDefaults[0]]
    /// Which of `colorPalettes` is active — per-instance only, never persisted (the store
    /// lists what's *available*, not what's currently selected); resets to the first palette
    /// every time migration runs.
    public private(set) var activeColorPaletteIndex: Int = 0
    /// Bounds-checked rather than a plain subscript: `buildWebConsoleState()` reads this from
    /// a detached background task (see `SessionUIBridge`) with no synchronization against
    /// `migrateColorPalettesFromJSONIfNeeded`/`selectColorPalette` mutating `colorPalettes`/
    /// `activeColorPaletteIndex` on the main actor — the same class of benign cross-thread
    /// read documented on `SessionUIBridge`, except an out-of-range index here crashes instead
    /// of just returning a stale value, so it falls back to the first palette instead.
    public var activeColorPalette: ColorPalette {
        colorPalettes.indices.contains(activeColorPaletteIndex) ? colorPalettes[activeColorPaletteIndex] : ColorPalette.builtInDefaults[0]
    }
    /// Every composition description's addressable name currently in the SwiftData store,
    /// sorted — mirrors `guideSequenceNames`. Refreshed after every migrate/insert/update/delete.
    public private(set) var compositionDescriptionNames: [String] = []
    /// The `CompositionDescriptionRecord.id` the current description was last loaded from/saved
    /// to — replaces the old file-path-based `currentCompositionFilePath`.
    public private(set) var currentCompositionRecordID: String?
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
    /// Names of every `LLMConnectionRecord` currently stored in `modelContainer` — refreshed
    /// by `refreshLLMConnections()` after every mutation. No longer folder-backed: LLM
    /// connections live in a private SwiftData store (`Application Support`, not the user's
    /// chosen Reglages folder), migrated once from any pre-existing `LLMConnections/*.json`
    /// folder (see `migrateLLMConnectionsFromJSONIfNeeded`) or seeded from
    /// `LLMConnectionTemplates.builtIn` on a fresh install.
    public private(set) var llmConnections: [String] = []
    public private(set) var currentLLMConnection: LLMConnection?
    /// Root folder for settings that are per-INSTALL, not per-PIECE (see `setSettingsFolder`)
    /// — `palettes.json`, `chordprogressions.json`, and the `LLMConnections` subfolder all
    /// live under here as one unit, unlike `pieceFolder`/`sampleFolder`/etc., which each stay
    /// independently choosable.
    public private(set) var settingsFolder: String?
    /// Root folder for the whole "Composition IA" toolkit (see `setPromptsFolder`) — the
    /// prompt sent to the LLM is *always* recomposed from three independently-managed parts
    /// (never loaded/replaced as one opaque blob — see `currentTextCompositionPrompt()`):
    /// a framing sentence, the source data (pasted text/description, or a `SoundTrack`), and
    /// optional style indications. This folder holds one fixed subfolder per part/kind —
    /// see `setPromptsFolder`'s doc comment for the full layout.
    public private(set) var promptsFolder: String?
    /// The "framing sentence" (the part of the prompt before the JSON schema, see
    /// `LLMPieceComposer.defaultTextFramingSentence`) overridden via
    /// `setTextFramingSentence`/`useTextFramingSentence` — `nil` means "use the built-in
    /// default."
    public private(set) var activeTextFramingSentence: String?
    public private(set) var activeSoundTrackFramingSentence: String?
    /// Saved framing-sentence names, in the SwiftData store (see `PromptSnippetRecord`) —
    /// refreshed after every migrate/insert/delete.
    public private(set) var textFramingSentenceNames: [String] = []
    public private(set) var soundTrackFramingSentenceNames: [String] = []
    /// Style indications for composing from a `SoundTrack` — the soundtrack counterpart of
    /// `additionalCompositionInstructions` (text composition bundles its indications into a
    /// saved `CompositionDescription` instead; a `SoundTrack` has no such bundle to attach
    /// them to, so they get their own save/load slot here, same pattern as the framing
    /// sentence). `nil` means "none" — unlike the framing sentence, there's no default text
    /// to fall back to.
    public private(set) var activeSoundTrackCompositionInstructions: String?
    public private(set) var soundTrackInstructionsNames: [String] = []
    /// Whether a `SoundTrack` recording is currently underway — see `startRecording`/
    /// `stopRecording`. Deliberately independent of `isPlaying` (that's the *other*,
    /// measure-based playback mode — see `SoundTrack`'s doc comment for why the two don't mix).
    public private(set) var isRecording = false
    /// The most recently recorded or loaded `SoundTrack` — the temporal-recording
    /// counterpart to `piece`. `nil` until a recording finishes or a file is loaded once.
    public private(set) var currentSoundTrack: SoundTrack?
    /// The `SoundTrackRecord.id` `currentSoundTrack` was last loaded from/saved to — `nil` for
    /// a brand-new recording never saved to the store yet. Replaces the old
    /// file-path-based `currentSoundTrackFilePath` now that soundtracks live in SwiftData, not
    /// files (see `useSoundTrack`/`saveSoundTrack`).
    public private(set) var currentSoundTrackRecordID: String?
    /// Whether `playSoundTrack()` is currently playing back `currentSoundTrack` — the
    /// temporal-mode counterpart to `isPlaying` (`Piece` playback). The two are independent
    /// and could in principle run at once, though nothing stops them from clashing audibly
    /// if you actually try that.
    public private(set) var isPlayingSoundTrack = false
    /// Every pitch currently sounding because of `playSoundTrack()` — mirrors
    /// `playbackHeldPitches` for the temporal-recording playback mode.
    public private(set) var soundTrackHeldPitches: Set<Int> = []
    /// A third, independent playback mode alongside `isPlaying`/`isPlayingSoundTrack` — "listen
    /// to the active guide" (see `startGuideAudition(speedFactor:)`), no held-pitches display of
    /// its own since nothing in the Guide screens shows it live yet.
    public private(set) var isAuditioningGuide = false

    private let player = PiecePlayer()
    private let soundTrackPlayer = SoundTrackPlayer()
    private let guideAuditionPlayer = GuideAuditionPlayer()
    private var midiListeners: [TrackID: MIDIInputListener] = [:]
    /// Purely diagnostic — one lightweight `MIDIInputListener` per currently-visible MIDI
    /// source, kept connected regardless of whether that source's corresponding track is
    /// actually being listened to (unlike `midiListeners`, which only exists for a *started*
    /// track). Lets `printTracks`/`scene-tree` show a device's MIDI channel (see
    /// `observedChannel(forMIDISourceIndex:)`) just from having it plugged in, without
    /// requiring "ecouter l'instrument" first — a channel can only ever be learned once a
    /// message actually arrives, but there's no reason that has to be the track's own real
    /// listening path. Rebuilt from scratch by `refreshPassiveChannelSniffers()` (called
    /// wherever `refreshTracks()` is), same all-or-nothing rebuild as `tracks` itself. Keyed
    /// by the same index `TrackID.midiSource(Int)` uses — meaningless in merged mode, where
    /// there's no single physical source a track maps to.
    private var passiveChannelSniffers: [Int: MIDIInputListener] = [:]
    /// Deliberately NOT `liveInputQueue`, unlike almost everything else a live callback thread
    /// touches — see `passiveObservedChannels`'s own doc comment for the deadlock this avoids.
    private let passiveChannelQueue = DispatchQueue(label: "ImprovSession.passiveChannel")
    /// Written from whichever CoreMIDI callback thread each sniffer above happens to fire on,
    /// read via `observedChannel(forMIDISourceIndex:)` — guarded by `passiveChannelQueue`, NOT
    /// `liveInputQueue`. This one had to be `@ObservationIgnored` (see `microphoneSpectrumSnapshot`'s
    /// own doc comment for that half of the reasoning) AND on its own dedicated queue, confirmed
    /// by a live `sample` of an actually-frozen process: `displayedChannel(for:)`/
    /// `labelWithChannel(_:)` are now read from several SwiftUI view bodies on the main thread
    /// (JamShack MIDI tab, Sons test-source picker, Scene role rows), and reading through
    /// `liveInputQueue.sync` there deadlocked against the real-time MIDI callback thread even
    /// AFTER `@ObservationIgnored` alone: the sample showed the callback thread parked inside
    /// `liveInputQueue` (running `handleIncomingMIDIEvent` → `refreshRecognition`, mutating the
    /// legitimately-observed `tracks`) waiting on SwiftUI's own Observation lock
    /// (`_MovableLockLock`/`ObservationCenter.invalidate`), while the main thread — which had
    /// already taken that very lock to evaluate `SceneRoleRow.body` — sat blocked waiting for
    /// `liveInputQueue`'s ownership token via this property's own `.sync` read. Two threads,
    /// each holding what the other one blocks on: a real deadlock, not just lock contention,
    /// and unrelated to which specific property is Observed — sharing `liveInputQueue` at all
    /// from a main-thread read is what creates the cycle, since ANY concurrent mutation of
    /// `tracks` on that queue can end up wanting the same Observation lock the main thread may
    /// already hold. A queue this property never shares with `tracks`'s own mutations breaks
    /// the cycle outright, same "isolated, otherwise-unused queue" precedent as
    /// `microphoneSpectrumQueue`.
    @ObservationIgnored
    private var passiveObservedChannels: [Int: Int] = [:]
    private var microphoneListener: MicrophonePitchListener?
    /// One independent chord/mode recognizer per track — created the first time a track
    /// starts listening, kept (not discarded) across a stop so `reset()` on the next start
    /// is the only thing that clears its history.
    private var recognizers: [TrackID: RecognitionEngine] = [:]
    /// One independent sampler per track with sound enabled — see `setSoundEnabled`. Never
    /// present for `.microphone` (enforced there, not here).
    private var samplers: [TrackID: SamplerUnit] = [:]

    /// Test-only peek at whether a track's own sampler is actually running (see
    /// `SamplerUnit.isRunning`'s doc comment for why this matters) — `samplers` itself stays
    /// `private`, an implementation detail no other caller needs. `nil` if this track never
    /// had a sampler created at all.
    func samplerIsRunning(for id: TrackID) -> Bool? {
        samplers[id]?.isRunning
    }
    /// One `MicrophonePitchStabilizer` per microphone track (today there's only ever one,
    /// `.microphone`, but keyed by `TrackID` for consistency with `recognizers`/`samplers`),
    /// created in `startTrack` from that track's `microphoneRecognitionMode` and discarded in
    /// `stopTrack` — see `handleDetectedPitches` for how it turns raw per-window detections
    /// into debounced note-on/note-off transitions, replacing what used to be a same-window
    /// direct diff with no smoothing at all.
    private var pitchStabilizers: [TrackID: MicrophonePitchStabilizer] = [:]
    /// One rolling event log per track, appended in `refreshRecognition` the instant the
    /// held-pitches/chord actually changes — see `WebConsoleTrackState.recentChordEvents`'s
    /// own doc comment for why this lives here (server-side, change-triggered) rather than
    /// being reconstructed client-side by diffing successive `GET /state` polls.
    private var recentChordEvents: [TrackID: [WebConsoleChordEvent]] = [:]
    private static let maxRecentChordEvents = 20
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
    /// Protocol-typed (not the concrete `NetworkServer`/`NetworkClient`) so either the
    /// local-network transport or `GameCenterTransport` can be stored/called the same way —
    /// see `NetworkServerTransport`/`NetworkClientTransport`'s own doc comments.
    private var netServer: (any NetworkServerTransport)?
    private var netClient: (any NetworkClientTransport)?
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
    private var virtualKeyboardServer: HTTPServer?
    /// `nil` when inactive — the port the interactive browser keyboard (see
    /// `startVirtualKeyboard`) is currently listening on.
    public private(set) var virtualKeyboardPort: Int?
    #if os(macOS)
    /// `nil` when inactive — see `startMCPServerIfEnabled`/`setMCPServerEnabled`.
    private var mcpServer: MCPServer?
    #endif
    /// `nil` when LUMI "live display" mode (see `startLumiLiveDisplay`) is off. Written and
    /// read only inside `liveInputQueue` — it's consulted from `syncLumiLiveModeIfActive()`,
    /// which runs on whatever thread delivered the live MIDI/microphone event that just
    /// happened, same as every other piece of per-track state this queue already guards.
    private var lumiLiveModeConfig: LumiDisplayConfig?
    /// The last state actually pushed to the LUMI, so `syncLumiLiveModeIfActive()` only
    /// sends new SysEx when the recognized mode (or lack thereof) really changed — without
    /// this, every single note-on/off while live mode is active would re-send the full
    /// guide-map/`.piano` message set, most of the time for no visible change. `.none` is a
    /// pure "nothing pushed yet" sentinel (distinct from `.piano`, an actual pushed state)
    /// so `startLumiLiveDisplay` reliably pushes an initial state instead of silently no-op'ing
    /// if the first computed state happens to be `.piano`.
    private var lumiLiveModeLastState: LumiLiveModeLastState = .none
    /// `nil` when LUMI "guide display" sync (see `startLumiGuideDisplay`) is off. Unlike
    /// `lumiLiveModeConfig`, this is only ever touched from the main thread (guide-step
    /// navigation is driven by the terminal's own key handling, not a background MIDI/
    /// microphone callback), so it needs no queue of its own.
    private var lumiGuideDisplayConfig: LumiDisplayConfig?
    /// Same "avoid resending identical SysEx" purpose as `lumiLiveModeLastState`, for the
    /// guide screen's current step instead of live recognition.
    private var lumiGuideDisplayLastState: LumiGuideDisplayLastState = .none
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
    /// Same role as `playbackGeneration`/`soundTrackPlaybackGeneration`, for `startGuideAudition(speedFactor:)`.
    private var guideAuditionGeneration = 0

    public enum SessionError: Error, CustomStringConvertible {
        case noPieceLoaded
        case noSampleFolderListed
        case invalidSampleIndex
        case invalidPieceIndex
        case noCurrentPieceFile
        case invalidLLMConnectionIndex
        case noSourceText
        case noLLMConnectionSelected
        case llmComposeFailed([String])
        case unknownTrack(String)
        case trackCannotHaveSound
        case recognitionModeOnlyForMicrophone
        case invalidRecognitionWindowCount
        case remoteTrackListeningIsNotLocal
        case networkRoleAlreadyActive
        case alreadyRecording
        case notRecording
        case noSoundTrackRecorded
        case invalidSoundTrackIndex
        case noCurrentSoundTrackFile
        case invalidPieceSectionIndex
        case invalidPieceTrackIndex
        case noPromptsFolderListed
        case webConsoleAlreadyActive
        case invalidTextFramingIndex
        case invalidSoundTrackFramingIndex
        case invalidCompositionIndex
        case noCurrentCompositionFile
        case noSoundTrackCompositionInstructions
        case invalidSoundTrackInstructionsIndex
        case invalidIconSuggestion
        case noGuideSequence
        case invalidModeReference
        case invalidGuideIndex
        case invalidGuideStepIndex
        case invalidChordIndex
        case noCurrentGuideFile
        case invalidSceneIndex
        case noSceneLoaded
        case unknownSceneRole
        case virtualKeyboardAlreadyActive
        case invalidColorPaletteIndex
        case invalidColorPaletteFile
        case lumiDestinationNotFound
        case invalidLumiColorHex
        case invalidLumiBrightness
        public var description: String {
            switch self {
            case .noPieceLoaded: return "no piece loaded — try 'load-demo' or 'load <path>'"
            case .noSampleFolderListed: return "no sample folder listed yet — try 'samples <folder>' first"
            case .invalidSampleIndex: return "no sample at that index"
            case .invalidPieceIndex: return "no piece at that index or name"
            case .noCurrentPieceFile: return "this piece was never saved — try 'save-as <name>'"
            case .invalidLLMConnectionIndex: return "no LLM connection at that index"
            case .noSourceText: return "no source text set — try 'paste-text' first"
            case .noLLMConnectionSelected: return "no LLM connection selected — try 'use-llm <n|name>' first"
            case .llmComposeFailed(let warnings): return "composition failed: \(warnings.joined(separator: "; "))"
            case .unknownTrack(let text): return "no such track '\(text)' — try 'tracks' first"
            case .trackCannotHaveSound: return "this track can't produce sound (the microphone is never sounded through the app, to avoid feedback)"
            case .recognitionModeOnlyForMicrophone: return "recognition mode only applies to the microphone track"
            case .invalidRecognitionWindowCount: return "window count must be at least 1"
            case .remoteTrackListeningIsNotLocal: return "this track belongs to another participant — its listening state is controlled on their machine, not this one"
            case .networkRoleAlreadyActive: return "already running as a server or connected as a client — disconnect/stop first"
            case .alreadyRecording: return "already recording — try 'stopRecording' first"
            case .notRecording: return "not currently recording"
            case .noSoundTrackRecorded: return "no soundtrack recorded or loaded yet — try 'startRecording' or load one"
            case .invalidSoundTrackIndex: return "no soundtrack at that index or name"
            case .noCurrentSoundTrackFile: return "this soundtrack was never saved — try saving with an explicit name"
            case .invalidPieceSectionIndex: return "no section at that index — try 'show-piece' first"
            case .invalidPieceTrackIndex: return "no track at that index in that section — try 'show-piece' first"
            case .noPromptsFolderListed: return "no composition-IA folder listed yet — try 'prompts <folder>' first"
            case .webConsoleAlreadyActive: return "web console already running — stop it first"
            case .invalidTextFramingIndex: return "no text framing sentence at that index"
            case .invalidSoundTrackFramingIndex: return "no soundtrack framing sentence at that index"
            case .invalidCompositionIndex: return "no composition description at that index or name"
            case .noCurrentCompositionFile: return "this description was never saved — try saving with an explicit name"
            case .noSoundTrackCompositionInstructions: return "no soundtrack style indications set — try 'set-soundtrack-instructions <texte>' first"
            case .invalidSoundTrackInstructionsIndex: return "no soundtrack style indications at that index"
            case .invalidIconSuggestion: return "the LLM's icon suggestion wasn't one of the allowed icon names"
            case .noGuideSequence: return "no guide sequence — try 'guide-new <titre>' first, or load one"
            case .invalidModeReference: return "unknown tonic or scale id — the scale id must match ScaleLibrary (e.g. ionian, dorian, phrygian, lydian, mixolydian, aeolian, locrian)"
            case .invalidGuideIndex: return "no guide sequence at that index or name"
            case .invalidGuideStepIndex: return "no step at that index in the guide sequence"
            case .invalidChordIndex: return "no chord at that index in the step's progression"
            case .noCurrentGuideFile: return "this guide sequence was never saved — try 'save-guide-as <name>'"
            case .invalidSceneIndex: return "no scene at that index or name"
            case .noSceneLoaded: return "no active scene — try 'scene-new <titre>' first, or load one"
            case .unknownSceneRole: return "no role with that id in the active scene"
            case .virtualKeyboardAlreadyActive: return "virtual keyboard already running — stop it first"
            case .invalidColorPaletteIndex: return "no color palette at that index"
            case .invalidColorPaletteFile: return "a palette needs exactly 12 colors (one per pitch class)"
            case .lumiDestinationNotFound: return "couldn't auto-detect a single LUMI MIDI destination — pass destinationIndex explicitly (see MIDIOutputPort.destinationDescriptors())"
            case .invalidLumiColorHex: return "color must be a 6-digit hex string, e.g. #FF0000"
            case .invalidLumiBrightness: return "brightness must be 0...100"
            }
        }
    }

    /// Set only via `init(modelContainer:)` (tests inject an in-memory container here) — `nil`
    /// means "create the real on-disk one lazily, on first actual use."
    @ObservationIgnored private let modelContainerOverride: ModelContainer?
    /// The private, app-container SwiftData store backing every `@Model` record in this class
    /// (LLM connections, color palettes, chord progression templates, language, LUMI/
    /// spectrogram/note-color/microphone-calibration settings, sound entries) — deliberately
    /// NOT inside the user-chosen Reglages folder (see e.g.
    /// `migrateLLMConnectionsFromJSONIfNeeded`): none of this data has any reason to depend on
    /// an external folder/security-scoped bookmark. One shared container/schema for every
    /// category, not one per category — same rationale as sharing a single CloudKit container
    /// (`iCloud.com.jamshack.JamShackApp`) rather than registering a new one per feature.
    /// Lazy, not created in `init()`: hundreds of `ImprovSession()` instances across this
    /// project's own test suite never touch any of this, and shouldn't each pay for (or risk
    /// sharing) a real on-disk SwiftData container just for existing.
    ///
    /// Three tiers, each a graceful fallback from the one before — never a crash, never a hard
    /// requirement on iCloud:
    /// 1. CloudKit-backed private database (`iCloud.com.jamshack.JamShackApp`, see the iCloud
    ///    entitlements in `App/project.yml`) — syncs across every device signed into the same
    ///    iCloud account. Every record type's fields already satisfy CloudKit's schema
    ///    constraints (every property has a default or is optional, no unique constraints, no
    ///    relationships), so no model changes were needed to support this.
    /// 2. Local-only on-disk store — exactly today's behavior, reached when there's no iCloud
    ///    account signed in, or this build isn't signed with the CloudKit capability (e.g. an
    ///    ad-hoc "Sign to Run Locally" build with no Development Team configured).
    /// 3. In-memory — should never actually happen in practice (nothing external for it to
    ///    fail on).
    @ObservationIgnored private lazy var modelContainer: ModelContainer = {
        if let modelContainerOverride { return modelContainerOverride }
        let schema = Schema([
            LLMConnectionRecord.self,
            ColorPaletteRecord.self,
            ChordProgressionTemplateRecord.self,
            LanguageSettingRecord.self,
            NotationStyleSettingRecord.self,
            TheoryAuditionSoundSettingRecord.self,
            ChordTemplateRecord.self,
            ScaleDefinitionRecord.self,
            LumiSettingsRecord.self,
            SpectrogramSettingsRecord.self,
            NoteColorSettingsRecord.self,
            MicrophoneCalibrationSettingsRecord.self,
            SoundEntryRecord.self,
            GuideSequenceRecord.self,
            SceneRecord.self,
            SoundTrackRecord.self,
            PromptSnippetRecord.self,
            CompositionDescriptionRecord.self,
            PieceRecord.self,
            MIDIDeviceIconRecord.self,
            SoundFontRecord.self,
            CloudStorageThresholdRecord.self,
        ])
        if let container = try? ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.com.jamshack.JamShackApp"))
        ) {
            return container
        }
        append("Warning: iCloud sync unavailable (no iCloud account, or this build isn't signed with the CloudKit capability) — falling back to local-only storage.")
        if let container = try? ModelContainer(for: schema) { return container }
        // Last-resort fallback — an in-memory container has nothing external to fail on, so
        // this should never actually happen in practice.
        append("Warning: could not open the on-disk settings store — using an in-memory one for this session (nothing will persist).")
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }()
    /// A single context owned by this session, not `modelContainer.mainContext` — that
    /// property is `@MainActor`-isolated, which would force every method below to become
    /// `async`, rippling into the CLI/tests/SwiftUI call sites for no real benefit (this class
    /// already treats itself as effectively single-threaded for its own state, per its own
    /// `@unchecked Sendable` rationale above).
    @ObservationIgnored private lazy var modelContext = ModelContext(modelContainer)

    /// Owns `NSMetadataQuery`-based discovery/reconciliation of soundfont files — see
    /// `startSoundFontLibrary`. Lazy for the same reason as `modelContainer`/`modelContext`:
    /// most test-only `ImprovSession()` instances never touch soundfonts at all.
    @ObservationIgnored private lazy var soundFontLibrary = SoundFontLibrary(modelContext: modelContext)

    /// Registered once, in `start()` — not `init()`, so the hundreds of test-only
    /// `ImprovSession()` instances that never call `start()` never pay for it. Holds the
    /// token so `deinit` can unregister it; without that, every `makeTestSession()` across a
    /// whole `swift test` run would leak one more permanent `NotificationCenter` observer.
    @ObservationIgnored private var remoteChangeObserverToken: NSObjectProtocol?

    public init(modelContainer: ModelContainer? = nil) {
        localClientID = UUID().uuidString
        modelContainerOverride = modelContainer
        refreshTracks()
    }

    deinit {
        if let remoteChangeObserverToken {
            NotificationCenter.default.removeObserver(remoteChangeObserverToken)
        }
    }

    public func start() throws {
        try player.start()
        try soundTrackPlayer.start()
        try guideAuditionPlayer.start()
        try theoryLibraryAuditionPlayer.start()
        append("Audio engine started.")
        startObservingRemoteStoreChanges()
    }

    /// CloudKit imports remote changes into `modelContainer`'s underlying store in the
    /// background regardless of this observer — but nothing previously refreshed this
    /// session's own cached name lists (`sceneNames`, `pieceNames`, etc.) when that happened,
    /// so a device already running wouldn't see a scene/piece/etc. created on another device
    /// until restarted. `.NSPersistentStoreRemoteChange` fires for ANY change to the
    /// underlying store — local writes too, not just CloudKit imports — so this is a cheap
    /// "re-fetch everything" rather than trying to interpret what changed. Deliberately does
    /// NOT touch whatever document is currently open/being edited (`currentScene`,
    /// `currentPiece`, etc.) — only the list-level name arrays — so a remote change can never
    /// clobber in-progress local edits.
    private func startObservingRemoteStoreChanges() {
        guard remoteChangeObserverToken == nil else { return }
        remoteChangeObserverToken = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: nil
        ) { [weak self] _ in
            // `queue: nil` delivers this synchronously on whatever thread posted the
            // notification (a CloudKit-sync background thread, not necessarily this session's
            // own thread) — hop to the main thread before touching `modelContext` (SwiftData
            // contexts are thread-confined to wherever they were created, here the main
            // thread/actor via `ContentView`'s `.task`) or any `@Observable` property.
            DispatchQueue.main.async { self?.refreshAllStoreBackedNameLists() }
        }
    }

    private func refreshAllStoreBackedNameLists() {
        refreshLLMConnections()
        refreshColorPalettes()
        refreshChordProgressionTemplates()
        refreshChordTemplates()
        refreshScaleDefinitions()
        refreshSceneNames()
        refreshGuideSequenceNames()
        refreshSoundTrackNames()
        refreshPieceNames()
        refreshCompositionDescriptionNames()
        refreshSoundEntries()
        // Previously missing here — a change from ANOTHER device (e.g. importing a soundfont,
        // toggling its sync preference) only ever showed up on this one after a full relaunch,
        // never live, because nothing refreshed `soundFonts` in reaction to CloudKit's own
        // remote-change notification. Confirmed as a real contributor to "two devices show
        // different synced files": each device's view was only ever as fresh as its last
        // launch, not its last CloudKit sync.
        refreshSoundFonts()
        refreshCloudStorageThreshold()
        textFramingSentenceNames = refreshPromptSnippetNames(category: .textFraming)
        soundTrackFramingSentenceNames = refreshPromptSnippetNames(category: .soundTrackFraming)
        soundTrackInstructionsNames = refreshPromptSnippetNames(category: .soundTrackInstructions)
    }

    public func loadDemoPiece() {
        piece = Self.iiVIDemoPiece()
        append("Loaded demo piece: \(piece!.title)")
    }

    /// Starts a blank piece (no sections yet) — the entry point for composing one, by hand
    /// or via `composeFromText()`, rather than loading an existing file.
    public func newPiece(title: String, tempoBPM: Double = 100, key: ModeReference = ModeReference(tonic: 0, scaleID: "ionian")) {
        piece = Piece(title: title, tempoBPM: tempoBPM, key: key)
        currentPieceRecordID = nil
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

    // MARK: - Composition descriptions (save/load title+text+indications for later reuse)

    private static let supportedCompositionExtensions: Set<String> = ["json"]

    /// Raw file I/O, unchanged in behavior — kept for reuse by the migration below and any
    /// future explicit-path caller. NOT the primary persistence path anymore (see
    /// `useCompositionDescription`/`saveCompositionDescription(as:)`).
    public func loadCompositionDescription(fromJSONFile path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try JSONDecoder().decode(CompositionDescription.self, from: data)
        setCompositionTitle(decoded.title)
        setSourceText(decoded.sourceText)
        setAdditionalCompositionInstructions(decoded.additionalInstructions)
        currentCompositionRecordID = nil
        append("Loaded composition description from \(path).")
    }

    public func saveCompositionDescription(toJSONFile path: String) throws {
        guard let sourceText else { throw SessionError.noSourceText }
        let description = CompositionDescription(title: compositionTitle, sourceText: sourceText, additionalInstructions: additionalCompositionInstructions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(description)
        try data.write(to: URL(fileURLWithPath: path))
        append("Saved composition description to \(path).")
    }

    private func refreshCompositionDescriptionNames() {
        compositionDescriptionNames = ((try? modelContext.fetch(FetchDescriptor<CompositionDescriptionRecord>())) ?? []).map(\.name).sorted()
    }

    /// One-time bridge from a folder of `.json` composition-description files to the SwiftData
    /// store — mirrors `migrateGuideSequencesFromJSONIfNeeded`: a no-op if the store already
    /// has descriptions, otherwise migrates every `.json` found in `folderPath` (never deleting
    /// the originals), addressed by filename (minus extension) since `CompositionDescription`'s
    /// own `title` field is optional and independent of the file's name. No "seed built-ins".
    public func migrateCompositionDescriptionsFromJSONIfNeeded(in folderPath: String) {
        refreshCompositionDescriptionNames()
        guard compositionDescriptionNames.isEmpty else { return }

        let folderURL = URL(fileURLWithPath: folderPath)
        let jsonFiles = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil))?
            .filter { Self.supportedCompositionExtensions.contains($0.pathExtension.lowercased()) } ?? []
        var migrated = 0
        for fileURL in jsonFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let description = try? JSONDecoder().decode(CompositionDescription.self, from: data) else { continue }
            let name = fileURL.deletingPathExtension().lastPathComponent
            modelContext.insert(CompositionDescriptionRecord(name: name, description: description))
            migrated += 1
        }
        if migrated > 0 {
            try? modelContext.save()
            append("Migrated \(migrated) composition description(s) from \(folderPath) (originals left in place).")
        }
        refreshCompositionDescriptionNames()
    }

    /// Loads a saved description by name and applies it via the same setters the "Decrire le
    /// morceau..." wizard itself uses (`setCompositionTitle`/`setSourceText`/
    /// `setAdditionalCompositionInstructions`) — replaces the old folder-based
    /// `loadCompositionDescription(named:)`.
    public func useCompositionDescription(named name: String) throws {
        let descriptor = FetchDescriptor<CompositionDescriptionRecord>(predicate: #Predicate { $0.name == name })
        guard let record = try? modelContext.fetch(descriptor).first, let description = record.asCompositionDescription else {
            throw SessionError.invalidCompositionIndex
        }
        setCompositionTitle(description.title)
        setSourceText(description.sourceText)
        setAdditionalCompositionInstructions(description.additionalInstructions)
        currentCompositionRecordID = record.id
        append("Loaded composition description: \(name)")
    }

    /// Convenience over `useCompositionDescription(named:)` using the 0-based position in `compositionDescriptionNames`.
    public func useCompositionDescription(atIndex index: Int) throws {
        guard compositionDescriptionNames.indices.contains(index) else { throw SessionError.invalidCompositionIndex }
        try useCompositionDescription(named: compositionDescriptionNames[index])
    }

    /// Re-saves the current description to whichever record it was last loaded from/saved to.
    /// Fails if that's never happened yet — use `saveCompositionDescription(as:)` for a first save.
    public func saveCompositionDescription() throws {
        guard let sourceText else { throw SessionError.noSourceText }
        guard let currentCompositionRecordID else { throw SessionError.noCurrentCompositionFile }
        let descriptor = FetchDescriptor<CompositionDescriptionRecord>(predicate: #Predicate { $0.id == currentCompositionRecordID })
        guard let record = try? modelContext.fetch(descriptor).first else { throw SessionError.noCurrentCompositionFile }
        let description = CompositionDescription(title: compositionTitle, sourceText: sourceText, additionalInstructions: additionalCompositionInstructions)
        record.encodedDescription = (try? JSONEncoder().encode(description)) ?? record.encodedDescription
        try modelContext.save()
        append("Saved composition description: \(record.name)")
    }

    /// Saves under a given name — "Save As". If a record with that exact name already exists,
    /// overwrites it (same "saving under an existing name silently overwrites it" behavior the
    /// old folder-based version had); otherwise inserts a new record.
    public func saveCompositionDescription(as name: String) throws {
        guard let sourceText else { throw SessionError.noSourceText }
        let description = CompositionDescription(title: compositionTitle, sourceText: sourceText, additionalInstructions: additionalCompositionInstructions)
        let descriptor = FetchDescriptor<CompositionDescriptionRecord>(predicate: #Predicate { $0.name == name })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.encodedDescription = (try? JSONEncoder().encode(description)) ?? existing.encodedDescription
            currentCompositionRecordID = existing.id
        } else {
            let record = CompositionDescriptionRecord(name: name, description: description)
            modelContext.insert(record)
            currentCompositionRecordID = record.id
        }
        try modelContext.save()
        refreshCompositionDescriptionNames()
        append("Saved composition description as: \(name)")
    }

    /// Deletes a stored composition description — new capability (no delete existed in the
    /// old folder-based UI; removing a file meant using the Finder directly).
    public func deleteCompositionDescription(atIndex index: Int) throws {
        guard compositionDescriptionNames.indices.contains(index) else { throw SessionError.invalidCompositionIndex }
        let name = compositionDescriptionNames[index]
        let descriptor = FetchDescriptor<CompositionDescriptionRecord>(predicate: #Predicate { $0.name == name })
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(record)
        try modelContext.save()
        refreshCompositionDescriptionNames()
        append("Deleted composition description: \(name)")
    }

    private static let supportedLLMConnectionExtensions: Set<String> = ["json"]

    /// Re-reads `llmConnections` (names, sorted) from `modelContainer` — called after every
    /// insert/delete so the in-memory list callers already iterate (CLI menus, the SwiftUI
    /// list, `WebConsoleMenuLists.llmConnections`) never drifts from what's actually stored.
    private func refreshLLMConnections() {
        let records = (try? modelContext.fetch(FetchDescriptor<LLMConnectionRecord>())) ?? []
        llmConnections = records.map(\.name).sorted()
    }

    /// One-time bridge from the old `<folder>/LLMConnections/*.json` world to the SwiftData
    /// store: called from `setSettingsFolder` in place of the old `listLLMConnections`. A
    /// no-op if the store already has connections (idempotent — safe to call on every launch).
    /// Otherwise, migrates any `.json` descriptors found in `folderPath` (never deleting the
    /// originals — they stay as a safety net, same "don't remove what you didn't create"
    /// caution used elsewhere for this kind of migration), or — a fresh install with nothing
    /// to migrate — seeds `LLMConnectionTemplates.builtIn` so the app never starts with an
    /// empty, unusable LLM connection list.
    public func migrateLLMConnectionsFromJSONIfNeeded(in folderPath: String) {
        refreshLLMConnections()
        guard llmConnections.isEmpty else { return }

        let folderURL = URL(fileURLWithPath: folderPath)
        let jsonFiles = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil))?
            .filter { Self.supportedLLMConnectionExtensions.contains($0.pathExtension.lowercased()) } ?? []

        if jsonFiles.isEmpty {
            for template in LLMConnectionTemplates.builtIn {
                modelContext.insert(LLMConnectionRecord(template))
            }
            append("Seeded \(LLMConnectionTemplates.builtIn.count) built-in LLM connection(s).")
        } else {
            var migrated = 0
            for fileURL in jsonFiles {
                guard let data = try? Data(contentsOf: fileURL),
                      let connection = try? JSONDecoder().decode(LLMConnection.self, from: data) else { continue }
                modelContext.insert(LLMConnectionRecord(connection))
                migrated += 1
            }
            append("Migrated \(migrated) LLM connection(s) from \(folderPath) (originals left in place).")
        }
        try? modelContext.save()
        refreshLLMConnections()
    }

    public func useLLMConnection(named name: String) throws {
        let descriptor = FetchDescriptor<LLMConnectionRecord>(predicate: #Predicate { $0.name == name })
        guard let record = try? modelContext.fetch(descriptor).first else {
            throw SessionError.invalidLLMConnectionIndex
        }
        let connection = record.asLLMConnection
        currentLLMConnection = connection
        append("Using LLM connection: \(connection.name) (\(connection.provider), model \(connection.model))")
    }

    /// Convenience over `useLLMConnection(named:)` using the 0-based position in `llmConnections`.
    public func useLLMConnection(atIndex index: Int) throws {
        guard llmConnections.indices.contains(index) else { throw SessionError.invalidLLMConnectionIndex }
        try useLLMConnection(named: llmConnections[index])
    }

    /// Adds a new stored LLM connection — used by the "Ajouter depuis un modele" and "Importer
    /// un fichier JSON" actions (`JamShackLLMView`) alike, both of which just produce an
    /// `LLMConnection` value one way or another.
    public func addLLMConnection(_ connection: LLMConnection) throws {
        modelContext.insert(LLMConnectionRecord(connection))
        try modelContext.save()
        refreshLLMConnections()
        append("Added LLM connection: \(connection.name)")
    }

    /// Removes a stored LLM connection — bookkeeping only, mirrors `detachInstrument`'s own
    /// "no error if it was never the active one" tolerance: deleting the currently-active
    /// connection doesn't clear `currentLLMConnection` (whatever's already loaded keeps working
    /// until the user picks something else, same as today's file-based behavior never re-read
    /// a deleted file out from under an active session either).
    public func deleteLLMConnection(atIndex index: Int) throws {
        guard llmConnections.indices.contains(index) else { throw SessionError.invalidLLMConnectionIndex }
        let name = llmConnections[index]
        let descriptor = FetchDescriptor<LLMConnectionRecord>(predicate: #Predicate { $0.name == name })
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(record)
        try modelContext.save()
        refreshLLMConnections()
        append("Deleted LLM connection: \(name)")
    }

    // MARK: - Composition prompts (always recomposed from parts — never loaded/replaced whole)

    private static let promptsTextFramingSubfolder = "Cadrage Composition Descriptive"
    private static let promptsSoundTrackFramingSubfolder = "Cadrage Composition Soundtrack"
    private static let promptsCompositionDescriptionSubfolder = "composition Descriptive"
    private static let promptsSoundTrackInstructionsSubfolder = "Indications Soundtracks"
    private static let promptsExportSubfolder = "Export"

    /// The exact prompt `composeFromText()` would send right now — always recomposed from
    /// `sourceText`, the active/default framing sentence, and `additionalCompositionInstructions`
    /// (never loaded/replaced as one opaque blob — see `exportTextCompositionPrompt(as:)` for
    /// the read-only alternative to that).
    public func currentTextCompositionPrompt() throws -> String {
        guard let sourceText else { throw SessionError.noSourceText }
        return LLMPieceComposer.buildPrompt(sourceText: sourceText, framingSentence: currentTextFramingSentence(), additionalInstructions: additionalCompositionInstructions)
    }

    /// The `composeSoundTrackToPieces()` counterpart of `currentTextCompositionPrompt()` —
    /// recomposed from `currentSoundTrack`, the active/default framing sentence, and
    /// `activeSoundTrackCompositionInstructions`.
    public func currentSoundTrackCompositionPrompt() throws -> String {
        guard let currentSoundTrack else { throw SessionError.noSoundTrackRecorded }
        return LLMPieceComposer.buildPrompt(fromSoundTrack: currentSoundTrack, framingSentence: currentSoundTrackFramingSentence(), additionalInstructions: activeSoundTrackCompositionInstructions)
    }

    /// The framing sentence `currentTextCompositionPrompt()` would use right now:
    /// `activeTextFramingSentence` if one was set/loaded, otherwise the built-in default.
    /// Never throws — unlike the full prompt, there's always a value to fall back to.
    public func currentTextFramingSentence() -> String {
        activeTextFramingSentence ?? LLMPieceComposer.defaultTextFramingSentence
    }

    /// The soundtrack counterpart of `currentTextFramingSentence()`.
    public func currentSoundTrackFramingSentence() -> String {
        activeSoundTrackFramingSentence ?? LLMPieceComposer.defaultSoundTrackFramingSentence
    }

    /// Sets a new in-memory framing-sentence override — same "empty clears" convention as
    /// `setAdditionalCompositionInstructions`. Purely in-memory: follow with
    /// `saveTextFramingSentence(as:)` to persist it for later reuse.
    public func setTextFramingSentence(_ text: String) {
        activeTextFramingSentence = text.isEmpty ? nil : text
        append(activeTextFramingSentence == nil
            ? "Phrase de cadrage (texte) : retour au prompt par defaut."
            : "Phrase de cadrage (texte) mise a jour.")
    }

    /// The soundtrack counterpart of `setTextFramingSentence(_:)`.
    public func setSoundTrackFramingSentence(_ text: String) {
        activeSoundTrackFramingSentence = text.isEmpty ? nil : text
        append(activeSoundTrackFramingSentence == nil
            ? "Phrase de cadrage (soundtrack) : retour au prompt par defaut."
            : "Phrase de cadrage (soundtrack) mise a jour.")
    }

    /// Fetches the `PromptSnippetRecord` for `(category, name)`, if any — shared by every
    /// `useX`/`saveX(as:)` pair below.
    private func promptSnippetRecord(category: PromptSnippetCategory, named name: String) -> PromptSnippetRecord? {
        let rawCategory = category.rawValue
        let descriptor = FetchDescriptor<PromptSnippetRecord>(predicate: #Predicate { $0.category == rawCategory && $0.name == name })
        return try? modelContext.fetch(descriptor).first
    }

    private func refreshPromptSnippetNames(category: PromptSnippetCategory) -> [String] {
        let rawCategory = category.rawValue
        let descriptor = FetchDescriptor<PromptSnippetRecord>(predicate: #Predicate { $0.category == rawCategory })
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.name).sorted()
    }

    /// Inserts a new snippet, or overwrites the existing one for `(category, name)` — same
    /// "saving under an existing name silently overwrites it" behavior the old
    /// folder-based `.txt` files had.
    private func savePromptSnippet(category: PromptSnippetCategory, name: String, text: String) {
        if let existing = promptSnippetRecord(category: category, named: name) {
            existing.text = text
        } else {
            modelContext.insert(PromptSnippetRecord(category: category, name: name, text: text))
        }
        try? modelContext.save()
    }

    /// One-time bridge from a folder of `.txt` snippet files to the SwiftData store — mirrors
    /// `migrateGuideSequencesFromJSONIfNeeded`: a no-op if the store already has snippets for
    /// `category`, otherwise migrates every `.txt` found in `folderURL` (never deleting the
    /// originals), addressed by filename minus extension. Returns the resulting name list.
    private func migratePromptSnippetsFromJSONIfNeeded(category: PromptSnippetCategory, in folderURL: URL) -> [String] {
        var names = refreshPromptSnippetNames(category: category)
        guard names.isEmpty else { return names }

        let txtFiles = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "txt" } ?? []
        var migrated = 0
        for fileURL in txtFiles {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let name = fileURL.deletingPathExtension().lastPathComponent
            modelContext.insert(PromptSnippetRecord(category: category, name: name, text: text))
            migrated += 1
        }
        if migrated > 0 {
            try? modelContext.save()
            names = refreshPromptSnippetNames(category: category)
        }
        return names
    }

    /// Points at the root folder for the whole "Composition IA" toolkit, creating its fixed
    /// subfolders if they don't exist yet (they stay as one-time migration sources/manual-drop
    /// spots — framing sentences, saved descriptions, and style indications all live in the
    /// SwiftData store now, see `migratePromptSnippetsFromJSONIfNeeded`/
    /// `migrateCompositionDescriptionsFromJSONIfNeeded`), except `Export` (exported full
    /// prompts, never reloaded from here — see `exportTextCompositionPrompt(as:)` — stays
    /// plain files, nothing to migrate).
    public func setPromptsFolder(_ folderPath: String) throws {
        let root = URL(fileURLWithPath: folderPath)
        let textFramingURL = root.appendingPathComponent(Self.promptsTextFramingSubfolder)
        let soundTrackFramingURL = root.appendingPathComponent(Self.promptsSoundTrackFramingSubfolder)
        let compositionURL = root.appendingPathComponent(Self.promptsCompositionDescriptionSubfolder)
        let soundTrackInstructionsURL = root.appendingPathComponent(Self.promptsSoundTrackInstructionsSubfolder)
        let exportURL = root.appendingPathComponent(Self.promptsExportSubfolder)
        try FileManager.default.createDirectory(at: textFramingURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: soundTrackFramingURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: compositionURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: soundTrackInstructionsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportURL, withIntermediateDirectories: true)
        promptsFolder = folderPath
        textFramingSentenceNames = migratePromptSnippetsFromJSONIfNeeded(category: .textFraming, in: textFramingURL)
        soundTrackFramingSentenceNames = migratePromptSnippetsFromJSONIfNeeded(category: .soundTrackFraming, in: soundTrackFramingURL)
        soundTrackInstructionsNames = migratePromptSnippetsFromJSONIfNeeded(category: .soundTrackInstructions, in: soundTrackInstructionsURL)
        migrateCompositionDescriptionsFromJSONIfNeeded(in: compositionURL.path)
        append("Dossier de composition IA: \(folderPath) (\(textFramingSentenceNames.count) cadrage texte, \(soundTrackFramingSentenceNames.count) cadrage soundtrack, \(compositionDescriptionNames.count) descriptions, \(soundTrackInstructionsNames.count) indications soundtrack).")
    }

    // MARK: - Settings folder (palettes, chord progression templates, LLM connections)

    /// Points at the root folder for install-wide settings, creating/loading its fixed
    /// contents — mirrors `setPromptsFolder`'s "one chosen folder, several fixed sub-paths"
    /// shape: `LLMConnections/` (now only ever read once, by `migrateLLMConnectionsFromJSONIfNeeded`
    /// — LLM connections themselves live in a private SwiftData store, not this folder; the
    /// folder still exists purely as a one-time migration source/manual-drop spot for anyone
    /// used to the old workflow), `palettes.json` (`migrateColorPalettesFromJSONIfNeeded`),
    /// `chordprogressions.json` (`migrateChordProgressionTemplatesFromJSONIfNeeded`), and every
    /// other `migrate...FromJSONIfNeeded` call below — every one of these categories now lives
    /// in the same shared SwiftData store as LLM connections (see `modelContainer`), with the
    /// JSON files in this folder kept only as one-time migration sources/manual-drop spots.
    /// Unlike `pieceFolder`/`sampleFolder`/etc. (each independently redirectable), these always
    /// move together as one unit.
    public func setSettingsFolder(_ folderPath: String) throws {
        try FileManager.default.createDirectory(atPath: folderPath, withIntermediateDirectories: true)
        let llmFolder = (folderPath as NSString).appendingPathComponent("LLMConnections")
        try FileManager.default.createDirectory(atPath: llmFolder, withIntermediateDirectories: true)
        migrateLLMConnectionsFromJSONIfNeeded(in: llmFolder)
        migrateColorPalettesFromJSONIfNeeded(fromJSONFile: (folderPath as NSString).appendingPathComponent("palettes.json"))
        migrateChordProgressionTemplatesFromJSONIfNeeded(fromJSONFile: (folderPath as NSString).appendingPathComponent("chordprogressions.json"))
        migrateLanguageSettingFromJSONIfNeeded(fromJSONFile: (folderPath as NSString).appendingPathComponent("language.json"))
        loadNotationStyleSetting()
        loadTheoryAuditionSoundSetting()
        migrateChordTemplatesFromJSONIfNeeded(fromJSONFile: (folderPath as NSString).appendingPathComponent("chords.json"))
        migrateScaleDefinitionsFromJSONIfNeeded(fromJSONFile: (folderPath as NSString).appendingPathComponent("scales.json"))
        migrateLumiSettingsFromJSONIfNeeded(fromJSONFile: (folderPath as NSString).appendingPathComponent("lumi.json"))
        migrateSpectrogramSettingsFromJSONIfNeeded(fromJSONFile: (folderPath as NSString).appendingPathComponent("spectrogram.json"))
        migrateNoteColorSettingsFromJSONIfNeeded(fromJSONFile: (folderPath as NSString).appendingPathComponent("note-colors.json"))
        migrateLLMAPIKeysFromJSONIfNeeded(fromJSONFile: (folderPath as NSString).appendingPathComponent("llm-api-keys.json"))
        migrateMicrophoneCalibrationFromJSONIfNeeded(fromJSONFile: (folderPath as NSString).appendingPathComponent("microphone-calibration.json"))
        migrateSoundSettingsFromJSONIfNeeded(fromJSONFile: (folderPath as NSString).appendingPathComponent("sound-settings.json"))
        // Must run after the JSON migration right above (which inserts path-keyed entries with
        // no hash yet) AND after `startSoundFontLibrary` has had a chance to populate
        // `soundFonts` (see `ContentView.swift`'s launch sequence for the real call order) —
        // resolves each pending entry's file name to a stable hash.
        migrateSoundEntriesToHashKeyedIfNeeded()
        settingsFolder = folderPath
        append("Dossier de reglages: \(folderPath).")
    }

    /// Saves `currentTextFramingSentence()` (the active override, or the default if none) as
    /// a new snippet in the SwiftData store.
    public func saveTextFramingSentence(as name: String) throws {
        savePromptSnippet(category: .textFraming, name: name, text: currentTextFramingSentence())
        textFramingSentenceNames = refreshPromptSnippetNames(category: .textFraming)
        append("Phrase de cadrage (texte) sauvegardee: \(name).")
    }

    /// The soundtrack counterpart of `saveTextFramingSentence(as:)`.
    public func saveSoundTrackFramingSentence(as name: String) throws {
        savePromptSnippet(category: .soundTrackFraming, name: name, text: currentSoundTrackFramingSentence())
        soundTrackFramingSentenceNames = refreshPromptSnippetNames(category: .soundTrackFraming)
        append("Phrase de cadrage (soundtrack) sauvegardee: \(name).")
    }

    /// Loads a previously saved framing sentence and makes it `activeTextFramingSentence` —
    /// used by `currentTextCompositionPrompt()` in place of the built-in default until
    /// `resetTextFramingSentence()` is called.
    public func useTextFramingSentence(named name: String) throws {
        guard let record = promptSnippetRecord(category: .textFraming, named: name) else { throw SessionError.invalidTextFramingIndex }
        activeTextFramingSentence = record.text
        append("Phrase de cadrage (texte) chargee: \(name).")
    }

    /// Convenience over `useTextFramingSentence(named:)` using the 0-based position in `textFramingSentenceNames`.
    public func useTextFramingSentence(atIndex index: Int) throws {
        guard textFramingSentenceNames.indices.contains(index) else { throw SessionError.invalidTextFramingIndex }
        try useTextFramingSentence(named: textFramingSentenceNames[index])
    }

    /// The soundtrack counterpart of `useTextFramingSentence(named:)`.
    public func useSoundTrackFramingSentence(named name: String) throws {
        guard let record = promptSnippetRecord(category: .soundTrackFraming, named: name) else { throw SessionError.invalidSoundTrackFramingIndex }
        activeSoundTrackFramingSentence = record.text
        append("Phrase de cadrage (soundtrack) chargee: \(name).")
    }

    /// Convenience over `useSoundTrackFramingSentence(named:)` using the 0-based position in `soundTrackFramingSentenceNames`.
    public func useSoundTrackFramingSentence(atIndex index: Int) throws {
        guard soundTrackFramingSentenceNames.indices.contains(index) else { throw SessionError.invalidSoundTrackFramingIndex }
        try useSoundTrackFramingSentence(named: soundTrackFramingSentenceNames[index])
    }

    /// Clears `activeTextFramingSentence` — `currentTextCompositionPrompt()` goes back to
    /// using `LLMPieceComposer.defaultTextFramingSentence`.
    public func resetTextFramingSentence() {
        activeTextFramingSentence = nil
        append("Phrase de cadrage (texte) : retour a la phrase par defaut.")
    }

    /// The soundtrack counterpart of `resetTextFramingSentence()`.
    public func resetSoundTrackFramingSentence() {
        activeSoundTrackFramingSentence = nil
        append("Phrase de cadrage (soundtrack) : retour a la phrase par defaut.")
    }

    /// Style indications for composing from a `SoundTrack` — the exact value
    /// `currentSoundTrackCompositionPrompt()` would use right now, or `nil` if none are set.
    public func currentSoundTrackCompositionInstructions() -> String? {
        activeSoundTrackCompositionInstructions
    }

    /// Sets/clears the in-memory soundtrack style indications — same "empty clears"
    /// convention as `setAdditionalCompositionInstructions`. Purely in-memory: follow with
    /// `saveSoundTrackCompositionInstructions(as:)` to persist it for later reuse.
    public func setSoundTrackCompositionInstructions(_ text: String?) {
        activeSoundTrackCompositionInstructions = (text?.isEmpty ?? true) ? nil : text
        append(activeSoundTrackCompositionInstructions == nil
            ? "Indications de style (soundtrack) effacees."
            : "Indications de style (soundtrack): \(activeSoundTrackCompositionInstructions!)")
    }

    /// Saves the active soundtrack style indications as a new snippet in the SwiftData store.
    /// Throws if there's nothing set — unlike the framing sentence, there's no default text to
    /// fall back to and save instead.
    public func saveSoundTrackCompositionInstructions(as name: String) throws {
        guard let instructions = activeSoundTrackCompositionInstructions else { throw SessionError.noSoundTrackCompositionInstructions }
        savePromptSnippet(category: .soundTrackInstructions, name: name, text: instructions)
        soundTrackInstructionsNames = refreshPromptSnippetNames(category: .soundTrackInstructions)
        append("Indications de style (soundtrack) sauvegardees: \(name).")
    }

    /// Loads previously saved soundtrack style indications and makes them active.
    public func useSoundTrackCompositionInstructions(named name: String) throws {
        guard let record = promptSnippetRecord(category: .soundTrackInstructions, named: name) else {
            throw SessionError.invalidSoundTrackInstructionsIndex
        }
        activeSoundTrackCompositionInstructions = record.text
        append("Indications de style (soundtrack) chargees: \(name).")
    }

    /// Convenience over `useSoundTrackCompositionInstructions(named:)` using the 0-based position in `soundTrackInstructionsNames`.
    public func useSoundTrackCompositionInstructions(atIndex index: Int) throws {
        guard soundTrackInstructionsNames.indices.contains(index) else { throw SessionError.invalidSoundTrackInstructionsIndex }
        try useSoundTrackCompositionInstructions(named: soundTrackInstructionsNames[index])
    }

    /// Clears the active soundtrack style indications — back to "none".
    public func resetSoundTrackCompositionInstructions() {
        activeSoundTrackCompositionInstructions = nil
        append("Indications de style (soundtrack) effacees.")
    }

    /// Deletes a saved text framing sentence — new capability, not exposed by the CLI (no
    /// delete existed there either, only show/set/save/use/reset).
    public func deleteTextFramingSentence(atIndex index: Int) throws {
        guard textFramingSentenceNames.indices.contains(index) else { throw SessionError.invalidTextFramingIndex }
        let name = textFramingSentenceNames[index]
        guard let record = promptSnippetRecord(category: .textFraming, named: name) else { return }
        modelContext.delete(record)
        try modelContext.save()
        textFramingSentenceNames = refreshPromptSnippetNames(category: .textFraming)
        append("Phrase de cadrage (texte) supprimee: \(name).")
    }

    /// The soundtrack counterpart of `deleteTextFramingSentence(atIndex:)`.
    public func deleteSoundTrackFramingSentence(atIndex index: Int) throws {
        guard soundTrackFramingSentenceNames.indices.contains(index) else { throw SessionError.invalidSoundTrackFramingIndex }
        let name = soundTrackFramingSentenceNames[index]
        guard let record = promptSnippetRecord(category: .soundTrackFraming, named: name) else { return }
        modelContext.delete(record)
        try modelContext.save()
        soundTrackFramingSentenceNames = refreshPromptSnippetNames(category: .soundTrackFraming)
        append("Phrase de cadrage (soundtrack) supprimee: \(name).")
    }

    /// Deletes saved soundtrack style indications — mirrors `deleteTextFramingSentence(atIndex:)`.
    public func deleteSoundTrackInstructions(atIndex index: Int) throws {
        guard soundTrackInstructionsNames.indices.contains(index) else { throw SessionError.invalidSoundTrackInstructionsIndex }
        let name = soundTrackInstructionsNames[index]
        guard let record = promptSnippetRecord(category: .soundTrackInstructions, named: name) else { return }
        modelContext.delete(record)
        try modelContext.save()
        soundTrackInstructionsNames = refreshPromptSnippetNames(category: .soundTrackInstructions)
        append("Indications de style (soundtrack) supprimees: \(name).")
    }

    /// Asks the active LLM connection to pick one icon, from the fixed `IconVocabulary`, for a
    /// scene/role/favorite instrument/MIDI keyboard named `name` — same "inject the real allowed
    /// vocabulary into the prompt, then validate the response against it rather than trust it"
    /// shape as `LLMPieceComposer`'s scale/chord validation, just for a single string instead of
    /// a whole piece. `generate` is injectable for tests, same convention as `composeFromText`.
    public func suggestIcon(
        kind: String, name: String,
        generate: (String, LLMConnection) throws -> String = LLMClient.generate
    ) throws -> String {
        guard let connection = currentLLMConnection else { throw SessionError.noLLMConnectionSelected }
        let prompt = """
        Tu dois choisir UNE seule icone dans cette liste exacte (reponds uniquement par le nom \
        exact de l'icone choisie, sans aucun autre texte, sans ponctuation) :
        \(IconVocabulary.allowedSymbolNames.joined(separator: ", "))

        Choisis l'icone la plus evocatrice pour ce \(kind) nomme \"\(name)\".
        """
        let raw = try generate(prompt, connection).trimmingCharacters(in: .whitespacesAndNewlines)
        guard IconVocabulary.allowedSymbolNames.contains(raw) else { throw SessionError.invalidIconSuggestion }
        return raw
    }

    /// Writes `currentTextCompositionPrompt()` (whatever would actually be sent right now) to
    /// a new file under `Export` — a read-only snapshot for reference/debugging, deliberately
    /// **not** reloadable: the prompt is always recomposed from its parts (framing sentence +
    /// data + indications), never replaced whole (see the `MARK` above).
    public func exportTextCompositionPrompt(as name: String) throws {
        guard let promptsFolder else { throw SessionError.noPromptsFolderListed }
        let prompt = try currentTextCompositionPrompt()
        let fileName = name.hasSuffix(".txt") ? name : name + ".txt"
        let url = URL(fileURLWithPath: promptsFolder).appendingPathComponent(Self.promptsExportSubfolder).appendingPathComponent(fileName)
        try prompt.write(to: url, atomically: true, encoding: .utf8)
        append("Prompt (texte) exporte: \(url.path).")
    }

    /// The soundtrack counterpart of `exportTextCompositionPrompt(as:)`.
    public func exportSoundTrackCompositionPrompt(as name: String) throws {
        guard let promptsFolder else { throw SessionError.noPromptsFolderListed }
        let prompt = try currentSoundTrackCompositionPrompt()
        let fileName = name.hasSuffix(".txt") ? name : name + ".txt"
        let url = URL(fileURLWithPath: promptsFolder).appendingPathComponent(Self.promptsExportSubfolder).appendingPathComponent(fileName)
        try prompt.write(to: url, atomically: true, encoding: .utf8)
        append("Prompt (soundtrack) exporte: \(url.path).")
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
    public func composeFromText(title: String? = nil, generate: (String, LLMConnection) throws -> String = LLMClient.generatePieceJSON) throws {
        let prompt = try currentTextCompositionPrompt()
        guard let connection = currentLLMConnection else { throw SessionError.noLLMConnectionSelected }

        append("Sending text to \(connection.name)...")
        let responseText = try generate(prompt, connection)

        let (composedPieceOpt, warnings) = LLMPieceComposer.parseAndValidate(responseText: responseText)
        for warning in warnings { append("Compose warning: \(warning)") }
        guard var composedPiece = composedPieceOpt else { throw SessionError.llmComposeFailed(warnings) }
        if let title { composedPiece.title = title }

        piece = composedPiece
        currentPieceRecordID = nil
        append("Composed '\(composedPiece.title)' from text (\(composedPiece.sections.count) section(s)).")
    }

    /// Raw file I/O, unchanged in behavior — kept for the CLI's explicit-path `load
    /// <path>`/`save <path>` verbs and as the migration itself reuses. NOT the primary
    /// persistence path anymore (see `usePiece`/`savePiece(as:)` below).
    public func loadPiece(fromJSONFile path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try JSONDecoder().decode(Piece.self, from: data)
        piece = decoded
        currentPieceRecordID = nil
        append("Loaded piece from \(path): \(decoded.title)")
    }

    public func savePiece(toJSONFile path: String) throws {
        guard let piece else { throw SessionError.noPieceLoaded }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(piece)
        try data.write(to: URL(fileURLWithPath: path))
        append("Saved piece to \(path).")
    }

    private static let supportedPieceExtensions: Set<String> = ["json"]

    private func refreshPieceNames() {
        pieceNames = ((try? modelContext.fetch(FetchDescriptor<PieceRecord>())) ?? []).map(\.title).sorted()
    }

    /// One-time bridge from a folder of `.json` piece files to the SwiftData store — mirrors
    /// `migrateGuideSequencesFromJSONIfNeeded`: a no-op if the store already has pieces,
    /// otherwise migrates every `.json` found in `folderPath` (never deleting the originals).
    /// No "seed built-ins" — pieces have none (see `loadDemoPiece()` for the one built-in demo,
    /// which was never file-backed to begin with).
    public func migratePiecesFromJSONIfNeeded(in folderPath: String) {
        refreshPieceNames()
        guard pieceNames.isEmpty else { return }

        let folderURL = URL(fileURLWithPath: folderPath)
        let jsonFiles = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil))?
            .filter { Self.supportedPieceExtensions.contains($0.pathExtension.lowercased()) } ?? []
        var migrated = 0
        for fileURL in jsonFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let decodedPiece = try? JSONDecoder().decode(Piece.self, from: data) else { continue }
            modelContext.insert(PieceRecord(decodedPiece))
            migrated += 1
        }
        if migrated > 0 {
            try? modelContext.save()
            append("Migrated \(migrated) piece(s) from \(folderPath) (originals left in place).")
        }
        refreshPieceNames()
    }

    /// Loads a piece by title from the SwiftData store — replaces the old folder-based
    /// `loadPiece(named:)`. First match wins if two records share a title (same tolerance
    /// `useLLMConnection(named:)`/`useGuideSequence(named:)` already accept).
    public func usePiece(named name: String) throws {
        let descriptor = FetchDescriptor<PieceRecord>(predicate: #Predicate { $0.title == name })
        guard let record = try? modelContext.fetch(descriptor).first, let decodedPiece = record.asPiece else {
            throw SessionError.invalidPieceIndex
        }
        piece = decodedPiece
        currentPieceRecordID = record.id
        append("Loaded piece: \(decodedPiece.title)")
    }

    /// Convenience over `usePiece(named:)` using the 0-based position in `pieceNames`.
    public func usePiece(atIndex index: Int) throws {
        guard pieceNames.indices.contains(index) else { throw SessionError.invalidPieceIndex }
        try usePiece(named: pieceNames[index])
    }

    /// Re-saves the current piece to whichever record it was last loaded from/saved to
    /// (`currentPieceRecordID`) — updates that exact record even if `piece.title` has since
    /// changed (unlike `savePiece(as:)`, which addresses by title). Fails if that's never
    /// happened yet — use `savePiece(as:)` for a first save.
    public func savePiece() throws {
        guard let piece else { throw SessionError.noPieceLoaded }
        guard let currentPieceRecordID else { throw SessionError.noCurrentPieceFile }
        let descriptor = FetchDescriptor<PieceRecord>(predicate: #Predicate { $0.id == currentPieceRecordID })
        guard let record = try? modelContext.fetch(descriptor).first else { throw SessionError.noCurrentPieceFile }
        record.title = piece.title
        record.encodedPiece = (try? JSONEncoder().encode(piece)) ?? record.encodedPiece
        try modelContext.save()
        refreshPieceNames()
        append("Saved piece: \(piece.title)")
    }

    /// Saves under a given title — "Save As". If a record with that exact title already
    /// exists, overwrites it (same "saving under an existing name silently overwrites it"
    /// behavior the old folder-based version had); otherwise inserts a new record. Adopts
    /// `name` as `piece`'s own title — there's no separate "filename" anymore.
    public func savePiece(as name: String) throws {
        guard var piece else { throw SessionError.noPieceLoaded }
        piece.title = name
        self.piece = piece
        let descriptor = FetchDescriptor<PieceRecord>(predicate: #Predicate { $0.title == name })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.encodedPiece = (try? JSONEncoder().encode(piece)) ?? existing.encodedPiece
            currentPieceRecordID = existing.id
        } else {
            let record = PieceRecord(piece)
            modelContext.insert(record)
            currentPieceRecordID = record.id
        }
        try modelContext.save()
        refreshPieceNames()
        append("Saved piece as: \(name)")
    }

    /// Deletes a stored piece — new capability (the old folder-based UI had no delete button;
    /// removing a file meant using the Finder directly, which stops being possible once the
    /// data lives in a private SwiftData store).
    public func deletePiece(atIndex index: Int) throws {
        guard pieceNames.indices.contains(index) else { throw SessionError.invalidPieceIndex }
        let name = pieceNames[index]
        let descriptor = FetchDescriptor<PieceRecord>(predicate: #Predicate { $0.title == name })
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(record)
        try modelContext.save()
        refreshPieceNames()
        append("Deleted piece: \(name)")
    }

    // MARK: - Guide sequences (mode sequences for the Guide screen)

    /// Starts a blank guide sequence (no steps yet) — mirrors `newPiece`.
    public func newGuideSequence(title: String) {
        currentGuide = GuideSequence(title: title)
        currentGuideRecordID = nil
        currentGuideStepIndex = nil
        append("New guide sequence created: \(title)")
    }

    public func addGuideStep(_ reference: ModeReference) throws {
        try addGuideStep(reference, chordProgression: nil)
    }

    /// Same as `addGuideStep(_:)`, additionally attaching `template` (resolved against
    /// `reference`'s mode right now, via `resolveChordProgression` — see `GuideStep`'s doc
    /// comment for why the resolved chords, not just the template name, are what gets
    /// stored) — `nil` behaves exactly like the plain overload above.
    public func addGuideStep(_ reference: ModeReference, chordProgression template: ChordProgressionTemplate?) throws {
        guard var currentGuide else { throw SessionError.noGuideSequence }
        // Rejected here (the one place every caller — CLI command, menu — goes through)
        // rather than silently stored: an unresolvable reference (typo'd/unknown scaleID)
        // used to end up saved as a step that could never resolve, showing "?" everywhere
        // and making the guide screen wrongly claim "not started" even after `startGuide`.
        guard let mode = reference.resolve() else { throw SessionError.invalidModeReference }
        let resolvedProgression = template.map { resolveChordProgression($0, in: mode) }
        currentGuide.steps.append(GuideStep(mode: reference, chordProgressionName: template?.name, chordProgression: resolvedProgression))
        self.currentGuide = currentGuide
        let progressionSuffix = template.map { " + \($0.name)" } ?? ""
        append("Added step to guide sequence '\(currentGuide.title)': \(mode.displayName)\(progressionSuffix).")
    }

    public func removeGuideStep(atIndex index: Int) throws {
        guard var currentGuide else { throw SessionError.noGuideSequence }
        guard currentGuide.steps.indices.contains(index) else { throw SessionError.invalidGuideStepIndex }
        currentGuide.steps.remove(at: index)
        self.currentGuide = currentGuide
        if let currentGuideStepIndex, currentGuideStepIndex >= currentGuide.steps.count {
            self.currentGuideStepIndex = currentGuide.steps.isEmpty ? nil : currentGuide.steps.count - 1
        }
        append("Removed step \(index + 1) from guide sequence '\(currentGuide.title)'.")
    }

    /// Manual equivalent of `MutableCollection.move(fromOffsets:toOffset:)` — that convenience
    /// is a `SwiftUI`-only extension (backing `.onMove`'s standard implementation), and
    /// `AppCore` deliberately never imports `SwiftUI` (it's shared by the plain `JamShack` CLI
    /// executable, which doesn't link it) — a real link failure, not a hypothetical, confirmed
    /// by `JamShack` failing to link with an undefined `SwiftUI` symbol until this was written
    /// out by hand. Same reordering semantics: elements at `source` are removed (order among
    /// themselves preserved) and reinserted starting at `destination`, adjusted for however many
    /// of the removed indices sat before it.
    private static func reordered<T>(_ array: [T], moving source: IndexSet, to destination: Int) -> [T] {
        var result = array
        let moved = source.map { array[$0] }
        for index in source.sorted(by: >) {
            result.remove(at: index)
        }
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        result.insert(contentsOf: moved, at: adjustedDestination)
        return result
    }

    /// Reorders the guide's own steps — the CLI/menu have no equivalent yet, added for the
    /// SwiftUI app's drag-and-drop step list (`GuideStepsSection`). Keeps `currentGuideStepIndex`
    /// pointed at the SAME step (not the same numeric position) if a guide is currently active,
    /// same "don't silently jump the active step" care as `removeGuideStep`.
    public func moveGuideSteps(fromOffsets source: IndexSet, toOffset destination: Int) throws {
        guard var currentGuide else { throw SessionError.noGuideSequence }
        let activeStep = currentGuideStepIndex.flatMap { currentGuide.steps.indices.contains($0) ? currentGuide.steps[$0] : nil }
        currentGuide.steps = Self.reordered(currentGuide.steps, moving: source, to: destination)
        self.currentGuide = currentGuide
        if let activeStep {
            currentGuideStepIndex = currentGuide.steps.firstIndex(of: activeStep)
        }
        append("Reordered steps of guide sequence '\(currentGuide.title)'.")
    }

    /// Reorders the chords WITHIN one step's already-resolved progression — same rationale as
    /// `moveGuideSteps`, for `GuideStepsSection`'s per-step chord list.
    public func moveGuideStepChords(atStepIndex stepIndex: Int, fromOffsets source: IndexSet, toOffset destination: Int) throws {
        guard var currentGuide else { throw SessionError.noGuideSequence }
        guard currentGuide.steps.indices.contains(stepIndex) else { throw SessionError.invalidGuideStepIndex }
        if let progression = currentGuide.steps[stepIndex].chordProgression {
            currentGuide.steps[stepIndex].chordProgression = Self.reordered(progression, moving: source, to: destination)
        }
        self.currentGuide = currentGuide
        append("Reordered chords of step \(stepIndex + 1) in guide sequence '\(currentGuide.title)'.")
    }

    /// Re-picks/changes a whole existing step's chord progression — `addGuideStep(_:chordProgression:)`
    /// only ever set this at CREATION time; this is the same resolution logic
    /// (`resolveChordProgression(_:in:)`) applied to a step already in the sequence, for the
    /// Guide Edition screen's per-step progression picker. `template: nil` clears the
    /// progression entirely (same "no progression" meaning as never having set one).
    public func setGuideStepChordProgression(atIndex index: Int, template: ChordProgressionTemplate?) throws {
        guard var currentGuide else { throw SessionError.noGuideSequence }
        guard currentGuide.steps.indices.contains(index) else { throw SessionError.invalidGuideStepIndex }
        guard let mode = currentGuide.steps[index].mode.resolve() else { throw SessionError.invalidModeReference }
        currentGuide.steps[index].chordProgressionName = template?.name
        currentGuide.steps[index].chordProgression = template.map { resolveChordProgression($0, in: mode) }
        self.currentGuide = currentGuide
        let progressionSuffix = template.map { " + \($0.name)" } ?? " (aucune)"
        append("Updated chord progression for step \(index + 1) of guide sequence '\(currentGuide.title)'\(progressionSuffix).")
    }

    /// Plays the active guide's steps audibly in sequence through `guideAuditionPlayer` — one
    /// chord-hold per chord in each step's progression (or, for a step with none, its tonic
    /// alone), back to back, no melody/timing beyond that (a guide has neither). `speedFactor`
    /// scales how long each chord is held (1.0 = 1 second/chord, 2.0 = twice as fast) — there's
    /// no tempo/BPM to scale here, just a flat per-chord duration, unlike `play()`'s
    /// measure-based `Piece` timing.
    public func startGuideAudition(speedFactor: Double = 1.0) {
        guard let currentGuide, !currentGuide.steps.isEmpty, !isAuditioningGuide else { return }
        let secondsPerChord = 1.0 / max(0.1, speedFactor)
        var chords: [GuideAuditionChord] = []
        var cursor = 0.0
        for step in currentGuide.steps {
            let progression = step.chordProgression ?? []
            if progression.isEmpty {
                if let mode = step.mode.resolve() {
                    chords.append(GuideAuditionChord(pitches: [48 + mode.tonic.value], startSeconds: cursor, durationSeconds: secondsPerChord))
                    cursor += secondsPerChord
                }
            } else {
                for chordReference in progression {
                    guard let chord = chordReference.resolve() else { continue }
                    let pitches = chord.pitchClasses.map { 48 + $0.value }
                    chords.append(GuideAuditionChord(pitches: pitches, startSeconds: cursor, durationSeconds: secondsPerChord))
                    cursor += secondsPerChord
                }
            }
        }
        guard !chords.isEmpty else { return }
        guideAuditionPlayer.play(chords)

        guideAuditionGeneration += 1
        let generation = guideAuditionGeneration
        isAuditioningGuide = true
        append("Ecoute du guide demarree.")

        playbackStateQueue.asyncAfter(deadline: .now() + cursor + 0.2) { [weak self] in
            guard let self, self.guideAuditionGeneration == generation else { return }
            self.isAuditioningGuide = false
            self.append("Ecoute du guide terminee.")
        }
    }

    /// Stops an in-progress guide audition early — mirrors `stopSoundTrackPlayback()`. A no-op
    /// if nothing is auditioning.
    public func stopGuideAudition() {
        guard isAuditioningGuide else { return }
        guideAuditionGeneration += 1
        guideAuditionPlayer.stopAllNotes()
        isAuditioningGuide = false
        append("Ecoute du guide arretee.")
    }

    // MARK: - Chord/Mode/Progression Library audition

    /// One simultaneous group of pitches to hold for `durationSeconds`, `startSeconds` after
    /// playback begins — an `AppCore`-native mirror of `AudioEngine.GuideAuditionChord` (see
    /// `playTheoryLibraryAudition(_:)`) so the Chord/Mode/Progression Library screens (in the
    /// `App` module) never need to import `AudioEngine` directly, the same boundary every other
    /// screen already respects (they only ever reach audio playback through `ImprovSession`
    /// methods).
    public struct TheoryAuditionNote: Sendable {
        public let pitches: [Int]
        public let startSeconds: Double
        public let durationSeconds: Double

        public init(pitches: [Int], startSeconds: Double, durationSeconds: Double) {
            self.pitches = pitches
            self.startSeconds = startSeconds
            self.durationSeconds = durationSeconds
        }
    }

    /// Whether any of the Chord/Mode/Progression Library screens is currently auditioning a
    /// chord/scale-run/progression — a single shared flag/player (like `isAuditioningGuide`'s
    /// own single `guideAuditionPlayer`), since only one such preview is ever meaningfully
    /// playing at a time.
    public private(set) var isAuditioningTheoryLibrary = false
    private let theoryLibraryAuditionPlayer = GuideAuditionPlayer()
    private var theoryLibraryAuditionGeneration = 0
    /// `FavoriteSound.id` of whatever is currently loaded into `theoryLibraryAuditionPlayer` —
    /// lets `loadTheoryLibraryAuditionSample` skip a redundant reload, see its own doc comment.
    private var theoryLibraryAuditionLoadedSoundID: String?

    /// Loads a `FavoriteSound` (as picked from `favoriteSounds` by one of the Library screens)
    /// into the shared theory-library audition player — a no-op when `sound` is already the one
    /// loaded (every Library screen calls this right before EVERY single play, including
    /// repeated presses of the same instrument, which is by far the common case). Skipping the
    /// redundant reload isn't just an optimization: reloading a sound bank instrument into a
    /// running `AVAudioUnitSampler` needs a brief moment to settle, and a note scheduled right
    /// after (at or near `startSeconds: 0`, as every caller here does for its very first note)
    /// landed inside that window and was silently swallowed — confirmed by it consistently being
    /// whichever note played first in time, never a later one.
    public func loadTheoryLibraryAuditionSample(_ sound: FavoriteSound) throws {
        guard theoryLibraryAuditionLoadedSoundID != sound.id else { return }
        try theoryLibraryAuditionPlayer.loadSample(at: URL(fileURLWithPath: sound.path), preset: sound.preset)
        theoryLibraryAuditionLoadedSoundID = sound.id
    }

    /// Plays `notes` through the shared theory-library audition player — used alike for a
    /// single chord (one note, all pitches simultaneous), a scale run (one note per degree,
    /// ascending/descending/both already sequenced by the caller), or a progression (one note
    /// per chord).
    public func playTheoryLibraryAudition(_ notes: [TheoryAuditionNote]) {
        guard !notes.isEmpty else { return }
        theoryLibraryAuditionPlayer.play(notes.map { GuideAuditionChord(pitches: $0.pitches, startSeconds: $0.startSeconds, durationSeconds: $0.durationSeconds) })
        theoryLibraryAuditionGeneration += 1
        let generation = theoryLibraryAuditionGeneration
        isAuditioningTheoryLibrary = true
        let totalDuration = notes.map { $0.startSeconds + $0.durationSeconds }.max() ?? 0
        playbackStateQueue.asyncAfter(deadline: .now() + totalDuration + 0.2) { [weak self] in
            guard let self, self.theoryLibraryAuditionGeneration == generation else { return }
            self.isAuditioningTheoryLibrary = false
        }
    }

    /// Stops an in-progress theory-library audition early — mirrors `stopGuideAudition()`.
    public func stopTheoryLibraryAudition() {
        guard isAuditioningTheoryLibrary else { return }
        theoryLibraryAuditionGeneration += 1
        theoryLibraryAuditionPlayer.stopAllNotes()
        isAuditioningTheoryLibrary = false
    }

    /// Changes ONE chord's quality within a step's already-resolved progression, keeping its
    /// root — the "see this chord's extensions" editor (7th/sus/etc. on the same fundamental,
    /// see `ChordVocabulary.allChords(forRoot:)`), not a re-pick of the whole progression (see
    /// `setGuideStepChordProgression(atIndex:template:)` for that).
    public func setGuideStepChordQuality(stepIndex: Int, chordIndex: Int, templateID: String) throws {
        guard var currentGuide else { throw SessionError.noGuideSequence }
        guard currentGuide.steps.indices.contains(stepIndex) else { throw SessionError.invalidGuideStepIndex }
        guard let progression = currentGuide.steps[stepIndex].chordProgression, progression.indices.contains(chordIndex) else {
            throw SessionError.invalidChordIndex
        }
        currentGuide.steps[stepIndex].chordProgression?[chordIndex].chordTemplateID = templateID
        self.currentGuide = currentGuide
        append("Updated chord \(chordIndex + 1) of step \(stepIndex + 1) in guide sequence '\(currentGuide.title)'.")
    }

    /// Raw file I/O, unchanged in behavior — kept for the CLI's explicit-path `save-guide
    /// <path>`/`load <path>`-style verbs and as the decoder migration reuses. NOT the primary
    /// persistence path anymore (see `useGuideSequence`/`saveGuideSequence(as:)` below) — no
    /// folder/`currentGuideRecordID` bookkeeping happens here.
    public func loadGuideSequence(fromJSONFile path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try JSONDecoder().decode(GuideSequence.self, from: data)
        currentGuide = decoded
        currentGuideRecordID = nil
        currentGuideStepIndex = nil
        append("Loaded guide sequence from \(path): \(decoded.title)")
    }

    public func saveGuideSequence(toJSONFile path: String) throws {
        guard let currentGuide else { throw SessionError.noGuideSequence }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(currentGuide)
        try data.write(to: URL(fileURLWithPath: path))
        append("Saved guide sequence to \(path).")
    }

    private static let supportedGuideExtensions: Set<String> = ["json"]

    /// Every guide sequence's title currently in the SwiftData store, sorted — mirrors
    /// `llmConnections`. Refreshed after every migrate/insert/update/delete.
    public private(set) var guideSequenceNames: [String] = []

    private func refreshGuideSequenceNames() {
        guideSequenceNames = ((try? modelContext.fetch(FetchDescriptor<GuideSequenceRecord>())) ?? []).map(\.title).sorted()
    }

    /// One-time bridge from a folder of `.json` guide sequence files to the SwiftData store —
    /// mirrors `migrateLLMConnectionsFromJSONIfNeeded`: a no-op if the store already has guide
    /// sequences, otherwise migrates every `.json` found in `folderPath` (never deleting the
    /// originals). No "seed built-ins" — guide sequences have none.
    public func migrateGuideSequencesFromJSONIfNeeded(in folderPath: String) {
        refreshGuideSequenceNames()
        guard guideSequenceNames.isEmpty else { return }

        let folderURL = URL(fileURLWithPath: folderPath)
        let jsonFiles = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil))?
            .filter { Self.supportedGuideExtensions.contains($0.pathExtension.lowercased()) } ?? []
        var migrated = 0
        for fileURL in jsonFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let sequence = try? JSONDecoder().decode(GuideSequence.self, from: data) else { continue }
            modelContext.insert(GuideSequenceRecord(sequence))
            migrated += 1
        }
        if migrated > 0 {
            try? modelContext.save()
            append("Migrated \(migrated) guide sequence(s) from \(folderPath) (originals left in place).")
        }
        refreshGuideSequenceNames()
    }

    /// Loads a guide sequence by title from the SwiftData store — replaces the old
    /// folder-based `loadGuideSequence(named:)`. First match wins if two records share a
    /// title (same tolerance `useLLMConnection(named:)` already accepts).
    public func useGuideSequence(named name: String) throws {
        let descriptor = FetchDescriptor<GuideSequenceRecord>(predicate: #Predicate { $0.title == name })
        guard let record = try? modelContext.fetch(descriptor).first, let sequence = record.asGuideSequence else {
            throw SessionError.invalidGuideIndex
        }
        currentGuide = sequence
        currentGuideRecordID = record.id
        currentGuideStepIndex = nil
        append("Loaded guide sequence: \(sequence.title)")
    }

    /// Convenience over `useGuideSequence(named:)` using the 0-based position in `guideSequenceNames`.
    public func useGuideSequence(atIndex index: Int) throws {
        guard guideSequenceNames.indices.contains(index) else { throw SessionError.invalidGuideIndex }
        try useGuideSequence(named: guideSequenceNames[index])
    }

    /// Re-saves the current guide sequence to whichever record it was last loaded from/saved
    /// to (`currentGuideRecordID`) — updates that exact record even if `currentGuide.title`
    /// has since changed (unlike `saveGuideSequence(as:)`, which addresses by title).
    public func saveGuideSequence() throws {
        guard let currentGuide else { throw SessionError.noGuideSequence }
        guard let currentGuideRecordID else { throw SessionError.noCurrentGuideFile }
        let descriptor = FetchDescriptor<GuideSequenceRecord>(predicate: #Predicate { $0.id == currentGuideRecordID })
        guard let record = try? modelContext.fetch(descriptor).first else { throw SessionError.noCurrentGuideFile }
        record.title = currentGuide.title
        record.encodedSequence = (try? JSONEncoder().encode(currentGuide)) ?? record.encodedSequence
        try modelContext.save()
        refreshGuideSequenceNames()
        append("Saved guide sequence: \(currentGuide.title)")
    }

    /// Saves under a given title — "Save As". If a record with that exact title already
    /// exists, overwrites it (same "saving under an existing name silently overwrites it"
    /// behavior the old folder-based version had); otherwise inserts a new record. Adopts
    /// `name` as `currentGuide`'s own title — there's no separate "filename" anymore, the
    /// stored title IS the display name.
    public func saveGuideSequence(as name: String) throws {
        guard var currentGuide else { throw SessionError.noGuideSequence }
        currentGuide.title = name
        self.currentGuide = currentGuide
        let descriptor = FetchDescriptor<GuideSequenceRecord>(predicate: #Predicate { $0.title == name })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.encodedSequence = (try? JSONEncoder().encode(currentGuide)) ?? existing.encodedSequence
            currentGuideRecordID = existing.id
        } else {
            let record = GuideSequenceRecord(currentGuide)
            modelContext.insert(record)
            currentGuideRecordID = record.id
        }
        try modelContext.save()
        refreshGuideSequenceNames()
        append("Saved guide sequence as: \(name)")
    }

    /// Deletes a stored guide sequence — new capability (the old folder-based UI had no
    /// delete button; removing a file meant using the Finder directly, which stops being
    /// possible once the data lives in a private SwiftData store).
    public func deleteGuideSequence(atIndex index: Int) throws {
        guard guideSequenceNames.indices.contains(index) else { throw SessionError.invalidGuideIndex }
        let name = guideSequenceNames[index]
        let descriptor = FetchDescriptor<GuideSequenceRecord>(predicate: #Predicate { $0.title == name })
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(record)
        try modelContext.save()
        refreshGuideSequenceNames()
        append("Deleted guide sequence: \(name)")
    }

    /// Gives the active guide a name — mirrors `renameCurrentScene(to:)`: if it was never saved
    /// (`currentGuideRecordID == nil`), this IS the first save (inserts a new record); if it's
    /// already backed by a record, renames that exact record in place (keeps its identity,
    /// unlike `saveGuideSequence(as:)` which matches an existing record by title text).
    public func renameCurrentGuide(to newTitle: String) throws {
        guard var guide = currentGuide else { throw SessionError.noGuideSequence }
        guide.title = newTitle
        currentGuide = guide
        if let currentGuideRecordID {
            let descriptor = FetchDescriptor<GuideSequenceRecord>(predicate: #Predicate { $0.id == currentGuideRecordID })
            guard let record = try? modelContext.fetch(descriptor).first else { throw SessionError.noCurrentGuideFile }
            record.title = newTitle
            record.encodedSequence = (try? JSONEncoder().encode(guide)) ?? record.encodedSequence
        } else {
            let record = GuideSequenceRecord(guide)
            modelContext.insert(record)
            self.currentGuideRecordID = record.id
        }
        try modelContext.save()
        refreshGuideSequenceNames()
        append("Renamed guide sequence: \(newTitle).")
    }

    /// Renames a stored guide sequence by list position — not necessarily the active one.
    /// Mirrors `renameScene(atIndex:name:)`. Keeps `currentGuide`/`currentGuideRecordID` in sync
    /// if the renamed record happens to be the active one.
    public func renameGuideSequence(atIndex index: Int, name: String) throws {
        guard guideSequenceNames.indices.contains(index) else { throw SessionError.invalidGuideIndex }
        let oldName = guideSequenceNames[index]
        let descriptor = FetchDescriptor<GuideSequenceRecord>(predicate: #Predicate { $0.title == oldName })
        guard let record = try? modelContext.fetch(descriptor).first else { throw SessionError.invalidGuideIndex }
        record.title = name
        try modelContext.save()
        if record.id == currentGuideRecordID { currentGuide?.title = name }
        refreshGuideSequenceNames()
        append("Renamed guide sequence: \(oldName) -> \(name).")
    }

    /// The exact stored bytes for a guide sequence by list position, for per-row export —
    /// mirrors `exportedSceneData(atIndex:)`: a stored record's `encodedSequence` already IS
    /// the full JSON, so this never touches `currentGuide`/`currentGuideRecordID`.
    public func exportedGuideData(atIndex index: Int) throws -> Data {
        guard guideSequenceNames.indices.contains(index) else { throw SessionError.invalidGuideIndex }
        let name = guideSequenceNames[index]
        let descriptor = FetchDescriptor<GuideSequenceRecord>(predicate: #Predicate { $0.title == name })
        guard let record = try? modelContext.fetch(descriptor).first else { throw SessionError.invalidGuideIndex }
        return record.encodedSequence
    }

    /// Backs a "Nouveau guide" button — mirrors `createNewScene()`: persists the current guide
    /// first if it's already named/saved, then starts a fresh unnamed one. If the current guide
    /// is anonymous (never named), nothing is persisted — same "discarded when you move on" rule.
    public func createNewGuideSequence() throws {
        if currentGuideRecordID != nil { try saveGuideSequence() }
        newGuideSequence(title: "")
    }

    /// Called once at app launch (not by the CLI/web console) — mirrors
    /// `ensureSceneReadyForLaunch()`: with no saved guide sequences, starts a fresh anonymous one
    /// so the app can land directly on the guide screen; with one or more saved, leaves
    /// `currentGuide` nil so the app lands on the guide list first.
    public func ensureGuideReadyForLaunch() {
        guard currentGuide == nil else { return }
        if guideSequenceNames.isEmpty {
            currentGuide = GuideSequence(title: "")
        }
    }

    /// Positions the guide at `index` (default the first step) — the Guide screen then
    /// shows that step's mode until `advanceGuideStep`/`stopGuide` changes it.
    public func startGuide(atStepIndex index: Int = 0) throws {
        guard let currentGuide else { throw SessionError.noGuideSequence }
        guard currentGuide.steps.indices.contains(index) else { throw SessionError.invalidGuideStepIndex }
        currentGuideStepIndex = index
        currentGuideChordIndex = nil
        append("Guide started at step \(index + 1)/\(currentGuide.steps.count).")
        syncLumiGuideDisplayIfActive()
    }

    public func stopGuide() {
        guard currentGuideStepIndex != nil else { return }
        currentGuideStepIndex = nil
        currentGuideChordIndex = nil
        append("Guide stopped.")
        syncLumiGuideDisplayIfActive()
    }

    /// Moves the guide's current step by `delta` (±1 for up/down), clamped to the
    /// sequence's bounds — no wraparound, so repeatedly pressing the same arrow at either
    /// end is a safe no-op. Does nothing if the guide isn't running. Resets
    /// `currentGuideChordIndex` unconditionally: a chord index from the previous step has no
    /// meaning against the new one's (possibly absent, possibly shorter) progression.
    public func advanceGuideStep(by delta: Int) {
        guard let currentGuide, let currentGuideStepIndex else { return }
        let clamped = max(0, min(currentGuide.steps.count - 1, currentGuideStepIndex + delta))
        self.currentGuideStepIndex = clamped
        currentGuideChordIndex = nil
        syncLumiGuideDisplayIfActive()
    }

    /// Moves `abs(delta)` positions (±1 for left/right) within the current step's chord
    /// progression, crossing into the next/previous step's own progression once the current
    /// one runs out — a step with no progression at all is skipped through entirely, as if
    /// already exhausted, rather than stopping navigation dead. Clamps (no wraparound) only
    /// at the very start/end of the whole guide sequence. Does nothing if the guide isn't
    /// running.
    public func advanceGuideChord(by delta: Int) {
        guard currentGuide != nil, currentGuideStepIndex != nil, delta != 0 else { return }
        let direction = delta > 0 ? 1 : -1
        for _ in 0..<abs(delta) {
            guard advanceGuideChordOneStep(direction: direction) else { break }
        }
        // Real bug fix: crossing into a neighboring step's progression (see
        // `advanceGuideChordOneStep`'s own doc comment) changes `currentGuideStepIndex` —
        // i.e. the MODE — same as `advanceGuideStep` does, but this method never called
        // this. `syncLumiGuideDisplayIfActive` already no-ops when the resolved state hasn't
        // actually changed (the common case: moving between chords within the SAME step), so
        // calling it unconditionally here is cheap and only ever sends when warranted.
        syncLumiGuideDisplayIfActive()
    }

    /// Moves exactly one position in `direction` (+1/-1). Returns `false` if there's nowhere
    /// left to go (start/end of the whole sequence), leaving state unchanged — see
    /// `advanceGuideChord`'s doc comment for the cross-step/skip-empty-steps behavior this
    /// implements.
    @discardableResult
    private func advanceGuideChordOneStep(direction: Int) -> Bool {
        guard let currentGuide, let stepIndex = currentGuideStepIndex else { return false }
        let progression = currentGuide.steps[stepIndex].chordProgression ?? []

        if let chordIndex = currentGuideChordIndex {
            if progression.indices.contains(chordIndex) {
                let nextChordIndex = chordIndex + direction
                if progression.indices.contains(nextChordIndex) {
                    currentGuideChordIndex = nextChordIndex
                    return true
                }
                // Ran off this step's progression — fall through to search neighbors below.
            }
        } else if !progression.isEmpty {
            // Nothing selected yet, and the CURRENT step does have a progression — enter it
            // at whichever end matches `direction`, before considering neighbors at all (a
            // bare first press must land on this step's own chord, not skip past it).
            currentGuideChordIndex = direction > 0 ? 0 : progression.count - 1
            return true
        }
        // Either the current step's progression just ran out, or it has none at all (and
        // nothing was selected) — look for the next step in `direction` that actually has
        // one, skipping empty steps entirely rather than stopping on them.
        var candidateStepIndex = stepIndex + direction
        while currentGuide.steps.indices.contains(candidateStepIndex) {
            let candidateProgression = currentGuide.steps[candidateStepIndex].chordProgression ?? []
            if !candidateProgression.isEmpty {
                currentGuideStepIndex = candidateStepIndex
                currentGuideChordIndex = direction > 0 ? 0 : candidateProgression.count - 1
                return true
            }
            candidateStepIndex += direction
        }
        return false
    }

    /// The currently-active guide step's resolved mode, or `nil` if the guide isn't running
    /// or the step's `ModeReference` doesn't resolve (unknown `scaleID`).
    public func currentGuideStepMode() -> Mode? {
        guard let currentGuide, let currentGuideStepIndex, currentGuide.steps.indices.contains(currentGuideStepIndex) else { return nil }
        return currentGuide.steps[currentGuideStepIndex].mode.resolve()
    }

    /// The chord `currentGuideChordIndex` points at, or `nil` if nothing's selected (guide
    /// not running, current step has no progression, or nothing navigated to yet).
    public func currentGuideChordReference() -> ChordReference? {
        guard let currentGuide, let stepIndex = currentGuideStepIndex, let chordIndex = currentGuideChordIndex,
              let progression = currentGuide.steps[stepIndex].chordProgression, progression.indices.contains(chordIndex)
        else { return nil }
        return progression[chordIndex]
    }

    // MARK: - Scenes (declared musical "roles", each optionally attached to a live instrument)
    //
    // See `Sources/AppCore/Scene.swift`'s own doc comments for the full rationale. In short:
    // a `SceneRole` ("Piano 1", "Basse Guitare"...) is declared independently of whatever
    // happens to be plugged in, owns its own `soundName`, and is only ever ATTACHED to a live
    // `TrackID` at runtime (`attachInstrument(_:toRole:)`, the one place that ever happens).
    // This replaces the old `SceneTrack`-only model, which kept an instrument's config keyed
    // directly on `TrackID.wireIDText` — for a MIDI port, nothing more than CoreMIDI's own raw
    // enumeration-order index — so unplugging a keyboard (or plugging a second one in first)
    // silently broke reattachment on `loadScene`, with zero feedback. `SceneTrack`/the old
    // `Scene.tracks` shape is still decodable (see `Scene.init(from:)`) for old files.

    /// Creates a new, empty active scene — the starting point for declaring roles before
    /// attaching instruments to them. Replaces any previously active (unsaved) scene, same as
    /// `newPiece`/`newGuideSequence` already do for their own "start a fresh document" case.
    public func newScene(title: String) {
        currentScene = Scene(title: title)
        currentSceneFilePath = nil
        currentSceneRecordID = nil
        append("Nouvelle scene : \(title)")
    }

    /// Appends a new, unattached role to the active scene — returns its id so a caller (e.g.
    /// a menu action) can immediately offer to attach an instrument to it.
    @discardableResult
    public func addSceneRole(name: String) throws -> SceneRole.ID {
        guard var scene = currentScene else { throw SessionError.noSceneLoaded }
        let role = SceneRole(name: name)
        scene.roles.append(role)
        currentScene = scene
        append("Role ajoute : \(name)")
        return role.id
    }

    /// Removes a role — whatever instrument was attached to it (if any) is simply detached,
    /// not stopped/muted (mirrors `detachInstrument`'s own "bookkeeping only" scope).
    public func removeSceneRole(_ roleID: SceneRole.ID) throws {
        guard var scene = currentScene else { throw SessionError.noSceneLoaded }
        guard let index = scene.roles.firstIndex(where: { $0.id == roleID }) else { throw SessionError.unknownSceneRole }
        let name = scene.roles[index].name
        scene.roles.remove(at: index)
        currentScene = scene
        append("Role supprime : \(name)")
    }

    /// Sets a role's own sound — if an instrument is currently attached, reapplies it
    /// immediately, since the sound belongs to the ROLE, not to whichever instrument happens
    /// to occupy it right now (the whole point of moving `instrumentName` off the track).
    /// Applies the underlying `setInstrument` FIRST and only commits `soundName` to the role
    /// if that succeeds (real `try`, not `try?`) — this used to swallow a failed sample load,
    /// leaving the role showing a "sound" that was never actually loaded onto any sampler:
    /// the UI looked assigned, but nothing was reachable to explain total silence when played.
    ///
    /// **Real bug fixed here**: `scene.roles[index].soundEnabled` never used to be touched by
    /// this method, only `soundName` — but `SceneRole.soundEnabled` defaults to `false` and
    /// nothing in the UI ever set it any other way, so `applyRoleConfiguration` (run again on
    /// every subsequent `attachInstrument`/scene reload) always saw a "declared disabled" role
    /// and force-called `setSoundEnabled(false, ...)`, silently re-muting a track that had JUST
    /// had a real sound successfully loaded onto it. Symptom reported: "plays but no sound" the
    /// next time an instrument was (re)attached to a role that already had a sound assigned.
    /// Now `soundEnabled` tracks whether a sound is actually assigned, kept in sync with what
    /// `setInstrument`/`setSoundEnabled` already do to the live track.
    public func setSceneRoleSound(_ roleID: SceneRole.ID, soundName: String?, preset: SoundFontPresetIdentity? = nil) throws {
        guard var scene = currentScene else { throw SessionError.noSceneLoaded }
        guard let index = scene.roles.firstIndex(where: { $0.id == roleID }) else { throw SessionError.unknownSceneRole }
        let attachedTrackID = scene.roles[index].attachedTrackID
        if let attachedTrackID {
            if let soundName {
                try setInstrument(named: soundName, for: attachedTrackID, preset: preset)
            } else {
                try? setSoundEnabled(false, for: attachedTrackID)
            }
        }
        scene.roles[index].soundName = soundName
        scene.roles[index].soundPreset = soundName != nil ? preset : nil
        scene.roles[index].soundEnabled = soundName != nil
        currentScene = scene
        append("Son du role '\(scene.roles[index].name)' : \(soundName ?? "aucun")")
    }

    /// Sets a role's own mix volume (linear 0...1) — if an instrument is currently attached,
    /// applies it immediately to that instrument's own `SamplerUnit`; either way it's saved on
    /// the role itself, so a later `attachInstrument`/`loadScene` reapplies it via
    /// `applyRoleConfiguration`, same "the role owns its own configuration" precedent as
    /// `soundName`.
    public func setSceneRoleVolume(_ roleID: SceneRole.ID, volume: Float) throws {
        guard var scene = currentScene else { throw SessionError.noSceneLoaded }
        guard let index = scene.roles.firstIndex(where: { $0.id == roleID }) else { throw SessionError.unknownSceneRole }
        scene.roles[index].volume = volume
        let attachedTrackID = scene.roles[index].attachedTrackID
        currentScene = scene
        if let attachedTrackID {
            samplers[attachedTrackID]?.setVolume(volume)
        }
    }

    /// Sets a role's own declared listening state — if an instrument is currently attached,
    /// starts/stops it immediately to match.
    public func setSceneRoleListening(_ roleID: SceneRole.ID, isListening: Bool) throws {
        guard var scene = currentScene else { throw SessionError.noSceneLoaded }
        guard let index = scene.roles.firstIndex(where: { $0.id == roleID }) else { throw SessionError.unknownSceneRole }
        scene.roles[index].isListening = isListening
        let attachedTrackID = scene.roles[index].attachedTrackID
        currentScene = scene
        if let attachedTrackID {
            if isListening { try? startTrack(attachedTrackID) } else { stopTrack(attachedTrackID) }
        }
    }

    /// Sets a role's icon (see `IconVocabulary`) — purely decorative, no live track to update.
    public func setSceneRoleIcon(_ roleID: SceneRole.ID, iconSystemName: String?) throws {
        guard var scene = currentScene else { throw SessionError.noSceneLoaded }
        guard let index = scene.roles.firstIndex(where: { $0.id == roleID }) else { throw SessionError.unknownSceneRole }
        scene.roles[index].iconSystemName = iconSystemName
        currentScene = scene
    }

    /// Every role in the active scene with no instrument attached yet — `[]` if there's no
    /// active scene at all.
    public func freeSceneRoles() -> [SceneRole] {
        currentScene?.roles.filter { $0.attachedTrackID == nil } ?? []
    }

    /// Every live track NOT currently attached to any role in the active scene — `[]` if
    /// there's no active scene (nothing to be "unassigned" relative to).
    public func unassignedInstruments() -> [TrackInfo] {
        guard let scene = currentScene else { return [] }
        let attachedIDs = Set(scene.roles.compactMap(\.attachedTrackID))
        return tracks.filter { !attachedIDs.contains($0.id) }
    }

    /// The one place `SceneRole.attachedTrackID` is ever set to a non-nil value. Auto-detaches
    /// `trackID` from wherever else it was attached, and whatever was previously attached to
    /// `roleID` — moving an instrument between roles is a normal action, not an error, so this
    /// never throws/rejects for "already attached somewhere," it just logs both sides of the
    /// move — then applies the role's own declared sound/listening state onto the instrument.
    public func attachInstrument(_ trackID: TrackID, toRole roleID: SceneRole.ID) throws {
        guard var scene = currentScene else { throw SessionError.noSceneLoaded }
        guard let targetIndex = scene.roles.firstIndex(where: { $0.id == roleID }) else { throw SessionError.unknownSceneRole }
        let trackIdx = try trackIndex(trackID) // throws .unknownTrack if this instrument doesn't exist

        if let previousIndex = scene.roles.firstIndex(where: { $0.attachedTrackID == trackID }), previousIndex != targetIndex {
            append("Instrument deplace : detache de '\(scene.roles[previousIndex].name)'.")
            scene.roles[previousIndex].attachedTrackID = nil
        }
        if let displaced = scene.roles[targetIndex].attachedTrackID, displaced != trackID {
            append("Role '\(scene.roles[targetIndex].name)' : instrument precedent detache.")
        }

        scene.roles[targetIndex].attachedTrackID = trackID
        scene.roles[targetIndex].lastAttachedInstrument = identityHint(for: trackID)
        if trackID == .microphone {
            // Sticky, like `lastAttachedInstrument`: whatever mode the microphone was already
            // running under gets remembered on the role, so a later `applyRoleConfiguration`
            // (on a fresh attach or a scene reload) restores the SAME mode rather than
            // silently resetting to `MicrophoneRecognitionMode.default`.
            scene.roles[targetIndex].microphoneRecognitionMode = tracks[trackIdx].microphoneRecognitionMode
        }
        let role = scene.roles[targetIndex]
        currentScene = scene

        try? applyRoleConfiguration(role, to: trackID)
        append("Instrument attache au role '\(role.name)'.")
    }

    /// Breaks a role's attachment — bookkeeping only, mirroring `stopTrack`'s own "state
    /// survives a stop" convention: the instrument itself keeps whatever listening/sound state
    /// it already had, only the role/track association is cleared. A no-op (not an error) if
    /// the role wasn't attached to anything, same idempotence already used elsewhere (e.g.
    /// `stopTrack` on an already-stopped track).
    public func detachInstrument(fromRole roleID: SceneRole.ID) throws {
        guard var scene = currentScene else { throw SessionError.noSceneLoaded }
        guard let index = scene.roles.firstIndex(where: { $0.id == roleID }) else { throw SessionError.unknownSceneRole }
        guard scene.roles[index].attachedTrackID != nil else { return }
        let name = scene.roles[index].name
        scene.roles[index].attachedTrackID = nil
        currentScene = scene
        append("Instrument detache du role '\(name)'.")
    }

    /// Applies a role's own `isListening`/`soundName`/`soundEnabled` onto whichever track is
    /// now attached to it — the same three steps `loadScene` used to run per saved
    /// `SceneTrack`, shared by `attachInstrument` and `loadScene` alike so they can't drift
    /// apart. Errors are swallowed (`try?`), same "best effort, don't abort the rest" spirit
    /// already used throughout this whole feature — a missing sample file shouldn't stop the
    /// attachment itself from taking effect.
    private func applyRoleConfiguration(_ role: SceneRole, to trackID: TrackID) throws {
        if let mode = role.microphoneRecognitionMode, trackID == .microphone {
            try? setMicrophoneRecognitionMode(mode, for: trackID)
        }
        // Real bug fixed here: this used to only ever turn listening ON (`if role.isListening
        // { startTrack }`), never OFF — so a role explicitly declared muted/not-listening in
        // the scene file had zero effect on a track that happened to already be listening
        // (e.g. every MIDI track this app auto-starts at launch, regardless of any scene).
        // Reported symptom: a scene's role shown "muted" in the UI, but Studio still showed
        // that same instrument actively listening/recognizing chords.
        if role.isListening {
            try? startTrack(trackID)
        } else {
            stopTrack(trackID)
        }
        if let soundName = role.soundName {
            try? setInstrument(named: soundName, for: trackID, preset: role.soundPreset)
            if !role.soundEnabled { try? setSoundEnabled(false, for: trackID) }
        } else {
            try? setSoundEnabled(role.soundEnabled, for: trackID)
        }
        // After the sound setup above, which is what actually creates/retrieves this track's
        // `SamplerUnit` in `samplers` — a no-op if none exists yet (role has no sound enabled).
        samplers[trackID]?.setVolume(role.volume)
    }

    /// A best-effort snapshot of `trackID`'s current identity, for `SceneRole.
    /// lastAttachedInstrument` — see `InstrumentIdentityHint`'s own doc comment for why each
    /// case is (or isn't) trustworthy across a reconnect. `nil` for `.remote` (this feature is
    /// local/standalone-only for now, see `InstrumentIdentityHint`'s doc comment) or for a
    /// `.midiSource` index no longer visible to CoreMIDI at the moment this is captured.
    private func identityHint(for trackID: TrackID) -> InstrumentIdentityHint? {
        switch trackID {
        case .midiMerged:
            return .midiMerged
        case .midiSource(let index):
            let descriptors = MIDIInputListener.sourceDescriptors()
            guard descriptors.indices.contains(index) else { return nil }
            let descriptor = descriptors[index]
            return .midiPort(midiUniqueID: descriptor.uniqueID, displayName: descriptor.displayName)
        case .computerKeyboard:
            return .computerKeyboard
        case .webKeyboard(let clientID):
            return .webKeyboard(clientID: clientID)
        case .microphone:
            return .microphone
        case .remote:
            return nil
        }
    }

    /// Decides whether `trackID` is likely the SAME instrument `hint` was last attached to —
    /// used by `loadScene` to auto-reattach and by
    /// `reconcileSceneAttachmentsAfterTrackRefresh` after a mid-session MIDI reshuffle.
    /// Deliberately conservative: for `.midiPort`, a CoreMIDI `uniqueID` match wins outright,
    /// but falling back to `displayName` only succeeds if EXACTLY ONE currently-visible source
    /// shares that name — a first-match-wins guess among duplicates would be exactly the kind
    /// of silent misattachment this whole redesign exists to stop making. `false` for a `nil`
    /// hint (nothing to match against) or any hint/`TrackID` kind mismatch.
    private func matches(_ hint: InstrumentIdentityHint?, _ trackID: TrackID) -> Bool {
        guard let hint else { return false }
        switch (hint, trackID) {
        case (.midiMerged, .midiMerged):
            // Never reattach a `.midiMerged` hint while the session is actually in individual
            // mode right now — `loadScene`/reconciliation must not silently flip
            // `midiFusionMode` as a side effect.
            return midiFusionMode == .merged
        case (.midiPort(let hintUniqueID, let hintDisplayName), .midiSource(let index)):
            let descriptors = MIDIInputListener.sourceDescriptors()
            guard descriptors.indices.contains(index) else { return false }
            let candidate = descriptors[index]
            if let hintUniqueID, let candidateID = candidate.uniqueID {
                return hintUniqueID == candidateID
            }
            return candidate.displayName == hintDisplayName
                && descriptors.filter { $0.displayName == hintDisplayName }.count == 1
        case (.computerKeyboard, .computerKeyboard):
            return true
        case (.webKeyboard(let hintClientID), .webKeyboard(let candidateClientID)):
            return hintClientID == candidateClientID
        case (.microphone, .microphone):
            return true
        default:
            return false
        }
    }

    /// After `refreshTracks()` rebuilds `tracks` from whatever CoreMIDI currently reports, an
    /// attached role's `.midiSource(Int)` may now point at a DIFFERENT physical device (index
    /// reshuffled) or at nothing at all (device unplugged) — this migrates each attached MIDI
    /// role to wherever its device now sits, or frees it with a log line if it's genuinely
    /// gone, then retries matching for every still-free role against the freshly rebuilt
    /// `tracks`. This is what makes "replug the same keyboard, run `tracks`" reattach
    /// automatically, given this app's own accepted no-hot-plug-notifications limitation (see
    /// `refreshTracks`'s own doc comment).
    private func reconcileSceneAttachmentsAfterTrackRefresh() {
        guard var scene = currentScene else { return }
        var changed = false
        var claimedTrackIDs = Set(scene.roles.compactMap(\.attachedTrackID))

        for index in scene.roles.indices {
            guard let attachedID = scene.roles[index].attachedTrackID else { continue }
            guard case .midiSource = attachedID else { continue }
            guard !tracks.contains(where: { $0.id == attachedID }) else { continue } // still valid
            claimedTrackIDs.remove(attachedID)
            let hint = scene.roles[index].lastAttachedInstrument
            if let relocated = tracks.first(where: { !claimedTrackIDs.contains($0.id) && matches(hint, $0.id) }) {
                scene.roles[index].attachedTrackID = relocated.id
                claimedTrackIDs.insert(relocated.id)
                append("Role '\(scene.roles[index].name)' : instrument MIDI retrouve a un nouvel index.")
            } else {
                scene.roles[index].attachedTrackID = nil
                append("Role '\(scene.roles[index].name)' : instrument MIDI introuvable, role libere.")
            }
            changed = true
        }
        for index in scene.roles.indices where scene.roles[index].attachedTrackID == nil {
            guard let hint = scene.roles[index].lastAttachedInstrument else { continue }
            guard let candidate = tracks.first(where: { !claimedTrackIDs.contains($0.id) && matches(hint, $0.id) }) else { continue }
            scene.roles[index].attachedTrackID = candidate.id
            claimedTrackIDs.insert(candidate.id)
            append("Role '\(scene.roles[index].name)' : instrument reattache automatiquement.")
            changed = true
        }
        if changed { currentScene = scene }
    }

    /// Captures the active scene (or, if none was ever created, synthesizes one on the fly —
    /// see below) and writes it to `path`.
    public func saveScene(title: String, toJSONFile path: String) throws {
        var scene: Scene
        if var existing = currentScene {
            existing.title = title
            // Refresh every attached role's identity hint from the live device right before
            // writing — catches a mid-session `attachInstrument` call (already recomputed at
            // attach time, but doesn't hurt) and, more importantly, a MIDI reshuffle that
            // `reconcileSceneAttachmentsAfterTrackRefresh` already migrated the attachment
            // through without necessarily refreshing this specific hint field.
            for index in existing.roles.indices {
                if let trackID = existing.roles[index].attachedTrackID {
                    existing.roles[index].lastAttachedInstrument = identityHint(for: trackID)
                    if trackID == .microphone, let trackIdx = tracks.firstIndex(where: { $0.id == trackID }) {
                        existing.roles[index].microphoneRecognitionMode = tracks[trackIdx].microphoneRecognitionMode
                    }
                }
            }
            scene = existing
        } else {
            // No declared roles at all (a user who never touched the new role commands) —
            // synthesize one role per currently listening-or-sounding local track, named
            // after its current label, pre-attached — preserves the old "just save what's
            // on" one-shot ergonomics for anyone who ignores the new machinery entirely.
            let roles = tracks.compactMap { track -> SceneRole? in
                guard track.id.wireIDText != nil, track.isListening || track.soundEnabled else { return nil }
                return SceneRole(
                    name: track.label, soundName: track.instrumentName, isListening: track.isListening,
                    soundEnabled: track.soundEnabled, lastAttachedInstrument: identityHint(for: track.id),
                    attachedTrackID: track.id
                )
            }
            scene = Scene(title: title, roles: roles)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(scene)
        try data.write(to: URL(fileURLWithPath: path))
        currentSceneFilePath = path
        append("Scene sauvegardee : \(path).")
    }

    private static let supportedSceneExtensions: Set<String> = ["json"]

    /// Every scene's title currently in the SwiftData store, sorted — mirrors
    /// `guideSequenceNames`. Refreshed after every migrate/insert/update/delete.
    public private(set) var sceneNames: [String] = []

    private func refreshSceneNames() {
        sceneNames = ((try? modelContext.fetch(FetchDescriptor<SceneRecord>())) ?? []).map(\.title).sorted()
    }

    /// One-time bridge from a folder of `.json` scene files to the SwiftData store — mirrors
    /// `migrateGuideSequencesFromJSONIfNeeded`: a no-op if the store already has scenes,
    /// otherwise migrates every `.json` found in `folderPath` (never deleting the originals,
    /// and reusing `Scene`'s own `Codable` conformance — so its `LegacyCodingKeys`/
    /// `SceneTrack` fallback still applies unchanged to an old-format file). No "seed
    /// built-ins" — scenes have none.
    public func migrateScenesFromJSONIfNeeded(in folderPath: String) {
        refreshSceneNames()
        guard sceneNames.isEmpty else { return }

        let folderURL = URL(fileURLWithPath: folderPath)
        let jsonFiles = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil))?
            .filter { Self.supportedSceneExtensions.contains($0.pathExtension.lowercased()) } ?? []
        var migrated = 0
        for fileURL in jsonFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let scene = try? JSONDecoder().decode(Scene.self, from: data) else { continue }
            modelContext.insert(SceneRecord(scene))
            migrated += 1
        }
        if migrated > 0 {
            try? modelContext.save()
            append("Migrated \(migrated) scene(s) from \(folderPath) (originals left in place).")
        }
        refreshSceneNames()
    }

    /// Saves under a title — "Save As". Writes through a temporary file via
    /// `saveScene(title:toJSONFile:)` (the same technique `SceneFileView`'s own "Exporter"
    /// button already uses) so the exact same synthesize-from-live-tracks fallback and
    /// identity-hint refresh happens whether saving to the store or exporting to a real file —
    /// then wraps the result into the SwiftData store instead of leaving it on disk. If a
    /// record with this exact title already exists, overwrites it (same "saving under an
    /// existing name silently overwrites it" behavior the old folder-based version had).
    public func saveScene(title: String, as name: String) throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try saveScene(title: name, toJSONFile: tempFile.path)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        let data = try Data(contentsOf: tempFile)
        let scene = try JSONDecoder().decode(Scene.self, from: data)
        currentScene = scene

        let descriptor = FetchDescriptor<SceneRecord>(predicate: #Predicate { $0.title == name })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.encodedScene = data
            currentSceneRecordID = existing.id
        } else {
            let record = SceneRecord(scene)
            modelContext.insert(record)
            currentSceneRecordID = record.id
        }
        try modelContext.save()
        refreshSceneNames()
        append("Scene sauvegardee : \(name).")
    }

    /// Re-saves the current scene to whichever record it was last loaded from/saved to
    /// (`currentSceneRecordID`) — updates that exact record even if `currentScene.title` has
    /// since changed (unlike `saveScene(title:as:)`, which addresses by title). Mirrors
    /// `saveGuideSequence()`.
    public func saveScene() throws {
        guard let currentScene else { throw SessionError.noSceneLoaded }
        guard let currentSceneRecordID else { throw SessionError.noSceneLoaded }
        let descriptor = FetchDescriptor<SceneRecord>(predicate: #Predicate { $0.id == currentSceneRecordID })
        guard let record = try? modelContext.fetch(descriptor).first else { throw SessionError.noSceneLoaded }
        record.title = currentScene.title
        record.encodedScene = (try? JSONEncoder().encode(currentScene)) ?? record.encodedScene
        try modelContext.save()
        refreshSceneNames()
        append("Scene sauvegardee : \(currentScene.title).")
    }

    /// Gives the active scene a name — the mechanism behind "type a name in the edit screen to
    /// save an anonymous scene": if it was never saved (`currentSceneRecordID == nil`), this IS
    /// the first save (inserts a new record, same as `saveScene(title:as:)`'s insert branch); if
    /// it's already backed by a record, renames that exact record in place (keeps its identity,
    /// unlike `saveScene(title:as:)` which matches an existing record by title text).
    public func renameCurrentScene(to newTitle: String) throws {
        guard var scene = currentScene else { throw SessionError.noSceneLoaded }
        scene.title = newTitle
        currentScene = scene
        if let currentSceneRecordID {
            let descriptor = FetchDescriptor<SceneRecord>(predicate: #Predicate { $0.id == currentSceneRecordID })
            guard let record = try? modelContext.fetch(descriptor).first else { throw SessionError.noSceneLoaded }
            record.title = newTitle
            record.encodedScene = (try? JSONEncoder().encode(scene)) ?? record.encodedScene
        } else {
            let record = SceneRecord(scene)
            modelContext.insert(record)
            self.currentSceneRecordID = record.id
        }
        try modelContext.save()
        refreshSceneNames()
        append("Scene renommee : \(newTitle).")
    }

    /// Renames a stored scene by list position — not necessarily the active one. Mirrors
    /// `renameColorPalette(atIndex:name:)`. Keeps `currentScene`/`currentSceneRecordID` in sync
    /// if the renamed record happens to be the active one.
    public func renameScene(atIndex index: Int, name: String) throws {
        guard sceneNames.indices.contains(index) else { throw SessionError.invalidSceneIndex }
        let oldName = sceneNames[index]
        let descriptor = FetchDescriptor<SceneRecord>(predicate: #Predicate { $0.title == oldName })
        guard let record = try? modelContext.fetch(descriptor).first else { throw SessionError.invalidSceneIndex }
        record.title = name
        try modelContext.save()
        if record.id == currentSceneRecordID { currentScene?.title = name }
        refreshSceneNames()
        append("Scene renommee : \(oldName) -> \(name).")
    }

    /// The icon assigned to a stored scene by list position, if any — see `IconVocabulary`.
    public func sceneIcon(atIndex index: Int) -> String? {
        guard sceneNames.indices.contains(index) else { return nil }
        let name = sceneNames[index]
        let descriptor = FetchDescriptor<SceneRecord>(predicate: #Predicate { $0.title == name })
        return (try? modelContext.fetch(descriptor).first)?.iconSystemName
    }

    /// Sets a stored scene's icon by list position — mirrors `renameScene(atIndex:name:)`, a
    /// real `SceneRecord` column rather than part of `encodedScene` (see that field's own doc
    /// comment), so no re-encoding of the scene blob is needed here.
    public func setSceneIcon(atIndex index: Int, iconSystemName: String?) throws {
        guard sceneNames.indices.contains(index) else { throw SessionError.invalidSceneIndex }
        let name = sceneNames[index]
        let descriptor = FetchDescriptor<SceneRecord>(predicate: #Predicate { $0.title == name })
        guard let record = try? modelContext.fetch(descriptor).first else { throw SessionError.invalidSceneIndex }
        record.iconSystemName = iconSystemName
        try modelContext.save()
        append("Icone de scene mise a jour : \(name).")
    }

    /// The exact stored bytes for a scene by list position, for per-row export — a stored
    /// record's `encodedScene` already IS the full JSON of that `Scene`, so this needs no
    /// temp-file round trip and never touches `currentScene`/`currentSceneRecordID` (exporting a
    /// scene that isn't the active one must not disturb what's currently being edited).
    public func exportedSceneData(atIndex index: Int) throws -> Data {
        guard sceneNames.indices.contains(index) else { throw SessionError.invalidSceneIndex }
        let name = sceneNames[index]
        let descriptor = FetchDescriptor<SceneRecord>(predicate: #Predicate { $0.title == name })
        guard let record = try? modelContext.fetch(descriptor).first else { throw SessionError.invalidSceneIndex }
        return record.encodedScene
    }

    /// Backs the "Nouvelle scene" button: persists the current scene first if it's already
    /// named/saved (so switching away never silently loses edits), then starts a fresh unnamed
    /// one. If the current scene is anonymous (never named), nothing is persisted — an
    /// anonymous scene is discarded when you move on, same rule as it not being saved on quit.
    public func createNewScene() throws {
        if currentSceneRecordID != nil { try saveScene() }
        newScene(title: "")
    }

    /// Called once at app launch (not by the CLI/web console, which keep their own no-auto-load
    /// behavior): resolves the "which scene should be showing" question so the UI never has to
    /// show a dead-end "no active scene" placeholder. With no saved scenes, starts a fresh
    /// anonymous one, with a single role already attached and ready to play (per explicit user
    /// request — a genuinely first-time install should never land on an empty, silent scene) —
    /// see `attachDefaultRoleForFreshScene()`. With one or more saved, leaves `currentScene` nil
    /// so the app lands on the scene list first — picking one (even the only one) is always an
    /// explicit step in the list → configuration flow.
    public func ensureSceneReadyForLaunch() {
        guard currentScene == nil else { return }
        if sceneNames.isEmpty {
            currentScene = Scene(title: "")
            attachDefaultRoleForFreshScene()
        }
    }

    /// One role, attached to whichever live input makes sense with nothing configured yet: a
    /// detected MIDI keyboard if one is visible (preferred — a real instrument beats the virtual
    /// one when both are possible), else the computer keyboard, always available. No explicit
    /// `soundName` — leaves the role's sound as the sampler's own default (see
    /// `setSoundEnabled(_:for:)`'s system-instrument fallback), immediately listening at full
    /// volume so this fresh scene is genuinely ready to play, not just present. Every step here
    /// is best-effort (`try?`) — a failure must never prevent the anonymous scene itself from
    /// existing.
    private func attachDefaultRoleForFreshScene() {
        let targetTrackID = tracks.first { if case .midiSource = $0.id { return true } else { return false } }?.id ?? .computerKeyboard
        let roleName = tracks.first { $0.id == targetTrackID }?.label ?? "Instrument"
        guard let roleID = try? addSceneRole(name: roleName) else { return }
        try? attachInstrument(targetTrackID, toRole: roleID)
        try? setSceneRoleListening(roleID, isListening: true)
        try? setSceneRoleVolume(roleID, volume: 1.0)
    }

    /// Loads a scene by title from the SwiftData store — replaces the old folder-based
    /// `loadScene(named:)`. Round-trips through a temp file via `loadScene(fromJSONFile:)`
    /// (same reuse technique as `saveScene(title:as:)`) so the reattachment-matching logic
    /// stays in exactly one place. First match wins if two records share a title (same
    /// tolerance `useLLMConnection(named:)`/`useGuideSequence(named:)` already accept).
    public func useScene(named name: String) throws {
        let descriptor = FetchDescriptor<SceneRecord>(predicate: #Predicate { $0.title == name })
        guard let record = try? modelContext.fetch(descriptor).first else { throw SessionError.invalidSceneIndex }
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try record.encodedScene.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try loadScene(fromJSONFile: tempFile.path)
        currentSceneRecordID = record.id
    }

    /// Convenience over `useScene(named:)` using the 0-based position in `sceneNames`.
    public func useScene(atIndex index: Int) throws {
        guard sceneNames.indices.contains(index) else { throw SessionError.invalidSceneIndex }
        try useScene(named: sceneNames[index])
    }

    /// Deletes a stored scene — new capability (the old folder-based UI had no delete
    /// button; removing a file meant using the Finder directly, which stops being possible
    /// once the data lives in a private SwiftData store).
    public func deleteScene(atIndex index: Int) throws {
        guard sceneNames.indices.contains(index) else { throw SessionError.invalidSceneIndex }
        let name = sceneNames[index]
        let descriptor = FetchDescriptor<SceneRecord>(predicate: #Predicate { $0.title == name })
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(record)
        try modelContext.save()
        refreshSceneNames()
        append("Deleted scene: \(name)")
    }

    /// Loads a saved scene, best-effort: each role's `lastAttachedInstrument` hint is matched
    /// (`matches(_:_:)`) against currently-visible instruments to decide whether to reattach
    /// automatically — each live track is claimed by at most one role during this pass, same
    /// "an instrument occupies only one role" invariant `attachInstrument` enforces at runtime.
    /// Unlike the old flat `SceneTrack`-keyed format, a role that can't be matched stays
    /// explicitly FREE and is called out in the log, never silently dropped with no feedback.
    public func loadScene(fromJSONFile path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        var scene = try JSONDecoder().decode(Scene.self, from: data)
        var claimedTrackIDs: Set<TrackID> = []
        var reattachedCount = 0
        for index in scene.roles.indices {
            let hint = scene.roles[index].lastAttachedInstrument
            guard let candidate = tracks.first(where: { !claimedTrackIDs.contains($0.id) && matches(hint, $0.id) }) else { continue }
            scene.roles[index].attachedTrackID = candidate.id
            claimedTrackIDs.insert(candidate.id)
            reattachedCount += 1
        }
        currentScene = scene
        currentSceneFilePath = path

        for role in scene.roles {
            guard let trackID = role.attachedTrackID else { continue }
            try? applyRoleConfiguration(role, to: trackID)
        }

        // Real bug fixed here: a live track NOT attached to any role in the scene just loaded
        // used to keep whatever listening/sound state it already had (e.g. every MIDI track
        // this app auto-starts listening+sounding at launch) — the scene had no way to say
        // "this input isn't part of me," only to configure the ones it DOES claim. Now the
        // scene is authoritative: anything it doesn't attach is stopped and muted, so what
        // Studio shows always matches what the loaded scene actually declares.
        for track in tracks where !claimedTrackIDs.contains(track.id) {
            stopTrack(track.id)
            try? setSoundEnabled(false, for: track.id)
        }

        let freeRoles = scene.roles.filter { $0.attachedTrackID == nil }
        var message = "Scene chargee : \(scene.title) — \(scene.roles.count) role(s), "
            + "\(reattachedCount) reattache(s) automatiquement, \(freeRoles.count) libre(s)."
        if !freeRoles.isEmpty {
            message += " Roles libres : \(freeRoles.map(\.name).joined(separator: ", "))"
                + " — utilise 'scene-role-attach' pour les affecter."
        }
        append(message)
    }


    // MARK: - Color palettes (per-instance, shared by the web console and virtual keyboard)

    /// One-time bridge from `palettes.json` to the SwiftData store — mirrors
    /// `migrateLLMConnectionsFromJSONIfNeeded`: a no-op if the store already has palettes
    /// (idempotent, safe to call on every launch), otherwise migrates the file's contents
    /// (never deleting it — same "don't remove what you didn't create" caution) or seeds
    /// `ColorPalette.builtInDefaults` if there's nothing to migrate. Resets
    /// `activeColorPaletteIndex` to 0 — which palette was active is never persisted, by design
    /// (see `activeColorPaletteIndex`'s doc comment).
    public func migrateColorPalettesFromJSONIfNeeded(fromJSONFile path: String) {
        refreshColorPalettes()
        guard colorPalettes.isEmpty else { return }

        let toSeed: [ColorPalette]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let file = try? JSONDecoder().decode(ColorPaletteFile.self, from: data), !file.palettes.isEmpty {
            toSeed = file.palettes
            append("Migrated \(file.palettes.count) color palette(s) from \(path) (original left in place).")
        } else {
            toSeed = ColorPalette.builtInDefaults
            append("Seeded \(toSeed.count) built-in color palette(s).")
        }
        for (index, palette) in toSeed.enumerated() {
            modelContext.insert(ColorPaletteRecord(palette, sortOrder: index))
        }
        try? modelContext.save()
        refreshColorPalettes()
        activeColorPaletteIndex = 0
    }

    /// Re-reads `colorPalettes` (in stored order, see `ColorPaletteRecord.sortOrder`) from
    /// `modelContext` — called after every migrate/insert/update so the in-memory list every
    /// caller already iterates never drifts from what's actually stored. Mirrors
    /// `refreshLLMConnections()`. Deliberately does NOT touch `activeColorPaletteIndex` (unlike
    /// the initial migration) — an in-place edit (`updateColorPalette`/`renameColorPalette`)
    /// never changes how many palettes there are or their order, so the active selection stays
    /// valid across a refresh.
    private func refreshColorPalettes() {
        let descriptor = FetchDescriptor<ColorPaletteRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        let records = (try? modelContext.fetch(descriptor)) ?? []
        colorPalettes = records.map(\.asColorPalette)
    }

    public func selectColorPalette(named name: String) throws {
        guard let index = colorPalettes.firstIndex(where: { $0.name == name }) else { throw SessionError.invalidColorPaletteIndex }
        try selectColorPalette(atIndex: index)
    }

    /// The one place `activeColorPaletteIndex` actually changes — `selectColorPalette(named:)`
    /// delegates here (not the reverse) since going index-first avoids re-deriving an index
    /// from a name that isn't guaranteed unique (unlike e.g. `llmConnections`' file names).
    public func selectColorPalette(atIndex index: Int) throws {
        guard colorPalettes.indices.contains(index) else { throw SessionError.invalidColorPaletteIndex }
        activeColorPaletteIndex = index
        append("Using color palette: \(activeColorPalette.name)")
    }

    /// Replaces one palette's colors in place (keeping its name and position) and persists —
    /// `colors`/`textColors` must both be exactly 12 entries (one per pitch class, same as
    /// every existing palette) or this throws rather than silently storing a malformed
    /// palette. `textColors` defaults to `ColorPalette.legibleTextColors(for:)` when omitted.
    public func updateColorPalette(atIndex index: Int, colors: [String], textColors: [String]? = nil) throws {
        guard colorPalettes.indices.contains(index) else { throw SessionError.invalidColorPaletteIndex }
        guard colors.count == 12 else { throw SessionError.invalidColorPaletteFile }
        let resolvedTextColors = textColors ?? ColorPalette.legibleTextColors(for: colors)
        guard resolvedTextColors.count == 12 else { throw SessionError.invalidColorPaletteFile }
        let records = (try? modelContext.fetch(FetchDescriptor<ColorPaletteRecord>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        guard records.indices.contains(index) else { throw SessionError.invalidColorPaletteIndex }
        records[index].colors = colors
        records[index].textColors = resolvedTextColors
        try modelContext.save()
        refreshColorPalettes()
    }

    /// Renames a palette in place and persists — kept separate from `updateColorPalette`
    /// (which never touches the name) so the editor UI can rename without also having to
    /// resend all 12 colors.
    public func renameColorPalette(atIndex index: Int, name: String) throws {
        guard colorPalettes.indices.contains(index) else { throw SessionError.invalidColorPaletteIndex }
        let records = (try? modelContext.fetch(FetchDescriptor<ColorPaletteRecord>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        guard records.indices.contains(index) else { throw SessionError.invalidColorPaletteIndex }
        records[index].name = name
        try modelContext.save()
        refreshColorPalettes()
    }

    /// Appends a brand-new palette (starting from `ColorPalette.builtInDefaults[0]`'s colors
    /// when none are given — a real starting point to tweak, not 12 copies of one color) and
    /// selects it immediately, so creating a palette drops the user straight into editing
    /// something they're already looking at.
    public func addColorPalette(name: String, colors: [String]? = nil) throws {
        let resolvedColors = colors ?? ColorPalette.builtInDefaults[0].colors
        let newPalette = ColorPalette(name: name, colors: resolvedColors, textColors: ColorPalette.legibleTextColors(for: resolvedColors))
        modelContext.insert(ColorPaletteRecord(newPalette, sortOrder: colorPalettes.count))
        try modelContext.save()
        refreshColorPalettes()
        try selectColorPalette(atIndex: colorPalettes.count - 1)
    }

    // MARK: - UI language (shared by terminal, web console, virtual keyboard)

    /// Which of the supported languages the static UI text is shown in — unlike
    /// `activeColorPaletteIndex`, this IS persisted (see
    /// `migrateLanguageSettingFromJSONIfNeeded`/`setLanguage`) since a language choice should
    /// survive a relaunch rather than silently reset to French every time.
    public private(set) var currentLanguage: AppLanguage = .fr

    /// One-time bridge from `language.json` to the SwiftData store — mirrors
    /// `migrateColorPalettesFromJSONIfNeeded(fromJSONFile:)`, but for a singleton value: a
    /// no-op (beyond loading the existing value) if a `LanguageSettingRecord` already exists,
    /// otherwise migrates the file's language (left in place) or seeds French.
    public func migrateLanguageSettingFromJSONIfNeeded(fromJSONFile path: String) {
        if let existing = try? modelContext.fetch(FetchDescriptor<LanguageSettingRecord>()).first {
            currentLanguage = existing.asAppLanguage
            return
        }
        let language: AppLanguage
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let file = try? JSONDecoder().decode(LanguageSettingFile.self, from: data) {
            language = file.language
            append("Migrated language setting from \(path) (original left in place).")
        } else {
            language = .fr
        }
        modelContext.insert(LanguageSettingRecord(language))
        try? modelContext.save()
        currentLanguage = language
    }

    /// The one place `currentLanguage` actually changes at runtime — persists immediately
    /// (unlike palette selection) since this setting must survive a relaunch. Unlike the old
    /// JSON-backed version, this no longer depends on a settings folder having been chosen —
    /// same rationale as `LLMConnectionRecord` not living inside that folder either.
    public func setLanguage(_ language: AppLanguage) throws {
        currentLanguage = language
        if let existing = try? modelContext.fetch(FetchDescriptor<LanguageSettingRecord>()).first {
            existing.language = language.rawValue
        } else {
            modelContext.insert(LanguageSettingRecord(language))
        }
        try modelContext.save()
    }

    // MARK: - Chord notation style (Chord/Mode/Progression Library, see `MusicTheoryKit.NotationStyle`)

    /// Which chord-naming convention chord/mode/progression names are displayed in — mirrors
    /// `currentLanguage`'s own "persisted singleton" shape exactly (see
    /// `NotationStyleSettingRecord`). Only one concrete style ships today
    /// (`AngloAmericanNotationStyle`), but every chord-name display already goes through this
    /// rather than a hardcoded style, so adding a second is additive.
    public private(set) var notationStyle: any NotationStyle = AngloAmericanNotationStyle()

    /// One-time load (there's nothing to migrate from a legacy JSON file for this setting — it
    /// didn't exist before the Chord/Mode/Progression Library — so this only ever seeds the
    /// default the first time, then loads whatever was last persisted).
    private func loadNotationStyleSetting() {
        if let existing = try? modelContext.fetch(FetchDescriptor<NotationStyleSettingRecord>()).first {
            notationStyle = NotationStyleRegistry.byID(existing.styleID)
        } else {
            modelContext.insert(NotationStyleSettingRecord(notationStyle.id))
            try? modelContext.save()
        }
    }

    /// The one place `notationStyle` actually changes at runtime — persists immediately, same
    /// as `setLanguage`.
    public func setNotationStyle(_ style: any NotationStyle) throws {
        notationStyle = style
        if let existing = try? modelContext.fetch(FetchDescriptor<NotationStyleSettingRecord>()).first {
            existing.styleID = style.id
        } else {
            modelContext.insert(NotationStyleSettingRecord(style.id))
        }
        try modelContext.save()
    }

    /// Which favorite sound the Théorie screens' audition playback uses — set from Settings >
    /// Théorie (`TheorieSettingsView`), read (via `theoryAuditionSound()`, never this raw id
    /// directly) by the Accords/Modes/Progressions screens themselves, which no longer own any
    /// picker or state of their own for this — see that settings view's own doc comment for why
    /// this moved out of the screens.
    public private(set) var theoryAuditionSoundID: String?

    private func loadTheoryAuditionSoundSetting() {
        if let existing = try? modelContext.fetch(FetchDescriptor<TheoryAuditionSoundSettingRecord>()).first {
            theoryAuditionSoundID = existing.soundID
        } else {
            modelContext.insert(TheoryAuditionSoundSettingRecord(nil))
            try? modelContext.save()
        }
    }

    public func setTheoryAuditionSoundID(_ soundID: String?) throws {
        theoryAuditionSoundID = soundID
        if let existing = try? modelContext.fetch(FetchDescriptor<TheoryAuditionSoundSettingRecord>()).first {
            existing.soundID = soundID
        } else {
            modelContext.insert(TheoryAuditionSoundSettingRecord(soundID))
        }
        try modelContext.save()
    }

    /// The actual `FavoriteSound` to use right now — whichever `favoriteSounds` entry matches
    /// the persisted `theoryAuditionSoundID`, or simply the first favorite if that's unset or
    /// stale (e.g. the previously-picked sound was un-favorited since) — so every Théorie
    /// screen's playback always has a sensible default without needing its own "pick one first"
    /// step, even if the user never opens Settings > Théorie at all.
    public func theoryAuditionSound() -> FavoriteSound? {
        favoriteSounds.first { $0.id == theoryAuditionSoundID } ?? favoriteSounds.first
    }

    // MARK: - Chord progression templates (roman-numeral libraries, see `RomanNumeralChord`)

    /// Every template loaded from the SwiftData store — same "flat list, hand-edited outside
    /// the app" convention as `colorPalettes`, not a one-document-per-file model like
    /// `Scene`/`GuideSequence`.
    public private(set) var chordProgressionTemplates: [ChordProgressionTemplate] = [ChordProgressionTemplate.builtInDefaults[0]]

    /// Mirrors `migrateColorPalettesFromJSONIfNeeded(fromJSONFile:)`.
    public func migrateChordProgressionTemplatesFromJSONIfNeeded(fromJSONFile path: String) {
        refreshChordProgressionTemplates()
        guard chordProgressionTemplates.isEmpty else { return }

        let toSeed: [ChordProgressionTemplate]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let file = try? JSONDecoder().decode(ChordProgressionTemplateFile.self, from: data), !file.progressions.isEmpty {
            toSeed = file.progressions
            append("Migrated \(file.progressions.count) chord progression template(s) from \(path) (original left in place).")
        } else {
            toSeed = ChordProgressionTemplate.builtInDefaults
            append("Seeded \(toSeed.count) built-in chord progression template(s).")
        }
        for (index, template) in toSeed.enumerated() {
            modelContext.insert(ChordProgressionTemplateRecord(template, sortOrder: index))
        }
        try? modelContext.save()
        refreshChordProgressionTemplates()
    }

    private func refreshChordProgressionTemplates() {
        let descriptor = FetchDescriptor<ChordProgressionTemplateRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        let records = (try? modelContext.fetch(descriptor)) ?? []
        chordProgressionTemplates = records.map(\.asChordProgressionTemplate)
    }

    /// Resolves every degree token in `template` against `mode` (see
    /// `RomanNumeralChord.rootAndQuality`) into a concrete `ChordReference` — tokens that
    /// fail to parse are silently skipped rather than failing the whole progression, since a
    /// hand-edited `chordprogressions.json` might contain a typo in one template without that
    /// making every OTHER template in the file unusable.
    public func resolveChordProgression(_ template: ChordProgressionTemplate, in mode: Mode) -> [ChordReference] {
        template.degrees.compactMap { token in
            guard let (root, quality) = RomanNumeralChord.rootAndQuality(for: token, in: mode) else { return nil }
            let templateID: String
            switch quality {
            case .major: templateID = "Ma"
            case .minor: templateID = "mi"
            case .diminished: templateID = "dim"
            }
            return ChordReference(root: root.value, chordTemplateID: templateID)
        }
    }

    // MARK: - Chord/scale library extensions (Chord & Mode Library, JSON-editable vocabulary)

    /// Chord qualities added on top of `ChordVocabulary.seed` via `chords.json` — empty until
    /// (and unless) that file exists and has content; the compiled-in seed needs no SwiftData
    /// round-trip at all, so this is purely the *extra* entries, not the whole catalog.
    public private(set) var extraChordTemplates: [ChordTemplate] = []

    /// One-time import of `chords.json` into SwiftData, then merges every stored entry into
    /// `ChordVocabulary` (see `ChordVocabulary.register(_:)`) — mirrors
    /// `migrateChordProgressionTemplatesFromJSONIfNeeded`'s shape, except there is no
    /// built-in-defaults fallback to seed: the compiled-in seed already lives in
    /// `ChordVocabulary.seed` independent of this store.
    public func migrateChordTemplatesFromJSONIfNeeded(fromJSONFile path: String) {
        refreshChordTemplates()
        guard extraChordTemplates.isEmpty else { return }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let file = try? JSONDecoder().decode(ChordTemplateFile.self, from: data), !file.chords.isEmpty
        else { return }
        for (index, template) in file.chords.enumerated() {
            modelContext.insert(ChordTemplateRecord(template, sortOrder: index))
        }
        try? modelContext.save()
        append("Migrated \(file.chords.count) chord template(s) from \(path) (original left in place).")
        refreshChordTemplates()
    }

    private func refreshChordTemplates() {
        let descriptor = FetchDescriptor<ChordTemplateRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        let records = (try? modelContext.fetch(descriptor)) ?? []
        extraChordTemplates = records.map(\.asChordTemplate)
        ChordVocabulary.register(extraChordTemplates)
    }

    /// Scale definitions added on top of `ScaleLibrary.all` via `scales.json` — see
    /// `extraChordTemplates`'s doc comment for the same "purely additive, no built-in-defaults
    /// fallback" rationale.
    public private(set) var extraScaleDefinitions: [ScaleDefinition] = []

    public func migrateScaleDefinitionsFromJSONIfNeeded(fromJSONFile path: String) {
        refreshScaleDefinitions()
        guard extraScaleDefinitions.isEmpty else { return }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let file = try? JSONDecoder().decode(ScaleDefinitionFile.self, from: data), !file.scales.isEmpty
        else { return }
        for (index, scale) in file.scales.enumerated() {
            modelContext.insert(ScaleDefinitionRecord(scale, sortOrder: index))
        }
        try? modelContext.save()
        append("Migrated \(file.scales.count) scale definition(s) from \(path) (original left in place).")
        refreshScaleDefinitions()
    }

    private func refreshScaleDefinitions() {
        let descriptor = FetchDescriptor<ScaleDefinitionRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        let records = (try? modelContext.fetch(descriptor)) ?? []
        extraScaleDefinitions = records.map(\.asScaleDefinition)
        ScaleLibrary.register(extraScaleDefinitions)
    }

    /// Sets one melodic track's instrument (a sample file name, resolved against
    /// `sampleFolder` at play time — see `resolvedInstrumentURLs`) within the current
    /// piece's `sectionIndex`-th section. Pass `nil`/empty to revert to the default sound.
    /// Doesn't persist by itself — follow with `save()`/`saveAs(_:)` to keep the change.
    public func setPieceTrackInstrument(sectionIndex: Int, trackIndex: Int, instrumentName: String?, preset: SoundFontPresetIdentity? = nil) throws {
        guard var piece else { throw SessionError.noPieceLoaded }
        guard piece.sections.indices.contains(sectionIndex) else { throw SessionError.invalidPieceSectionIndex }
        guard piece.sections[sectionIndex].tracks.indices.contains(trackIndex) else { throw SessionError.invalidPieceTrackIndex }
        piece.sections[sectionIndex].tracks[trackIndex].instrument = instrumentName ?? ""
        piece.sections[sectionIndex].tracks[trackIndex].instrumentPreset = instrumentName != nil ? preset : nil
        self.piece = piece
        append("Piste '\(piece.sections[sectionIndex].tracks[trackIndex].name)' (section '\(piece.sections[sectionIndex].name)') : instrument \(instrumentName.map { "'\($0)'" } ?? "par defaut").")
    }

    /// Sets a section's chord-progression instrument — the harmonic-accompaniment
    /// counterpart to `setPieceTrackInstrument`, since chords have no track of their own.
    public func setPieceChordInstrument(sectionIndex: Int, instrumentName: String?, preset: SoundFontPresetIdentity? = nil) throws {
        guard var piece else { throw SessionError.noPieceLoaded }
        guard piece.sections.indices.contains(sectionIndex) else { throw SessionError.invalidPieceSectionIndex }
        piece.sections[sectionIndex].chordInstrument = instrumentName
        piece.sections[sectionIndex].chordInstrumentPreset = instrumentName != nil ? preset : nil
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

    /// Stops the current piece playback early — the "Arreter" button's counterpart to
    /// letting it finish on its own. Bumps `playbackGeneration` (invalidating every already-
    /// scheduled note-on/off/chord-index closure from the current `play()` call, same
    /// mechanism `play()` itself relies on) and asks `player` to immediately silence
    /// whatever it might currently have sounding. A no-op if nothing is playing.
    public func stopPlayback() {
        guard isPlaying else { return }
        playbackGeneration += 1
        player.stopAllNotes()
        isPlaying = false
        playbackHeldPitches = []
        playbackCurrentChordIndex = nil
        append("Lecture arretee.")
    }

    /// Resolves every distinct `RenderedNote.instrumentName` used by `notes` to an actual
    /// sample file in `sampleFolder` (same folder/lookup `use-sample`/`loadSample(named:)`
    /// already use for the piece-playback default sound) — a name with no matching file is
    /// simply left out, letting `PiecePlayer.play` fall back to (and warn about) its
    /// per-instrument default sound instead.
    private func resolvedInstrumentURLs(for notes: [RenderedNote]) -> [String: URL] {
        var result: [String: URL] = [:]
        for name in Set(notes.compactMap(\.instrumentName)) {
            guard let url = try? resolvedSampleURL(named: name), FileManager.default.fileExists(atPath: url.path) else { continue }
            result[name] = url
        }
        return result
    }

    public func availableMIDISources() -> [String] {
        MIDIInputListener.sourceNames()
    }

    /// Same visible MIDI sources as `availableMIDISources()`, but identity-bearing — needed to
    /// look up/assign a per-device icon (see `midiDeviceIcon(uniqueID:displayName:)`), which
    /// `TrackInfo`/a bare name alone can't key reliably (same reasoning `InstrumentIdentityHint
    /// .midiPort` already documents). A plain tuple rather than re-exposing `MIDIEngine`'s own
    /// `MIDISourceDescriptor` type, so App-target code needs no direct dependency on `MIDIEngine`
    /// just to read a device's name/id.
    public func availableMIDISourceDescriptors() -> [(name: String, uniqueID: Int32?)] {
        MIDIInputListener.sourceDescriptors().map { (name: $0.displayName, uniqueID: $0.uniqueID) }
    }

    /// The icon assigned to a MIDI device, if any — matched by `uniqueID` when the device
    /// reports one (the reliable case), else by `displayName` (see `MIDIDeviceIconRecord`'s own
    /// doc comment for why this needs its own small registry, unlike the other 3 icon kinds).
    public func midiDeviceIcon(uniqueID: Int32?, displayName: String) -> String? {
        let records = (try? modelContext.fetch(FetchDescriptor<MIDIDeviceIconRecord>())) ?? []
        if let uniqueID, let match = records.first(where: { $0.midiUniqueID == uniqueID }) {
            return match.iconSystemName
        }
        return records.first(where: { $0.midiUniqueID == nil && $0.displayName == displayName })?.iconSystemName
    }

    /// Sets (upserts) a MIDI device's icon and persists.
    public func setMIDIDeviceIcon(uniqueID: Int32?, displayName: String, iconSystemName: String) throws {
        let records = (try? modelContext.fetch(FetchDescriptor<MIDIDeviceIconRecord>())) ?? []
        let existing: MIDIDeviceIconRecord? = {
            if let uniqueID { return records.first { $0.midiUniqueID == uniqueID } }
            return records.first { $0.midiUniqueID == nil && $0.displayName == displayName }
        }()
        if let existing {
            existing.iconSystemName = iconSystemName
            existing.displayName = displayName
        } else {
            modelContext.insert(MIDIDeviceIconRecord(midiUniqueID: uniqueID, displayName: displayName, iconSystemName: iconSystemName))
        }
        try modelContext.save()
        append("Icone de clavier MIDI mise a jour : \(displayName).")
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

    /// Turns physical-computer-keyboard note input on/off — see `computerKeyboardInputEnabled`'s
    /// own doc comment for why it defaults off. Purely a UI-facing switch: it doesn't touch
    /// `.computerKeyboard`'s own listening/sound state (unrelated — that track can be listening
    /// today, e.g. showing held-note display from a scene, regardless of whether typing on the
    /// physical keyboard is what's feeding it).
    public func setComputerKeyboardInputEnabled(_ enabled: Bool) {
        computerKeyboardInputEnabled = enabled
        append("Clavier ordinateur : \(enabled ? "actif" : "inactif").")
    }

    /// Bumped by `requestComputerKeyboardFocus()` — `ContentView` observes this (via
    /// `onChange`) to reclaim actual SwiftUI keyboard focus for computer-keyboard note capture.
    /// Exists because a native `Picker`/`Menu` (e.g. the Sounds tab's test-source picker, or a
    /// Scene role's sound menu) keeps SwiftUI keyboard focus once used, with nothing else to
    /// hand it back — the reported symptom this fixes: after reassigning a role's sound in the
    /// Scene tab, typing stopped producing notes even though computer-keyboard input was on.
    public private(set) var computerKeyboardFocusRequestToken = 0

    /// Call after any interaction with a native pop-up control (`Picker`/`Menu`) that the user
    /// would reasonably expect to be followed by typing/playing again.
    public func requestComputerKeyboardFocus() {
        computerKeyboardFocusRequestToken += 1
    }

    /// Semitone offset applied to every `JamShackUI.computerKeyboardNoteMap` pitch — lets the
    /// mapped "ASDFGHJKL;"/"WE_TYU_OP" keys be moved up/down by whole octaves (12 semitones per
    /// step) so the active zone can be shifted to match a different register without changing
    /// which physical keys are used. Session-only (not persisted), default 0 — no shift, exactly
    /// `computerKeyboardNoteMap`'s own pitches (60...76).
    public private(set) var computerKeyboardOctaveShift = 0

    public func shiftComputerKeyboardOctave(by steps: Int) {
        computerKeyboardOctaveShift += steps * 12
    }

    /// Rebuilds `tracks` from `midiFusionMode` and the currently-visible MIDI sources,
    /// preserving every surviving track's listening/sound/recognition state by identity
    /// (`TrackID`) — called at `init` and after `setMIDIFusionMode`, and exposed as the
    /// `tracks` command so a newly plugged-in MIDI device can be picked up on demand (this
    /// app doesn't watch for CoreMIDI hot-plug notifications).
    public func refreshTracks() {
        // Real bug reproduced under stress (concurrent `refreshTracks()` + live note traffic:
        // "Object ... deallocated with non-zero retain count", a genuine memory-corrupting data
        // race): every mutation `handleIncomingMIDIEvent` makes to `tracks` goes through
        // `liveInputQueue.sync` (see that function's own doc comment), but this function used
        // to read/write `tracks` completely unguarded — reachable any time the user hits
        // "Rafraichir" (or changes MIDI fusion mode) while a MIDI device is actively being
        // played, which fires on its own CoreMIDI callback thread, not the main thread. Wrapping
        // the whole body is safe from self-deadlock: `preservedOrNewTrack`/
        // `refreshPassiveChannelSniffers`/`reconcileSceneAttachmentsAfterTrackRefresh` never
        // call `liveInputQueue.sync` themselves.
        liveInputQueue.sync {
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
            // `.webKeyboard(clientID:)` tracks are NOT recreated here — unlike every other kind,
            // they're dynamic and per-browser (see `ensureWebKeyboardTrack`), so this would
            // either need a fixed clientID (defeating the point) or drop every connected
            // browser's track on every `refreshTracks()` call (e.g. after `midi-mode`). Existing
            // ones are preserved below, just never freshly created here. `.remote` tracks get the
            // exact same treatment, for the exact same reason — they're owned by the network
            // layer (`addOrUpdateRemoteTrack`/`mergeRemoteSnapshot`), not by this function; before
            // this line existed, calling `refreshTracks()` (e.g. via the `tracks`/`scene-tree`
            // commands, or `midi-mode`) silently wiped every OTHER participant's known
            // instruments until they next announced a track or played a note.
            updated.append(contentsOf: tracks.filter { track in
                switch track.id {
                case .webKeyboard, .remote: return true
                default: return false
                }
            })
            updated.append(preservedOrNewTrack(.microphone, label: "Microphone", canHaveSound: false))
            tracks = updated
            refreshPassiveChannelSniffers()
            reconcileSceneAttachmentsAfterTrackRefresh()
        }
    }

    /// Tears down every existing passive sniffer and reconnects one per currently-visible
    /// MIDI source — see `passiveChannelSniffers`'s doc comment. A fresh, disposable
    /// `MIDIInputListener`/CoreMIDI client per source is simpler than teaching that class to
    /// tell several connected sources apart on one shared port (it doesn't track source
    /// identity per packet today), and there are only ever a handful of MIDI sources in
    /// practice — the extra CoreMIDI clients this creates are not a real cost here.
    private func refreshPassiveChannelSniffers() {
        passiveChannelSniffers.removeAll()
        for index in 0..<availableMIDISources().count {
            let handler: MIDIInputListener.Handler = { [weak self] event in
                guard let self else { return }
                self.passiveChannelQueue.async { self.passiveObservedChannels[index] = event.channel }
            }
            guard let listener = try? MIDIInputListener(clientName: "MusicImprovAssistant-ChannelSniffer", handler: handler) else { continue }
            listener.connectSource(atIndex: index)
            passiveChannelSniffers[index] = listener
        }
    }

    /// The last MIDI channel (0...15) observed on the source at `index` in
    /// `availableMIDISources()`'s order — regardless of whether the corresponding
    /// `.midiSource(index)` track is actually being listened to. `nil` until at least one
    /// message has arrived from it since the last `refreshTracks()`/`refreshPassiveChannelSniffers()`.
    public func observedChannel(forMIDISourceIndex index: Int) -> Int? {
        passiveChannelQueue.sync { passiveObservedChannels[index] }
    }

    /// The MIDI channel to show for `track` — the real, actually-observed-through-listening
    /// value if there is one (`TrackInfo.lastChannel`), else the passive sniffer's own
    /// observation (`observedChannel(forMIDISourceIndex:)`) for a `.midiSource` track;
    /// `nil` for anything else, including `.midiMerged`, which has no single physical source
    /// of its own to sniff. Shared by every UI that lists/labels a MIDI-capable track (the
    /// CLI's own `printTracks`, the SwiftUI app's role/instrument pickers) so they can't
    /// silently drift onto two different notions of "this track's channel."
    public func displayedChannel(for track: TrackInfo) -> Int? {
        // `lastChannel` is set by `updateRecognitionState` for ANY track, not just MIDI ones —
        // `pressKey`/`releaseKey` (the computer keyboard's own input path) default `channel` to
        // 0, which used to make this function report "canal 1" for the computer keyboard the
        // moment a single key was typed, even though it was never a MIDI device to begin with.
        guard isMIDITrack(track.id) else { return nil }
        if let channel = track.lastChannel { return channel }
        guard case .midiSource(let index) = track.id else { return nil }
        return observedChannel(forMIDISourceIndex: index)
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
        case .computerKeyboard, .webKeyboard, .microphone, .remote: return false
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
        case .computerKeyboard, .webKeyboard:
            break
        case .microphone:
            let mode = tracks[index].microphoneRecognitionMode
            let newListener = MicrophonePitchListener(
                strategy: Self.analysisStrategy(for: mode),
                handler: { [weak self] detected, level in
                    self?.handleDetectedPitches(detected, level: level, track: id)
                },
                spectrumHandler: { [weak self] magnitudes, binHz in
                    self?.storeMicrophoneSpectrum(magnitudes: magnitudes, binHz: binHz)
                }
            )
            newListener.spectrumEnabled = microphoneSpectrumCaptureEnabled
            try newListener.start()
            microphoneListener = newListener
            pitchStabilizers[id] = MicrophonePitchStabilizer(policy: Self.stabilizerPolicy(for: mode))
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
        case .computerKeyboard, .webKeyboard:
            break
        case .microphone:
            microphoneListener?.stop()
            microphoneListener = nil
            pitchStabilizers[id] = nil
        }
        liveInputQueue.sync {
            recognizers[id]?.reset()
            tracks[index].heldPitches = []
            tracks[index].recognizedChord = nil
            tracks[index].recognizedModes = []
            tracks[index].lastDetectedPitches = []
            tracks[index].microphoneInputLevel = 0
        }
        recentChordEvents[id] = nil
        tracks[index].isListening = false
        append("Piste '\(tracks[index].label)' : ecoute arretee.")
        unannounceTrackToServerIfClient(id)
    }

    #if os(macOS)
    /// A real General MIDI instrument bank macOS ships as part of `CoreAudio.component` itself —
    /// no bundled asset, no user import needed. Used as a nicer-than-silence/sine-synth default
    /// the moment a track's sound is enabled with no instrument explicitly chosen yet (see
    /// `setSoundEnabled(_:for:)`). Undocumented Apple implementation detail, not a published API
    /// path — guarded by `FileManager.fileExists` and loaded `try?`, so its absence on some
    /// future OS version just silently falls back to `AVAudioUnitSampler`'s own built-in sine
    /// synth, same as today. No iOS equivalent is exposed to a sandboxed app, so this stays
    /// macOS-only (see backlog point 18 for a real cross-platform default-sound story).
    private static let systemDefaultInstrumentURL = URL(fileURLWithPath:
        "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
    #endif

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
                #if os(macOS)
                if FileManager.default.fileExists(atPath: Self.systemDefaultInstrumentURL.path) {
                    try? unit.loadSample(at: Self.systemDefaultInstrumentURL)
                }
                #endif
                samplers[id] = unit
            }
        } else {
            samplers[id]?.stop()
        }
        tracks[index].soundEnabled = enabled
        append("Piste '\(tracks[index].label)' : son \(enabled ? "active" : "desactive").")
    }

    /// Resolves a sound "name" to a real file URL — either an absolute path (what
    /// `soundFontPath(forHash:)`/`favoriteSounds` hand back now, since a soundfont's real
    /// location lives under `SoundFontLocations`, not `sampleFolder`) or, unchanged, a path
    /// relative to `sampleFolder` (the CLI's own long-standing convention — see
    /// `listSampleFiles`). Every sample-loading entry point in this class accepts either shape
    /// through this one helper, so a hash-resolved favorite and a CLI-relative name both work
    /// with the exact same calls.
    private func resolvedSampleURL(named name: String) throws -> URL {
        if (name as NSString).isAbsolutePath {
            return URL(fileURLWithPath: name)
        }
        guard let sampleFolder else { throw SessionError.noSampleFolderListed }
        return URL(fileURLWithPath: sampleFolder).appendingPathComponent(name)
    }

    /// Loads a sample-based instrument by name from `sampleFolder` (see `listSampleFiles`)
    /// onto one track's own sampler, enabling its sound if it wasn't already — each track
    /// can carry a different instrument, sounding at the same time as any other track's.
    public func setInstrument(named name: String, for id: TrackID, preset: SoundFontPresetIdentity? = nil) throws {
        let index = try trackIndex(id)
        guard tracks[index].canHaveSound else { throw SessionError.trackCannotHaveSound }
        let url = try resolvedSampleURL(named: name)
        let unit: SamplerUnit
        if let existing = samplers[id] {
            unit = existing
        } else {
            unit = SamplerUnit()
            samplers[id] = unit
        }
        // Always (re)start, not just for a freshly-created unit — reusing an EXISTING
        // `SamplerUnit` whose engine was previously stopped (via `setSoundEnabled(false, ...)`,
        // e.g. a muted-but-remembered role) without this would leave `startNote` a silent
        // no-op forever: real bug reproduced and confirmed in isolation (a stopped
        // `AVAudioEngine` makes `AVAudioUnitSampler.startNote` produce zero audio, no error),
        // matching a track reporting `soundEnabled=true` + sampler present + startNote called,
        // yet totally silent. `SamplerUnit.start()` is safe to call on an already-running engine.
        try unit.start()
        try unit.loadSample(at: url, preset: preset)
        tracks[index].soundEnabled = true
        tracks[index].instrumentName = name
        tracks[index].instrumentPreset = preset
        append("Piste '\(tracks[index].label)' : instrument '\(name)' charge, son active.")
    }

    /// The presets bundled inside a multi-preset `.sf2` file (see `SoundFontPresetReader`) —
    /// `path` is relative to `sampleFolder`, same convention as `sampleFiles`. Throws whatever
    /// the reader throws for anything that isn't a `.sf2` shaped like one (a `.dls`/`.aupreset`,
    /// or a `.sf2` the reader can't parse) — callers should treat that the same as "just the
    /// file's own single default sound," same as before multi-preset support existed.
    public func soundFontPresets(forPath path: String) throws -> [SoundFontPreset] {
        try SoundFontPresetReader.presets(at: resolvedSampleURL(named: path))
    }

    /// Convenience over `setInstrument(named:for:)` using the 0-based position in `sampleFiles`.
    public func setInstrument(atIndex sampleIndex: Int, for id: TrackID, preset: SoundFontPresetIdentity? = nil) throws {
        guard sampleFiles.indices.contains(sampleIndex) else { throw SessionError.invalidSampleIndex }
        try setInstrument(named: sampleFiles[sampleIndex], for: id, preset: preset)
    }

    /// Changes how the microphone track turns raw FFT detections into confirmed notes — see
    /// `MicrophoneRecognitionMode`. Only valid for `.microphone` (meaningless for any other
    /// track kind). If the track is currently listening, restarts it (stop then start) so the
    /// new mode takes effect immediately rather than only on the next manual restart — a
    /// brief, one-time input gap, acceptable since permission is already granted so there's no
    /// re-prompt.
    public func setMicrophoneRecognitionMode(_ mode: MicrophoneRecognitionMode, for id: TrackID) throws {
        let index = try trackIndex(id)
        guard id == .microphone else { throw SessionError.recognitionModeOnlyForMicrophone }
        switch mode {
        case .polyphonicLatched(let windows) where windows < 1, .polyphonicSliding(let windows) where windows < 1:
            throw SessionError.invalidRecognitionWindowCount
        default:
            break
        }
        let wasListening = tracks[index].isListening
        if wasListening { stopTrack(id) }
        tracks[index].microphoneRecognitionMode = mode
        if wasListening { try startTrack(id) }
        append("Piste '\(tracks[index].label)' : mode de reconnaissance -> \(Self.describe(mode)).")
    }

    /// Maps a user-facing `MicrophoneRecognitionMode` to the `AnalysisStrategy` that decides
    /// which `FFTPitchAnalyzer` method runs per window — see that enum's own doc comment for
    /// why the two polyphonic modes share one strategy.
    private static func analysisStrategy(for mode: MicrophoneRecognitionMode) -> AnalysisStrategy {
        switch mode {
        case .monophonicHeuristic: return .monophonicHeuristic
        case .monophonicHPS: return .monophonicHPS
        case .polyphonicLatched, .polyphonicSliding: return .polyphonic(maxPeaks: 6)
        }
    }

    /// Maps a user-facing `MicrophoneRecognitionMode` to the temporal-smoothing `Policy` run
    /// by that track's `MicrophonePitchStabilizer` — `.passthrough` for both monophonic modes,
    /// since their fix is spectral (in `AnalysisStrategy`/`FFTPitchAnalyzer`), not temporal.
    private static func stabilizerPolicy(for mode: MicrophoneRecognitionMode) -> MicrophonePitchStabilizer.Policy {
        switch mode {
        case .monophonicHeuristic, .monophonicHPS: return .passthrough
        case .polyphonicLatched(let windows): return .latched(windows: windows)
        case .polyphonicSliding(let windows): return .sliding(windows: windows)
        }
    }

    /// French display text for a recognition mode — used in the log line above and in the
    /// terminal/web status displays.
    private static func describe(_ mode: MicrophoneRecognitionMode) -> String {
        switch mode {
        case .monophonicHeuristic: return "monophonique (heuristique)"
        case .monophonicHPS: return "monophonique (HPS)"
        case .polyphonicLatched(let windows): return "polyphonique verrouille (N=\(windows))"
        case .polyphonicSliding(let windows): return "polyphonique glissant (K=\(windows))"
        }
    }

    private static let supportedSampleExtensions: Set<String> = ["sf2", "dls", "aupreset"]

    /// Scans `folderPath` **and every subfolder beneath it** for `.sf2`/`.dls`/`.aupreset`
    /// files and remembers both the folder and the match list (in `sampleFiles`) so they can
    /// be picked by index afterwards. Recursive so a whole decompressed sound library (its own
    /// subfolder of many .sf2 files) can simply be unzipped straight into this folder — each
    /// entry in `sampleFiles` is a path *relative* to `folderPath` (e.g.
    /// `"OrchestralLib/Strings/Violin.sf2"`), not a bare filename, so files with the same name
    /// in different subfolders stay distinguishable and `appendingPathComponent` in
    /// `loadSample(named:)`/`setInstrument(named:for:)`/etc. still resolves them correctly.
    public func listSampleFiles(in folderPath: String) throws {
        // `subpathsOfDirectory(atPath:)` already returns paths *relative to `folderPath`*
        // (including subfolders) as plain strings — unlike `FileManager.enumerator(at:)`,
        // there's no symlink-resolution mismatch to worry about between the base folder URL
        // and the enumerated file URLs (e.g. `NSTemporaryDirectory()`'s `/var/folders/...` vs.
        // its resolved `/private/var/folders/...`, hit while testing this).
        let contents = try FileManager.default.subpathsOfDirectory(atPath: folderPath)
        sampleFolder = folderPath
        sampleFiles = contents
            .filter { Self.supportedSampleExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
        append(sampleFiles.isEmpty
            ? "No .sf2/.dls/.aupreset files found in \(folderPath) (including subfolders)."
            : "Found \(sampleFiles.count) sample file(s) in \(folderPath) (including subfolders).")
    }

    /// Every soundfont hash `refreshSoundFonts` has ever seen this session — lets it tell "a
    /// soundfont that just newly appeared in the index" (worth running the download policy for
    /// once) apart from "a soundfont that was already here and simply hasn't been downloaded by
    /// choice" (never re-runs the policy on it every single refresh).
    @ObservationIgnored private var soundFontHashesEverSeen: Set<String> = []

    /// Re-reads `soundFonts` from `modelContext` — mirrors `refreshSoundEntries`, called after
    /// every `SoundFontLibrary` reconciliation/import so the in-memory list never drifts from
    /// what's actually indexed. Also runs `SoundFontDownloadPolicy` once for each soundfont
    /// newly seen this session (e.g. a synced entry discovered by `NSMetadataQuery` on another
    /// device's import) — see `applyDownloadPolicyIfNeeded(forHash:)`.
    private func refreshSoundFonts() {
        soundFonts = ((try? modelContext.fetch(FetchDescriptor<SoundFontRecord>())) ?? []).compactMap(\.asSoundFontEntry)
        let newlySeenHashes = Set(soundFonts.map(\.hash)).subtracting(soundFontHashesEverSeen)
        soundFontHashesEverSeen.formUnion(newlySeenHashes)
        for hash in newlySeenHashes {
            applyDownloadPolicyIfNeeded(forHash: hash)
        }
    }

    /// Runs `SoundFontDownloadPolicy` for one `.synced` soundfont not yet materialized on this
    /// device, downloading it immediately if the policy says `.autoDownload` — the `.askUser`
    /// and `.metadataOnly` outcomes are left for the UI to surface (see
    /// `downloadDecision(forHash:)`), never acted on automatically here.
    private func applyDownloadPolicyIfNeeded(forHash hash: String) {
        guard let entry = soundFonts.first(where: { $0.hash == hash }),
              entry.syncPreference == .synced, soundFontPath(forHash: hash) == nil else { return }
        if downloadDecision(for: entry) == .autoDownload {
            try? soundFontLibrary.requestDownload(of: entry)
        }
    }

    /// What `SoundFontDownloadPolicy` recommends for `entry` on THIS device right now — exposed
    /// so a UI (see `SoundsView`) can show an appropriate prompt/badge for the `.askUser`/
    /// `.metadataOnly` outcomes `applyDownloadPolicyIfNeeded` deliberately doesn't act on by
    /// itself.
    public func downloadDecision(for entry: SoundFontEntry) -> SoundFontLocalDownloadDecision {
        SoundFontDownloadPolicy.decide(
            fileSize: entry.fileSize,
            currentFreeSpace: DeviceFreeSpace.availableBytes(),
            profile: DeviceStorageProfile.current,
            isFavorite: soundEntries.contains { $0.soundFontHash == entry.hash && $0.isFavorite },
            recentlyUsedOnThisDevice: SoundFontLocalUsageLedger.wasUsedRecently(entry.hash)
        )
    }

    /// Explicitly requests download of a `.synced` soundfont not yet materialized on this
    /// device — the manual counterpart to `applyDownloadPolicyIfNeeded`'s automatic path, for
    /// the `.askUser`/`.metadataOnly` cases the user chooses to act on anyway (e.g. a "Download"
    /// button in `SoundsView`).
    public func downloadSoundFont(hash: String) throws {
        guard let entry = soundFonts.first(where: { $0.hash == hash }) else { return }
        try soundFontLibrary.requestDownload(of: entry)
    }

    /// Deletes a soundfont entirely (see `SoundFontLibrary.delete(hash:)` for what that means
    /// for a `.synced` entry — every device, not just this one) and any favorite/alias entries
    /// that referenced it, which would otherwise be orphaned (unreachable — `soundEntries`
    /// already can't resolve a hash `soundFonts` no longer lists — but never cleaned up).
    public func deleteSoundFont(hash: String) {
        guard soundFontLibrary.delete(hash: hash) != nil else { return }
        let orphanedEntries = (try? modelContext.fetch(FetchDescriptor<SoundEntryRecord>())) ?? []
        for record in orphanedEntries where record.soundFontHash == hash {
            modelContext.delete(record)
        }
        try? modelContext.save()
        refreshSoundFonts()
        refreshSoundEntries()
    }

    /// Wipes the ENTIRE soundfont library — every index record, every `.sf2`/`.dls` file this
    /// device can see (local-only folder AND the app's iCloud Drive container, the latter
    /// removing them from every device signed into the account), and every favorite/alias that
    /// referenced any of them. A deliberate, explicit, user-requested nuke-and-pave — see
    /// `SoundFontLibrary.wipeEverything()`'s own doc comment for when this is the right call
    /// (recovering from cross-device duplicate-hash corruption a plain `deduplicate()` pass
    /// can't retroactively fix once the user has already acted on the corrupted state, e.g.
    /// deleted/toggled the "wrong" one of two duplicate rows).
    public func wipeSoundFontLibrary() {
        soundFontLibrary.wipeEverything()
        let allSoundEntries = (try? modelContext.fetch(FetchDescriptor<SoundEntryRecord>())) ?? []
        for record in allSoundEntries {
            modelContext.delete(record)
        }
        try? modelContext.save()
        refreshSoundFonts()
        refreshSoundEntries()
        append("Soundfont library wiped: every soundfont file and favorite/alias removed (local and synced).")
    }

    /// Moves an already-imported soundfont between synced (iCloud Drive, every device) and
    /// local-only (this device alone) — see `SoundFontLibrary.changeSyncPreference(hash:to:)`
    /// for exactly what that means physically. Throws `SoundFontLibraryError
    /// .notDownloadedOnThisDevice` if the file isn't actually present here right now (a
    /// `.synced` entry not yet downloaded) — download it first (`downloadSoundFont(hash:)`).
    @discardableResult
    public func setSoundFontSyncPreference(hash: String, to preference: SoundFontSyncPreference) throws -> SoundFontEntry {
        let entry = try soundFontLibrary.changeSyncPreference(hash: hash, to: preference)
        refreshSoundFonts()
        return entry
    }

    /// The user's own self-imposed iCloud storage budget for synced soundfonts, in bytes — see
    /// `CloudStorageThresholdRecord`'s own doc comment for why this is synced (account-wide,
    /// not per-device) rather than a `UserDefaults` setting like `DeviceStorageProfile`/
    /// `LocalStorageThreshold`. `nil` until ever set.
    public private(set) var cloudStorageThresholdBytes: Int64?

    private func refreshCloudStorageThreshold() {
        cloudStorageThresholdBytes = (try? modelContext.fetch(FetchDescriptor<CloudStorageThresholdRecord>()))?.first?.bytes
    }

    public func setCloudStorageThresholdBytes(_ bytes: Int64?) throws {
        if let existing = try modelContext.fetch(FetchDescriptor<CloudStorageThresholdRecord>()).first {
            existing.bytes = bytes
        } else {
            modelContext.insert(CloudStorageThresholdRecord(bytes: bytes))
        }
        try modelContext.save()
        cloudStorageThresholdBytes = bytes
    }

    /// Starts the soundfont library's `NSMetadataQuery`-backed discovery for both physical
    /// folders (see `SoundFontLocations`) — call once at launch, BEFORE
    /// `migrateSoundFontsFromFolderScanIfNeeded` (which needs `soundFontLibrary`'s folders
    /// already resolved to copy non-synced files into). `syncedFolderURLIfAvailable()` returning
    /// `nil` (no iCloud account, or this build isn't signed with the ubiquity-container
    /// capability) just means every soundfont behaves as local-only for now — never a hard
    /// failure.
    public func startSoundFontLibrary() {
        startSoundFontLibrary(
            syncedFolder: SoundFontLocations.syncedFolderURLIfAvailable(),
            localFolder: SoundFontLocations.localFolderURL()
        )
    }

    /// Same as `startSoundFontLibrary()` but with explicit folder overrides instead of
    /// resolving `SoundFontLocations` (which always points at real, non-sandboxed system
    /// locations — the real `Application Support`, the real iCloud Drive container) — lets
    /// tests exercise the whole soundfont pipeline against an isolated temp directory instead.
    public func startSoundFontLibrary(syncedFolder: URL?, localFolder: URL) {
        refreshSoundFonts()
        refreshCloudStorageThreshold()
        soundFontLibrary.start(syncedFolder: syncedFolder, localFolder: localFolder, onChange: { [weak self] in self?.refreshSoundFonts() })
    }

    /// One-time bridge from the old folder-scan-based soundfont storage (`sampleFolder`/
    /// `sampleFiles`, still how the CLI itself works) to the hash-indexed `soundFonts` store —
    /// mirrors `migrateSoundSettingsFromJSONIfNeeded`'s "only if the store is still empty"
    /// guard. Must run AFTER `startSoundFontLibrary` (which resolves the physical folders this
    /// copies non-synced files into). Files already sitting under the app's own iCloud Drive
    /// container (a common case: many users already pointed their JamShack root there) are
    /// indexed in place with no copy; everything else is copied into the local-only folder as a
    /// safe default (never guesses a user's iCloud quota tolerance — see `SoundFontStorage`'s
    /// adaptive policy for what decides sync preference for anything imported after this
    /// one-time migration).
    public func migrateSoundFontsFromFolderScanIfNeeded(in oldSampleFolderPath: String) {
        refreshSoundFonts()
        guard soundFonts.isEmpty else { return }
        guard let contents = try? FileManager.default.subpathsOfDirectory(atPath: oldSampleFolderPath) else { return }
        let files = contents.filter { Self.supportedSampleExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        guard !files.isEmpty else { return }

        let syncedFolder = soundFontLibrary.syncedFolder
        let oldRoot = URL(fileURLWithPath: oldSampleFolderPath).standardizedFileURL
        var migratedCount = 0
        for relativePath in files {
            let sourceURL = oldRoot.appendingPathComponent(relativePath)
            let alreadyUnderSyncedFolder = syncedFolder.map { sourceURL.path.hasPrefix($0.standardizedFileURL.path) } ?? false
            do {
                if alreadyUnderSyncedFolder {
                    let presets = (try? SoundFontPresetReader.presets(at: sourceURL)) ?? []
                    let hash = try SoundFontHasher.sha256Hex(ofFileAt: sourceURL)
                    let size = ((try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size]) as? NSNumber)?.int64Value ?? 0
                    let entry = SoundFontEntry(
                        hash: hash, displayName: sourceURL.lastPathComponent, fileName: sourceURL.lastPathComponent,
                        fileSize: size, presets: presets, dateAdded: Date(), syncPreference: .synced
                    )
                    // Check for an existing record by hash FIRST (same as `SoundFontLibrary
                    // .upsert`, which every other insertion path already goes through) — this
                    // branch used to insert unconditionally, which was the actual root cause of
                    // real duplicate-hash corruption: two devices, each with the JamShack root
                    // already pointed at (or containing) the synced folder, could both run this
                    // one-time migration before CloudKit's own index sync had caught up between
                    // them (the `soundFonts.isEmpty` guard above only checks what THIS device
                    // has pulled down so far, not what actually exists elsewhere), each creating
                    // its own separate row for the exact same file. CloudKit then dutifully
                    // synced BOTH rows forever after, with no way to tell they were the same
                    // soundfont — exactly the "two devices show different synced files, deletes
                    // behave strangely" bug reported. See `SoundFontLibrary.deduplicate()` for
                    // the one-time cleanup of rows already corrupted this way.
                    if let existingRecord = try? modelContext.fetch(
                        FetchDescriptor<SoundFontRecord>(predicate: #Predicate<SoundFontRecord> { $0.contentHash == hash })
                    ).first {
                        existingRecord.update(from: entry)
                    } else {
                        modelContext.insert(SoundFontRecord(entry))
                    }
                } else {
                    try soundFontLibrary.importFile(at: sourceURL, destination: .localOnly)
                }
                migratedCount += 1
            } catch {
                append("Could not migrate soundfont '\(relativePath)' from folder scan: \(error).")
            }
        }
        try? modelContext.save()
        refreshSoundFonts()
        append("Migrated \(migratedCount) soundfont(s) from folder scan at \(oldSampleFolderPath) (original files left in place).")
    }

    /// Imports a soundfont file the user picked explicitly (`.fileImporter`, drag & drop — see
    /// `SoundsView`), copying+hashing it into the chosen physical location and adding it to the
    /// index. See `SoundFontLibrary.importFile`.
    @discardableResult
    public func importSoundFont(
        at url: URL, syncPreference: SoundFontSyncPreference, displayName: String? = nil, origin: SoundFontOrigin = .userImported
    ) throws -> SoundFontEntry {
        let entry = try soundFontLibrary.importFile(at: url, destination: syncPreference, displayName: displayName, origin: origin)
        refreshSoundFonts()
        return entry
    }

    /// Downloads one of the app's own "offered" soundfonts (see `CuratedSoundFontCatalog`) and
    /// imports it through the exact same path as a user-picked file — `origin: .curated` is the
    /// only difference, letting a future re-download button work if the local copy ever
    /// disappears (the reconciliation in `SoundFontLibrary` never prunes a `.curated` entry just
    /// because its file is temporarily missing). Always imported `.localOnly`: nothing about an
    /// offered soundfont implies the user wants to spend their own iCloud quota syncing it —
    /// sharing it afterward is the same one-tap "Partagé" toggle as any other soundfont.
    ///
    /// Verifies the freshly-imported file's own hash (computed by `importFile` itself while
    /// copying it into place) against `entry.sha256` — the catalog's pinned expectation from
    /// curation time. A mismatch means either a corrupted transfer or the origin silently
    /// replacing the file at that URL since curation; either way the newly-created record and
    /// file are rolled back and `.integrityCheckFailed` is thrown rather than ever indexing a
    /// bank that doesn't match what was promised. Because the catalog itself is embedded in the
    /// app binary (see `CuratedSoundFontCatalog`'s own doc comment), a mismatch that turns out to be a
    /// genuinely-updated origin file can't self-heal here — it needs a new catalog entry
    /// (new `sha256`/`version`) shipped in a future app release.
    ///
    /// The only `async` entry point on this class — deliberately isolated to this one feature
    /// rather than making the rest of `ImprovSession` `async` too (see `modelContext`'s own doc
    /// comment for why the class otherwise stays synchronous). `CuratedSoundFontCatalog.download`
    /// is itself genuinely non-blocking (delegate + continuation, no thread-blocking wait — an
    /// earlier semaphore-based version froze the whole UI, main thread included, for the
    /// download's entire duration when called from a plain, non-detached `Task`, since such a
    /// `Task` inherits its creator's actor and a blocking call on it blocks that actor's real
    /// thread). Awaiting it here resumes the rest of this function back on whatever actor called
    /// `installCuratedSoundFont` in the first place (same "await resumes on the awaiting
    /// context's actor" rule this codebase already relies on for `Task { await Task.yield(); … }`
    /// elsewhere) — which is what makes it safe for `importSoundFont` below to touch
    /// `modelContext` right after. `onProgress` is called on the main actor as the transfer
    /// progresses (see `CuratedSoundFontCatalog.download`'s own doc comment) — a no-op default
    /// for callers (tests, a future CLI) that don't need progress UI.
    @discardableResult
    public func installCuratedSoundFont(
        _ entry: SoundFontCatalogEntry, onProgress: @escaping @MainActor (Double) -> Void = { _ in }
    ) async throws -> SoundFontEntry {
        let downloadedURL = try await CuratedSoundFontCatalog.download(entry, onProgress: onProgress)
        defer { try? FileManager.default.removeItem(at: downloadedURL) }
        let installed = try importSoundFont(
            at: downloadedURL, syncPreference: .localOnly, displayName: entry.displayName,
            origin: .curated(sourceURL: entry.downloadURL, catalogEntryId: entry.id, catalogVersion: entry.version)
        )
        guard installed.hash.caseInsensitiveCompare(entry.sha256) == .orderedSame else {
            deleteSoundFont(hash: installed.hash)
            throw CuratedSoundFontCatalogError.integrityCheckFailed
        }
        return installed
    }

    /// Every installed `.curated` soundfont whose catalog entry has since moved to a newer
    /// `version` than what was installed — the "update available" signal from
    /// `KnowledgeBase/SoundfontMgt/SPEC-catalogue-soundfonts.md` §9. Comparison is purely by
    /// `id`+`version` string equality (no semantic version parsing): the catalog is embedded in
    /// the app binary, so "a newer version exists" always means "this app build's catalog
    /// disagrees with what was installed," never a live server telling a possibly-older client
    /// something it can't act on yet.
    public var catalogUpdates: [(installed: SoundFontEntry, latest: SoundFontCatalogEntry)] {
        soundFonts.compactMap { installed in
            guard case .curated(_, let catalogEntryId, let catalogVersion) = installed.origin,
                  let latest = CuratedSoundFontCatalog.entries.first(where: { $0.id == catalogEntryId }),
                  latest.version != catalogVersion
            else { return nil }
            return (installed, latest)
        }
    }

    /// The absolute path to a soundfont's bytes on THIS device, if they're actually present —
    /// `nil` for a soundfont known to the index (visible in `soundFonts`, presets browsable)
    /// but not yet downloaded here (`.synced`, not materialized on this device) or genuinely
    /// missing. Never resolves through `sampleFolder`/`sampleFiles` — soundfonts found this way
    /// live in `soundFontLibrary`'s own folders instead (read back from there, not re-resolved
    /// via `SoundFontLocations` directly, so this agrees with whatever folders
    /// `startSoundFontLibrary`/`importSoundFont` actually used — real system folders in
    /// production, an isolated temp directory in tests).
    public func soundFontPath(forHash hash: String) -> String? {
        guard let entry = soundFonts.first(where: { $0.hash == hash }) else { return nil }
        let folder: URL?
        switch entry.syncPreference {
        case .synced: folder = soundFontLibrary.syncedFolder
        case .localOnly: folder = soundFontLibrary.localFolder
        }
        guard let folder else { return nil }
        let url = folder.appendingPathComponent(entry.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    /// Loads a sample-based instrument by name from the last-listed folder (see
    /// `listSampleFiles`), replacing the piece-playback sampler's current sound (the
    /// default sine synth, or whatever was loaded before) — used by `play()`, entirely
    /// separate from any live-input track's own instrument (see `setInstrument(named:for:)`).
    public func loadSample(named name: String, preset: SoundFontPresetIdentity? = nil) throws {
        try player.loadSample(at: resolvedSampleURL(named: name), preset: preset)
        append("Loaded instrument: \(name)")
    }

    /// Convenience over `loadSample(named:)` using the 0-based position in `sampleFiles`.
    public func loadSample(atIndex index: Int, preset: SoundFontPresetIdentity? = nil) throws {
        guard sampleFiles.indices.contains(index) else { throw SessionError.invalidSampleIndex }
        try loadSample(named: sampleFiles[index], preset: preset)
    }

    /// Same as `loadSample(named:)`, for `soundTrackPlayer`'s own sampler instead of the
    /// piece-playback one — until this is called, a `SoundTrack` recording plays back through
    /// the default sine synth, exactly like a piece would before its own `loadSample`.
    public func loadSoundTrackSample(named name: String, preset: SoundFontPresetIdentity? = nil) throws {
        try soundTrackPlayer.loadSample(at: resolvedSampleURL(named: name), preset: preset)
        append("Son de lecture (enregistrement): \(name)")
    }

    /// Convenience over `loadSoundTrackSample(named:)` using the 0-based position in `sampleFiles`.
    public func loadSoundTrackSample(atIndex index: Int, preset: SoundFontPresetIdentity? = nil) throws {
        guard sampleFiles.indices.contains(index) else { throw SessionError.invalidSampleIndex }
        try loadSoundTrackSample(named: sampleFiles[index], preset: preset)
    }

    /// Same as `loadSoundTrackSample(named:)`, for `guideAuditionPlayer`'s own sampler — until
    /// this is called, "Ecouter le guide" plays back through the default sine synth.
    public func loadGuideAuditionSample(named name: String, preset: SoundFontPresetIdentity? = nil) throws {
        try guideAuditionPlayer.loadSample(at: resolvedSampleURL(named: name), preset: preset)
        append("Son d'ecoute du guide: \(name)")
    }

    /// Derives the SoundTrack playback sound from the active scene instead of requiring a
    /// manual pick each time (see the Studio tab's "Enregistrement actuel" sub-tab, merged from
    /// the former standalone "Play" sub-tab, 2026-07-26) — the role attached to
    /// `.computerKeyboard` if there is one (the most likely "lead" instrument), otherwise the
    /// first attached role with a sound of its own. A no-op (not an error) if there's no active
    /// scene or no attached role has a sound — same "best effort" spirit as
    /// `applyRoleConfiguration`.
    public func applyCurrentSceneSoundToSoundTrackPlayer() {
        guard let scene = currentScene else { return }
        let role = scene.roles.first(where: { $0.attachedTrackID == .computerKeyboard && $0.soundName != nil })
            ?? scene.roles.first(where: { $0.attachedTrackID != nil && $0.soundName != nil })
        guard let soundName = role?.soundName else { return }
        try? loadSoundTrackSample(named: soundName, preset: role?.soundPreset)
    }

    /// One favorited sound — a specific preset within a `.sf2` (or a `.dls`/`.aupreset`'s own
    /// single sound, `preset == nil`), ready to display and to pass straight back into
    /// `setInstrument`/`setSceneRoleSound`/etc. A favorite is always a SOUND, never a whole
    /// file: a multi-preset `.sf2` can contribute several distinct `FavoriteSound`s, one per
    /// preset the user actually favorited.
    public struct FavoriteSound: Identifiable, Equatable, Sendable {
        public var path: String
        public var preset: SoundFontPresetIdentity?
        public var displayName: String
        public var iconSystemName: String?

        public var id: String {
            guard let preset else { return path }
            return "\(path)#\(preset.program):\(preset.bank)"
        }

        public init(path: String, preset: SoundFontPresetIdentity?, displayName: String, iconSystemName: String? = nil) {
            self.path = path
            self.preset = preset
            self.displayName = displayName
            self.iconSystemName = iconSystemName
        }
    }

    /// Every favorited sound (see `SoundEntry.isFavorite`) whose soundfont is actually present
    /// on this device right now (see `soundFontPath(forHash:)`) — this is what every sound
    /// *picker* in the app should show (`PiecesPlayView`/`GuideEditionView`/`SceneLayoutView`'s
    /// role-sound menu), so a big decompressed library dumped into the soundfont folder doesn't
    /// turn every picker into an unusable wall of cryptic filenames/presets. The Sounds sub-tab
    /// itself (where favorites get chosen from in the first place) browses every file/preset
    /// directly, not through this list — deliberately no "fall back to showing everything when
    /// there are zero favorites" exception: marking at least one favorite is the expected first
    /// step before using any other sound picker. A favorite whose soundfont is indexed
    /// (`soundFonts`) but not downloaded on this device (`.synced`, not materialized here) is
    /// silently omitted, same as a genuinely missing file always was — the difference is this
    /// case is recoverable (download it) rather than a permanently broken reference.
    public var favoriteSounds: [FavoriteSound] {
        var presetsByHash: [String: [SoundFontPreset]] = [:]
        return soundEntries.compactMap { entry -> FavoriteSound? in
            guard entry.isFavorite, let path = soundFontPath(forHash: entry.soundFontHash) else { return nil }
            let fallbackName = "\(soundFonts.first { $0.hash == entry.soundFontHash }?.displayName ?? (path as NSString).lastPathComponent) — \(originalSoundName(forHash: entry.soundFontHash, preset: entry.preset, cache: &presetsByHash))"
            return FavoriteSound(path: path, preset: entry.preset, displayName: entry.alias ?? fallbackName, iconSystemName: entry.iconSystemName)
        }
    }

    /// The preset's own name as authored in the `.sf2` file (e.g. "Alto Sax"), used as the
    /// second half of `favoriteSounds`' fallback display name ("file — sound") when no alias
    /// was set — read straight from the already-indexed `soundFonts` entry (never re-parses the
    /// file itself, unlike the old path-based equivalent this replaces). `cache` avoids
    /// repeating the lookup once per favorited preset sharing the same soundfont.
    private func originalSoundName(forHash hash: String, preset: SoundFontPresetIdentity?, cache: inout [String: [SoundFontPreset]]) -> String {
        let presets: [SoundFontPreset]
        if let cached = cache[hash] {
            presets = cached
        } else {
            presets = soundFonts.first { $0.hash == hash }?.presets ?? []
            cache[hash] = presets
        }
        let identity = preset ?? SoundFontPresetIdentity(program: 0, bank: 0)
        return presets.first { $0.identity == identity }?.name ?? soundFonts.first { $0.hash == hash }?.displayName ?? hash
    }

    /// The alias for a specific sound if one was assigned, else `nil`. `preset` identifies WHICH
    /// sound within the soundfont; `nil` means that file's own single/default sound.
    public func soundAlias(forHash hash: String, preset: SoundFontPresetIdentity? = nil) -> String? {
        soundEntries.first { $0.soundFontHash == hash && $0.preset == preset }?.alias
    }

    public func isSoundFavorite(forHash hash: String, preset: SoundFontPresetIdentity? = nil) -> Bool {
        soundEntries.first { $0.soundFontHash == hash && $0.preset == preset }?.isFavorite ?? false
    }

    /// The icon assigned to a specific sound if one was assigned (suggested by the active LLM
    /// connection or picked manually — see `IconVocabulary`), else `nil`.
    public func soundIcon(forHash hash: String, preset: SoundFontPresetIdentity? = nil) -> String? {
        soundEntries.first { $0.soundFontHash == hash && $0.preset == preset }?.iconSystemName
    }

    /// Best-effort translation from a path-based sound reference — still how `SceneRole.soundName`
    /// works (see that type's own doc comment; migrating scene roles to a hash-based identity is
    /// explicitly out of scope for this pass, a separate known follow-up) — to this soundfont's
    /// stable hash, by matching the path's file name against the current index. `nil` if no
    /// indexed soundfont has that file name (never indexed, or renamed since).
    private func soundFontHash(forLegacyPath path: String) -> String? {
        let fileName = (path as NSString).lastPathComponent
        return soundFonts.first { $0.fileName == fileName }?.hash
    }

    /// What to show in any sound picker for a path-based sound reference (`SceneRole.soundName`)
    /// — its alias if the path resolves to a known, curated soundfont, otherwise the path
    /// itself unchanged (today's behavior for anything not yet migrated to hash-based identity).
    public func displayName(forSamplePath path: String, preset: SoundFontPresetIdentity? = nil) -> String {
        guard let hash = soundFontHash(forLegacyPath: path), let alias = soundAlias(forHash: hash, preset: preset) else { return path }
        return alias
    }

    /// Sets (or clears, with `nil`/empty) a sound's alias and persists. Removes the entry
    /// entirely once it has neither an alias nor a favorite flag, keeping the store limited to
    /// sounds the user actually curated.
    public func setSoundAlias(forHash hash: String, preset: SoundFontPresetIdentity? = nil, alias: String?) throws {
        let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        try updateSoundEntry(forHash: hash, preset: preset) { $0.alias = (trimmed?.isEmpty ?? true) ? nil : trimmed }
    }

    /// Marks (or unmarks) a sound as a favorite and persists — see `favoriteSounds`.
    public func setSoundFavorite(forHash hash: String, preset: SoundFontPresetIdentity? = nil, isFavorite: Bool) throws {
        try updateSoundEntry(forHash: hash, preset: preset) { $0.isFavorite = isFavorite }
    }

    /// Sets (or clears, with `nil`) a sound's icon and persists — same shape as `setSoundAlias`.
    public func setSoundIcon(forHash hash: String, preset: SoundFontPresetIdentity? = nil, iconSystemName: String?) throws {
        try updateSoundEntry(forHash: hash, preset: preset) { $0.iconSystemName = iconSystemName }
    }

    /// Shared mutator behind `setSoundAlias`/`setSoundFavorite`/`setSoundIcon`: finds or creates
    /// the entry for `(hash, preset)`, applies `mutate`, drops the entry if it ends up with no
    /// alias and not a favorite (the "untouched" state), then persists either way. Fetches every
    /// `SoundEntryRecord` and filters in memory rather than a `#Predicate` on the flattened
    /// `presetProgram`/`presetBank` fields — only ever a handful of curated sounds, and this
    /// sidesteps any doubt about optional-`Int` equality inside a SwiftData predicate.
    private func updateSoundEntry(forHash hash: String, preset: SoundFontPresetIdentity?, mutate: (inout SoundEntry) -> Void) throws {
        let records = (try? modelContext.fetch(FetchDescriptor<SoundEntryRecord>())) ?? []
        let presetProgram = preset.map { Int($0.program) }
        let presetBank = preset.map { Int($0.bank) }
        if let record = records.first(where: { $0.soundFontHash == hash && $0.presetProgram == presetProgram && $0.presetBank == presetBank }) {
            var entry = record.asSoundEntry
            mutate(&entry)
            if entry.alias == nil && !entry.isFavorite && entry.iconSystemName == nil {
                modelContext.delete(record)
            } else {
                record.alias = entry.alias
                record.isFavorite = entry.isFavorite
                record.iconSystemName = entry.iconSystemName
            }
        } else {
            var entry = SoundEntry(soundFontHash: hash, preset: preset)
            mutate(&entry)
            if entry.alias != nil || entry.isFavorite || entry.iconSystemName != nil {
                modelContext.insert(SoundEntryRecord(entry))
            }
        }
        try modelContext.save()
        refreshSoundEntries()
    }

    /// Re-reads `soundEntries` from `modelContext` — called after every migrate/mutate so the
    /// in-memory list every caller already iterates never drifts from what's actually stored.
    private func refreshSoundEntries() {
        soundEntries = ((try? modelContext.fetch(FetchDescriptor<SoundEntryRecord>())) ?? []).map(\.asSoundEntry)
    }

    /// One-time bridge from the OLD, path-keyed `sound-settings.json` to the SwiftData store —
    /// mirrors `migrateColorPalettesFromJSONIfNeeded(fromJSONFile:)`'s "only if the store is
    /// still empty" guard. Each entry is inserted with `legacyPath` set and `soundFontHash`
    /// still empty — `migrateSoundEntriesToHashKeyedIfNeeded` (which must run afterward) is what
    /// actually resolves the hash.
    public func migrateSoundSettingsFromJSONIfNeeded(fromJSONFile path: String) {
        refreshSoundEntries()
        guard soundEntries.isEmpty else { return }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let file = try? JSONDecoder().decode(SoundSettingsFile.self, from: data), !file.sounds.isEmpty else { return }
        for legacy in file.sounds {
            let record = SoundEntryRecord(SoundEntry(
                soundFontHash: "", alias: legacy.alias, isFavorite: legacy.isFavorite,
                preset: legacy.preset, iconSystemName: legacy.iconSystemName
            ))
            record.legacyPath = legacy.path
            modelContext.insert(record)
        }
        try? modelContext.save()
        refreshSoundEntries()
        append("Migrated \(file.sounds.count) sound setting(s) from \(path) (original left in place, pending hash resolution).")
    }

    /// One-time bridge for any `SoundEntryRecord` still carrying the OLD path-keyed identity
    /// (`legacyPath` set, `soundFontHash` empty — only ever produced by
    /// `migrateSoundSettingsFromJSONIfNeeded`) — resolves each to a stable hash by matching its
    /// path's file name against the now-populated `soundFonts` index. Must run after
    /// `startSoundFontLibrary`/`migrateSoundFontsFromFolderScanIfNeeded` (see
    /// `ContentView.swift`'s launch sequence for the real call order), so the hashes it needs to
    /// match against actually exist. An entry that can't be matched (its file was already renamed/removed before this
    /// update ever ran) is dropped rather than left permanently stuck — it was already
    /// effectively unreachable under the old path-based scheme too.
    public func migrateSoundEntriesToHashKeyedIfNeeded() {
        let records = (try? modelContext.fetch(FetchDescriptor<SoundEntryRecord>())) ?? []
        let pending = records.filter(\.soundFontHash.isEmpty)
        guard !pending.isEmpty else { return }
        var resolvedCount = 0
        for record in pending {
            guard let legacyPath = record.legacyPath, let hash = soundFontHash(forLegacyPath: legacyPath) else {
                append("Sound favorite/alias '\(record.legacyPath ?? "?")' no longer matches any indexed soundfont — dropped (already broken before this update).")
                modelContext.delete(record)
                continue
            }
            record.soundFontHash = hash
            record.legacyPath = nil
            resolvedCount += 1
        }
        try? modelContext.save()
        refreshSoundEntries()
        if resolvedCount > 0 {
            append("Resolved \(resolvedCount) sound favorite/alias entry(ies) to hash-based identity.")
        }
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

    /// Releases every pitch this track currently thinks is held — a "panic button" for a
    /// client that can't reliably enumerate what it thinks is down itself (see the virtual
    /// keyboard's Escape handler): two independent `GET /note-on`/`GET /note-off` requests
    /// are two independent TCP connections with no ordering guarantee between them, so a fast
    /// tap can occasionally have its "off" processed before its "on", leaving a note stuck —
    /// this recovers by asking the *session*, not the client, what's actually still held.
    public func releaseAllKeys(track: TrackID = .computerKeyboard) {
        let stuck: [Int] = liveInputQueue.sync { Array(tracks.first { $0.id == track }?.heldPitches ?? []) }
        for pitch in stuck { releaseKey(pitch: pitch, track: track) }
    }

    /// Everything a note on/off does to one track's recognition state: logging,
    /// `heldPitches`, feeding that track's own recognizer, and — unless this is the
    /// microphone (which never sounds through the app, to avoid feedback) or this track's
    /// sound is off — its own sampler. Must run inside `liveInputQueue.sync` — this touches
    /// `recognizers`/`tracks` without its own synchronization, relying on the caller for that.
    private func updateRecognitionState(pitch: Int, isNoteOn: Bool, velocity: Int, channel: Int, track: TrackID) {
        guard let index = tracks.firstIndex(where: { $0.id == track }) else { return }
        lastMIDIEvent = MIDINoteEvent(kind: isNoteOn ? .noteOn : .noteOff, pitch: pitch, velocity: isNoteOn ? velocity : 0, channel: channel)
        tracks[index].lastChannel = channel
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
        syncLumiLiveModeIfActive()
    }

    /// Turns a stream of "here are the pitches right now, or empty for silence" reports into
    /// discrete, debounced note-on/note-off transitions via that track's
    /// `MicrophonePitchStabilizer` (see its doc comment for the confirmation policies) — the
    /// same shape as how MIDI note-on/note-off events already drive `heldPitches`/the
    /// recognizer, so several simultaneously-confirmed pitches naturally feed the same chord
    /// recognition real MIDI chords already use. `internal`, not `private`, so it's directly
    /// testable (`@testable import`) — see also `simulateMicrophoneDetection`, the public
    /// forwarder `SanityChecks` uses since it has no `@testable import`. Runs on whichever
    /// thread `MicrophonePitchListener` calls back on.
    func handleDetectedPitches(_ detected: [DetectedPitch], level: Float, track: TrackID) {
        liveInputQueue.sync {
            guard let index = tracks.firstIndex(where: { $0.id == track }) else { return }
            tracks[index].microphoneInputLevel = level
            tracks[index].lastDetectedPitches = detected
            if var capture = microphoneCalibrationCapture {
                capture.peakLevel = max(capture.peakLevel, level)
                microphoneCalibrationCapture = capture
            }
            let raw = Set(detected.map(\.midiPitch))
            for transition in pitchStabilizers[track]?.ingest(raw) ?? [] {
                updateRecognitionState(
                    pitch: transition.pitch, isNoteOn: transition.kind == .noteOn,
                    velocity: transition.kind == .noteOn ? 100 : 0, channel: 0, track: track
                )
            }
        }
        syncLumiLiveModeIfActive()
    }

    /// Public forwarder to `handleDetectedPitches` for `SanityChecks` (a separate executable
    /// target with no `@testable import`, so it can only reach `public` API) — lets it exercise
    /// the full FFT-detection-to-note-event pipeline (including the stabilizer) without real
    /// microphone hardware, the same way `pressKey`/`releaseKey` already do for MIDI/keyboard
    /// input.
    public func simulateMicrophoneDetection(_ detected: [DetectedPitch], level: Float, track: TrackID = .microphone) {
        handleDetectedPitches(detected, level: level, track: track)
    }

    // MARK: - Microphone spectroscope (opt-in, off by default — see MicrophoneControlsView)

    /// A dedicated queue, deliberately NOT `liveInputQueue`: unlike every other consumer of
    /// `liveInputQueue`, `currentMicrophoneSpectrum()` is polled straight from a SwiftUI
    /// `TimelineView` on the **main thread**, several times a second, for as long as the
    /// spectroscope is open. `liveInputQueue` is also where the real-time microphone/MIDI
    /// callback thread does its own frequent blocking `.sync` work (note detection, network
    /// broadcast) — sharing that queue would mean the main thread's render pass and the
    /// real-time audio thread repeatedly blocking on one another (priority inversion), which
    /// can freeze the UI and, if it stalls the audio thread's real-time deadline long enough,
    /// crash the process outright. This is exactly the "never bind SwiftUI directly to
    /// anything mutated off the main thread [via a contended queue]" pitfall `SessionUIBridge`
    /// exists to avoid everywhere else — an isolated, otherwise-unused queue for this one
    /// scalar snapshot sidesteps it just as well without needing to route through the
    /// bridge's `WebConsoleState` (which is also serialized over HTTP for the web console —
    /// not a place to add a per-window magnitude array).
    private let microphoneSpectrumQueue = DispatchQueue(label: "ImprovSession.microphoneSpectrum")
    /// `@ObservationIgnored` is load-bearing, not cosmetic: `ImprovSession` is `@Observable`,
    /// so without this, every read/write of this property goes through Swift's Observation
    /// runtime (`ObservationRegistrar`/`ObservationCenter`), which uses its own internal lock
    /// shared across the whole process — regardless of which queue guards the raw memory.
    /// That lock is what actually deadlocked on-device: the real-time audio thread mutating
    /// `tracks` (a legitimately-observed property) and this spectrum-queue thread mutating
    /// this property both tried to acquire it at once, while the main thread's `TimelineView`
    /// sat blocked on `microphoneSpectrumQueue.sync` waiting for the latter — three threads in
    /// a cycle, confirmed via a live `sample` of the frozen process (all three parked on the
    /// same `_MovableLockLock`/`ObservationCenter.invalidate` frame). This property was never
    /// meant to be observed reactively anyway (see `currentMicrophoneSpectrum`'s own doc
    /// comment — it's polled, not bound), so removing it from observation tracking entirely is
    /// the actual fix, not just a queue swap. `microphoneSpectrumQueue` above still matters for
    /// plain memory-safety (concurrent access to an un-observed property is still a data race),
    /// it just no longer also has to fight SwiftUI's own lock.
    @ObservationIgnored
    private var microphoneSpectrumSnapshot: (magnitudes: [Float], binHz: Double)?
    /// The user's own toggle, remembered independently of whether a `MicrophonePitchListener`
    /// currently exists — `startTrack(.microphone)` applies it to a freshly-created listener,
    /// and `setMicrophoneSpectrumCaptureEnabled` applies it live to an already-running one, so
    /// flipping the toggle either before or after starting the microphone both work. Off by
    /// default, per explicit user request. `@ObservationIgnored` for the same reason as
    /// `microphoneSpectrumSnapshot` above — it's flipped from the main thread (a UI toggle) but
    /// read from `MicrophonePitchListener`'s own `spectrumEnabled`, never observed by a View.
    @ObservationIgnored
    private var microphoneSpectrumCaptureEnabled = false

    private func storeMicrophoneSpectrum(magnitudes: [Float], binHz: Double) {
        microphoneSpectrumQueue.async { self.microphoneSpectrumSnapshot = (magnitudes, binHz) }
        // Opportunistically feed the calibration capture's peak-magnitude tracking (see
        // `microphoneCalibrationCapture`'s own doc comment) — a no-op if no capture is in
        // progress. `microphoneCalibrationCapture` is guarded by `liveInputQueue`, NOT
        // `microphoneSpectrumQueue`, so this hops onto that queue rather than touching it
        // directly from here (this closure runs on the real-time audio thread, same as
        // `handleDetectedPitches`, which already owns that property on `liveInputQueue`) —
        // `.async`, matching the "never block the real-time thread" rule the spectrum
        // snapshot write above already follows.
        liveInputQueue.async {
            guard var capture = self.microphoneCalibrationCapture else { return }
            capture.peakMagnitude = max(capture.peakMagnitude, magnitudes.max() ?? 0)
            self.microphoneCalibrationCapture = capture
        }
    }

    /// Turns the microphone's spectroscope capture on/off — cheap to leave off (the default):
    /// `MicrophonePitchListener` only does the extra per-window FFT-spectrum copy at all when
    /// this is `true` (see its own `spectrumEnabled` doc comment).
    public func setMicrophoneSpectrumCaptureEnabled(_ enabled: Bool) {
        microphoneSpectrumCaptureEnabled = enabled
        microphoneListener?.spectrumEnabled = enabled
        if !enabled { microphoneSpectrumQueue.async { self.microphoneSpectrumSnapshot = nil } }
    }

    /// The most recent magnitude spectrum captured from the microphone, or `nil` if
    /// spectroscope capture is off (see `setMicrophoneSpectrumCaptureEnabled`) or nothing's
    /// been analyzed yet. Safe to poll directly from the main thread (e.g. a `TimelineView`)
    /// — see `microphoneSpectrumQueue`'s own doc comment for why this one piece of state
    /// deliberately isn't guarded by `liveInputQueue` like the rest of this class.
    public func currentMicrophoneSpectrum() -> (magnitudes: [Float], binHz: Double)? {
        microphoneSpectrumQueue.sync { microphoneSpectrumSnapshot }
    }

    // MARK: - Microphone calibration (two-point quiet/loud range, see MicrophoneCalibrationSettingsFile)

    public enum MicrophoneCalibrationPhase: Sendable, Equatable {
        case quiet
        case loud
    }

    /// Guarded by `liveInputQueue`, same as `microphoneInputLevel` — set/cleared only from
    /// the main thread (`beginMicrophoneCalibrationCapture`/`endMicrophoneCalibrationCapture`)
    /// but updated from the microphone's real-time callback thread inside
    /// `handleDetectedPitches`, which already owns that queue for `microphoneInputLevel` — not
    /// a new source of cross-thread state, so no new queue is needed here (unlike the
    /// spectroscope's `microphoneSpectrumQueue`: this isn't polled tightly from a
    /// `TimelineView`, only read once when the UI ends a capture). `@ObservationIgnored` for
    /// the same reason as `microphoneSpectrumSnapshot` above — this is mutated from the
    /// real-time audio thread (inside `handleDetectedPitches`, alongside `tracks`), and never
    /// meant to be observed by any View; leaving it under Observation tracking would add a
    /// second background-thread contender for SwiftUI's internal invalidation lock, the same
    /// mechanism that caused the spectroscope deadlock.
    @ObservationIgnored
    private var microphoneCalibrationCapture: (phase: MicrophoneCalibrationPhase, peakLevel: Float, peakMagnitude: Float)?

    /// See `MicrophoneCalibrationSettingsFile`'s own doc comment for what this is used for.
    public private(set) var microphoneCalibration = MicrophoneCalibrationSettingsFile()

    /// One-time bridge from `microphone-calibration.json` to the SwiftData store — mirrors
    /// `migrateLanguageSettingFromJSONIfNeeded(fromJSONFile:)`: a no-op (beyond loading the
    /// existing value) if a `MicrophoneCalibrationSettingsRecord` already exists, otherwise
    /// migrates the file's values (left in place) or seeds the defaults.
    public func migrateMicrophoneCalibrationFromJSONIfNeeded(fromJSONFile path: String) {
        if let existing = try? modelContext.fetch(FetchDescriptor<MicrophoneCalibrationSettingsRecord>()).first {
            microphoneCalibration = existing.asMicrophoneCalibrationSettingsFile
            return
        }
        let file: MicrophoneCalibrationSettingsFile
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let decoded = try? JSONDecoder().decode(MicrophoneCalibrationSettingsFile.self, from: data) {
            file = decoded
            append("Migrated microphone calibration from \(path) (original left in place).")
        } else {
            file = MicrophoneCalibrationSettingsFile()
        }
        modelContext.insert(MicrophoneCalibrationSettingsRecord(file))
        try? modelContext.save()
        microphoneCalibration = file
    }

    private func saveMicrophoneCalibration() throws {
        if let existing = try? modelContext.fetch(FetchDescriptor<MicrophoneCalibrationSettingsRecord>()).first {
            existing.quietRMS = microphoneCalibration.quietRMS
            existing.loudRMS = microphoneCalibration.loudRMS
            existing.quietPeakMagnitude = microphoneCalibration.quietPeakMagnitude
            existing.loudPeakMagnitude = microphoneCalibration.loudPeakMagnitude
        } else {
            modelContext.insert(MicrophoneCalibrationSettingsRecord(microphoneCalibration))
        }
        try modelContext.save()
    }

    /// Starts a capture window for one calibration phase: for as long as this is active
    /// (until `endMicrophoneCalibrationCapture()`/`cancelMicrophoneCalibrationCapture()` is
    /// called), every microphone analysis window's level is compared against a running peak —
    /// the UI drives how long that lasts (typically "hold this while you play a few quiet/
    /// loud notes"), not this method, so there's no timer here to get out of sync with what's
    /// shown on screen. Requires the microphone track to already be listening (same as the
    /// existing "Niveau" meter) — otherwise the peak just stays at 0.
    public func beginMicrophoneCalibrationCapture(phase: MicrophoneCalibrationPhase) {
        liveInputQueue.sync { microphoneCalibrationCapture = (phase, 0, 0) }
    }

    /// Commits the current capture window's peak level (and peak spectral magnitude, if the
    /// spectroscope happened to be on — see `microphoneCalibrationCapture`'s own doc comment,
    /// 0 otherwise) into `microphoneCalibration` (persisted) and clears the capture state. A
    /// no-op if no capture is in progress (e.g. `beginMicrophoneCalibrationCapture` was never
    /// called, or this is called twice).
    public func endMicrophoneCalibrationCapture() throws {
        let capture: (phase: MicrophoneCalibrationPhase, peakLevel: Float, peakMagnitude: Float)? = liveInputQueue.sync {
            let value = microphoneCalibrationCapture
            microphoneCalibrationCapture = nil
            return value
        }
        guard let capture else { return }
        switch capture.phase {
        case .quiet:
            microphoneCalibration.quietRMS = capture.peakLevel
            microphoneCalibration.quietPeakMagnitude = capture.peakMagnitude
        case .loud:
            microphoneCalibration.loudRMS = capture.peakLevel
            microphoneCalibration.loudPeakMagnitude = capture.peakMagnitude
        }
        try saveMicrophoneCalibration()
        let phaseLabel = capture.phase == .quiet ? "note faible" : "note forte"
        append("Calibration microphone (\(phaseLabel)) enregistree : niveau \(capture.peakLevel).")
    }

    /// Abandons the current capture window without touching `microphoneCalibration` — for a
    /// "Annuler" button mid-capture.
    public func cancelMicrophoneCalibrationCapture() {
        liveInputQueue.sync { microphoneCalibrationCapture = nil }
    }

    public func resetMicrophoneCalibration() throws {
        microphoneCalibration = MicrophoneCalibrationSettingsFile()
        try saveMicrophoneCalibration()
        append("Calibration microphone reinitialisee.")
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

        recordChordEventIfChanged(track: track, heldPitches: tracks[index].heldPitches, chord: chord)
    }

    /// Appends to this track's `recentChordEvents` the instant the held-pitches/chord actually
    /// changes — called on every single note on/off, same as `refreshRecognition` itself, so a
    /// chord that's played and released faster than a browser's poll interval still lands in
    /// the log exactly once, instead of possibly never being observed at all (the bug this
    /// replaces: the staff history used to be reconstructed client-side by diffing successive
    /// `GET /state` polls, which could miss anything faster than ~150-250ms). A full release
    /// (empty `heldPitches`) is never appended — same "last-played event stays visible, no
    /// blank rest entries" convention the client-side version already established.
    private func recordChordEventIfChanged(track: TrackID, heldPitches: Set<Int>, chord: RecognizedChord?) {
        guard !heldPitches.isEmpty else { return }
        let (chordTones, _) = Self.pitchClassSets(
            forChordRoot: chord?.root.value, chordTemplateID: chord?.chordTemplateID, modeTonic: nil, scaleID: nil
        )
        let event = WebConsoleChordEvent(
            pitches: heldPitches.sorted(), chordRoot: chord?.root.value, chordTones: chordTones.sorted()
        )
        var log = recentChordEvents[track] ?? []
        if let last = log.last, last.pitches == event.pitches, last.chordRoot == event.chordRoot, last.chordTones == event.chordTones {
            return
        }
        log.append(event)
        if log.count > Self.maxRecentChordEvents { log.removeFirst() }
        recentChordEvents[track] = log
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

    /// Hosts a collaborative session over Game Center's matchmaking instead of a local TCP
    /// listener — same "server" logic as `startServer(port:)` (any matched player is
    /// accepted, tracks merged, `sync` broadcast every ~150ms), just addressed via
    /// `GKPlayer.gamePlayerID` instead of a per-TCP-connection UUID. `match` must already be
    /// a real, connected `GKMatch` — obtaining one (authentication, presenting Game Center's
    /// matchmaker UI) is a UI-layer concern, not this session's — see `GameCenterCoordinator`
    /// in the App target.
    public func startGameCenterServer(with match: GKMatch) throws {
        guard networkRole == .standalone else { throw SessionError.networkRoleAlreadyActive }
        let transport = GameCenterTransport(
            match: match, role: .organizer,
            onMessage: { [weak self] connectionID, message in self?.handleServerMessage(connectionID, message) },
            onDisconnect: { [weak self] connectionID in self?.handleClientDisconnected(connectionID) }
        )
        netServer = transport
        networkRole = .gameCenterServer
        startSyncBroadcastTimer()
        append("Session Game Center demarree (organisateur).")
    }

    /// Every participant currently connected while hosting (`networkRole == .server`), even
    /// one with no active/announced track yet — unlike scanning `tracks` for `.remote`
    /// entries (which only ever shows participants who've *announced* at least one
    /// instrument), this reads `clientIDToClientName` directly, populated as soon as a
    /// connection's `hello` message arrives. Empty (not an error) outside server mode — see
    /// `Sources/JamShack/main.swift`'s scene-tree renderer for the main consumer.
    public func connectedClients() -> [(clientID: String, name: String)] {
        guard networkRole.isServerRole else { return [] }
        return liveInputQueue.sync { clientIDToClientName.map { (clientID: $0.key, name: $0.value) } }
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
        guard networkRole.isServerRole else { return }
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

    #if os(macOS)
    private static let mcpServerEnabledKey = "JamShackMCPServerEnabled"

    /// Whether the embedded MCP server should be running — off by default, explicit opt-in via
    /// the "I.A." settings panel (`JamShackAIView.swift`). `UserDefaults`-backed, per-device,
    /// never synced via CloudKit — same convention as `DeviceStorageProfile`: whether to expose
    /// this device's control surface to a local MCP client (Claude Desktop) is a per-machine
    /// decision, not a preference that should follow the user to another device. Reading this
    /// does NOT tell you whether the server is actually running right now (see `mcpServer`) —
    /// only whether the user wants it to be; `startMCPServerIfEnabled()`/`setMCPServerEnabled`
    /// are what actually start/stop it.
    public var mcpServerEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.mcpServerEnabledKey)
    }

    /// Persists the user's choice and immediately starts/stops the server to match — this is
    /// the method the "I.A." panel's toggle calls, so any failure to start (e.g. the port
    /// already bound by something else) throws back to that UI immediately rather than being
    /// silently swallowed.
    public func setMCPServerEnabled(_ enabled: Bool) throws {
        UserDefaults.standard.set(enabled, forKey: Self.mcpServerEnabledKey)
        if enabled {
            try startMCPServerNow()
        } else {
            stopMCPServer()
        }
    }

    private func startMCPServerNow() throws {
        guard mcpServer == nil else { return }
        let server = MCPServer(session: self)
        try server.start(port: MCPServer.defaultPort)
        mcpServer = server
        append("Serveur MCP demarre sur http://127.0.0.1:\(MCPServer.defaultPort)")
    }

    /// Called once at launch (see `ContentView.swift`'s `.task`) — starts the server
    /// automatically if the user had already enabled it in a previous session, so they don't
    /// have to re-toggle it every time just to keep using Claude Desktop. Deliberately
    /// non-throwing (unlike `setMCPServerEnabled`): mirrors `ensureGuideReadyForLaunch`/
    /// `ensureSceneReadyForLaunch`'s own "always safe to call, never a launch-blocking failure"
    /// contract — a genuine failure here (e.g. the port already bound by something else) is
    /// surfaced next time the user opens the I.A. panel and notices the toggle looks enabled
    /// but Claude Desktop still can't connect; acceptable for a first version, revisit if this
    /// proves confusing in practice.
    public func startMCPServerIfEnabled() {
        guard mcpServerEnabled else { return }
        try? startMCPServerNow()
    }

    public func stopMCPServer() {
        mcpServer?.stop()
        mcpServer = nil
        append("Serveur MCP arrete.")
    }
    #endif

    private func handleWebConsoleRequest(_ request: HTTPRequest) -> HTTPResponse {
        let (path, query) = Self.splitQuery(request.path)
        switch path {
        case "/": return .text(webConsoleIndexHTML, contentType: "text/html; charset=utf-8")
        case "/app.js": return .text(webConsoleAppJS, contentType: "application/javascript")
        case "/state": return HTTPResponse(contentType: "application/json", body: webConsoleStateQueue.sync { webConsoleStateCache })
        case "/menu-lists": return handleMenuListsRequest()
        case "/menu-action": return handleMenuAction(query)
        case "/piece-detail": return handlePieceDetailRequest()
        case "/composition-detail": return handleCompositionDetailRequest()
        case "/guide-detail": return handleGuideDetailRequest()
        case "/soundtrack-detail": return handleSoundTrackDetailRequest()
        case "/guide-advance-step":
            // Global session state, like the virtual keyboard's own `/guide-advance` — any
            // browser tab's arrow keys move the SAME guide everyone sees, mirroring the
            // terminal's own up/down arrows on its `.guide` screen.
            guard let delta = query["delta"].flatMap(Int.init) else { return .text("bad delta", contentType: "text/plain", status: 400) }
            advanceGuideStep(by: delta)
            return .text("", contentType: "text/plain")
        case "/guide-advance-chord":
            guard let delta = query["delta"].flatMap(Int.init) else { return .text("bad delta", contentType: "text/plain", status: 400) }
            advanceGuideChord(by: delta)
            return .text("", contentType: "text/plain")
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

    /// `public` (not `private`) so `Tests/AppCoreTests` AND `SanityChecks` (a genuinely
    /// different module — no `@testable import` there, so `internal` wouldn't be visible to
    /// it) can exercise `recentChordEvents` directly, without standing up the HTTP layer just
    /// to unit-test the event log.
    public func buildWebConsoleState() -> WebConsoleState {
        let lastEvent = lastMIDIEvent.map { "\($0.kind == .noteOn ? "on " : "off")pitch=\($0.pitch) vel=\($0.velocity)" }

        let listeningTracks: [TrackInfo] = liveInputQueue.sync { tracks.filter { $0.isListening } }
        let trackStates = listeningTracks.map(self.webConsoleTrackState)

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

        return WebConsoleState(
            lastEvent: lastEvent, tracks: trackStates, playback: playback, soundTrackPlayback: soundTrackPlayback,
            wheel: buildWebConsoleWheelState(listeningTracks: listeningTracks),
            guide: buildWebConsoleGuideState(),
            palette: activeColorPalette.colors, paletteTextColors: activeColorPalette.textColors,
            scene: buildWebConsoleSceneState(), language: currentLanguage.rawValue,
            lumi: WebConsoleLumiState(
                rootColorHex: lumiSettings.rootColorHex, scaleColorHex: lumiSettings.scaleColorHex,
                brightnessPercentage: lumiSettings.brightnessPercentage,
                autoPropagateRunMode: lumiSettings.autoPropagateRunMode, autoPropagateGuideMode: lumiSettings.autoPropagateGuideMode
            ),
            noteColors: WebConsoleNoteColorsState(
                modeRootHex: noteColorSettings.modeRootHex, modeOtherHex: noteColorSettings.modeOtherHex,
                chordRootHex: noteColorSettings.chordRootHex, chordToneHex: noteColorSettings.chordToneHex,
                heldNoChordHex: noteColorSettings.heldNoChordHex, heldOutsideChordHex: noteColorSettings.heldOutsideChordHex
            )
        )
    }

    /// See `WebConsoleSceneState`'s doc comment — mirrors `Sources/JamShack/main.swift`'s
    /// `printSceneTree()` exactly, just producing a JSON-friendly shape instead of ASCII
    /// box-drawing.
    private func buildWebConsoleSceneState() -> WebConsoleSceneState {
        let networkRoleText: String
        switch networkRole {
        case .standalone: networkRoleText = "solo"
        case .server(let port): networkRoleText = "serveur sur le port \(port)"
        case .client(let description): networkRoleText = "connecte a \(description)"
        case .gameCenterServer: networkRoleText = "serveur Game Center"
        case .gameCenterClient(let description): networkRoleText = "connecte via Game Center a \(description)"
        }

        let allTracks = liveInputQueue.sync { tracks }
        let localInstruments = allTracks
            .filter { if case .remote = $0.id { return false }; return true }
            .map(self.webConsoleTrackState)

        let clients = connectedClients().map { client in
            let instruments = allTracks
                .filter { if case .remote(let clientID, _) = $0.id { return clientID == client.clientID }; return false }
                .map(self.webConsoleTrackState)
            return WebConsoleSceneClientState(clientID: client.clientID, name: client.name, instruments: instruments)
        }

        let roles = (currentScene?.roles ?? []).map { role in
            let attachedLabel = role.attachedTrackID.flatMap { id in allTracks.first { $0.id == id }?.label }
            return WebConsoleSceneRoleState(name: role.name, attachedLabel: attachedLabel, soundName: role.soundName)
        }

        return WebConsoleSceneState(
            networkRoleText: networkRoleText, webConsolePort: webConsolePort, virtualKeyboardPort: virtualKeyboardPort,
            localInstruments: localInstruments, clients: clients, sceneTitle: currentScene?.title, roles: roles
        )
    }

    // MARK: - Web console remote menu (mirrors the terminal's own pull-down menu)
    //
    // `Sources/JamShack/main.swift`'s `menuCategories` (the DOS-style pull-down menu) and the
    // plain-text REPL both funnel into one shared `executeCommand(_:_:)` switch so the two
    // never duplicate business logic — see that file's own doc comment. This section is the
    // same idea extended to the web console's new "Menu" tab: a thin HTTP-reachable dispatcher
    // over the exact same `ImprovSession` public methods `executeCommand` already calls, not a
    // second copy of any actual behavior. It's a NEW, separate switch (not literally
    // `executeCommand` itself) because that one is wired to blocking terminal I/O
    // (`print`/`readLine` for follow-up prompts) that has no meaning over HTTP — a browser
    // form collects every field in one submission instead of prompting step by step, so a
    // menu item that CLI-side chains several prompts (e.g. "Nouveau guide musical..."'s
    // repeating tonic/scale/progression loop) is exposed here as its underlying atomic
    // commands instead (`guide-new`, `guide-add-mode`) — same effect, reached by submitting
    // the form more than once instead of being walked through prompts. Pure read-only
    // displays (`status`, `run`, `scene-tree`, `show-*`) are deliberately NOT mirrored here —
    // the user only asked for the action items ("ajouter, activer, lister, creer..."), and
    // those displays already exist elsewhere (Run/Scene/Infos tabs) or are just a `GET /state`
    // read away.

    private struct WebConsoleMenuTrack: Codable { var id: String; var label: String }
    private struct WebConsoleMenuScale: Codable { var id: String; var name: String }
    /// `attachedLabel` is the label of whichever track currently occupies this role, `nil` if
    /// free — precomputed server-side so the web/MCP client never has to cross-reference
    /// `tracks` itself just to show "Piano 1 (Clavier ordinateur)" vs "Piano 1 (libre)".
    private struct WebConsoleMenuSceneRole: Codable { var id: String; var name: String; var attachedLabel: String? }
    private struct WebConsoleMenuLists: Codable {
        var tracks: [WebConsoleMenuTrack]
        var pieceFiles: [String]
        var sampleFiles: [String]
        var soundTrackFiles: [String]
        var guideFiles: [String]
        var sceneFiles: [String]
        var compositionFiles: [String]
        var textFramingFiles: [String]
        var soundTrackFramingFiles: [String]
        var soundTrackInstructionsFiles: [String]
        var llmConnections: [String]
        var colorPalettes: [String]
        var chordProgressionTemplates: [String]
        var scales: [WebConsoleMenuScale]
        var midiFusionMode: String
        /// Only non-empty right after a "Rechercher" (`jam-discover`) action — see that
        /// case's own comment in `performMenuAction`.
        var discoveredJamSessions: [String]
        /// Every role in the active scene (attached or not) — `[]` if there's no active
        /// scene. See `Sources/AppCore/Scene.swift`'s own doc comments for what a role is.
        var sceneRoles: [WebConsoleMenuSceneRole]
        /// Local tracks not currently attached to any role — mirrors `unassignedInstruments()`
        /// but as wire ids, same shape as `tracks` above. `[]` (not "every track") when
        /// there's no active scene, since "unassigned" is meaningless without one.
        var unassignedTracks: [WebConsoleMenuTrack]
        /// See `WebConsoleState.language`'s doc comment — the Menu tab is built once per
        /// tab-visit and never reads `/state`, so this is the only channel it has to notice a
        /// language change made while already sitting on that tab.
        var language: String
    }

    /// `internal` (not `private`), specifically so `MCPServer.swift` (same module, different
    /// file) can reuse this exact JSON shape for its own `get_menu_lists` MCP tool — no new
    /// business logic, just a second front door.
    func handleMenuListsRequest() -> HTTPResponse {
        // Local tracks only (`wireIDText != nil`) — `.remote` tracks aren't something this
        // machine can start/stop/reassign, same restriction `executeCommand`'s own `track`
        // command has (its `parseTrackID` never produces a `.remote` id either).
        let localTracks = tracks.compactMap { track -> WebConsoleMenuTrack? in
            guard let idText = track.id.wireIDText else { return nil }
            return WebConsoleMenuTrack(id: idText, label: track.label)
        }
        let sceneRoles = (currentScene?.roles ?? []).map { role in
            let attachedLabel = role.attachedTrackID.flatMap { id in tracks.first { $0.id == id }?.label }
            return WebConsoleMenuSceneRole(id: role.id.uuidString, name: role.name, attachedLabel: attachedLabel)
        }
        let unassignedTracks = unassignedInstruments().compactMap { track -> WebConsoleMenuTrack? in
            guard let idText = track.id.wireIDText else { return nil }
            return WebConsoleMenuTrack(id: idText, label: track.label)
        }
        let lists = WebConsoleMenuLists(
            tracks: localTracks, pieceFiles: pieceNames, sampleFiles: sampleFiles,
            soundTrackFiles: soundTrackNames, guideFiles: guideSequenceNames, sceneFiles: sceneNames,
            compositionFiles: compositionDescriptionNames, textFramingFiles: textFramingSentenceNames,
            soundTrackFramingFiles: soundTrackFramingSentenceNames, soundTrackInstructionsFiles: soundTrackInstructionsNames,
            llmConnections: llmConnections, colorPalettes: colorPalettes.map(\.name),
            chordProgressionTemplates: chordProgressionTemplates.map(\.name),
            scales: ScaleLibrary.all.map { WebConsoleMenuScale(id: $0.id, name: $0.popularName) },
            midiFusionMode: midiFusionMode == .merged ? "fusionne" : "individuel",
            discoveredJamSessions: lastDiscoveredServers.map(\.name),
            sceneRoles: sceneRoles, unassignedTracks: unassignedTracks, language: currentLanguage.rawValue
        )
        guard let data = try? JSONEncoder().encode(lists) else { return .notFound() }
        return HTTPResponse(contentType: "application/json", body: data)
    }

    private enum MenuActionError: Error, CustomStringConvertible {
        case unknownAction(String)
        case invalidTrack
        case invalidValue
        var description: String {
            switch self {
            case .unknownAction(let name): return "action inconnue : \(name)"
            case .invalidTrack: return "piste inconnue ou manquante"
            case .invalidValue: return "valeur manquante ou invalide"
            }
        }
    }

    private struct MenuActionResult: Codable {
        var ok: Bool
        var message: String
        var items: [String]?
    }

    /// Cache for whichever jam-session discovery scan the "Menu" tab's own "Rechercher" action
    /// last triggered, mirrored back out via `WebConsoleMenuLists.discoveredJamSessions` —
    /// same "numbered list from the last scan/listing" convention as `pieceFiles`/
    /// `sampleFiles`/etc., even though a `DiscoveredServer` itself isn't nameable/storable any
    /// other way (its `endpoint` is an opaque `NWEndpoint`, not `Codable`).
    private var lastDiscoveredServers: [DiscoveredServer] = []

    /// `internal` (not `private`) for the same reason as `handleMenuListsRequest` above —
    /// `MCPServer.swift` reuses this exact `{ok, message, items?}` JSON shape for every
    /// menu-action MCP tool call.
    func handleMenuAction(_ query: [String: String]) -> HTTPResponse {
        let action = query["action"] ?? ""
        let value = query["value"] ?? ""
        let result: MenuActionResult
        do {
            result = try performMenuAction(action, query: query, value: value)
        } catch {
            result = MenuActionResult(ok: false, message: "\(error)")
        }
        guard let data = try? JSONEncoder().encode(result) else { return .notFound() }
        return HTTPResponse(contentType: "application/json", body: data)
    }

    // swiftlint-friendly length aside, this mirrors `executeCommand`'s own single big switch
    // (one case per command) — same shape, just dispatching to the same `ImprovSession`
    // methods from HTTP query parameters instead of parsed REPL argument tokens.
    private func performMenuAction(_ action: String, query: [String: String], value: String) throws -> MenuActionResult {
        func ok(_ message: String) -> MenuActionResult { MenuActionResult(ok: true, message: message) }
        switch action {
        // --- JamShack ---
        case "folder-pieces": migratePiecesFromJSONIfNeeded(in: value); return ok("\(pieceNames.count) morceau(x) trouve(s).")
        case "folder-samples": try listSampleFiles(in: value); return ok("\(sampleFiles.count) son(s) trouve(s).")
        case "folder-soundtracks": migrateSoundTracksFromJSONIfNeeded(in: value); return ok("\(soundTrackNames.count) enregistrement(s) trouve(s).")
        case "folder-guides": migrateGuideSequencesFromJSONIfNeeded(in: value); return ok("\(guideSequenceNames.count) guide(s) trouve(s).")
        case "folder-scenes": migrateScenesFromJSONIfNeeded(in: value); return ok("\(sceneNames.count) scene(s) trouvee(s).")
        case "folder-settings": try setSettingsFolder(value); return ok("Dossier de reglages defini.")
        case "folder-prompts": try setPromptsFolder(value); return ok("Dossier de composition IA defini.")
        case "use-llm": try useLLMConnection(named: value); return ok("Connexion LLM active : \(value)")
        case "use-palette": try selectColorPalette(named: value); return ok("Palette active : \(value)")
        case "midi-mode-merged": setMIDIFusionMode(.merged); return ok("Mode MIDI : fusionne.")
        case "midi-mode-individual": setMIDIFusionMode(.individual); return ok("Mode MIDI : individuel.")
        case "web-console-start": try startWebConsole(port: Int(value) ?? 8080); return ok("Console web demarree.")
        case "web-console-stop": stopWebConsole(); return ok("Console web arretee.")
        case "vk-start": try startVirtualKeyboard(port: Int(value) ?? 8081); return ok("Clavier virtuel demarre.")
        case "vk-stop": stopVirtualKeyboard(); return ok("Clavier virtuel arrete.")
        case "lumi-root-color": try setLumiRootColor(hex: value); return ok("Couleur racine LUMI : \(value).")
        case "lumi-scale-color": try setLumiScaleColor(hex: value); return ok("Couleur gamme LUMI : \(value).")
        case "lumi-brightness":
            guard let percentage = Int(value) else { throw MenuActionError.invalidValue }
            try setLumiBrightness(percentage); return ok("Luminosite LUMI : \(percentage)%.")
        case "lumi-auto-run-on": try setLumiAutoPropagateRunMode(true); return ok("Propagation auto LUMI (mode run) activee.")
        case "lumi-auto-run-off": try setLumiAutoPropagateRunMode(false); return ok("Propagation auto LUMI (mode run) desactivee.")
        case "lumi-auto-guide-on": try setLumiAutoPropagateGuideMode(true); return ok("Propagation auto LUMI (mode guide) activee.")
        case "lumi-auto-guide-off": try setLumiAutoPropagateGuideMode(false); return ok("Propagation auto LUMI (mode guide) desactivee.")
        case "refresh-midi": refreshTracks(); return ok("Liste des instruments MIDI rafraichie.")

        // --- Scene ---
        case "track-on":
            guard let id = TrackID(wireIDText: value) else { throw MenuActionError.invalidTrack }
            try startTrack(id); return ok("Piste demarree.")
        case "track-off":
            guard let id = TrackID(wireIDText: value) else { throw MenuActionError.invalidTrack }
            stopTrack(id); return ok("Piste arretee.")
        case "track-sound-on":
            guard let id = TrackID(wireIDText: value) else { throw MenuActionError.invalidTrack }
            try setSoundEnabled(true, for: id); return ok("Son active.")
        case "track-sound-off":
            guard let id = TrackID(wireIDText: value) else { throw MenuActionError.invalidTrack }
            try setSoundEnabled(false, for: id); return ok("Son desactive.")
        case "track-instrument":
            guard let id = TrackID(wireIDText: query["track"] ?? "") else { throw MenuActionError.invalidTrack }
            try setInstrument(named: value, for: id); return ok("Instrument choisi : \(value)")
        case "track-recognition-mode":
            guard let id = TrackID(wireIDText: query["track"] ?? "") else { throw MenuActionError.invalidTrack }
            guard let mode = MicrophoneRecognitionMode(wireValueText: value) else { throw MenuActionError.invalidValue }
            try setMicrophoneRecognitionMode(mode, for: id); return ok("Mode de reconnaissance : \(value)")
        case "scene-save": try saveScene(title: value, as: value); return ok("Scene sauvegardee : \(value)")
        case "scene-load": try useScene(named: value); return ok("Scene chargee : \(value)")
        case "scene-new": newScene(title: value); return ok("Nouvelle scene : \(value)")
        case "scene-role-add":
            let roleID = try addSceneRole(name: value)
            return ok("Role ajoute : \(value) (\(roleID.uuidString))")
        case "scene-role-sound":
            guard let roleID = UUID(uuidString: query["role"] ?? "") else { throw MenuActionError.invalidValue }
            try setSceneRoleSound(roleID, soundName: value.isEmpty ? nil : value)
            return ok("Son du role mis a jour.")
        case "scene-role-listen":
            guard let roleID = UUID(uuidString: query["role"] ?? "") else { throw MenuActionError.invalidValue }
            try setSceneRoleListening(roleID, isListening: value.lowercased() == "on")
            return ok("Ecoute du role mise a jour.")
        case "scene-role-attach":
            guard let roleID = UUID(uuidString: query["role"] ?? "") else { throw MenuActionError.invalidValue }
            guard let trackID = TrackID(wireIDText: value) else { throw MenuActionError.invalidTrack }
            try attachInstrument(trackID, toRole: roleID)
            return ok("Instrument attache.")
        case "scene-role-detach":
            guard let roleID = UUID(uuidString: value) else { throw MenuActionError.invalidValue }
            try detachInstrument(fromRole: roleID)
            return ok("Instrument detache.")

        // --- Guide Musicaux ---
        case "guide-new": newGuideSequence(title: value); return ok("Nouveau guide : \(value)")
        case "guide-add-mode":
            guard let tonic = Int(query["tonic"] ?? "") else { throw MenuActionError.invalidValue }
            guard let scaleID = query["scale"], !scaleID.isEmpty else { throw MenuActionError.invalidValue }
            let progressionName = query["progression"] ?? ""
            let progression = progressionName.isEmpty ? nil :
                chordProgressionTemplates.first { $0.name.lowercased() == progressionName.lowercased() }
            try addGuideStep(ModeReference(tonic: tonic, scaleID: scaleID), chordProgression: progression)
            return ok("Etape ajoutee au guide.")
        case "guide-load": try useGuideSequence(named: value); return ok("Guide charge : \(value)")
        case "guide-save": try saveGuideSequence(); return ok("Guide sauvegarde.")
        case "guide-save-as": try saveGuideSequence(as: value); return ok("Guide sauvegarde : \(value)")
        case "guide-start": try startGuide(atStepIndex: 0); return ok("Guide demarre.")
        case "guide-stop": stopGuide(); return ok("Guide arrete.")

        // --- Enregistrement ---
        case "record-start":
            let ids = Set(value.split(separator: " ").compactMap { TrackID(wireIDText: String($0)) })
            try startRecording(title: "Enregistrement", tracks: ids); return ok("Enregistrement demarre.")
        case "record-stop":
            let soundTrack = try stopRecording()
            return ok("Enregistrement termine : \(soundTrack.events.count) evenement(s).")
        case "soundtrack-play": try playSoundTrack(); return ok("Lecture de l'enregistrement demarree.")
        case "soundtrack-load": try useSoundTrack(named: value); return ok("Enregistrement charge : \(value)")
        case "soundtrack-save": try saveSoundTrack(); return ok("Enregistrement sauvegarde.")
        case "soundtrack-save-as": try saveSoundTrack(as: value); return ok("Enregistrement sauvegarde : \(value)")
        case "soundtrack-compose":
            let count = Int(query["count"] ?? "") ?? 1
            let paths = try composeSoundTrackToPieces(candidateCount: count, title: value.isEmpty ? nil : value)
            return ok("Morceau(x) compose(s) : \(paths.joined(separator: ", "))")
        case "soundtrack-framing-set": setSoundTrackFramingSentence(value); return ok("Phrase de cadrage modifiee.")
        case "soundtrack-framing-save": try saveSoundTrackFramingSentence(as: value); return ok("Phrase de cadrage sauvegardee : \(value)")
        case "soundtrack-framing-load": try useSoundTrackFramingSentence(named: value); return ok("Phrase de cadrage chargee : \(value)")
        case "soundtrack-framing-reset": resetSoundTrackFramingSentence(); return ok("Phrase de cadrage reinitialisee.")
        case "soundtrack-instructions-set": setSoundTrackCompositionInstructions(value.isEmpty ? nil : value); return ok("Indications de style modifiees.")
        case "soundtrack-instructions-save": try saveSoundTrackCompositionInstructions(as: value); return ok("Indications sauvegardees : \(value)")
        case "soundtrack-instructions-load": try useSoundTrackCompositionInstructions(named: value); return ok("Indications chargees : \(value)")
        case "soundtrack-instructions-reset": resetSoundTrackCompositionInstructions(); return ok("Indications reinitialisees.")
        case "soundtrack-prompt-export": try exportSoundTrackCompositionPrompt(as: value); return ok("Prompt exporte : \(value)")

        // --- Morceaux ---
        case "piece-play": try play(); return ok("Lecture demarree.")
        case "piece-sample": try loadSample(named: value); return ok("Son de lecture choisi : \(value)")
        case "piece-track-instrument":
            guard let section = Int(query["section"] ?? ""), let track = Int(query["track"] ?? "") else { throw MenuActionError.invalidValue }
            try setPieceTrackInstrument(sectionIndex: section - 1, trackIndex: track - 1, instrumentName: value.isEmpty ? nil : value)
            return ok("Instrument de piste modifie.")
        case "piece-chord-instrument":
            guard let section = Int(query["section"] ?? "") else { throw MenuActionError.invalidValue }
            try setPieceChordInstrument(sectionIndex: section - 1, instrumentName: value.isEmpty ? nil : value)
            return ok("Instrument d'accords modifie.")
        case "piece-load-demo": loadDemoPiece(); return ok("Morceau demo charge.")
        case "piece-load": try usePiece(named: value); return ok("Morceau charge : \(value)")
        case "piece-save": try savePiece(); return ok("Morceau sauvegarde.")
        case "piece-save-as": try savePiece(as: value); return ok("Morceau sauvegarde : \(value)")

        // --- Composition ---
        case "composition-describe":
            setCompositionTitle(query["title"]?.isEmpty == false ? query["title"] : nil)
            setSourceText(value)
            setAdditionalCompositionInstructions(query["instructions"]?.isEmpty == false ? query["instructions"] : nil)
            return ok("Description mise a jour.")
        case "composition-compose": try composeFromText(title: nil); return ok("Composition lancee.")
        case "composition-load": try useCompositionDescription(named: value); return ok("Description chargee : \(value)")
        case "composition-save-as": try saveCompositionDescription(as: value); return ok("Description sauvegardee : \(value)")
        case "composition-save": try saveCompositionDescription(); return ok("Description sauvegardee.")
        case "text-framing-set": setTextFramingSentence(value); return ok("Phrase de cadrage modifiee.")
        case "text-framing-save": try saveTextFramingSentence(as: value); return ok("Phrase de cadrage sauvegardee : \(value)")
        case "text-framing-load": try useTextFramingSentence(named: value); return ok("Phrase de cadrage chargee : \(value)")
        case "text-framing-reset": resetTextFramingSentence(); return ok("Phrase de cadrage reinitialisee.")
        case "text-prompt-export": try exportTextCompositionPrompt(as: value); return ok("Prompt exporte : \(value)")

        // --- Jam Session ---
        case "jam-start":
            if let pseudo = query["pseudo"], !pseudo.isEmpty { localClientName = pseudo }
            try startServer(port: Int(value) ?? 7777); return ok("Jam session demarree.")
        case "jam-stop": stopServer(); return ok("Jam session arretee.")
        case "jam-join":
            if let pseudo = query["pseudo"], !pseudo.isEmpty { localClientName = pseudo }
            guard let host = query["host"], !host.isEmpty else { throw MenuActionError.invalidValue }
            try connectToServer(host: host, port: Int(query["port"] ?? "") ?? 7777)
            return ok("Connecte.")
        case "jam-discover":
            lastDiscoveredServers = discoverServers()
            return MenuActionResult(
                ok: true, message: "\(lastDiscoveredServers.count) session(s) trouvee(s).",
                items: lastDiscoveredServers.map(\.name)
            )
        case "jam-connect-discovered":
            guard let index = Int(value), lastDiscoveredServers.indices.contains(index) else { throw MenuActionError.invalidValue }
            if let pseudo = query["pseudo"], !pseudo.isEmpty { localClientName = pseudo }
            try connectToServer(discovered: lastDiscoveredServers[index])
            return ok("Connecte a \(lastDiscoveredServers[index].name).")
        case "jam-leave": disconnectFromServer(); return ok("Deconnecte.")

        default:
            throw MenuActionError.unknownAction(action)
        }
    }

    // MARK: - Read-only structure detail (piece/composition/guide/soundtrack)
    //
    // `GET /state` and `GET /menu-lists` cover live performance state and dropdown-list
    // filenames respectively, but neither carries the actual CONTENT/STRUCTURE of what's
    // loaded — no section count, no chords-per-section, no melody notes, no staged
    // composition description, no per-step guide detail, no soundtrack events. This was a
    // real gap, not a hypothetical one: an MCP client mid-AI-composition got stuck unable to
    // answer "how many sections does this piece have, what are the melodic lines, what
    // chords are in section 2" — nothing in the existing HTTP surface could tell it. These
    // four routes are the fix, one per already-existing-but-unreadable piece of state.
    //
    // Every response struct below reuses the underlying `PieceModel`/`SoundTrackModel` types
    // UNCHANGED wherever no name resolution helps (`TimeSignature`, `RhythmStructure`,
    // `MelodicFragment`, `MelodyEvent`, `FragmentPlacement`, `PlayingStyle`,
    // `RecordedNoteEvent`) — deliberately NOT re-encoding the whole `Piece` as one opaque
    // blob (that would be zero-maintenance but leaves a caller doing pitch-class arithmetic
    // on every chord/mode itself) and NOT hand-summarizing away detail into counts either
    // (the exact mistake `pieceDetailLines()`'s track line already makes — see below). Only
    // `ModeReference`/`ChordReference` get a wrapper that adds a resolved name/label
    // alongside the raw ints — the same "label next to the raw value" shape already used by
    // `WebConsoleChordProgressionEntry` (`WebConsoleState.swift`). Per-note pitches are left
    // as raw MIDI ints on purpose: pitch-class-from-MIDI is trivial, unambiguous arithmetic,
    // unlike chord/scale identification, which is the actual source of friction — enriching
    // every note would just double payload size for no benefit.
    //
    // Kept in sync BY HAND against `Section`/`ChordEvent`/etc. if those ever gain a field —
    // same accepted trade-off as `ACTIONS` (mcp-server/server.py) vs `MENU_ACTIONS`, or
    // `SanityChecks` vs `Tests/*`: real duplication, deliberately chosen over the
    // alternatives above, not an oversight.
    //
    // Deliberately NOT added to `MENU_ACTIONS`/the web console's "Commandes" tab: these are
    // read-only displays, the same category `GET /state` already is, which also isn't a menu
    // action — that tab's scope stays "actions only" by design.

    /// `public` (not `private`), same reason as `buildWebConsoleState()`: `Tests/AppCoreTests`
    /// AND `SanityChecks` (a genuinely different module, no `@testable import`) both need to
    /// exercise the detail-building logic directly, without standing up the HTTP layer.
    public struct PieceDetailModeReference: Codable {
        public var tonic: Int
        public var scaleID: String
        public var tonicName: String
        public var scaleName: String

        init(_ reference: ModeReference) {
            tonic = reference.tonic
            scaleID = reference.scaleID
            tonicName = PitchClass(reference.tonic).name()
            scaleName = ScaleLibrary.byID(reference.scaleID)?.popularName ?? reference.scaleID
        }
    }

    public struct PieceDetailChordReference: Codable {
        public var root: Int
        public var chordTemplateID: String
        public var rootName: String
        public var label: String

        init(_ reference: ChordReference) {
            root = reference.root
            chordTemplateID = reference.chordTemplateID
            rootName = PitchClass(reference.root).name()
            label = "\(rootName)\(reference.chordTemplateID)"
        }
    }

    public struct PieceDetailModeTransition: Codable {
        public var toMode: PieceDetailModeReference
        public var pivotChords: [PieceDetailChordReference]
        public var atMeasure: Int

        init(_ transition: ModeTransition) {
            toMode = PieceDetailModeReference(transition.toMode)
            pivotChords = transition.pivotChords.map(PieceDetailChordReference.init)
            atMeasure = transition.atMeasure
        }
    }

    public struct PieceDetailChordEvent: Codable {
        public var id: String
        public var measure: Int
        public var beat: Double
        public var durationBeats: Double
        public var chord: PieceDetailChordReference
        public var inversion: Int
        public var bassOverride: Int?
        public var bassOverrideName: String?
        public var playingStyle: PlayingStyle

        init(_ event: ChordEvent) {
            id = event.id
            measure = event.measure
            beat = event.beat
            durationBeats = event.durationBeats
            chord = PieceDetailChordReference(event.chord)
            inversion = event.inversion
            bassOverride = event.bassOverride
            bassOverrideName = event.bassOverride.map { PitchClass($0).name() }
            playingStyle = event.playingStyle
        }
    }

    public struct PieceDetailTrack: Codable {
        public var id: String
        public var name: String
        public var instrument: String
        public var melodyEvents: [MelodyEvent]
        public var fragmentPlacements: [FragmentPlacement]

        init(_ track: Track) {
            id = track.id
            name = track.name
            instrument = track.instrument
            melodyEvents = track.melodyEvents
            fragmentPlacements = track.fragmentPlacements
        }
    }

    public struct PieceDetailSection: Codable {
        public var id: String
        public var name: String
        public var lengthInMeasures: Int
        public var mode: PieceDetailModeReference
        public var modeTransition: PieceDetailModeTransition?
        public var chordProgression: [PieceDetailChordEvent]
        public var tracks: [PieceDetailTrack]
        public var chordInstrument: String?

        init(_ section: Section) {
            id = section.id
            name = section.name
            lengthInMeasures = section.lengthInMeasures
            mode = PieceDetailModeReference(section.mode)
            modeTransition = section.modeTransition.map(PieceDetailModeTransition.init)
            chordProgression = section.chordProgression.map(PieceDetailChordEvent.init)
            // EVERY track, including ones with zero `melodyEvents` — the terminal's own
            // `pieceDetailLines()` silently skips those (`where !track.melodyEvents.isEmpty`),
            // which is exactly the kind of gap that caused the incident this route fixes: a
            // fragment-only track would otherwise just vanish from an LLM's view of the piece.
            tracks = section.tracks.map(PieceDetailTrack.init)
            chordInstrument = section.chordInstrument
        }
    }

    public struct PieceDetailResponse: Codable {
        public var loaded: Bool
        public var id: String?
        public var title: String?
        public var composer: String?
        public var timeSignature: TimeSignature?
        public var tempoBPM: Double?
        public var key: PieceDetailModeReference?
        public var rhythmStructure: RhythmStructure?
        public var fragments: [MelodicFragment]?
        public var sections: [PieceDetailSection]?
    }

    public func buildPieceDetail() -> PieceDetailResponse {
        guard let piece else {
            return PieceDetailResponse(
                loaded: false, id: nil, title: nil, composer: nil, timeSignature: nil,
                tempoBPM: nil, key: nil, rhythmStructure: nil, fragments: nil, sections: nil
            )
        }
        return PieceDetailResponse(
            loaded: true, id: piece.id, title: piece.title, composer: piece.composer,
            timeSignature: piece.timeSignature, tempoBPM: piece.tempoBPM,
            key: PieceDetailModeReference(piece.key), rhythmStructure: piece.rhythmStructure,
            fragments: piece.fragments, sections: piece.sections.map(PieceDetailSection.init)
        )
    }

    private func handlePieceDetailRequest() -> HTTPResponse {
        guard let data = try? JSONEncoder().encode(buildPieceDetail()) else { return .notFound() }
        return HTTPResponse(contentType: "application/json", body: data)
    }

    public struct CompositionDetailResponse: Codable {
        public var title: String?
        public var additionalInstructions: String?
        public var sourceText: String?
        public var resolvedPrompt: String?
    }

    public func buildCompositionDetail() -> CompositionDetailResponse {
        // `currentTextCompositionPrompt()`'s only throw site is "no `sourceText` yet" (see
        // its own `guard let sourceText else { throw ... }`) — already reported via
        // `sourceText` above, so `try?` silently producing `nil` here needs no separate
        // error field to explain itself.
        CompositionDetailResponse(
            title: compositionTitle, additionalInstructions: additionalCompositionInstructions,
            sourceText: sourceText, resolvedPrompt: try? currentTextCompositionPrompt()
        )
    }

    private func handleCompositionDetailRequest() -> HTTPResponse {
        guard let data = try? JSONEncoder().encode(buildCompositionDetail()) else { return .notFound() }
        return HTTPResponse(contentType: "application/json", body: data)
    }

    public struct GuideDetailStep: Codable {
        public var mode: PieceDetailModeReference
        public var chordProgressionName: String?
        public var chordProgression: [PieceDetailChordReference]?
        public var isCurrent: Bool
    }

    public struct GuideDetailResponse: Codable {
        public var loaded: Bool
        public var title: String?
        public var filePath: String?
        public var currentStepIndex: Int?
        public var steps: [GuideDetailStep]?
    }

    public func buildGuideDetail() -> GuideDetailResponse {
        guard let currentGuide else {
            return GuideDetailResponse(loaded: false, title: nil, filePath: nil, currentStepIndex: nil, steps: nil)
        }
        let steps = currentGuide.steps.enumerated().map { index, step in
            GuideDetailStep(
                mode: PieceDetailModeReference(step.mode),
                chordProgressionName: step.chordProgressionName,
                chordProgression: step.chordProgression?.map(PieceDetailChordReference.init),
                isCurrent: index == currentGuideStepIndex
            )
        }
        return GuideDetailResponse(
            loaded: true, title: currentGuide.title, filePath: currentGuideRecordID,
            currentStepIndex: currentGuideStepIndex, steps: steps
        )
    }

    private func handleGuideDetailRequest() -> HTTPResponse {
        guard let data = try? JSONEncoder().encode(buildGuideDetail()) else { return .notFound() }
        return HTTPResponse(contentType: "application/json", body: data)
    }

    public struct SoundTrackDetailResponse: Codable {
        public var loaded: Bool
        public var id: String?
        public var title: String?
        public var filePath: String?
        public var durationSeconds: Double?
        public var trackIDs: [String]?
        public var events: [RecordedNoteEvent]?
    }

    public func buildSoundTrackDetail() -> SoundTrackDetailResponse {
        guard let currentSoundTrack else {
            return SoundTrackDetailResponse(
                loaded: false, id: nil, title: nil, filePath: nil, durationSeconds: nil,
                trackIDs: nil, events: nil
            )
        }
        return SoundTrackDetailResponse(
            loaded: true, id: currentSoundTrack.id, title: currentSoundTrack.title,
            filePath: currentSoundTrackRecordID, durationSeconds: currentSoundTrack.durationSeconds,
            trackIDs: currentSoundTrack.trackIDs.sorted(), events: currentSoundTrack.events
        )
    }

    private func handleSoundTrackDetailRequest() -> HTTPResponse {
        guard let data = try? JSONEncoder().encode(buildSoundTrackDetail()) else { return .notFound() }
        return HTTPResponse(contentType: "application/json", body: data)
    }

    // MARK: - Virtual keyboard (interactive browser piano — keydown/keyup + mouse/touch)

    /// Starts a small hand-rolled HTTP server serving an interactive piano keyboard page.
    /// Unlike the web console above (a read-only mirror of `run`), this one accepts input:
    /// clicking/touching a key, or typing on the browser's own keyboard, drives
    /// `pressKey`/`releaseKey` on a `.webKeyboard(clientID:)` track — a real hardware
    /// keyboard, the terminal's typed "clavier", and any number of browser tabs can all
    /// listen/sound independently (each tab gets its own track, see
    /// `ensureWebKeyboardTrack`). Deliberately a *separate* server/page from the web console
    /// rather than a new mode bolted onto it, so that always-on read-only mirror stays
    /// simple. Both can run at once, on different ports, with no interaction between them.
    public func startVirtualKeyboard(port: Int) throws {
        guard virtualKeyboardPort == nil else { throw SessionError.virtualKeyboardAlreadyActive }
        guard let uPort = UInt16(exactly: port) else { throw HTTPServerError.invalidPort }
        let server = HTTPServer(onRequest: { [weak self] request in
            self?.handleVirtualKeyboardRequest(request) ?? .notFound()
        })
        try server.start(port: uPort)
        virtualKeyboardServer = server
        virtualKeyboardPort = port
        append("Clavier virtuel demarre sur http://localhost:\(port)")
    }

    public func stopVirtualKeyboard() {
        guard virtualKeyboardPort != nil else { return }
        virtualKeyboardServer?.stop()
        virtualKeyboardServer = nil
        virtualKeyboardPort = nil
        liveInputQueue.sync { removeAllWebKeyboardTracks() }
        append("Clavier virtuel arrete.")
    }

    // MARK: - Note color settings (persisted role colors, see NoteColorSettingsFile)

    /// See `NoteColorSettingsFile`'s own doc comment for defaults/persistence shape/why
    /// there's no editing UI yet.
    public private(set) var noteColorSettings = NoteColorSettingsFile()

    /// One-time bridge from `note-colors.json` to the SwiftData store — mirrors
    /// `migrateMicrophoneCalibrationFromJSONIfNeeded(fromJSONFile:)`.
    public func migrateNoteColorSettingsFromJSONIfNeeded(fromJSONFile path: String) {
        if let existing = try? modelContext.fetch(FetchDescriptor<NoteColorSettingsRecord>()).first {
            noteColorSettings = existing.asNoteColorSettingsFile
            return
        }
        let file: NoteColorSettingsFile
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let decoded = try? JSONDecoder().decode(NoteColorSettingsFile.self, from: data) {
            file = decoded
            append("Migrated note color settings from \(path) (original left in place).")
        } else {
            file = NoteColorSettingsFile()
        }
        modelContext.insert(NoteColorSettingsRecord(file))
        try? modelContext.save()
        noteColorSettings = file
    }

    // MARK: - LLM API keys (Keychain-backed — see `APIKeyStore`'s own doc comment)

    /// Every env-var slot that currently has a Keychain-persisted key — used by the SwiftUI
    /// "JamShack > LLM" tab to know which slot is already set, without needing the actual
    /// secret for that (see `llmAPIKey(forEnvVar:)` for the one place that reads it back).
    public private(set) var llmAPIKeyEnvVars: [String] = []

    private func refreshLLMAPIKeyEnvVars() {
        llmAPIKeyEnvVars = APIKeyStore.persistedEnvVars().sorted()
    }

    /// The persisted key for `envVar`, if any — used only to prefill the SwiftUI field with
    /// the actual value (mirrors the old `llmAPIKeys.keysByEnvVar[envVar]` lookup).
    public func llmAPIKey(forEnvVar envVar: String) -> String? {
        APIKeyStore.persistedKey(forEnvVar: envVar)
    }

    /// One-time bridge from the old plaintext `llm-api-keys.json` to the Keychain — mirrors
    /// every other `migrate...FromJSONIfNeeded` in this file (idempotent: a no-op if the
    /// Keychain already has persisted keys), with one deliberate difference: it DELETES the
    /// plaintext file once its keys are copied over, rather than leaving it in place as a
    /// migration safety net. Leaving a decommissioned plaintext secret on disk after
    /// "migrating" it would defeat the point — see `Docs/BACKLOG.md`'s "App SwiftUI
    /// (2026-07-25)" entry, which already recorded Keychain as the intended destination.
    public func migrateLLMAPIKeysFromJSONIfNeeded(fromJSONFile path: String) {
        refreshLLMAPIKeyEnvVars()
        guard llmAPIKeyEnvVars.isEmpty else { return }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let file = try? JSONDecoder().decode(LLMAPIKeysFile.self, from: data), !file.keysByEnvVar.isEmpty else { return }
        for (envVar, key) in file.keysByEnvVar {
            APIKeyStore.persist(key, forEnvVar: envVar)
        }
        try? FileManager.default.removeItem(atPath: path)
        append("Migrated \(file.keysByEnvVar.count) LLM API key(s) from \(path) into the Keychain (plaintext file removed).")
        refreshLLMAPIKeyEnvVars()
    }

    /// Stores (or clears, if `key` is empty) the API key for a given env-var slot (e.g.
    /// "ANTHROPIC_API_KEY", the value of some connection's `apiKeyEnvVar`) in the Keychain —
    /// `APIKeyStore.persist` both updates the in-memory override `LLMProvider`s actually read
    /// at call time and writes/deletes the Keychain item, so the key survives a relaunch
    /// without needing a real shell environment variable set.
    public func setLLMAPIKey(_ key: String, forEnvVar envVar: String) throws {
        APIKeyStore.persist(key.isEmpty ? nil : key, forEnvVar: envVar)
        refreshLLMAPIKeyEnvVars()
        append(key.isEmpty ? "Clef API effacee pour \(envVar)." : "Clef API mise a jour pour \(envVar).")
    }

    // MARK: - LUMI Keys settings (persisted colors/brightness/auto-propagation)

    /// See `LumiSettingsFile`'s own doc comment for defaults/persistence shape.
    public private(set) var lumiSettings = LumiSettingsFile()

    /// One-time bridge from `lumi.json` to the SwiftData store — mirrors
    /// `migrateMicrophoneCalibrationFromJSONIfNeeded(fromJSONFile:)`.
    public func migrateLumiSettingsFromJSONIfNeeded(fromJSONFile path: String) {
        if let existing = try? modelContext.fetch(FetchDescriptor<LumiSettingsRecord>()).first {
            lumiSettings = existing.asLumiSettingsFile
            return
        }
        let file: LumiSettingsFile
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let decoded = try? JSONDecoder().decode(LumiSettingsFile.self, from: data) {
            file = decoded
            append("Migrated LUMI settings from \(path) (original left in place).")
        } else {
            file = LumiSettingsFile()
        }
        modelContext.insert(LumiSettingsRecord(file))
        try? modelContext.save()
        lumiSettings = file
    }

    private func saveLumiSettings() throws {
        if let existing = try? modelContext.fetch(FetchDescriptor<LumiSettingsRecord>()).first {
            existing.rootColorHex = lumiSettings.rootColorHex
            existing.scaleColorHex = lumiSettings.scaleColorHex
            existing.brightnessPercentage = lumiSettings.brightnessPercentage
            existing.autoPropagateRunMode = lumiSettings.autoPropagateRunMode
            existing.autoPropagateGuideMode = lumiSettings.autoPropagateGuideMode
        } else {
            modelContext.insert(LumiSettingsRecord(lumiSettings))
        }
        try modelContext.save()
    }

    public func setLumiRootColor(hex: String) throws {
        guard LumiColorHex.rgb(hex) != nil else { throw SessionError.invalidLumiColorHex }
        lumiSettings.rootColorHex = hex
        try saveLumiSettings()
        append("Couleur racine LUMI : \(hex).")
    }

    public func setLumiScaleColor(hex: String) throws {
        guard LumiColorHex.rgb(hex) != nil else { throw SessionError.invalidLumiColorHex }
        lumiSettings.scaleColorHex = hex
        try saveLumiSettings()
        append("Couleur gamme LUMI : \(hex).")
    }

    public func setLumiBrightness(_ percentage: Int) throws {
        guard (0...100).contains(percentage) else { throw SessionError.invalidLumiBrightness }
        lumiSettings.brightnessPercentage = percentage
        try saveLumiSettings()
        append("Luminosite LUMI : \(percentage)%.")
    }

    public func setLumiAutoPropagateRunMode(_ enabled: Bool) throws {
        lumiSettings.autoPropagateRunMode = enabled
        try saveLumiSettings()
        append("Propagation auto LUMI (mode run) : \(enabled ? "activee" : "desactivee").")
    }

    public func setLumiAutoPropagateGuideMode(_ enabled: Bool) throws {
        lumiSettings.autoPropagateGuideMode = enabled
        try saveLumiSettings()
        append("Propagation auto LUMI (mode guide) : \(enabled ? "activee" : "desactivee").")
    }

    // MARK: - Spectrogram settings (persisted palette/note overlay)

    /// See `SpectrogramSettingsFile`'s own doc comment for defaults/persistence shape.
    public private(set) var spectrogramSettings = SpectrogramSettingsFile()

    /// One-time bridge from `spectrogram.json` to the SwiftData store — mirrors
    /// `migrateMicrophoneCalibrationFromJSONIfNeeded(fromJSONFile:)`.
    public func migrateSpectrogramSettingsFromJSONIfNeeded(fromJSONFile path: String) {
        if let existing = try? modelContext.fetch(FetchDescriptor<SpectrogramSettingsRecord>()).first {
            spectrogramSettings = existing.asSpectrogramSettingsFile
            return
        }
        let file: SpectrogramSettingsFile
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let decoded = try? JSONDecoder().decode(SpectrogramSettingsFile.self, from: data) {
            file = decoded
            append("Migrated spectrogram settings from \(path) (original left in place).")
        } else {
            file = SpectrogramSettingsFile()
        }
        modelContext.insert(SpectrogramSettingsRecord(file))
        try? modelContext.save()
        spectrogramSettings = file
    }

    private func saveSpectrogramSettings() throws {
        if let existing = try? modelContext.fetch(FetchDescriptor<SpectrogramSettingsRecord>()).first {
            existing.palette = spectrogramSettings.palette
            existing.showNoteOverlay = spectrogramSettings.showNoteOverlay
        } else {
            modelContext.insert(SpectrogramSettingsRecord(spectrogramSettings))
        }
        try modelContext.save()
    }

    public func setSpectrogramPalette(_ palette: String) throws {
        spectrogramSettings.palette = palette
        try saveSpectrogramSettings()
    }

    public func setSpectrogramShowNoteOverlay(_ enabled: Bool) throws {
        spectrogramSettings.showNoteOverlay = enabled
        try saveSpectrogramSettings()
    }

    /// Which console screen is active, for `notifyActiveScreen` — deliberately just a 3-way
    /// hint (not the terminal's own `ConsoleScreenMode`, which `AppCore` shouldn't know
    /// about): "run", "guide", or "anything else" is all the auto-propagation decision needs.
    public enum LumiAutoPropagationScreen: Equatable {
        case run
        case guide
        case other
    }

    /// Called whenever the active console screen changes (see `JamShack`'s
    /// `runConsoleScreen`) so the LUMI automatically follows `lumiSettings
    /// .autoPropagateRunMode`/`autoPropagateGuideMode` without the user needing to type
    /// `lumi-run`/`lumi-guide-sync` by hand every session. Falls back to `.piano` (via
    /// `stopLumiLiveDisplay`/`stopLumiGuideDisplay`, both of which push it on the way out —
    /// see their doc comments) whenever the relevant toggle is off, no LUMI is detected, or
    /// the active screen is neither Run nor Guide. Safe to call repeatedly with the same
    /// screen: each `start.../stop...` call underneath is itself a no-op once already in
    /// that state.
    public func notifyActiveScreen(_ screen: LumiAutoPropagationScreen) {
        switch screen {
        case .run where lumiSettings.autoPropagateRunMode:
            stopLumiGuideDisplay()
            guard let rootColor = LumiColorHex.rgb(lumiSettings.rootColorHex),
                  let scaleColor = LumiColorHex.rgb(lumiSettings.scaleColorHex) else { return }
            try? startLumiLiveDisplay(rootColor: rootColor, scaleColor: scaleColor, brightnessPercentage: lumiSettings.brightnessPercentage)
        case .guide where lumiSettings.autoPropagateGuideMode:
            stopLumiLiveDisplay()
            guard let rootColor = LumiColorHex.rgb(lumiSettings.rootColorHex),
                  let scaleColor = LumiColorHex.rgb(lumiSettings.scaleColorHex) else { return }
            try? startLumiGuideDisplay(rootColor: rootColor, scaleColor: scaleColor, brightnessPercentage: lumiSettings.brightnessPercentage)
        default:
            stopLumiLiveDisplay()
            stopLumiGuideDisplay()
        }
    }

    // MARK: - LUMI Keys guide map (static root/scale color map, see LumiGuideMap)

    /// Pushes a static "guide" color map to a LUMI Keys BLOCK: root note in `rootColor`,
    /// every other key in `scaleColor` — reacting to nothing, just showing the chosen
    /// tonic/scale until pushed again. Never touches `liveInputQueue`/any track state: this
    /// is pure outbound MIDI to an external device, not a mutation of this session's own
    /// held-note/recognition state, so it needs none of that queue's synchronization.
    ///
    /// `destinationIndex` defaults to auto-detecting the single CoreMIDI destination whose
    /// name contains "LUMI" (same heuristic as the `LumiSpike` diagnostic CLI) — pass an
    /// explicit index (from `MIDIOutputPort.destinationDescriptors()`) if that's ambiguous
    /// or wrong (e.g. more than one class-compliant MIDI device attached).
    public func pushLumiGuideMap(
        destinationIndex: Int? = nil,
        mode: ModeReference,
        rootColor: (red: UInt8, green: UInt8, blue: UInt8),
        scaleColor: (red: UInt8, green: UInt8, blue: UInt8),
        brightnessPercentage: Int = 100
    ) throws {
        guard mode.resolve() != nil else { throw SessionError.invalidModeReference }
        guard let index = destinationIndex ?? MIDIOutputPort.autoDetectedDestinationIndex(nameContains: "lumi") else {
            throw SessionError.lumiDestinationNotFound
        }
        try sendLumiMessages(
            LumiGuideMap.messages(mode: mode, rootColor: rootColor, scaleColor: scaleColor, brightnessPercentage: brightnessPercentage),
            toDestinationIndex: index
        )
        append("Carte LUMI envoyee : tonique \(PitchClass(mode.tonic).name()), gamme \(mode.scaleID).")
    }

    private func sendLumiMessages(_ messages: [[UInt8]], toDestinationIndex index: Int) throws {
        let output = try MIDIOutputPort()
        for message in messages {
            try output.send(message, toDestinationAtIndex: index)
        }
    }

    /// Sends the LUMI's own built-in "piano" display directly — bypassing
    /// `notifyActiveScreen`'s own toggles/state tracking entirely — the simplest possible
    /// smoke test: unmistakably visible on the device regardless of any color/scale
    /// configuration, and it's the very display every other LUMI feature here falls back to
    /// (see `LumiAutoPropagationScreen`'s `default` case), so if THIS doesn't show up on the
    /// device, nothing else will either. Unlike `notifyActiveScreen` (which swallows errors
    /// via `try?` on purpose — a missing LUMI shouldn't ever interrupt normal use), this
    /// surfaces a real error (no destination detected, MIDI send failed) so a "Testeur LUMI"
    /// UI can answer "is basic sending wired up at all" directly.
    /// `deviceID` overrides the SysEx envelope's own default (0x34) — see
    /// `LumiSysex.envelope`'s doc comment: this byte may be a topology-assigned ID rather
    /// than a fixed constant, meaning it can silently change after an unplug/replug, with
    /// every command afterward reaching the device but being ignored (wrong device ID, not a
    /// missing/broken connection) — exactly the "worked once, then stopped" symptom this
    /// parameter exists to let a "Testeur LUMI" UI probe for, by trying other values.
    public func testLumiPianoMode(destinationIndex: Int? = nil, deviceID: UInt8 = 0x34) throws {
        guard let index = destinationIndex ?? MIDIOutputPort.autoDetectedDestinationIndex(nameContains: "lumi") else {
            throw SessionError.lumiDestinationNotFound
        }
        try sendLumiMessages([LumiSysex.setColorMode(.piano, deviceID: deviceID)], toDestinationIndex: index)
        append("Test LUMI : mode piano envoye (ID appareil 0x\(String(deviceID, radix: 16, uppercase: true))).")
    }

    /// Every currently-visible CoreMIDI destination's display name — lets a "Testeur LUMI"
    /// UI show exactly what's detected (and under what name) without needing any
    /// `MIDIEngine` type exposed outside this module. Useful when
    /// `MIDIOutputPort.autoDetectedDestinationIndex`'s "name must contain 'lumi', must match
    /// exactly one" requirement fails and nothing explains why.
    public static func visibleMIDIDestinationNames() -> [String] {
        MIDIOutputPort.destinationDescriptors().map(\.displayName)
    }

    // MARK: - LUMI Keys live display ("run" mode — follow live recognition, else piano)

    private struct LumiDisplayConfig {
        /// `nil` when the destination was auto-detected (the common case) rather than
        /// explicitly passed by the caller.
        ///
        /// Real bug found and fixed (2026-07-25), root-caused via live protocol captures
        /// (MIDI Monitor + ROLI Dashboard) that first ruled out the device-ID byte/checksum/
        /// bit-packing as the cause of a "LUMI worked once, then stopped" report — both
        /// matched this encoder byte-for-byte, so the wire format itself was never the
        /// problem. The actual bug: `startLumiLiveDisplay`/`startLumiGuideDisplay` used to
        /// resolve `MIDIOutputPort.autoDetectedDestinationIndex(nameContains: "lumi")` ONCE
        /// and cache the resulting `Int`, then reuse that same index on every subsequent
        /// send for as long as Run/Guide mode stayed on (i.e. on every recognized chord/mode
        /// change). But that index is just a position in CoreMIDI's current destination
        /// enumeration — it can shift the moment the visible destination SET changes (any
        /// other MIDI device connecting/disconnecting, not just the LUMI itself), silently
        /// redirecting every later send to whatever device now sits at that stale index (or
        /// to nothing, if the list shrank) — exactly "worked once [while the index was still
        /// valid], then stopped [after something else changed the enumeration]". Fixed by
        /// never caching a resolved index for this ongoing case: `resolvedDestinationIndex()`
        /// re-resolves by name on every single call instead. An index the CALLER explicitly
        /// passed in (disambiguating more than one class-compliant device) is a deliberate
        /// choice and is still honored as fixed for that whole session, same as before.
        let explicitDestinationIndex: Int?
        let rootColor: (red: UInt8, green: UInt8, blue: UInt8)
        let scaleColor: (red: UInt8, green: UInt8, blue: UInt8)
        let brightnessPercentage: Int

        func resolvedDestinationIndex() -> Int? {
            explicitDestinationIndex ?? MIDIOutputPort.autoDetectedDestinationIndex(nameContains: "lumi")
        }
    }

    /// What the LUMI should currently show while live display mode is on. `.none` is an
    /// internal-only "nothing pushed yet" sentinel; the real states pushed to hardware are
    /// `.piano` (nothing recognized — LUMI's own built-in piano-style display, `ColorMode
    /// .piano`) and `.mode` (a recognized mode — `LumiGuideMap`'s root/scale color map).
    enum LumiLiveModeLastState: Equatable {
        case none
        case piano
        case mode(RecognizedMode)

        /// Picks whichever track's recognition actually reflects what's played on the LUMI:
        /// the merged MIDI track if that's listening (`.midiMerged` folds every connected
        /// MIDI source, LUMI included, into one stream), otherwise — under
        /// `MIDIFusionMode.individual`, where each port gets its own track labeled with its
        /// real device name (see `refreshTracks`'s `"MIDI : \(name)"`) — specifically the
        /// `.midiSource` track whose label names the LUMI. Deliberately NOT "the first
        /// listening track": with several MIDI devices attached in individual mode, an
        /// unrelated keyboard that happens to sort earlier must never drive the LUMI's own
        /// display. No match (LUMI not connected, or its track isn't currently listening)
        /// falls through to `.piano` — the honest "nothing to show" state — rather than
        /// silently substituting some other device's recognition.
        static func current(for tracks: [TrackInfo]) -> LumiLiveModeLastState {
            let candidate = referenceTrack(in: tracks)?.recognizedModes.first
            return candidate.map(LumiLiveModeLastState.mode) ?? .piano
        }

        private static func referenceTrack(in tracks: [TrackInfo]) -> TrackInfo? {
            if let merged = tracks.first(where: { $0.id == .midiMerged && $0.isListening }) {
                return merged
            }
            return tracks.first { track in
                guard case .midiSource = track.id, track.isListening else { return false }
                return track.label.localizedCaseInsensitiveContains("lumi")
            }
        }
    }

    /// Starts following live recognition on the LUMI: whenever the reference mode (see
    /// `LumiLiveModeLastState.current`) changes, push its root/scale color map; when nothing
    /// is recognized, fall back to LUMI's own `.piano` display instead of leaving stale
    /// colors on screen. Pushes an initial state immediately (usually `.piano`, since
    /// nothing's been played yet) rather than waiting for the first note.
    public func startLumiLiveDisplay(
        destinationIndex: Int? = nil,
        rootColor: (red: UInt8, green: UInt8, blue: UInt8),
        scaleColor: (red: UInt8, green: UInt8, blue: UInt8),
        brightnessPercentage: Int = 100
    ) throws {
        // Validates a destination exists RIGHT NOW (immediate feedback if the LUMI isn't
        // detected at all), but does NOT cache this resolved index for later sends — see
        // `LumiDisplayConfig.explicitDestinationIndex`'s doc comment for why.
        guard destinationIndex ?? MIDIOutputPort.autoDetectedDestinationIndex(nameContains: "lumi") != nil else {
            throw SessionError.lumiDestinationNotFound
        }
        liveInputQueue.sync {
            lumiLiveModeConfig = LumiDisplayConfig(explicitDestinationIndex: destinationIndex, rootColor: rootColor, scaleColor: scaleColor, brightnessPercentage: brightnessPercentage)
            lumiLiveModeLastState = .none
        }
        syncLumiLiveModeIfActive()
        append("Mode run LUMI active.")
    }

    /// Pushes `.piano` on the way out (if it was actually active — a no-op if it wasn't),
    /// so "run mode off" always means "honest piano display", never stale leftover colors.
    public func stopLumiLiveDisplay() {
        let previousIndex: Int? = liveInputQueue.sync {
            let index = lumiLiveModeConfig.flatMap { $0.resolvedDestinationIndex() }
            lumiLiveModeConfig = nil
            lumiLiveModeLastState = .none
            return index
        }
        guard let previousIndex else { return }
        do {
            try sendLumiMessages([LumiSysex.setColorMode(.piano)], toDestinationIndex: previousIndex)
        } catch {
            append("Erreur envoi LUMI (arret mode run): \(error)")
        }
        append("Mode run LUMI arrete.")
    }

    /// Called after every live MIDI/microphone event (outside `liveInputQueue.sync`, never
    /// inside it — see `lumiLiveModeConfig`'s doc comment): snapshots whatever's needed from
    /// `tracks` inside a short `liveInputQueue.sync`, decides if the reference mode actually
    /// changed, and only then does the (potentially slower) MIDI I/O outside the queue.
    private func syncLumiLiveModeIfActive() {
        let pending: (config: LumiDisplayConfig, state: LumiLiveModeLastState)? = liveInputQueue.sync {
            guard let config = lumiLiveModeConfig else { return nil }
            let newState = LumiLiveModeLastState.current(for: tracks)
            guard newState != lumiLiveModeLastState else { return nil }
            lumiLiveModeLastState = newState
            return (config, newState)
        }
        guard let pending else { return }
        guard let index = pending.config.resolvedDestinationIndex() else {
            append("Erreur envoi LUMI (mode run) : destination LUMI introuvable.")
            return
        }
        do {
            switch pending.state {
            case .mode(let mode):
                try sendLumiMessages(
                    LumiGuideMap.messages(
                        mode: ModeReference(tonic: mode.tonic.value, scaleID: mode.scaleID),
                        rootColor: pending.config.rootColor, scaleColor: pending.config.scaleColor,
                        brightnessPercentage: pending.config.brightnessPercentage
                    ),
                    toDestinationIndex: index
                )
            case .piano:
                try sendLumiMessages([LumiSysex.setColorMode(.piano)], toDestinationIndex: index)
            case .none:
                break
            }
        } catch {
            append("Erreur envoi LUMI (mode run): \(error)")
        }
    }

    // MARK: - LUMI Keys guide-screen sync (follow the Guide Musical screen's current step)

    /// What the LUMI should show for a given guide step, if any. `.none` is the internal
    /// "nothing pushed yet" sentinel (see `LumiLiveModeLastState`'s analogous doc comment);
    /// `.piano` covers both "the guide isn't running" and "the current step's scale has no
    /// native LUMI equivalent" — in both cases there's nothing sensible to color, so LUMI's
    /// own built-in piano display is the honest fallback rather than a possibly-misleading
    /// chromatic map.
    enum LumiGuideDisplayLastState: Equatable {
        case none
        case piano
        case guideMap(ModeReference)

        static func current(forStepMode reference: ModeReference?) -> LumiGuideDisplayLastState {
            guard let reference, LumiColorMap.lumiScale(forScaleID: reference.scaleID) != nil else { return .piano }
            return .guideMap(reference)
        }
    }

    /// The raw `ModeReference` (not the resolved `Mode`) of the guide's current step, if the
    /// guide is running and the step index is in range — mirrors `currentGuideStepMode()`'s
    /// exact guard, but returns the reference itself since that's what `LumiGuideDisplayLastState
    /// .current`/`LumiGuideMap.messages` need (the resolved `Mode` has already lost `scaleID`
    /// as a plain string by the time it's a `ScaleDefinition`).
    private func currentGuideStepReference() -> ModeReference? {
        guard let currentGuide, let currentGuideStepIndex, currentGuide.steps.indices.contains(currentGuideStepIndex) else { return nil }
        return currentGuide.steps[currentGuideStepIndex].mode
    }

    /// Starts following the Guide Musical screen on the LUMI: whenever the current step (or
    /// "no guide running") changes, push its root/scale color map, or LUMI's own `.piano`
    /// display if the step's scale has no native equivalent. Only ever called from the main
    /// thread (see `lumiGuideDisplayConfig`'s doc comment), so — unlike the live/"run" mode
    /// sibling above — no `liveInputQueue` involvement is needed here.
    public func startLumiGuideDisplay(
        destinationIndex: Int? = nil,
        rootColor: (red: UInt8, green: UInt8, blue: UInt8),
        scaleColor: (red: UInt8, green: UInt8, blue: UInt8),
        brightnessPercentage: Int = 100
    ) throws {
        // Validates a destination exists RIGHT NOW, without caching it for later sends — see
        // `LumiDisplayConfig.explicitDestinationIndex`'s doc comment for why.
        guard destinationIndex ?? MIDIOutputPort.autoDetectedDestinationIndex(nameContains: "lumi") != nil else {
            throw SessionError.lumiDestinationNotFound
        }
        lumiGuideDisplayConfig = LumiDisplayConfig(explicitDestinationIndex: destinationIndex, rootColor: rootColor, scaleColor: scaleColor, brightnessPercentage: brightnessPercentage)
        lumiGuideDisplayLastState = .none
        syncLumiGuideDisplayIfActive()
        append("Mode guide LUMI actif.")
    }

    /// Pushes `.piano` on the way out (if it was actually active — a no-op if it wasn't),
    /// same reasoning as `stopLumiLiveDisplay`'s own doc comment.
    public func stopLumiGuideDisplay() {
        guard let previousIndex = lumiGuideDisplayConfig?.resolvedDestinationIndex() else { return }
        lumiGuideDisplayConfig = nil
        lumiGuideDisplayLastState = .none
        do {
            try sendLumiMessages([LumiSysex.setColorMode(.piano)], toDestinationIndex: previousIndex)
        } catch {
            append("Erreur envoi LUMI (arret mode guide): \(error)")
        }
        append("Mode guide LUMI arrete.")
    }

    /// Call after anything that changes `currentGuideStepIndex` (`startGuide`, `stopGuide`,
    /// `advanceGuideStep`) — non-throwing (catches/logs its own errors) so those methods'
    /// existing signatures don't need to become `throws` just for this.
    private func syncLumiGuideDisplayIfActive() {
        guard let config = lumiGuideDisplayConfig else { return }
        let newState = LumiGuideDisplayLastState.current(forStepMode: currentGuideStepReference())
        guard newState != lumiGuideDisplayLastState else { return }
        lumiGuideDisplayLastState = newState
        guard let index = config.resolvedDestinationIndex() else {
            append("Erreur envoi LUMI (mode guide) : destination LUMI introuvable.")
            return
        }
        do {
            switch newState {
            case .guideMap(let reference):
                try sendLumiMessages(
                    LumiGuideMap.messages(mode: reference, rootColor: config.rootColor, scaleColor: config.scaleColor, brightnessPercentage: config.brightnessPercentage),
                    toDestinationIndex: index
                )
            case .piano:
                try sendLumiMessages([LumiSysex.setColorMode(.piano)], toDestinationIndex: index)
            case .none:
                break
            }
        } catch {
            append("Erreur envoi LUMI (mode guide): \(error)")
        }
    }

    /// `/` and `/app.js` need no identity (the page hasn't loaded/run its own script yet, so
    /// it has no `clientID` to send). Every other route requires `?client=<uuid>` (a random
    /// id the browser generates once and keeps in `localStorage`, so the SAME browser keeps
    /// driving the SAME track across reloads) and takes `?name=<alias>` as this connection's
    /// current display name — sent on every request rather than a separate "register" call,
    /// since this server keeps no persistent connection to notice a client ever arrived.
    private func handleVirtualKeyboardRequest(_ request: HTTPRequest) -> HTTPResponse {
        let (path, query) = Self.splitQuery(request.path)
        switch path {
        case "/": return .text(virtualKeyboardIndexHTML, contentType: "text/html; charset=utf-8")
        case "/app.js": return .text(virtualKeyboardAppJS, contentType: "application/javascript")
        default: break
        }
        guard let clientID = query["client"], !clientID.isEmpty else {
            return .text("missing ?client=<id>", contentType: "text/plain", status: 400)
        }
        let track = TrackID.webKeyboard(clientID: clientID)
        ensureWebKeyboardTrack(clientID: clientID, alias: query["name"]?.isEmpty == false ? query["name"]! : "Invite")
        switch path {
        case "/state":
            let info: TrackInfo? = liveInputQueue.sync { tracks.first { $0.id == track } }
            // `guide` is only included while a guide is actually running (unlike `wheel`,
            // below, which is now always present, mirroring the read-only console) — the
            // guide's own step list/title has no meaning at all when there's no guide.
            let guideState = buildWebConsoleGuideState()
            let isGuideActive = guideState?.isActive == true
            // Always computed now, guide or not — `buildWebConsoleWheelState` already falls
            // back through piece/track/C-Ionian on its own (see its doc comment) so this
            // never fails to produce something to click chords on. Rendering still hides the
            // mode-relative parts (diatonic boundary, active mode name, roman numerals)
            // client-side while no guide is running — see `app.js`'s own `renderWheel`.
            let listeningTracks: [TrackInfo] = liveInputQueue.sync { tracks.filter(\.isListening) }
            let wheelState = buildWebConsoleWheelState(listeningTracks: listeningTracks)
            let response = VirtualKeyboardStateResponse(
                track: info.map(self.webConsoleTrackState), guide: isGuideActive ? guideState : nil, wheel: wheelState,
                palette: activeColorPalette.colors, paletteTextColors: activeColorPalette.textColors, language: currentLanguage.rawValue,
                noteColors: WebConsoleNoteColorsState(
                    modeRootHex: noteColorSettings.modeRootHex, modeOtherHex: noteColorSettings.modeOtherHex,
                    chordRootHex: noteColorSettings.chordRootHex, chordToneHex: noteColorSettings.chordToneHex,
                    heldNoChordHex: noteColorSettings.heldNoChordHex, heldOutsideChordHex: noteColorSettings.heldOutsideChordHex
                )
            )
            guard let data = try? JSONEncoder().encode(response) else { return .notFound() }
            return HTTPResponse(contentType: "application/json", body: data)
        case "/note-on":
            guard let pitch = query["pitch"].flatMap(Int.init) else { return .text("bad pitch", contentType: "text/plain", status: 400) }
            pressKey(pitch: pitch, track: track)
            return .text("", contentType: "text/plain")
        case "/note-off":
            guard let pitch = query["pitch"].flatMap(Int.init) else { return .text("bad pitch", contentType: "text/plain", status: 400) }
            releaseKey(pitch: pitch, track: track)
            return .text("", contentType: "text/plain")
        case "/release-all":
            releaseAllKeys(track: track)
            return .text("", contentType: "text/plain")
        case "/guide-advance":
            // Global session state, not scoped to `track`/`clientID` (any client's `Tab`/
            // `Shift+Tab` moves the SAME guide for everyone watching, exactly like the
            // terminal's own left/right arrow keys on the `.guide` screen) — `?client=...` is
            // still required (see this function's own doc comment) but unused here.
            guard let delta = query["delta"].flatMap(Int.init) else { return .text("bad delta", contentType: "text/plain", status: 400) }
            advanceGuideStep(by: delta)
            return .text("", contentType: "text/plain")
        default: return .notFound()
        }
    }

    /// This server only ever needs flat query parameters (`pitch`, `client`, `name`, and — since
    /// the web console's "Menu" tab — `action`/`value`/whatever named fields each menu action
    /// takes, see `performMenuAction`) — no need for `HTTPRequest` itself to grow general
    /// query-string support for that, so this stays a small local helper rather than a change
    /// to `WebConsole`'s wire format.
    private static func splitQuery(_ path: String) -> (path: String, query: [String: String]) {
        guard let qIndex = path.firstIndex(of: "?") else { return (path, [:]) }
        let base = String(path[..<qIndex])
        var result: [String: String] = [:]
        for pair in path[path.index(after: qIndex)...].split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            result[String(parts[0])] = String(parts[1]).removingPercentEncoding ?? String(parts[1])
        }
        return (base, result)
    }

    /// Creates a fresh, already-listening track the first time `clientID` is seen, or just
    /// refreshes its display name (`alias`) on every later request — recognition doesn't
    /// depend on `isListening` at all (`updateRecognitionState` only requires the track to
    /// exist), so there's no need to touch it again once true. Mirrors
    /// `addOrUpdateRemoteTrack`'s shape for the same reason: both are tracks that come and go
    /// dynamically, unlike MIDI ports or the computer keyboard, which `refreshTracks()` owns.
    private func ensureWebKeyboardTrack(clientID: String, alias: String) {
        let id = TrackID.webKeyboard(clientID: clientID)
        liveInputQueue.sync {
            if let index = tracks.firstIndex(where: { $0.id == id }) {
                tracks[index].label = alias
            } else {
                tracks.append(TrackInfo(id: id, label: alias, isListening: true, canHaveSound: true))
                recognizers[id] = RecognitionEngine()
            }
        }
    }

    /// Drops every `.webKeyboard(...)` track regardless of client — used when the virtual
    /// keyboard server itself stops, since none of them mean anything without it. Must run
    /// inside `liveInputQueue.sync`, mirroring `removeAllRemoteTracks()`.
    private func removeAllWebKeyboardTracks() {
        let ids = tracks.compactMap { track -> TrackID? in
            if case .webKeyboard = track.id { return track.id }
            return nil
        }
        for id in ids {
            recognizers[id] = nil
            samplers[id]?.stop()
            samplers[id] = nil
        }
        tracks.removeAll { ids.contains($0.id) }
    }

    /// The mode the always-visible circle-of-fifths wheel is computed for — the first
    /// candidate (in priority order: the active guide step, the piece currently playing, the
    /// first listening track's top recognized mode) whose scale actually has a parent major
    /// key (family 1 only, see `CircleOfFifths.parentTonic(for:)`), falling back to C Ionian
    /// so the wheel is genuinely always present rather than disappearing while nothing
    /// suitable is detected.
    ///
    /// Callers need BOTH this mode's own tonic (e.g. D, for "D Dorian" — which mode-name to
    /// mark active, and where relative-degree "I" belongs) and its parent tonic (e.g. C —
    /// which 7 cells are diatonic at all) — see `CircleOfFifths.wheel(tonic:activeTonic:)`.
    private func wheelReferenceMode() -> Mode {
        let playbackMode: Mode? = playbackStateQueue.sync {
            guard isPlaying, let index = playbackCurrentChordIndex, playbackTimeline.indices.contains(index) else { return nil }
            let segment = playbackTimeline[index]
            return ScaleLibrary.byID(segment.mode.scaleID).map { Mode(tonic: PitchClass(segment.mode.tonic), scale: $0) }
        }
        let trackMode: Mode? = liveInputQueue.sync {
            for track in tracks where track.isListening {
                if let recognized = track.recognizedModes.first, let scale = ScaleLibrary.byID(recognized.scaleID) {
                    return Mode(tonic: recognized.tonic, scale: scale)
                }
            }
            return nil
        }
        for candidate in [currentGuideStepMode(), playbackMode, trackMode] {
            if let candidate, CircleOfFifths.parentTonic(for: candidate) != nil { return candidate }
        }
        return Mode(tonic: PitchClass(0), scale: ScaleLibrary.byID("ionian")!)
    }

    /// A plain triad template's quality ("Ma"/"mi"/"dim") from a possibly-extended chord
    /// template (e.g. "Ma7", "mi7b5", "7") — used to match a track's recognized chord to the
    /// specific (root, quality) wheel cell it's sounding, not just its root.
    private static func chordQuality(templateID: String) -> ChordQuality? {
        guard let intervals = ChordVocabulary.byID(templateID)?.intervalsFromRoot else { return nil }
        let set = Set(intervals)
        if set.contains(3) && set.contains(6) { return .diminished }
        if set.contains(3) { return .minor }
        if set.contains(4) { return .major }
        return nil
    }

    /// Builds the always-present circle-of-fifths wheel (see `wheelReferenceMode()`),
    /// annotating each cell with the label of every currently-listening track whose
    /// recognized chord is rooted there with a matching quality — the multi-instrument
    /// "who's playing what function right now" view.
    private func buildWebConsoleWheelState(listeningTracks: [TrackInfo]) -> WebConsoleWheelState {
        let mode = wheelReferenceMode()
        return Self.wheelState(
            forTonic: CircleOfFifths.parentTonic(for: mode)!, activeTonic: mode.tonic,
            activeModeName: mode.scale.systematicName, listeningTracks: listeningTracks
        )
    }

    /// Pure conversion from `CircleOfFifths.wheel(tonic:activeTonic:)` (`MusicTheoryKit`, no
    /// session/SwiftData dependency) to the wire-shaped `WebConsoleWheelState` — extracted from
    /// `buildWebConsoleWheelState(listeningTracks:)` so a caller with an arbitrary user-picked
    /// tonic/mode (the Mode Library's own circle-of-fifths section, not tied to whatever's
    /// currently playing/listening) can build one directly, without needing a live session's
    /// own track/playback state. `listeningTracks` defaults to none, for exactly that case.
    public static func wheelState(forTonic tonic: PitchClass, activeTonic: PitchClass? = nil, activeModeName: String, listeningTracks: [TrackInfo] = []) -> WebConsoleWheelState {
        let wheel = CircleOfFifths.wheel(tonic: tonic, activeTonic: activeTonic)
        let columns = wheel.columns.map { column -> WebConsoleWheelColumnState in
            let cells = column.cells.map { cell -> WebConsoleWheelCellState in
                let trackLabels = listeningTracks.compactMap { track -> String? in
                    guard let chord = track.recognizedChord, chord.root == cell.pitchClass,
                          Self.chordQuality(templateID: chord.chordTemplateID) == cell.quality else { return nil }
                    return track.label
                }
                return WebConsoleWheelCellState(pitchClass: cell.pitchClass.value, shape: cell.shape.rawValue, quality: cell.quality.rawValue, relativeDegree: cell.relativeDegree, isDiatonic: cell.isDiatonic, trackLabels: trackLabels)
            }
            return WebConsoleWheelColumnState(pitchClass: column.pitchClass.value, modeName: column.modeName, cells: cells)
        }
        return WebConsoleWheelState(tonic: wheel.tonic.value, activeModeName: activeModeName, columns: columns, activeColumnIndex: wheel.activeColumnIndex)
    }

    /// Builds a one-off `listeningTracks` entry for `wheelState(...)` above, for a caller that
    /// has a chord to highlight but no real `TrackInfo`/recognition data of its own — e.g. the
    /// Mode Library's "ring the chord currently playing" indicator, reusing the exact same
    /// cell-matching/outline mechanism the live recognition view already uses instead of
    /// growing a second one. Exposed here (rather than requiring the caller to import
    /// `RecognitionEngine` itself just to build a `RecognizedChord`) since this file already
    /// depends on that module.
    public static func syntheticListeningTrack(chordRoot: Int, chordTemplateID: String, label: String = "current") -> TrackInfo {
        TrackInfo(
            id: .microphone, label: label, canHaveSound: false,
            recognizedChord: RecognizedChord(root: PitchClass(chordRoot), chordTemplateID: chordTemplateID, bass: PitchClass(chordRoot), confidence: 1)
        )
    }

    /// The Guide screen's own state (see `startGuide`/`advanceGuideStep`) — entirely
    /// independent of `tracks`/`playback` above: a track's own degree-line keeps showing its
    /// own recognized mode regardless of whether a guide is running (the guide only drives
    /// its own dedicated panel/screen, both here and in `JamShack`'s `.guide` screen). The
    /// wheel itself is no longer part of this — see `buildWebConsoleWheelState()`, always
    /// present at the top level of `WebConsoleState`.
    private func buildWebConsoleGuideState() -> WebConsoleGuideState? {
        guard let currentGuide else { return nil }
        let steps = currentGuide.steps.enumerated().map { index, step in
            WebConsoleGuideStepState(label: step.mode.resolve()?.displayName ?? "?", isCurrent: index == currentGuideStepIndex)
        }
        let currentStep = currentGuideStepIndex.flatMap { currentGuide.steps.indices.contains($0) ? currentGuide.steps[$0] : nil }
        guard let mode = currentGuideStepMode() else {
            return WebConsoleGuideState(
                isActive: false, steps: steps, currentStepIndex: nil, currentModeTones: [], heldPitches: [],
                currentChordProgressionName: nil, currentChordProgression: [],
                currentChordIndex: nil, currentChordRoot: nil, currentChordTones: [], currentChordGuitarDiagram: nil
            )
        }
        let heldPitches = liveInputQueue.sync { Array(Set(tracks.filter(\.isListening).flatMap(\.heldPitches))) }
        let guideChord = currentGuideChordReference()
        let (guideChordTones, _) = Self.pitchClassSets(
            forChordRoot: guideChord?.root, chordTemplateID: guideChord?.chordTemplateID, modeTonic: nil, scaleID: nil
        )
        let guitarDiagram = guideChord.flatMap { GuitarChordShape.diagram(forRoot: $0.root, chordTemplateID: $0.chordTemplateID) }
        return WebConsoleGuideState(
            isActive: true, steps: steps, currentStepIndex: currentGuideStepIndex,
            currentModeTones: mode.pitchClasses.map(\.value), heldPitches: heldPitches,
            currentChordProgressionName: currentStep?.chordProgressionName,
            currentChordProgression: (currentStep?.chordProgression ?? []).map {
                WebConsoleChordProgressionEntry(
                    label: $0.resolve()?.displayName ?? "?",
                    root: $0.root,
                    quality: Self.chordQuality(templateID: $0.chordTemplateID)?.rawValue
                )
            },
            currentChordIndex: currentGuideChordIndex, currentChordRoot: guideChord?.root, currentChordTones: guideChordTones,
            currentChordGuitarDiagram: guitarDiagram.map {
                WebConsoleGuitarChordDiagram(
                    label: $0.label, barreFret: $0.barreFret,
                    frets: $0.positions.map(\.relativeFret), fingers: $0.positions.map(\.finger)
                )
            }
        )
    }

    /// One listening track's state, transposed from `TrackInfo`'s structured recognition into
    /// the flat pitch-class sets/labels the browser needs — same computation
    /// `renderTrackKeyboard`/`chordDisplayText`/`modesDisplayText` do in `JamShack/main.swift`
    /// for the terminal's own keyboard, just producing data instead of ANSI text.
    private func webConsoleTrackState(_ track: TrackInfo) -> WebConsoleTrackState {
        let (chordTones, modeTones) = Self.pitchClassSets(
            forChordRoot: track.recognizedChord?.root.value, chordTemplateID: track.recognizedChord?.chordTemplateID,
            modeTonic: track.recognizedModes.first?.tonic.value, scaleID: track.recognizedModes.first?.scaleID
        )
        let chordLabel = track.recognizedChord.map(Self.describe) ?? (track.remoteChordDisplay)
        let modesLabel = !track.recognizedModes.isEmpty ? track.recognizedModes.map(Self.describe).joined(separator: ", ") : track.remoteModesDisplay
        return WebConsoleTrackState(
            id: Self.webConsoleTrackIDText(track.id), label: track.label, owner: track.ownerName,
            isListening: track.isListening, canHaveSound: track.canHaveSound, soundEnabled: track.soundEnabled,
            instrumentName: track.instrumentName,
            heldPitches: Array(track.heldPitches),
            chordRoot: track.recognizedChord?.root.value, chordTones: chordTones, modeTones: modeTones,
            chordLabel: chordLabel, modesLabel: modesLabel,
            microphoneLevel: track.id == .microphone ? track.microphoneInputLevel : nil,
            recognitionMode: track.id == .microphone ? Self.describe(track.microphoneRecognitionMode) : nil,
            recentChordEvents: recentChordEvents[track.id] ?? []
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
            // Degree-ordered (index 0 = degree 1), not a `Set` — the web console's degree-line
            // badges rely on `modeTones[i]` meaning "degree i+1".
            modeTones = Mode(tonic: PitchClass(modeTonic), scale: scale).pitchClasses.map(\.value)
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

    /// Joins a collaborative session over Game Center's matchmaking instead of connecting to
    /// a local-network host/port — same "client" logic as `connectToServer` (announces
    /// `hello` + every already-listening local track right away, so joining mid-session
    /// doesn't require re-toggling anything). `match` must already be a real, connected
    /// `GKMatch` — see `startGameCenterServer(with:)`'s own doc comment for why obtaining one
    /// is a UI-layer concern, not this session's.
    public func joinGameCenterSession(with match: GKMatch) throws {
        guard networkRole == .standalone else { throw SessionError.networkRoleAlreadyActive }
        let transport = GameCenterTransport(
            match: match, role: .participant,
            onMessage: { [weak self] _, message in self?.handleClientMessage(message) },
            onDisconnect: { [weak self] _ in self?.handleServerDisconnected() }
        )
        netClient = transport
        let organizerName = match.players.first?.displayName ?? "Game Center"
        networkRole = .gameCenterClient(description: organizerName)
        for message in initialClientMessages() { transport.send(message) }
        append("Connecte a la session Game Center de \(organizerName).")
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
        guard networkRole.isClientRole else { return }
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
        guard networkRole.isServerRole, let netServer else { return }
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
        guard networkRole.isClientRole, let netClient, let wireID = track.id.wireIDText else { return }
        netClient.send(NetMessage(kind: .trackAnnounce, clientID: localClientID, trackID: wireID, label: track.label, canHaveSound: track.canHaveSound))
    }

    private func unannounceTrackToServerIfClient(_ id: TrackID) {
        guard networkRole.isClientRole, let netClient, let wireID = id.wireIDText else { return }
        netClient.send(NetMessage(kind: .trackUnannounce, clientID: localClientID, trackID: wireID))
    }

    private func forwardNoteEventToServerIfClient(track: TrackID, isNoteOn: Bool, pitch: Int, velocity: Int, channel: Int) {
        guard networkRole.isClientRole, let netClient, let wireID = track.wireIDText else { return }
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
        currentSoundTrackRecordID = nil
        append("Enregistrement arrete : \(soundTrack.events.count) evenement(s), \(String(format: "%.1f", soundTrack.durationSeconds))s.")
        return soundTrack
    }

    private static let supportedSoundTrackExtensions: Set<String> = ["json"]

    /// Raw file I/O, unchanged in behavior — kept for the CLI's explicit-path
    /// `save-soundtrack <path>` verb and as the migration itself reuses. NOT the primary
    /// persistence path anymore (see `useSoundTrack`/`saveSoundTrack(as:)` below).
    public func loadSoundTrack(fromJSONFile path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try JSONDecoder().decode(SoundTrack.self, from: data)
        currentSoundTrack = decoded
        currentSoundTrackRecordID = nil
        append("Loaded soundtrack from \(path): \(decoded.title)")
    }

    public func saveSoundTrack(toJSONFile path: String) throws {
        guard let currentSoundTrack else { throw SessionError.noSoundTrackRecorded }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(currentSoundTrack)
        try data.write(to: URL(fileURLWithPath: path))
        append("Saved soundtrack to \(path).")
    }

    /// Every soundtrack's title currently in the SwiftData store, sorted — mirrors
    /// `guideSequenceNames`. Refreshed after every migrate/insert/update/delete.
    public private(set) var soundTrackNames: [String] = []

    private func refreshSoundTrackNames() {
        soundTrackNames = ((try? modelContext.fetch(FetchDescriptor<SoundTrackRecord>())) ?? []).map(\.title).sorted()
    }

    /// One-time bridge from a folder of `.json` soundtrack files to the SwiftData store —
    /// mirrors `migrateGuideSequencesFromJSONIfNeeded`: a no-op if the store already has
    /// soundtracks, otherwise migrates every `.json` found in `folderPath` (never deleting the
    /// originals). No "seed built-ins" — soundtracks have none.
    public func migrateSoundTracksFromJSONIfNeeded(in folderPath: String) {
        refreshSoundTrackNames()
        guard soundTrackNames.isEmpty else { return }

        let folderURL = URL(fileURLWithPath: folderPath)
        let jsonFiles = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil))?
            .filter { Self.supportedSoundTrackExtensions.contains($0.pathExtension.lowercased()) } ?? []
        var migrated = 0
        for fileURL in jsonFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let soundTrack = try? JSONDecoder().decode(SoundTrack.self, from: data) else { continue }
            modelContext.insert(SoundTrackRecord(soundTrack))
            migrated += 1
        }
        if migrated > 0 {
            try? modelContext.save()
            append("Migrated \(migrated) soundtrack(s) from \(folderPath) (originals left in place).")
        }
        refreshSoundTrackNames()
    }

    /// Loads a soundtrack by title from the SwiftData store — replaces the old folder-based
    /// `loadSoundTrack(named:)`. First match wins if two records share a title (same
    /// tolerance `useLLMConnection(named:)`/`useGuideSequence(named:)` already accept).
    public func useSoundTrack(named name: String) throws {
        let descriptor = FetchDescriptor<SoundTrackRecord>(predicate: #Predicate { $0.title == name })
        guard let record = try? modelContext.fetch(descriptor).first, let soundTrack = record.asSoundTrack else {
            throw SessionError.invalidSoundTrackIndex
        }
        currentSoundTrack = soundTrack
        currentSoundTrackRecordID = record.id
        append("Loaded soundtrack: \(soundTrack.title)")
    }

    /// Convenience over `useSoundTrack(named:)` using the 0-based position in `soundTrackNames`.
    public func useSoundTrack(atIndex index: Int) throws {
        guard soundTrackNames.indices.contains(index) else { throw SessionError.invalidSoundTrackIndex }
        try useSoundTrack(named: soundTrackNames[index])
    }

    /// Re-saves `currentSoundTrack` to whichever record it was last loaded from/saved to
    /// (`currentSoundTrackRecordID`) — updates that exact record even if the title has since
    /// changed (unlike `saveSoundTrack(as:)`, which addresses by title). Fails if that's
    /// never happened yet — use `saveSoundTrack(as:)` for a first save.
    public func saveSoundTrack() throws {
        guard let currentSoundTrack else { throw SessionError.noSoundTrackRecorded }
        guard let currentSoundTrackRecordID else { throw SessionError.noCurrentSoundTrackFile }
        let descriptor = FetchDescriptor<SoundTrackRecord>(predicate: #Predicate { $0.id == currentSoundTrackRecordID })
        guard let record = try? modelContext.fetch(descriptor).first else { throw SessionError.noCurrentSoundTrackFile }
        record.title = currentSoundTrack.title
        record.durationSeconds = currentSoundTrack.durationSeconds
        record.encodedSoundTrack = (try? JSONEncoder().encode(currentSoundTrack)) ?? record.encodedSoundTrack
        try modelContext.save()
        refreshSoundTrackNames()
        append("Saved soundtrack: \(currentSoundTrack.title)")
    }

    /// Saves under a given title — "Save As". If a record with that exact title already
    /// exists, overwrites it (same "saving under an existing name silently overwrites it"
    /// behavior the old folder-based version had); otherwise inserts a new record. Adopts
    /// `name` as `currentSoundTrack`'s own title — there's no separate "filename" anymore.
    public func saveSoundTrack(as name: String) throws {
        guard var currentSoundTrack else { throw SessionError.noSoundTrackRecorded }
        currentSoundTrack.title = name
        self.currentSoundTrack = currentSoundTrack
        let descriptor = FetchDescriptor<SoundTrackRecord>(predicate: #Predicate { $0.title == name })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.durationSeconds = currentSoundTrack.durationSeconds
            existing.encodedSoundTrack = (try? JSONEncoder().encode(currentSoundTrack)) ?? existing.encodedSoundTrack
            currentSoundTrackRecordID = existing.id
        } else {
            let record = SoundTrackRecord(currentSoundTrack)
            modelContext.insert(record)
            currentSoundTrackRecordID = record.id
        }
        try modelContext.save()
        refreshSoundTrackNames()
        append("Saved soundtrack as: \(name)")
    }

    /// Deletes a stored soundtrack — new capability (the old folder-based UI had no delete
    /// button; removing a file meant using the Finder directly, which stops being possible
    /// once the data lives in a private SwiftData store).
    public func deleteSoundTrack(atIndex index: Int) throws {
        guard soundTrackNames.indices.contains(index) else { throw SessionError.invalidSoundTrackIndex }
        let name = soundTrackNames[index]
        let descriptor = FetchDescriptor<SoundTrackRecord>(predicate: #Predicate { $0.title == name })
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(record)
        try modelContext.save()
        refreshSoundTrackNames()
        append("Deleted soundtrack: \(name)")
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

    /// Stops the current soundtrack playback early — mirrors `stopPlayback()`, just for
    /// `soundTrackPlayer`/`isPlayingSoundTrack` instead of `player`/`isPlaying`. A no-op if
    /// nothing is playing.
    public func stopSoundTrackPlayback() {
        guard isPlayingSoundTrack else { return }
        soundTrackPlaybackGeneration += 1
        soundTrackPlayer.stopAllNotes()
        isPlayingSoundTrack = false
        soundTrackHeldPitches = []
        append("Lecture de la soundtrack arretee.")
    }

    /// Asks the AI module to reverse-engineer a measure-based `Piece` structure out of
    /// `currentSoundTrack`'s purely temporal recording — tempo, key, chord progression — and
    /// inserts each candidate that survives validation as its own new `PieceRecord` (reusing
    /// `LLMPieceComposer.parseAndValidate`, exactly the same validation `composeFromText()`
    /// already relies on: an invalid response is dropped with a warning, never trusted
    /// outright). Returns a display label per candidate actually saved — at least one, or
    /// throws if none survived. The last successful candidate becomes the current `piece`
    /// (ready for `show-piece`/`play`), same as `composeFromText()` does; every candidate,
    /// including earlier ones, stays in the store to inspect via `pieces`/`use-piece`.
    /// `title`, when given, overrides the LLM's own chosen title — every candidate gets the
    /// same title (multiple records CAN share a title, same tolerance `usePiece(named:)`
    /// already accepts — pick by index, via `use-piece <n>`, to disambiguate reliably), the
    /// returned label adds a "(candidat N)" suffix so a multi-candidate run's own log/display
    /// distinguishes them without that suffix polluting the piece's own stored title.
    @discardableResult
    public func composeSoundTrackToPieces(
        candidateCount: Int = 1, title: String? = nil, generate: (String, LLMConnection) throws -> String = LLMClient.generatePieceJSON
    ) throws -> [String] {
        guard let connection = currentLLMConnection else { throw SessionError.noLLMConnectionSelected }
        let prompt = try currentSoundTrackCompositionPrompt()

        let count = max(1, candidateCount)
        var savedLabels: [String] = []
        var lastRecord: PieceRecord?
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
            let record = PieceRecord(candidatePiece)
            modelContext.insert(record)
            lastRecord = record
            let suffix = count > 1 ? " (candidat \(index))" : ""
            let label = "\(candidatePiece.title)\(suffix)"
            savedLabels.append(label)
            append("Candidat \(index) sauvegarde: \(label)")
        }
        guard !savedLabels.isEmpty else { throw SessionError.llmComposeFailed(["no candidate survived validation"]) }
        try? modelContext.save()
        refreshPieceNames()
        if let lastRecord {
            piece = lastRecord.asPiece
            currentPieceRecordID = lastRecord.id
        }
        return savedLabels
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
