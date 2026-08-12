import SwiftUI
import Localization

/// Compact swatch/glyph key for the Tonnetz's 3 edge directions and 2 triangle qualities — same
/// shape as `FunctionalMapLegendView`/`MelodicMapLegendView` (a narrow sidebar column, not a full
/// explanatory panel), added per explicit request once the dual-graph layout freed up space for
/// it. Edge-kind rows match `edgeColor(kind:)`'s own colors in `Tonnetz.swift` directly, so the
/// swatch is a real reference to what's on screen, not a redundant restatement of geometry.
/// Triangle-quality rows use a shape glyph (apex-up/apex-down), not color, since `colorByIdentity`
/// already ties triangle fill hue to the chord's root, not its quality.
public struct TonnetzLegendView: View {
    public let language: AppLanguage
    public var axis: Axis

    public init(language: AppLanguage, axis: Axis = .horizontal) {
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
        HStack(spacing: 4) {
            Rectangle().fill(Color.blue).frame(width: 14, height: 2)
            Text(L10n.string(.appTonnetzLegendFifth, language)).font(.caption)
        }
        HStack(spacing: 4) {
            Rectangle().fill(Color.green).frame(width: 14, height: 2).rotationEffect(.degrees(-30))
            Text(L10n.string(.appTonnetzLegendMajorThird, language)).font(.caption)
        }
        HStack(spacing: 4) {
            Rectangle().fill(Color.orange).frame(width: 14, height: 2).rotationEffect(.degrees(30))
            Text(L10n.string(.appTonnetzLegendMinorThird, language)).font(.caption)
        }
        HStack(spacing: 4) {
            Image(systemName: "triangle.fill").font(.system(size: 10)).foregroundStyle(.secondary)
            Text(L10n.string(.appTonnetzLegendMajorTriad, language)).font(.caption)
        }
        HStack(spacing: 4) {
            Image(systemName: "triangle.fill").rotationEffect(.degrees(180)).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(L10n.string(.appTonnetzLegendMinorTriad, language)).font(.caption)
        }
    }
}
