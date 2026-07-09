import Foundation

/// One track's saved instrument configuration within a `Scene` — deliberately not the same
/// track's live `TrackInfo` (no held pitches/recognition state, none of which makes sense to
/// "restore" later): just what a scene is actually about, whether it's listening, whether its
/// sound is on, and which sample it's loaded with.
public struct SceneTrack: Codable, Equatable, Sendable {
    /// `TrackID.wireIDText` — a local track's own wire-format id (e.g. "midi", "clavier",
    /// "midi:2"). Never a `.remote` track: a scene only ever captures this machine's own
    /// instrument setup.
    public var trackID: String
    public var isListening: Bool
    public var soundEnabled: Bool
    public var instrumentName: String?

    public init(trackID: String, isListening: Bool, soundEnabled: Bool, instrumentName: String?) {
        self.trackID = trackID
        self.isListening = isListening
        self.soundEnabled = soundEnabled
        self.instrumentName = instrumentName
    }
}

/// A saved snapshot of which tracks were listening, with which sound, at the moment it was
/// captured (see `ImprovSession.saveScene`) — a quick way back to a known instrument setup
/// (e.g. "piano solo", "full band") without re-toggling every track by hand.
public struct Scene: Codable, Equatable, Sendable {
    public var title: String
    public var tracks: [SceneTrack]

    public init(title: String, tracks: [SceneTrack] = []) {
        self.title = title
        self.tracks = tracks
    }
}
