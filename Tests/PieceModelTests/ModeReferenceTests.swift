import XCTest
@testable import PieceModel
@testable import MusicTheoryKit

final class ModeReferenceTests: XCTestCase {

    func testResolveValidScaleIDMatchesDirectConstruction() {
        let reference = ModeReference(tonic: 2, scaleID: "dorian")
        let resolved = reference.resolve()
        let expected = Mode(tonic: PitchClass(2), scale: ScaleLibrary.byID("dorian")!)
        XCTAssertEqual(resolved, expected)
    }

    func testResolveUnknownScaleIDReturnsNil() {
        let reference = ModeReference(tonic: 0, scaleID: "not-a-real-scale")
        XCTAssertNil(reference.resolve())
    }

    func testChordReferenceResolveValidTemplateID() {
        let reference = ChordReference(root: 0, chordTemplateID: "Ma7")
        let resolved = reference.resolve()
        let expected = Chord(root: PitchClass(0), template: ChordVocabulary.byID("Ma7")!)
        XCTAssertEqual(resolved, expected)
        XCTAssertEqual(resolved?.pitchClasses, [0, 4, 7, 11].map(PitchClass.init))
    }

    func testChordReferenceResolveUnknownTemplateIDReturnsNil() {
        let reference = ChordReference(root: 0, chordTemplateID: "not-a-real-chord")
        XCTAssertNil(reference.resolve())
    }

    func testModeTransitionStoresItsFields() {
        let toMode = ModeReference(tonic: 7, scaleID: "dorian")
        let pivot = ChordReference(root: 7, chordTemplateID: "mi7")
        let transition = ModeTransition(toMode: toMode, pivotChords: [pivot], atMeasure: 9)
        XCTAssertEqual(transition.toMode, toMode)
        XCTAssertEqual(transition.pivotChords, [pivot])
        XCTAssertEqual(transition.atMeasure, 9)
    }
}
