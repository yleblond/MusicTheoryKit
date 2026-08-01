import SwiftUI
import AppCore
import JamShackUI
import Localization

/// Wraps `RunScreen` (the "En direct" tab) with the same detach-into-its-own-window swap
/// `GuideConfigurationView` already does for Guide > Lecture — as its own view (mirroring that
/// one) rather than an inline `if`/`else` inside `ContentView`'s giant `body`, which didn't
/// reliably swap to the placeholder in practice.
struct LiveTabContent: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    @Environment(AppModel.self) private var appModel
    #if os(macOS) || os(visionOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    var body: some View {
        #if os(macOS) || os(visionOS)
        if appModel.openAuxiliaryWindows.contains(.runScreen) {
            DetachedPlaceholderView(
                message: L10n.string(.appLabelOuvertDansFenetreSeparee, session.currentLanguage),
                language: session.currentLanguage,
                onReintegrate: { dismissWindow(id: AuxiliaryWindowID.runScreen.rawValue) }
            )
        } else {
            RunScreen(session: session, bridge: bridge)
                // Same LUMI-follows-the-active-screen wiring as Guide > Lecture.
                .onAppear { session.notifyActiveScreen(.run) }
                .onDisappear {
                    // Guarded: if `RunScreenWindow` just took over (this tab disappearing
                    // because the user opened it in its own window), don't stomp its `.run`
                    // with `.other`.
                    if !appModel.openAuxiliaryWindows.contains(.runScreen) {
                        session.notifyActiveScreen(.other)
                    }
                }
        }
        #else
        RunScreen(session: session, bridge: bridge)
            .onAppear { session.notifyActiveScreen(.run) }
            .onDisappear { session.notifyActiveScreen(.other) }
        #endif
    }
}
