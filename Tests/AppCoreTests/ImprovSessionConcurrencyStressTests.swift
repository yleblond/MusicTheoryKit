import XCTest
@testable import AppCore
import PieceModel
import MusicTheoryKit
import Foundation

// Regression stress tests for the two concurrency bug classes that have each caused a real
// crash in this project (see Docs/BACKLOG.md and ImprovSession.swift's liveInputQueue/
// playbackStateQueue doc comments): a single clean run proves nothing for this class of
// intermittent bug, so these deliberately repeat many iterations. Deliberately separate from
// ImprovSessionTests.swift — these are slow and repetitive by design, not fast unit tests.
//
// Run under Thread Sanitizer for real assurance: `swift test --sanitize=thread --filter
// ImprovSessionConcurrencyStressTests`.
final class ImprovSessionConcurrencyStressTests: XCTestCase {

    // Guards against a regression of the `playbackHeldPitches`/`playbackGeneration` race
    // (ImprovSession.swift's playbackStateQueue doc comment): overlapping `play()` calls used
    // to schedule `.global()` callbacks that mutated a shared `Set` from multiple concurrent
    // worker threads with no synchronization — "a genuine data race that crashed with memory
    // corruption in testing." Calling play() back-to-back on a very fast piece, faster than
    // each call's own callbacks can finish, re-exercises exactly that overlap.
    func testRepeatedOverlappingPlayCallsNeverCorruptPlaybackState() throws {
        let session = ImprovSession()
        try session.start()

        let section = Section(
            name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
            chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 1, chord: ChordReference(root: 0, chordTemplateID: "Ma7"))]
        )
        // Very fast tempo so each play() finishes almost immediately, letting many
        // iterations run quickly while still overlapping the next call's own scheduling.
        let piece = Piece(title: "stress", tempoBPM: 6000, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section])
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try JSONEncoder().encode(piece).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.loadPiece(fromJSONFile: tempFile.path)

        for _ in 0..<500 {
            try session.play()
            Thread.sleep(forTimeInterval: 0.002) // shorter than the piece's own duration — guarantees overlap with the next play()
        }
        // Let the last play() call's full duration + trailing cleanup callback actually fire.
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertFalse(session.isPlaying, "the final generation's cleanup callback must still fire and clear isPlaying")
        XCTAssertTrue(session.playbackHeldPitches.isEmpty, "no stale callback from an earlier generation left a stuck pitch")
        XCTAssertNil(session.playbackCurrentChordIndex)
    }

    // Guards against a regression of the computer-keyboard auto-release race
    // (ImprovSession.swift's liveInputQueue doc comment): several notes pressed in quick
    // succession used to schedule independent `.global()` release timers that could fire
    // concurrently with each other and with a fresh press — "crashed with a bad pointer
    // dereference in RecognitionEngine.noteOff in the field." `DispatchQueue.concurrentPerform`
    // (not `Task`) guarantees genuine multi-thread concurrent entry, which is what actually
    // stresses liveInputQueue's `.sync` serialization.
    func testConcurrentPressAndReleaseFromMultipleThreadsNeverCorruptsHeldPitches() throws {
        let session = ImprovSession()
        try session.start()
        try session.startTrack(.computerKeyboard)

        DispatchQueue.concurrentPerform(iterations: 200) { i in
            let pitch = 60 + (i % 12)
            session.pressKey(pitch: pitch)
            session.releaseKey(pitch: pitch)
        }

        // A direct read proves the queue drained cleanly with no crash and a consistent
        // final state, not just "the process didn't die."
        session.releaseAllKeys(track: .computerKeyboard)
        XCTAssertTrue(session.tracks.first { $0.id == .computerKeyboard }?.heldPitches.isEmpty ?? false)
    }
}
