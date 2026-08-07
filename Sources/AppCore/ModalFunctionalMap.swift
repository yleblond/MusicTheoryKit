import MusicTheoryKit
import PieceModel

/// A diatonic chord's functional color in the Mode Library's "Exploration fonctionnelle" panel
/// — deliberately NOT named after classical scale-degree numbers (see `FunctionalHarmonyTable`'s
/// own `familyID == 1`-only restriction): the same scale degree can be `.home` in one mode and
/// `.tension` in another, since what matters is a chord's relationship to the mode's own tonic,
/// not its degree number. See `ModalFunctionalMapBuilder`'s own doc comment for how each role is
/// actually decided.
public enum ModalFunctionalRole: String, Codable, CaseIterable, Sendable {
    case home, away, tension, neutral
}

/// Which of the (currently two) ways to classify a mode's chords into `ModalFunctionalRole` is
/// active — exposed as a user-facing picker rather than a single hardcoded rule, since neither
/// classical theory nor modern modal-jazz pedagogy agrees on one universal formula for this.
/// `standardTable` today is one hand-authored table; the picker/data model are both built so a
/// second or third named table (and, later, user-authored ones) can be added as more cases/rows
/// without any of `ModeFunctionalMap`'s own shape changing.
public enum FunctionalRoleSource: String, CaseIterable, Identifiable, Sendable {
    case computed, standardTable
    public var id: String { rawValue }
}

/// One diatonic chord's entry in a `ModeFunctionalMap`.
public struct ModalChordFunction: Sendable, Equatable {
    public let reference: ChordReference
    /// 1-based diatonic scale degree (1...7) — used for layout/lookup, never shown to the user
    /// as "this chord's function" on its own (that's exactly the framing this whole feature
    /// avoids, see `ModalFunctionalRole`'s doc comment).
    public let degree: Int
    public let role: ModalFunctionalRole
    /// 0 (fully stable) ... 1 (maximal tension) — drives the orbit graph's radius.
    public let functionalIntensity: Double
    public let isModalCharacteristic: Bool
    /// Which of the mode's own characteristic notes (see `ModalFunctionalMapBuilder.characteristicNotes(for:)`)
    /// this specific chord actually contains — empty whenever `isModalCharacteristic` is false.
    public let characteristicNotes: [PitchClass]
}

/// A directed "tends to resolve toward" relationship between two of a `ModeFunctionalMap`'s own
/// chords, by degree — see `ModalFunctionalMapBuilder`'s own doc comment for how `strength` is
/// derived. `fromDegree`/`toDegree` are always distinct degrees within the SAME map (1...7).
public struct HarmonicAttraction: Sendable, Equatable {
    public let fromDegree: Int
    public let toDegree: Int
    /// 0...1 — below `ModalFunctionalMapBuilder.minimumDisplayedStrength` isn't worth drawing.
    public let strength: Double
}

/// Everything the "Exploration fonctionnelle" panel needs to draw both graphs for one mode —
/// see `ModalFunctionalMapBuilder.build(for:source:)`, the only way to construct one.
public struct ModeFunctionalMap: Sendable {
    public let mode: Mode
    public let source: FunctionalRoleSource
    /// Always the 7 classic diatonic degrees, in order — degree 1 is always `.home`. Empty for
    /// any mode outside `familyID == 1`, matching `ChordProgressionResolver.diatonicChordReferences`'s
    /// own restriction (nothing in this feature invents theory that doesn't already exist
    /// elsewhere in the app for the other scale families).
    public let chords: [ModalChordFunction]
    public let attractions: [HarmonicAttraction]
    /// The mode's own defining notes relative to its nearest "unaltered" reference (major for
    /// modes as bright or brighter than major, natural minor for the others) — see
    /// `ModalFunctionalMapBuilder.characteristicNotes(for:)`.
    public let modeCharacteristicNotes: [PitchClass]
}

