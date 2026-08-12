/// A historical or theoretical tuning system, expressed purely as a deviation from 12-tone equal
/// temperament — the shape the whole app's audio pipeline actually consumes (a small cents
/// correction per note), not the raw frequency ratios the tuning literature usually starts from.
public struct Temperament: Identifiable, Sendable {
    /// How a temperament's cents deviations are actually computed.
    public enum Model: Sendable {
        /// 12 deviations, index = semitones above the tonic (index 0 = tonic, always 0) —
        /// correct for any temperament that doesn't distinguish enharmonically-equal spellings
        /// (Équal trivially; Werckmeister III and this app's 5-limit Juste table both by design,
        /// see each's own doc comment below), since it never needs a `SpelledPitch` to look up.
        case chromaticDegree([Double])
        /// Cents computed directly from a note's position on the line of fifths (`fifthCents`
        /// per fifth-step away from the tonic) — the correct model for a temperament genuinely
        /// built from an unbroken chain of fifths (Pythagorean; a future meantone variant would
        /// use a narrower `fifthCents`), where G# and Ab are NOT the same note (they sit 12
        /// fifths apart — the "Pythagorean comma"). See `TemperamentLibrary.cents(for:in:tonic:)`
        /// for how this degrades gracefully to a canonical default spelling when no real
        /// `SpelledPitch` context is available.
        case lineOfFifths(fifthCents: Double)
    }

    public let id: String
    public let model: Model

    public init(id: String, model: Model) {
        if case .chromaticDegree(let table) = model {
            precondition(table.count == 12, "chromaticDegree table must have exactly 12 entries")
        }
        self.id = id
        self.model = model
    }
}

/// The fixed set of temperaments this app knows about (Phase 1 — see the Intonations feature
/// plan: Équal/Pythagoricien/Juste/Werckmeister III today, more historical temperaments are a
/// matter of adding another table here, not touching anything downstream).
public enum TemperamentLibrary {
    public static let equal = Temperament(id: "equal", model: .chromaticDegree(Array(repeating: 0, count: 12)))

    /// Pythagorean tuning — a chain of pure fifths (701.955¢ each). Modeled as `.lineOfFifths`
    /// (not a fixed 12-entry table): the whole point of Pythagorean tuning is that it does NOT
    /// collapse enharmonically-equal spellings to the same pitch — G# (8 fifths from C) and Ab
    /// (-4 fifths from C) differ by exactly the Pythagorean comma (≈23.46¢), see
    /// `TemperamentTests` for the verified computation.
    public static let pythagorean = Temperament(id: "pythagorean", model: .lineOfFifths(fifthCents: 701.955))

    /// 5-limit just intonation — the standard published 12-tone table built from simple integer
    /// ratios (16/15, 9/8, 6/5, 5/4, 4/3, 45/32, 3/2, 8/5, 5/3, 16/9, 15/8), each compared to its
    /// equal-tempered degree. Kept as `.chromaticDegree`: as built here, this is already anchored
    /// per-mode (each of a mode's own 7 degrees maps to one fixed ratio), so there's no
    /// within-a-mode enharmonic ambiguity left to resolve the way Pythagorean has.
    public static let justIntonation = Temperament(id: "justIntonation", model: .chromaticDegree([
        0, 11.73, 3.91, 15.64, -13.69, -1.96, -9.78, 1.96, 13.69, -15.64, -3.91, -11.73,
    ]))

    /// Werckmeister III (1691) — a well temperament: the fifths C-G, G-D, D-A and B-F# are each
    /// narrowed by 1/4 syntonic comma, every other fifth stays pure. Standard published absolute
    /// cents from C are 0, 90.225, 192.18, 294.135, 390.225, 498.045, 588.27, 696.09, 792.18,
    /// 888.27, 996.09, 1092.18 — the table here is each of those minus its equal-tempered degree
    /// (`d*100`). Kept as `.chromaticDegree`: well temperaments were specifically designed to
    /// play on an ordinary 12-key-per-octave keyboard with no split keys, so G# and Ab are
    /// deliberately the same pitch here, by design (not a simplification).
    public static let werckmeisterIII = Temperament(id: "werckmeisterIII", model: .chromaticDegree([
        0, -9.775, -7.82, -5.865, -9.775, -1.955, -11.73, -3.91, -7.82, -11.73, -3.91, -7.82,
    ]))

