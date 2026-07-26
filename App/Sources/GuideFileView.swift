import SwiftUI
import AppCore
import Localization

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
        .alert(L10n.string(.appNouveauGuide, session.currentLanguage), isPresented: $showNewAlert) {
            TextField(L10n.string(.fieldTitre, session.currentLanguage), text: $newTitle)
            Button(L10n.string(.appCreer, session.currentLanguage)) {
                session.newGuideSequence(title: newTitle.isEmpty ? L10n.string(.headingGuide, session.currentLanguage) : newTitle)
                newTitle = ""
            }
            Button(L10n.string(.appAnnuler, session.currentLanguage), role: .cancel) {}
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        Section {
            if let guide = session.currentGuide {
                Text(guide.title).font(.headline)
            } else {
                Text(L10n.string(.appPlaceholderAucunGuideActifPoint, session.currentLanguage)).foregroundStyle(.secondary)
            }
            Button(L10n.string(.appNouveauGuide, session.currentLanguage)) { showNewAlert = true }
        } header: {
            Text(L10n.string(.headingGuide, session.currentLanguage))
        }
    }

    @ViewBuilder
    private var folderSection: some View {
        Section {
            if session.guideFiles.isEmpty {
                Text(L10n.string(.appPlaceholderAucunDossierGuides, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
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
                    Button(L10n.string(.appButtonSauvegarderDansCeDossier, session.currentLanguage)) {
                        do {
                            try session.saveGuideSequence(as: (session.currentGuide?.title ?? L10n.string(.headingGuide, session.currentLanguage)) + ".json")
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
            }
        } header: {
            Text(L10n.string(.appHeadingDossierGuides, session.currentLanguage))
        }
    }
}

#Preview {
    GuideFileView(session: ImprovSession(), onLoaded: {})
}
