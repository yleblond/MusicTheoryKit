import SwiftUI
import AppCore
import UniformTypeIdentifiers
import Localization

/// "Fichier" sub-tab of the Scene tab: create/rename the active scene, single-file
/// export/import, and the folder-based scene browser (list/load/save-into-folder — the folder
/// itself is picked from the "JamShack" tab's "Dossiers" sub-tab, same place as every other
/// folder the app needs).
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
    /// Called after a scene is actually made current — created, loaded (from the folder,
    /// a reload, or a single-file import) — `SceneManagementView` switches to the
    /// "Disposition" sub-tab, per explicit user request.
    let onLoaded: () -> Void

    @State private var newSceneTitle = ""
    @State private var showNewSceneAlert = false
    @State private var actionError: String?

    @State private var pendingSceneExportData = Data()
    @State private var showSceneExporter = false
    @State private var showSceneImporter = false

    private var scene: AppCore.Scene? { session.currentScene }

    var body: some View {
        Form {
            sceneHeaderSection
            sceneFolderSection
            saveLoadSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .alert(L10n.string(.appNouvelleScene, session.currentLanguage), isPresented: $showNewSceneAlert) {
            TextField(L10n.string(.fieldTitre, session.currentLanguage), text: $newSceneTitle)
            Button(L10n.string(.appCreer, session.currentLanguage)) {
                session.newScene(title: newSceneTitle.isEmpty ? L10n.string(.tabScene, session.currentLanguage) : newSceneTitle)
                newSceneTitle = ""
                onLoaded()
            }
            Button(L10n.string(.appAnnuler, session.currentLanguage), role: .cancel) {}
        }
        .fileExporter(
            isPresented: $showSceneExporter,
            document: PlainDataDocument(data: pendingSceneExportData),
            contentType: .json,
            defaultFilename: scene?.title ?? L10n.string(.tabScene, session.currentLanguage)
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
                Text(scene.title).font(.headline)
            } else {
                Text(L10n.string(.appPlaceholderAucuneSceneActivePoint, session.currentLanguage)).foregroundStyle(.secondary)
            }
            Button(L10n.string(.appNouvelleScene, session.currentLanguage)) { showNewSceneAlert = true }
            // `currentSceneFilePath` also gets set by the "Exporter..." button below, which
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
    private var sceneFolderSection: some View {
        Section {
            if session.sceneFiles.isEmpty {
                Text(L10n.string(.appPlaceholderAucunDossierScenes, session.currentLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.sceneFiles, id: \.self) { name in
                    Button(name.strippingJSONExtension) {
                        do {
                            try session.loadScene(named: name)
                            onLoaded()
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
                if scene != nil {
                    Button(L10n.string(.appButtonSauvegarderDansCeDossier, session.currentLanguage)) {
                        do {
                            try session.saveScene(title: scene?.title ?? L10n.string(.tabScene, session.currentLanguage), as: (scene?.title ?? L10n.string(.tabScene, session.currentLanguage)) + ".json")
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
            }
        } header: {
            Text(L10n.string(.appHeadingDossierScenes, session.currentLanguage))
        }
    }

    @ViewBuilder
    private var saveLoadSection: some View {
        Section {
            Button(L10n.string(.appButtonExporter, session.currentLanguage)) {
                do {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
                    try session.saveScene(title: scene?.title ?? L10n.string(.tabScene, session.currentLanguage), toJSONFile: tempURL.path)
                    pendingSceneExportData = try Data(contentsOf: tempURL)
                    try? FileManager.default.removeItem(at: tempURL)
                    showSceneExporter = true
                } catch {
                    actionError = "\(error)"
                }
            }
            Button(L10n.string(.appButtonImporter, session.currentLanguage)) { showSceneImporter = true }
        } header: {
            Text(L10n.string(.appHeadingFichierUnique, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintPartagerScene, session.currentLanguage))
        }
    }
}

#Preview {
    SceneFileView(session: ImprovSession(), onLoaded: {})
}
