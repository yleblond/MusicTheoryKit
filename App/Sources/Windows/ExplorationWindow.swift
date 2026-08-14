import SwiftUI
import AppCore

/// Detached-window counterpart of the "Exploration" tab (`ModeLibraryView(contentFocus:
/// .exploration)`, see `AuxiliaryWindowID.theorieExploration`) — mirrors `TheoryWindow` exactly.
struct ExplorationWindow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        SessionGatedView { session, _ in
            ModeLibraryView(session: session, contentFocus: .exploration, isDetachedWindow: true, usesSharedModeSelection: false)
        }
        .onAppear { appModel.markWindowOpen(.theorieExploration) }
        .onDisappear { appModel.markWindowClosed(.theorieExploration) }
    }
}
