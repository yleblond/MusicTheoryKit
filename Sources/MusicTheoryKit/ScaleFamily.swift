/// One of the 7 families of "scales of harmonies": a base interval pattern (in semitones)
/// whose successive rotations (by degree) generate every scale in the family.
///
/// Source: Oliver Prehn, "The Scales of Harmonies" (NewJazz).
public struct ScaleFamily: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let basePattern: [Int]

    public init(id: Int, name: String, basePattern: [Int]) {
        precondition(basePattern.reduce(0, +) == 12, "A scale family's base pattern must span one octave")
        self.id = id
        self.name = name
        self.basePattern = basePattern
    }

    /// Interval steps (in semitones) of the scale starting at the given 1-based degree of this family.
    public func steps(forDegree degree: Int) -> [Int] {
        let i = (degree - 1) % basePattern.count
        return Array(basePattern[i...] + basePattern[..<i])
    }
}

public enum ScaleFamilies {
    public static let all: [Int: ScaleFamily] = Dictionary(
        uniqueKeysWithValues: [
            // Each base pattern is the literal interval sequence of that family's degree-1
            // scale (as tabulated in scales_of_harmonies.pdf) — NOT the "textbook" parent
            // scale of the family. E.g. family 2's degree 1 is Altered/Super Locrian, not
            // the ascending melodic minor itself (which is degree 2 in that table).
            ScaleFamily(id: 1, name: "Major Modes", basePattern: [2, 2, 1, 2, 2, 2, 1]),          // degree 1 = Ionian
            ScaleFamily(id: 2, name: "Melodic Minor Modes", basePattern: [1, 2, 1, 2, 2, 2, 2]),  // degree 1 = Altered
            ScaleFamily(id: 3, name: "Harmonic Minor Modes", basePattern: [2, 2, 1, 3, 1, 2, 1]), // degree 1 = Major #5
            ScaleFamily(id: 4, name: "Harmonic Major Modes", basePattern: [2, 2, 1, 2, 1, 3, 1]), // degree 1 = Harmonic Major
            ScaleFamily(id: 5, name: "Diminished Modes", basePattern: [2, 1, 2, 1, 2, 1, 2, 1]),
            ScaleFamily(id: 6, name: "Whole Tone", basePattern: [2, 2, 2, 2, 2, 2]),
            ScaleFamily(id: 7, name: "Augmented Modes", basePattern: [3, 1, 3, 1, 3, 1]),
        ].map { ($0.id, $0) }
    )

    public static func family(_ id: Int) -> ScaleFamily {
        guard let family = all[id] else {
            preconditionFailure("Unknown scale family id \(id)")
        }
        return family
    }
}
