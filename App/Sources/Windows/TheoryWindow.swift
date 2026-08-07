import SwiftUI
import AppCore

/// Detached-window counterpart of the "Théorie" tab (`TheoryView`, see
/// `AuxiliaryWindowID.theorie`) — mirrors `MicrophoneWindow`/`SceneLayoutWindow` exactly.
struct TheoryWindow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        SessionGatedView { session, _ in
            TheoryView(session: session, isDetachedWindow: true)
        }
        .onAppear { appModel.markWindowOpen(.theorie) }
        .onDisappear { appModel.markWindowClosed(.theorie) }
    }
}
