import SwiftUI
import AppCore
import JamShackUI
import Localization

/// Wraps `MicrophoneControlsView` with the same detach-into-its-own-window swap
/// `GuideConfigurationView` already does for Guide > Lecture — as its own view (mirroring that
/// one) rather than an inline `if`/`else` inside `ContentView`'s giant `body`, which didn't
/// reliably swap to the placeholder in practice.
struct MicrophoneTabContent: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    @Environment(AppModel.self) private var appModel
    #if os(macOS) || os(visionOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    var body: some View {
        #if os(macOS) || os(visionOS)
        if appModel.openAuxiliaryWindows.contains(.microphone) {
            DetachedPlaceholderView(
                message: L10n.string(.appLabelOuvertDansFenetreSeparee, session.currentLanguage),
                language: session.currentLanguage,
                onReintegrate: { dismissWindow(id: AuxiliaryWindowID.microphone.rawValue) }
            )
        } else {
            MicrophoneControlsView(session: session, bridge: bridge)
        }
        #else
        MicrophoneControlsView(session: session, bridge: bridge)
        #endif
    }
}
