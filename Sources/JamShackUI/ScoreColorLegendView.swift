import SwiftUI
import ScoreImport
import Localization

/// Compact swatch/label key for the score view's role-coloring — same shape as
/// `TonnetzLegendView`/`FunctionalMapLegendView` (a narrow column, not a full explanatory panel).
/// Notes are colored by the CURRENT CHORD's functional role in its mode (home/away/tension/
/// neutral — same 4-color classification "Exploration fonctionnelle" already uses, see
/// `FunctionalRoleColors`/`functionalRoleLabel` in `FunctionalChordGraph.swift`), not a fixed
/// per-role hue table like before — so the legend shows the 4 role colors (reusing that exact
/// palette/labels, not redefining them) plus a caption explaining the darker/lighter convention,
/// rather than 4 fixed swatches. Keep in sync with `ScoreEngravingAdapter.color(forPitch:atTick:in:)`.
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
        ForEach(ModalFunctionalRole.allCases, id: \.self) { role in
            row(color: FunctionalRoleColors.fill(for: role), label: functionalRoleLabel(role, language: language))
        }
        Text(L10n.string(.appScoreLegendShadingExplanation, language))
            .font(.caption2).foregroundStyle(.secondary)
    }

    private func row(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption)
        }
    }
}

#Preview {
    ScoreColorLegendView(language: .fr)
        .padding()
}
