import XCTest
@testable import MusicTheoryKit

final class ScaleLibraryTests: XCTestCase {

    /// Ground truth transcribed directly from scales_of_harmonies.pdf (½=1, 1=2, 1½=3 semitones),
    /// independent of the family/rotation generator. Every entry must match exactly.
    static let expectedIntervalSteps: [String: [Int]] = [
        "ionian": [2, 2, 1, 2, 2, 2, 1],
        "dorian": [2, 1, 2, 2, 2, 1, 2],
        "phrygian": [1, 2, 2, 2, 1, 2, 2],
        "lydian": [2, 2, 2, 1, 2, 2, 1],
        "mixolydian": [2, 2, 1, 2, 2, 1, 2],
        "aeolian": [2, 1, 2, 2, 1, 2, 2],
        "locrian": [1, 2, 2, 1, 2, 2, 2],

        "altered": [1, 2, 1, 2, 2, 2, 2],
        "melodic_minor": [2, 1, 2, 2, 2, 2, 1],
        "dorian_b2": [1, 2, 2, 2, 2, 1, 2],
        "lydian_augmented": [2, 2, 2, 2, 1, 2, 1],
        "lydian_dominant": [2, 2, 2, 1, 2, 1, 2],
        "aeolian_dominant": [2, 2, 1, 2, 1, 2, 2],
        "half_diminished": [2, 1, 2, 1, 2, 2, 2],

        "major_augmented": [2, 2, 1, 3, 1, 2, 1],
        "dorian_4": [2, 1, 3, 1, 2, 1, 2],
        "phrygian_dominant": [1, 3, 1, 2, 1, 2, 2],
        "lydian_2": [3, 1, 2, 1, 2, 2, 1],
        "altered_dominant_bb7": [1, 2, 1, 2, 2, 1, 3],
        "harmonic_minor": [2, 1, 2, 2, 1, 3, 1],
        "locrian_nat6": [1, 2, 2, 1, 3, 1, 2],

        "harmonic_major": [2, 2, 1, 2, 1, 3, 1],
        "dorian_b5": [2, 1, 2, 1, 3, 1, 2],
        "phrygian_b4": [1, 2, 1, 3, 1, 2, 2],
        "lydian_b3": [2, 1, 3, 1, 2, 2, 1],
        "mixolydian_b2": [1, 3, 1, 2, 2, 1, 2],
        "lydian_augmented_2": [3, 1, 2, 2, 1, 2, 1],
        "locrian_bb7": [1, 2, 2, 1, 2, 1, 3],

        "diminished": [2, 1, 2, 1, 2, 1, 2, 1],
        "dominant_diminished": [1, 2, 1, 2, 1, 2, 1, 2],

        "whole_tone": [2, 2, 2, 2, 2, 2],

        "augmented": [3, 1, 3, 1, 3, 1],
        "inverted_augmented": [1, 3, 1, 3, 1, 3],
    ]

    func testTotalCount() {
        XCTAssertEqual(ScaleLibrary.all.count, 33)
    }

    func testUniqueIDs() {
        let ids = ScaleLibrary.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testLiteralIntervalSteps() throws {
        for (id, expected) in Self.expectedIntervalSteps {
            let scale = try XCTUnwrap(ScaleLibrary.byID(id), "missing scale \(id)")
            XCTAssertEqual(scale.intervalSteps, expected, "\(id) interval steps mismatch")
        }
    }

    func testEveryExpectedIDIsCovered() {
        let libraryIDs = Set(ScaleLibrary.all.map(\.id))
        let expectedIDs = Set(Self.expectedIntervalSteps.keys)
        XCTAssertEqual(libraryIDs, expectedIDs, "expected ground truth and library ids diverge")
    }

    func testStepsSumToOctave() {
        for scale in ScaleLibrary.all {
            XCTAssertEqual(scale.intervalSteps.reduce(0, +), 12, "\(scale.id) does not sum to 12 semitones")
        }
    }

    func testPitchClassesAreDistinct() {
        for scale in ScaleLibrary.all {
            let pitchClasses = scale.pitchClassesFromRoot
            XCTAssertEqual(pitchClasses.count, scale.noteCount)
            XCTAssertEqual(Set(pitchClasses).count, pitchClasses.count, "\(scale.id) has duplicate pitch classes")
            XCTAssertEqual(pitchClasses.first, 0)
        }
    }

    func testFamilySizes() {
        XCTAssertEqual(ScaleLibrary.scales(inFamily: 1).count, 7)
        XCTAssertEqual(ScaleLibrary.scales(inFamily: 2).count, 7)
        XCTAssertEqual(ScaleLibrary.scales(inFamily: 3).count, 7)
        XCTAssertEqual(ScaleLibrary.scales(inFamily: 4).count, 7)
        XCTAssertEqual(ScaleLibrary.scales(inFamily: 5).count, 2)
        XCTAssertEqual(ScaleLibrary.scales(inFamily: 6).count, 1)
        XCTAssertEqual(ScaleLibrary.scales(inFamily: 7).count, 2)
    }
}
