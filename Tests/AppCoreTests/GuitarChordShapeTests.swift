import XCTest
import MusicTheoryKit
@testable import AppCore

// Every covered shape's ACTUAL sounded pitch classes are recomputed here and compared
// against ChordVocabulary's own intervalsFromRoot — see the mirrored SanityChecks section's
// own header comment for why this matters (catches a future transcription slip in
// GuitarChordShapes.swift, independent of the hand-verification that produced that table).
final class GuitarChordShapeTests: XCTestCase {
    /// Goes through `Diagram.soundedPitchClass(atStringIndex:)` itself rather than
    /// re-deriving the fret math independently — this is deliberately the same production
    /// code `GuitarChordDiagramView` uses to color each string by note identity, so every test
    /// below that calls this also exercises that method.
    private func soundedRelativePitchClasses(_ diagram: GuitarChordShape.Diagram, root: Int) -> Set<Int> {
        var result: Set<Int> = []
        for index in diagram.positions.indices {
            guard let sounded = diagram.soundedPitchClass(atStringIndex: index) else { continue }
            result.insert(((sounded.value - root) % 12 + 12) % 12)
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

    /// Every "Ma"/"mi" 1st/2nd-inversion shape, every root — same sounded-pitch-class
    /// cross-check as `testShapesSoundTheRightIntervalsForEveryCoveredQuality`, but for the
    /// D-G-B compact triad shapes (`GuitarChordShapes.triadInversionShapesByTemplateID`)
    /// instead of the 6-string barre table.
    func testInversionShapesSoundTheRightIntervalsForCoveredTriads() throws {
        for templateID in ["Ma", "mi"] {
            let template = try XCTUnwrap(ChordVocabulary.byID(templateID))
            let expected = Set(template.intervalsFromRoot.map { (($0 % 12) + 12) % 12 })
            for root in 0..<12 {
                for inversion in [1, 2] {
                    let diagram = try XCTUnwrap(
                        GuitarChordShape.diagram(forRoot: root, chordTemplateID: templateID, inversion: inversion),
                        "\(templateID) inversion \(inversion) at root \(root) unexpectedly returned nil"
                    )
                    XCTAssertFalse(diagram.isBasePositionFallback, "\(templateID) inversion \(inversion) at root \(root) should be a genuine shape")
                    XCTAssertEqual(
                        soundedRelativePitchClasses(diagram, root: root), expected,
                        "\(templateID) inversion \(inversion) at root \(root)"
                    )
                }
            }
        }
    }

    func testUncoveredInversionFallsBackToRootPositionWithFlagSet() throws {
        let fallback = try XCTUnwrap(GuitarChordShape.diagram(forRoot: 0, chordTemplateID: "Ma7", inversion: 1))
        XCTAssertTrue(fallback.isBasePositionFallback)
        let rootPosition = try XCTUnwrap(GuitarChordShape.diagram(forRoot: 0, chordTemplateID: "Ma7"))
        XCTAssertEqual(fallback.positions, rootPosition.positions)
        XCTAssertEqual(fallback.barreFret, rootPosition.barreFret)
    }

    func testInversionZeroMatchesRootPositionDiagram() throws {
        let withInversionParam = try XCTUnwrap(GuitarChordShape.diagram(forRoot: 3, chordTemplateID: "mi7", inversion: 0))
        let rootPositionOnly = try XCTUnwrap(GuitarChordShape.diagram(forRoot: 3, chordTemplateID: "mi7"))
        XCTAssertEqual(withInversionParam, rootPositionOnly)
    }

    /// The E-shape "Ma" barre table's own doc comment claims the root always falls on string 6
    /// (index 0) — true, but NOT the only string that sounds it: E major (open, root = E = pitch
    /// class 4) also doubles the root on the D string (index 2, fret 2) and the high e string
    /// (index 5, open), per real open-E-chord fingering.
    func testSoundedPitchClassRootStringForOpenPositionMajor() throws {
        let diagram = try XCTUnwrap(GuitarChordShape.diagram(forRoot: 4, chordTemplateID: "Ma"))
        let root = PitchClass(4)
        let rootStringIndices = diagram.positions.indices.filter { diagram.soundedPitchClass(atStringIndex: $0) == root }
        XCTAssertEqual(Set(rootStringIndices), Set([0, 2, 5]))
    }

    /// A D-G-B triad inversion shape never voices strings 6/5/1 (indices 0, 1, 5 — always
    /// muted, see `triadInversionShapesByTemplateID`'s own doc comment) — the root can land on
    /// whichever of the 3 active strings the inversion puts it on, unlike the 6-string barre
    /// shapes where it's always string 6. For C major (root = pitch class 0), 1st inversion
    /// (`barreFretOffset: 0`, `dGBRelativeFrets: (d: 2, g: 0, b: 1)`) puts the root on the B
    /// string: D string sounds fret 2 (pitch class 4, the 3rd), G string sounds fret 0 (pitch
    /// class 7, the 5th), B string sounds fret 1 (pitch class 0, the root) — independently
    /// cross-checked against `ChordVocabulary`'s own intervals by
    /// `testInversionShapesSoundTheRightIntervalsForCoveredTriads` above; this test only pins
    /// down WHICH string carries which tone.
    func testSoundedPitchClassRootStringForTriadInversion() throws {
        let diagram = try XCTUnwrap(GuitarChordShape.diagram(forRoot: 0, chordTemplateID: "Ma", inversion: 1))
        for index in [0, 1, 5] {
            XCTAssertNil(diagram.soundedPitchClass(atStringIndex: index), "string index \(index) should be muted")
        }
        XCTAssertEqual(diagram.soundedPitchClass(atStringIndex: 2), PitchClass(4)) // D string -> major 3rd (E)
        XCTAssertEqual(diagram.soundedPitchClass(atStringIndex: 3), PitchClass(7)) // G string -> perfect 5th (G)
        XCTAssertEqual(diagram.soundedPitchClass(atStringIndex: 4), PitchClass(0)) // B string -> root (C)
    }

    func testSoundedPitchClassIsNilForAMutedString() throws {
        let diagram = try XCTUnwrap(GuitarChordShape.diagram(forRoot: 0, chordTemplateID: "dim")) // 2 muted strings
        XCTAssertNil(diagram.soundedPitchClass(atStringIndex: 4))
        XCTAssertNil(diagram.soundedPitchClass(atStringIndex: 5))
    }
}
