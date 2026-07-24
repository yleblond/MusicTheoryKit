import SwiftUI
import AppCore
import UniformTypeIdentifiers

/// Scene/role management: create a scene, declare roles ("Piano 1", "Basse"...), attach a
/// live instrument (MIDI/computer keyboard/microphone/...) to a role, assign each role its
/// own sound, and save/load the whole thing — the GUI counterpart to the CLI's "Scene"
/// menu category (`scene-new`/`scene-role-*`/`save-scene`/`use-scene` commands).
///
/// The sample-sound folder is no longer picked here — it's now the "Sons (samples)" row in
/// the "JamShack" tab's "Dossiers" sub-tab (`JamShackFoldersView`), same place as every other
/// folder the app needs. This screen just reads `session.sampleFiles` for the role sound
/// picker, and `session.sceneFiles`/`sceneFolder` for the folder-based save/load section
/// below (also picked from the same "Dossiers" sub-tab).
///
/// Single-file export/import still goes through SwiftUI's `.fileExporter`/`.fileImporter` on
/// BOTH platforms — NOT a typed path on macOS, even though that matches the CLI's own
/// convention there. The CLI can type any path because it's a plain, unsandboxed process;
/// this app has `com.apple.security.app-sandbox` enabled (a real security boundary, kept
/// deliberately), and a sandboxed app can only reach a path it didn't create itself by going
/// through an actual Open/Save panel (or a persisted security-scoped bookmark from a past
/// one) — typing a path directly is silently/visibly refused regardless of what's typed.
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

    private var scene: AppCore.Scene? { session.currentScene }

    var body: some View {
        Form {
            sceneHeaderSection
            // Reachable whether or not a scene is currently active: this is how you load one
            // in the first place, not just how you switch away from an existing one.
            sceneFolderSection
            if scene != nil {
                // Sound-availability hint BEFORE roles: a role's sound picker needs
                // `session.sampleFiles` already populated to have anything to offer.
                sampleAvailabilitySection
                rolesSection
                unassignedInstrumentsSection
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
    private var rolesSection: some View {
        Section {
            ForEach(scene?.roles ?? []) { role in
                SceneRoleRow(session: session, role: role, sampleFiles: session.sampleFiles, onError: { actionError = $0 })
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
    private var sampleAvailabilitySection: some View {
        Section {
            if session.sampleFiles.isEmpty {
                Text("Aucun son disponible — choisis un dossier de sons dans l'onglet JamShack > Dossiers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(session.sampleFiles.count) son(s) trouve(s) — choisis-en un dans le menu 'Son' de chaque role ci-dessous.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Sons disponibles")
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

private struct SceneRoleRow: View {
    let session: ImprovSession
    let role: SceneRole
    let sampleFiles: [String]
    let onError: (String) -> Void

    private func setSound(_ name: String?) {
        do {
            try session.setSceneRoleSound(role.id, soundName: name)
        } catch {
            onError("\(error)")
        }
    }

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
                Spacer()
                if sampleFiles.isEmpty {
                    Text("choisis un dossier de sons ci-dessus").font(.caption).foregroundStyle(.secondary)
                } else {
                    Menu(role.soundName ?? "Aucun") {
                        Button("Aucun") { setSound(nil) }
                        ForEach(sampleFiles, id: \.self) { name in
                            Button(name) { setSound(name) }
                        }
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
    }
}

#Preview {
    SceneManagementView(session: ImprovSession())
}
