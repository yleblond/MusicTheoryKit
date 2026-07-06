/// A note reduced to its chromatic class (0 = C ... 11 = B), independent of octave.
public struct PitchClass: Hashable, Codable, CaseIterable, Sendable {
    public let value: Int

    public init(_ value: Int) {
        self.value = ((value % 12) + 12) % 12
    }

    public static let allCases: [PitchClass] = (0..<12).map(PitchClass.init)

    public static func + (lhs: PitchClass, semitones: Int) -> PitchClass {
        PitchClass(lhs.value + semitones)
    }

    /// Interval in semitones from `self` up to `other`, in [0, 11].
    public func distance(to other: PitchClass) -> Int {
        (other.value - value + 12) % 12
    }

    private static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    public func name(preferFlats: Bool = false) -> String {
        (preferFlats ? Self.flatNames : Self.sharpNames)[value]
    }
}
