/// Which scales are conventionally suggested for a given harmonic function/chord quality.
public struct FunctionalScaleSuggestion: Sendable {
    public let function: String
    public let chordQuality: String
    /// Ordered by preference, as charted by the source.
    public let suggestedScaleIDs: [String]

    public init(function: String, chordQuality: String, suggestedScaleIDs: [String]) {
        self.function = function
        self.chordQuality = chordQuality
        self.suggestedScaleIDs = suggestedScaleIDs
    }
}

/// Source: Oliver Prehn, "Scale Chart for Improvisation over ii-V-I Jazz Chords in Major".
public enum IIVIMajorChart {
    public static let suggestions: [FunctionalScaleSuggestion] = [
        FunctionalScaleSuggestion(
            function: "ii",
            chordQuality: "mi7",
            suggestedScaleIDs: ["dorian", "dorian_b2", "dorian_4", "phrygian", "phrygian_b4"]
        ),
        FunctionalScaleSuggestion(
            function: "V",
            chordQuality: "7",
            suggestedScaleIDs: ["mixolydian", "lydian_dominant", "mixolydian_b2", "aeolian_dominant", "phrygian_dominant"]
        ),
        FunctionalScaleSuggestion(
            function: "I",
            chordQuality: "Ma7",
            suggestedScaleIDs: ["ionian", "lydian", "lydian_2", "harmonic_major", "augmented"]
        ),
    ]

    public static func scales(forFunction function: String) -> [ScaleDefinition] {
        guard let suggestion = suggestions.first(where: { $0.function == function }) else { return [] }
        return suggestion.suggestedScaleIDs.compactMap(ScaleLibrary.byID)
    }
}
