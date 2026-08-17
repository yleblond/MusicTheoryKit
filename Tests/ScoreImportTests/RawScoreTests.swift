import XCTest
@testable import ScoreImport

final class RawScoreTests: XCTestCase {
    func testEncodeDecodeRoundTrip() throws {
        let score = RawScore(
            sourceFormat: .midi,
            title: "Test Piece",
            composer: "Anon",
            divisionsPerQuarterNote: 480,
            tempoMap: [RawTempoEvent(tick: 0, microsecondsPerQuarter: 500_000)],
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            keySignatureMap: [RawKeySignatureEvent(tick: 0, fifths: 0, isMinor: false)],
            parts: [
                RawPart(
                    id: "0",
                    name: "Piano",
                    instrumentHint: "Acoustic Grand Piano",
                    notes: [
                        RawNote(startTick: 0, durationTicks: 480, pitch: 60, velocity: 100),
                        RawNote(
                            startTick: 480, durationTicks: 480, pitch: 64,
                            spelling: RawSpelling(step: "E", alter: 0, octave: 4)
                        ),
                        RawNote(startTick: 960, durationTicks: 480, pitch: 0, isRest: true),
                    ]
                ),
            ],
            explicitChords: [RawChordSymbol(tick: 0, rootStep: "C", rootAlter: 0, kind: "major")]
        )

        let data = try JSONEncoder().encode(score)
        let decoded = try JSONDecoder().decode(RawScore.self, from: data)

        XCTAssertEqual(decoded, score)
        XCTAssertEqual(decoded.parts.first?.notes.count, 3)
        XCTAssertEqual(decoded.tempoMap.first?.beatsPerMinute, 120)
    }

    func testMinimalInitDefaults() {
        let score = RawScore(sourceFormat: .musicXML, divisionsPerQuarterNote: 960)
        XCTAssertTrue(score.parts.isEmpty)
        XCTAssertTrue(score.explicitChords.isEmpty)
        XCTAssertNil(score.title)
    }
}
