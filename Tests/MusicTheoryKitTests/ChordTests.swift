import XCTest
@testable import MusicTheoryKit

final class ChordTests: XCTestCase {

    func testVocabularySize() {
        // 13 original + 10 added for the Chord Library (5, sus2, sus4, 6, mi6, add9, miAdd9, 9,
        // Ma9, mi9) — see ChordVocabulary.seed's own doc comment.
        XCTAssertEqual(ChordVocabulary.seed.count, 23)
    }

    func testCMajorTriad() throws {
        let template = try XCTUnwrap(ChordVocabulary.byID("Ma"))
        let chord = Chord(root: PitchClass(0), template: template)
        XCTAssertEqual(chord.pitchClassSet, Set([0, 4, 7].map(PitchClass.init)))
        XCTAssertEqual(chord.displayName, "CMa")
    }

    func testAMinorTriad() throws {
        let template = try XCTUnwrap(ChordVocabulary.byID("mi"))
        let chord = Chord(root: PitchClass(9), template: template)
        XCTAssertEqual(chord.pitchClassSet, Set([9, 0, 4].map(PitchClass.init)))
    }

    func testScaleChordSymbolsResolve() {
        let unresolvable: Set<String> = ["7alt", "6#5"]
        for scale in ScaleLibrary.all {
            for symbol in scale.chordSymbols where !unresolvable.contains(symbol) {
                XCTAssertNotNil(ChordVocabulary.byID(symbol), "\(symbol) (from \(scale.id)) has no ChordTemplate")
            }
        }
    }

    func testCMaj7() throws {
        let template = try XCTUnwrap(ChordVocabulary.byID("Ma7"))
        let chord = Chord(root: PitchClass(0), template: template)
        XCTAssertEqual(chord.pitchClassSet, Set([0, 4, 7, 11].map(PitchClass.init)))
        XCTAssertEqual(chord.displayName, "CMa7")
    }

    func testDMin7() throws {
        let template = try XCTUnwrap(ChordVocabulary.byID("mi7"))
        let chord = Chord(root: PitchClass(2), template: template)
        XCTAssertEqual(chord.pitchClassSet, Set([2, 5, 9, 0].map(PitchClass.init)))
    }
}
