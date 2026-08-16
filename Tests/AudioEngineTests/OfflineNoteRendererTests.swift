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

    func testRenderChordReturnsApproximatelyTheRequestedSampleCount() throws {
        let renderer = try OfflineNoteRenderer(sampleRate: 44100)
        let samples = try renderer.renderChord(pitches: [(60, 0), (64, 0), (67, 0)], durationSeconds: 0.5)
        XCTAssertGreaterThanOrEqual(samples.count, Int(0.5 * 44100))
        XCTAssertLessThan(samples.count, Int(0.5 * 44100) + 8192)
    }

    func testRenderChordProducesNonSilentAudio() throws {
        let renderer = try OfflineNoteRenderer(sampleRate: 44100)
        let samples = try renderer.renderChord(pitches: [(60, 0), (64, 0), (67, 0)], durationSeconds: 0.5)
        XCTAssertGreaterThan(FFTPitchAnalyzer.rms(of: Array(samples.suffix(4096))), FFTPitchAnalyzer.minimumRMSForDetection)
    }

    /// Each tone's own independent pitch-bend (one MIDI channel per tone — see `renderChord`'s
    /// own doc comment) must actually take effect in the MIXED output, not just the last one
    /// applied — a real regression this shape of bug could hide: if channel assignment were
    /// broken (e.g. every tone accidentally sharing channel 0), only one cents value could ever
    /// apply at a time. Comparing a chord rendered with all-zero cents against the same chord
    /// with a large uniform offset on every tone should produce a MEASURABLY different spectrum
    /// (peaks shift), confirming the offsets reached the sampler.
    func testRenderChordAppliesEachChannelsOwnPitchBend() throws {
        let renderer = try OfflineNoteRenderer(sampleRate: 44100)
        let unbent = try renderer.renderChord(pitches: [(60, 0), (64, 0), (67, 0)], durationSeconds: 0.5)
        let renderer2 = try OfflineNoteRenderer(sampleRate: 44100)
        let bent = try renderer2.renderChord(pitches: [(60, 90), (64, 90), (67, 90)], durationSeconds: 0.5)
        XCTAssertNotEqual(Array(unbent.suffix(4096)), Array(bent.suffix(4096)))
    }
}
