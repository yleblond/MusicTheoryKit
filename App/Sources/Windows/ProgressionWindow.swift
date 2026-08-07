import SwiftUI
import AppCore

/// Detached-window counterpart of the "Progressions" tab (`ProgressionLibraryView`, see
/// `AuxiliaryWindowID.theorieProgressions`) — mirrors `TheoryWindow` exactly.
struct ProgressionWindow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        SessionGatedView { session, _ in
            ProgressionLibraryView(session: session, isDetachedWindow: true)
        }
        .onAppear { appModel.markWindowOpen(.theorieProgressions) }
        .onDisappear { appModel.markWindowClosed(.theorieProgressions) }
    }
}
