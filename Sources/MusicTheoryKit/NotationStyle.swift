/// A pluggable chord-naming convention — turns a `Chord` (a notation-neutral root + template
/// id, e.g. root C + template id `"mi7b5"`) into a display string ("Cm7b5", or, in another
/// style, "Do⁻⁷⁽ᵇ⁵⁾"/whatever that style's own convention is). Only `AngloAmericanNotationStyle`
/// ships today (per the Chord/Mode/Progression Library's confirmed v1 scope), but every
/// chord-name display in the app goes through this protocol rather than hardcoding
/// `ChordTemplate.id` directly, so a second style is a new conformance away, not a redesign.
public protocol NotationStyle: Sendable {
    /// Stable, persisted key (e.g. `"angloAmerican"`) — see `NotationStyleRegistry`/
    /// `AppCore.NotationStyleSetting`.
    var id: String { get }

    func rootName(_ pitchClass: PitchClass, preferFlats: Bool) -> String

    /// The part after the root, e.g. `"m7b5"` for template id `"mi7b5"`. Falls back to the raw
    /// template id for any quality this style doesn't have a dedicated entry for (a `chords.json`
    /// addition, or a future seeded quality nobody has taught this style about yet) — always
    /// renders *something* legible rather than an empty string.
    func qualitySuffix(_ template: ChordTemplate) -> String
}

public extension NotationStyle {
    func displayName(for chord: Chord, preferFlats: Bool = false) -> String {
        rootName(chord.root, preferFlats: preferFlats) + qualitySuffix(chord.template)
    }
}

/// The one notation style shipped in this version: standard American lead-sheet symbols (C,
/// Cm, Cmaj7, Cdim, C+...) — distinct from `ChordTemplate.id`'s own internal shorthand ("Ma",
/// "mi", "miMa7"...), which is a stable lookup key, not a display string.
public struct AngloAmericanNotationStyle: NotationStyle {
    public let id = "angloAmerican"

    public init() {}

    public func rootName(_ pitchClass: PitchClass, preferFlats: Bool) -> String {
        pitchClass.name(preferFlats: preferFlats)
    }

    /// Hand-authored for every quality in `ChordVocabulary.seed` (kept in sync by hand — same
    /// convention as `GuitarChordShapes.shapesByTemplateID`/`NotationStyle`'s own doc comment).
    private static let suffixesByTemplateID: [String: String] = [
        "Ma": "", "mi": "m", "dim": "dim", "aug": "+",
        "Ma7": "maj7", "mi7": "m7", "mi7b5": "m7b5", "7": "7",
        "Ma7#5": "maj7#5", "miMa7": "mMaj7", "dim7": "dim7", "7#5": "7#5", "7b5": "7b5",
        "5": "5", "sus2": "sus2", "sus4": "sus4", "6": "6", "mi6": "m6",
        "add9": "add9", "miAdd9": "m(add9)", "9": "9", "Ma9": "maj9", "mi9": "m9",
    ]

    public func qualitySuffix(_ template: ChordTemplate) -> String {
        Self.suffixesByTemplateID[template.id] ?? template.id
    }
}

/// Every notation style available to pick from (Settings > Notation) — a single entry today,
/// grown by adding a new `NotationStyle` conformance and listing it here.
public enum NotationStyleRegistry {
    public static let all: [any NotationStyle] = [AngloAmericanNotationStyle()]

    /// Falls back to `AngloAmericanNotationStyle` for an unknown/not-yet-migrated id, so every
    /// call site can treat this as total rather than handling `nil`.
    public static func byID(_ id: String) -> any NotationStyle {
        all.first { $0.id == id } ?? AngloAmericanNotationStyle()
    }
}
