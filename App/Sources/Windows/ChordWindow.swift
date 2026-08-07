import SwiftUI
import AppCore

/// Detached-window counterpart of the "Accords" tab (`ChordLibraryView`, see
/// `AuxiliaryWindowID.theorieAccords`) — mirrors `TheoryWindow` exactly.
struct ChordWindow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        SessionGatedView { session, _ in
            ChordLibraryView(session: session, isDetachedWindow: true)
        }
        .onAppear { appModel.markWindowOpen(.theorieAccords) }
        .onDisappear { appModel.markWindowClosed(.theorieAccords) }
    }
}
