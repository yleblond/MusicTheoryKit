import SwiftUI
import AppCore
import UniformTypeIdentifiers

/// Scene/role management: create a scene, declare roles ("Piano 1", "Basse"...), attach a
/// live instrument (MIDI/computer keyboard/microphone/...) to a role, assign each role its
/// own sound, and save/load the whole thing — the GUI counterpart to the CLI's "Scene"
/// menu category (`scene-new`/`scene-role-*`/`save-scene`/`use-scene` commands).
///
/// File access (scene save/load, the sample-sound folder) goes through SwiftUI's
/// `.fileExporter`/`.fileImporter` on BOTH platforms — NOT a typed path on macOS, even
/// though that matches the CLI's own convention there. The CLI can type any path because
/// it's a plain, unsandboxed process; this app has `com.apple.security.app-sandbox` enabled
/// (a real security boundary, kept deliberately), and a sandboxed app can only reach a path
/// it didn't create itself by going through an actual Open/Save panel (or a persisted
/// security-scoped bookmark from a past one) — typing a path directly is silently/visibly
/// refused regardless of what's typed. `.fileExporter`/`.fileImporter` are exactly "the
/// panel," and they work identically well on macOS as on iOS.
struct SceneManagementView: View {
    let session: ImprovSession

    @State private var newSceneTitle = ""
    @State private var showNewSceneAlert = false
    @State private var newRoleName = ""
    @State private var showNewRoleAlert = false
    @State private var actionError: String?

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
            Button(sampleFolderURL == nil ? "Choisir un dossier de sons" : "Changer de dossier de sons") {
                showSampleFolderImporter = true
            }
            if let sampleFolderURL {
                Text(sampleFolderURL.path).font(.caption).foregroundStyle(.secondary)
            }
            if !session.sampleFiles.isEmpty {
                Text("\(session.sampleFiles.count) son(s) trouve(s) — utilisable(s) comme nom dans le champ 'Son' d'un role.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Sons disponibles")
        } footer: {
            Text("Cet acces ne persiste que pendant que l'app tourne — a refaire au prochain lancement.")
        }
    }

    @ViewBuilder
    private var saveLoadSection: some View {
        Section {
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
