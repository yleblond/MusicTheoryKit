import XCTest
@testable import PieceModel
@testable import MusicTheoryKit

final class RenderingTests: XCTestCase {

    private func makeSection(tracks: [Track] = []) -> Section {
        Section(
            name: "A",
            lengthInMeasures: 4,
            mode: ModeReference(tonic: 0, scaleID: "dorian"),
            tracks: tracks
        )
    }

    private func makePiece(fragments: [MelodicFragment] = [], sections: [Section] = []) -> Piece {
        Piece(
            title: "test piece",
            tempoBPM: 120,
            key: ModeReference(tonic: 0, scaleID: "dorian"),
            fragments: fragments,
            sections: sections
        )
    }

    func testAbsoluteBeatAtStartOfSectionIsZero() {
        let section = makeSection()
        XCTAssertEqual(section.absoluteBeat(measure: 1, beat: 1, beatsPerMeasure: 4), 0)
    }

    func testAbsoluteBeatAdvancesByFullMeasures() {
        let section = makeSection()
        XCTAssertEqual(section.absoluteBeat(measure: 3, beat: 1, beatsPerMeasure: 4), 8)
    }

    func testAbsoluteBeatWithinMeasureOffset() {
        let section = makeSection()
        XCTAssertEqual(section.absoluteBeat(measure: 2, beat: 2.5, beatsPerMeasure: 4), 5.5)
    }

    func testScheduledNotesFromMelodyEventsAreConvertedAndSorted() {
        let track = Track(
            name: "lead",
            instrument: "piano",
            melodyEvents: [
                MelodyEvent(measure: 2, beat: 1, durationBeats: 1, pitch: 67, velocity: 90),
                MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60, velocity: 100),
            ]
        )
        let section = makeSection(tracks: [track])
        let piece = makePiece(sections: [section])

        let notes = track.scheduledNotes(in: piece, section: section)

