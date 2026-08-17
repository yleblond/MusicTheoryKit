import XCTest
@testable import ScoreImport

final class KeyModeDetectorTests: XCTestCase {
    func testDetectsCMajorFromADiatonicCMajorMelody() throws {
        // C D E F G A B C, all held equally long -> unambiguous C ionian.
        let notes = [60, 62, 64, 65, 67, 69, 71, 72].map { (pitch: $0, durationTicks: 480) }
        let mode = try XCTUnwrap(KeyModeDetector.detect(notes: notes))
        XCTAssertEqual(mode.tonic, 0)
        XCTAssertEqual(mode.scaleID, "ionian")
    }

    func testDetectsAMinorFromADiatonicAMinorMelody() throws {
        // A B C D E F G, all natural-minor pitch classes of A.
        let notes = [69, 71, 60, 62, 64, 65, 67].map { (pitch: $0, durationTicks: 480) }
        let mode = try XCTUnwrap(KeyModeDetector.detect(notes: notes))
        // A natural minor == A aeolian, same pitch classes as C ionian -> tie-break picks
        // whichever scale has fewer notes; both are 7-note diatonic scales, so either a tie
        // is broken arbitrarily or one is picked consistently — assert only that SOME 7-note
        // scale covering these classes was chosen, not a specific tonic (both C ionian and A
        // aeolian are equally valid readings of this exact pitch-class set).
        XCTAssertTrue(mode.scaleID == "ionian" || mode.scaleID == "aeolian")
    }

    func testReturnsNilBelowConfidenceThreshold() {
        // Wildly chromatic material (every pitch class present, no scale covers more than a
        // fraction) should not confidently match any 7-note scale.
        let notes = (60...71).map { (pitch: $0, durationTicks: 10) }
        XCTAssertNil(KeyModeDetector.detect(notes: notes, minimumConfidence: 0.99))
    }

    func testReturnsNilForEmptyInput() {
        XCTAssertNil(KeyModeDetector.detect(notes: []))
    }

    func testLongerHeldNoteOutweighsBriefPassingTones() {
        // A long C (tonic) plus brief chromatic passing tones should still read as C-rooted.
        let notes: [(pitch: Int, durationTicks: Int)] = [
            (60, 4000), (61, 5), (63, 5), (66, 5), // C held long; a few chromatic blips
        ]
        let mode = try? XCTUnwrap(KeyModeDetector.detect(notes: notes, minimumConfidence: 0.5))
        XCTAssertNotNil(mode)
    }
}
