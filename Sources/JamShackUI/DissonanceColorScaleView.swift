import SwiftUI

/// A vertical color-bar legend for `DissonanceColorRamp` — shared between the 2D heatmap and the
/// 3D surface (same ramp, same 0...1 normalized meaning either way), per explicit request.
public struct DissonanceColorScaleView: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 6) {
            LinearGradient(gradient: Gradient(stops: Self.gradientStops), startPoint: .bottom, endPoint: .top)
                .frame(width: 16)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            VStack {
                Text("1.0").font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Text("0.5").font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Text("0.0").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }

    /// Sampled every 0.05 rather than reusing `DissonanceColorRamp`'s own coarser stops directly
    /// — `LinearGradient` interpolates linearly IN RGB BETWEEN stops same as `DissonanceColorRamp`
    /// itself does, so this many samples keeps the bar visually identical to it without exposing
    /// the ramp's internal stop list.
    private static var gradientStops: [Gradient.Stop] {
        stride(from: 0.0, through: 1.0, by: 0.05).map { Gradient.Stop(color: DissonanceColorRamp.color(forNormalized: $0), location: $0) }
    }
}
