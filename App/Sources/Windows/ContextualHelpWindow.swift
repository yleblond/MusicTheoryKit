import SwiftUI
import AppCore
import Localization

/// Root view of `AuxiliaryWindowID.contextualHelp`'s `WindowGroup` — a small, independent window
/// (macOS/visionOS) showing whichever screen currently registered itself via
/// `AppModel.setContextualHelp` (see `View.registerContextualHelp`), so it can stay open
/// alongside whatever screen it's explaining rather than covering it like a popover would. Was
/// `TheorieLegendWindow`, hardcoded to `TheoryLegendContent` — generalized to any screen's own
/// help per explicit request, so the same window/button now serves every screen instead of only
/// Modes/Exploration. No open/closed tracking — see `AuxiliaryWindowID.contextualHelp`'s own doc
/// comment.
struct ContextualHelpWindow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // `pinnedHelpTopic` (set by tapping a cross-reference link inside another
                // topic's own text) takes priority over the live screen's own registration —
                // see `AppModel.pinnedHelpTopic`'s own doc comment.
                if let pinned = appModel.pinnedHelpTopic {
                    Button {
                        appModel.pinnedHelpTopic = nil
                    } label: {
                        Label(L10n.string(.appHelpButtonRetour, appModel.session.currentLanguage), systemImage: "chevron.backward")
                    }
                    .buttonStyle(.plain)
                    pinned.content(language: appModel.session.currentLanguage)
                } else if let content = appModel.contextualHelpContent {
                    // Re-invoked (not a stored `AnyView`) so it stays live against whatever the
                    // registering screen's own closure still reads fresh (e.g.
                    // `session.currentLanguage`) for as long as this window stays open.
                    content()
                }
            }
            .padding()
        }
        .interceptHelpLinks(pinnedTopic: $appModel.pinnedHelpTopic)
    }
}
