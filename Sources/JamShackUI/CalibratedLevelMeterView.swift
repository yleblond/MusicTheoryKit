import SwiftUI

/// A small horizontal level meter with the calibrated quiet/loud RMS levels drawn as tick
/// marks, so a glance shows not just "how loud right now" but "where that sits relative to
/// calibration" — under/between/over the two reference points. A plain `ProgressView` can't
/// show this: it only ever fills 0...1 of its own track, and since the app's existing
/// `normalized(_:)` maps the calibrated range itself onto 0...1, the quiet/loud marks would
/// trivially sit at the two ends of the bar every time — never informative. This view instead
/// picks a FIXED scale (a margin above the loud reference, same "stable, not per-frame-relative
/// scale" philosophy as `SpectrumView`'s own y-axis) so the marks land somewhere meaningful
/// inside the track instead of always at its edges.
public struct CalibratedLevelMeterView: View {
    public let rawLevel: Float
    public let quietRMS: Float
    public let loudRMS: Float

    public init(rawLevel: Float, quietRMS: Float, loudRMS: Float) {
        self.rawLevel = rawLevel
        self.quietRMS = quietRMS
        self.loudRMS = loudRMS
    }

    /// 130% of the loud reference (or of the current level/quiet reference, if either happens
    /// to exceed that) — a fixed ceiling so the bar doesn't re-stretch every frame the way an
    /// auto-normalized one would.
    private var scaleMax: Float {
        max(loudRMS * 1.3, rawLevel, quietRMS * 1.3, 0.0001)
    }

    public var body: some View {
        let scaleMax = self.scaleMax
        return Canvas { context, size in
            let corner = size.height / 2
            context.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: corner),
                with: .color(.gray.opacity(0.25))
            )
            let levelWidth = CGFloat(min(1, max(0, rawLevel / scaleMax))) * size.width
            if levelWidth > 0 {
                context.fill(
                    Path(roundedRect: CGRect(x: 0, y: 0, width: levelWidth, height: size.height), cornerRadius: corner),
                    with: .color(.accentColor)
                )
            }
            func tick(_ value: Float, color: Color) {
                guard value > 0 else { return }
                let x = CGFloat(min(1, max(0, value / scaleMax))) * size.width
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2))
            }
            // Same yellow/orange convention `SpectrumView.drawCalibrationThresholds` already
            // uses for quiet/loud, so the two views read consistently.
            tick(quietRMS, color: .yellow)
            tick(loudRMS, color: .orange)
        }
        .frame(height: 14)
    }
}

#Preview {
    VStack(spacing: 12) {
        CalibratedLevelMeterView(rawLevel: 0.02, quietRMS: 0.01, loudRMS: 0.2)
        CalibratedLevelMeterView(rawLevel: 0.15, quietRMS: 0.01, loudRMS: 0.2)
        CalibratedLevelMeterView(rawLevel: 0.28, quietRMS: 0.01, loudRMS: 0.2)
    }
    .padding()
}
