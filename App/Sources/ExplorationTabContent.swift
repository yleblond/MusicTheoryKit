import SwiftUI
import AppCore
import Localization

/// Wraps `ModeLibraryView(contentFocus: .exploration)` with the same detach-into-its-own-window
/// swap `TheoryTabContent`/`ChordTabContent` already do for their own screens.
struct ExplorationTabContent: View {
    let session: ImprovSession

    @Environment(AppModel.self) private var appModel
    #if os(macOS) || os(visionOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    var body: some View {
        #if os(macOS) || os(visionOS)
        if appModel.openAuxiliaryWindows.contains(.theorieExploration) {
            DetachedPlaceholderView(
                message: L10n.string(.appLabelOuvertDansFenetreSeparee, session.currentLanguage),
                language: session.currentLanguage,
                onReintegrate: { dismissWindow(id: AuxiliaryWindowID.theorieExploration.rawValue) }
            )
        } else {
            ModeLibraryView(session: session, contentFocus: .exploration)
        }
        #else
        ModeLibraryView(session: session, contentFocus: .exploration)
        #endif
    }
}
