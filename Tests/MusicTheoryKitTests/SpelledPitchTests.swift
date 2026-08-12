import XCTest
@testable import MusicTheoryKit

final class SpelledPitchTests: XCTestCase {

    func testNaturalLettersMatchStandardPitchClasses() {
        XCTAssertEqual(NoteLetter.C.naturalPitchClass, 0)
        XCTAssertEqual(NoteLetter.D.naturalPitchClass, 2)
        XCTAssertEqual(NoteLetter.E.naturalPitchClass, 4)
        XCTAssertEqual(NoteLetter.F.naturalPitchClass, 5)
        XCTAssertEqual(NoteLetter.G.naturalPitchClass, 7)
        XCTAssertEqual(NoteLetter.A.naturalPitchClass, 9)
        XCTAssertEqual(NoteLetter.B.naturalPitchClass, 11)
    }

    func testLineOfFifthsMatchesStandardConvention() {
        // The well-known line of fifths: ...Eb Bb F C G D A E B F# C#...
        XCTAssertEqual(NoteLetter.F.lineOfFifths, -1)
        XCTAssertEqual(NoteLetter.C.lineOfFifths, 0)
        XCTAssertEqual(NoteLetter.G.lineOfFifths, 1)
        XCTAssertEqual(NoteLetter.D.lineOfFifths, 2)
        XCTAssertEqual(NoteLetter.A.lineOfFifths, 3)
        XCTAssertEqual(NoteLetter.E.lineOfFifths, 4)
        XCTAssertEqual(NoteLetter.B.lineOfFifths, 5)
    }

    func testSharpAndFlatGSpellingsAreDistinctLineOfFifthsButSamePitchClass() {
        let gSharp = SpelledPitch(letter: .G, accidental: .sharp, octave: 4)
        let aFlat = SpelledPitch(letter: .A, accidental: .flat, octave: 4)
        XCTAssertEqual(gSharp.pitchClass, aFlat.pitchClass, "both should collapse to the same key")
        XCTAssertEqual(gSharp.lineOfFifths, 8)
        XCTAssertEqual(aFlat.lineOfFifths, -4)
        XCTAssertNotEqual(gSharp.lineOfFifths, aFlat.lineOfFifths, "but their spelling identity must differ")
    }

    func testDFlatLineOfFifths() {
        let dFlat = SpelledPitch(letter: .D, accidental: .flat, octave: 3)
        XCTAssertEqual(dFlat.lineOfFifths, -5)
        XCTAssertEqual(dFlat.pitchClass.value, 1)
    }

    func testAccidentalSemitoneAndFifthsOffsetsAreConsistent() {
        XCTAssertEqual(Accidental.sharp.semitoneOffset, 1)
        XCTAssertEqual(Accidental.sharp.lineOfFifthsOffset, 7)
        XCTAssertEqual(Accidental.flat.semitoneOffset, -1)
        XCTAssertEqual(Accidental.flat.lineOfFifthsOffset, -7)
        XCTAssertEqual(Accidental.doubleSharp.lineOfFifthsOffset, 14)
        XCTAssertEqual(Accidental.natural.symbol, "")
    }
}
