import SwiftUI
import AppCore

/// Detached-window counterpart of the "Tonnetz" tab (`TonnetzLibraryView`, see
/// `AuxiliaryWindowID.theorieTonnetz`) — mirrors `ChordWindow` exactly.
struct TonnetzWindow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        SessionGatedView { session, _ in
            TonnetzLibraryView(session: session, isDetachedWindow: true)
        }
        .onAppear { appModel.markWindowOpen(.theorieTonnetz) }
        .onDisappear { appModel.markWindowClosed(.theorieTonnetz) }
    }
}
