import XCTest
@testable import ScoreImport

final class BeatQuantizerTests: XCTestCase {
    private let ticksPerQuarter = 480
    private var ticksPerBeatUnit: Int { ticksPerQuarter } // 4/4, beatUnit 4
    private var measureLengthTicks: Int { ticksPerBeatUnit * 4 }

    func testMeasureBeatAtExactBoundaries() {
        XCTAssertEqual(BeatQuantizer.measureBeat(forTick: 0, measureLengthTicks: measureLengthTicks, ticksPerBeatUnit: ticksPerBeatUnit).measure, 1)
        XCTAssertEqual(BeatQuantizer.measureBeat(forTick: 0, measureLengthTicks: measureLengthTicks, ticksPerBeatUnit: ticksPerBeatUnit).beat, 1)

        let (measure, beat) = BeatQuantizer.measureBeat(forTick: measureLengthTicks, measureLengthTicks: measureLengthTicks, ticksPerBeatUnit: ticksPerBeatUnit)
        XCTAssertEqual(measure, 2)
        XCTAssertEqual(beat, 1)
    }

    func testMeasureBeatMidMeasure() {
        // beat 3 of measure 1 = 2 full beats in => tick 960
        let (measure, beat) = BeatQuantizer.measureBeat(forTick: 960, measureLengthTicks: measureLengthTicks, ticksPerBeatUnit: ticksPerBeatUnit)
        XCTAssertEqual(measure, 1)
        XCTAssertEqual(beat, 3)
    }

    func testSnappedRoundsToNearestGridPoint() {
        // sixteenth-note grid at 480 ticks/quarter -> grid step = 120 ticks
        XCTAssertEqual(BeatQuantizer.snapped(tick: 119, ticksPerQuarter: 480, subdivisionsPerBeat: 4), 120)
        XCTAssertEqual(BeatQuantizer.snapped(tick: 121, ticksPerQuarter: 480, subdivisionsPerBeat: 4), 120)
        XCTAssertEqual(BeatQuantizer.snapped(tick: 180, ticksPerQuarter: 480, subdivisionsPerBeat: 4), 240)
    }

    func testMelodyEventsDropsRestsAndFloorsMinimumDuration() {
        let notes = [
            RawNote(startTick: 0, durationTicks: 480, pitch: 60, velocity: 90),
            RawNote(startTick: 480, durationTicks: 0, pitch: 0, isRest: true), // dropped
            RawNote(startTick: 960, durationTicks: 10, pitch: 64, velocity: 80), // near-zero duration after snapping
        ]

        let events = BeatQuantizer.melodyEvents(
            from: notes, ticksPerQuarter: ticksPerQuarter, measureLengthTicks: measureLengthTicks,
            ticksPerBeatUnit: ticksPerBeatUnit, subdivisionsPerBeat: 4
        )

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].pitch, 60)
        XCTAssertEqual(events[0].measure, 1)
        XCTAssertEqual(events[0].beat, 1)
        XCTAssertEqual(events[0].durationBeats, 1.0, accuracy: 0.001)
        XCTAssertGreaterThan(events[1].durationBeats, 0) // never collapses to zero
        XCTAssertEqual(events[1].velocity, 80)
    }
}
