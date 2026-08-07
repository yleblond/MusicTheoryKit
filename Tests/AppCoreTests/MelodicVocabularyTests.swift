import XCTest
@testable import AppCore
@testable import MusicTheoryKit

final class MelodicVocabularyTests: XCTestCase {
    private func profile(_ analysis: MelodicVocabularyAnalysis, note: Int) -> MelodicNoteProfile {
        analysis.notes.first { $0.note == PitchClass(note) }!
    }

    /// The spec's own worked example: D Dorian, G7 (the IV chord) selected — G B D F, with
    /// D/E/F/G/A/B/C read against it as 5/13/b7/1/9/3/11. Confirms both the raw interval facts
    /// AND the qualitative role outcome the spec calls out explicitly: chord tones (F, B) are
    /// NOT automatically "stable" (they classify as `.chordTone`), the 13th (E) is `.color` (not
    /// tension, despite sitting a half-step above the chord's own b7), and the natural 11 (C) —
    /// the textbook avoid-note half-step above a major 3rd — IS tension.
    func testG7OverDDorianMatchesTheSpecsWorkedExample() {
        let dorian = ScaleLibrary.scales(inFamily: 1).first { $0.degree == 2 }!
        let mode = Mode(tonic: PitchClass(2), scale: dorian) // D Dorian
        let chord = Chord(root: PitchClass(7), template: ChordVocabulary.byID("7")!) // G7

        let analysis = MelodicVocabularyAnalyzer.analyze(mode: mode, chord: chord)
        XCTAssertEqual(analysis.notes.count, 7)

        let d = profile(analysis, note: 2), e = profile(analysis, note: 4), f = profile(analysis, note: 5)
        let g = profile(analysis, note: 7), a = profile(analysis, note: 9), b = profile(analysis, note: 11)
        let c = profile(analysis, note: 0)

        XCTAssertEqual(d.intervalFromChordRoot, 7); XCTAssertEqual(d.chordToneType, .fifth); XCTAssertEqual(d.defaultRole, .stable)
        XCTAssertEqual(g.intervalFromChordRoot, 0); XCTAssertEqual(g.chordToneType, .root); XCTAssertEqual(g.defaultRole, .stable)
        XCTAssertEqual(f.intervalFromChordRoot, 10); XCTAssertEqual(f.chordToneType, .seventh); XCTAssertEqual(f.defaultRole, .chordTone)
        XCTAssertEqual(b.intervalFromChordRoot, 4); XCTAssertEqual(b.chordToneType, .third); XCTAssertEqual(b.defaultRole, .chordTone)
        XCTAssertEqual(e.intervalFromChordRoot, 9); XCTAssertEqual(e.extensionType, "13"); XCTAssertEqual(e.defaultRole, .color)
        XCTAssertEqual(a.intervalFromChordRoot, 2); XCTAssertEqual(a.extensionType, "9"); XCTAssertEqual(a.defaultRole, .color)
        XCTAssertEqual(c.intervalFromChordRoot, 5); XCTAssertEqual(c.extensionType, "11"); XCTAssertEqual(c.defaultRole, .tension)

        // B is dorian's own characteristic note (the natural 6th vs. natural minor) — modally
        // identifying even though its melodic role here is plain chord-tone, per the spec's
        // "a note can be both COLOR/CHORD-TONE and ◆ MODAL, independently" requirement.
        XCTAssertEqual(b.modalIdentity, 1.0)
        XCTAssertEqual(d.modalIdentity, 0.0)
    }

    func testChangingChordWithoutChangingModeChangesFunctionButNotTheNoteSet() {
        let dorian = ScaleLibrary.scales(inFamily: 1).first { $0.degree == 2 }!
        let mode = Mode(tonic: PitchClass(2), scale: dorian)
        let onG7 = MelodicVocabularyAnalyzer.analyze(mode: mode, chord: Chord(root: PitchClass(7), template: ChordVocabulary.byID("7")!))
        let onDm7 = MelodicVocabularyAnalyzer.analyze(mode: mode, chord: Chord(root: PitchClass(2), template: ChordVocabulary.byID("mi7")!))

        XCTAssertEqual(Set(onG7.notes.map(\.note)), Set(onDm7.notes.map(\.note)), "same mode, same note set")
        let bOnG7 = profile(onG7, note: 11), bOnDm7 = profile(onDm7, note: 11)
        XCTAssertNotEqual(bOnG7.intervalFromChordRoot, bOnDm7.intervalFromChordRoot)
        // B stays modally characteristic of Dorian regardless of which chord is sounding.
        XCTAssertEqual(bOnG7.modalIdentity, 1.0)
        XCTAssertEqual(bOnDm7.modalIdentity, 1.0)
    }

