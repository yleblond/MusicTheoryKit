import SwiftUI
import AppCore
import UniformTypeIdentifiers
import Localization

/// Screen 1 of the Guide tab: the store-based guide list (activate/rename/export/delete any
/// saved guide sequence — guides live in a private SwiftData store, no folder to pick anymore),
/// a discreet import affordance next to the list's own header, and a "Nouveau guide" button —
/// activating or creating a guide here is the only way to reach screen 2, `GuideConfigurationView`
/// (see `onLoaded`). Everything about the *currently active* guide (name, manual save, the
/// Edition/Lecture modes) lives on that second screen instead, not here. Mirrors `SceneFileView`.
struct GuideFileView: View {
    let session: ImprovSession
    /// Called after a guide is actually made current — activated from the list, created fresh,
    /// or imported from a single file — `GuideView` switches to screen 2.
    let onLoaded: () -> Void

    @State private var actionError: String?

    @State private var renamingIndex: Int?
    @State private var renameDraft = ""
    @State private var showRenameAlert = false

    @State private var pendingGuideExportData = Data()
    @State private var showGuideExporter = false
    @State private var pendingExportFilename = ""
    @State private var showGuideImporter = false

    var body: some View {
        Form {
            newGuideSection
            guideListSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .alert(L10n.string(.appAlertRenommerGuide, session.currentLanguage), isPresented: $showRenameAlert) {
            TextField(L10n.string(.fieldTitre, session.currentLanguage), text: $renameDraft)
            Button(L10n.string(.appButtonRenommer, session.currentLanguage)) {
                if let renamingIndex {
                    do {
                        try session.renameGuideSequence(atIndex: renamingIndex, name: renameDraft)
                    } catch {
                        actionError = "\(error)"
                    }
                }
                renameDraft = ""
                renamingIndex = nil
            }
            Button(L10n.string(.appAnnuler, session.currentLanguage), role: .cancel) { renamingIndex = nil }
        }
        .fileExporter(
            isPresented: $showGuideExporter,
            document: PlainDataDocument(data: pendingGuideExportData),
            contentType: .json,
            defaultFilename: pendingExportFilename
        ) { result in
            if case .failure(let error) = result { actionError = "\(error)" }
        }
        .fileImporter(isPresented: $showGuideImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    try session.loadGuideSequence(fromJSONFile: url.path)
                    onLoaded()
                } catch {
                    actionError = "\(error)"
                }
            case .failure(let error):
                actionError = "\(error)"
            }
        }
    }

    @ViewBuilder
    private var newGuideSection: some View {
        Section {
            if let actionError {
                Text(actionError).foregroundStyle(.red).font(.caption)
            }
            Button(L10n.string(.appNouveauGuide, session.currentLanguage)) {
                do {
                    try session.createNewGuideSequence()
                    onLoaded()
                } catch {
                    actionError = "\(error)"
                }
            }
        } header: {
            Text(L10n.string(.headingGuide, session.currentLanguage))
        }
    }

    @ViewBuilder
    private var guideListSection: some View {
        Section {
            if session.guideSequenceNames.isEmpty {
                Text(L10n.string(.appPlaceholderAucunDossierGuides, session.currentLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(session.guideSequenceNames.enumerated()), id: \.offset) { index, name in
                    HStack {
                        Button(name) {
                            do {
                                try session.useGuideSequence(named: name)
                                onLoaded()
                            } catch {
                                actionError = "\(error)"
                            }
                        }
                        Spacer()
                        Button {
                            renamingIndex = index
                            renameDraft = name
                            showRenameAlert = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L10n.string(.appButtonRenommer, session.currentLanguage))
                        Button {
                            do {
                                pendingGuideExportData = try session.exportedGuideData(atIndex: index)
                                pendingExportFilename = name
                                showGuideExporter = true
                            } catch {
                                actionError = "\(error)"
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L10n.string(.appButtonExporter, session.currentLanguage))
                        Button {
                            do {
                                try session.deleteGuideSequence(atIndex: index)
                            } catch {
                                actionError = "\(error)"
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }
            }
        } header: {
            HStack {
                Text(L10n.string(.appHeadingDossierGuides, session.currentLanguage))
                Spacer()
                Button {
                    showGuideImporter = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.string(.appButtonImporter, session.currentLanguage))
            }
        }
    }
}

#Preview {
    GuideFileView(session: ImprovSession(), onLoaded: {})
}
