import Foundation

/// A rendering-ready score: ticks have been resolved into discrete notated durations and
/// measures, and pitches into VexFlow-style key strings — the shape `ScoreEngravingView`
/// (a `WKWebView` hosting VexFlow) serializes to JSON and hands to its JS renderer, which does
/// no musical reasoning of its own. Produced from a `RawScore` by `ScoreEngravingAdapter`;
/// later (role-coloring analysis) fills in each note's `color`.
public struct NotatedScore: Codable, Equatable, Sendable {
    public var parts: [NotatedPart]

    public init(parts: [NotatedPart] = []) {
        self.parts = parts
    }
}

public struct NotatedPart: Codable, Equatable, Sendable {
    public var id: String
    public var name: String?
    public var measures: [NotatedMeasure]

    public init(id: String, name: String? = nil, measures: [NotatedMeasure] = []) {
        self.id = id
        self.name = name
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
    /// display-only `keys` strings since downstream role analysis (phase 4) reasons in MIDI
    /// pitch numbers, not letter names.
    public var pitches: [Int]
    /// CSS color string, nil = the renderer's default (black) — set by role-coloring analysis,
    /// always nil coming straight out of `ScoreEngravingAdapter`.
    public var color: String?

    public init(id: String, isRest: Bool, keys: [String] = [], duration: String, pitches: [Int] = [], color: String? = nil) {
        self.id = id
        self.isRest = isRest
        self.keys = keys
        self.duration = duration
        self.pitches = pitches
        self.color = color
    }
}
