import SwiftUI
import AppCore
import Localization

/// The "Morceaux" tab — a sequential catalog → detail flow, mirroring `SceneManagementView`,
/// but ALWAYS opening on the catalog (unlike Scene/Composition, an empty piece store does not
/// jump straight to a "creation" screen — Morceaux has no such notion): **Catalogue**
/// (`PiecesFileView`, import + the saved-piece list — loading a piece here switches to
/// **Détail**) leads into **Détail** (`PieceDetailView`: name/play button, file-info/per-track
/// sound and notation-with-live-highlight tabs) — same detach-into-its-own-window swap the
/// Théorie tabs already do for their own screens (`TonnetzTabContent`'s own doc comment).
struct PiecesView: View {
    let session: ImprovSession

    private enum Screen { case catalog, detail }

    @State private var screen: Screen = .catalog

    @Environment(AppModel.self) private var appModel
    #if os(macOS) || os(visionOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    var body: some View {
        Group {
            switch screen {
            case .catalog:
                PiecesFileView(session: session, onLoaded: { screen = .detail })
            case .detail:
                #if os(macOS) || os(visionOS)
                if appModel.openAuxiliaryWindows.contains(.compositionPieceDetail) {
                    DetachedPlaceholderView(
                        message: L10n.string(.appLabelOuvertDansFenetreSeparee, session.currentLanguage),
                        language: session.currentLanguage,
                        onReintegrate: { dismissWindow(id: AuxiliaryWindowID.compositionPieceDetail.rawValue) }
                    )
                } else {
                    PieceDetailView(session: session, onBackToCatalog: { screen = .catalog })
                }
                #else
                PieceDetailView(session: session, onBackToCatalog: { screen = .catalog })
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
