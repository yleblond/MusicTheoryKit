import XCTest
@testable import MusicTheoryKit

final class DiatonicSpellingTests: XCTestCase {

    private func spelling(_ pitches: [SpelledPitch]) -> [String] {
        pitches.map { "\($0.letter)\($0.accidental.symbol)" }
    }

    func testAbMajorSpelling() throws {
        let mode = Mode(tonic: PitchClass(8), scale: try XCTUnwrap(ScaleLibrary.byID("ionian")))
        let degrees = try XCTUnwrap(DiatonicSpelling.spelledDegrees(for: mode))
        XCTAssertEqual(spelling(degrees), ["A♭", "B♭", "C", "D♭", "E♭", "F", "G"])
    }

    func testEMajorSpelling() throws {
        let mode = Mode(tonic: PitchClass(4), scale: try XCTUnwrap(ScaleLibrary.byID("ionian")))
        let degrees = try XCTUnwrap(DiatonicSpelling.spelledDegrees(for: mode))
        XCTAssertEqual(spelling(degrees), ["E", "F♯", "G♯", "A", "B", "C♯", "D♯"])
    }

    func testDDorianSpellingMatchesItsCMajorParentRotatedToD() throws {
        let mode = Mode(tonic: PitchClass(2), scale: try XCTUnwrap(ScaleLibrary.byID("dorian")))
        let degrees = try XCTUnwrap(DiatonicSpelling.spelledDegrees(for: mode))
        XCTAssertEqual(spelling(degrees), ["D", "E", "F", "G", "A", "B", "C"])
    }

    func testGLocrianSpellingMatchesItsAbMajorParentRotatedToG() throws {
        let mode = Mode(tonic: PitchClass(7), scale: try XCTUnwrap(ScaleLibrary.byID("locrian")))
        let degrees = try XCTUnwrap(DiatonicSpelling.spelledDegrees(for: mode))
        XCTAssertEqual(spelling(degrees), ["G", "A♭", "B♭", "C", "D♭", "E♭", "F"])
    }

    func testEveryDegreeMatchesTheModesOwnPitchClasses() throws {
        let mode = Mode(tonic: PitchClass(8), scale: try XCTUnwrap(ScaleLibrary.byID("ionian")))
        let degrees = try XCTUnwrap(DiatonicSpelling.spelledDegrees(for: mode))
        XCTAssertEqual(degrees.map(\.pitchClass), mode.pitchClasses)
    }

    func testNonFamilyOneScaleReturnsNil() throws {
        // Harmonic minor (or whichever non-family-1 scale) has no well-defined parent major key.
        let harmonicMinor = try XCTUnwrap(ScaleLibrary.all.first { $0.familyID != 1 })
        let mode = Mode(tonic: PitchClass(0), scale: harmonicMinor)
        XCTAssertNil(DiatonicSpelling.spelledDegrees(for: mode))
    }
}
