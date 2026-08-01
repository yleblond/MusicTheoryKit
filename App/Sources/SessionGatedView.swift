import SwiftUI
import AppCore
import JamShackUI
import Localization

/// Shared "wait for `AppModel.start()`" gate — every window (main + the 4 auxiliary ones)
/// wraps its real content in this instead of re-writing the bridge/startError/ProgressView
/// tri-state itself. Each window's own `.task { }` calls `appModel.start()` too (idempotent,
/// see `AppModel.didStart`), so an auxiliary window opened stand-alone before the main window
/// has ever appeared (possible on macOS/visionOS, e.g. window restoration) still starts the
/// session itself rather than sitting on a `ProgressView` forever.
struct SessionGatedView<Content: View>: View {
    @Environment(AppModel.self) private var appModel
    @ViewBuilder let content: (ImprovSession, SessionUIBridge) -> Content

    var body: some View {
        Group {
            if let bridge = appModel.bridge {
                content(appModel.session, bridge)
            } else if let startError = appModel.startError {
                Text(startError).foregroundStyle(.red).padding()
            } else {
                ProgressView(L10n.string(.appStatusDemarrage, appModel.session.currentLanguage))
            }
        }
        .task { await appModel.start() }
    }
}

/// Shown in the main window in place of a screen that's currently open in its own detached
/// window (visionOS spatial placement / macOS floating window) — "Réintégrer" closes that
/// window, which brings the real screen back here (driven by `AppModel.openAuxiliaryWindows`,
/// updated by the detached window's own `onAppear`/`onDisappear`).
struct DetachedPlaceholderView: View {
    let message: String
    let language: AppLanguage
    let onReintegrate: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onReintegrate) {
                Label(L10n.string(.appButtonReintegrer, language), systemImage: "arrow.down.right.and.arrow.up.left")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
