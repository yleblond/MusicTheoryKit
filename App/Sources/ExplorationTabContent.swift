import SwiftUI
import AppCore
import Localization

/// Wraps `ModeLibraryView(contentFocus: .exploration)` with the same detach-into-its-own-window
/// swap `TheoryTabContent`/`ChordTabContent` already do for their own screens.
struct ExplorationTabContent: View {
    let session: ImprovSession
    /// Whether THIS tab is the one currently on screen in `ContentView` — Théorie tab content
    /// stays mounted across tab switches (see `SoundsView.isActive`'s own doc comment), so
    /// `ModeLibraryView` needs this passed through explicitly to know when to register/clear its
    /// own contextual help (`View.registerContextualHelp`) rather than relying on
    /// `.onAppear`/`.onDisappear`.
    let isActive: Bool

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
            ModeLibraryView(session: session, contentFocus: .exploration, isActive: isActive)
        }
        #else
        ModeLibraryView(session: session, contentFocus: .exploration, isActive: isActive)
        #endif
    }
}
