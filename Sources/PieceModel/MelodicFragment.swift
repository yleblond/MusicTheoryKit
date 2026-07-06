import Foundation

/// How a fragment's stored intervals are interpreted to rebuild absolute pitches.
public enum IntervalReferenceMode: String, Codable, Sendable {
    /// "Mode A": every interval is measured from the fragment's first note.
    case fromFirstNote
    /// "Mode B": every interval is measured from the previous note.
    case fromPreviousNote
}

/// A named, reusable melodic motif stored as relative intervals (semitones) rather than
/// absolute pitches, so it can be transposed, retrograded, inverted or re-timed on reuse.
public struct MelodicFragment: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var referenceMode: IntervalReferenceMode
    /// Semitone deltas; count == noteCount - 1.
    public var intervals: [Int]
    /// Duration of each note, in beats; count == noteCount.
    public var noteDurations: [Double]

    public init(
        id: String = UUID().uuidString,
        name: String,
        referenceMode: IntervalReferenceMode,
        intervals: [Int],
        noteDurations: [Double]
    ) {
        precondition(noteDurations.count == intervals.count + 1, "noteDurations must have one more entry than intervals")
        self.id = id
        self.name = name
        self.referenceMode = referenceMode
        self.intervals = intervals
        self.noteDurations = noteDurations
    }

    public var noteCount: Int { intervals.count + 1 }

    /// Absolute pitches obtained by anchoring the fragment's first note at `basePitch`.
    public func absolutePitches(basePitch: Int) -> [Int] {
        switch referenceMode {
        case .fromFirstNote:
            return [basePitch] + intervals.map { basePitch + $0 }
        case .fromPreviousNote:
            var pitches = [basePitch]
            for delta in intervals { pitches.append(pitches.last! + delta) }
            return pitches
        }
    }

    /// The fragment's melodic contour, anchored at 0 — used as a neutral coordinate space
    /// for shape-based transforms (retrograde, inversion) regardless of `referenceMode`.
    private var shape: [Int] { absolutePitches(basePitch: 0) }

    private func intervals(fromShape shape: [Int]) -> [Int] {
        switch referenceMode {
        case .fromFirstNote:
            return shape.dropFirst().map { $0 - shape[0] }
        case .fromPreviousNote:
            return zip(shape, shape.dropFirst()).map { $1 - $0 }
        }
    }

    /// Reverses note order (and durations), preserving the fragment's `referenceMode`.
    public func retrograded() -> MelodicFragment {
        let reversedShape = Array(shape.reversed())
        let normalizedShape = reversedShape.map { $0 - reversedShape[0] }
        var copy = self
        copy.id = UUID().uuidString
        copy.name = "\(name) (retrograde)"
        copy.intervals = intervals(fromShape: normalizedShape)
        copy.noteDurations = Array(noteDurations.reversed())
        return copy
    }

    /// Mirrors the melodic contour around `pivot` (relative to the fragment's own shape,
    /// where the first note sits at 0). Defaults to inverting around the first note.
    public func inverted(aroundPivot pivot: Int = 0) -> MelodicFragment {
        let invertedShape = shape.map { 2 * pivot - $0 }
        var copy = self
        copy.id = UUID().uuidString
        copy.name = "\(name) (inverted)"
        copy.intervals = intervals(fromShape: invertedShape)
        return copy
    }

    /// Scales note durations by `1 / factor`: factor > 1 plays the fragment faster.
    public func accelerated(by factor: Double) -> MelodicFragment {
        precondition(factor > 0, "acceleration factor must be positive")
        var copy = self
        copy.id = UUID().uuidString
        copy.name = "\(name) (x\(factor))"
        copy.noteDurations = noteDurations.map { $0 / factor }
        return copy
    }
}
