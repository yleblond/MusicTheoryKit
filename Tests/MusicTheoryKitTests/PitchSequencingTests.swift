import XCTest
@testable import MusicTheoryKit

final class PitchSequencingTests: XCTestCase {
    func testAscendingPitchesStrictlyIncreaseAndPreserveOrderedPitchClasses() {
        // A pitch-class sequence that wraps past 12 as raw ints (e.g. a mode transposed to a
        // high tonic) must still come out strictly ascending in real MIDI pitches.
        let pitchClasses = [9, 11, 1, 2, 4, 6, 8] // A Ionian-esque wrap-around example
        let pitches = PitchSequencing.ascendingPitches(forPitchClasses: pitchClasses, startingAbove: 47)
        for (previous, next) in zip(pitches, pitches.dropFirst()) {
            XCTAssertLessThan(previous, next)
        }
        XCTAssertEqual(pitches.map { (($0 % 12) + 12) % 12 }, pitchClasses)
        XCTAssertGreaterThan(pitches[0], 47)
    }

    func testEmptyInputProducesEmptyOutput() {
        XCTAssertEqual(PitchSequencing.ascendingPitches(forPitchClasses: [], startingAbove: 60), [])
    }
}
