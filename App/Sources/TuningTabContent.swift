import SwiftUI
import AppCore

/// Théorie's own "Intonations" tab — wraps `TuningLibraryView`. No detach-into-its-own-window
/// support yet, same as `TonnetzTabContent`/`StudioJamSessionTabContent`.
struct TuningTabContent: View {
    let session: ImprovSession

    var body: some View {
        TuningLibraryView(session: session)
    }
}
