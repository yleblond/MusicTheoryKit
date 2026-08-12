import XCTest
@testable import AppCore
import AudioEngine

/// No `.sf2` fixture is bundled in this repo (see `PiecePlayerTests`'s own comment) — these
/// tests build a grid WITHOUT calling `loadSample` at all, so `OfflineNoteRenderer` renders
/// through `AVAudioUnitSampler`'s own built-in default instrument. Enough to exercise the real
/// build-then-cache pipeline end to end (this is exactly what `OfflineNoteRendererTests` already
/// confirmed produces non-silent, analyzable audio) without needing a real soundfont on disk.
///
/// Each test uses its own fresh `UUID()` in the fake `.sf2` path, so cache entries never collide
/// between tests or between runs — left behind on disk afterward (harmless test debris in
/// `~/Library/Caches/DissonanceSpectra`, not worth the complexity of tearing down).
final class OctaveSpectrumGridTests: XCTestCase {
    private func testKey(samplesPerOctave: Int) -> OctaveSpectrumGridKey {
        OctaveSpectrumGridKey(soundFontPath: "/synthetic-\(UUID().uuidString).sf2", preset: nil, baseMidiPitch: 60, samplesPerOctave: samplesPerOctave)
    }

    private func assertApproximatelyEqual(_ actual: [Double], _ expected: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (a, e) in zip(actual, expected) { XCTAssertEqual(a, e, accuracy: accuracy, file: file, line: line) }
    }

    func testBuildProducesOneMoreThanSamplesPerOctavePoints() throws {
        let renderer = try OfflineNoteRenderer() // no loadSample — exercises the sampler's own built-in default instrument
        let grid = try OctaveSpectrumGridBuilder.build(key: testKey(samplesPerOctave: 4), renderer: renderer, progress: nil)
        XCTAssertEqual(grid.points.count, 5)
    }

    func testBuildPointsSpanExactlyOneOctaveInAscendingOrder() throws {
        let renderer = try OfflineNoteRenderer()
        let grid = try OctaveSpectrumGridBuilder.build(key: testKey(samplesPerOctave: 4), renderer: renderer, progress: nil)
        XCTAssertEqual(grid.points.first!.semitoneOffset, 0, accuracy: 1e-9)
        XCTAssertEqual(grid.points.last!.semitoneOffset, 12, accuracy: 1e-9)
        XCTAssertEqual(grid.points.map(\.semitoneOffset), grid.points.map(\.semitoneOffset).sorted())
        // Frequency should roughly double from the base pitch to an octave above (allowing for
        // the built-in default instrument's own real, slightly-off-nominal tuning).
        let ratio = grid.points.last!.frequencyHz / grid.points.first!.frequencyHz
        XCTAssertEqual(ratio, 2.0, accuracy: 0.05)
    }

    func testStoreLoadAfterSaveReturnsAnEquivalentGrid() throws {
        let renderer = try OfflineNoteRenderer()
        let key = testKey(samplesPerOctave: 3)
        let built = try OctaveSpectrumGridBuilder.build(key: key, renderer: renderer, progress: nil)
        try OctaveSpectrumGridStore.save(built)
        let loaded = OctaveSpectrumGridStore.load(for: key)
        XCTAssertEqual(loaded?.points.map(\.frequencyHz), built.points.map(\.frequencyHz))
    }

    func testStoreLoadReturnsNilForAKeyThatWasNeverSaved() {
        XCTAssertNil(OctaveSpectrumGridStore.load(for: testKey(samplesPerOctave: 5)))
    }

    func testProgressCallbackReachesOneAfterTheLastPoint() throws {
        let renderer = try OfflineNoteRenderer()
        var lastProgress: Double = 0
        _ = try OctaveSpectrumGridBuilder.build(key: testKey(samplesPerOctave: 3), renderer: renderer, progress: { lastProgress = $0 })
        XCTAssertEqual(lastProgress, 1.0, accuracy: 1e-9)
    }

    /// A hand-built grid (not via the builder — no audio involved) so the nearest-point lookup
    /// and scale-factor math can be checked precisely, independent of what a real (or the
    /// default-instrument stand-in) render happens to produce.
    private func syntheticGrid() -> OctaveSpectrumGrid {
        let key = OctaveSpectrumGridKey(soundFontPath: "/synthetic.sf2", preset: nil, baseMidiPitch: 60, samplesPerOctave: 2)
        let points = [
            OctaveSpectrumGrid.CapturedSpectrumPoint(semitoneOffset: 0, frequencyHz: 200, partials: [SpectralPartial(frequencyHz: 200, amplitude: 1), SpectralPartial(frequencyHz: 400, amplitude: 0.5)]),
            OctaveSpectrumGrid.CapturedSpectrumPoint(semitoneOffset: 6, frequencyHz: 283, partials: [SpectralPartial(frequencyHz: 283, amplitude: 1), SpectralPartial(frequencyHz: 566, amplitude: 0.4)]),
            OctaveSpectrumGrid.CapturedSpectrumPoint(semitoneOffset: 12, frequencyHz: 400, partials: [SpectralPartial(frequencyHz: 400, amplitude: 1), SpectralPartial(frequencyHz: 800, amplitude: 0.3)]),
        ]
        return OctaveSpectrumGrid(key: key, points: points)
    }

    func testPartialsAtExactlyACapturedPointsFrequencyAreUnscaled() {
        let grid = syntheticGrid()
        let result = grid.partials(atFrequencyHz: 200)
        XCTAssertEqual(result.map(\.frequencyHz), [200, 400])
        XCTAssertEqual(result.map(\.amplitude), [1, 0.5])
    }

    func testPartialsBetweenTwoPointsScaleTheNearestOnesFrequencies() {
        let grid = syntheticGrid()
        // 210 sits much closer to the 200Hz point than to the 283Hz one — should scale THAT
        // point's partials by 210/200 = 1.05, not blend with the 283Hz point at all.
        let result = grid.partials(atFrequencyHz: 210)
        assertApproximatelyEqual(result.map(\.frequencyHz), [210, 420], accuracy: 1e-9)
        XCTAssertEqual(result.map(\.amplitude), [1, 0.5]) // amplitude is untouched by the scale
    }

    func testPartialsPicksTheMiddlePointWhenClosestInLogFrequencySpace() {
        let grid = syntheticGrid()
        // Nearest-point selection is log-frequency-based (pitch perception, and this grid's own
        // even semitone spacing, are both logarithmic) — 320 sits closer to 283 than to 400 in
        // that space (the log-midpoint between them is ~336.5, well above 320), even though it's
        // also well clear of the 200Hz point.
        let result = grid.partials(atFrequencyHz: 320)
        let scaleFromMiddlePoint = 320.0 / 283.0
        assertApproximatelyEqual(result.map(\.frequencyHz), [283 * scaleFromMiddlePoint, 566 * scaleFromMiddlePoint], accuracy: 1e-6)
    }
}
