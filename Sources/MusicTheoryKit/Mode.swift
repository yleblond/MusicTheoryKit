/// A `ScaleDefinition` anchored to a tonic — the object actually played/detected/suggested.
public struct Mode: Equatable, Sendable {
    public let tonic: PitchClass
    public let scale: ScaleDefinition

    public init(tonic: PitchClass, scale: ScaleDefinition) {
        self.tonic = tonic
        self.scale = scale
    }

    public var pitchClasses: [PitchClass] {
        scale.pitchClassesFromRoot.map { tonic + $0 }
    }

    public var pitchClassSet: Set<PitchClass> {
        Set(pitchClasses)
    }

    /// 1-based scale degree lookup, wrapping across octaves of the scale.
    public func degree(_ n: Int) -> PitchClass {
        let notes = pitchClasses
        return notes[(n - 1) % notes.count]
    }

    public var displayName: String {
        "\(tonic.name()) \(scale.popularName)"
    }
}