        XCTAssertEqual(notes.map(\.startBeat), [0, 4])
        XCTAssertEqual(notes.map(\.pitch), [60, 67])
        XCTAssertEqual(notes.map(\.velocity), [100, 90])
    }

    func testScheduledNotesFromFragmentPlacementResolvesTransformsAndAdvancesCursor() {
        let fragment = MelodicFragment(
            id: "motif-1",
            name: "motif",
            referenceMode: .fromPreviousNote,
            intervals: [2, 2],
            noteDurations: [1, 1, 1]
        )
        let placement = FragmentPlacement(
            fragmentID: "motif-1",
            measure: 1,
            beat: 1,
            basePitch: 60,
            accelerationFactor: 2.0,
            velocity: 80
        )
        let track = Track(name: "lead", instrument: "piano", fragmentPlacements: [placement])
        let section = makeSection(tracks: [track])
        let piece = makePiece(fragments: [fragment], sections: [section])

        let notes = track.scheduledNotes(in: piece, section: section)

        XCTAssertEqual(notes.map(\.pitch), [60, 62, 64])
        XCTAssertEqual(notes.map(\.durationBeats), [0.5, 0.5, 0.5])
        XCTAssertEqual(notes.map(\.startBeat), [0, 0.5, 1.0])
        XCTAssertEqual(notes.map(\.velocity), [80, 80, 80])
    }

    func testScheduledNotesSkipsFragmentPlacementsWithUnknownFragmentID() {
        let placement = FragmentPlacement(fragmentID: "does-not-exist", measure: 1, beat: 1, basePitch: 60)
        let track = Track(name: "lead", instrument: "piano", fragmentPlacements: [placement])
        let section = makeSection(tracks: [track])
        let piece = makePiece(sections: [section])

        XCTAssertEqual(track.scheduledNotes(in: piece, section: section), [])
    }

    func testScheduledNotesMergesAndSortsMelodyEventsAndFragmentPlacements() {
        let fragment = MelodicFragment(id: "motif-1", name: "motif", referenceMode: .fromFirstNote, intervals: [4], noteDurations: [1, 1])
        let track = Track(
            name: "lead",
            instrument: "piano",
            melodyEvents: [MelodyEvent(measure: 1, beat: 3, durationBeats: 1, pitch: 72)],
            fragmentPlacements: [FragmentPlacement(fragmentID: "motif-1", measure: 1, beat: 1, basePitch: 60)]
        )
        let section = makeSection(tracks: [track])
        let piece = makePiece(fragments: [fragment], sections: [section])

        let notes = track.scheduledNotes(in: piece, section: section)

        XCTAssertEqual(notes.map(\.startBeat), [0, 1, 2])
        XCTAssertEqual(notes.map(\.pitch), [60, 64, 72])
    }

    private func makeSectionWithChord(_ event: ChordEvent) -> Section {
        Section(
            name: "A",
            lengthInMeasures: 1,
            mode: ModeReference(tonic: 0, scaleID: "dorian"),
            chordProgression: [event]
        )
    }

    func testChordScheduledNotesSimultaneousDefaultIsRootPosition() {
        // Dm7 (root D=2, mi7 = [0,3,7,10]) at octaveBase 48: D3 F3 A3 C4, root at the bass.
        let section = makeSectionWithChord(ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 2, chordTemplateID: "mi7")))
        let notes = section.chordScheduledNotes(beatsPerMeasure: 4)
        XCTAssertEqual(notes.map(\.pitch), [50, 53, 57, 60])
        XCTAssertEqual(notes.map(\.startBeat), [0, 0, 0, 0])
        XCTAssertEqual(notes.map(\.durationBeats), [4, 4, 4, 4])
    }

    func testChordScheduledNotesFirstInversionMovesRootUpAnOctave() {
        let section = makeSectionWithChord(
            ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 2, chordTemplateID: "mi7"), inversion: 1)
        )
        let notes = section.chordScheduledNotes(beatsPerMeasure: 4)
        // Root position was [50, 53, 57, 60]; first inversion drops the bottom note (root)
        // to the top, an octave up.
        XCTAssertEqual(notes.map(\.pitch).sorted(), [53, 57, 60, 62])
    }

    func testChordScheduledNotesBassOverrideAddsSlashBassBelowChord() {
        // Dm7/A: A (pitch class 9) is already a chord tone, so it's pulled down an octave.
        let section = makeSectionWithChord(
            ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 2, chordTemplateID: "mi7"), bassOverride: 9)
        )
        let notes = section.chordScheduledNotes(beatsPerMeasure: 4)
        XCTAssertEqual(notes.map(\.pitch), [45, 50, 53, 60])
    }

    func testChordScheduledNotesArpeggioUpSpreadsNotesAcrossDuration() {
        let section = makeSectionWithChord(
            ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma7"), playingStyle: .arpeggioUp)
        )
        let notes = section.chordScheduledNotes(beatsPerMeasure: 4)
        XCTAssertEqual(notes.map(\.pitch), [48, 52, 55, 59])
        XCTAssertEqual(notes.map(\.startBeat), [0, 1, 2, 3])
    }

    func testChordScheduledNotesUnknownTemplateProducesNoNotes() {
        let section = makeSectionWithChord(
            ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "not-a-chord"))
        )
        XCTAssertEqual(section.chordScheduledNotes(beatsPerMeasure: 4), [])
    }

    func testPieceRenderedNotesCombinesChordsAndTracksInSeconds() {
        let track = Track(name: "lead", instrument: "piano", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 72)])
        let section = Section(
            name: "A",
            lengthInMeasures: 1,
            mode: ModeReference(tonic: 0, scaleID: "ionian"),
            chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma7"))],
            tracks: [track]
        )
        let piece = Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section])
        // 120 BPM => 0.5s per beat.
        let notes = piece.renderedNotes()
        XCTAssertEqual(notes.count, 5) // 4 chord tones + 1 melody note
        XCTAssertEqual(notes.map(\.startSeconds), [0, 0, 0, 0, 0])
        XCTAssertTrue(notes.contains { $0.pitch == 72 && $0.durationSeconds == 0.5 })
        XCTAssertTrue(notes.contains { $0.pitch == 48 && $0.durationSeconds == 2.0 })
    }

    func testPieceRenderedNotesOffsetsSecondSectionByFirstSectionsLength() {
        let sectionA = Section(name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"))
        let trackB = Track(name: "lead", instrument: "piano", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60)])
        let sectionB = Section(name: "B", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"), tracks: [trackB])
        let piece = Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [sectionA, sectionB])
        let notes = piece.renderedNotes()
        // Section A is 1 measure of 4 beats at 0.5s/beat = 2s before section B starts.
        XCTAssertEqual(notes.map(\.startSeconds), [2.0])
    }
}
