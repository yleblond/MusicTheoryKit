import MusicTheoryKit

/// A single note's pedagogical color in the "Vocabulaire mélodique" panel — deliberately
/// distinct from `ModalFunctionalRole` (which colors ACCORDS relative to the tonic): this colors
/// NOTES relative to whichever chord is currently selected. See `MelodicVocabularyAnalyzer`'s own
/// doc comment for how a `MelodicNoteProfile`'s numeric dimensions turn into one of these.
public enum MelodicRole: String, Codable, CaseIterable, Sendable {
    case stable, chordTone, color, tension, contextual
}

/// Which structural slot of the chord a chord-tone note fills — `.other` covers any extension
/// baked directly into the chord's own template (e.g. the added 9th in a "Ma9" template), as
/// opposed to `MelodicNoteProfile.extensionType` (a mode tone that ISN'T part of the chord at all).
public enum ChordToneType: String, Codable, Sendable {
    case root, third, fifth, seventh, other
}

public enum ResolutionDirection: String, Codable, Sendable { case up, down }

public enum ResolutionReason: String, Codable, Sendable {
    case semitone, chordTone, voiceLeading, modal, contextual
}

/// One candidate "this note wants to move here" — see `MelodicVocabularyAnalyzer.resolutions(for:in:chord:)`.
public struct MelodicResolution: Sendable, Equatable {
    public let targetNote: PitchClass
    public let direction: ResolutionDirection
    public let semitones: Int
    public let strength: Double
    public let reason: ResolutionReason
}

/// Everything computed about one of the mode's own notes relative to the currently selected
/// chord — Layers 1 (`intervalFromChordRoot`...`extensionType`) and 2
/// (`structuralStability`...`confidence`) of `MelodicVocabularyAnalyzer`'s pipeline, still with NO
/// color/label of any kind: `JamShackUI`'s presentation layer (`melodicRolePresentation(for:)`)
/// is the only place a role turns into a color, exactly so the numeric facts below stay reusable
/// (e.g. for a future "detailed analysis" bar view) independent of any one presentation choice.
public struct MelodicNoteProfile: Sendable, Equatable {
    public let note: PitchClass
    public let intervalFromChordRoot: Int // 0...11, semitones above the chord's own root
    public let isChordTone: Bool
    public let chordToneType: ChordToneType?
    public let isExtension: Bool
    /// "b9"/"9"/"#9"/"11"/"#11"/"b13"/"13" — only set when `isExtension`.
    public let extensionType: String?
    public let structuralStability: Double
    public let consonance: Double
    public let harmonicDissonance: Double
    public let colorStrength: Double
    public let resolutionTendency: Double
    /// How strongly this note is one of the MODE's own defining notes (independent of the
    /// current chord) — see `ModalFunctionalMapBuilder.characteristicNotes(for:)`. Only
    /// meaningful with full confidence for the 7 classic modes; see `confidence`.
    public let modalIdentity: Double
    public let resolutions: [MelodicResolution]
    /// Lower outside the 7 classic modes (`familyID == 1`) — `modalIdentity` has no established
    /// reference there, so this profile leans more on the generically-computable dimensions.
    /// Never fabricates a false certainty rather than admit that (see this file's own doc
    /// comment on `MelodicVocabularyAnalyzer`).
    public let confidence: Double
    public let defaultRole: MelodicRole
}

/// One note actually played (via the panel's own playable row/keyboard) — `MelodicContext`'s
/// own rolling window, see `MelodicVocabularyAnalyzer.detectApproachResolution(from:to:chord:)`.
public struct PlayedNote: Sendable, Equatable {
    public let pitchClass: PitchClass
    public init(pitchClass: PitchClass) { self.pitchClass = pitchClass }
}

/// Everything `MelodicVocabularyAnalyzer.analyze(mode:chord:)` returns for the currently selected
/// chord — one `MelodicNoteProfile` per note of `mode`'s own scale, in scale-degree order.
public struct MelodicVocabularyAnalysis: Sendable {
    public let mode: Mode
    public let chord: Chord
    public let notes: [MelodicNoteProfile]
    public let characteristicNotes: [PitchClass]
    public let confidence: Double
}

