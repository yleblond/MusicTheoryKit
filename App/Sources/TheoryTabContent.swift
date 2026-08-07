import SwiftUI
import AppCore
import Localization

/// Wraps `TheoryView` with the same detach-into-its-own-window swap `MicrophoneTabContent`/
/// `GuideConfigurationView` already do for their own screens.
struct TheoryTabContent: View {
    let session: ImprovSession

    @Environment(AppModel.self) private var appModel
    #if os(macOS) || os(visionOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    var body: some View {
        #if os(macOS) || os(visionOS)
        if appModel.openAuxiliaryWindows.contains(.theorie) {
            DetachedPlaceholderView(
                message: L10n.string(.appLabelOuvertDansFenetreSeparee, session.currentLanguage),
                language: session.currentLanguage,
                onReintegrate: { dismissWindow(id: AuxiliaryWindowID.theorie.rawValue) }
            )
        } else {
            TheoryView(session: session)
        }
        #else
        TheoryView(session: session)
        #endif
    }
}
