import SwiftUI
import AppCore
import Localization

/// Wraps `ProgressionLibraryView` with the same detach-into-its-own-window swap
/// `TheoryTabContent`/`ChordTabContent` already do for their own screens.
struct ProgressionTabContent: View {
    let session: ImprovSession

    @Environment(AppModel.self) private var appModel
    #if os(macOS) || os(visionOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    var body: some View {
        #if os(macOS) || os(visionOS)
        if appModel.openAuxiliaryWindows.contains(.theorieProgressions) {
            DetachedPlaceholderView(
                message: L10n.string(.appLabelOuvertDansFenetreSeparee, session.currentLanguage),
                language: session.currentLanguage,
                onReintegrate: { dismissWindow(id: AuxiliaryWindowID.theorieProgressions.rawValue) }
            )
        } else {
            ProgressionLibraryView(session: session)
        }
        #else
        ProgressionLibraryView(session: session)
        #endif
    }
}
