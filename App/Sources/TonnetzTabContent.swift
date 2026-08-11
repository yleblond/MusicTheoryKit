import SwiftUI
import AppCore
import JamShackUI

/// Studio's own "Tonnetz" tab: `TonnetzScreen` from `JamShackUI`, coupled to the app's single
/// "clavier principal" (`session.theoryLiveInputSourceID`) exactly like every other Studio tab.
/// No detach-into-its-own-window support yet (unlike `LiveTabContent`/`RunScreen`) — deferred to
/// a later pass, same simplicity as `StudioJamSessionTabContent`.
struct TonnetzTabContent: View {
    let session: ImprovSession

    var body: some View {
        TonnetzScreen(session: session)
    }
}
