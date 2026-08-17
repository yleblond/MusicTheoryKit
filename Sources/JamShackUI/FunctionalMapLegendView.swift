import SwiftUI
import AppCore
import ScoreImport
import Localization

/// Always-visible color/role key for the "Exploration fonctionnelle" panel — per the original
/// spec's own explicit requirement that color never be the sole way to recognize a role (each
/// chip carries a text label too, not just a colored dot). The fuller explanation used to live
/// behind this view's own "?" popover, then in a combined `TheoryLegendContent`; both are gone
/// now (2026-08-16) in favor of the app-wide `HelpTopicID.theorieExploration` content (see
/// `HelpTopicID.swift`, App target), rendered through the shared `HelpContentView`.
public struct FunctionalMapLegendView: View {
    public let language: AppLanguage
    /// `.horizontal` (the original, still used wherever there's a full-width row to spare) or
    /// `.vertical` (one role per line) — added so a narrow column (e.g. under the progression
    /// preview) can show the same legend without it running off the side, per explicit request.
    public var axis: Axis

    public init(language: AppLanguage, axis: Axis = .horizontal) {
        self.language = language
        self.axis = axis
    }

    private var roles: [(ModalFunctionalRoleForLegend)] {
        [.home, .away, .tension, .neutral]
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
        ForEach(roles, id: \.self) { role in
            HStack(spacing: 4) {
                Circle().fill(role.color).frame(width: 10, height: 10)
                Text(role.label(language: language)).font(.caption)
            }
        }
        HStack(spacing: 4) {
            Image(systemName: "diamond.fill")
                .foregroundStyle(Color(hex: "#8e24aa"))
                .font(.system(size: 9))
            Text(L10n.string(.appLabelCaracteristiqueModale, language)).font(.caption)
        }
    }
}

/// A legend-only mirror of `ModalFunctionalRole` (from `AppCore`) — kept separate rather than
/// extending that type directly, since color/label are presentation concerns `AppCore`'s own
/// model has no business knowing about.
private enum ModalFunctionalRoleForLegend: Hashable {
    case home, away, tension, neutral

    var color: Color {
        switch self {
        case .home: return Color(hex: "#2e7d32")
        case .away: return Color(hex: "#f9a825")
        case .tension: return Color(hex: "#e64a19")
        case .neutral: return Color(hex: "#1565c0")
        }
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .home: return functionalRoleLabel(.home, language: language)
        case .away: return functionalRoleLabel(.away, language: language)
        case .tension: return functionalRoleLabel(.tension, language: language)
        case .neutral: return functionalRoleLabel(.neutral, language: language)
        }
    }
}
