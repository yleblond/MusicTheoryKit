import SwiftUI
import AppCore
import Localization

/// The "Composition" tab — a sequential list → composer flow, mirroring
/// `SceneManagementView`: **Fichier** (`CompositionFileView`, the store-based description list —
/// activating or creating a description is the only way to reach the next screen) leads into
/// **Composer** (`CompositionComposerView`, the title/style/description fields plus the compose
/// action). With no saved descriptions, this view opens straight on Composer (nothing to list
/// yet); otherwise it opens on the list.
struct CompositionView: View {
    let session: ImprovSession

    private enum Screen { case list, composer }

    @State private var screen: Screen

    init(session: ImprovSession) {
        self.session = session
        _screen = State(initialValue: session.compositionDescriptionNames.isEmpty ? .composer : .list)
    }

    var body: some View {
        Group {
            switch screen {
            case .list:
                CompositionFileView(session: session, onLoaded: { screen = .composer })
            case .composer:
                CompositionComposerView(session: session, onBackToList: { screen = .list })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    CompositionView(session: ImprovSession())
}
