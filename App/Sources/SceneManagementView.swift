import SwiftUI
import AppCore
import Localization

/// The "Scene" tab — split into two sub-tabs (same vertical icon-sidebar pattern as the
/// "JamShack" tab, for the same reason: keeps each screen focused instead of one long form):
/// **Fichier** (create/rename the scene, single-file export/import, the folder-based scene
/// browser — creating/loading a scene here switches to **Disposition**, per explicit user
/// request — see `SceneFileView`) and **Disposition** (instruments <-> roles, side by side —
/// see `SceneLayoutView`).
struct SceneManagementView: View {
    let session: ImprovSession

    private enum SubTab: CaseIterable, Identifiable {
        case file, layout

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .file: return "doc.text"
            case .layout: return "rectangle.split.2x1"
            }
        }

        func accessibilityLabel(_ language: AppLanguage) -> String {
            switch self {
            case .file: return L10n.string(.appTabFichierScene, language)
            case .layout: return L10n.string(.appTabDispositionScene, language)
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
                case .file: SceneFileView(session: session, onLoaded: { subTab = .layout })
                case .layout: SceneLayoutView(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    SceneManagementView(session: ImprovSession())
}
