import XCTest
@testable import PieceModel
import SoundFontModel

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

    /// `Track.instrumentPreset`/`Section.chordInstrumentPreset` were added after pieces were
    /// already being saved on real installs — a piece file saved before multi-preset `.sf2`
    /// support (no `instrumentPreset`/`chordInstrumentPreset` keys at all) must still decode,
    /// both defaulting to `nil` (that instrument just uses its file's own default preset,
    /// exactly as before).
    func testTrackAndSectionDecodePreExistingJSONWithNoPresetKeysAsNilPresets() throws {
        let json = """
        {
            "id": "s1", "name": "A", "lengthInMeasures": 4,
            "mode": {"tonic": 0, "scaleID": "dorian"},
            "chordProgression": [], "chordInstrument": "mcb.sf2",
            "tracks": [
                {"id": "t1", "name": "lead", "instrument": "piano.sf2", "melodyEvents": [], "fragmentPlacements": []}
            ]
        }
        """
        let section = try JSONDecoder().decode(Section.self, from: Data(json.utf8))

        XCTAssertEqual(section.chordInstrument, "mcb.sf2")
        XCTAssertNil(section.chordInstrumentPreset)
        XCTAssertEqual(section.tracks.first?.instrument, "piano.sf2")
        XCTAssertNil(section.tracks.first?.instrumentPreset)
    }

    func testTrackAndSectionRoundTripAPresetThroughJSON() throws {
        let preset = SoundFontPresetIdentity(program: 19, bank: 0)
        let section = Section(
            name: "A", lengthInMeasures: 4, mode: ModeReference(tonic: 0, scaleID: "dorian"),
            tracks: [Track(name: "lead", instrument: "piano.sf2", instrumentPreset: preset)],
            chordInstrument: "mcb.sf2", chordInstrumentPreset: preset
        )

        let data = try JSONEncoder().encode(section)
        let decoded = try JSONDecoder().decode(Section.self, from: data)

        XCTAssertEqual(decoded, section)
        XCTAssertEqual(decoded.chordInstrumentPreset, preset)
        XCTAssertEqual(decoded.tracks.first?.instrumentPreset, preset)
    }
}
