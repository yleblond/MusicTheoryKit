import XCTest
@testable import AudioEngine

/// No `.sf2` fixture is bundled in this repo (see `PiecePlayerTests`'s own comment on why —
/// soundfonts are user-downloaded assets, never checked in), so these tests exercise the
/// renderer's OWN mechanics (manual-rendering setup, buffer accumulation, note on/off) against
/// `AVAudioUnitSampler`'s built-in default instrument rather than a loaded `.sf2` — enough to
/// catch a broken render loop (wrong buffer length, a thrown/hung `renderOffline`, silence)
/// without needing a real soundfont on disk.
final class OfflineNoteRendererTests: XCTestCase {
    func testRenderNoteReturnsApproximatelyTheRequestedSampleCount() throws {
        let renderer = try OfflineNoteRenderer(sampleRate: 44100)
        let samples = try renderer.renderNote(pitch: 60, durationSeconds: 0.5)
        // Rendered in fixed-size chunks (`engine.manualRenderingMaximumFrameCount`), so the
        // actual count is rounded up to the next chunk boundary rather than exact.
        XCTAssertGreaterThanOrEqual(samples.count, Int(0.5 * 44100))
        XCTAssertLessThan(samples.count, Int(0.5 * 44100) + 8192)
    }

    func testRenderNoteProducesNonSilentAudio() throws {
        let renderer = try OfflineNoteRenderer(sampleRate: 44100)
        let samples = try renderer.renderNote(pitch: 69, durationSeconds: 0.5)
        XCTAssertGreaterThan(FFTPitchAnalyzer.rms(of: Array(samples.suffix(4096))), FFTPitchAnalyzer.minimumRMSForDetection)
    }

    func testRenderNoteWithACentsOffsetStillProducesNonSilentAudio() throws {
        let renderer = try OfflineNoteRenderer(sampleRate: 44100)
        let samples = try renderer.renderNote(pitch: 69, cents: 35, durationSeconds: 0.5)
        XCTAssertGreaterThan(FFTPitchAnalyzer.rms(of: Array(samples.suffix(4096))), FFTPitchAnalyzer.minimumRMSForDetection)
    }
}
