import XCTest
@testable import AudioEngine
#if os(iOS)
import AVFoundation
#endif

/// Covers the fix for "assigned a sound but nothing plays on iOS": `SamplerUnit`/`PiecePlayer`
/// each ran their own `AVAudioEngine` with no `AVAudioSession` handling at all, so on iOS,
/// output stayed under the default `.soloAmbient` category — silenced by the Silent switch,
/// and never guaranteed to actually route to the speaker. `MicrophonePitchListener` already
/// had the equivalent fix for its own (record-capable) session, but only runs it when the
/// microphone track actually starts; a track that only ever plays a sample never touched it.
final class PlaybackAudioSessionTests: XCTestCase {
    func testActivateIfNeededMovesSessionOffDefaultCategoryOnIOS() {
        #if os(iOS)
        PlaybackAudioSession.activateIfNeeded()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playAndRecord)
        #else
        PlaybackAudioSession.activateIfNeeded() // no-op on macOS; just confirm it doesn't crash
        #endif
    }

    func testSamplerUnitStartsAndSoundsANoteWithoutThrowing() throws {
        let unit = SamplerUnit()
        try unit.start()
        unit.startNote(pitch: 60, velocity: 100)
        unit.stopNote(pitch: 60)
        unit.stop()
    }

    func testPiecePlayerStartsWithoutThrowing() throws {
        let player = PiecePlayer()
        try player.start()
        player.stop()
    }
}
