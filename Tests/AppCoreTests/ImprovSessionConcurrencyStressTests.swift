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

    /// Regression stress test for a real reported hang, confirmed via a live `sample` of the
    /// actually-frozen app: the main thread was inside `SceneRoleRow.body.getter` →
    /// `displayedChannel(for:)` → `observedChannel(forMIDISourceIndex:)`, blocked waiting for
    /// `liveInputQueue`'s ownership token, while the real-time MIDI callback thread was parked
    /// INSIDE that very queue (running `handleIncomingMIDIEvent` → `refreshRecognition`,
    /// mutating the legitimately-observed `tracks`) waiting on SwiftUI's own Observation lock
    /// (`_MovableLockLock`/`ObservationCenter.invalidate`) — the same lock the main thread had
    /// already taken to evaluate that very view body. Two threads, each holding what the other
    /// blocks on. `@ObservationIgnored` alone (this property's first fix) did NOT resolve it:
    /// the cycle isn't about which property is Observed, it's that `liveInputQueue.sync` from
    /// the main thread can never safely wait behind a real-time thread that might itself be
    /// waiting on the Observation lock for something unrelated (`tracks`). The actual fix moved
    /// `passiveObservedChannels` onto its own dedicated `passiveChannelQueue`, never shared with
    /// `tracks`'s own mutations — see that property's doc comment. This test hammers real note
    /// traffic (`liveInputQueue.sync` via `pressKey`/`releaseKey`) concurrently with UI-style
    /// channel reads (`observedChannel`/`displayedChannel`), for long enough that a reintroduced
    /// deadlock has a real chance to hang this test until XCTest's own timeout fails it, instead
    /// of silently passing. Deliberately does NOT also hammer `session.tracks` from a background
    /// thread: real SwiftUI only ever reads that property from the main thread, so a background
    /// thread doing the same is a stress pattern with no equivalent in the running app, not a
    /// reproduction of anything users can actually hit — `tracks` itself being safe for a
    /// non-main thread to read concurrently with a real-time write is a separate, pre-existing
    /// question this test doesn't take a position on either way.
    func testConcurrentChannelReadsAlongsideNoteTrafficNeverHangs() throws {
        let session = ImprovSession()
        try session.start()
        try session.startTrack(.computerKeyboard)
        // Captured once, before any concurrent work starts — a plain local copy, not a repeated
        // live read of `session.tracks` (see this test's own doc comment on why that's excluded).
        let fixedTracks = session.tracks

        // A `DispatchGroup` with a timed `wait`, not `XCTestExpectation`/`waitForExpectations`
        // (`@MainActor`-isolated, awkward to call from a plain synchronous stress test): a
        // timeout here means a real hang, and `wait(timeout:)` returning `.timedOut` fails the
        // test instead of blocking CI forever the way the original bug blocked the app itself.
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            for i in 0..<400 {
                let pitch = 60 + (i % 12)
                session.pressKey(pitch: pitch)
                session.releaseKey(pitch: pitch)
            }
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            for _ in 0..<400 {
                // `refreshTracks()` rebuilds `passiveChannelSniffers`/`passiveObservedChannels`
                // (`refreshPassiveChannelSniffers`) on every call, going through `liveInputQueue`
                // (see that function's own doc comment for the real crash this guards against:
                // concurrent with real note traffic, this used to corrupt `tracks`' backing
                // storage — "deallocated with non-zero retain count", reproduced and fixed).
                session.refreshTracks()
            }
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            for _ in 0..<400 {
                for track in fixedTracks {
                    _ = session.displayedChannel(for: track)
                }
            }
            group.leave()
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success, "concurrent MIDI/channel work hung instead of completing")
    }
}
