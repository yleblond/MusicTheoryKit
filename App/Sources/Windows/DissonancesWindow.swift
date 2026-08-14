import SwiftUI
import AppCore

/// Detached-window counterpart of the "Dissonances" tab (`DissonancesLibraryView`, see
/// `AuxiliaryWindowID.theorieDissonances`) — mirrors `ChordWindow` exactly.
struct DissonancesWindow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        SessionGatedView { session, _ in
            DissonancesLibraryView(session: session, isActive: true, isDetachedWindow: true)
        }
        .onAppear { appModel.markWindowOpen(.theorieDissonances) }
        .onDisappear { appModel.markWindowClosed(.theorieDissonances) }
    }
}
