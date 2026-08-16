import SwiftUI
import AppCore
import Localization

/// A per-screen "Théorie" button triggering the SAME contextual-help presentation the shared
/// bottom-bar "?" already does (`ContentView.contextualHelpButton`) — opens
/// `AuxiliaryWindowID.contextualHelp` on macOS/visionOS, or sets `appModel.showsContextualHelpSheet`
/// elsewhere. Doesn't own any content itself: whichever screen places this button is expected to
/// have already called `.registerContextualHelp(id:isActive:content:)` with its own legend/help
/// view, exactly as `ModeLibraryView`'s `.exploration` focus already does. Meant to be placed next
/// to that screen's own `detachButton`, for a consistent per-screen affordance — first applied to
/// `TonnetzLibraryView`; retrofitting the other Théorie screens (Accords, Modes, Progressions,
/// Intonations) with the same button is a follow-up, not yet done. Icon-only (a book, not the
/// bottom bar's "?") per explicit request — this button sits directly over screen content, where
/// a text label would compete for space more than the bottom bar's own dedicated row does.
struct TheoryHelpButton: View {
    let session: ImprovSession

    @Environment(AppModel.self) private var appModel
    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Button {
            // Reset before opening — see `AppModel.pinnedHelpTopic`'s own doc comment.
            appModel.pinnedHelpTopic = nil
            #if os(macOS) || os(visionOS)
            openWindow(id: AuxiliaryWindowID.contextualHelp.rawValue)
            #else
            appModel.showsContextualHelpSheet = true
            #endif
        } label: {
            Image(systemName: "book.closed")
        }
        .accessibilityLabel(L10n.string(.appButtonTheorie, session.currentLanguage))
    }
}
