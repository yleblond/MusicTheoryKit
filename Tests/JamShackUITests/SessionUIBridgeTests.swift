import XCTest
@testable import JamShackUI
import AppCore

@MainActor
final class SessionUIBridgeTests: XCTestCase {

    func testInitialStateMatchesBuildWebConsoleStateAtConstruction() throws {
        let session = ImprovSession()
        try session.start()
        let bridge = SessionUIBridge(session: session)
        XCTAssertEqual(bridge.state.tracks.count, session.buildWebConsoleState().tracks.count)
    }

    func testPollingPicksUpLiveSessionChanges() async throws {
        let session = ImprovSession()
        try session.start()
        try session.startTrack(.computerKeyboard)
        // Poll fast so the test doesn't need to wait long.
        let bridge = SessionUIBridge(session: session, pollsPerSecond: 60)

        session.pressKey(pitch: 60)
        session.pressKey(pitch: 64)
        session.pressKey(pitch: 67)

        // Give the poll loop a few cycles to observe the change.
        try await Task.sleep(for: .milliseconds(200))

        let clavier = bridge.state.tracks.first { $0.id == "clavier" }
        XCTAssertEqual(Set(clavier?.heldPitches ?? []), Set([60, 64, 67]))
    }
}
