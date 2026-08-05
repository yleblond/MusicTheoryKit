import XCTest
import SwiftData
@testable import AppCore
@testable import PieceModel
@testable import MusicTheoryKit

/// Covers the Chord/Mode/Progression Library's own additions: JSON-editable chord/scale
/// vocabularies (mirroring `migrateChordProgressionTemplatesFromJSONIfNeeded`'s own tests),
/// `ChordProgressionResolver`'s rich diatonic resolution, and `ProgressionNameAliases`.
final class ChordScaleLibraryTests: XCTestCase {
    /// `ChordVocabulary.register(_:)`/`ScaleLibrary.register(_:)` mutate genuinely global,
    /// process-wide state (by design — see their own doc comments) — every test below that
    /// triggers a migration (directly or via `ImprovSession`) MUST reset both afterward, or it
    /// leaks into unrelated tests sharing the same process (confirmed the hard way: this used
    /// to silently break `ScaleLibraryTests.testFamilySizes`'s family-1 count).
    override func tearDown() {
        ChordVocabulary.resetForTesting()
        ScaleLibrary.resetForTesting()
        super.tearDown()
    }

    // MARK: - JSON migration

    func testMigrateChordTemplatesFromJSONInsertsAndRegistersNewQualities() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        let json = #"{"chords":[{"id":"testOnlyQuality","intervalsFromRoot":[0,1,2]}]}"#
        try json.write(to: tempFile, atomically: true, encoding: .utf8)

        let session = makeTestSession()
        session.migrateChordTemplatesFromJSONIfNeeded(fromJSONFile: tempFile.path)
        XCTAssertEqual(session.extraChordTemplates.map(\.id), ["testOnlyQuality"])
        XCTAssertEqual(ChordVocabulary.byID("testOnlyQuality")?.intervalsFromRoot, [0, 1, 2])

        // A second session sharing the same store loads what's there rather than re-seeding.
        let reloaded = makeTestSession()
        reloaded.migrateChordTemplatesFromJSONIfNeeded(fromJSONFile: tempFile.path)
        XCTAssertEqual(reloaded.extraChordTemplates.map(\.id), ["testOnlyQuality"])
    }

    func testMigrateChordTemplatesIsANoOpWithNoFileAndNoExistingRecords() {
        let session = makeTestSession()
        session.migrateChordTemplatesFromJSONIfNeeded(fromJSONFile: "/nonexistent/path/chords.json")
        XCTAssertTrue(session.extraChordTemplates.isEmpty)
        // The compiled-in seed is unaffected either way.
        XCTAssertNotNil(ChordVocabulary.byID("Ma"))
    }

    func testMigrateScaleDefinitionsFromJSONInsertsAndRegistersNewScales() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        let json = #"{"scales":[{"id":"testOnlyScale","familyID":1,"degree":1,"popularName":"Test","systematicName":"Test","chordSymbols":["Ma7"]}]}"#
        try json.write(to: tempFile, atomically: true, encoding: .utf8)

        let session = makeTestSession()
        session.migrateScaleDefinitionsFromJSONIfNeeded(fromJSONFile: tempFile.path)
        XCTAssertEqual(session.extraScaleDefinitions.map(\.id), ["testOnlyScale"])
        XCTAssertEqual(ScaleLibrary.byID("testOnlyScale")?.popularName, "Test")
    }

    // MARK: - ChordProgressionResolver

    func testResolveRichUsesTheModesActualDiatonicSeventhChords() {
        let mode = Mode(tonic: PitchClass(0), scale: ScaleLibrary.byID("ionian")!) // C major
        let template = ChordProgressionTemplate(name: "test", degrees: ["ii", "V", "I"])
        let references = ChordProgressionResolver.resolveRich(template, in: mode)
        // ii in C major is D dorian -> mi7; V is G mixolydian -> 7; I is C ionian -> Ma7.
        XCTAssertEqual(references.map(\.chordTemplateID), ["mi7", "7", "Ma7"])
        XCTAssertEqual(references.map(\.root), [2, 7, 0])
    }

    func testResolveRichFallsBackToLiteralQualityOutsideFamilyOne() {
        let mode = Mode(tonic: PitchClass(0), scale: ScaleLibrary.byID("whole_tone")!) // familyID 6
        let template = ChordProgressionTemplate(name: "test", degrees: ["I", "vi"])
        let references = ChordProgressionResolver.resolveRich(template, in: mode)
        XCTAssertEqual(references.map(\.chordTemplateID), ["Ma", "mi"])
    }

    func testDiatonicChordReferencesReturnsSevenChordsForFamilyOneAndEmptyOtherwise() {
        let major = Mode(tonic: PitchClass(0), scale: ScaleLibrary.byID("ionian")!)
        XCTAssertEqual(ChordProgressionResolver.diatonicChordReferences(in: major).count, 7)

        let wholeTone = Mode(tonic: PitchClass(0), scale: ScaleLibrary.byID("whole_tone")!)
        XCTAssertTrue(ChordProgressionResolver.diatonicChordReferences(in: wholeTone).isEmpty)
    }

    // MARK: - ProgressionNameAliases

    func testMatchingNamesFindsTheTemplateItselfAndItsAlternates() {
        let names = ProgressionNameAliases.matchingNames(for: ["I", "V", "vi", "IV"])
        XCTAssertTrue(names.contains("Pop (I-V-vi-IV)"))
        XCTAssertTrue(names.contains("Axis progression"))
    }

    func testRelativeMinorRewriteNormalizesToTheSameRootSequenceAsItsMajorCounterpart() {
        // "i-VI-III-VII" read starting on the relative minor's own tonic (e.g. Am-F-C-G)
        // should normalize to the same root sequence as its relative-major rewrite.
        let minorOffsets = ProgressionNameAliases.normalizedRootOffsets(["i", "VI", "III", "VII"])
        let majorOffsets = ProgressionNameAliases.normalizedRootOffsets(["vi", "IV", "I", "V"])
        XCTAssertEqual(minorOffsets, majorOffsets)
    }

    func testUnparsableTokenReturnsNoMatches() {
        XCTAssertEqual(ProgressionNameAliases.matchingNames(for: ["not-a-numeral"]), [])
    }
}
