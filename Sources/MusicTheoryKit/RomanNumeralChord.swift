/// Parses a roman-numeral chord-degree token (the notation used in `AppCore.ChordProgressionTemplate`,
/// e.g. "I", "vi", "vii°") into a scale degree + quality, and resolves it against an actual
/// `Mode` — pure theory, no dependency on `PieceModel`'s `ChordReference` (that resolution
/// step lives one layer up, in `AppCore`, since it needs a chord-template id string, not just
/// a `ChordQuality`).
///
/// Deliberately **not** derived from the mode's own diatonic harmony (e.g. degree i is
/// naturally minor in Dorian) — the case of the token IS the quality, taken literally,
/// exactly like a chord-progression written down in a blues/jazz reference book: "I-IV-V"
/// always means three major triads, whichever mode/tonic you apply it to. Simpler to reason
/// about and more predictable than re-deriving quality from an arbitrary scale family.
public enum RomanNumeralChord {
    private static let degreeByRomanUpper: [String: Int] = [
        "I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6, "VII": 7,
    ]

    /// "I" -> (1, .major), "vi" -> (6, .minor), "vii\u{b0}" -> (7, .diminished). `nil` if
    /// `token` (after stripping a trailing "\u{b0}") isn't one of the 7 roman numerals I-VII,
    /// case-insensitively.
    public static func parse(_ token: String) -> (degree: Int, quality: ChordQuality)? {
        var text = token
        var forcedDiminished = false
        if text.hasSuffix("\u{b0}") {
            forcedDiminished = true
            text.removeLast()
        }
        let upper = text.uppercased()
        guard let degree = degreeByRomanUpper[upper] else { return nil }
        let quality: ChordQuality = forcedDiminished ? .diminished : (text == upper ? .major : .minor)
        return (degree, quality)
    }

    /// `mode.degree(degree)` (1-based, wraps across octaves) as the root, `quality` taken
    /// literally from `token` — see this type's own doc comment for why. `nil` if `token`
    /// doesn't parse.
    public static func rootAndQuality(for token: String, in mode: Mode) -> (root: PitchClass, quality: ChordQuality)? {
        guard let (degree, quality) = parse(token) else { return nil }
        return (mode.degree(degree), quality)
    }
}
