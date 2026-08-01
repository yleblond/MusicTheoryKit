import SwiftUI
import AppCore

/// Detached-window counterpart of Scene > Configuration (`SceneLayoutView`, see
/// `AuxiliaryWindowID.sceneLayout`). `onBackToList` is a true no-op here — there's no "Fichier"
/// list screen in a standalone window, same reasoning as `GuideLectureWindow`'s `onGuideStopped`.
struct SceneLayoutWindow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        SessionGatedView { session, _ in
            SceneLayoutView(session: session, onBackToList: {}, isDetachedWindow: true)
        }
        .onAppear { appModel.markWindowOpen(.sceneLayout) }
        .onDisappear { appModel.markWindowClosed(.sceneLayout) }
    }
}
