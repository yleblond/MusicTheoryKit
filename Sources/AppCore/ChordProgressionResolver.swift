import MusicTheoryKit
import PieceModel

/// Resolves a `ChordProgressionTemplate`'s roman-numeral degrees into concrete chords using the
/// mode's own *actual* diatonic harmony (`ScaleDefinition.chordSymbols`), for the Progression
/// Library's display — e.g. degree ii in a Dorian-family mode resolves to a `mi7`, not just a
/// bare `mi` triad. This is deliberately a SEPARATE, additive code path from
/// `ImprovSession.resolveChordProgression`/`RomanNumeralChord.rootAndQuality`, which the Guide
/// feature already depends on and which intentionally reads the token's quality literally from
/// its case (see that type's own doc comment) — nothing here changes that existing behavior.
public enum ChordProgressionResolver {
    /// One `ChordReference` per degree token, using the richest chord quality this mode's own
    /// scale family can offer for that degree — falls back to the literal-case quality
    /// ("I"/"IV"/"V" -> "Ma", lowercase -> "mi", trailing "\u{b0}" -> "dim") whenever the mode's
    /// family has no diatonic-chord data for that degree (any family other than 1, the 7
    /// classic major modes — same restriction as `CircleOfFifths.parentTonic(for:)`/
    /// `FunctionalHarmonyTable`). Tokens that fail to parse are skipped, same as
    /// `ImprovSession.resolveChordProgression`.
    public static func resolveRich(_ template: ChordProgressionTemplate, in mode: Mode) -> [ChordReference] {
        template.degrees.compactMap { token in
            guard let (degree, quality) = RomanNumeralChord.parse(token) else { return nil }
            let root = mode.degree(degree)
            let templateID = diatonicChordTemplateID(forDegree: degree, in: mode) ?? literalTemplateID(for: quality)
            return ChordReference(root: root.value, chordTemplateID: templateID)
        }
    }

    /// The chord-name sequence for `template` in `mode`, formatted with `style` — the direct
    /// display value for the Progression Library's list/detail rows.
    public static func chordSymbols(for template: ChordProgressionTemplate, in mode: Mode, style: any NotationStyle, preferFlats: Bool = false) -> [String] {
        resolveRich(template, in: mode).map { reference in
            guard let chord = reference.resolve() else { return "?" }
            return style.displayName(for: chord, preferFlats: preferFlats)
        }
    }

    /// The 7 diatonic chords of `mode`'s own scale family, degree 1 through 7, in order — `[]`
    /// for any family other than 1 (see `diatonicChordTemplateID`'s own doc comment). Used by
    /// the Mode Library's "Accords du mode" list and its circle-of-fifths section alike.
    public static func diatonicChordReferences(in mode: Mode) -> [ChordReference] {
        (1...7).compactMap { degree in
            guard let templateID = diatonicChordTemplateID(forDegree: degree, in: mode) else { return nil }
            return ChordReference(root: mode.degree(degree).value, chordTemplateID: templateID)
        }
    }

    /// The scale-degree-relative quality (as a `ChordVocabulary` id) at `degree` within `mode`'s
    /// own family — `nil` for any family other than 1 (the classic 7 major modes, the only
    /// family with a full 7-degree diatonic-chord table).
    private static func diatonicChordTemplateID(forDegree degree: Int, in mode: Mode) -> String? {
        guard mode.scale.familyID == 1 else { return nil }
        let familyScales = ScaleLibrary.scales(inFamily: 1)
        guard familyScales.count == 7 else { return nil }
        let wrappedDegree = (((mode.scale.degree - 1) + (degree - 1)) % 7 + 7) % 7 + 1
        return familyScales.first { $0.degree == wrappedDegree }?.chordSymbols.first
    }

    private static func literalTemplateID(for quality: ChordQuality) -> String {
        switch quality {
        case .major: return "Ma"
        case .minor: return "mi"
        case .diminished: return "dim"
        }
    }
}
