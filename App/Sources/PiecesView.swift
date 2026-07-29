import SwiftUI
import AppCore
import Localization

/// The "Morceaux" tab — a sequential list → play flow, mirroring `SceneManagementView`, but
/// ALWAYS opening on the list (unlike Scene/Composition, an empty piece store does not jump
/// straight to a "creation" screen — Morceaux has no such notion): **Fichier**
/// (`PiecesFileView`, loaded piece info, demo, store browser — loading a piece here switches to
/// **Play**) leads into **Play** (`PiecesPlayView`, play/stop the loaded piece, choose its sound).
struct PiecesView: View {
    let session: ImprovSession

    private enum Screen { case list, play }

    @State private var screen: Screen = .list

    var body: some View {
        Group {
            switch screen {
            case .list:
                PiecesFileView(session: session, onLoaded: { screen = .play })
            case .play:
                PiecesPlayView(session: session, onBackToList: { screen = .list })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    PiecesView(session: ImprovSession())
}
