import SwiftUI
import AppCore

/// "Fichier" sub-tab of the Guide tab: create a new guide, see which one is active, and the
/// folder-based guide browser (list/load/save-into-folder — the folder itself is picked from
/// the "JamShack" tab's "Dossiers" sub-tab).
struct GuideFileView: View {
    let session: ImprovSession
    /// Called after a guide is actually loaded from the folder — `GuideView` switches to the
    /// "Lecture" sub-tab, per explicit user request.
    let onLoaded: () -> Void

    @State private var newTitle = ""
    @State private var showNewAlert = false
    @State private var actionError: String?

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            headerSection
            folderSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .alert("Nouveau guide", isPresented: $showNewAlert) {
            TextField("Titre", text: $newTitle)
            Button("Creer") {
                session.newGuideSequence(title: newTitle.isEmpty ? "Guide" : newTitle)
                newTitle = ""
            }
            Button("Annuler", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        Section {
            if let guide = session.currentGuide {
                Text(guide.title).font(.headline)
            } else {
                Text("Aucun guide actif.").foregroundStyle(.secondary)
            }
            Button("Nouveau guide") { showNewAlert = true }
        } header: {
            Text("Guide")
        }
    }

    @ViewBuilder
    private var folderSection: some View {
        Section {
            if session.guideFiles.isEmpty {
                Text("Aucun dossier de guides choisi — JamShack > Dossiers.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(session.guideFiles, id: \.self) { name in
                    Button(name.strippingJSONExtension) {
                        do {
                            try session.loadGuideSequence(named: name)
                            onLoaded()
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
                if session.currentGuide != nil {
                    Button("Sauvegarder dans ce dossier") {
                        do {
                            try session.saveGuideSequence(as: (session.currentGuide?.title ?? "Guide") + ".json")
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
            }
        } header: {
            Text("Dossier de guides")
        }
    }
}

#Preview {
    GuideFileView(session: ImprovSession(), onLoaded: {})
}
