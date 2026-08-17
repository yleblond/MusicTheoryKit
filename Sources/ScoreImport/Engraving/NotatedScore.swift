import Foundation

/// A rendering-ready score: ticks have been resolved into discrete notated durations and
/// measures, and pitches into VexFlow-style key strings — the shape `ScoreEngravingView`
/// (a `WKWebView` hosting VexFlow) serializes to JSON and hands to its JS renderer, which does
/// no musical reasoning of its own. Produced from a `RawScore` by `ScoreEngravingAdapter`;
/// later (role-coloring analysis) fills in each note's `colors`.
public struct NotatedScore: Codable, Equatable, Sendable {
    public var parts: [NotatedPart]

    public init(parts: [NotatedPart] = []) {
        self.parts = parts
    }
}

/// Which clef a part's stave is drawn in — chosen once from the part's overall pitch profile
/// (see `ScoreEngravingAdapter`'s `staffPlan(forPitches:)`) and held fixed for its entire
/// duration, never re-evaluated mid-piece.
public enum Clef: String, Codable, Equatable, Sendable {
    case treble
    case bass
}

public struct NotatedPart: Codable, Equatable, Sendable {
    public var id: String
    public var name: String?
    public var clef: Clef
    /// Non-nil when this staff is one half of a grand staff for a single logical track — its
    /// sibling staff (the other clef) shares the same value and is guaranteed adjacent in
    /// `NotatedScore.parts` (treble first, then bass), rendered with no extra spacing and a
    /// connecting brace (`bridge.js`) instead of as two unrelated instruments. `nil` for a
    /// standalone staff (most parts — a single clef with occasional ledger lines is normal
    /// engraving, not every part that dips outside its main register needs a grand staff; see
    /// `staffPlan(forPitches:)`'s own doc comment for the threshold).
    public var staffGroupID: String?
    /// A VexFlow key-signature spec string (e.g. `"D"`, `"F#"`, `"Bb"`) drawn at the start of
    /// every system, right after the clef — `nil` (the default, and what every existing score
    /// decodes to) means no signature, exactly like today's behavior. Only ever set by
    /// `ScoreEngravingAdapter.build(from: Piece)` (the raw-file preview path has no mode context
    /// to derive one from).
    public var keySignature: String?
    public var measures: [NotatedMeasure]

    public init(id: String, name: String? = nil, clef: Clef = .treble, staffGroupID: String? = nil, keySignature: String? = nil, measures: [NotatedMeasure] = []) {
        self.id = id
        self.name = name
        self.clef = clef
        self.staffGroupID = staffGroupID
        self.keySignature = keySignature
        self.measures = measures
    }
}

/// A chord's roman-numeral analysis, positioned to print under a specific beat of a measure —
/// see `ScoreEngravingAdapter`'s own `harmonicTimeline`, the source of these entries.
public struct ChordAnnotationEntry: Codable, Equatable, Sendable {
    /// 1-based position within the measure (matches `ChordEvent.beat`'s own convention).
    public var beat: Double
    public var chordSymbol: String
    public var romanNumeral: String
    public var isLowConfidence: Bool

    public init(beat: Double, chordSymbol: String, romanNumeral: String, isLowConfidence: Bool) {
        self.beat = beat
        self.chordSymbol = chordSymbol
        self.romanNumeral = romanNumeral
        self.isLowConfidence = isLowConfidence
    }
}

public struct NotatedMeasure: Codable, Equatable, Sendable {
    public var beatsPerMeasure: Int
    public var beatUnit: Int
    public var notes: [NotatedNote]
    /// Populated only on the top staff of a section (see `ScoreEngravingAdapter`) — a chord
    /// symbol is a harmonic event, not tied to any one instrument's own part.
    public var chordAnnotations: [ChordAnnotationEntry]

    public init(beatsPerMeasure: Int, beatUnit: Int, notes: [NotatedNote] = [], chordAnnotations: [ChordAnnotationEntry] = []) {
        self.beatsPerMeasure = beatsPerMeasure
        self.beatUnit = beatUnit
        self.notes = notes
        self.chordAnnotations = chordAnnotations
    }
}

public struct NotatedNote: Codable, Equatable, Sendable {
    public var id: String
    public var isRest: Bool
    /// VexFlow key strings, e.g. "c#/4" — empty when `isRest`. More than one entry draws as a
    /// chord (a stack of noteheads sharing one stem).
    public var keys: [String]
    /// VexFlow duration code: "w"/"h"/"q"/"8"/"16"/"32", optionally suffixed "d" for a dot.
    public var duration: String
    /// Absolute MIDI pitches, parallel to `keys` — empty when `isRest`. Kept alongside the
    /// display-only `keys` strings since role-coloring analysis reasons in MIDI pitch numbers,
    /// not letter names.
    public var pitches: [Int]
    /// CSS color strings, parallel to `pitches`/`keys` — one entry per stacked pitch, since a
    /// chord's notes can each have a different harmonic/melodic role (root vs. tone vs.
    /// neither), not one color for the whole stack. `nil` entry = the renderer's default
    /// (black); the whole array is `nil` for a rest or when no role analysis was run (e.g. the
    /// raw-file preview in `ScoreEngravingAdapter.build(from: RawScore)`).
    public var colors: [String?]?
    /// Explicit accidental glyph to draw per stacked pitch — one of `"#"`/`"b"`/`"##"`/`"bb"`/
    /// `"n"` (natural), or `nil` (nothing to draw, either because the pitch is unaltered or
    /// because the key signature already implies it and no earlier note this measure showed a
    /// different one). Parallel to `keys`/`pitches`/`colors`. The whole array is `nil` (not just
    /// each entry) when no key-signature-aware decision was made at all (the raw-file preview,
    /// `ScoreEngravingAdapter.build(from: RawScore)`) — `bridge.js` falls back to its own
    /// derive-from-the-key-string behavior in that case, exactly like before this field existed.
    public var accidentals: [String?]?
    /// This note's own absolute position in real playback time — `nil` for a rest or for the
    /// raw-file preview (`build(from: RawScore)`, which has no tempo/`Piece` context to resolve
    /// real seconds from). Lets `bridge.js` tell "the note actually sounding right now" apart
    /// from any other note sharing the same pitch elsewhere in the piece (see
    /// `window.highlightPitches`'s own doc comment) — matching by pitch value alone previously lit
    /// up every occurrence of a repeating pitch (e.g. an arpeggiated accompaniment), not just the
    /// current one.
    public var startSeconds: Double?
    public var durationSeconds: Double?

    public init(
        id: String, isRest: Bool, keys: [String] = [], duration: String, pitches: [Int] = [],
        colors: [String?]? = nil, accidentals: [String?]? = nil, startSeconds: Double? = nil, durationSeconds: Double? = nil
    ) {
        self.id = id
        self.isRest = isRest
        self.keys = keys
        self.duration = duration
        self.pitches = pitches
        self.colors = colors
        self.accidentals = accidentals
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
    }
}
