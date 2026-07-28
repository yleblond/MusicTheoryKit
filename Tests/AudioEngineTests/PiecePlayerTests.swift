import XCTest
@testable import AudioEngine
import PieceModel
import SoundFontModel

/// Covers the fix that made `PiecePlayer` group samplers by (instrument name, preset) instead
/// of by name alone — two tracks referencing the SAME multi-preset `.sf2` but different presets
/// must never share one `SamplerUnit`, since `AVAudioUnitSampler` can only have one preset
/// loaded at a time.
final class PiecePlayerTests: XCTestCase {
    func testPlayAttemptsAnIndependentLoadPerDistinctPresetEvenForTheSameFile() throws {
        let player = PiecePlayer()
        try player.start()

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        // Malformed on purpose — `AVAudioUnitSampler` throws loading it either way; the point
        // here is confirming BOTH presets get their OWN independent load attempt (and so their
        // own warning), rather than being deduped into a single sampler under the shared name.
        let url = tempDir.appendingPathComponent("Bank.sf2")
        try Data().write(to: url)

        let notes = [
            RenderedNote(
                startSeconds: 0, durationSeconds: 1, pitch: 60, velocity: 100,
                instrumentName: "Bank.sf2", instrumentPreset: SoundFontPresetIdentity(program: 0, bank: 0)
            ),
            RenderedNote(
                startSeconds: 0, durationSeconds: 1, pitch: 64, velocity: 100,
                instrumentName: "Bank.sf2", instrumentPreset: SoundFontPresetIdentity(program: 19, bank: 0)
            ),
        ]

        let warnings = player.play(notes, instrumentURLs: ["Bank.sf2": url])
        XCTAssertEqual(warnings.count, 2)
        player.stopAllNotes()
    }

    func testPlayReusesTheSameSamplerForRepeatedNotesWithTheSamePreset() throws {
        let player = PiecePlayer()
        try player.start()

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let url = tempDir.appendingPathComponent("Bank.sf2")
        try Data().write(to: url)

        let preset = SoundFontPresetIdentity(program: 0, bank: 0)
        let notes = [
            RenderedNote(startSeconds: 0, durationSeconds: 1, pitch: 60, velocity: 100, instrumentName: "Bank.sf2", instrumentPreset: preset),
            RenderedNote(startSeconds: 1, durationSeconds: 1, pitch: 62, velocity: 100, instrumentName: "Bank.sf2", instrumentPreset: preset),
        ]

        let warnings = player.play(notes, instrumentURLs: ["Bank.sf2": url])
        XCTAssertEqual(warnings.count, 1, "same file + same preset must be grouped onto one sampler, one load attempt")
        player.stopAllNotes()
    }
}
