/// A conventional major-key signature: how many sharps or flats appear at the clef. Only
/// meaningful for a tonic that has one universally-taught convention — pitch class 1 (C#/Db)
/// is the one tonic with two equally valid spellings (7 sharps vs. 5 flats); this picks Db (5
/// flats), the one actually used in practice (a 7-sharp key signature, with its implied B#, is
/// vanishingly rare outside theory exercises).
public enum MajorKeySignature: Equatable, Sendable {
    case sharps(Int)
    case flats(Int)

    public var accidentalCount: Int {
        switch self {
        case .sharps(let count), .flats(let count): return count
        }
    }

    /// Letter order the accidentals are added in — F,C,G,D,A,E,B for sharps (reversed for
    /// flats) — expressed here as the actual sharped/flatted pitch class at each step (e.g.
    /// sharps: F#=6, C#=1, G#=8, D#=3, A#=10, E#=5, B#=0).
    private static let sharpOrderPitchClasses = [6, 1, 8, 3, 10, 5, 0]
    private static let flatOrderPitchClasses = [10, 3, 8, 1, 6, 11, 4]

    /// The pitch classes this key signature implies are sharped/flatted throughout the piece —
    /// e.g. 2 sharps means every F and C is implicitly F#/C#, so `{6, 1}`.
    public var affectedPitchClasses: Set<Int> {
        switch self {
        case .sharps(let count): return Set(Self.sharpOrderPitchClasses.prefix(count))
        case .flats(let count): return Set(Self.flatOrderPitchClasses.prefix(count))
        }
    }

    /// The standard circle-of-fifths key signature for a given major tonic (pitch class 0...11).
    public static func forMajorTonic(_ tonic: Int) -> MajorKeySignature {
        let normalized = ((tonic % 12) + 12) % 12
        let byTonic: [Int: MajorKeySignature] = [
            0: .sharps(0), 7: .sharps(1), 2: .sharps(2), 9: .sharps(3), 4: .sharps(4), 11: .sharps(5), 6: .sharps(6),
            1: .flats(5), 8: .flats(4), 3: .flats(3), 10: .flats(2), 5: .flats(1),
        ]
        return byTonic[normalized] ?? .sharps(0)
    }
}
