import SwiftUI
import AppCore

/// Detached-window counterpart of the "Accueil" tab (`StatusGraphView`, see
/// `AuxiliaryWindowID.home`) — mirrors `ChordWindow` exactly.
struct StatusWindow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        SessionGatedView { session, _ in
            StatusGraphView(session: session, isDetachedWindow: true)
        }
        .onAppear { appModel.markWindowOpen(.home) }
        .onDisappear { appModel.markWindowClosed(.home) }
    }
}
