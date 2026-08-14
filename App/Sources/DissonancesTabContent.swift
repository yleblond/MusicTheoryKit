import SwiftUI
import AppCore
import Localization

/// Théorie's own "Dissonances" tab — wraps `DissonancesLibraryView` with the same detach-into-
/// its-own-window swap `ChordTabContent`/`TheoryTabContent` already do for their own screens.
struct DissonancesTabContent: View {
    let session: ImprovSession
    /// See `ExplorationTabContent.isActive`'s own doc comment — feeds `DissonancesLibraryView`'s
    /// own `session.setContextualMode`.
    let isActive: Bool

    @Environment(AppModel.self) private var appModel
    #if os(macOS) || os(visionOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    var body: some View {
        #if os(macOS) || os(visionOS)
        if appModel.openAuxiliaryWindows.contains(.theorieDissonances) {
            DetachedPlaceholderView(
                message: L10n.string(.appLabelOuvertDansFenetreSeparee, session.currentLanguage),
                language: session.currentLanguage,
                onReintegrate: { dismissWindow(id: AuxiliaryWindowID.theorieDissonances.rawValue) }
            )
        } else {
            DissonancesLibraryView(session: session, isActive: isActive)
        }
        #else
        DissonancesLibraryView(session: session, isActive: isActive)
        #endif
    }
}