/// Builds a `ModeFunctionalMap` two different ways:
///
/// - `.computed`: a general formula from three signals that don't assume any particular scale
///   degree is "the dominant" — (1) the chord root's distance from the tonic on the circle of
///   fifths (farther = less stable), (2) how many tones it shares with the tonic triad (more
///   shared tones = more stable), (3) whether it contains a note a semitone away from the tonic
///   in either direction (the actual acoustic source of a "pull", present in some modes' chords
///   and not others — e.g. absent from every Dorian/Aeolian chord, present in Phrygian's II via
///   its own b2). A diminished/half-diminished chord gets an extra instability bump.
/// - `.standardTable`: a hand-authored role/intensity for each of the 7 classic modes' own 7
///   diatonic chords, reasoned from each mode's actual interval content (not copied from
///   classical major/minor functional harmony) — see the private `standardRole` table below for
///   the reasoning behind each entry. Exists so a user who disagrees with the formula's output
///   for a given chord has a second, independently-reasoned opinion to compare against — the
///   whole reason `FunctionalRoleSource` is a picker and not a single fixed rule.
///
/// `isModalCharacteristic`/`characteristicNotes` are computed identically regardless of
/// `source` — which notes make a mode's own sound distinctive is a settled fact, not a matter of
/// interpretation the way "how tense is this chord" is.
public enum ModalFunctionalMapBuilder {
    /// Below this, an attraction arrow isn't worth drawing — keeps the attraction graph from
    /// turning into a spiderweb of barely-there lines (explicitly called out as a UX risk in the
    /// original spec this feature was built from).
    public static let minimumDisplayedStrength = 0.25

    public static func build(for mode: Mode, source: FunctionalRoleSource) -> ModeFunctionalMap {
        let references = ChordProgressionResolver.diatonicChordReferences(in: mode)
        guard references.count == 7, let tonicChord = references[0].resolve() else {
            return ModeFunctionalMap(mode: mode, source: source, chords: [], attractions: [], modeCharacteristicNotes: [])
        }
        let characteristics = characteristicNotes(for: mode)
        let chords: [ModalChordFunction] = references.enumerated().map { index, reference in
            let degree = index + 1
            let chord = reference.resolve()
            let ownNotes = Set(chord?.pitchClasses ?? [])
            let matchedCharacteristics = characteristics.filter { ownNotes.contains($0) }
            let (role, intensity): (ModalFunctionalRole, Double)
            switch source {
            case .computed: (role, intensity) = computedRole(for: reference, degree: degree, in: mode, tonicChord: tonicChord)
            case .standardTable: (role, intensity) = standardRole(forScaleDegree: mode.scale.degree, chordDegree: degree)
            }
            return ModalChordFunction(
                reference: reference, degree: degree, role: role, functionalIntensity: intensity,
                isModalCharacteristic: !matchedCharacteristics.isEmpty, characteristicNotes: matchedCharacteristics
            )
        }
        let attractions = chords.filter { $0.role != .home }.compactMap { chord -> HarmonicAttraction? in
            guard chord.functionalIntensity >= minimumDisplayedStrength else { return nil }
            return HarmonicAttraction(fromDegree: chord.degree, toDegree: 1, strength: chord.functionalIntensity)
        }
        return ModeFunctionalMap(mode: mode, source: source, chords: chords, attractions: attractions, modeCharacteristicNotes: characteristics)
    }

    // MARK: - Computed formula

