import XCTest
@testable import MusicTheoryKit

final class ChordTests: XCTestCase {

    func testVocabularySize() {
        XCTAssertEqual(ChordVocabulary.seed.count, 13)
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
