import MusicTheoryKit

/// Common alternate names for a handful of `ChordProgressionTemplate.builtInDefaults` entries —
/// e.g. "Pop (I-V-vi-IV)" is also widely called the "Axis progression". Small and hand-authored
/// (unlike chords/scales, not worth a JSON-editable catalog for this pass).
public enum ProgressionNameAliases {
    public struct Alias: Sendable {
        public let canonicalName: String
        public let alternateNames: [String]
    }

    public static let all: [Alias] = [
        Alias(canonicalName: "Pop (I-V-vi-IV)", alternateNames: ["Axis progression", "Progression \u{00AB} 4 accords \u{00BB}"]),
        Alias(canonicalName: "Annees 50 (I-vi-IV-V)", alternateNames: ["50s progression", "Doo-wop progression"]),
        Alias(canonicalName: "Cadence andalouse (i-VII-VI-V)", alternateNames: ["Andalusian cadence"]),
        Alias(canonicalName: "ii-V-I (jazz)", alternateNames: ["Two-five-one"]),
        Alias(canonicalName: "Blues 12 mesures", alternateNames: ["12-bar blues"]),
    ]

    /// Semitone offset from the tonic for each of the major scale's 7 degrees (Ionian).
    private static let majorScaleOffsets = [0, 2, 4, 5, 7, 9, 11]

    /// The semitone-offset-from-tonic sequence for `degrees`, expressed relative to one shared
    /// major tonal center — folds a minor-context progression's own numbering (i, ii\u{b0}, III...)
    /// onto its relative major's numbering, so e.g. "i-VI-III-VII" (read starting on the
    /// relative minor's own tonic) normalizes to the same sequence as a relative-major rewrite
    /// starting on "I". Whether `degrees` is "in minor context" is inferred from the presence of
    /// a literal minor tonic token (lowercase "i", degree 1) among them — a heuristic, not a
    /// stored flag (see this type's own doc comment: this equivalence rule is a judgment call,
    /// flagged for the Progression Library owner to revisit if it ever surprises in practice).
    /// `nil` if any token fails to parse.
    static func normalizedRootOffsets(_ degrees: [String]) -> [Int]? {
        let parsed = degrees.map { RomanNumeralChord.parse($0) }
        guard parsed.allSatisfy({ $0 != nil }) else { return nil }
        let isMinorContext = parsed.contains { $0?.degree == 1 && $0?.quality == .minor }
        return parsed.map { pair in
            guard let pair else { return 0 }
            let degreeIndex = isMinorContext ? ((pair.degree - 1) + 5) % 7 : (pair.degree - 1) % 7
            return majorScaleOffsets[degreeIndex]
        }
    }

    /// Every canonical/alternate name whose own `ChordProgressionTemplate.builtInDefaults`
    /// degrees normalize to the same root sequence as `degrees` — `[]` if none match (including
    /// when `degrees` itself doesn't parse). Matching `degrees` against its own template
    /// (e.g. asking for "I-V-vi-IV"'s names) is expected to include that template's own name.
    public static func matchingNames(for degrees: [String]) -> [String] {
        guard let target = normalizedRootOffsets(degrees) else { return [] }
        var matches: [String] = []
        for template in ChordProgressionTemplate.builtInDefaults {
            guard let candidate = normalizedRootOffsets(template.degrees), candidate == target else { continue }
            matches.append(template.name)
            if let alias = all.first(where: { $0.canonicalName == template.name }) {
                matches.append(contentsOf: alias.alternateNames)
            }
        }
        return matches
    }
}
