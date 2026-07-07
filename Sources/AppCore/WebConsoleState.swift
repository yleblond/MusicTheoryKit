import Foundation

/// The JSON shape served at `GET /state` by the web console (see
/// `ImprovSession.buildWebConsoleState()`) — every value is already resolved/formatted
/// server-side (pitch classes, not raw `RecognizedChord`/`RecognizedMode`; display strings,
/// not confidence scores to re-render) so `WebConsole`'s static `app.js` only ever has to
/// paint, never re-derive recognition. Mirrors the shape `renderConsoleFrame(mode: .run)`
/// (`ImprovCLI/main.swift`) already draws in the terminal — kept in sync by hand, documented
/// at both ends (see also the JSON contract doc comment on `webConsoleIndexHTML`/`webConsoleAppJS`
/// in `WebConsole/StaticAssets.swift`).
struct WebConsoleState: Codable {
    var lastEvent: String?
    var tracks: [WebConsoleTrackState]
    var playback: WebConsolePlaybackState?
    var soundTrackPlayback: WebConsoleSoundTrackPlaybackState?
}

struct WebConsoleTrackState: Codable {
    var id: String
    var label: String
    /// The owning participant's pseudo for a `.remote` track (`TrackInfo.ownerName`), `nil`
    /// for every local track — same "no need to label your own tracks with your own name"
    /// convention as the terminal's `ownerSuffix(_:)`.
    var owner: String?
    var heldPitches: [Int]
    var chordRoot: Int?
    var chordTones: [Int]
    var modeTones: [Int]
    var chordLabel: String?
    var modesLabel: String?
    var microphoneLevel: Float?
}

struct WebConsoleTimelineSegment: Codable {
    var label: String
    var isCurrent: Bool
}

struct WebConsolePlaybackState: Codable {
    var timeline: [WebConsoleTimelineSegment]
    var heldPitches: [Int]
    var chordRoot: Int?
    var chordTones: [Int]
    var modeTones: [Int]
}

struct WebConsoleSoundTrackPlaybackState: Codable {
    var heldPitches: [Int]
}
