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

    func testPartialsBelowTheGridsLowestPointScalesThatPointAlone() {
        let grid = syntheticGrid()
        let result = grid.partials(atFrequencyHz: 180) // below the 200Hz first point — no lower neighbor to fade toward
        assertApproximatelyEqual(result.map(\.frequencyHz), [180, 360], accuracy: 1e-9)
        XCTAssertEqual(result.map(\.amplitude), [1, 0.5]) // amplitude is untouched by the scale
    }

    func testPartialsAboveTheGridsHighestPointScalesThatPointAlone() {
        let grid = syntheticGrid()
        let result = grid.partials(atFrequencyHz: 420) // above the 400Hz last point — no higher neighbor to fade toward
        assertApproximatelyEqual(result.map(\.frequencyHz), [420, 840], accuracy: 1e-9)
        XCTAssertEqual(result.map(\.amplitude), [1, 0.3])
    }

    func testPartialsBetweenTwoPointsCrossfadesBothScaledToTheSameTargetFrequency() {
        let grid = syntheticGrid()
        // 210 sits close to the 200Hz point but still bracketed by the 283Hz one — both
        // contribute, each scaled to 210Hz first, weighted by log-frequency proximity.
        let result = grid.partials(atFrequencyHz: 210)
        let t = log(210.0 / 200.0) / log(283.0 / 200.0)
        let lowRatio = 210.0 / 200.0
        let highRatio = 210.0 / 283.0
        assertApproximatelyEqual(result.map(\.frequencyHz), [200 * lowRatio, 400 * lowRatio, 283 * highRatio, 566 * highRatio], accuracy: 1e-6)
        assertApproximatelyEqual(result.map(\.amplitude), [1 * (1 - t), 0.5 * (1 - t), 1 * t, 0.4 * t], accuracy: 1e-9)
    }

    func testPartialsExactlyMidwayInLogFrequencySpaceBlendsBothPointsEqually() {
        let grid = syntheticGrid()
        let midpointHz = (200.0 * 283.0).squareRoot() // geometric mean = exact log-space midpoint
        let result = grid.partials(atFrequencyHz: midpointHz)
        assertApproximatelyEqual(result.map(\.amplitude), [0.5, 0.25, 0.5, 0.2], accuracy: 1e-9)
    }

    func testPartialsFartherFromTheMiddlePointStillBlendsWithTheHighEndpoint() {
        let grid = syntheticGrid()
        // 320 is bracketed by the 283Hz and 400Hz points (still inside the grid, past the
        // midpoint) — both contribute, weighted by log-frequency proximity.
        let result = grid.partials(atFrequencyHz: 320)
        let t = log(320.0 / 283.0) / log(400.0 / 283.0)
        let lowRatio = 320.0 / 283.0
        let highRatio = 320.0 / 400.0
        assertApproximatelyEqual(result.map(\.frequencyHz), [283 * lowRatio, 566 * lowRatio, 400 * highRatio, 800 * highRatio], accuracy: 1e-6)
        assertApproximatelyEqual(result.map(\.amplitude), [1 * (1 - t), 0.4 * (1 - t), 1 * t, 0.3 * t], accuracy: 1e-9)
    }

    // MARK: - capturedPartials fallback (a captured point must never end up with ZERO partials
    // for a genuinely non-silent render — see the function's own doc comment)

    private static let sampleRate = 44100.0

    private func sineWindow(frequencyHz: Double, analyzer: FFTPitchAnalyzer) -> [Float] {
        (0..<analyzer.size).map { n in Float(sin(2 * Double.pi * frequencyHz * Double(n) / Self.sampleRate)) }
    }

    /// Deterministic white noise (a fixed xorshift64 PRNG, not `Double.random`, so the test is
    /// reproducible) — a genuinely flat expected spectrum, no single bin standing out 8x above
    /// the band average (`FFTPitchAnalyzer`'s own `candidatePeaks` gate), so `dominantPartials`
    /// itself returns nothing even though the signal is clearly non-silent.
    private func flatSpectrumWindow(analyzer: FFTPitchAnalyzer) -> [Float] {
        var state: UInt64 = 88172645463325252
        func nextNoise() -> Float {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Float(Int64(bitPattern: state) % 2000 - 1000) / 1000
        }
        return (0..<analyzer.size).map { _ in nextNoise() }
    }

    func testCapturedPartialsFallsBackToTheLoudestBinWhenDominantPartialsFindsNothing() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let window = flatSpectrumWindow(analyzer: analyzer)
        XCTAssertTrue(analyzer.dominantPartials(in: window, sampleRate: Self.sampleRate).isEmpty, "test setup: expected the strict gate to reject a flat spectrum")

        let partials = OctaveSpectrumGridBuilder.capturedPartials(fromWindow: window, analyzer: analyzer, sampleRate: Self.sampleRate)
        XCTAssertEqual(partials.count, 1)
        XCTAssertGreaterThan(partials.first?.amplitude ?? 0, 0)
    }

    func testCapturedPartialsReturnsEmptyForGenuineSilence() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let silence = [Float](repeating: 0, count: analyzer.size)
        XCTAssertTrue(OctaveSpectrumGridBuilder.capturedPartials(fromWindow: silence, analyzer: analyzer, sampleRate: Self.sampleRate).isEmpty)
    }

    func testCapturedPartialsMatchesDominantPartialsWhenItFindsSomething() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let window = sineWindow(frequencyHz: 440, analyzer: analyzer)
        let direct = analyzer.dominantPartials(in: window, sampleRate: Self.sampleRate)
        XCTAssertFalse(direct.isEmpty, "test setup: expected a clean sine tone to produce a clear dominant partial")

        let viaCapturedPartials = OctaveSpectrumGridBuilder.capturedPartials(fromWindow: window, analyzer: analyzer, sampleRate: Self.sampleRate)
        XCTAssertEqual(viaCapturedPartials.count, direct.count)
        assertApproximatelyEqual(viaCapturedPartials.map(\.frequencyHz), direct.map(\.frequencyHz), accuracy: 1e-6)
    }
}
