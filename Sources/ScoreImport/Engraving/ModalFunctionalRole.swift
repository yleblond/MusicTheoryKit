/// A diatonic chord's functional color relative to a mode's own tonic — deliberately NOT named
/// after classical scale-degree numbers (see `ModalFunctionalRoleTable`'s own doc comment): the
/// same scale degree can be `.home` in one mode and `.tension` in another, since what matters is
/// a chord's relationship to the mode's own tonic, not its degree number.
///
/// Lives here (`ScoreImport`), not alongside the fuller `ModalFunctionalMapBuilder`/
/// `ModeFunctionalMap` machinery that originally introduced it (`Sources/AppCore/
/// ModalFunctionalMap.swift`, for the Mode Library's "Exploration fonctionnelle" panel) — that
/// type needs `ChordProgressionResolver` (an `AppCore`-only, SwiftData-adjacent dependency chain)
/// to resolve each degree's actual `ChordReference`/characteristic notes, which `ScoreImport`
/// can't reach (dependency direction is `AppCore` -> `ScoreImport`, never the reverse). This role
/// enum plus the table below have zero such dependency, so they're factored out to the lowest
/// module both consumers can reach: `ScoreEngravingAdapter`'s score-coloring (`ScoreImport`
/// itself) and `ModalFunctionalMapBuilder` (`AppCore`, which already imports `ScoreImport`).
public enum ModalFunctionalRole: String, Codable, CaseIterable, Sendable {
    case home, away, tension, neutral
}

/// The hand-authored (as opposed to `ModalFunctionalMapBuilder`'s alternate `.computed` formula)
/// role/intensity table for each of the 7 classic modes' own 7 diatonic chords, reasoned from
/// each mode's actual interval content (not copied from classical major/minor functional
/// harmony).
public enum ModalFunctionalRoleTable {
    /// One hand-reasoned (role, intensity) per (mode, diatonic degree) — root motion by fifths,
    /// shared tones with the tonic, half-step pulls, diminished quality, applied by ear/analysis
    /// to each of the 7 modes individually. Degree 1 is always `.home` (Locrian's is intentionally
    /// non-zero intensity — its own tonic triad is diminished, a real and well-known quirk worth
    /// surfacing rather than papering over with a flat 0). `scaleDegree` is `ScaleDefinition.degree`
    /// (1 = Ionian ... 7 = Locrian); `chordDegree` is the target chord's own 1-based diatonic
    /// degree (1...7) within that mode.
    public static func standardRole(forScaleDegree scaleDegree: Int, chordDegree: Int) -> (role: ModalFunctionalRole, intensity: Double) {
        // [degree1, degree2, ..., degree7]
        let table: [(ModalFunctionalRole, Double)]
        switch scaleDegree {
        case 1: // Ionian: I ii iii IV V vi vii°
            table = [(.home, 0.0), (.away, 0.35), (.away, 0.3), (.away, 0.35), (.tension, 0.85), (.away, 0.3), (.tension, 0.95)]
        case 2: // Dorian: i ii III IV v vi° VII — no half-step pull anywhere, deliberately flatter
            table = [(.home, 0.0), (.away, 0.4), (.away, 0.3), (.away, 0.35), (.neutral, 0.5), (.tension, 0.7), (.away, 0.45)]
        case 3: // Phrygian: i II III iv v° VI vii — the Phrygian ii=bII cadence is the strongest pull
            table = [(.home, 0.0), (.tension, 0.75), (.away, 0.3), (.away, 0.4), (.tension, 0.7), (.away, 0.3), (.away, 0.45)]
        case 4: // Lydian: I II iii #iv° V vi vii — keeps Ionian's leading tone AND gains #4's own color
            table = [(.home, 0.0), (.away, 0.4), (.away, 0.35), (.tension, 0.85), (.tension, 0.8), (.away, 0.3), (.tension, 0.7)]
        case 5: // Mixolydian: I ii iii° IV v vi VII — the 5th degree is minor, deliberately NOT a "dominant"
            table = [(.home, 0.0), (.away, 0.4), (.tension, 0.65), (.away, 0.35), (.neutral, 0.5), (.away, 0.3), (.away, 0.45)]
        case 6: // Aeolian: i ii° III iv v VI VII — natural minor's own v is minor, no true leading tone
            table = [(.home, 0.0), (.tension, 0.65), (.away, 0.3), (.away, 0.35), (.neutral, 0.5), (.away, 0.35), (.away, 0.45)]
        case 7: // Locrian: i° II iii iv V VI vii — even home is diminished; V carries both characteristic notes
            table = [(.home, 0.2), (.tension, 0.8), (.away, 0.35), (.away, 0.4), (.tension, 0.9), (.away, 0.35), (.away, 0.45)]
        default:
            table = Array(repeating: (.neutral, 0.5), count: 7)
        }
        let wrapped = ((chordDegree - 1) % 7 + 7) % 7
        return table[wrapped]
    }
}