    func testNonFamilyOneScaleStillAnalyzesWithLowerConfidenceAndNoModalIdentity() {
        let harmonicMinor = ScaleLibrary.scales(inFamily: 2).first!
        let mode = Mode(tonic: PitchClass(0), scale: harmonicMinor)
        let chord = Chord(root: PitchClass(0), template: ChordVocabulary.byID("mi")!)
        let analysis = MelodicVocabularyAnalyzer.analyze(mode: mode, chord: chord)

        XCTAssertFalse(analysis.notes.isEmpty)
        XCTAssertTrue(analysis.characteristicNotes.isEmpty)
        XCTAssertLessThan(analysis.confidence, 0.9)
        for note in analysis.notes {
            XCTAssertEqual(note.modalIdentity, 0.0)
            XCTAssertGreaterThanOrEqual(note.structuralStability, 0)
            XCTAssertLessThanOrEqual(note.structuralStability, 1)
        }
    }

    /// The spec's own point (§35-36): the engine must not be limited to 7-note diatonic scales.
    /// The whole-tone scale (6 notes, family 6 — a real, already-registered `ScaleDefinition`,
    /// unlike `ScaleFamilies` itself which has no runtime-registration API to fabricate an
    /// arbitrary pentatonic family for a test) is as structurally different from a classic mode
    /// as it gets, and should still analyze without crashing or needing any special-casing.
    func testNonDiatonicScalesLikeWholeToneStillAnalyzeWithoutCrashing() {
        let wholeTone = ScaleLibrary.byID("whole_tone")!
        let mode = Mode(tonic: PitchClass(0), scale: wholeTone)
        XCTAssertEqual(mode.pitchClasses.map(\.value), [0, 2, 4, 6, 8, 10])

        let chord = Chord(root: PitchClass(0), template: ChordVocabulary.byID("7#5")!)
        let analysis = MelodicVocabularyAnalyzer.analyze(mode: mode, chord: chord)
        XCTAssertEqual(analysis.notes.count, 6)
        XCTAssertTrue(analysis.characteristicNotes.isEmpty)
        XCTAssertLessThan(analysis.confidence, 0.9)
        for note in analysis.notes {
            XCTAssertGreaterThanOrEqual(note.harmonicDissonance, 0)
            XCTAssertLessThanOrEqual(note.harmonicDissonance, 1)
        }
    }

    func testResolutionsStayWithinTwoSemitonesAndFavorChordTones() {
        let dorian = ScaleLibrary.scales(inFamily: 1).first { $0.degree == 2 }!
        let mode = Mode(tonic: PitchClass(2), scale: dorian)
        let chord = Chord(root: PitchClass(7), template: ChordVocabulary.byID("7")!)
        let analysis = MelodicVocabularyAnalyzer.analyze(mode: mode, chord: chord)
        for note in analysis.notes {
            for resolution in note.resolutions {
                XCTAssertTrue((1...2).contains(resolution.semitones))
                XCTAssertGreaterThanOrEqual(resolution.strength, 0.3)
            }
        }
    }

    func testDetectApproachResolution() {
        let chord = Chord(root: PitchClass(7), template: ChordVocabulary.byID("7")!) // G7: G B D F
        XCTAssertTrue(MelodicVocabularyAnalyzer.detectApproachResolution(from: PitchClass(6), to: PitchClass(7), chord: chord)) // F#->G, semitone into the root
        XCTAssertFalse(MelodicVocabularyAnalyzer.detectApproachResolution(from: PitchClass(6), to: PitchClass(1), chord: chord)) // target not a chord tone
        XCTAssertFalse(MelodicVocabularyAnalyzer.detectApproachResolution(from: PitchClass(0), to: PitchClass(7), chord: chord)) // too far (5 semitones)
    }
}
