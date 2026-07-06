import XCTest
@testable import MusicTheoryKit

final class ModeTests: XCTestCase {

    func testCIonian() throws {
        let ionian = try XCTUnwrap(ScaleLibrary.byID("ionian"))
        let mode = Mode(tonic: PitchClass(0), scale: ionian)
        XCTAssertEqual(mode.pitchClassSet, Set([0, 2, 4, 5, 7, 9, 11].map(PitchClass.init)))
    }

    func testDDorianMatchesCIonian() throws {
        let dorian = try XCTUnwrap(ScaleLibrary.byID("dorian"))
        let ionian = try XCTUnwrap(ScaleLibrary.byID("ionian"))
        let dDorian = Mode(tonic: PitchClass(2), scale: dorian)
        let cIonian = Mode(tonic: PitchClass(0), scale: ionian)
        XCTAssertEqual(dDorian.pitchClassSet, cIonian.pitchClassSet)
    }

    func testDegreeWraps() throws {
        let ionian = try XCTUnwrap(ScaleLibrary.byID("ionian"))
        let mode = Mode(tonic: PitchClass(0), scale: ionian)
        XCTAssertEqual(mode.degree(1), PitchClass(0))
        XCTAssertEqual(mode.degree(8), mode.degree(1))
    }

    func testDisplayName() throws {
        let dorian = try XCTUnwrap(ScaleLibrary.byID("dorian"))
        let mode = Mode(tonic: PitchClass(2), scale: dorian)
        XCTAssertEqual(mode.displayName, "D Dorian")
    }
}
