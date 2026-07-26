import SwiftUI
import AppCore
import Localization

/// The "Composition" tab — split into two sub-tabs: **Fichier** (composition-description
/// folder — see `CompositionFileView`) and **Composer** (title/style/description + the
/// compose action — see `CompositionComposerView`).
struct CompositionView: View {
    let session: ImprovSession

    private enum SubTab: CaseIterable, Identifiable {
        case file, composer

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .file: return "doc.text"
            case .composer: return "wand.and.stars"
            }
        }

        func accessibilityLabel(_ language: AppLanguage) -> String {
            switch self {
            case .file: return L10n.string(.appTabFichierComposition, language)
            case .composer: return L10n.string(.appTabComposerCourt, language)
            }
        }
    }

    @State private var subTab: SubTab = .file

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                ForEach(SubTab.allCases) { tab in
                    Button {
                        subTab = tab
                    } label: {
                        Image(systemName: tab.systemImage)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(
                                subTab == tab ? Color.accentColor.opacity(0.2) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.accessibilityLabel(session.currentLanguage))
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            Divider()
            Group {
                switch subTab {
                case .file: CompositionFileView(session: session)
                case .composer: CompositionComposerView(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    CompositionView(session: ImprovSession())
}
