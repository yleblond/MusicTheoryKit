import AudioEngine
import RecognitionEngine

/// Identifies one independent live-input "piste" (track). MIDI can be heard as a single
/// merged stream or as one track per visible port, depending on `MIDIFusionMode` — see
/// `ImprovSession.setMIDIFusionMode`/`refreshTracks`.
public enum TrackID: Hashable, Sendable {
    case midiMerged
    case midiSource(Int)
    case computerKeyboard
    /// A piano keyboard rendered in a browser (see `ImprovSession.startVirtualKeyboard`) —
    /// keydown/keyup and mouse/touch on the rendered keys drive `pressKey`/`releaseKey` just
    /// like `.computerKeyboard`, but kept as its own distinct track/id: a real hardware
    /// keyboard, the terminal's typed "clavier", and a browser tab can all listen at once
    /// without fighting over the same recognizer/held-notes state. Parameterized by
    /// `clientID` (a UUID the browser generates once and keeps in `localStorage`, not the
    /// user-chosen display name — that's `TrackInfo.label` instead, see
    /// `ImprovSession.ensureWebKeyboardTrack`) so *several* browsers/tablets can each drive
    /// their own independent track against the same running server — one virtual keyboard,
    /// several players, same as several MIDI ports or several `.remote` tracks.
    case webKeyboard(clientID: String)
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
        case .webKeyboard(let clientID): return "clavier-web:\(clientID)"
        case .microphone: return "micro"
        case .remote: return nil
        }
    }

    /// The inverse of `wireIDText` for every *local* track kind (never produces `.remote` —
    /// a saved `Scene` only ever captures this machine's own tracks, see
    /// `ImprovSession.saveScene`). `nil` for anything that isn't one of those wire strings.
    public init?(wireIDText text: String) {
        switch text {
        case "midi": self = .midiMerged
        case "clavier": self = .computerKeyboard
        case "micro": self = .microphone
        default:
            if text.hasPrefix("midi:"), let n = Int(text.dropFirst(5)), n >= 1 {
                self = .midiSource(n - 1)
                return
            }
            if text.hasPrefix("clavier-web:") {
                let clientID = String(text.dropFirst("clavier-web:".count))
                guard !clientID.isEmpty else { return nil }
                self = .webKeyboard(clientID: clientID)
                return
            }
            return nil
        }
    }
}

/// Whether MIDI is heard as one merged stream (`.midiMerged`, this app's original behavior)
/// or as one independent track per visible port (`.individual`, the default since a per-port
/// track is what lets the LUMI-run-mode integration identify the LUMI's own track by name
/// — see `ImprovSession.setMIDIFusionMode`/`midiFusionMode`).
public enum MIDIFusionMode: Sendable, Equatable {
    case merged
    case individual
}

/// How a `.microphone` track turns raw FFT detections into confirmed notes — see
/// `ImprovSession.setMicrophoneRecognitionMode`. Two different techniques are offered for the
/// "one instrument voice at a time" case (flute, voice, single-line reed/brass...) and two
/// different temporal-smoothing strategies for the "several notes at once" case (piano,
/// guitar...), deliberately kept side by side rather than settling on one, so they can be
/// compared against real playing. See `FFTPitchAnalyzer.monophonicFundamentalHeuristic`/
/// `monophonicFundamentalHPS` and `MicrophonePitchStabilizer.Policy` for what each one
/// actually does.
public enum MicrophoneRecognitionMode: Sendable, Equatable, Codable {
    /// One note at a time; harmonic-vs-fundamental ambiguity resolved via a lightweight
    /// subharmonic-promotion heuristic over the top few FFT candidates.
    case monophonicHeuristic
    /// One note at a time; harmonic-vs-fundamental ambiguity resolved via a Harmonic Product
    /// Spectrum estimate — more principled, a bit more computation, same latency budget.
    case monophonicHPS
    /// Several simultaneous notes; a note-on/off is confirmed only once `windows` consecutive
    /// ~93ms analysis windows agree, damping flicker at the cost of added confirmation latency.
    case polyphonicLatched(windows: Int)
    /// Several simultaneous notes; a note-on/off is confirmed by simple majority over the
    /// last `windows` analysis windows — tolerates one dropped/aliased window without losing
    /// confirmation, unlike `.polyphonicLatched`'s strict consecutiveness requirement.
    case polyphonicSliding(windows: Int)

