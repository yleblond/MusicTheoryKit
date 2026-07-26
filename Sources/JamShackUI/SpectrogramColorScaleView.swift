import SwiftUI

/// A vertical companion to `SpectrogramView`: a color legend (bottom = quiet/dark, top =
/// loud/bright, using the EXACT same gradient the waterfall itself is colored with — see
/// `SpectrogramColorScale`) doubling as a live level meter, with the calibrated quiet/loud
/// magnitudes marked as tick lines. Answers both "what does this color mean" and "where's the
/// current level relative to calibration" in one small widget, meant to sit right next to the
/// waterfall it's legending.
public struct SpectrogramColorScaleView: View {
    /// The current frame's peak magnitude — `nil` while not capturing (no live indicator drawn).
    public let currentPeakMagnitude: Float?
    public let calibrationQuietMagnitude: Float?
    public let calibrationLoudMagnitude: Float?
    public let palette: SpectrogramPalette

    public init(
        currentPeakMagnitude: Float?, calibrationQuietMagnitude: Float?, calibrationLoudMagnitude: Float?,
        palette: SpectrogramPalette = .thermal
    ) {
        self.currentPeakMagnitude = currentPeakMagnitude
        self.calibrationQuietMagnitude = calibrationQuietMagnitude
        self.calibrationLoudMagnitude = calibrationLoudMagnitude
        self.palette = palette
    }

    public var body: some View {
        let peakForScale = SpectrogramColorScale.peakForScale(calibrationLoudMagnitude: calibrationLoudMagnitude, fallback: currentPeakMagnitude ?? 1)
        return Canvas { context, size in
            let rows = max(1, Int(size.height))
            for row in 0..<rows {
                // row 0 is the TOP (highest intensity), matching the waterfall's own vertical
                // convention (loud at top).
                let intensity = 1 - Double(row) / Double(rows)
                let color = SpectrogramColorScale.color(intensity, palette: palette)
                context.fill(
                    Path(CGRect(x: 0, y: CGFloat(row), width: size.width, height: 1)),
                    with: .color(Color(red: Double(color.0) / 255, green: Double(color.1) / 255, blue: Double(color.2) / 255))
                )
            }
            func tick(_ magnitude: Float?, color: Color) {
                guard let magnitude, magnitude > 0 else { return }
                let intensity = SpectrogramColorScale.intensity(for: magnitude, peakForScale: peakForScale)
                let y = size.height - CGFloat(intensity) * size.height
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2))
            }
            // Same yellow/orange convention as `SpectrumView`/`CalibratedLevelMeterView`.
            tick(calibrationQuietMagnitude, color: .yellow)
            tick(calibrationLoudMagnitude, color: .orange)
            if let currentPeakMagnitude {
                let intensity = SpectrogramColorScale.intensity(for: currentPeakMagnitude, peakForScale: peakForScale)
                let y = size.height - CGFloat(intensity) * size.height
                var marker = Path()
                marker.move(to: CGPoint(x: 0, y: y))
                marker.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(marker, with: .color(.white), style: StrokeStyle(lineWidth: 2))
            }
        }
        .frame(width: 20)
    }
}

#Preview {
    HStack {
        SpectrogramColorScaleView(currentPeakMagnitude: 8000, calibrationQuietMagnitude: 2000, calibrationLoudMagnitude: 60000)
    }
    .frame(height: 280)
    .padding()
}
