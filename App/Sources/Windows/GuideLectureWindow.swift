import SwiftUI
import AppCore
import JamShackUI

/// Detached-window counterpart of Guide > Lecture (`GuideLectureView`, see `AuxiliaryWindowID
/// .guideLecture`). `onGuideStopped` is a true no-op here: `GuideConfigurationView`'s own
/// Edition/Lecture `mode` toggle doesn't exist in a standalone window — `GuideLectureView`
/// already falls back to its own `inactivePlaceholder` purely from `bridge.state.guide?
/// .isActive` going false (which `session.stopGuide()`, already called by the stop button
/// before this closure runs, is what flips), so there's nothing left for this window to do.
struct GuideLectureWindow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        SessionGatedView { session, bridge in
            GuideLectureView(session: session, bridge: bridge, onGuideStopped: {}, isDetachedWindow: true)
                .onAppear {
                    appModel.markWindowOpen(.guideLecture)
                    session.notifyActiveScreen(.guide)
                }
                .onDisappear {
                    appModel.markWindowClosed(.guideLecture)
                    session.notifyActiveScreen(.other)
                }
        }
    }
}
