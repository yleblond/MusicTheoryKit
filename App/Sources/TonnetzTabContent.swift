import SwiftUI
import AppCore

/// Théorie's own "Tonnetz" tab — wraps `TonnetzLibraryView`, coupled to the same "clavier
/// principal" (`session.theoryLiveInputSourceID`) every other Théorie screen shares.
/// No detach-into-its-own-window support yet (unlike `ChordTabContent`/`TheoryTabContent`) —
/// deferred to a later pass.
struct TonnetzTabContent: View {
    let session: ImprovSession
    /// See `ExplorationTabContent.isActive`'s own doc comment — feeds `TonnetzLibraryView`'s own
    /// `.registerMainKeyboardChord` so the persistent bar only reflects this screen's selection
    /// while it's actually the one on screen.
    let isActive: Bool

    var body: some View {
        TonnetzLibraryView(session: session, isActive: isActive)
    }
}
