import XCTest
@testable import AppCore

/// Only checks the WIRING between `OctaveSpectrumGrid.partials(atFrequencyHz:)` and
/// `SensoryDissonance.totalDissonance` (shape, finiteness, normalization bounds) — the
/// dissonance formula itself is already covered by `SensoryDissonanceTests`, and the
/// nearest/crossfade partial lookup by `OctaveSpectrumGridTests`.
final class DissonanceLandscapeTests: XCTestCase {
    private func syntheticGrid() -> OctaveSpectrumGrid {
        let key = OctaveSpectrumGridKey(soundFontPath: "/synthetic.sf2", preset: nil, baseMidiPitch: 60, samplesPerOctave: 2)
        let points = [
            OctaveSpectrumGrid.CapturedSpectrumPoint(semitoneOffset: 0, frequencyHz: 200, partials: [SpectralPartial(frequencyHz: 200, amplitude: 1), SpectralPartial(frequencyHz: 400, amplitude: 0.5)]),
            OctaveSpectrumGrid.CapturedSpectrumPoint(semitoneOffset: 6, frequencyHz: 283, partials: [SpectralPartial(frequencyHz: 283, amplitude: 1), SpectralPartial(frequencyHz: 566, amplitude: 0.4)]),
            OctaveSpectrumGrid.CapturedSpectrumPoint(semitoneOffset: 12, frequencyHz: 400, partials: [SpectralPartial(frequencyHz: 400, amplitude: 1), SpectralPartial(frequencyHz: 800, amplitude: 0.3)]),
        ]
        return OctaveSpectrumGrid(key: key, points: points)
    }

    private func emptyGrid() -> OctaveSpectrumGrid {
        OctaveSpectrumGrid(key: OctaveSpectrumGridKey(soundFontPath: "/empty.sf2", preset: nil, baseMidiPitch: 60, samplesPerOctave: 0), points: [])
    }

    func testRawValuesHasResolutionRowsAndColumns() {
        let raw = DissonanceLandscape.rawValues(grid: syntheticGrid(), resolution: 5)
        XCTAssertEqual(raw.count, 5)
        XCTAssertTrue(raw.allSatisfy { $0.count == 5 })
    }

    func testRawValuesAreAllFiniteAndNonNegative() {
        let raw = DissonanceLandscape.rawValues(grid: syntheticGrid(), resolution: 6)
        for row in raw {
            for value in row {
                XCTAssertTrue(value.isFinite)
                XCTAssertGreaterThanOrEqual(value, 0)
            }
        }
    }

    func testEmptyGridProducesNoValues() {
        XCTAssertEqual(DissonanceLandscape.rawValues(grid: emptyGrid(), resolution: 5).count, 0)
    }

    func testResolutionOfOneOrLessProducesNoValues() {
        let grid = syntheticGrid()
        XCTAssertEqual(DissonanceLandscape.rawValues(grid: grid, resolution: 1).count, 0)
        XCTAssertEqual(DissonanceLandscape.rawValues(grid: grid, resolution: 0).count, 0)
    }

    func testNormalizedValuesSpanExactlyZeroToOne() {
        let normalized = DissonanceLandscape.normalizedValues(grid: syntheticGrid(), resolution: 8)
        let flat = normalized.flatMap { $0 }
        XCTAssertEqual(flat.min()!, 0, accuracy: 1e-9)
        XCTAssertEqual(flat.max()!, 1, accuracy: 1e-9)
        XCTAssertTrue(flat.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testNormalizedValuesOfAnEmptyGridIsEmpty() {
        XCTAssertEqual(DissonanceLandscape.normalizedValues(grid: emptyGrid(), resolution: 5).count, 0)
    }

    // MARK: - Smoothing (graphical-only, independent of the underlying capture density)

    func testRawValuesWithZeroSigmaMatchesUnsmoothed() {
        let grid = syntheticGrid()
        XCTAssertEqual(DissonanceLandscape.rawValues(grid: grid, resolution: 8), DissonanceLandscape.rawValues(grid: grid, resolution: 8, smoothingSigma: 0))
    }

    func testRawValuesWithPositiveSigmaDiffersFromUnsmoothed() {
        let grid = syntheticGrid()
        XCTAssertNotEqual(DissonanceLandscape.rawValues(grid: grid, resolution: 8), DissonanceLandscape.rawValues(grid: grid, resolution: 8, smoothingSigma: 2))
    }

    func testGaussianBlurredWithZeroSigmaReturnsInputUnchanged() {
        let input = [[0.0, 10.0], [10.0, 0.0]]
        XCTAssertEqual(DissonanceLandscape.gaussianBlurred(input, sigma: 0), input)
    }

    func testGaussianBlurredSpreadsASharpSpikeIntoItsNeighbors() {
        var input = [[Double]](repeating: [Double](repeating: 0, count: 7), count: 7)
        input[3][3] = 100
        let blurred = DissonanceLandscape.gaussianBlurred(input, sigma: 1.0)
        XCTAssertLessThan(blurred[3][3], 100)
        XCTAssertGreaterThan(blurred[3][2], 0)
        XCTAssertGreaterThan(blurred[2][3], 0)
    }

    func testGaussianBlurredPreservesGridShape() {
        let input = [[Double]](repeating: [Double](repeating: 1, count: 4), count: 3)
        let blurred = DissonanceLandscape.gaussianBlurred(input, sigma: 1.5)
        XCTAssertEqual(blurred.count, 3)
        XCTAssertTrue(blurred.allSatisfy { $0.count == 4 })
    }

    func testGaussianBlurredOfAUniformGridIsUnchanged() {
        let input = [[Double]](repeating: [Double](repeating: 5, count: 5), count: 5)
        let blurred = DissonanceLandscape.gaussianBlurred(input, sigma: 2.0)
        for row in blurred {
            for value in row {
                XCTAssertEqual(value, 5, accuracy: 1e-9)
            }
        }
    }
}
