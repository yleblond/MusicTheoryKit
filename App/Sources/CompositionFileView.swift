import SwiftUI
import AppCore

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
                Text("Aucun dossier de composition IA choisi — JamShack > Dossiers.").font(.caption).foregroundStyle(.secondary)
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
                Button("Sauvegarder la description dans ce dossier") {
                    do {
                        try session.saveCompositionDescription(as: (session.compositionTitle ?? "Description") + ".json")
                    } catch {
                        actionError = "\(error)"
                    }
                }
            }
        } header: {
            Text("Dossier de composition IA")
        }
    }
}

#Preview {
    CompositionFileView(session: ImprovSession())
}
