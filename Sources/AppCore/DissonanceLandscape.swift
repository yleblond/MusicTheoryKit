import Foundation

/// Shared raw-data computation for the "Dissonances" screen's rendering modes (2D heatmap, 3D
/// surface) — one triad-above-a-fixed-root sensory-dissonance evaluation per grid cell
/// (`SensoryDissonance.totalDissonance`), computed once per `(grid, resolution)` pair since it's
/// too expensive to repeat every redraw/rotation. Factored out of `DissonanceHeatmapView` so a
/// second rendering mode can reuse the exact same numbers rather than recomputing (and risking
/// drift) on its own.
public enum DissonanceLandscape {
    /// `resolution` real-valued dissonance evaluations per axis, `[row(y)][col(x)]`, x/y both
    /// spanning `[1, 2]` (root ratio 1 through the octave-up ratio 2) — NOT yet normalized.
    /// `smoothingSigma` (0 = disabled, the default) applies a purely GRAPHICAL Gaussian blur
    /// across cells afterward — this never touches `OctaveSpectrumGrid`/the crossfade that feeds
    /// it, it only softens how the already-computed landscape is displayed. Exists because denser
    /// captures (see `OctaveSpectrumGrid.partials(atFrequencyHz:)`) narrow the crossfade window
    /// between real captured points, which lets real inter-capture variation (and analysis noise)
    /// show through as visible texture — this is an independent, optional knob for anyone who
    /// wants a smoother PICTURE without changing the underlying data/density.
    public static func rawValues(grid: OctaveSpectrumGrid, resolution: Int, smoothingSigma: Double = 0) -> [[Double]] {
        guard resolution > 1, let rootHz = grid.points.first?.frequencyHz else { return [] }
        let rootPartials = grid.partials(atFrequencyHz: rootHz)
        var raw = [[Double]](repeating: [Double](repeating: 0, count: resolution), count: resolution)
        for row in 0..<resolution {
            let yRatio = 1.0 + Double(row) / Double(resolution - 1)
            let tone3 = grid.partials(atFrequencyHz: rootHz * yRatio)
            for col in 0..<resolution {
                let xRatio = 1.0 + Double(col) / Double(resolution - 1)
                let tone2 = grid.partials(atFrequencyHz: rootHz * xRatio)
                raw[row][col] = SensoryDissonance.totalDissonance(ofTones: [rootPartials, tone2, tone3])
            }
        }
        return gaussianBlurred(raw, sigma: smoothingSigma)
    }

    /// `rawValues` rescaled to `[0, 1]` — the min/max-normalized form every rendering mode
    /// actually colors/heights by. Blurring (see `rawValues`) commutes with this min/max rescale
    /// (both are linear/affine), so smoothing before or after normalizing gives the same result —
    /// done inside `rawValues` so callers of either function see consistent, already-smoothed
    /// numbers.
    public static func normalizedValues(grid: OctaveSpectrumGrid, resolution: Int, smoothingSigma: Double = 0) -> [[Double]] {
        let raw = rawValues(grid: grid, resolution: resolution, smoothingSigma: smoothingSigma)
        guard !raw.isEmpty else { return raw }
        let minValue = raw.compactMap { $0.min() }.min() ?? 0
        let maxValue = raw.compactMap { $0.max() }.max() ?? 0
        let range = max(maxValue - minValue, 1e-12)
        return raw.map { rowValues in rowValues.map { ($0 - minValue) / range } }
    }

    /// Separable Gaussian blur (horizontal pass, then vertical) over a 2D grid, clamping at the
    /// edges (repeats the border value rather than darkening/fading toward an implicit zero) —
    /// `sigma <= 0` is a no-op, returned unchanged, so passing the default never allocates or
    /// walks the grid a second time. Internal rather than `private` so `DissonanceLandscapeTests`
    /// can exercise the blur mechanics directly against hand-built inputs, independent of
    /// `SensoryDissonance`'s own numbers.
    static func gaussianBlurred(_ values: [[Double]], sigma: Double) -> [[Double]] {
        guard sigma > 0, let firstRow = values.first, !firstRow.isEmpty else { return values }
        let radius = max(1, Int((sigma * 3).rounded(.up)))
        let offsets = Array(-radius...radius)
        let weights: [Double] = {
            let raw = offsets.map { exp(-(Double($0) * Double($0)) / (2 * sigma * sigma)) }
            let sum = raw.reduce(0, +)
            return raw.map { $0 / sum }
        }()

        let rows = values.count, cols = firstRow.count
        var horizontallyBlurred = values
        for r in 0..<rows {
            for c in 0..<cols {
                var sum = 0.0
                for (offset, weight) in zip(offsets, weights) {
                    let cc = max(0, min(cols - 1, c + offset))
                    sum += values[r][cc] * weight
                }
                horizontallyBlurred[r][c] = sum
            }
        }
        var result = horizontallyBlurred
        for c in 0..<cols {
            for r in 0..<rows {
                var sum = 0.0
                for (offset, weight) in zip(offsets, weights) {
                    let rr = max(0, min(rows - 1, r + offset))
                    sum += horizontallyBlurred[rr][c] * weight
                }
                result[r][c] = sum
            }
        }
        return result
    }
}
