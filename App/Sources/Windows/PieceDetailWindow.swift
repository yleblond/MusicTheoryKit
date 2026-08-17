import SwiftUI
import AppCore

/// Detached-window counterpart of the Morceaux tab's detail screen (`PieceDetailView`, see
/// `AuxiliaryWindowID.compositionPieceDetail`) — mirrors `TonnetzWindow` exactly.
struct PieceDetailWindow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        SessionGatedView { session, _ in
            PieceDetailView(session: session, onBackToCatalog: {}, isDetachedWindow: true)
        }
        .onAppear { appModel.markWindowOpen(.compositionPieceDetail) }
        .onDisappear { appModel.markWindowClosed(.compositionPieceDetail) }
    }
}
