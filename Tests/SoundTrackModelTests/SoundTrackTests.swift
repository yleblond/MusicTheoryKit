import XCTest
@testable import SoundTrackModel

final class SoundTrackTests: XCTestCase {
    func testSoundTrackRoundTripsThroughJSON() throws {
        let events = [
            RecordedNoteEvent(timeSeconds: 0.0, trackID: "clavier", isNoteOn: true, pitch: 60, velocity: 100),
            RecordedNoteEvent(timeSeconds: 0.5, trackID: "clavier", isNoteOn: false, pitch: 60, velocity: 0),
        ]
        let original = SoundTrack(title: "Test", durationSeconds: 0.5, events: events)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SoundTrack.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testTrackIDsCollectsDistinctSources() {
        let soundTrack = SoundTrack(title: "Multi", durationSeconds: 1, events: [
            RecordedNoteEvent(timeSeconds: 0, trackID: "clavier", isNoteOn: true, pitch: 60, velocity: 100),
            RecordedNoteEvent(timeSeconds: 0.1, trackID: "midi:1", isNoteOn: true, pitch: 64, velocity: 90),
            RecordedNoteEvent(timeSeconds: 0.2, trackID: "clavier", isNoteOn: false, pitch: 60, velocity: 0),
        ])
        XCTAssertEqual(soundTrack.trackIDs, ["clavier", "midi:1"])
    }
}
