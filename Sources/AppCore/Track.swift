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
    /// a real acoustic sound — see `ImprovSession.setSoundEnabled`.
    public let canHaveSound: Bool
    public var soundEnabled: Bool
    public var instrumentName: String?
    public var heldPitches: Set<Int>
    public var recognizedChord: RecognizedChord?
    public var recognizedModes: [RecognizedMode]
    /// Only ever populated for `.microphone` — the FFT's raw detections, kept for display
    /// alongside `heldPitches` (see `ImprovSession.handleDetectedPitches`).
    public var lastDetectedPitches: [DetectedPitch]
    /// Only meaningful for `.microphone` — its current raw input level (RMS).
    public var microphoneInputLevel: Float

    public init(
        id: TrackID, label: String, isListening: Bool = false, canHaveSound: Bool,
        soundEnabled: Bool = false, instrumentName: String? = nil, heldPitches: Set<Int> = [],
        recognizedChord: RecognizedChord? = nil, recognizedModes: [RecognizedMode] = [],
        lastDetectedPitches: [DetectedPitch] = [], microphoneInputLevel: Float = 0
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
    }
}
