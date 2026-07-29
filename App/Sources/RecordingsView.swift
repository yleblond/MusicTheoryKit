import SwiftUI
import AppCore
import Localization

/// The "Enregistrements" tab — a sequential list → detail flow, mirroring `SceneManagementView`:
/// **Fichier** (`RecordingFileView`, the store-based soundtrack browser) leads into **Detail**
/// (`RecordingDetailView`, play/stop the current recording plus compose-from-it via the active
/// LLM connection — merges what used to be two separate sub-tabs into one screen). Neither view
/// needs `bridge` — only `session`.
struct RecordingsView: View {
    let session: ImprovSession

    private enum Screen { case list, detail }

    @State private var screen: Screen = .list

    var body: some View {
        Group {
            switch screen {
            case .list:
                RecordingFileView(session: session, onLoaded: { screen = .detail })
            case .detail:
                RecordingDetailView(session: session, onBackToList: { screen = .list })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RecordingsView(session: ImprovSession())
}
