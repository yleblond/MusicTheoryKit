import SwiftUI
import AppCore
import Localization

/// The "Scene" tab — a sequential list → configuration flow, not a permanently-visible sidebar:
/// **Fichier** (`SceneFileView`, the store-based scene list — activating or creating a scene is
/// the only way to reach the next screen) leads into **Configuration** (`SceneLayoutView`,
/// instruments <-> roles plus the active scene's name). Landing screen at launch is decided by
/// `ImprovSession.ensureSceneReadyForLaunch()` (called once in `DefaultFolders.swift`): with no
/// saved scenes, it starts a fresh anonymous one and this view opens straight on Configuration;
/// with any saved, `currentScene` is left nil and this view opens on the list instead — picking
/// one (even the only one) is always an explicit step.
struct SceneManagementView: View {
    let session: ImprovSession

    @Environment(AppModel.self) private var appModel
    #if os(macOS) || os(visionOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    private enum Screen { case list, configuration }

    @State private var screen: Screen

    init(session: ImprovSession) {
        self.session = session
        _screen = State(initialValue: session.sceneNames.isEmpty ? .configuration : .list)
    }

    var body: some View {
        Group {
            switch screen {
            case .list:
                SceneFileView(session: session, onLoaded: { screen = .configuration })
            case .configuration:
                #if os(macOS) || os(visionOS)
                if appModel.openAuxiliaryWindows.contains(.sceneLayout) {
                    DetachedPlaceholderView(
                        message: L10n.string(.appLabelOuvertDansFenetreSeparee, session.currentLanguage),
                        language: session.currentLanguage,
                        onReintegrate: { dismissWindow(id: AuxiliaryWindowID.sceneLayout.rawValue) }
                    )
                } else {
                    SceneLayoutView(session: session, onBackToList: { screen = .list })
                }
                #else
                SceneLayoutView(session: session, onBackToList: { screen = .list })
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SceneManagementView(session: ImprovSession())
}
