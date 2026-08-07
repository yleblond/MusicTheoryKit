import SwiftUI
import AppCore
import Localization

/// Always-visible color/role key for the "Exploration fonctionnelle" panel — per the original
/// spec's own explicit requirement that color never be the sole way to recognize a role (each
/// chip carries a text label too, not just a colored dot). The fuller explanation used to live
/// behind this view's own "?" popover; it's now part of the single combined `TheoryLegendContent`
/// window/sheet (see that type's own doc comment) shared with `MelodicMapLegendView`, so there's
/// one place to look up either palette instead of two separate, easy-to-miss popovers.
public struct FunctionalMapLegendView: View {
    public let language: AppLanguage

    public init(language: AppLanguage) {
        self.language = language
    }

    private var roles: [(ModalFunctionalRoleForLegend)] {
        [.home, .away, .tension, .neutral]
    }

    public var body: some View {
        HStack(spacing: 12) {
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

/// Public so `TheoryLegendContent` can compose it into the combined legend window/sheet.
public struct FunctionalMapHelpContent: View {
    public let language: AppLanguage

    public init(language: AppLanguage) {
        self.language = language
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string(.appHelpFunctionalMapTitle, language)).font(.headline)
            Group {
                Text(L10n.string(.appHelpFunctionalMapHome, language))
                Text(L10n.string(.appHelpFunctionalMapAway, language))
                Text(L10n.string(.appHelpFunctionalMapTension, language))
                Text(L10n.string(.appHelpFunctionalMapNeutral, language))
                Text(L10n.string(.appHelpFunctionalMapModal, language))
            }
            .font(.callout)
            Divider()
            Text(L10n.string(.appHelpFunctionalMapDistance, language)).font(.callout)
            Text(L10n.string(.appHelpFunctionalMapArrows, language)).font(.callout)
            Divider()
            Text(L10n.string(.appHelpFunctionalMapImportant, language)).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 340, alignment: .leading)
    }
}
