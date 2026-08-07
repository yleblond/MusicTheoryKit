import SwiftUI
import AppCore
import Localization

/// Wraps `ModeLibraryView` with the same detach-into-its-own-window swap `MicrophoneTabContent`/
/// `GuideConfigurationView` already do for their own screens — the "Modes" tab (formerly the
/// merged "Théorie" tab; Accords/Progressions are now their own plain top-level tabs, see
/// `ContentView.StudioTab`, since only Modes grew enough content — the functional/melodic
/// exploration panel — to still be worth detaching).
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
            ModeLibraryView(session: session)
        }
        #else
        ModeLibraryView(session: session)
        #endif
    }
}
