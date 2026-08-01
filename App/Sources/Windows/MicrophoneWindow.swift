import SwiftUI
import AppCore

/// Detached-window counterpart of the "Microphone" settings tab (`MicrophoneControlsView`,
/// see `AuxiliaryWindowID.microphone`). The spectrum-capture stop-on-close fix lives inside
/// `MicrophoneControlsView` itself (its `spectroscopeEnabled` state is private) rather than
/// here.
struct MicrophoneWindow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        SessionGatedView { session, bridge in
            MicrophoneControlsView(session: session, bridge: bridge, isDetachedWindow: true)
        }
        .onAppear { appModel.markWindowOpen(.microphone) }
        .onDisappear { appModel.markWindowClosed(.microphone) }
    }
}
