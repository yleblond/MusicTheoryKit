import XCTest
@testable import PieceModel

final class MelodicFragmentTests: XCTestCase {

    /// A simple ascending triad-outline motif, C-E-G-C (durations irrelevant here).
    func makeFragment(mode: IntervalReferenceMode) -> MelodicFragment {
        switch mode {
        case .fromFirstNote:
            return MelodicFragment(name: "test", referenceMode: .fromFirstNote, intervals: [4, 7, 12], noteDurations: [1, 1, 1, 1])
        case .fromPreviousNote:
            return MelodicFragment(name: "test", referenceMode: .fromPreviousNote, intervals: [4, 3, 5], noteDurations: [1, 1, 1, 1])
        }
    }

    func testFromFirstNoteAbsolutePitches() {
        let fragment = makeFragment(mode: .fromFirstNote)
        XCTAssertEqual(fragment.absolutePitches(basePitch: 60), [60, 64, 67, 72])
    }

    func testFromPreviousNoteAbsolutePitches() {
        let fragment = makeFragment(mode: .fromPreviousNote)
        XCTAssertEqual(fragment.absolutePitches(basePitch: 60), [60, 64, 67, 72])
    }

    func testRetrogradePreservesShapeReversed() {
        for mode in [IntervalReferenceMode.fromFirstNote, .fromPreviousNote] {
            let fragment = makeFragment(mode: mode)
            let retrograded = fragment.retrograded()
            let originalPitches = fragment.absolutePitches(basePitch: 60)
            // `absolutePitches` always anchors the fragment's own first note at `basePitch`,
            // so the retrograded fragment's "first note" is the original's last note: anchor
            // there to get the exact reverse of the original pitch sequence.
            let retrogradedPitches = retrograded.absolutePitches(basePitch: originalPitches.last!)
            XCTAssertEqual(retrogradedPitches, Array(originalPitches.reversed()), "mode \(mode)")
            XCTAssertEqual(retrograded.noteDurations, Array(fragment.noteDurations.reversed()))
        }
    }

    func testInversionAroundFirstNoteMirrorsContour() {
        for mode in [IntervalReferenceMode.fromFirstNote, .fromPreviousNote] {
            let fragment = makeFragment(mode: mode)
            let inverted = fragment.inverted()
            // Inverting around the first note: shape[i] -> -shape[i], so absolute pitch
            // becomes basePitch - (originalPitch - basePitch).
            let originalPitches = fragment.absolutePitches(basePitch: 60)
            let invertedPitches = inverted.absolutePitches(basePitch: 60)
            let expected = originalPitches.map { 2 * 60 - $0 }
            XCTAssertEqual(invertedPitches, expected, "mode \(mode)")
        }
    }

    func testInversionRoundTrips() {
        let fragment = makeFragment(mode: .fromPreviousNote)
        let doubleInverted = fragment.inverted().inverted()
        XCTAssertEqual(doubleInverted.absolutePitches(basePitch: 60), fragment.absolutePitches(basePitch: 60))
    }

    func testAccelerationScalesDurations() {
        let fragment = makeFragment(mode: .fromPreviousNote)
        let accelerated = fragment.accelerated(by: 2.0)
        XCTAssertEqual(accelerated.noteDurations, fragment.noteDurations.map { $0 / 2.0 })
        // Pitches are untouched by acceleration.
        XCTAssertEqual(accelerated.absolutePitches(basePitch: 60), fragment.absolutePitches(basePitch: 60))
    }

    func testNoteCount() {
        let fragment = makeFragment(mode: .fromPreviousNote)
        XCTAssertEqual(fragment.noteCount, 4)
    }
}
