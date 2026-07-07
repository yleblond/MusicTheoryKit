import AudioEngine
import RecognitionEngine

/// Identifies one independent live-input "piste" (track). MIDI can be heard as a single
/// merged stream or as one track per visible port, depending on `MIDIFusionMode` — see
/// `ImprovSession.setMIDIFusionMode`/`refreshTracks`.
public enum TrackID: Hashable, Sendable {
    case midiMerged
    case midiSource(Int)
    case computerKeyboard
    case microphone
    /// A track owned by another participant in a collaborative session (see
    /// `ImprovSession.startServer`/`connectToServer`) — `clientID` is that participant's
    /// persistent identity, `trackID` is the id its own local track reports itself as (e.g.
    /// "clavier", "midi:1"). Recognition for these runs on whichever machine is acting as
    /// server; sound is always a purely local decision (see `TrackInfo.canHaveSound`), never
    /// forced by the network.
    case remote(clientID: String, trackID: String)

    /// The canonical wire-format string for this track's *local* identity — what a client
    /// puts in `NetMessage.trackID` when announcing or forwarding a note event for one of
    /// its own tracks. `nil` for `.remote`: a track already received over the network never
    /// re-announces itself back out under its own separate identity.
    public var wireIDText: String? {
        switch self {
        case .midiMerged: return "midi"
        case .midiSource(let index): return "midi:\(index + 1)"
        case .computerKeyboard: return "clavier"
        case .microphone: return "micro"
        case .remote: return nil
        }
    }
}

/// Whether MIDI is heard as one merged stream (`.midiMerged`, the historical/default
/// behavior) or as one independent track per visible port (`.individual`) — see
/// `ImprovSession.setMIDIFusionMode`.
public enum MIDIFusionMode: Sendable, Equatable {
    case merged
    case individual
}

/// One live-input track's current state: whether it's being listened to, whether (and with
/// what instrument) it produces sound, and its own independent chord/mode recognition —
/// every track recognizes on its own held notes, there is no single shared set anymore.
public struct TrackInfo: Identifiable, Sendable {
    public let id: TrackID
    public var label: String
    public var isListening: Bool
    /// Always false for `.microphone`: sounding what the microphone hears through the
    /// app's own output risks audible feedback, since the microphone is already picking up
    /// a real acoustic sound — see `ImprovSession.setSoundEnabled`. Mirrored unchanged onto
    /// a `.remote` copy of a microphone track, as a deliberate simplification (see
    /// `ImprovSession.mergeRemoteSnapshot`'s doc comment).
    public let canHaveSound: Bool
    public var soundEnabled: Bool
    public var instrumentName: String?
    public var heldPitches: Set<Int>
    /// Real, structured recognition — only ever populated on whichever machine actually
    /// runs this track's `RecognitionEngine` (its owner if local, or the server if
    /// `.remote`). A client mirroring another participant's track leaves this `nil` and
    /// uses `remoteChordDisplay` instead — see that property's doc comment for why.
    public var recognizedChord: RecognizedChord?
    public var recognizedModes: [RecognizedMode]
    /// Only ever populated for `.microphone` — the FFT's raw detections, kept for display
    /// alongside `heldPitches` (see `ImprovSession.handleDetectedPitches`).
    public var lastDetectedPitches: [DetectedPitch]
    /// Only meaningful for `.microphone` — its current raw input level (RMS).
    public var microphoneInputLevel: Float
    /// Only ever populated for `.remote` tracks on a client: a ready-to-display chord
    /// summary taken straight from the server's `sync` broadcast. A `RecognizedChord` needs
    /// theory-library values (root pitch class, chord template ID) that only exist where
    /// the recognizer actually runs — reconstructing one client-side from a display string
    /// would be lossy and pointless, so the server sends the string it already formatted
    /// for its own display and every client just shows that same string verbatim.
    public var remoteChordDisplay: String?
    /// Same idea as `remoteChordDisplay`, for the mode-candidates line.
    public var remoteModesDisplay: String?
    /// Only ever populated for `.remote` tracks: the owning participant's chosen display
    /// name (`ImprovSession.localClientName`, as broadcast in `RemoteTrackSnapshot.clientName`)
    /// — `nil` for every local track (no need to label your own tracks with your own name).
    /// Lets a UI show "whose track is this" instead of just the opaque `remote:<uuid>@...` id
    /// — see `printTracks`/`renderConsoleFrame`/the web console's `owner` field.
    public var ownerName: String?

    public init(
        id: TrackID, label: String, isListening: Bool = false, canHaveSound: Bool,
        soundEnabled: Bool = false, instrumentName: String? = nil, heldPitches: Set<Int> = [],
        recognizedChord: RecognizedChord? = nil, recognizedModes: [RecognizedMode] = [],
        lastDetectedPitches: [DetectedPitch] = [], microphoneInputLevel: Float = 0,
        remoteChordDisplay: String? = nil, remoteModesDisplay: String? = nil, ownerName: String? = nil
    ) {
        self.id = id
        self.label = label
        self.isListening = isListening
        self.canHaveSound = canHaveSound
        self.soundEnabled = soundEnabled
        self.instrumentName = instrumentName
        self.heldPitches = heldPitches
        self.recognizedChord = recognizedChord
        self.recognizedModes = recognizedModes
        self.lastDetectedPitches = lastDetectedPitches
        self.microphoneInputLevel = microphoneInputLevel
        self.remoteChordDisplay = remoteChordDisplay
        self.remoteModesDisplay = remoteModesDisplay
        self.ownerName = ownerName
    }
}
