import XCTest
@testable import MusicTheoryKit

final class ChordVoicingTests: XCTestCase {
    func testInversionZeroIsRootPosition() throws {
        let template = try XCTUnwrap(ChordVocabulary.byID("Ma7"))
        let chord = Chord(root: PitchClass(0), template: template)
        let voicing = chord.voicing(inversion: 0)
        XCTAssertEqual(voicing.orderedPitchClasses.map(\.value), [0, 4, 7, 11])
        XCTAssertEqual(voicing.bassPitchClass, PitchClass(0))
    }

    func testFirstAndSecondInversionRotateTheTriad() throws {
        let template = try XCTUnwrap(ChordVocabulary.byID("Ma"))
        let chord = Chord(root: PitchClass(0), template: template)
        XCTAssertEqual(chord.voicing(inversion: 1).orderedPitchClasses.map(\.value), [4, 7, 0])
        XCTAssertEqual(chord.voicing(inversion: 2).orderedPitchClasses.map(\.value), [7, 0, 4])
    }

    func testInversionWrapsRatherThanCrashingPastMaxInversion() throws {
        let template = try XCTUnwrap(ChordVocabulary.byID("Ma"))
        let chord = Chord(root: PitchClass(0), template: template)
        // 3 tones: inversion 3 wraps back to root position (3 % 3 == 0).
        XCTAssertEqual(chord.voicing(inversion: 3).orderedPitchClasses.map(\.value), [0, 4, 7])
    }

    func testMaxInversionMatchesToneCount() throws {
        let triad = try XCTUnwrap(ChordVocabulary.byID("Ma"))
        XCTAssertEqual(Chord.maxInversion(for: triad), 2)
        let seventh = try XCTUnwrap(ChordVocabulary.byID("Ma7"))
        XCTAssertEqual(Chord.maxInversion(for: seventh), 3)
    }

    func testBassOverrideFindsMatchingInversion() throws {
        let template = try XCTUnwrap(ChordVocabulary.byID("Ma"))
        let chord = Chord(root: PitchClass(0), template: template) // C major: C, E, G
        let voicing = try XCTUnwrap(chord.voicing(bassOverride: PitchClass(7))) // G in the bass -> 2nd inversion
        XCTAssertEqual(voicing.inversion, 2)
        XCTAssertEqual(voicing.bassPitchClass, PitchClass(7))
    }

    func testBassOverrideReturnsNilForANonChordTone() throws {
        let template = try XCTUnwrap(ChordVocabulary.byID("Ma"))
        let chord = Chord(root: PitchClass(0), template: template)
        XCTAssertNil(chord.voicing(bassOverride: PitchClass(2))) // D isn't a tone of C major
    }
}
