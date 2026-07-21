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
/// index 0 is scale degree 1, index 1 is degree 2, etc. — this is what lets the degree-line
/// badges show each note's degree number, not just "in the mode or not".
public struct WebConsoleState: Codable {
    var lastEvent: String?
    /// `public` (unlike most fields here) so `Tests/AppCoreTests`/`SanityChecks` can read
    /// `recentChordEvents` off a track without standing up the HTTP layer just to unit-test it.
    public var tracks: [WebConsoleTrackState]
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
    /// The scene tree — same information the terminal's `scene-tree` command renders as
    /// ASCII box-drawing, see `ImprovSession.buildWebConsoleSceneState()`. Always present
    /// (not gated behind server mode), like every other top-level field here — `clients` is
    /// just empty outside `.server`.
    var scene: WebConsoleSceneState
    /// The active UI language ("fr"|"en"|"de") — see `ImprovSession.currentLanguage`. Sent on
    /// every poll (not just once), same reasoning as `palette`: a language change made via the
    /// terminal must be visible in an already-open browser tab within one refresh cycle, no
    /// reload needed.
    var language: String
    /// See `ImprovSession.lumiSettings`/`LumiSettingsFile` — sent so the web console's LUMI
    /// settings form shows the current values (and reflects a change made from the terminal
    /// menu within one refresh cycle), same reasoning as `palette`/`language`.
    var lumi: WebConsoleLumiState
    /// See `ImprovSession.noteColorSettings`/`NoteColorSettingsFile` — the client applies
    /// these as CSS custom properties (`app.js`'s `applyNoteColors`) rather than baking them
    /// into the static embedded stylesheet, so a settings-file change is visible within one
    /// refresh cycle without needing the page's own CSS regenerated per request.
    var noteColors: WebConsoleNoteColorsState
}

/// See `WebConsoleState.noteColors`'s doc comment. A flat mirror of `NoteColorSettingsFile`,
/// same "own type, not reused directly" reasoning as `WebConsoleLumiState`.
struct WebConsoleNoteColorsState: Codable {
    var modeRootHex: String
    var modeOtherHex: String
    var chordRootHex: String
    var chordToneHex: String
    var heldNoChordHex: String
    var heldOutsideChordHex: String
}

/// See `WebConsoleState.lumi`'s doc comment. A flat mirror of `LumiSettingsFile` — kept as
/// its own type (not reusing `LumiSettingsFile` directly as `Codable` here) so this file's
/// JSON-over-the-wire shape can evolve independently of the on-disk settings format.
struct WebConsoleLumiState: Codable {
    var rootColorHex: String
    var scaleColorHex: String
    var brightnessPercentage: Int
    var autoPropagateRunMode: Bool
    var autoPropagateGuideMode: Bool
}

/// See `WebConsoleState.scene`'s doc comment.
struct WebConsoleSceneState: Codable {
    /// "solo" | "serveur sur le port N" | "connecte a <description>" — same text as the
    /// terminal's `networkRoleText()`.
    var networkRoleText: String
    var webConsolePort: Int?
    var virtualKeyboardPort: Int?
    /// Every non-`.remote` track (mirrors `printSceneTree`'s "Instruments locaux" section) —
    /// reuses `WebConsoleTrackState`, the same shape `tracks` already sends.
    var localInstruments: [WebConsoleTrackState]
    /// Every currently-connected jam-session participant and their announced instruments —
    /// always empty outside `.server` (see `ImprovSession.connectedClients()`).
    var clients: [WebConsoleSceneClientState]
    /// `nil` if no scene is active — lets the client show "(aucune)" explicitly rather than
    /// just omitting the whole section, so the scene/role concept is always visibly present
    /// in the tree, not just when it happens to be in use.
    var sceneTitle: String?
    /// Every role in the active scene, attached or not — `[]` if there's no active scene.
    /// See `Sources/AppCore/Scene.swift`'s own doc comments for what a role is.
    var roles: [WebConsoleSceneRoleState]
}

struct WebConsoleSceneClientState: Codable {
    var clientID: String
    var name: String
    var instruments: [WebConsoleTrackState]
}

struct WebConsoleSceneRoleState: Codable {
    var name: String
    /// The label of whichever track is currently attached, `nil` if free — precomputed
    /// server-side, same "server resolves once, client just paints" convention as
    /// `WebConsoleTrackState.chordLabel`.
    var attachedLabel: String?
    var soundName: String?
}