/// Computes a `MelodicVocabularyAnalysis` from raw interval math — deliberately NOT a
/// `switch mode.scale.systematicName` (see this file's own guiding principle, carried over from
/// the harmonic map's own `ModalFunctionalMapBuilder`): every dimension below is derived from (1)
/// the note's own semitone distance to the chord's root, (2) its distance to the chord's OTHER
/// tones, and (3) whether it's one of the mode's own characteristic notes — none of which assumes
/// a 7-note diatonic scale, a particular scale family, or any named mode. A pentatonic scale, a
/// whole-tone scale, or a mode of the melodic minor all run through the exact same code path;
/// only `modalIdentity` (which has no defined meaning outside the 7 classic modes today) degrades
/// gracefully via a lower `confidence` rather than refusing to analyze at all.
///
/// Every threshold/weight below is a first-pass, clearly-labeled pedagogical judgment call (like
/// `ModalFunctionalMapBuilder`'s own computed formula) — not a musicological law. Expect to tune
/// these once real use surfaces cases where the classification feels wrong.
public enum MelodicVocabularyAnalyzer {
    public static func analyze(mode: Mode, chord: Chord) -> MelodicVocabularyAnalysis {
        let characteristics = mode.scale.familyID == 1 ? ModalFunctionalMapBuilder.characteristicNotes(for: mode) : []
        let confidence = mode.scale.familyID == 1 ? 0.9 : 0.75
        let notes = mode.pitchClasses.map { note in
            profile(for: note, chord: chord, scaleNotes: mode.pitchClasses, characteristicNotes: characteristics, confidence: confidence)
        }
        return MelodicVocabularyAnalysis(mode: mode, chord: chord, notes: notes, characteristicNotes: characteristics, confidence: confidence)
    }

    /// A note a semitone or a whole tone away from `current`, immediately followed by `current`
    /// landing on one of the chord's own tones — the only context signal V1 acts on (see
    /// `App/Sources/ModeLibraryView.swift`'s own recent-notes history), matching this feature's
    /// own "V1 effects stay light" guidance rather than a full melodic-phrase analysis.
    public static func detectApproachResolution(from previous: PitchClass, to current: PitchClass, chord: Chord) -> Bool {
        let semitoneDistance = min(previous.distance(to: current), current.distance(to: previous))
        return semitoneDistance > 0 && semitoneDistance <= 2 && chord.pitchClassSet.contains(current)
    }

    // MARK: - Per-note profile

    private static func profile(
        for note: PitchClass, chord: Chord, scaleNotes: [PitchClass], characteristicNotes: [PitchClass], confidence: Double
    ) -> MelodicNoteProfile {
        let interval = chord.root.distance(to: note)
        let chordIntervals = chord.template.intervalsFromRoot.map { (($0 % 12) + 12) % 12 }
        let slotIndex = chordIntervals.firstIndex(of: interval)
        let isChordTone = slotIndex != nil
        let chordToneType: ChordToneType? = slotIndex.map { index in
            switch index {
            case 0: return .root
            case 1: return .third
            case 2: return .fifth
            case 3: return .seventh
            default: return .other
            }
        }
        let extensionType = isChordTone ? nil : Self.extensionLabel[interval]
        let isExtension = !isChordTone && extensionType != nil

        let dissonance = harmonicDissonance(of: note, isChordTone: isChordTone, against: chord)
        let consonance = 1 - dissonance
        let stability = structuralStability(chordToneType: chordToneType, interval: interval, isExtension: isExtension)
        let colorStrength = isExtension ? max(0, 1 - dissonance * 1.2) : 0.15
        let resolutionTendency = self.resolutionTendency(dissonance: dissonance, isChordTone: isChordTone, note: note, chord: chord)
        let modalIdentity: Double = characteristicNotes.contains(note) ? 1.0 : 0.0
        let resolutions = self.resolutions(for: note, in: scaleNotes, chord: chord)

        let role = classifyMelodicRole(
            structuralStability: stability, isChordTone: isChordTone, harmonicDissonance: dissonance,
            colorStrength: colorStrength, resolutionTendency: resolutionTendency
        )

        return MelodicNoteProfile(
            note: note, intervalFromChordRoot: interval, isChordTone: isChordTone, chordToneType: chordToneType,
            isExtension: isExtension, extensionType: extensionType, structuralStability: stability, consonance: consonance,
            harmonicDissonance: dissonance, colorStrength: colorStrength, resolutionTendency: resolutionTendency,
            modalIdentity: modalIdentity, resolutions: resolutions, confidence: confidence, defaultRole: role
        )
    }

