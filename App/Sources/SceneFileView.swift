import SwiftUI
import AppCore
import UniformTypeIdentifiers

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
        .alert("Nouvelle scene", isPresented: $showNewSceneAlert) {
            TextField("Titre", text: $newSceneTitle)
            Button("Creer") {
                session.newScene(title: newSceneTitle.isEmpty ? "Scene" : newSceneTitle)
                newSceneTitle = ""
                onLoaded()
            }
            Button("Annuler", role: .cancel) {}
        }
        .fileExporter(
            isPresented: $showSceneExporter,
            document: PlainDataDocument(data: pendingSceneExportData),
            contentType: .json,
            defaultFilename: scene?.title ?? "Scene"
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
                Text("Aucune scene active.").foregroundStyle(.secondary)
            }
            Button("Nouvelle scene") { showNewSceneAlert = true }
            // `currentSceneFilePath` also gets set by the "Exporter..." button below, which
            // writes to (then deletes) a temp file — `fileExists` keeps this button from
            // offering a reload of a path that no longer exists on disk.
            if let path = session.currentSceneFilePath, FileManager.default.fileExists(atPath: path) {
                Button("Recharger cette scene") {
                    do {
                        try session.loadScene(fromJSONFile: path)
                        onLoaded()
                    } catch {
                        actionError = "\(error)"
                    }
                }
            }
        } header: {
            Text("Scene")
        } footer: {
            if let path = session.currentSceneFilePath, FileManager.default.fileExists(atPath: path) {
                Text("Recharge la scene depuis le disque, en perdant les changements non sauvegardes.")
            }
        }
    }

    @ViewBuilder
    private var sceneFolderSection: some View {
        Section {
            if session.sceneFiles.isEmpty {
                Text("Aucun dossier de scenes choisi — vas dans l'onglet JamShack > Dossiers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.sceneFiles, id: \.self) { name in
                    Button(name) {
                        do {
                            try session.loadScene(named: name)
                            onLoaded()
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
                if scene != nil {
                    Button("Sauvegarder dans ce dossier") {
                        do {
                            try session.saveScene(title: scene?.title ?? "Scene", as: (scene?.title ?? "Scene") + ".json")
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
            }
        } header: {
            Text("Dossier de scenes")
        }
    }

    @ViewBuilder
    private var saveLoadSection: some View {
        Section {
            Button("Exporter...") {
                do {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
                    try session.saveScene(title: scene?.title ?? "Scene", toJSONFile: tempURL.path)
                    pendingSceneExportData = try Data(contentsOf: tempURL)
                    try? FileManager.default.removeItem(at: tempURL)
                    showSceneExporter = true
                } catch {
                    actionError = "\(error)"
                }
            }
            Button("Importer...") { showSceneImporter = true }
        } header: {
            Text("Fichier unique")
        } footer: {
            Text("Pour partager une scene en dehors du dossier de scenes (AirDrop, Fichiers, etc).")
        }
    }
}

#Preview {
    SceneFileView(session: ImprovSession(), onLoaded: {})
}
