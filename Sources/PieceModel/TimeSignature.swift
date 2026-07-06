public struct TimeSignature: Codable, Equatable, Sendable {
    public var beatsPerMeasure: Int
    public var beatUnit: Int   // 4 = quarter note, 8 = eighth note...

    public init(beatsPerMeasure: Int, beatUnit: Int) {
        self.beatsPerMeasure = beatsPerMeasure
        self.beatUnit = beatUnit
    }

    public static let commonTime = TimeSignature(beatsPerMeasure: 4, beatUnit: 4)
}

public struct RhythmStructure: Codable, Equatable, Sendable {
    /// How many equal subdivisions each beat is divided into (4 = sixteenth notes under a quarter-note beat).
    public var subdivisionsPerBeat: Int
    /// 0 = straight, up to 1 = maximum swing (long-short ratio applied to subdivision pairs).
    public var swingFeel: Double

    public init(subdivisionsPerBeat: Int = 4, swingFeel: Double = 0) {
        self.subdivisionsPerBeat = subdivisionsPerBeat
        self.swingFeel = swingFeel
    }
}