    /// Successive perfect fifths starting from C — index distance between two pitch classes here
    /// (wrapped to the shorter side of the 12-column circle) is that pair's distance on the
    /// circle of fifths, in [0, 6]. No such helper exists on `CircleOfFifths` today (it only
    /// builds the wheel's display data), so this is deliberately local and minimal rather than
    /// growing that type for a single caller.
    private static let fifthsOrder = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]

    private static func fifthsDistance(from a: PitchClass, to b: PitchClass) -> Int {
        guard let ia = fifthsOrder.firstIndex(of: a.value), let ib = fifthsOrder.firstIndex(of: b.value) else { return 0 }
        let diff = abs(ia - ib)
        return min(diff, 12 - diff)
    }

    private static func computedRole(
        for reference: ChordReference, degree: Int, in mode: Mode, tonicChord: Chord
    ) -> (ModalFunctionalRole, Double) {
        guard let chord = reference.resolve() else { return (.neutral, 0.5) }
        // Every diatonic half-diminished/diminished chord this app's own `ChordVocabulary` uses
        // for family 1 spells its id with one of these — see `ChordProgressionResolver`'s own
        // table (built from `ScaleDefinition.chordSymbols`).
        let isUnstableQuality = reference.chordTemplateID.contains("b5") || reference.chordTemplateID.contains("dim")
        if degree == 1 {
            // The tonic triad usually anchors the whole map at zero tension — except in Locrian,
            // the one mode where the tonic triad is itself diminished (its own 5th is a b5), a
            // real and well-known quirk worth surfacing rather than papering over with a flat 0.
            return (.home, isUnstableQuality ? 0.2 : 0.0)
        }
        let fifths = fifthsDistance(from: mode.tonic, to: chord.root)
        let sharedTones = chord.pitchClassSet.intersection(tonicChord.pitchClassSet).count
        let below = PitchClass(mode.tonic.value - 1)
        let above = PitchClass(mode.tonic.value + 1)
        // A half-step pull isn't only "contains the classical leading tone below the tonic" —
        // Phrygian/Locrian's own signature cadence is a chord ROOTED a half-step ABOVE the
        // tonic resolving down onto it, an equally real acoustic pull the other direction.
        let hasSemitonePull = chord.pitchClassSet.contains(below) || chord.root == above
        var intensity = Double(fifths) / 6.0 - 0.12 * Double(sharedTones)
        if hasSemitonePull { intensity += 0.25 }
        if isUnstableQuality { intensity += 0.15 }
        intensity = min(max(intensity, 0), 1)
        let role: ModalFunctionalRole
        if hasSemitonePull || isUnstableQuality { role = .tension }
        else if intensity < 0.35 { role = .away }
        else { role = .neutral }
        return (role, intensity)
    }

    // MARK: - Standard table

    /// Each mode's own defining note(s), as semitone offsets from its tonic, relative to its
    /// nearest "unaltered" reference — major for Ionian/Lydian/Mixolydian (as bright or
    /// brighter than major), natural minor (Aeolian) for Dorian/Phrygian/Locrian (as dark or
    /// darker). Ionian itself has none (it IS the reference). Keyed by `ScaleDefinition.degree`
    /// (1 = Ionian ... 7 = Locrian, see `ScaleLibrary.all`'s family-1 rows) rather than by name,
    /// so it can never silently drift out of sync with a renamed `id`/`popularName`.
    public static func characteristicNotes(for mode: Mode) -> [PitchClass] {
        let intervals: [Int]
        switch mode.scale.degree {
        case 1: intervals = []       // Ionian — the reference itself
        case 2: intervals = [9]      // Dorian — natural 6th (vs. natural minor's b6)
        case 3: intervals = [1]      // Phrygian — b2 (vs. natural minor's natural 2nd)
        case 4: intervals = [6]      // Lydian — #4 (vs. major's perfect 4th)
        case 5: intervals = [10]     // Mixolydian — b7 (vs. major's major 7th)
        case 6: intervals = [8]      // Aeolian — b6 (vs. Dorian's natural 6th)
        case 7: intervals = [1, 6]   // Locrian — b2 AND b5 (even its own tonic triad is diminished)
        default: intervals = []
        }
        return intervals.map { mode.tonic + $0 }
    }

    /// One hand-reasoned (role, intensity) per (mode, diatonic degree) — see this file's own doc
    /// comment for the general reasoning (root motion by fifths, shared tones with the tonic,
    /// half-step pulls, diminished quality) applied by ear/analysis to each of the 7 modes
    /// individually, rather than copied from classical major/minor functional harmony. Degree 1
    /// is always `.home` (Locrian's is intentionally non-zero — see `computedRole`'s own comment
    /// on the same quirk).
    private static func standardRole(forScaleDegree scaleDegree: Int, chordDegree: Int) -> (ModalFunctionalRole, Double) {
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
