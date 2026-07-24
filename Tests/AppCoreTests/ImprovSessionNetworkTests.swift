import XCTest
@testable import AppCore
import PieceModel
import MusicTheoryKit
import Foundation

// Real HTTP/TCP integration tests over real loopback sockets (not mocks) — deliberately
// separate from ImprovSessionTests.swift: these are slow, use fixed ports, and exercise the
// actual NetworkServer/NetworkClient/HTTPServer wiring end to end, unlike the fast in-process
// unit tests in that file. Mirrors the technique SanityChecks used before this migration.
final class ImprovSessionNetworkTests: XCTestCase {

    private func syncGET(_ url: String, timeout: TimeInterval = 2) -> (status: Int, contentType: String?, body: String)? {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: (Int, String?, String)?
        URLSession.shared.dataTask(with: URL(string: url)!) { data, response, _ in
            if let http = response as? HTTPURLResponse, let data {
                result = (http.statusCode, http.value(forHTTPHeaderField: "Content-Type"), String(data: data, encoding: .utf8) ?? "")
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + timeout)
        return result
    }

    // A real client/server pair over real loopback TCP, both `ImprovSession` instances living
    // in this one process — exercises the actual `NetworkServer`/`NetworkClient`/
    // `FramedConnection` wire path end to end. Port 17891 is arbitrary; a rerun failing
    // specifically with "address already in use" points at the OS not having released it yet
    // from a previous run, not a logic bug.
    func testCollaborativeServerClientSyncsTracksAndRecognition() throws {
        let server = ImprovSession()
        try server.start()
        server.localClientName = "Alice"
        let client = ImprovSession()
        try client.start()
        client.localClientName = "Bob"
        let port = 17891

        try server.startServer(port: port)
        try client.connectToServer(host: "127.0.0.1", port: port)
        Thread.sleep(forTimeInterval: 0.3) // TCP handshake + hello

        try server.startTrack(.computerKeyboard)
        for pitch in [62, 66, 69] { server.pressKey(pitch: pitch) } // D F# A -> D major

        try client.startTrack(.computerKeyboard)
        for pitch in [60, 64, 67] { client.pressKey(pitch: pitch) } // C E G -> C major

        Thread.sleep(forTimeInterval: 0.6) // noteEvent -> server recognizes -> next sync tick -> client merges

        let clientTrackOnServer = TrackID.remote(clientID: client.localClientID, trackID: "clavier")
        let mirroredOnServer = try XCTUnwrap(server.tracks.first { $0.id == clientTrackOnServer })
        XCTAssertEqual(mirroredOnServer.recognizedChord?.chordTemplateID, "Ma")
        XCTAssertEqual(mirroredOnServer.ownerName, "Bob")

        let serverTrackOnClient = TrackID.remote(clientID: server.localClientID, trackID: "clavier")
        let mirroredOnClient = try XCTUnwrap(client.tracks.first { $0.id == serverTrackOnClient })
        XCTAssertTrue(mirroredOnClient.remoteChordDisplay?.contains("Ma") ?? false)
        XCTAssertEqual(mirroredOnClient.ownerName, "Alice")

        server.stopServer()
        client.disconnectFromServer()
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertFalse(server.tracks.contains { if case .remote = $0.id { return true }; return false })
        XCTAssertFalse(client.tracks.contains { if case .remote = $0.id { return true }; return false })
    }

    // A real HTTP round trip over real loopback TCP against the actual `HTTPServer`.
    func testWebConsoleServesPageScriptAndState() throws {
        let session = ImprovSession()
        try session.start()
        try session.startWebConsole(port: 18394)
        try session.startTrack(.computerKeyboard)
        session.pressKey(pitch: 60)
        session.pressKey(pitch: 64)
        session.pressKey(pitch: 67)
        Thread.sleep(forTimeInterval: 0.3) // let the 150ms refresh timer tick at least once

        let page = try XCTUnwrap(syncGET("http://127.0.0.1:18394/"))
        XCTAssertEqual(page.status, 200)
        XCTAssertTrue(page.contentType?.contains("text/html") ?? false)

        let script = try XCTUnwrap(syncGET("http://127.0.0.1:18394/app.js"))
        XCTAssertEqual(script.status, 200)
        XCTAssertEqual(script.contentType, "application/javascript")

        let state = try XCTUnwrap(syncGET("http://127.0.0.1:18394/state"))
        XCTAssertEqual(state.status, 200)
        XCTAssertTrue(state.body.contains("\"chordRoot\":0"))
        XCTAssertTrue(state.body.contains("\"id\":\"clavier\""))

        let notFound = try XCTUnwrap(syncGET("http://127.0.0.1:18394/nope"))
        XCTAssertEqual(notFound.status, 404)

        session.stopWebConsole()
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertNil(syncGET("http://127.0.0.1:18394/state", timeout: 1))
    }

    // No `.webKeyboard(clientID:)` track is pre-created at all — it's created on demand per
    // browser the first time that browser's `clientID` shows up in a request.
    func testStartVirtualKeyboardSetsPortAndStopRemovesAnyConnectedClientTracks() throws {
        let session = ImprovSession()
        try session.start()
        XCTAssertNil(session.virtualKeyboardPort)
        try session.startVirtualKeyboard(port: 18395)
        XCTAssertEqual(session.virtualKeyboardPort, 18395)
        XCTAssertFalse(session.tracks.contains { if case .webKeyboard = $0.id { return true }; return false })
        _ = syncGET("http://127.0.0.1:18395/note-on?pitch=60&client=test-client-1&name=Alice")
        XCTAssertTrue(session.tracks.contains { if case .webKeyboard = $0.id { return true }; return false })
        session.stopVirtualKeyboard()
        XCTAssertNil(session.virtualKeyboardPort)
        XCTAssertFalse(session.tracks.contains { if case .webKeyboard = $0.id { return true }; return false })
    }

    func testStartVirtualKeyboardTwiceThrows() throws {
        let session = ImprovSession()
        try session.startVirtualKeyboard(port: 18396)
        defer { session.stopVirtualKeyboard() }
        XCTAssertThrowsError(try session.startVirtualKeyboard(port: 18397)) { error in
            guard case ImprovSession.SessionError.virtualKeyboardAlreadyActive = error else {
                return XCTFail("expected virtualKeyboardAlreadyActive, got \(error)")
            }
        }
    }

    // Real HTTP round trip through the actual `GET /note-on`/`GET /note-off` routes (not
    // `session.pressKey` directly) — the point is verifying the HTTP-to-session wiring.
    func testVirtualKeyboardServesPageAndAcceptsNoteOnOff() throws {
        let session = ImprovSession()
        try session.start()
        try session.startVirtualKeyboard(port: 18398)

        let page = try XCTUnwrap(syncGET("http://127.0.0.1:18398/"))
        XCTAssertEqual(page.status, 200)
        XCTAssertTrue(page.contentType?.contains("text/html") ?? false)

        let script = try XCTUnwrap(syncGET("http://127.0.0.1:18398/app.js"))
        XCTAssertEqual(script.status, 200)
        XCTAssertEqual(script.contentType, "application/javascript")

        let noClient = try XCTUnwrap(syncGET("http://127.0.0.1:18398/state"))
        XCTAssertEqual(noClient.status, 400)

        let alice = "&client=alice-uuid&name=Alice"
        let before = try XCTUnwrap(syncGET("http://127.0.0.1:18398/state?dummy=1" + alice))
        XCTAssertTrue(before.body.contains("\"heldPitches\":[]"))
        XCTAssertTrue(before.body.contains("\"label\":\"Alice\""))

        _ = syncGET("http://127.0.0.1:18398/note-on?pitch=60" + alice)
        _ = syncGET("http://127.0.0.1:18398/note-on?pitch=64" + alice)
        _ = syncGET("http://127.0.0.1:18398/note-on?pitch=67" + alice)
        Thread.sleep(forTimeInterval: 0.2)

        let held = try XCTUnwrap(syncGET("http://127.0.0.1:18398/state?dummy=1" + alice))
        XCTAssertTrue(held.body.contains("\"chordRoot\":0"))
        XCTAssertTrue(held.body.contains("\"id\":\"clavier-web:alice-uuid\""))

        // A second, unrelated client must get its OWN independent track — no cross-talk.
        let bob = "&client=bob-uuid&name=Bob"
        _ = syncGET("http://127.0.0.1:18398/note-on?pitch=62" + bob)
        Thread.sleep(forTimeInterval: 0.2)
        let bobState = try XCTUnwrap(syncGET("http://127.0.0.1:18398/state?dummy=1" + bob))
        let aliceState = try XCTUnwrap(syncGET("http://127.0.0.1:18398/state?dummy=1" + alice))
        XCTAssertTrue(bobState.body.contains("\"heldPitches\":[62]"))
        let alicePossibleOrders = ["[60,64,67]", "[60,67,64]", "[64,60,67]", "[64,67,60]", "[67,60,64]", "[67,64,60]"]
        XCTAssertTrue(alicePossibleOrders.contains { aliceState.body.contains("\"heldPitches\":\($0)") })

        _ = syncGET("http://127.0.0.1:18398/note-off?pitch=60" + alice)
        _ = syncGET("http://127.0.0.1:18398/note-off?pitch=64" + alice)
        _ = syncGET("http://127.0.0.1:18398/note-off?pitch=67" + alice)
        Thread.sleep(forTimeInterval: 0.2)

        let released = try XCTUnwrap(syncGET("http://127.0.0.1:18398/state?dummy=1" + alice))
        XCTAssertTrue(released.body.contains("\"heldPitches\":[]"))

        // The Escape "panic button" route — simulates a note stuck held and confirms
        // GET /release-all clears it without needing to know which pitch was stuck.
        _ = syncGET("http://127.0.0.1:18398/note-on?pitch=72" + alice)
        Thread.sleep(forTimeInterval: 0.2)
        _ = syncGET("http://127.0.0.1:18398/release-all?dummy=1" + alice)
        Thread.sleep(forTimeInterval: 0.2)
        let afterReleaseAll = try XCTUnwrap(syncGET("http://127.0.0.1:18398/state?dummy=1" + alice))
        XCTAssertTrue(afterReleaseAll.body.contains("\"heldPitches\":[]"))

        let badPitch = try XCTUnwrap(syncGET("http://127.0.0.1:18398/note-on?pitch=notanumber" + alice))
        XCTAssertEqual(badPitch.status, 400)

        session.stopVirtualKeyboard()
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertNil(syncGET("http://127.0.0.1:18398/state" + alice, timeout: 1))
    }

    func testVirtualKeyboardStateAlwaysIncludesWheelButOnlyGuideWhileActive() throws {
        let session = ImprovSession()
        try session.start()
        try session.startVirtualKeyboard(port: 18399)
        let client = "&client=guide-client&name=Guidee"

        // Synthesized `Encodable` conformance uses `encodeIfPresent` for `Optional`
        // properties — a `nil` field is OMITTED from the JSON entirely, so the absence
        // check is on the key itself.
        let noGuide = try XCTUnwrap(syncGET("http://127.0.0.1:18399/state?dummy=1" + client))
        XCTAssertFalse(noGuide.body.contains("\"guide\""))
        // `wheel` is always present, whether or not a guide is running.
        XCTAssertTrue(noGuide.body.contains("\"wheel\""))

        session.newGuideSequence(title: "Test")
        try session.addGuideStep(ModeReference(tonic: 9, scaleID: "lydian")) // A Lydian
        try session.startGuide()
        Thread.sleep(forTimeInterval: 0.1)

        let withGuide = try XCTUnwrap(syncGET("http://127.0.0.1:18399/state?dummy=1" + client))
        XCTAssertTrue(withGuide.body.contains("\"isActive\":true"))
        XCTAssertTrue(withGuide.body.contains("\"activeModeName\":\"Lydian\""))

        session.stopVirtualKeyboard()
    }

    func testVirtualKeyboardGuideAdvanceMovesTheSharedGuideStep() throws {
        let session = ImprovSession()
        try session.start()
        try session.startVirtualKeyboard(port: 18410)
        let client = "&client=advance-client&name=Advancer"

        session.newGuideSequence(title: "Advance Test")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.addGuideStep(ModeReference(tonic: 7, scaleID: "mixolydian"))
        try session.startGuide()
        XCTAssertEqual(session.currentGuideStepIndex, 0)

        let advanced = try XCTUnwrap(syncGET("http://127.0.0.1:18410/guide-advance?delta=1" + client))
        XCTAssertEqual(advanced.status, 200)
        XCTAssertEqual(session.currentGuideStepIndex, 1)

        let back = try XCTUnwrap(syncGET("http://127.0.0.1:18410/guide-advance?delta=-1" + client))
        XCTAssertEqual(back.status, 200)
        XCTAssertEqual(session.currentGuideStepIndex, 0)

        session.stopVirtualKeyboard()
    }

    func testVirtualKeyboardStateExposesCurrentStepChordProgression() throws {
        let session = ImprovSession()
        try session.start()
        try session.startVirtualKeyboard(port: 18411)
        let client = "&client=progression-client&name=Progressor"

        session.newGuideSequence(title: "Progression Test")
        // C Ionian + "ii-V-I (jazz)" resolves to Dmi, GMa, CMa (roman-numeral case IS the
        // quality, taken literally as a plain triad; no 7ths).
        let progression = ChordProgressionTemplate(name: "ii-V-I (jazz)", degrees: ["ii", "V", "I"])
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"), chordProgression: progression)
        try session.startGuide()
        Thread.sleep(forTimeInterval: 0.1)

        let withProgression = try XCTUnwrap(syncGET("http://127.0.0.1:18411/state?dummy=1" + client))
        XCTAssertTrue(withProgression.body.contains("\"currentChordProgressionName\":\"ii-V-I (jazz)\""))
        XCTAssertTrue(withProgression.body.contains("\"label\":\"Dmi\""))
        XCTAssertTrue(withProgression.body.contains("\"label\":\"GMa\""))
        XCTAssertTrue(withProgression.body.contains("\"label\":\"CMa\""))
        XCTAssertTrue(withProgression.body.contains("\"quality\":\"minor\""))
        XCTAssertTrue(withProgression.body.contains("\"quality\":\"major\""))

        session.stopVirtualKeyboard()
    }

    // The active palette's colors must appear in BOTH the web console's and the virtual
    // keyboard's `/state`, and switching palettes must be reflected on the very next poll.
    func testActiveColorPaletteIsReflectedInWebConsoleAndVirtualKeyboardState() throws {
        let session = ImprovSession()
        try session.start()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.loadOrCreateColorPalettes(fromJSONFile: tempFile.path)

        try session.startWebConsole(port: 18400)
        try session.startVirtualKeyboard(port: 18401)
        Thread.sleep(forTimeInterval: 0.3)

        let consoleState = try XCTUnwrap(syncGET("http://127.0.0.1:18400/state"))
        XCTAssertTrue(consoleState.body.contains("\"palette\":[\"#DB2A52\""))
        XCTAssertTrue(consoleState.body.contains("\"paletteTextColors\":[\"#ffffff\""))

        let vkState = try XCTUnwrap(syncGET("http://127.0.0.1:18401/state?client=palette-test&name=Test"))
        XCTAssertTrue(vkState.body.contains("\"palette\":[\"#DB2A52\""))
        XCTAssertTrue(vkState.body.contains("\"paletteTextColors\":[\"#ffffff\""))

        try session.selectColorPalette(named: "Pastel")
        Thread.sleep(forTimeInterval: 0.3)

        let consoleStateAfter = try XCTUnwrap(syncGET("http://127.0.0.1:18400/state"))
        XCTAssertTrue(consoleStateAfter.body.contains("\"palette\":[\"#FFADAD\""))
        XCTAssertTrue(consoleStateAfter.body.contains("\"paletteTextColors\":[\"#111111\""))

        let vkStateAfter = try XCTUnwrap(syncGET("http://127.0.0.1:18401/state?client=palette-test&name=Test"))
        XCTAssertTrue(vkStateAfter.body.contains("\"palette\":[\"#FFADAD\""))
        XCTAssertTrue(vkStateAfter.body.contains("\"paletteTextColors\":[\"#111111\""))

        session.stopWebConsole()
        session.stopVirtualKeyboard()
    }
}
