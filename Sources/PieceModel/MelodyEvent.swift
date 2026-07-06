import Foundation

/// A directly-authored melody note (as opposed to one generated from a `FragmentPlacement`).
public struct MelodyEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var measure: Int          // 1-based
    public var beat: Double          // 1-based position within the measure
    public var durationBeats: Double
    public var pitch: Int            // absolute MIDI note number (0...127)
    public var velocity: Int         // 0...127

    public init(
        id: String = UUID().uuidString,
        measure: Int,
        beat: Double,
        durationBeats: Double,
        pitch: Int,
        velocity: Int = 100
    ) {
        self.id = id
        self.measure = measure
        self.beat = beat
        self.durationBeats = durationBeats
        self.pitch = pitch
        self.velocity = velocity
    }
}

/// Places a named `MelodicFragment` on the timeline, with the transformations described
/// in the source spec: transposition (via `basePitch`), retrograde, inversion and acceleration.
public struct FragmentPlacement: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var fragmentID: String
    public var measure: Int          // 1-based
    public var beat: Double          // 1-based position within the measure
    public var basePitch: Int        // absolute MIDI note for the fragment's first note
    public var retrograde: Bool
    /// nil = no inversion; otherwise the pivot (relative to the fragment's own shape).
    public var inversionPivot: Int?
    /// 1.0 = unchanged tempo; > 1 plays the fragment faster.
    public var accelerationFactor: Double
    public var velocity: Int         // 0...127

    public init(
        id: String = UUID().uuidString,
        fragmentID: String,
        measure: Int,
        beat: Double,
        basePitch: Int,
        retrograde: Bool = false,
        inversionPivot: Int? = nil,
        accelerationFactor: Double = 1.0,
        velocity: Int = 100
    ) {
        self.id = id
        self.fragmentID = fragmentID
        self.measure = measure
        self.beat = beat
        self.basePitch = basePitch
        self.retrograde = retrograde
        self.inversionPivot = inversionPivot
        self.accelerationFactor = accelerationFactor
        self.velocity = velocity
    }

    /// Applies this placement's transforms to the given fragment, in a fixed, well-defined
    /// order: retrograde, then inversion, then acceleration.
    public func resolvedFragment(from fragment: MelodicFragment) -> MelodicFragment {
        var resolved = fragment
        if retrograde { resolved = resolved.retrograded() }
        if let pivot = inversionPivot { resolved = resolved.inverted(aroundPivot: pivot) }
        if accelerationFactor != 1.0 { resolved = resolved.accelerated(by: accelerationFactor) }
        return resolved
    }
}
