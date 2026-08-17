import XCTest
@testable import AppCore
@testable import PieceModel
import MusicTheoryKit

/// `ImprovSession.theoryDisplayState` — the single held-pitches/chord/mode tuple every Théorie
/// screen reads, either from a live track (`theoryLiveInputSourceID`, unchanged behavior) or from
/// piece playback (`piecePlaybackObservationScope`, new). See that property's own doc comment for
/// why playback's chord/mode are always the piece's ground truth regardless of which track(s) are
/// observed for held pitches specifically.
final class TheoryDisplayStateTests: XCTestCase {
    func testReturnsNilWhenNothingIsSelected() {
        let session = makeTestSession()
        XCTAssertNil(session.theoryDisplayState)
    }

    func testFallsBackToLiveTrackRecognitionWhenNotObservingPlayback() throws {
        let session = makeTestSession()
        try session.start()
        session.pressKey(pitch: 60, track: .computerKeyboard)
        session.pressKey(pitch: 64, track: .computerKeyboard)
        session.pressKey(pitch: 67, track: .computerKeyboard)
        session.setTheoryLiveInputSource(.computerKeyboard)

        let state = try XCTUnwrap(session.theoryDisplayState)
        XCTAssertEqual(state.heldPitches, [60, 64, 67])
        XCTAssertEqual(state.chordRoot, 0, "C major triad -> root C")
    }

    private func loadTemporaryPiece(_ piece: Piece, into session: ImprovSession) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try JSONEncoder().encode(piece).write(to: url)
        try session.loadPiece(fromJSONFile: url.path)
    }

    /// Two named tracks, each holding one long, distinct note — slow enough (60 BPM, 4-beat
    /// notes) that a short sleep safely catches both mid-flight without racing completion, same
    /// pattern `ImprovSessionTests.testPlayTracksPlaybackStateSynchronouslyThenClearsItWhenFinished`
    /// already uses for playback-state tests.
    private func twoTrackPiece() -> Piece {
        let section = Section(
            name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 2, scaleID: "ionian"),
            chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 2, chordTemplateID: "Ma"))],
            tracks: [
                Track(name: "Melody", instrument: "", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 74, velocity: 100)]),
                Track(name: "Bass", instrument: "", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 38, velocity: 100)]),
            ]
        )
        return Piece(title: "t", tempoBPM: 60, key: ModeReference(tonic: 2, scaleID: "ionian"), sections: [section])
    }

    func testWholePieceScopeUsesGroundTruthChordAndCombinesAllTracksHeldPitches() throws {
        let session = makeTestSession()
        try session.start()
        try loadTemporaryPiece(twoTrackPiece(), into: session)
        session.setPiecePlaybackObservationScope(.wholePiece)

        try session.play()
        // Chord/mode come from `playbackTimeline`, set synchronously in `play()` — no sleep needed.
        let immediateState = try XCTUnwrap(session.theoryDisplayState)
        XCTAssertEqual(immediateState.chordRoot, 2, "D major chord -> root D, the piece's own ground truth")
        XCTAssertTrue(immediateState.modeTones.contains(2))

        Thread.sleep(forTimeInterval: 0.15) // let the note-onset closures (scheduled, async) fire
        let state = try XCTUnwrap(session.theoryDisplayState)
        // Superset, not exact equality: the section's own chord accompaniment ALSO sounds
        // (correctly — `playbackHeldPitches` is "every pitch currently sounding", not just
        // tracks) — what this test actually verifies is that BOTH tracks' own notes are there,
        // regardless of what else is playing alongside them.
        XCTAssertTrue(state.heldPitches.isSuperset(of: [74, 38]), "whole piece -> both tracks' notes combined, got \(state.heldPitches)")
        session.stopPlayback()
    }

    func testTracksScopeFiltersHeldPitchesButChordModeStayGroundTruth() throws {
        let session = makeTestSession()
        try session.start()
        try loadTemporaryPiece(twoTrackPiece(), into: session)
        session.setPiecePlaybackObservationScope(.tracks(["Melody"]))

        try session.play()
        Thread.sleep(forTimeInterval: 0.15)
        let state = try XCTUnwrap(session.theoryDisplayState)
        XCTAssertEqual(state.heldPitches, [74], "only the selected track's notes, not Bass's")
        XCTAssertEqual(state.chordRoot, 2, "chord/mode are never filtered by track selection")
        session.stopPlayback()
    }

    func testPlaybackScopeTakesPriorityOverALiveTrackWhenBothAreSet() throws {
        let session = makeTestSession()
        try session.start()
        session.pressKey(pitch: 60, track: .computerKeyboard)
        session.setTheoryLiveInputSource(.computerKeyboard)
        try loadTemporaryPiece(twoTrackPiece(), into: session)
        session.setPiecePlaybackObservationScope(.wholePiece)
        try session.play()

        let state = try XCTUnwrap(session.theoryDisplayState)
        XCTAssertEqual(state.chordRoot, 2, "playback ground truth wins over the live track's own recognition")
        session.stopPlayback()
    }
}
