import XCTest
@testable import LLMEngine
import MusicTheoryKit
import PieceModel

final class LLMPieceComposerTests: XCTestCase {

    // MARK: - parsePitchClass

    func testParsesNaturalNoteNames() {
        XCTAssertEqual(parsePitchClass("C"), 0)
        XCTAssertEqual(parsePitchClass("D"), 2)
        XCTAssertEqual(parsePitchClass("B"), 11)
    }

    func testParsesSharpsAndFlats() {
        XCTAssertEqual(parsePitchClass("C#"), 1)
        XCTAssertEqual(parsePitchClass("Db"), 1)
        XCTAssertEqual(parsePitchClass("Cb"), 11)
        XCTAssertEqual(parsePitchClass("B#"), 0)
    }

    func testParsesLowercaseLetterAndIgnoresWhitespace() {
        XCTAssertEqual(parsePitchClass(" f# "), 6)
    }

    func testRejectsGarbage() {
        XCTAssertNil(parsePitchClass("H"))
        XCTAssertNil(parsePitchClass(""))
        XCTAssertNil(parsePitchClass("C##"))
    }

    // MARK: - extractJSON

    func testExtractJSONPassesThroughPlainJSON() {
        XCTAssertEqual(LLMPieceComposer.extractJSON(from: "{\"a\":1}"), "{\"a\":1}")
    }

    func testExtractJSONStripsMarkdownFence() {
        let fenced = "```json\n{\"a\":1}\n```"
        XCTAssertEqual(LLMPieceComposer.extractJSON(from: fenced), "{\"a\":1}")
    }

    // MARK: - compose(from:) validation

    private func minimalValidDTOJSON(chords: String = "[{\"measure\":1,\"root\":\"D\",\"templateID\":\"mi7\"}]") -> String {
        """
        {
          "title": "Test",
          "tempoBPM": 100,
          "tonic": "C",
          "scaleID": "ionian",
          "sections": [
            { "name": "A", "lengthInMeasures": 1, "tonic": "C", "scaleID": "ionian", "chords": \(chords) }
          ]
        }
        """
    }

    func testValidResponseProducesAPiece() {
        let (piece, warnings) = LLMPieceComposer.parseAndValidate(responseText: minimalValidDTOJSON())
        XCTAssertEqual(piece?.title, "Test")
        XCTAssertEqual(piece?.key, ModeReference(tonic: 0, scaleID: "ionian"))
        XCTAssertEqual(piece?.sections.first?.chordProgression.first?.chord, ChordReference(root: 2, chordTemplateID: "mi7"))
        XCTAssertTrue(warnings.isEmpty)
    }

    func testFencedValidResponseAlsoParses() {
        let fenced = "```json\n\(minimalValidDTOJSON())\n```"
        let (piece, _) = LLMPieceComposer.parseAndValidate(responseText: fenced)
        XCTAssertNotNil(piece)
    }

    func testInvalidTopLevelKeyRejectsEverything() {
        let json = """
        { "title": "T", "tempoBPM": 100, "tonic": "Z", "scaleID": "not-real", "sections": [] }
        """
        let (piece, warnings) = LLMPieceComposer.parseAndValidate(responseText: json)
        XCTAssertNil(piece)
        XCTAssertFalse(warnings.isEmpty)
    }

    func testInvalidChordIsDroppedButValidOnesSurvive() {
        let json = minimalValidDTOJSON(chords: """
        [{"measure":1,"root":"D","templateID":"mi7"},{"measure":2,"root":"Q","templateID":"nope"}]
        """)
        let (piece, warnings) = LLMPieceComposer.parseAndValidate(responseText: json)
        XCTAssertEqual(piece?.sections.first?.chordProgression.count, 1)
        XCTAssertTrue(warnings.contains { $0.contains("dropped chord") })
    }

    func testSectionWithNoValidChordsIsDropped() {
        let json = minimalValidDTOJSON(chords: "[{\"measure\":1,\"root\":\"Z\",\"templateID\":\"nope\"}]")
        let (piece, warnings) = LLMPieceComposer.parseAndValidate(responseText: json)
        XCTAssertNil(piece)
        XCTAssertTrue(warnings.contains { $0.contains("no valid chords") })
    }

    func testMelodyNotesOutOfMIDIRangeAreDropped() {
        let json = """
        {
          "title": "Test", "tempoBPM": 100, "tonic": "C", "scaleID": "ionian",
          "sections": [
            { "name": "A", "lengthInMeasures": 1, "tonic": "C", "scaleID": "ionian",
              "chords": [{"measure":1,"root":"C","templateID":"Ma7"}],
              "melody": [{"measure":1,"beat":1,"durationBeats":1,"pitch":60},{"measure":1,"beat":2,"durationBeats":1,"pitch":200}]
            }
          ]
        }
        """
        let (piece, warnings) = LLMPieceComposer.parseAndValidate(responseText: json)
        XCTAssertEqual(piece?.sections.first?.tracks.first?.melodyEvents.count, 1)
        XCTAssertTrue(warnings.contains { $0.contains("out-of-range") })
    }

    func testTempoIsClampedToAReasonableRange() {
        let json = """
        { "title": "T", "tempoBPM": 999, "tonic": "C", "scaleID": "ionian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "C", "scaleID": "ionian",
            "chords": [{"measure":1,"root":"C","templateID":"Ma7"}] } ] }
        """
        let (piece, _) = LLMPieceComposer.parseAndValidate(responseText: json)
        XCTAssertEqual(piece?.tempoBPM, 240)
    }

    func testUnparsableJSONReturnsNilWithAWarning() {
        let (piece, warnings) = LLMPieceComposer.parseAndValidate(responseText: "not json at all")
        XCTAssertNil(piece)
        XCTAssertFalse(warnings.isEmpty)
    }

    // MARK: - buildPrompt

    func testBuildPromptEmbedsSourceTextAndVocabulary() {
        let prompt = LLMPieceComposer.buildPrompt(sourceText: "Roses are red")
        XCTAssertTrue(prompt.contains("Roses are red"))
        XCTAssertTrue(prompt.contains("ionian"))
        XCTAssertTrue(prompt.contains("Ma7"))
    }
}