    /// Standard jazz-harmony extension names for every semitone a chord tone doesn't already
    /// occupy — a chord whose own template DOES occupy one of these (e.g. an add9 chord's own
    /// 9th) never reaches this table, since `isChordTone` already claimed it first.
    private static let extensionLabel: [Int: String] = [
        1: "b9", 2: "9", 3: "#9", 4: "3", 5: "11", 6: "#11", 8: "b13", 9: "13",
    ]

    /// Root/fifth read as more structurally stable than third/seventh even though all four can
    /// be genuine chord tones — see this file's own doc comment on why `isChordTone` must never
    /// imply "stable" by itself (a dominant chord's third and seventh are exactly what MAKE it a
    /// dominant, i.e. exactly what make it want to move). Extensions get a lower ceiling still,
    /// tiered by how commonly they're treated as a "sweet" color (9/13) vs. a "spicy" alteration
    /// (b9/#9/b13/#11).
    private static func structuralStability(chordToneType: ChordToneType?, interval: Int, isExtension: Bool) -> Double {
        if let chordToneType {
            switch chordToneType {
            case .root: return 1.0
            case .fifth: return 0.85
            case .third: return 0.55
            case .seventh: return 0.45
            case .other: return 0.5
            }
        }
        if isExtension {
            switch interval {
            case 2, 9: return 0.45 // 9, 13
            case 5: return 0.4     // 11
            case 1, 3, 6, 8: return 0.2 // b9, #9, #11, b13
            default: return 0.3
            }
        }
        return 0.3
    }

    /// The strongest clash this note forms against any of the chord's OWN tones — a semitone
    /// apart is treated as the sharpest friction (the spec's own "half-step above the third"
    /// example — the textbook natural-11-against-a-major-3rd avoid note), a tritone as a
    /// milder-but-real characteristic tension, everything else mild. Being an actual chord tone
    /// tempers the felt dissonance even when the interval math alone would call it sharp (e.g. a
    /// dominant 7th chord's own tritone between its 3rd and b7 reads as that chord's character,
    /// not as a clash, once both notes are already "inside" it).
    ///
    /// A half-step specifically against the SEVENTH is discounted rather than scored like one
    /// against the root/third: a 13th sitting a half-step above a dominant chord's own b7 is one
    /// of the most standard, pleasant extensions in real jazz harmony (`G13` chords are
    /// everywhere) — nothing like a b9's harshness against the root, even though both are, in
    /// raw interval terms, "a semitone away from a chord tone." Confirmed against this file's
    /// own G7-in-D-Dorian test case: without this discount the 13th (E) misclassified as tension
    /// instead of color.
    private static func harmonicDissonance(of note: PitchClass, isChordTone: Bool, against chord: Chord) -> Double {
        let slotByTone = chordToneSlots(for: chord)
        var worst = 0.1
        for tone in chord.pitchClassSet where tone != note {
            let distance = min(note.distance(to: tone), tone.distance(to: note))
            var clash: Double
            switch distance {
            case 1: clash = 0.85
            case 2: clash = 0.3
            case 6: clash = 0.55
            default: clash = 0.1
            }
            if distance == 1 && slotByTone[tone] == .seventh { clash *= 0.35 }
            worst = max(worst, clash)
        }
        if isChordTone { worst *= 0.4 }
        return min(worst, 1)
    }

