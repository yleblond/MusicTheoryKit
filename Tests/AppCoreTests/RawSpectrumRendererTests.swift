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
}
