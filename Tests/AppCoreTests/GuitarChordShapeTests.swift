import XCTest
import MusicTheoryKit
@testable import AppCore

// Every covered shape's ACTUAL sounded pitch classes are recomputed here and compared
// against ChordVocabulary's own intervalsFromRoot — see the mirrored SanityChecks section's
// own header comment for why this matters (catches a future transcription slip in
// GuitarChordShapes.swift, independent of the hand-verification that produced that table).
final class GuitarChordShapeTests: XCTestCase {
    /// Open strings' pitch classes, string 6 (low E) ... string 1 (high e).
    private let openStringPitchClasses = [4, 9, 2, 7, 11, 4]

    private func soundedRelativePitchClasses(_ diagram: GuitarChordShape.Diagram, root: Int) -> Set<Int> {
        var result: Set<Int> = []
        for (index, position) in diagram.positions.enumerated() {
            guard let relativeFret = position.relativeFret else { continue }
            let fret = diagram.barreFret + relativeFret
            let sounded = (openStringPitchClasses[index] + fret) % 12
            result.insert(((sounded - root) % 12 + 12) % 12)
        }
        return result
    }

    func testShapesSoundTheRightIntervalsForEveryCoveredQuality() throws {
        let coveredTemplateIDs = ["Ma", "mi", "7", "Ma7", "mi7", "mi7b5", "dim7", "aug", "dim", "miMa7", "7#5", "7b5"]
        for templateID in coveredTemplateIDs {
            let template = try XCTUnwrap(ChordVocabulary.byID(templateID), "no such ChordTemplate: \(templateID)")
            let expected = Set(template.intervalsFromRoot.map { (($0 % 12) + 12) % 12 })
            for root in [0, 5, 7, 11] {
                let diagram = try XCTUnwrap(
                    GuitarChordShape.diagram(forRoot: root, chordTemplateID: templateID),
                    "\(templateID) at root \(root) unexpectedly returned nil"
                )
                XCTAssertEqual(soundedRelativePitchClasses(diagram, root: root), expected, "\(templateID) at root \(root)")
            }
        }
        // Well-known reference positions: F major barre chord at fret 1, G major at fret 3.
        XCTAssertEqual(GuitarChordShape.diagram(forRoot: 5, chordTemplateID: "Ma")?.barreFret, 1)
        XCTAssertEqual(GuitarChordShape.diagram(forRoot: 7, chordTemplateID: "Ma")?.barreFret, 3)
    }

    func testReturnsNilForAnUncoveredQuality() {
        XCTAssertNil(GuitarChordShape.diagram(forRoot: 0, chordTemplateID: "Ma7#5"))
        XCTAssertNil(GuitarChordShape.diagram(forRoot: 0, chordTemplateID: "not-a-real-template"))
    }
}