    public static let all: [Temperament] = [equal, pythagorean, justIntonation, werckmeisterIII]

    public static func byID(_ id: String) -> Temperament? {
        all.first { $0.id == id }
    }

    /// The cents correction for `pitchClass` when `temperament` is anchored on `tonic` — no
    /// enharmonic context available, so a `.lineOfFifths` temperament falls back to
    /// `DiatonicSpelling.canonicalSpelling` for both `pitchClass` and `tonic` (the same default
    /// spelling convention used throughout this codebase). Existing callers that only ever have
    /// a bare `PitchClass` (not a real musical context) keep exactly their previous behavior —
    /// this is the same table Pythagorean always used before `.lineOfFifths` existed.
    public static func cents(for pitchClass: PitchClass, in temperament: Temperament, tonic: PitchClass) -> Double {
        switch temperament.model {
        case .chromaticDegree(let table):
            let degree = ((pitchClass.value - tonic.value) % 12 + 12) % 12
            return table[degree]
        case .lineOfFifths(let fifthCents):
            let spelled = DiatonicSpelling.canonicalSpelling(forPitchClass: pitchClass)
            let tonicSpelled = DiatonicSpelling.canonicalSpelling(forPitchClass: tonic)
            return lineOfFifthsCents(offset: spelled.lineOfFifths - tonicSpelled.lineOfFifths, fifthCents: fifthCents, pitchClass: pitchClass, tonic: tonic)
        }
    }

    /// Enharmonically-aware counterpart of `cents(for pitchClass:in:tonic:)` — for a
    /// `.chromaticDegree` temperament this is identical to the pitch-class-only overload (the
    /// spelling doesn't matter); for `.lineOfFifths` it uses `spelledPitch`'s and
    /// `tonicSpelling`'s REAL line-of-fifths positions, so G# and Ab (or any other enharmonic
    /// pair) can come out with genuinely different corrections. See `DiatonicSpelling` for how a
    /// mode's own scale degrees get their real spelling resolved.
    public static func cents(for spelledPitch: SpelledPitch, in temperament: Temperament, tonicSpelling: SpelledPitch) -> Double {
        switch temperament.model {
        case .chromaticDegree(let table):
            let degree = ((spelledPitch.pitchClass.value - tonicSpelling.pitchClass.value) % 12 + 12) % 12
            return table[degree]
        case .lineOfFifths(let fifthCents):
            return lineOfFifthsCents(offset: spelledPitch.lineOfFifths - tonicSpelling.lineOfFifths, fifthCents: fifthCents, pitchClass: spelledPitch.pitchClass, tonic: tonicSpelling.pitchClass)
        }
    }

    /// Raw line-of-fifths cents (`offset * fifthCents`), reduced to a deviation from equal
    /// temperament within ±600¢ of `pitchClass`'s own chromatic degree above `tonic` — the same
    /// "reduce to the nearest equal-tempered octave" step every `.lineOfFifths` computation needs
    /// regardless of where the spelling itself came from.
    private static func lineOfFifthsCents(offset: Int, fifthCents: Double, pitchClass: PitchClass, tonic: PitchClass) -> Double {
        let rawCents = Double(offset) * fifthCents
        let chromaticDegree = ((pitchClass.value - tonic.value) % 12 + 12) % 12
        let equalCents = Double(chromaticDegree) * 100
        var deviation = rawCents - equalCents
        while deviation > 600 { deviation -= 1200 }
        while deviation < -600 { deviation += 1200 }
        return deviation
    }
}
