import SwiftUI
import AppCore
import UniformTypeIdentifiers
import Localization

/// "Fichier" sub-tab of the Scene tab: the active scene's header (name, manual save, reload from
/// a raw file path), the store-based scene list (activate/rename/export/delete any saved scene —
/// scenes live in a private SwiftData store, no folder to pick anymore), and a single discreet
/// import affordance next to the list's own header.
///
/// Single-file export/import goes through SwiftUI's `.fileExporter`/`.fileImporter` on BOTH
/// platforms — NOT a typed path on macOS, even though that matches the CLI's own convention
/// there. The CLI can type any path because it's a plain, unsandboxed process; this app has
/// `com.apple.security.app-sandbox` enabled (a real security boundary, kept deliberately), and
/// a sandboxed app can only reach a path it didn't create itself by going through an actual
/// Open/Save panel — typing a path directly is silently/visibly refused regardless of what's
/// typed.
struct SceneFileView: View {
    let session: ImprovSession
    /// Called after a scene is actually made current — activated from the list or imported from
    /// a single file — `SceneManagementView` switches to the "Disposition" sub-tab, per explicit
    /// user request.
    let onLoaded: () -> Void

    @State private var actionError: String?

    @State private var renamingIndex: Int?
    @State private var renameDraft = ""
    @State private var showRenameAlert = false

    @State private var pendingSceneExportData = Data()
    @State private var showSceneExporter = false
    @State private var pendingExportFilename = ""
    @State private var showSceneImporter = false

    private var scene: AppCore.Scene? { session.currentScene }

    var body: some View {
        Form {
            sceneHeaderSection
            sceneListSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .alert(L10n.string(.appAlertRenommerScene, session.currentLanguage), isPresented: $showRenameAlert) {
            TextField(L10n.string(.fieldTitre, session.currentLanguage), text: $renameDraft)
            Button(L10n.string(.appButtonRenommer, session.currentLanguage)) {
                if let renamingIndex {
                    do {
                        try session.renameScene(atIndex: renamingIndex, name: renameDraft)
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
            isPresented: $showSceneExporter,
            document: PlainDataDocument(data: pendingSceneExportData),
            contentType: .json,
            defaultFilename: pendingExportFilename
        ) { result in
            if case .failure(let error) = result { actionError = "\(error)" }
        }
        .fileImporter(isPresented: $showSceneImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    try session.loadScene(fromJSONFile: url.path)
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
    private var sceneHeaderSection: some View {
        Section {
            if let actionError {
                Text(actionError).foregroundStyle(.red).font(.caption)
            }
            if let scene {
                Text(scene.title.isEmpty ? L10n.string(.appPlaceholderSceneSansNom, session.currentLanguage) : scene.title)
                    .font(.headline)
            }
            if session.currentSceneRecordID != nil {
                Button(L10n.string(.appButtonSauvegarderDansCeDossier, session.currentLanguage)) {
                    do {
                        try session.saveScene()
                    } catch {
                        actionError = "\(error)"
                    }
                }
            }
            // `currentSceneFilePath` also gets set by the per-row "Exporter" button below, which
            // writes to (then deletes) a temp file — `fileExists` keeps this button from
            // offering a reload of a path that no longer exists on disk.
            if let path = session.currentSceneFilePath, FileManager.default.fileExists(atPath: path) {
                Button(L10n.string(.appButtonRechargerScene, session.currentLanguage)) {
                    do {
                        try session.loadScene(fromJSONFile: path)
                        onLoaded()
                    } catch {
                        actionError = "\(error)"
                    }
                }
            }
        } header: {
            Text(L10n.string(.tabScene, session.currentLanguage))
        } footer: {
            if let path = session.currentSceneFilePath, FileManager.default.fileExists(atPath: path) {
                Text(L10n.string(.appHintRechargeScene, session.currentLanguage))
            }
        }
    }

    @ViewBuilder
    private var sceneListSection: some View {
        Section {
            if session.sceneNames.isEmpty {
                Text(L10n.string(.appPlaceholderAucunDossierScenes, session.currentLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(session.sceneNames.enumerated()), id: \.offset) { index, name in
                    HStack {
                        Button(name) {
                            do {
                                try session.useScene(named: name)
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
                                pendingSceneExportData = try session.exportedSceneData(atIndex: index)
                                pendingExportFilename = name
                                showSceneExporter = true
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
                                try session.deleteScene(atIndex: index)
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
                Text(L10n.string(.appHeadingDossierScenes, session.currentLanguage))
                Spacer()
                Button {
                    showSceneImporter = true
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
    SceneFileView(session: ImprovSession(), onLoaded: {})
}
