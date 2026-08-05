/// A diatonic scale degree's functional-harmony role (tonic, dominant, etc.) — notation-neutral
/// identifiers; the French display strings ("Tonique", "Dominante"...) live one layer up, in
/// `Localization`, since this module has no dependency on it (same boundary `ScaleFamily.name`/
/// `ScaleDefinition.popularName` already keep by staying plain English literals).
public enum FunctionalHarmonyRole: String, Codable, CaseIterable, Sendable {
    case tonic, supertonic, mediant, subdominant, dominant, submediant, leadingTone
}

public enum FunctionalHarmonyTable {
    /// Degree (1-based) -> role, for the 7 classic major-scale degrees — the same mapping
    /// applies to every mode of `familyID == 1` (Ionian, Dorian, ...): the role is defined
    /// relative to the *parent* major scale's own degree numbering, not to whichever of the 7
    /// modes is currently the tonic (matches `CircleOfFifths.parentTonic(for:)`'s own
    /// family-1-only scope for the same reason).
    private static let familyOneRoles: [Int: FunctionalHarmonyRole] = [
        1: .tonic, 2: .supertonic, 3: .mediant, 4: .subdominant,
        5: .dominant, 6: .submediant, 7: .leadingTone,
    ]

    /// `nil` for any family other than 1 (no defined functional-harmony vocabulary for e.g. the
    /// melodic/harmonic-minor mode families) — same restriction as `CircleOfFifths.parentTonic(for:)`.
    public static func role(forDegree degree: Int, familyID: Int) -> FunctionalHarmonyRole? {
        guard familyID == 1 else { return nil }
        let wrapped = ((degree - 1) % 7 + 7) % 7 + 1
        return familyOneRoles[wrapped]
    }
}
