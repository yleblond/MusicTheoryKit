import XCTest
@testable import ScoreImport

final class ScoreEngravingAdapterTests: XCTestCase {
    private let ticksPerQuarter = 480

    func testSingleQuarterNoteInOneMeasure() {
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [RawPart(id: "0", notes: [RawNote(startTick: 0, durationTicks: 480, pitch: 60)])]
        )

        let notated = ScoreEngravingAdapter.build(from: score)

        XCTAssertEqual(notated.parts.count, 1)
        let measures = notated.parts[0].measures
        XCTAssertEqual(measures.count, 1)
        XCTAssertEqual(measures[0].beatsPerMeasure, 4)
        // A single quarter note followed by rests filling the remaining 3 beats.
        XCTAssertEqual(measures[0].notes.first?.duration, "q")
        XCTAssertEqual(measures[0].notes.first?.keys, ["c/4"])
        XCTAssertFalse(measures[0].notes.first?.isRest ?? true)
        XCTAssertTrue(measures[0].notes.dropFirst().allSatisfy(\.isRest))
    }

    func testGapBecomesRests() {
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [RawPart(id: "0", notes: [
                RawNote(startTick: 0, durationTicks: 480, pitch: 60),
                // gap of one beat (960...1440), then a note at beat 3
                RawNote(startTick: 1440, durationTicks: 480, pitch: 62),
            ])]
        )

        let notated = ScoreEngravingAdapter.build(from: score)
        let notes = notated.parts[0].measures[0].notes
        XCTAssertEqual(notes.map(\.isRest), [false, true, false])
    }

    func testSimultaneousNotesGroupIntoChord() {
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [RawPart(id: "0", notes: [
                RawNote(startTick: 0, durationTicks: 480, pitch: 60),
                RawNote(startTick: 0, durationTicks: 480, pitch: 64),
                RawNote(startTick: 0, durationTicks: 480, pitch: 67),
            ])]
        )

        let notated = ScoreEngravingAdapter.build(from: score)
        let firstNote = notated.parts[0].measures[0].notes[0]
        XCTAssertEqual(firstNote.pitches.sorted(), [60, 64, 67])
        XCTAssertEqual(firstNote.keys.count, 3)
    }

    func testNoteClippedAtMeasureBoundaryNotTied() {
        // A whole-note-length note starting one beat before the end of a 4/4 measure would
        // naturally spill into the next measure; v1 clips it instead of tying across the bar.
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [RawPart(id: "0", notes: [
                RawNote(startTick: 1440, durationTicks: 1920, pitch: 60), // starts at beat 4, would run 4 beats long
            ])]
        )

        let notated = ScoreEngravingAdapter.build(from: score)
        let measures = notated.parts[0].measures
        XCTAssertEqual(measures.count, 1) // clipped, no second measure spawned for the overflow
        let note = measures[0].notes.last { !$0.isRest }
        XCTAssertEqual(note?.duration, "q") // clipped down to the 1 remaining beat
    }

    func testExplicitSpellingIsPreservedVerbatim() {
        let score = RawScore(
            sourceFormat: .musicXML,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [RawPart(id: "0", notes: [
                RawNote(
                    startTick: 0, durationTicks: 480, pitch: 64,
                    spelling: RawSpelling(step: "F", alter: -1, octave: 4) // Fb, not E
                ),
            ])]
        )

        let notated = ScoreEngravingAdapter.build(from: score)
        XCTAssertEqual(notated.parts[0].measures[0].notes.first?.keys, ["fb/4"])
    }

    func testMissingSpellingFallsBackToCanonicalSpelling() {
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [RawPart(id: "0", notes: [RawNote(startTick: 0, durationTicks: 480, pitch: 61)])] // C#4/Db4
        )

        let notated = ScoreEngravingAdapter.build(from: score)
        // DiatonicSpelling's canonical table picks Db over C# — see DiatonicSpelling.swift.
        XCTAssertEqual(notated.parts[0].measures[0].notes.first?.keys, ["db/4"])
    }

    func testMultipleMeasuresFromTimeSignatureChange() {
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [
                RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4),
                RawTimeSignatureEvent(tick: 1920, beatsPerMeasure: 3, beatUnit: 4), // after 1 measure of 4/4
            ],
            parts: [RawPart(id: "0", notes: [
                RawNote(startTick: 0, durationTicks: 480, pitch: 60),
                RawNote(startTick: 1920, durationTicks: 480, pitch: 62), // first note of the 3/4 measure
            ])]
        )

        let notated = ScoreEngravingAdapter.build(from: score)
        let measures = notated.parts[0].measures
        XCTAssertEqual(measures.count, 2)
        XCTAssertEqual(measures[0].beatsPerMeasure, 4)
        XCTAssertEqual(measures[1].beatsPerMeasure, 3)
    }

    func testEmptyPartProducesNoMeasures() {
        let score = RawScore(sourceFormat: .midi, divisionsPerQuarterNote: ticksPerQuarter, parts: [RawPart(id: "0", notes: [])])
        let notated = ScoreEngravingAdapter.build(from: score)
        XCTAssertTrue(notated.parts[0].measures.isEmpty)
    }
}
