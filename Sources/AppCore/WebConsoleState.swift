import Foundation

/// The JSON shape served at `GET /state` by the web console (see
/// `ImprovSession.buildWebConsoleState()`) — every value is already resolved/formatted
/// server-side (pitch classes, not raw `RecognizedChord`/`RecognizedMode`; display strings,
/// not confidence scores to re-render) so `WebConsole`'s static `app.js` only ever has to
/// paint, never re-derive recognition. Mirrors the shape `renderConsoleFrame(mode: .run)`
/// (`JamShack/main.swift`) already draws in the terminal — kept in sync by hand, documented
/// at both ends (see also the JSON contract doc comment on `webConsoleIndexHTML`/`webConsoleAppJS`
/// in `WebConsole/StaticAssets.swift`).
///
/// `modeTones` (on `WebConsoleTrackState` and `WebConsolePlaybackState`, and
/// `WebConsoleGuideState.currentModeTones`) is degree-ordered, not an arbitrary set order:
/// index 0 is scale degree 1, index 1 is degree 2, etc. — this is what lets the role-line
/// badges show each note's degree number, not just "in the mode or not".
struct WebConsoleState: Codable {
    var lastEvent: String?
    var tracks: [WebConsoleTrackState]
    var playback: WebConsolePlaybackState?
    var soundTrackPlayback: WebConsoleSoundTrackPlaybackState?
    /// Always present (not gated behind an active guide) — see `WebConsoleWheelState`.
    var wheel: WebConsoleWheelState
    var guide: WebConsoleGuideState?
    /// The active `ColorPalette`'s 12 hex colors (index 0 = C ... 11 = B) — see
    /// `ImprovSession.activeColorPalette`. Sent on every poll (not just once) so switching
    /// palettes via the menu updates any already-open browser tab within one refresh cycle,
    /// no reload needed.
    var palette: [String]
    /// Same indexing as `palette` — the legible text color to paint OVER each note's own
    /// background color (a light background needs dark text and vice versa; see
    /// `ColorPalette.textColors`'s doc comment for why this isn't purely formulaic).
    var paletteTextColors: [String]
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

/// The Guide screen's own state (see `ImprovSession.startGuide`/`advanceGuideStep`) —
/// independent of `WebConsoleTrackState`/`WebConsolePlaybackState`: a track's role-line keeps
/// showing its own recognized mode regardless of whether a guide is running.
struct WebConsoleGuideState: Codable {
    var isActive: Bool
    /// Every step's display label (e.g. "D Dorian"), the current one flagged — mirrors
    /// `WebConsoleTimelineSegment`'s "list + isCurrent" shape.
    var steps: [WebConsoleGuideStepState]
    var currentStepIndex: Int?
    /// Degree-ordered, empty when `isActive` is `false`.
    var currentModeTones: [Int]
    /// Aggregated held pitches across every listening track, for the Guide panel's own
    /// keyboard — the guide has no chord of its own, so there's no root/tone coloring here.
    var heldPitches: [Int]
}

struct WebConsoleGuideStepState: Codable {
    var label: String
    var isCurrent: Bool
}

/// The circle-of-fifths wheel, always present (not gated behind an active guide): a fixed
/// 12-column x 3-ring chord palette (see `MusicTheoryKit.CircleOfFifths`) — `tonic` (the
/// *parent* major key of whichever mode is currently most relevant; in priority order: the
/// active guide step, the piece currently playing, the first listening track's recognized
/// mode, falling back to C Ionian so the wheel never disappears — see
/// `ImprovSession.wheelReferenceMode()`) determines which 7 cells are flagged `isDiatonic`;
/// the palette itself (which chord lives at which column/ring) never changes.
struct WebConsoleWheelState: Codable {
    var tonic: Int
    /// The systematic name of the mode actually being played (e.g. "Dorian" for "D Dorian") —
    /// `app.js` marks whichever column's `modeName` equals this string as the active mode
    /// name. That column is always the *parent*'s (see `CircleOfFifthsColumn.modeName`'s doc
    /// comment) — comparing by name rather than by pitch class is what makes this land on the
    /// parent instead of the active tonic itself.
    var activeModeName: String
    /// Always 12, in fixed ascending-fifths order starting at C — never depends on `tonic`.
    var columns: [WebConsoleWheelColumnState]
    /// Index into `columns` where `pitchClass == tonic`.
    var activeColumnIndex: Int
}

struct WebConsoleWheelColumnState: Codable {
    var pitchClass: Int
    /// Non-nil for 7 of the 12 columns — see `CircleOfFifthsColumn.modeName`'s doc comment;
    /// NOT the same 7 columns as the diatonic ones.
    var modeName: String?
    /// Always 3, in fixed ring order: major, minor, diminished — each cell's own `pitchClass`
    /// may differ from this column's (see `WebConsoleWheelCellState`).
    var cells: [WebConsoleWheelCellState]
}

struct WebConsoleWheelCellState: Codable {
    /// This cell's own chord root — NOT necessarily its column's `pitchClass`: only the
    /// major cell is rooted on the column itself; minor is the column's relative minor
    /// (+9 semitones), diminished is its leading-tone diminished (+11 semitones) — see
    /// `MusicTheoryKit.CircleOfFifthsCell`.
    var pitchClass: Int
    /// "square" | "circle" — alternates by this cell's own `pitchClass` parity, no musical
    /// meaning.
    var shape: String
    /// "major" | "minor" | "diminished".
    var quality: String
    /// Relative to `tonic`, cased/marked by quality — e.g. "IV", "ii", "vii°", "bVII".
    var relativeDegree: String
    /// Whether this cell's chord is one of `tonic`'s 7 diatonic chords — the "grouping
    /// layer" highlight.
    var isDiatonic: Bool
    /// Labels of every currently-listening track whose recognized chord matches this exact
    /// root+quality — lets a multi-instrument setup see which instrument(s) are sounding
    /// which function right now.
    var trackLabels: [String]
}

/// `GET /state?client=...`'s response shape for the virtual keyboard (see
/// `ImprovSession.handleVirtualKeyboardRequest`) — deliberately a small wrapper rather than
/// reusing `WebConsoleState` wholesale: this page only ever needs ONE client's own track
/// (never the whole session's `tracks` array). `wheel` is always present, like the read-only
/// console's own — the virtual keyboard page shows it (and lets you click cells to play
/// chords) whether or not a guide is running; only `guide` itself is omitted while no guide
/// is active, since there's no step list/title to show. See `app.js`'s own `renderWheel` for
/// how it hides the mode-relative parts (diatonic boundary, roman numerals, active mode name)
/// while no guide is running, without needing a second server-side shape for that case.
struct VirtualKeyboardStateResponse: Codable {
    var track: WebConsoleTrackState?
    var guide: WebConsoleGuideState?
    var wheel: WebConsoleWheelState?
    /// Always present (unlike `guide`/`wheel`) — the degree badges need it whether or not a
    /// guide is running. See `WebConsoleState.palette`'s doc comment.
    var palette: [String]
    /// See `WebConsoleState.paletteTextColors`'s doc comment.
    var paletteTextColors: [String]
}
