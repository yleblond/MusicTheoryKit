import SwiftUI
import AppCore
import UniformTypeIdentifiers

/// Scene/role management: create a scene, declare roles ("Piano 1", "Basse"...), attach a
/// live instrument (MIDI/computer keyboard/microphone/...) to a role, assign each role its
/// own sound, and save/load the whole thing — the GUI counterpart to the CLI's "Scene"
/// menu category (`scene-new`/`scene-role-*`/`save-scene`/`use-scene` commands).
///
/// Save/load is deliberately different per platform, per the same reasoning already used for
/// `ServerControlsView`'s ports and `SourcesView`'s server/client fields: macOS keeps the
/// existing file-path-typing convention (`ImprovSession.saveScene(title:toJSONFile:)` takes a
/// plain path, exactly like the CLI), but iOS is sandboxed — there's no "type any path on
/// disk" the way a Mac terminal has, so scene files go through SwiftUI's `.fileExporter`/
/// `.fileImporter` (the standard iOS document-picker pattern: Files app, iCloud Drive, "On My
/// iPad"...) instead. Same split for the sample-sound folder: macOS types a folder path,
/// iOS picks a folder via `.fileImporter(allowedContentTypes: [.folder])` and keeps a
/// security-scoped access token open for the rest of this view's lifetime.
struct SceneManagementView: View {
    let session: ImprovSession

    @State private var newSceneTitle = ""
    @State private var showNewSceneAlert = false
    @State private var newRoleName = ""
    @State private var showNewRoleAlert = false
    @State private var actionError: String?

    // macOS-only fields.
    @State private var scenePathText = ""
    @State private var sampleFolderPathText = ""

    // iOS-only fields.
    @State private var pendingSceneExportData = Data()
    @State private var showSceneExporter = false
    @State private var showSceneImporter = false
    @State private var showSampleFolderImporter = false
    @State private var sampleFolderURL: URL?

    private var scene: AppCore.Scene? { session.currentScene }

    var body: some View {
        Form {
            sceneHeaderSection
            if scene != nil {
                rolesSection
                unassignedInstrumentsSection
                sampleFolderSection
                saveLoadSection
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .alert("Nouvelle scene", isPresented: $showNewSceneAlert) {
            TextField("Titre", text: $newSceneTitle)
            Button("Creer") {
                session.newScene(title: newSceneTitle.isEmpty ? "Scene" : newSceneTitle)
                newSceneTitle = ""
            }
            Button("Annuler", role: .cancel) {}
        }
        .alert("Nouveau role", isPresented: $showNewRoleAlert) {
            TextField("Nom (ex: Piano 1)", text: $newRoleName)
            Button("Ajouter") {
                do {
                    try session.addSceneRole(name: newRoleName.isEmpty ? "Role" : newRoleName)
                } catch {
                    actionError = "\(error)"
                }
                newRoleName = ""
            }
            Button("Annuler", role: .cancel) {}
        }
        #if os(iOS)
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
                do { try session.loadScene(fromJSONFile: url.path) } catch { actionError = "\(error)" }
            case .failure(let error):
                actionError = "\(error)"
            }
        }
        .fileImporter(isPresented: $showSampleFolderImporter, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                sampleFolderURL?.stopAccessingSecurityScopedResource()
                if url.startAccessingSecurityScopedResource() {
                    sampleFolderURL = url
                    do { try session.listSampleFiles(in: url.path) } catch { actionError = "\(error)" }
                }
            case .failure(let error):
                actionError = "\(error)"
            }
        }
        #endif
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
        } header: {
            Text("Scene")
        }
    }

    @ViewBuilder
    private var rolesSection: some View {
        Section {
            ForEach(scene?.roles ?? []) { role in
                SceneRoleRow(session: session, role: role, onError: { actionError = $0 })
            }
            Button("Ajouter un role") { showNewRoleAlert = true }
        } header: {
            Text("Roles")
        }
    }

    @ViewBuilder
    private var unassignedInstrumentsSection: some View {
        let unassigned = session.unassignedInstruments()
        let freeRoles = session.freeSceneRoles()
        if !unassigned.isEmpty {
            Section {
                ForEach(unassigned) { track in
                    HStack {
                        Text(track.label)
                        Spacer()
                        if freeRoles.isEmpty {
                            Text("aucun role libre").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Menu("Attacher a...") {
                                ForEach(freeRoles) { role in
                                    Button(role.name) {
                                        do {
                                            try session.attachInstrument(track.id, toRole: role.id)
                                        } catch {
                                            actionError = "\(error)"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Instruments non affectes")
            }
        }
    }

    @ViewBuilder
    private var sampleFolderSection: some View {
        Section {
            #if os(macOS)
            HStack {
                TextField("Dossier des sons (.sf2/.dls/.aupreset)", text: $sampleFolderPathText)
                Button("Lister") {
                    do { try session.listSampleFiles(in: sampleFolderPathText) } catch { actionError = "\(error)" }
                }
            }
            #else
            Button(sampleFolderURL == nil ? "Choisir un dossier de sons" : "Changer de dossier de sons") {
                showSampleFolderImporter = true
            }
            #endif
            if !session.sampleFiles.isEmpty {
                Text("\(session.sampleFiles.count) son(s) trouve(s) — utilisable(s) comme nom dans le champ 'Son' d'un role.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Sons disponibles")
        }
    }

    @ViewBuilder
    private var saveLoadSection: some View {
        Section {
            #if os(macOS)
            HStack {
                TextField("Chemin du fichier .json", text: $scenePathText)
            }
            HStack {
                Button("Sauvegarder") {
                    do {
                        try session.saveScene(title: scene?.title ?? "Scene", toJSONFile: scenePathText)
                    } catch {
                        actionError = "\(error)"
                    }
                }
                Button("Charger") {
                    do {
                        try session.loadScene(fromJSONFile: scenePathText)
                    } catch {
                        actionError = "\(error)"
                    }
                }
            }
            #else
            Button("Sauvegarder...") {
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
            Button("Charger...") { showSceneImporter = true }
            #endif
        } header: {
            Text("Sauvegarde")
        }
    }
}

private struct SceneRoleRow: View {
    let session: ImprovSession
    let role: SceneRole
    let onError: (String) -> Void

    @State private var soundName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(role.name).font(.headline)
                Spacer()
                if let trackID = role.attachedTrackID, let track = session.tracks.first(where: { $0.id == trackID }) {
                    Text(track.label).foregroundStyle(.green)
                } else {
                    Text("libre").foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Son")
                TextField("nom du fichier son", text: $soundName)
                    .multilineTextAlignment(.trailing)
                    .onSubmit {
                        do {
                            try session.setSceneRoleSound(role.id, soundName: soundName.isEmpty ? nil : soundName)
                        } catch {
                            onError("\(error)")
                        }
                    }
            }
            HStack {
                Toggle("Ecoute", isOn: Binding(
                    get: { role.isListening },
                    set: { newValue in
                        do {
                            try session.setSceneRoleListening(role.id, isListening: newValue)
                        } catch {
                            onError("\(error)")
                        }
                    }
                ))
                Spacer()
                if role.attachedTrackID != nil {
                    Button("Detacher") {
                        do {
                            try session.detachInstrument(fromRole: role.id)
                        } catch {
                            onError("\(error)")
                        }
                    }
                }
                Button("Supprimer", role: .destructive) {
                    do {
                        try session.removeSceneRole(role.id)
                    } catch {
                        onError("\(error)")
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear { soundName = role.soundName ?? "" }
    }
}

#Preview {
    SceneManagementView(session: ImprovSession())
}
