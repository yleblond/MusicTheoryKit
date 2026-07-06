/// A single named scale/mode: a rotation (degree) of a `ScaleFamily`'s base pattern.
/// Only metadata is authored by hand; the interval content is always derived from the family,
/// so it can never drift from the source pattern.
public struct ScaleDefinition: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let familyID: Int
    public let degree: Int
    public let popularName: String
    public let systematicName: String
    public let chordSymbols: [String]

    public init(
        id: String,
        familyID: Int,
        degree: Int,
        popularName: String,
        systematicName: String,
        chordSymbols: [String]
    ) {
        self.id = id
        self.familyID = familyID
        self.degree = degree
        self.popularName = popularName
        self.systematicName = systematicName
        self.chordSymbols = chordSymbols
    }

    /// Interval steps (in semitones) between consecutive scale degrees, starting from the root.
    public var intervalSteps: [Int] {
        ScaleFamilies.family(familyID).steps(forDegree: degree)
    }

    public var noteCount: Int { intervalSteps.count }

    /// Pitch classes relative to the root (0 = root), in scale order.
    public var pitchClassesFromRoot: [Int] {
        intervalSteps.dropLast().reduce(into: [0]) { acc, step in
            acc.append((acc.last! + step) % 12)
        }
    }
}
