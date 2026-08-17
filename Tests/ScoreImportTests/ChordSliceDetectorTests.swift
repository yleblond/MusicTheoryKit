import XCTest
import MusicTheoryKit
@testable import ScoreImport

final class ChordSliceDetectorTests: XCTestCase {
    func testBestChordRecognizesCMajorTriad() throws {
        let best = try XCTUnwrap(ChordSliceDetector.bestChord(forPitchClasses: [PitchClass(0), PitchClass(4), PitchClass(7)]))
        XCTAssertEqual(best.root.value, 0)
        XCTAssertEqual(best.chordTemplateID, "Ma")
        XCTAssertEqual(best.confidence, 1.0, accuracy: 0.001)
    }

    func testBestChordReturnsNilForFewerThanTwoNotes() {
        XCTAssertNil(ChordSliceDetector.bestChord(forPitchClasses: [PitchClass(0)]))
        XCTAssertNil(ChordSliceDetector.bestChord(forPitchClasses: []))
    }

    func testDetectChordProgressionMergesAdjacentIdenticalSlices() {
        let ticksPerQuarter = 480
        let measureLength = ticksPerQuarter * 4
        // C major triad held across two full measures (one long chord, not two separate ones).
        let notes: [(startTick: Int, durationTicks: Int, pitch: Int)] = [
            (0, measureLength * 2, 60), (0, measureLength * 2, 64), (0, measureLength * 2, 67),
        ]

        let events = ChordSliceDetector.detectChordProgression(
            notes: notes, totalTicks: measureLength * 2, sliceTicks: measureLength,
            ticksPerBeatUnit: ticksPerQuarter, measureLengthTicks: measureLength
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].measure, 1)
        XCTAssertEqual(events[0].durationBeats, 8.0, accuracy: 0.001) // 2 measures of 4 beats
        XCTAssertEqual(events[0].chord.chordTemplateID, "Ma")
    }

    func testDetectChordProgressionSeparatesDifferentChords() {
        let ticksPerQuarter = 480
        let measureLength = ticksPerQuarter * 4
        let notes: [(startTick: Int, durationTicks: Int, pitch: Int)] = [
            (0, measureLength, 60), (0, measureLength, 64), (0, measureLength, 67), // C major, measure 1
            (measureLength, measureLength, 65), (measureLength, measureLength, 69), (measureLength, measureLength, 72), // F major, measure 2
        ]

        let events = ChordSliceDetector.detectChordProgression(
            notes: notes, totalTicks: measureLength * 2, sliceTicks: measureLength,
            ticksPerBeatUnit: ticksPerQuarter, measureLengthTicks: measureLength
        )

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].measure, 1)
        XCTAssertEqual(events[1].measure, 2)
    }

    func testChordVocabularyIDMapsKnownMusicXMLKinds() {
        XCTAssertEqual(ChordSliceDetector.chordVocabularyID(forExplicitKind: "major-seventh"), "Ma7")
        XCTAssertEqual(ChordSliceDetector.chordVocabularyID(forExplicitKind: "minor"), "mi")
        XCTAssertNil(ChordSliceDetector.chordVocabularyID(forExplicitKind: "something-unheard-of"))
    }
}
