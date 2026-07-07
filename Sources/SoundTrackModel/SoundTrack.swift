import Foundation

/// One raw note on/off, as it actually happened during a recording — `timeSeconds` is
/// elapsed time since the recording started (not a measure/beat, unlike `PieceModel`'s
/// event types), and `trackID` is the *wire-format* id of whichever live-input track
/// produced it (e.g. "clavier", "midi:1" — see `AppCore.TrackID.wireIDText`) so a
/// multi-track recording can still tell its sources apart on playback/inspection, without
/// this model needing to depend on `AppCore` to express that.
public struct RecordedNoteEvent: Codable, Equatable, Sendable {
    public var timeSeconds: Double
    public var trackID: String
    public var isNoteOn: Bool
    public var pitch: Int
    public var velocity: Int

    public init(timeSeconds: Double, trackID: String, isNoteOn: Bool, pitch: Int, velocity: Int) {
        self.timeSeconds = timeSeconds
        self.trackID = trackID
        self.isNoteOn = isNoteOn
        self.pitch = pitch
        self.velocity = velocity
    }
}

/// A purely event-based recording of one or more live-input tracks, in real time
/// (seconds) rather than `PieceModel.Piece`'s measures/beats — deliberately a different,
/// incompatible shape: there is no tempo, no chord progression, no notion of a "measure"
/// here, just "this pitch went on/off at this many seconds in." Meant to capture an actual
/// performance faithfully; turning it into a measure-based `Piece` is a separate, lossy
/// step (see `LLMPieceComposer.buildPrompt(fromSoundTrack:)`), not something this type does.
public struct SoundTrack: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var durationSeconds: Double
    public var events: [RecordedNoteEvent]

    public init(id: String = UUID().uuidString, title: String, durationSeconds: Double, events: [RecordedNoteEvent]) {
        self.id = id
        self.title = title
        self.durationSeconds = durationSeconds
        self.events = events
    }

    /// Every distinct track id that contributed at least one event — for display ("this
    /// recording has clavier + midi:1") without scanning `events` by hand each time.
    public var trackIDs: Set<String> {
        Set(events.map(\.trackID))
    }
}