    /// Applied to a `.microphone` track that starts listening without an explicit mode
    /// choice: light polyphonic smoothing (a small, deliberate departure from this app's
    /// original always-unsmoothed microphone behavior), not one of the monophonic modes —
    /// nothing about a freshly-added microphone track implies it's a solo instrument.
    public static let `default`: MicrophoneRecognitionMode = .polyphonicLatched(windows: 2)

    /// The canonical wire-format string for this mode — what the terminal's `track <id> mode
    /// ...` command, the web console's fixed-option menu, and the MCP server all send/parse
    /// (mirrors `TrackID.wireIDText`/`init?(wireIDText:)`'s own convention). `windows` is
    /// appended as `:N` only when it differs from that mode's own preset default, so the
    /// common preset choices stay short while arbitrary values remain round-trippable.
    public var wireValueText: String {
        switch self {
        case .monophonicHeuristic: return "mono-heuristique"
        case .monophonicHPS: return "mono-hps"
        case .polyphonicLatched(let windows): return windows == 2 ? "poly-latched" : "poly-latched:\(windows)"
        case .polyphonicSliding(let windows): return windows == 3 ? "poly-glissant" : "poly-glissant:\(windows)"
        }
    }

    /// The inverse of `wireValueText`, also accepting an explicit `poly-latched:N`/
    /// `poly-glissant:K` suffix for arbitrary window counts (the terminal command's power-user
    /// path — the web/MCP fixed-option menu only ever sends the bare preset form). `nil` for
    /// anything not recognized, including a present-but-non-numeric suffix (a plain missing
    /// suffix falls back to that mode's own preset default — `setMicrophoneRecognitionMode` is
    /// what actually validates `windows >= 1`, not this parser).
    public init?(wireValueText text: String) {
        let parts = text.split(separator: ":", maxSplits: 1)
        guard let key = parts.first else { return nil }
        var windows: Int?
        if parts.count > 1 {
            guard let parsed = Int(parts[1]) else { return nil }
            windows = parsed
        }
        switch key {
        case "mono-heuristique": self = .monophonicHeuristic
        case "mono-hps": self = .monophonicHPS
        case "poly-latched": self = .polyphonicLatched(windows: windows ?? 2)
        case "poly-glissant": self = .polyphonicSliding(windows: windows ?? 3)
        default: return nil
        }
    }
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
    /// Only meaningful for `.microphone` — see `MicrophoneRecognitionMode`.
    public var microphoneRecognitionMode: MicrophoneRecognitionMode
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
    /// The MIDI channel (0...15) of the most recent note event seen on this track — `nil`
    /// until at least one has arrived (or always, for a track kind that isn't MIDI at all).
    /// Purely diagnostic (see `printTracks`): a MIDI port has no channel of its own, only
    /// individual messages do, so this can only ever reflect "whatever channel this device
    /// last sent on", useful for spotting/resolving a channel conflict between two devices —
    /// not a filter or a guarantee every message on this track shares one channel.
    public var lastChannel: Int?

    public init(
        id: TrackID, label: String, isListening: Bool = false, canHaveSound: Bool,
        soundEnabled: Bool = false, instrumentName: String? = nil, heldPitches: Set<Int> = [],
        recognizedChord: RecognizedChord? = nil, recognizedModes: [RecognizedMode] = [],
        lastDetectedPitches: [DetectedPitch] = [], microphoneInputLevel: Float = 0,
        microphoneRecognitionMode: MicrophoneRecognitionMode = .default,
        remoteChordDisplay: String? = nil, remoteModesDisplay: String? = nil, ownerName: String? = nil,
        lastChannel: Int? = nil
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
        self.microphoneRecognitionMode = microphoneRecognitionMode
        self.remoteChordDisplay = remoteChordDisplay
        self.remoteModesDisplay = remoteModesDisplay
        self.ownerName = ownerName
        self.lastChannel = lastChannel
    }
}
