import XCTest
@testable import NetEngine

final class NetMessageTests: XCTestCase {
    func testNetMessageRoundTripsThroughJSON() throws {
        let original = NetMessage(
            kind: .noteEvent, clientID: "abc", trackID: "clavier",
            isNoteOn: true, pitch: 60, velocity: 100, channel: 0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NetMessage.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testSyncMessageCarriesTrackSnapshots() throws {
        let snapshot = RemoteTrackSnapshot(
            clientID: "abc", trackID: "midi", label: "MIDI (fusionne)",
            isListening: true, canHaveSound: true, heldPitches: [60, 64, 67],
            chordName: "CMa", modesText: "C ionian"
        )
        let message = NetMessage(kind: .sync, tracks: [snapshot])
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(NetMessage.self, from: data)
        XCTAssertEqual(decoded.tracks, [snapshot])
    }
}
