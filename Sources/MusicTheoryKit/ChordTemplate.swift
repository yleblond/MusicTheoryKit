/// A chord quality as a pitch-class set relative to its root.
public struct ChordTemplate: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let intervalsFromRoot: [Int]

    public init(id: String, intervalsFromRoot: [Int]) {
        self.id = id
        self.intervalsFromRoot = intervalsFromRoot
    }
}

/// Starting vocabulary: the chord qualities named in the "Chords" column of the scale
/// library (all 7th chords, so every scale is tied to at least one recognizable chord),
/// plus the four basic triads. The triads matter for recognition: without them, a bare
/// major/minor/diminished/augmented triad has no exact match and gets force-fit into the
/// nearest 7th chord (e.g. a plain C-E-G reported as "CMa7"). "7alt" and "6#5" are
/// intentionally omitted from the 7th chords: their tensions vary and they are not a
/// single fixed pitch-class set.
public enum ChordVocabulary {
    public static let seed: [ChordTemplate] = [
        ChordTemplate(id: "Ma", intervalsFromRoot: [0, 4, 7]),
        ChordTemplate(id: "mi", intervalsFromRoot: [0, 3, 7]),
        ChordTemplate(id: "dim", intervalsFromRoot: [0, 3, 6]),
        ChordTemplate(id: "aug", intervalsFromRoot: [0, 4, 8]),
        ChordTemplate(id: "Ma7", intervalsFromRoot: [0, 4, 7, 11]),
        ChordTemplate(id: "mi7", intervalsFromRoot: [0, 3, 7, 10]),
        ChordTemplate(id: "mi7b5", intervalsFromRoot: [0, 3, 6, 10]),
        ChordTemplate(id: "7", intervalsFromRoot: [0, 4, 7, 10]),
        ChordTemplate(id: "Ma7#5", intervalsFromRoot: [0, 4, 8, 11]),
        ChordTemplate(id: "miMa7", intervalsFromRoot: [0, 3, 7, 11]),
        ChordTemplate(id: "dim7", intervalsFromRoot: [0, 3, 6, 9]),
        ChordTemplate(id: "7#5", intervalsFromRoot: [0, 4, 8, 10]),
        ChordTemplate(id: "7b5", intervalsFromRoot: [0, 4, 6, 10]),
    ]

    private static let byIDLookup: [String: ChordTemplate] = Dictionary(
        uniqueKeysWithValues: seed.map { ($0.id, $0) }
    )

    public static func byID(_ id: String) -> ChordTemplate? {
        byIDLookup[id]
    }
}

/// A chord template anchored to a root — the object actually played/detected/suggested.
public struct Chord: Equatable, Sendable {
    public let root: PitchClass
    public let template: ChordTemplate

    public init(root: PitchClass, template: ChordTemplate) {
        self.root = root
        self.template = template
    }

    public var pitchClasses: [PitchClass] {
        template.intervalsFromRoot.map { root + $0 }
    }

    public var pitchClassSet: Set<PitchClass> {
        Set(pitchClasses)
    }

    public var displayName: String {
        "\(root.name())\(template.id)"
    }
}
