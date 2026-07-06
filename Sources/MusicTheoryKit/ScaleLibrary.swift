/// The complete catalog of 33 "scales of harmonies", grouped in 7 families.
/// Source: Oliver Prehn, "The Scales of Harmonies" (NewJazz), scales_of_harmonies.pdf.
public enum ScaleLibrary {
    public static let all: [ScaleDefinition] = [
        // Family 1 — Major Modes
        ScaleDefinition(id: "ionian", familyID: 1, degree: 1, popularName: "Major", systematicName: "Ionian", chordSymbols: ["Ma7"]),
        ScaleDefinition(id: "dorian", familyID: 1, degree: 2, popularName: "Dorian", systematicName: "Dorian", chordSymbols: ["mi7"]),
        ScaleDefinition(id: "phrygian", familyID: 1, degree: 3, popularName: "Phrygian", systematicName: "Phrygian", chordSymbols: ["mi7"]),
        ScaleDefinition(id: "lydian", familyID: 1, degree: 4, popularName: "Lydian", systematicName: "Lydian", chordSymbols: ["Ma7"]),
        ScaleDefinition(id: "mixolydian", familyID: 1, degree: 5, popularName: "Mixolydian", systematicName: "Mixolydian", chordSymbols: ["7"]),
        ScaleDefinition(id: "aeolian", familyID: 1, degree: 6, popularName: "Natural minor", systematicName: "Aeolian", chordSymbols: ["mi7"]),
        ScaleDefinition(id: "locrian", familyID: 1, degree: 7, popularName: "Locrian", systematicName: "Locrian", chordSymbols: ["mi7b5"]),

        // Family 2 — Melodic Minor Modes
        ScaleDefinition(id: "altered", familyID: 2, degree: 1, popularName: "Altered / Super Locrian", systematicName: "Ionian #1", chordSymbols: ["7alt", "mi7b5"]),
        ScaleDefinition(id: "melodic_minor", familyID: 2, degree: 2, popularName: "Ascending mel. minor", systematicName: "Dorian #7", chordSymbols: ["miMa7"]),
        ScaleDefinition(id: "dorian_b2", familyID: 2, degree: 3, popularName: "Dorian b2", systematicName: "Phrygian #6", chordSymbols: ["mi7"]),
        ScaleDefinition(id: "lydian_augmented", familyID: 2, degree: 4, popularName: "Lydian Augmented", systematicName: "Lydian #5", chordSymbols: ["Ma7#5"]),
        ScaleDefinition(id: "lydian_dominant", familyID: 2, degree: 5, popularName: "Lydian dominant", systematicName: "Mixolydian #4", chordSymbols: ["7"]),
        ScaleDefinition(id: "aeolian_dominant", familyID: 2, degree: 6, popularName: "Aeolian dominant", systematicName: "Aeolian #3", chordSymbols: ["7"]),
        ScaleDefinition(id: "half_diminished", familyID: 2, degree: 7, popularName: "Half diminished", systematicName: "Locrian #2", chordSymbols: ["mi7b5"]),

        // Family 3 — Harmonic Minor Modes
        ScaleDefinition(id: "major_augmented", familyID: 3, degree: 1, popularName: "Major #5 / Major Aug.", systematicName: "Ionian #5", chordSymbols: ["Ma7#5"]),
        ScaleDefinition(id: "dorian_4", familyID: 3, degree: 2, popularName: "Dorian #4", systematicName: "Dorian #4", chordSymbols: ["mi7"]),
        ScaleDefinition(id: "phrygian_dominant", familyID: 3, degree: 3, popularName: "Phrygian dominant", systematicName: "Phrygian #3", chordSymbols: ["7"]),
        ScaleDefinition(id: "lydian_2", familyID: 3, degree: 4, popularName: "Lydian #2", systematicName: "Lydian #2", chordSymbols: ["Ma7"]),
        ScaleDefinition(id: "altered_dominant_bb7", familyID: 3, degree: 5, popularName: "Altered dominant bb7", systematicName: "Mixolydian #1", chordSymbols: ["dim7"]),
        ScaleDefinition(id: "harmonic_minor", familyID: 3, degree: 6, popularName: "Harmonic minor", systematicName: "Aeolian #7", chordSymbols: ["miMa7"]),
        ScaleDefinition(id: "locrian_nat6", familyID: 3, degree: 7, popularName: "Locrian \u{266E}6", systematicName: "Locrian #6", chordSymbols: ["mi7b5"]),

        // Family 4 — Harmonic Major Modes
        ScaleDefinition(id: "harmonic_major", familyID: 4, degree: 1, popularName: "Harmonic Major", systematicName: "Ionian b6", chordSymbols: ["Ma7"]),
        ScaleDefinition(id: "dorian_b5", familyID: 4, degree: 2, popularName: "Dorian b5", systematicName: "Dorian b5", chordSymbols: ["mi7b5"]),
        ScaleDefinition(id: "phrygian_b4", familyID: 4, degree: 3, popularName: "Phrygian b4", systematicName: "Phrygian b4", chordSymbols: ["mi7", "7"]),
        ScaleDefinition(id: "lydian_b3", familyID: 4, degree: 4, popularName: "Lydian b3", systematicName: "Lydian b3", chordSymbols: ["miMa7"]),
        ScaleDefinition(id: "mixolydian_b2", familyID: 4, degree: 5, popularName: "Mixolydian b2", systematicName: "Mixolydian b2", chordSymbols: ["7"]),
        ScaleDefinition(id: "lydian_augmented_2", familyID: 4, degree: 6, popularName: "Lydian augmented #2", systematicName: "Aeolian b1", chordSymbols: ["Ma7#5", "dim7"]),
        ScaleDefinition(id: "locrian_bb7", familyID: 4, degree: 7, popularName: "Locrian bb7", systematicName: "Locrian b7", chordSymbols: ["dim7"]),

        // Family 5 — Diminished Modes (8 notes)
        ScaleDefinition(id: "diminished", familyID: 5, degree: 1, popularName: "Diminished", systematicName: "Diminished", chordSymbols: ["dim7"]),
        ScaleDefinition(id: "dominant_diminished", familyID: 5, degree: 2, popularName: "Dominant diminished", systematicName: "Inverted diminished", chordSymbols: ["7"]),

        // Family 6 — Whole Tone (6 notes)
        ScaleDefinition(id: "whole_tone", familyID: 6, degree: 1, popularName: "Whole tone", systematicName: "Whole tone", chordSymbols: ["7#5", "7b5"]),

        // Family 7 — Augmented Modes (6 notes)
        ScaleDefinition(id: "augmented", familyID: 7, degree: 1, popularName: "Augmented", systematicName: "Augmented", chordSymbols: ["Ma7"]),
        ScaleDefinition(id: "inverted_augmented", familyID: 7, degree: 2, popularName: "Inverted Augmented", systematicName: "Inverted Augmented", chordSymbols: ["6#5"]),
    ]

    private static let byIDLookup: [String: ScaleDefinition] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    public static func byID(_ id: String) -> ScaleDefinition? {
        byIDLookup[id]
    }

    public static func scales(inFamily familyID: Int) -> [ScaleDefinition] {
        all.filter { $0.familyID == familyID }.sorted { $0.degree < $1.degree }
    }
}
