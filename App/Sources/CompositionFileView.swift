import SwiftUI
import AppCore
import Localization

/// "Fichier" sub-tab of the Composition tab: the folder-based composition-description browser
/// (list/load/save-into-folder — the folder itself is picked from the "JamShack" tab's
/// "Dossiers" sub-tab). Loading a description here updates `session` directly, so switching to
/// the "Composer" sub-tab (whose fields read from `session` on appear) picks it up without any
/// direct coupling between the two sibling views.
struct CompositionFileView: View {
    let session: ImprovSession

    @State private var actionError: String?

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            folderSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    @ViewBuilder
    private var folderSection: some View {
        Section {
            if session.compositionFiles.isEmpty {
                Text(L10n.string(.appPlaceholderAucunDossierCompositionIA, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(session.compositionFiles, id: \.self) { name in
                    Button(name.strippingJSONExtension) {
                        do {
                            try session.loadCompositionDescription(named: name)
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
                Button(L10n.string(.appButtonSauvegarderDescriptionDossier, session.currentLanguage)) {
                    do {
                        try session.saveCompositionDescription(as: (session.compositionTitle ?? L10n.string(.fieldDescription, session.currentLanguage)) + ".json")
                    } catch {
                        actionError = "\(error)"
                    }
                }
            }
        } header: {
            Text(L10n.string(.appHeadingDossierCompositionIA, session.currentLanguage))
        }
    }
}

#Preview {
    CompositionFileView(session: ImprovSession())
}
