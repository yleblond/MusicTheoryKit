import Foundation

/// The color ramps `SpectrogramColorScale.color(_:palette:)` can render intensity through —
/// user-selectable per explicit request, echoing the couple of variants (a warm "thermal" one,
/// a cool blue one, a plain grayscale one) shown in reference screenshots of another
/// spectrogram tool.
public enum SpectrogramPalette: String, CaseIterable, Identifiable, Sendable {
    case thermal, blue, grayscale
    public var id: Self { self }
}

/// The intensity/color math shared by `SpectrogramView`'s waterfall and
/// `SpectrogramColorScaleView`'s legend — factored out so the two can never drift apart (the
/// whole point of a legend is that its colors mean exactly what the graph's colors mean).
public enum SpectrogramColorScale {
    /// Same "stable, 120%-of-loud ceiling" scale `SpectrumView`'s y-axis already uses —
    /// `fallback` only matters when there's no calibration at all to anchor to.
    public static func peakForScale(calibrationLoudMagnitude: Float?, fallback: Float) -> Float {
        max(calibrationLoudMagnitude.map { $0 * 1.2 } ?? fallback, 1)
    }

    /// Log-scaled, clamped to [0, 1] — a linear scale makes anything but the single loudest
    /// value invisible, since real spectrum energy spans several orders of magnitude.
    public static func intensity(for magnitude: Float, peakForScale: Float) -> Double {
        let ratio = log10(1 + Double(magnitude)) / log10(1 + Double(peakForScale))
        return min(max(ratio, 0), 1)
    }

    private static func stops(for palette: SpectrogramPalette) -> [(Double, (Double, Double, Double))] {
        switch palette {
        case .thermal:
            // Dark-to-bright thermal ramp (black -> purple -> red -> orange -> yellow -> pale)
            // — reads clearly against this app's dark theme and keeps quiet regions genuinely
            // dark instead of a mid-tone color, so loud transients still pop visually.
            return [
                (0.0, (0, 0, 0)),
                (0.15, (24, 0, 42)),
                (0.35, (92, 0, 84)),
                (0.55, (182, 22, 42)),
                (0.75, (230, 102, 18)),
                (0.9, (250, 200, 60)),
                (1.0, (255, 250, 224)),
            ]
        case .blue:
            return [
                (0.0, (0, 0, 0)),
                (0.2, (6, 10, 46)),
                (0.45, (16, 40, 120)),
                (0.7, (30, 110, 210)),
                (0.88, (100, 200, 245)),
                (1.0, (225, 250, 255)),
            ]
        case .grayscale:
            return [
                (0.0, (0, 0, 0)),
                (1.0, (255, 255, 255)),
            ]
        }
    }

    public static func color(_ intensity: Double, palette: SpectrogramPalette = .thermal) -> (UInt8, UInt8, UInt8) {
        let stops = stops(for: palette)
        var lower = stops[0], upper = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) where intensity >= stops[i].0 && intensity <= stops[i + 1].0 {
            lower = stops[i]
            upper = stops[i + 1]
            break
        }
        let span = upper.0 - lower.0
        let t = span > 0 ? (intensity - lower.0) / span : 0
        func mix(_ a: Double, _ b: Double) -> UInt8 { UInt8(max(0, min(255, a + (b - a) * t))) }
        return (mix(lower.1.0, upper.1.0), mix(lower.1.1, upper.1.1), mix(lower.1.2, upper.1.2))
    }
}
