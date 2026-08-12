import SwiftUI
import AppCore

/// Théorie's own "Intonations" tab — wraps `TuningLibraryView`. No detach-into-its-own-window
/// support yet, same as `TonnetzTabContent`/`StudioJamSessionTabContent`.
struct TuningTabContent: View {
    let session: ImprovSession
    /// See `ExplorationTabContent.isActive`'s own doc comment — feeds `TuningLibraryView`'s own
    /// `session.setContextualMode`.
    let isActive: Bool

    var body: some View {
        TuningLibraryView(session: session, isActive: isActive)
    }
}
