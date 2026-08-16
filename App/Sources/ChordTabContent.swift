import SwiftUI
import AppCore
import Localization

/// Wraps `ChordLibraryView` with the same detach-into-its-own-window swap `TheoryTabContent`/
/// `MicrophoneTabContent` already do for their own screens.
struct ChordTabContent: View {
    let session: ImprovSession
    /// See `ExplorationTabContent.isActive`'s own doc comment.
    let isActive: Bool

    @Environment(AppModel.self) private var appModel
    #if os(macOS) || os(visionOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    var body: some View {
        #if os(macOS) || os(visionOS)
        if appModel.openAuxiliaryWindows.contains(.theorieAccords) {
            DetachedPlaceholderView(
                message: L10n.string(.appLabelOuvertDansFenetreSeparee, session.currentLanguage),
                language: session.currentLanguage,
                onReintegrate: { dismissWindow(id: AuxiliaryWindowID.theorieAccords.rawValue) }
            )
        } else {
            chordLibrary
        }
        #else
        chordLibrary
        #endif
    }

    private var chordLibrary: some View {
        ChordLibraryView(session: session, isActive: isActive)
            .registerContextualHelp(id: HelpTopicID.theorieAccords.rawValue, isActive: isActive) {
                HelpTopicID.theorieAccords.content(language: session.currentLanguage)
            }
    }
}
