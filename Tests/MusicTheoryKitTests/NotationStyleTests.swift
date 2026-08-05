import XCTest
@testable import MusicTheoryKit

final class NotationStyleTests: XCTestCase {
    private let style = AngloAmericanNotationStyle()

    func testCommonChordNamesMatchStandardLeadSheetSymbols() throws {
        let expectations: [(root: Int, templateID: String, expected: String)] = [
            (0, "Ma", "C"), (0, "mi", "Cm"), (0, "dim", "Cdim"), (0, "aug", "C+"),
            (0, "Ma7", "Cmaj7"), (0, "mi7", "Cm7"), (0, "mi7b5", "Cm7b5"), (0, "7", "C7"),
            (0, "miMa7", "CmMaj7"), (0, "dim7", "Cdim7"), (0, "5", "C5"),
        ]
        for expectation in expectations {
            let template = try XCTUnwrap(ChordVocabulary.byID(expectation.templateID))
            let chord = Chord(root: PitchClass(expectation.root), template: template)
            XCTAssertEqual(style.displayName(for: chord), expectation.expected)
        }
    }

    func testUnknownQualityFallsBackToTheRawTemplateIDRatherThanAnEmptyString() {
        let unknown = ChordTemplate(id: "someFutureQuality", intervalsFromRoot: [0, 4, 7])
        let chord = Chord(root: PitchClass(2), template: unknown)
        XCTAssertEqual(style.displayName(for: chord), "DsomeFutureQuality")
    }

    func testRegistryFallsBackToAngloAmericanForAnUnknownID() {
        let resolved = NotationStyleRegistry.byID("not-a-real-style")
        XCTAssertEqual(resolved.id, "angloAmerican")
    }
}
