import SwiftUI
import AppCore
import JamShackUI
import Localization

/// The "Guide" tab — a sequential list → configuration flow, not a permanently-visible sidebar:
/// **Fichier** (`GuideFileView`, the store-based guide list — activating or creating a guide is
/// the only way to reach the next screen) leads into **Configuration** (`GuideConfigurationView`,
/// the active guide's name plus an Edition/Lecture mode toggle). Landing screen at launch is
/// decided by `ImprovSession.ensureGuideReadyForLaunch()` (called once in `DefaultFolders.swift`):
/// with no saved guides, it starts a fresh anonymous one and this view opens straight on
/// Configuration; with any saved, `currentGuide` is left nil and this view opens on the list
/// instead — picking one (even the only one) is always an explicit step. Mirrors
/// `SceneManagementView`.
struct GuideView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    private enum Screen { case list, configuration }

    @State private var screen: Screen

    @Environment(AppModel.self) private var appModel

    init(session: ImprovSession, bridge: SessionUIBridge) {
        self.session = session
        self.bridge = bridge
        _screen = State(initialValue: session.guideSequenceNames.isEmpty ? .configuration : .list)
    }

    var body: some View {
        Group {
            switch screen {
            case .list:
                GuideFileView(session: session, onLoaded: { screen = .configuration })
            case .configuration:
                GuideConfigurationView(session: session, bridge: bridge, onBackToList: { screen = .list })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // "Éditer le guide" from Studio's own Guide-play tab (`StudioGuidePlayTabContent`) lands
        // here — jump straight to Configuration (a guide is already active, since we were just
        // playing it) instead of making the user re-pick it from the list, per explicit request.
        .onChange(of: appModel.guideNavigationRequestToken) { _, _ in
            guard appModel.guideNavigationRequest == .editInComposition else { return }
            screen = .configuration
        }
    }
}

#Preview {
    let session = ImprovSession()
    return GuideView(session: session, bridge: SessionUIBridge(session: session))
        .environment(AppModel())
}
