import SwiftUI
import Localization

/// Compact swatch/label key for the score view's role-coloring — same shape as
/// `TonnetzLegendView`/`FunctionalMapLegendView` (a narrow column, not a full explanatory panel).
/// Colors match `ScoreEngravingAdapter.color(forPitch:atTick:in:)`'s own hex values exactly
/// (softened ~35% toward white per user feedback that the original saturated values were tiring
/// to read — keep both in sync), so the swatch is a real reference to what's on screen, not a
/// redundant restatement.
public struct ScoreColorLegendView: View {
    public let language: AppLanguage
    public var axis: Axis

    public init(language: AppLanguage, axis: Axis = .vertical) {
        self.language = language
        self.axis = axis
    }

    public var body: some View {
        Group {
            if axis == .horizontal {
                HStack(spacing: 12) { legendRows }
            } else {
                VStack(alignment: .leading, spacing: 6) { legendRows }
            }
        }
    }

    @ViewBuilder
    private var legendRows: some View {
        row(hex: "#f16d9a", label: L10n.string(.appScoreLegendChordRoot, language))
        row(hex: "#fee67c", label: L10n.string(.appScoreLegendChordTone, language))
        row(hex: "#ffbc59", label: L10n.string(.appScoreLegendModeRoot, language))
        row(hex: "#59d3e3", label: L10n.string(.appScoreLegendModeTone, language))
    }

    private func row(hex: String, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(Color(hex: hex)).frame(width: 10, height: 10)
            Text(label).font(.caption)
        }
    }
}

#Preview {
    ScoreColorLegendView(language: .fr)
        .padding()
}
