import XCTest
@testable import PieceModel

final class PieceTests: XCTestCase {

    func testFragmentLookupByIDFindsMatch() {
        let fragment = MelodicFragment(id: "motif-1", name: "motif", referenceMode: .fromFirstNote, intervals: [4], noteDurations: [1, 1])
        let piece = Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "dorian"), fragments: [fragment])
        XCTAssertEqual(piece.fragment(id: "motif-1"), fragment)
    }

    func testFragmentLookupByIDReturnsNilWhenMissing() {
        let piece = Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "dorian"))
        XCTAssertNil(piece.fragment(id: "missing"))
    }

    func testPieceRoundTripsThroughJSON() throws {
        let fragment = MelodicFragment(id: "motif-1", name: "motif", referenceMode: .fromPreviousNote, intervals: [2, 2], noteDurations: [1, 1, 1])
        let section = Section(
            name: "A",
            lengthInMeasures: 4,
            mode: ModeReference(tonic: 0, scaleID: "dorian"),
            modeTransition: ModeTransition(
                toMode: ModeReference(tonic: 7, scaleID: "dorian"),
                pivotChords: [ChordReference(root: 7, chordTemplateID: "mi7")],
                atMeasure: 3
            ),
            chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma7"))],
            tracks: [
                Track(
                    name: "lead",
                    instrument: "piano",
                    melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60)],
                    fragmentPlacements: [FragmentPlacement(fragmentID: "motif-1", measure: 1, beat: 1, basePitch: 60)]
                )
            ]
        )
        let piece = Piece(
            title: "Round Trip",
            composer: "Test Suite",
            tempoBPM: 96,
            key: ModeReference(tonic: 0, scaleID: "dorian"),
            fragments: [fragment],
            sections: [section]
        )

        let data = try JSONEncoder().encode(piece)
        let decoded = try JSONDecoder().decode(Piece.self, from: data)

        XCTAssertEqual(decoded, piece)
    }
}
