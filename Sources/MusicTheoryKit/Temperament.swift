/// A historical or theoretical tuning system, expressed purely as a deviation from 12-tone equal
/// temperament — the shape the whole app's audio pipeline actually consumes (a small cents
/// correction per note), not the raw frequency ratios the tuning literature usually starts from.
/// `centsFromEqualByDegree[d]` is the correction for the pitch class `d` semitones above whatever
/// tonic the temperament is anchored to (index 0 = tonic, always 0 — every temperament here keeps
/// the tonic itself untouched).
public struct Temperament: Identifiable, Sendable {
    public let id: String
    public let centsFromEqualByDegree: [Double]

    public init(id: String, centsFromEqualByDegree: [Double]) {
        precondition(centsFromEqualByDegree.count == 12, "centsFromEqualByDegree must have exactly 12 entries")
        self.id = id
        self.centsFromEqualByDegree = centsFromEqualByDegree
    }
}

/// The fixed set of temperaments this app knows about (Phase 1 — see the Intonations feature
/// plan: Équal/Pythagoricien/Juste/Werckmeister III today, more historical temperaments are a
/// matter of adding another table here, not touching anything downstream).
public enum TemperamentLibrary {
    public static let equal = Temperament(id: "equal", centsFromEqualByDegree: Array(repeating: 0, count: 12))

    /// Pythagorean tuning — a chain of pure fifths (701.955¢ each), taking the conventional
    /// -5...+6-fifths range around the tonic (Db at -5 fifths through F# at +6), the same
    /// convention used almost universally to avoid an even-more-lopsided "wolf" placement.
    /// Derived by direct computation (`k` fifths from the tonic, `k*701.955` cents, reduced to
    /// the nearest equal-temperament octave and compared to that degree's own `d*100`), not
    /// copied from an unverified table — see `TemperamentTests` for the check computation.
    public static let pythagorean = Temperament(id: "pythagorean", centsFromEqualByDegree: [
        0, -9.775, 3.91, -5.865, 7.82, -1.955, 11.73, 1.955, -7.82, 5.865, -3.91, 9.775,
    ])

    /// 5-limit just intonation — the standard published 12-tone table built from simple integer
    /// ratios (16/15, 9/8, 6/5, 5/4, 4/3, 45/32, 3/2, 8/5, 5/3, 16/9, 15/8), each compared to its
    /// equal-tempered degree.
    public static let justIntonation = Temperament(id: "justIntonation", centsFromEqualByDegree: [
        0, 11.73, 3.91, 15.64, -13.69, -1.96, -9.78, 1.96, 13.69, -15.64, -3.91, -11.73,
    ])

    /// Werckmeister III (1691) — a well temperament: the fifths C-G, G-D, D-A and B-F# are each
    /// narrowed by 1/4 syntonic comma, every other fifth stays pure. Standard published absolute
    /// cents from C are 0, 90.225, 192.18, 294.135, 390.225, 498.045, 588.27, 696.09, 792.18,
    /// 888.27, 996.09, 1092.18 — the table here is each of those minus its equal-tempered degree
    /// (`d*100`).
    public static let werckmeisterIII = Temperament(id: "werckmeisterIII", centsFromEqualByDegree: [
        0, -9.775, -7.82, -5.865, -9.775, -1.955, -11.73, -3.91, -7.82, -11.73, -3.91, -7.82,
    ])

    public static let all: [Temperament] = [equal, pythagorean, justIntonation, werckmeisterIII]

    public static func byID(_ id: String) -> Temperament? {
        all.first { $0.id == id }
    }

    /// The cents correction for `pitchClass` when `temperament` is anchored on `tonic`.
    public static func cents(for pitchClass: PitchClass, in temperament: Temperament, tonic: PitchClass) -> Double {
        let degree = ((pitchClass.value - tonic.value) % 12 + 12) % 12
        return temperament.centsFromEqualByDegree[degree]
    }
}
