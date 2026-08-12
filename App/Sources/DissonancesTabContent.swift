import SwiftUI
import AppCore

/// Théorie's own "Dissonances" tab — wraps `DissonancesLibraryView`. No detach-into-its-own-window
/// support yet, same as `TuningTabContent`/`TonnetzTabContent`.
struct DissonancesTabContent: View {
    let session: ImprovSession
    /// See `ExplorationTabContent.isActive`'s own doc comment — feeds `DissonancesLibraryView`'s
    /// own `session.setContextualMode`.
    let isActive: Bool

    var body: some View {
        DissonancesLibraryView(session: session, isActive: isActive)
    }
}
