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
    public var measures: [NotatedMeasure]

    public init(id: String, name: String? = nil, clef: Clef = .treble, staffGroupID: String? = nil, measures: [NotatedMeasure] = []) {
        self.id = id
        self.name = name
        self.clef = clef
        self.staffGroupID = staffGroupID
        self.measures = measures
    }
}

public struct NotatedMeasure: Codable, Equatable, Sendable {
    public var beatsPerMeasure: Int
    public var beatUnit: Int
    public var notes: [NotatedNote]

    public init(beatsPerMeasure: Int, beatUnit: Int, notes: [NotatedNote] = []) {
        self.beatsPerMeasure = beatsPerMeasure
        self.beatUnit = beatUnit
        self.notes = notes
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

    public init(id: String, isRest: Bool, keys: [String] = [], duration: String, pitches: [Int] = [], colors: [String?]? = nil) {
        self.id = id
        self.isRest = isRest
        self.keys = keys
        self.duration = duration
        self.pitches = pitches
        self.colors = colors
    }
}
