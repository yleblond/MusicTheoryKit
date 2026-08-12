import SwiftUI
import AppCore
import Localization

/// Théorie's own "Tonnetz" tab — wraps `TonnetzLibraryView`, coupled to the same "clavier
/// principal" (`session.theoryLiveInputSourceID`) every other Théorie screen shares. Same
/// detach-into-its-own-window swap `ChordTabContent`/`TheoryTabContent` already do for their own
/// screens.
struct TonnetzTabContent: View {
    let session: ImprovSession
    /// See `ExplorationTabContent.isActive`'s own doc comment — feeds `TonnetzLibraryView`'s own
    /// `.registerMainKeyboardChord` so the persistent bar only reflects this screen's selection
    /// while it's actually the one on screen.
    let isActive: Bool

    @Environment(AppModel.self) private var appModel
    #if os(macOS) || os(visionOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    var body: some View {
        #if os(macOS) || os(visionOS)
        if appModel.openAuxiliaryWindows.contains(.theorieTonnetz) {
            DetachedPlaceholderView(
                message: L10n.string(.appLabelOuvertDansFenetreSeparee, session.currentLanguage),
                language: session.currentLanguage,
                onReintegrate: { dismissWindow(id: AuxiliaryWindowID.theorieTonnetz.rawValue) }
            )
        } else {
            TonnetzLibraryView(session: session, isActive: isActive)
        }
        #else
        TonnetzLibraryView(session: session, isActive: isActive)
        #endif
    }
}