    private static func chordToneSlots(for chord: Chord) -> [PitchClass: ChordToneType] {
        var slots: [PitchClass: ChordToneType] = [:]
        for (index, interval) in chord.template.intervalsFromRoot.enumerated() {
            let type: ChordToneType
            switch index {
            case 0: type = .root
            case 1: type = .third
            case 2: type = .fifth
            case 3: type = .seventh
            default: type = .other
            }
            slots[chord.root + interval] = type
        }
        return slots
    }

    /// Distinct from raw dissonance: a dissonant note with no close resolution target just sits
    /// there as color rather than urgently pulling anywhere (see this file's own doc comment on
    /// keeping COLOR and TENSION separable).
    private static func resolutionTendency(dissonance: Double, isChordTone: Bool, note: PitchClass, chord: Chord) -> Double {
        let nearestChordToneDistance = chord.pitchClassSet
            .map { min(note.distance(to: $0), $0.distance(to: note)) }
            .filter { $0 > 0 }
            .min() ?? 6
        let proximityBoost: Double = nearestChordToneDistance <= 2 ? 1.0 : (nearestChordToneDistance <= 4 ? 0.6 : 0.3)
        let ownWeight = isChordTone ? 0.7 : 1.1
        return min(1, dissonance * proximityBoost * ownWeight)
    }

    /// Up to 2 nearby (≤2 semitone) scale notes this note might resolve toward, favoring ones
    /// that are themselves chord tones (an actual landing point) over ones that are merely
    /// closer scale neighbors — mirrors the "economical voice-leading" preference real
    /// resolutions follow, without claiming any one of these is THE correct resolution.
    private static func resolutions(for note: PitchClass, in scaleNotes: [PitchClass], chord: Chord) -> [MelodicResolution] {
        var candidates: [MelodicResolution] = []
        for target in scaleNotes where target != note {
            let isTargetChordTone = chord.pitchClassSet.contains(target)
            let targetStability: Double = isTargetChordTone ? 0.8 : 0.25
            let up = (target.value - note.value + 12) % 12
            let down = (note.value - target.value + 12) % 12
            if up > 0, up <= 2 {
                candidates.append(MelodicResolution(
                    targetNote: target, direction: .up, semitones: up,
                    strength: proximityScore(up) * targetStability, reason: isTargetChordTone ? .chordTone : .voiceLeading
                ))
            }
            if down > 0, down <= 2 {
                candidates.append(MelodicResolution(
                    targetNote: target, direction: .down, semitones: down,
                    strength: proximityScore(down) * targetStability, reason: isTargetChordTone ? .chordTone : .voiceLeading
                ))
            }
        }
        return candidates.sorted { $0.strength > $1.strength }.filter { $0.strength >= 0.3 }.prefix(2).map { $0 }
    }

    private static func proximityScore(_ semitones: Int) -> Double { semitones == 1 ? 1.0 : 0.6 }

    // MARK: - Layer 3 boundary

    /// The ONLY place a numeric profile turns into a `MelodicRole` — everything past this point
    /// (color, label, icon, explanation) belongs to `JamShackUI`'s presentation layer instead,
    /// same "no musicological rule in the UI" boundary `ModalFunctionalMapBuilder`'s own role
    /// classification already keeps.
    public static func classifyMelodicRole(
        structuralStability: Double, isChordTone: Bool, harmonicDissonance: Double, colorStrength: Double, resolutionTendency: Double
    ) -> MelodicRole {
        if structuralStability > 0.8 && harmonicDissonance < 0.2 { return .stable }
        if isChordTone && harmonicDissonance < 0.5 { return .chordTone }
        if colorStrength > 0.55 && resolutionTendency < 0.5 { return .color }
        if harmonicDissonance > 0.55 || resolutionTendency > 0.65 { return .tension }
        return .contextual
    }
}
