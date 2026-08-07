import XCTest
@testable import MusicTheoryKit

final class MajorKeySignatureTests: XCTestCase {
    func testWellKnownKeySignatures() {
        XCTAssertEqual(MajorKeySignature.forMajorTonic(0), .sharps(0)) // C
        XCTAssertEqual(MajorKeySignature.forMajorTonic(7), .sharps(1)) // G
        XCTAssertEqual(MajorKeySignature.forMajorTonic(2), .sharps(2)) // D
        XCTAssertEqual(MajorKeySignature.forMajorTonic(5), .flats(1))  // F
        XCTAssertEqual(MajorKeySignature.forMajorTonic(10), .flats(2)) // Bb
    }

    func testDMajorAffectedPitchClassesMatchItsActualSharps() {
        // D major: D E F# G A B C# — sharped notes are F and C.
        XCTAssertEqual(MajorKeySignature.forMajorTonic(2).affectedPitchClasses, Set([6, 1]))
    }

    func testBbMajorAffectedPitchClassesMatchItsActualFlats() {
        // Bb major: Bb C D Eb F G A — flatted notes are B and E.
        XCTAssertEqual(MajorKeySignature.forMajorTonic(10).affectedPitchClasses, Set([10, 3]))
    }
}
