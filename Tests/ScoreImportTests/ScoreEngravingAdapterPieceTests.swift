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
        XCTAssertEqual(notated.parts[0].clef, .treble)
    }

    func testBassRegisterTrackGetsBassClef() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    tracks: [
                        Track(name: "Bass", instrument: "", melodyEvents: [
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 2, pitch: 40, velocity: 100),
                            MelodyEvent(measure: 1, beat: 3, durationBeats: 2, pitch: 43, velocity: 100),
                        ]),
                    ]
                ),
            ]
        )

        XCTAssertEqual(ScoreEngravingAdapter.build(from: piece).parts[0].clef, .bass)
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

    // MARK: - Role-coloring analysis

    func testChordRootToneAndOutOfContextNotesGetDistinctColors() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma"))],
                    tracks: [
                        Track(name: "Melody", instrument: "", melodyEvents: [
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60, velocity: 100), // C: chord root
                            MelodyEvent(measure: 1, beat: 2, durationBeats: 1, pitch: 64, velocity: 100), // E: chord tone
                            MelodyEvent(measure: 1, beat: 3, durationBeats: 1, pitch: 61, velocity: 100), // C#: outside both the C-major chord and the C-ionian mode
                        ]),
                    ]
                ),
            ]
        )

        let notes = ScoreEngravingAdapter.build(from: piece).parts[0].measures[0].notes.filter { !$0.isRest }
        XCTAssertEqual(notes.map(\.colors), [["#f16d9a"], ["#fee67c"], [nil]])
    }

    func testChordStackNotesEachGetTheirOwnColor() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma"))],
                    tracks: [
                        Track(name: "Chord", instrument: "", melodyEvents: [
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 60, velocity: 100), // root
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 64, velocity: 100), // tone
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 61, velocity: 100), // outside both
                        ]),
                    ]
                ),
            ]
        )

        let notes = ScoreEngravingAdapter.build(from: piece).parts[0].measures[0].notes.filter { !$0.isRest }
        XCTAssertEqual(notes.count, 1, "three simultaneous same-duration notes group into one chord stack")
        XCTAssertEqual(notes[0].pitches, [60, 64, 61])
        XCTAssertEqual(notes[0].colors, ["#f16d9a", "#fee67c", nil], "each stacked pitch is colored by its own role, not the stack as a whole")
    }

    func testModeToneWithoutAChordStillGetsColored() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    // No chordProgression at all — only the section's mode should drive coloring.
                    tracks: [
                        Track(name: "Melody", instrument: "", melodyEvents: [
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60, velocity: 100), // C: mode root
                            MelodyEvent(measure: 1, beat: 2, durationBeats: 1, pitch: 62, velocity: 100), // D: mode tone
                            MelodyEvent(measure: 1, beat: 3, durationBeats: 1, pitch: 61, velocity: 100), // C#: outside the mode
                        ]),
                    ]
                ),
            ]
        )

        let notes = ScoreEngravingAdapter.build(from: piece).parts[0].measures[0].notes.filter { !$0.isRest }
        XCTAssertEqual(notes.map(\.colors), [["#ffbc59"], ["#59d3e3"], [nil]])
    }
}
