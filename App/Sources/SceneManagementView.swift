import SwiftUI
import AppCore
import Localization

/// The "Scene" tab — split into two sub-tabs (same vertical icon-sidebar pattern as the
/// "JamShack" tab, for the same reason: keeps each screen focused instead of one long form):
/// **Fichier** (per-scene rename/export/delete, the store-based scene list, single-file import —
/// activating/creating a scene here switches to **Disposition**, per explicit user request — see
/// `SceneFileView`) and **Disposition** (instruments <-> roles, side by side, plus the active
/// scene's name — see `SceneLayoutView`). Defaults to **Disposition**: `ImprovSession.
/// ensureSceneReadyForLaunch()` (called once at app startup, see `DefaultFolders.swift`)
/// guarantees a scene is already active unless several are saved and none has been picked yet,
/// in which case Disposition's own `ActivateOrCreateBlock` IS the pick-or-create screen — no
/// separate "no active scene" dead end anywhere in this tab anymore. The sidebar's "+" button
/// creates a brand-new (anonymous, unsaved) scene from anywhere in this tab, persisting the
/// outgoing one first if it was already named.
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

    @State private var subTab: SubTab = .layout
    @State private var actionError: String?

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
                Divider().padding(.vertical, 4)
                Button {
                    do {
                        try session.createNewScene()
                        subTab = .layout
                    } catch {
                        actionError = "\(error)"
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string(.appNouvelleScene, session.currentLanguage))
                if let actionError {
                    Text(actionError).font(.caption2).foregroundStyle(.red).frame(width: 44)
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