public struct WebConsoleTrackState: Codable {
    /// `public` (see `WebConsoleState.tracks`'s own doc comment for why).
    public var id: String
    var label: String
    /// The owning participant's pseudo for a `.remote` track (`TrackInfo.ownerName`), `nil`
    /// for every local track — same "no need to label your own tracks with your own name"
    /// convention as the terminal's `ownerSuffix(_:)`.
    var owner: String?
    /// Unused by the Run tab (`state.tracks` only ever contains listening tracks already),
    /// but needed by the Scene tab's tree (`WebConsoleSceneState`), which lists every
    /// instrument regardless of listening state — mirrors the terminal scene tree's own
    /// "ecoute: oui/non, son: oui/non" line.
    var isListening: Bool
    var canHaveSound: Bool
    var soundEnabled: Bool
    var instrumentName: String?
    var heldPitches: [Int]
    var chordRoot: Int?
    var chordTones: [Int]
    var modeTones: [Int]
    var chordLabel: String?
    var modesLabel: String?
    var microphoneLevel: Float?
    /// Only set for `.microphone` — the current recognition mode's display text (see
    /// `ImprovSession.describe(_:)`), same gating as `microphoneLevel`.
    var recognitionMode: String?
    /// A rolling log of this track's last ~20 distinct held-pitches/chord snapshots, oldest
    /// first — appended server-side the instant the recognized state actually changes
    /// (`ImprovSession.refreshRecognition`), NOT sampled by however often a browser happens to
    /// poll `GET /state`. Exists so the web console's/virtual keyboard's staff history can't
    /// silently miss a chord that was played and released faster than the ~150-250ms poll
    /// interval — a real, reported bug when the staff instead tried to reconstruct this history
    /// client-side by diffing successive polls (see `StaticAssets.swift`/
    /// `VirtualKeyboardAssets.swift`'s own history-rendering code, which just draws this array
    /// now instead of building its own). `public` (see `WebConsoleState.tracks`'s own doc
    /// comment for why).
    public var recentChordEvents: [WebConsoleChordEvent]
}

/// One entry in `WebConsoleTrackState.recentChordEvents` — deliberately the same shape as the
/// staff's own per-event JS object (`{pitches, chordRoot, chordTones}`) so the client can just
/// draw this array with no reshaping. `public` (see `WebConsoleState.tracks`'s own doc comment
/// for why) — read-only from outside `AppCore`, constructed only via the internal memberwise
/// init `ImprovSession` itself uses, no public initializer needed.
public struct WebConsoleChordEvent: Codable {
    public var pitches: [Int]
    public var chordRoot: Int?
    public var chordTones: [Int]
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
/// independent of `WebConsoleTrackState`/`WebConsolePlaybackState`: a track's degree-line keeps
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
    /// keyboard.
    var heldPitches: [Int]
    /// The current step's attached chord progression (see `PieceModel.GuideStep`), if any —
    /// `nil`/empty otherwise. `nil` if the guide has no chord "proposed" right now (no
    /// progression on this step, or nothing navigated to yet — see
    /// `ImprovSession.currentGuideChordIndex`); otherwise the index of the current entry in
    /// `currentChordProgression`, so the client can mark it without a second lookup.
    var currentChordProgressionName: String?
    /// In progression order — same "server already formatted it, client just shows the
    /// string" convention as `WebConsoleTrackState.chordLabel`, plus `root`/`quality` so the
    /// client can also mark matching wheel cells (same shape as the `trackLabels` match in
    /// `WebConsoleWheelCellState`).
    var currentChordProgression: [WebConsoleChordProgressionEntry]
    var currentChordIndex: Int?
    /// The proposed chord's own root/tones, for the Guide panel's keyboard to color —
    /// same shape as `WebConsolePlaybackState.chordRoot`/`chordTones`. Empty/nil whenever
    /// `currentChordIndex` is nil.
    var currentChordRoot: Int?
    var currentChordTones: [Int]
    /// The proposed chord's guitar-tab diagram (see `GuitarChordShape`) — `nil` whenever
    /// `currentChordIndex` is nil, OR when it isn't (a chord IS selected) but that quality
    /// has no verified standard shape (`GuitarChordShape.diagram` itself returned `nil`) —
    /// the client shows a "no standard position" message for the latter case specifically
    /// (see `renderGuide`'s own handling), not silently nothing.
    var currentChordGuitarDiagram: WebConsoleGuitarChordDiagram?
}

/// A flat, wire-friendly mirror of `GuitarChordShape.Diagram` — `frets`/`fingers` are
/// string 6 (low E) ... string 1 (high e), same order as `GuitarChordShape.Diagram
/// .positions`, `nil` entries meaning a muted string.
struct WebConsoleGuitarChordDiagram: Codable {
    var label: String
    var barreFret: Int
    var frets: [Int?]
    var fingers: [Int?]
}

struct WebConsoleChordProgressionEntry: Codable {
    /// Pre-formatted chord label, e.g. "CMa7", "Dmi", "Bdim".
    var label: String
    var root: Int
    /// "major" | "minor" | "diminished", nil if the chord's template has no recognizable
    /// triad quality (e.g. augmented) — still shown in text, just not markable on the wheel.
    var quality: String?
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
    /// See `WebConsoleState.language`'s doc comment.
    var language: String
    /// Always present, same reasoning as `palette` — see `WebConsoleState.noteColors`'s doc
    /// comment.
    var noteColors: WebConsoleNoteColorsState
}
