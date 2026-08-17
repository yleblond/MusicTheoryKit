import XCTest
@testable import ScoreImport

final class RawScoreComposerTests: XCTestCase {
    private let ticksPerQuarter = 480

    func testEmptyScoreProducesNilPieceWithWarning() {
        let score = RawScore(sourceFormat: .midi, divisionsPerQuarterNote: ticksPerQuarter, parts: [RawPart(id: "0", notes: [])])
        let (piece, warnings) = RawScoreComposer.compose(from: score)
        XCTAssertNil(piece)
        XCTAssertFalse(warnings.isEmpty)
    }

    func testComposesADiatonicMelodyWithoutExplicitChordsIntoAPlayablePiece() throws {
        // One measure of a C major triad held together (so both key detection and chord
        // slicing have something unambiguous to latch onto), 4/4, 480 ticks/quarter.
        let measureLength = ticksPerQuarter * 4
        let score = RawScore(
            sourceFormat: .midi,
            title: "Test Song",
            divisionsPerQuarterNote: ticksPerQuarter,
            tempoMap: [RawTempoEvent(tick: 0, microsecondsPerQuarter: 500_000)], // 120 BPM
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [RawPart(id: "0", name: "Melody", notes: [
                RawNote(startTick: 0, durationTicks: measureLength, pitch: 60),
                RawNote(startTick: 0, durationTicks: measureLength, pitch: 64),
                RawNote(startTick: 0, durationTicks: measureLength, pitch: 67),
            ])]
        )

        let (pieceOpt, warnings) = RawScoreComposer.compose(from: score)
        let piece = try XCTUnwrap(pieceOpt)

        XCTAssertEqual(piece.title, "Test Song")
        XCTAssertEqual(piece.tempoBPM, 120, accuracy: 0.01)
        XCTAssertEqual(piece.timeSignature.beatsPerMeasure, 4)
        XCTAssertEqual(piece.sections.count, 1)
        XCTAssertEqual(piece.sections[0].tracks.count, 1)
        XCTAssertEqual(piece.sections[0].tracks[0].name, "Melody")
        XCTAssertEqual(piece.sections[0].tracks[0].melodyEvents.count, 3)
        XCTAssertFalse(piece.sections[0].chordProgression.isEmpty) // detected via ChordSliceDetector
        XCTAssertEqual(piece.sections[0].chordProgression.first?.chord.chordTemplateID, "Ma")
        XCTAssertTrue(warnings.isEmpty, "a clean, unambiguous fixture shouldn't produce warnings, got: \(warnings)")
    }

    func testExplicitChordsAreUsedDirectlyInsteadOfInferred() throws {
        let measureLength = ticksPerQuarter * 4
        let score = RawScore(
            sourceFormat: .musicXML,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [RawPart(id: "0", notes: [RawNote(startTick: 0, durationTicks: measureLength, pitch: 60)])],
            explicitChords: [RawChordSymbol(tick: 0, rootStep: "D", rootAlter: 0, kind: "minor-seventh")]
        )

        let (pieceOpt, _) = RawScoreComposer.compose(from: score)
        let piece = try XCTUnwrap(pieceOpt)

        XCTAssertEqual(piece.sections[0].chordProgression.count, 1)
        let chord = piece.sections[0].chordProgression[0]
        XCTAssertEqual(chord.chord.chordTemplateID, "mi7")
        XCTAssertEqual(chord.chord.root, 2) // D
    }

    func testMultipleTimeSignaturesProduceAWarningAndUseTheFirst() throws {
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [
                RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4),
                RawTimeSignatureEvent(tick: 1920, beatsPerMeasure: 3, beatUnit: 4),
            ],
            parts: [RawPart(id: "0", notes: [
                RawNote(startTick: 0, durationTicks: ticksPerQuarter, pitch: 60),
                RawNote(startTick: 1920, durationTicks: ticksPerQuarter, pitch: 62),
            ])]
        )

        let (pieceOpt, warnings) = RawScoreComposer.compose(from: score)
        let piece = try XCTUnwrap(pieceOpt)
        XCTAssertEqual(piece.timeSignature.beatsPerMeasure, 4)
        XCTAssertTrue(warnings.contains { $0.contains("time signature") })
    }

    func testEmptyTitleFallsBackToDefault() throws {
        let score = RawScore(
            sourceFormat: .midi, title: "", divisionsPerQuarterNote: ticksPerQuarter,
            parts: [RawPart(id: "0", notes: [RawNote(startTick: 0, durationTicks: ticksPerQuarter, pitch: 60)])]
        )
        let (pieceOpt, _) = RawScoreComposer.compose(from: score)
        XCTAssertEqual(pieceOpt?.title, "Imported piece")
    }
}
