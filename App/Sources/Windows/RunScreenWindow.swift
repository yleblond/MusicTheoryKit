import SwiftUI
import AppCore
import JamShackUI

/// Detached-window counterpart of the "Live" tab (`RunScreen`, see `AuxiliaryWindowID
/// .runScreen`). With true detach, the main tab's own `RunScreen` instance is replaced by a
/// placeholder while this window is open (see `ContentView`), so only one instance of
/// `RunScreen` is ever actually visible at a time. `markWindowOpen` runs before
/// `notifyActiveScreen(.run)` so that by the time the main tab's own instance disappears (in
/// reaction to `markWindowOpen`) and checks "is the window already open" (see `ContentView`),
/// it correctly skips its own `.other` call instead of stomping this window's `.run`.
struct RunScreenWindow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        SessionGatedView { session, bridge in
            RunScreen(session: session, bridge: bridge, isDetachedWindow: true)
                .onAppear {
                    appModel.markWindowOpen(.runScreen)
                    session.notifyActiveScreen(.run)
                }
                .onDisappear {
                    appModel.markWindowClosed(.runScreen)
                    session.notifyActiveScreen(.other)
                }
        }
    }
}
