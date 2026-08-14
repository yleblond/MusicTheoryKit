import SwiftUI
import AppCore

/// Detached-window counterpart of the "Intonations" tab (`TuningLibraryView`, see
/// `AuxiliaryWindowID.theorieIntonation`) — mirrors `ChordWindow` exactly.
struct IntonationWindow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        SessionGatedView { session, _ in
            TuningLibraryView(session: session, isActive: true, isDetachedWindow: true)
        }
        .onAppear { appModel.markWindowOpen(.theorieIntonation) }
        .onDisappear { appModel.markWindowClosed(.theorieIntonation) }
    }
}
