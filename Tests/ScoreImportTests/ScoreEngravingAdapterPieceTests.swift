import XCTest
import MusicTheoryKit
import PieceModel
@testable import ScoreImport

final class ScoreEngravingAdapterPieceTests: XCTestCase {
    func testRendersASingleSectionPieceWithOneTrack() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    tracks: [
                        Track(name: "Melody", instrument: "", melodyEvents: [
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60, velocity: 100),
                            MelodyEvent(measure: 1, beat: 2, durationBeats: 1, pitch: 62, velocity: 100),
                        ]),
                    ]
                ),
            ]
        )

        let notated = ScoreEngravingAdapter.build(from: piece)

        XCTAssertEqual(notated.parts.count, 1)
        XCTAssertEqual(notated.parts[0].name, "Melody")
        XCTAssertEqual(notated.parts[0].measures.count, 1)
        let notes = notated.parts[0].measures[0].notes.filter { !$0.isRest }
        XCTAssertEqual(notes.map(\.pitches), [[60], [62]])
    }

    func testMultipleSectionsConcatenateInOrder() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    tracks: [Track(name: "Melody", instrument: "", melodyEvents: [
                        MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 60, velocity: 100),
                    ])]
                ),
                Section(
                    name: "B", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    tracks: [Track(name: "Melody", instrument: "", melodyEvents: [
                        MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 67, velocity: 100),
                    ])]
                ),
            ]
        )

        let notated = ScoreEngravingAdapter.build(from: piece)

        XCTAssertEqual(notated.parts.count, 1)
        XCTAssertEqual(notated.parts[0].measures.count, 2)
        XCTAssertEqual(notated.parts[0].measures[0].notes.first { !$0.isRest }?.pitches, [60])
        XCTAssertEqual(notated.parts[0].measures[1].notes.first { !$0.isRest }?.pitches, [67])
    }

    func testTrackMissingFromASectionBecomesSilenceNotAMisalignment() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    tracks: [
                        Track(name: "Melody", instrument: "", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 60, velocity: 100)]),
                        Track(name: "Bass", instrument: "", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 36, velocity: 100)]),
                    ]
                ),
                Section(
                    name: "B", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    tracks: [Track(name: "Melody", instrument: "", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 67, velocity: 100)])]
                    // "Bass" absent here on purpose.
                ),
            ]
        )

        let notated = ScoreEngravingAdapter.build(from: piece)
        let bass = notated.parts.first { $0.name == "Bass" }
        XCTAssertEqual(bass?.measures.count, 2) // still gets a 2nd, silent measure, not truncated
        XCTAssertTrue(bass?.measures[1].notes.allSatisfy(\.isRest) ?? false)

        let melody = notated.parts.first { $0.name == "Melody" }
        // Melody's 2nd-section note must still land in ITS 2nd measure, not shifted by Bass's absence.
        XCTAssertEqual(melody?.measures[1].notes.first { !$0.isRest }?.pitches, [67])
    }

    func testEmptyPieceProducesNoParts() {
        let piece = Piece(title: "Empty", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"))
        XCTAssertTrue(ScoreEngravingAdapter.build(from: piece).parts.isEmpty)
    }
}
