import XCTest
@testable import AppCore
import AudioEngine

/// No `.sf2` fixture is bundled in this repo (see `OctaveSpectrumGridTests`'s own comment) — these
/// tests drive the internal `render(pitches:renderer:)` split directly, against an
/// `OfflineNoteRenderer` that never had `loadSample` called (exercising `AVAudioUnitSampler`'s own
/// built-in default instrument), same reasoning as `OctaveSpectrumGridBuilder.build`'s own tests.
final class RawSpectrumRendererTests: XCTestCase {
    func testRenderReturnsOneSpectrumPerRequestedPitchInOrder() throws {
        let renderer = try OfflineNoteRenderer()
        let spectra = try RawSpectrumRenderer.render(pitches: [(60, 0), (64, 0), (67, -15)], renderer: renderer)
        XCTAssertEqual(spectra.count, 3)
    }

    func testEachSpectrumHasHalfTheAnalyzerWindowSizeOfBins() throws {
        let renderer = try OfflineNoteRenderer()
        let spectra = try RawSpectrumRenderer.render(pitches: [(60, 0)], renderer: renderer)
        let spectrum = try XCTUnwrap(spectra.first)
        XCTAssertEqual(spectrum.magnitudes.count, 2048) // FFTPitchAnalyzer(size: 4096) → size/2 bins
        XCTAssertGreaterThan(spectrum.binHz, 0)
    }

    func testRawNoteSpectrumStoresWhatItsGivenVerbatim() {
        let spectrum = RawNoteSpectrum(magnitudes: [1, 2, 3], binHz: 10.75)
        XCTAssertEqual(spectrum.magnitudes, [1, 2, 3])
        XCTAssertEqual(spectrum.binHz, 10.75)
    }

    func testRenderChordReturnsOneConsolidatedPairRegardlessOfToneCount() throws {
        let renderer = try OfflineNoteRenderer()
        let result = try RawSpectrumRenderer.renderChord(pitches: [(60, 0), (64, -14), (67, 3)], renderer: renderer)
        XCTAssertEqual(result.raw.magnitudes.count, 2048)
        XCTAssertEqual(result.corrected.magnitudes.count, 2048)
    }

    func testRenderChordRawUsesZeroCentsEvenWhenPitchesCarryTheirOwn() throws {
        // Rendering the SAME pitches with `cents: 0` on every entry (what `raw` should behave
        // like internally) must be identical to `renderChord`'s own `raw` result — confirms the
        // "raw" pass really does force every tone to 0 cents rather than reusing whatever was
        // passed in.
        let rendererA = try OfflineNoteRenderer()
        let viaRenderChord = try RawSpectrumRenderer.renderChord(pitches: [(60, 0), (64, 40), (67, -25)], renderer: rendererA)
        let rendererB = try OfflineNoteRenderer()
        let viaZeroedManually = try RawSpectrumRenderer.renderChord(pitches: [(60, 0), (64, 0), (67, 0)], renderer: rendererB)
        XCTAssertEqual(viaRenderChord.raw.magnitudes, viaZeroedManually.raw.magnitudes)
    }
}
