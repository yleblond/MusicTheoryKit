import XCTest
@testable import AudioEngine

final class MicrophonePitchStabilizerTests: XCTestCase {

    func testPassthroughConfirmsEveryWindowImmediately() {
        let stabilizer = MicrophonePitchStabilizer(policy: .passthrough)
        XCTAssertEqual(stabilizer.ingest([60]), [StabilizedTransition(pitch: 60, kind: .noteOn)])
        XCTAssertEqual(stabilizer.ingest([60, 64]), [StabilizedTransition(pitch: 64, kind: .noteOn)])
        XCTAssertEqual(stabilizer.ingest([]), [
            StabilizedTransition(pitch: 60, kind: .noteOff),
            StabilizedTransition(pitch: 64, kind: .noteOff),
        ])
    }

    func testLatchedRejectsFlickerShorterThanN() {
        let stabilizer = MicrophonePitchStabilizer(policy: .latched(windows: 3))
        XCTAssertEqual(stabilizer.ingest([60]), [])
        XCTAssertEqual(stabilizer.ingest([]), [])
        XCTAssertEqual(stabilizer.ingest([60]), [])
        XCTAssertEqual(stabilizer.confirmedPitches, [])
    }

    func testLatchedConfirmsNoteOnAfterNConsecutiveWindows() {
        let stabilizer = MicrophonePitchStabilizer(policy: .latched(windows: 3))
        XCTAssertEqual(stabilizer.ingest([60]), [])
        XCTAssertEqual(stabilizer.ingest([60]), [])
        XCTAssertEqual(stabilizer.ingest([60]), [StabilizedTransition(pitch: 60, kind: .noteOn)])
        XCTAssertEqual(stabilizer.confirmedPitches, [60])
    }

    func testLatchedConfirmsNoteOffOnlyAfterNConsecutiveAbsences() {
        let stabilizer = MicrophonePitchStabilizer(policy: .latched(windows: 2))
        _ = stabilizer.ingest([60])
        XCTAssertEqual(stabilizer.ingest([60]), [StabilizedTransition(pitch: 60, kind: .noteOn)])
        XCTAssertEqual(stabilizer.ingest([]), []) // one dropout: not yet confirmed off
        XCTAssertEqual(stabilizer.confirmedPitches, [60])
        XCTAssertEqual(stabilizer.ingest([]), [StabilizedTransition(pitch: 60, kind: .noteOff)])
        XCTAssertEqual(stabilizer.confirmedPitches, [])
    }

    func testSlidingConfirmsByMajorityNotConsecutive() {
        let stabilizer = MicrophonePitchStabilizer(policy: .sliding(windows: 3))
        XCTAssertEqual(stabilizer.ingest([60]), [])       // 1/1 present
        XCTAssertEqual(stabilizer.ingest([]), [])         // 1/2 present, no majority yet
        XCTAssertEqual(stabilizer.ingest([60]), [StabilizedTransition(pitch: 60, kind: .noteOn)]) // 2/3 present -> majority
    }

    func testSlidingToleratesOneDroppedWindow() {
        let stabilizer = MicrophonePitchStabilizer(policy: .sliding(windows: 3))
        _ = stabilizer.ingest([60])
        _ = stabilizer.ingest([60])
        XCTAssertEqual(stabilizer.ingest([60]), [StabilizedTransition(pitch: 60, kind: .noteOn)])
        // One dropped window out of the last 3 (60,60,-) is still a majority present -> stays confirmed.
        XCTAssertEqual(stabilizer.ingest([]), [])
        XCTAssertEqual(stabilizer.confirmedPitches, [60])
    }

    func testWindowsOfOneMatchesPassthroughForBothPolicies() {
        let latched = MicrophonePitchStabilizer(policy: .latched(windows: 1))
        let sliding = MicrophonePitchStabilizer(policy: .sliding(windows: 1))
        let passthrough = MicrophonePitchStabilizer(policy: .passthrough)
        for observed: Set<Int> in [[60], [60, 64], [64], []] {
            XCTAssertEqual(latched.ingest(observed), passthrough.ingest(observed))
        }
        for observed: Set<Int> in [[60], [60, 64], [64], []] {
            XCTAssertEqual(sliding.ingest(observed), passthrough.ingest(observed))
        }
    }

    func testMultiplePitchesTrackedIndependently() {
        let stabilizer = MicrophonePitchStabilizer(policy: .latched(windows: 2))
        // 60 is present in every window (confirms after 2 consecutive); 64 alternates
        // present/absent — present in 2 of 3 windows overall, but never twice IN A ROW, so
        // under `.latched` (unlike `.sliding`'s majority rule) it never confirms at all.
        XCTAssertEqual(stabilizer.ingest([60, 64]), [])
        XCTAssertEqual(stabilizer.ingest([60]), [StabilizedTransition(pitch: 60, kind: .noteOn)])
        XCTAssertEqual(stabilizer.ingest([60, 64]), [])
        XCTAssertEqual(stabilizer.confirmedPitches, [60])
    }

    func testResetClearsHistoryAndConfirmedPitches() {
        let stabilizer = MicrophonePitchStabilizer(policy: .latched(windows: 2))
        _ = stabilizer.ingest([60])
        _ = stabilizer.ingest([60])
        XCTAssertEqual(stabilizer.confirmedPitches, [60])
        stabilizer.reset()
        XCTAssertEqual(stabilizer.confirmedPitches, [])
        // Fresh history: needs the full N again, not just one more window.
        XCTAssertEqual(stabilizer.ingest([60]), [])
    }
}
