import SwiftUI
import AppCore

/// "Disposition" sub-tab of the Scene tab: instruments <-> roles, side by side — attach an
/// unassigned instrument to a role from either direction (a dropdown on the instrument's own
/// row, "Attacher a...", or the dropdown on the role's own row, which now lists every
/// available instrument directly instead of just showing "libre" as plain, non-interactive
/// text). An unassigned instrument's own "Attacher a..." menu lists EVERY role, not just free
/// ones — an already-occupied role is marked "(occupe par ...)"; picking it moves that
/// instrument in (`attachInstrument` already displaces whatever was there, freeing it, so this
/// is just exposing a capability the session already had) — and offers "Ajouter un role..." to
/// create one on the spot instead of needing to visit the roles panel first.
struct SceneLayoutView: View {
    let session: ImprovSession

    @State private var newRoleName = ""
    @State private var showNewRoleAlert = false
    @State private var actionError: String?

    private var scene: AppCore.Scene? { session.currentScene }

    var body: some View {
        Group {
            if scene == nil {
                ContentUnavailableView {
                    Label("Aucune scene active", systemImage: "theatermasks")
                } description: {
                    Text("Active une scene existante ou cree-en une nouvelle.")
                } actions: {
                    ActivateOrCreateBlock(
                        files: session.sceneFiles,
                        onActivate: { try session.loadScene(named: $0) },
                        createButtonLabel: "Creer une scene",
                        createAlertTitle: "Nouvelle scene",
                        createFieldPlaceholder: "Nom de la scene",
                        onCreate: { session.newScene(title: $0) }
                    )
                }
            } else {
                VStack(spacing: 0) {
                    if let actionError {
                        Text(actionError).foregroundStyle(.red).font(.caption).padding(.horizontal)
                    }
                    HStack(alignment: .top, spacing: 0) {
                        Form { unassignedInstrumentsSection }
                        Divider()
                        Form { rolesSection }
                    }
                    #if os(macOS)
                    .formStyle(.grouped)
                    #endif
                }
            }
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
    }

    @ViewBuilder
    private var unassignedInstrumentsSection: some View {
        let unassigned = session.unassignedInstruments()
        Section {
            if unassigned.isEmpty {
                Text("Tous les instruments sont affectes.").font(.caption).foregroundStyle(.secondary)
            } else if let scene {
                ForEach(unassigned) { track in
                    UnassignedInstrumentRow(session: session, track: track, scene: scene, onError: { actionError = $0 })
                }
            }
        } header: {
            Text("Instruments non affectes")
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
}

private struct UnassignedInstrumentRow: View {
    let session: ImprovSession
    let track: TrackInfo
    let scene: AppCore.Scene
    let onError: (String) -> Void

    @State private var showNewRoleAlert = false
    @State private var newRoleName = ""

    var body: some View {
        HStack {
            Text(track.label)
            Spacer()
            Menu("Attacher a...") {
                ForEach(scene.roles) { role in
                    Button(label(for: role)) { attach(to: role) }
                }
                if !scene.roles.isEmpty { Divider() }
                Button("Ajouter un role...") { showNewRoleAlert = true }
            }
        }
        .alert("Nouveau role", isPresented: $showNewRoleAlert) {
            TextField("Nom (ex: Piano 1)", text: $newRoleName)
            Button("Creer et attacher") {
                do {
                    let roleID = try session.addSceneRole(name: newRoleName.isEmpty ? "Role" : newRoleName)
                    try session.attachInstrument(track.id, toRole: roleID)
                } catch {
                    onError("\(error)")
                }
                newRoleName = ""
            }
            Button("Annuler", role: .cancel) {}
        }
    }

    /// Marks an already-occupied role so picking it reads as "take over this role" rather
    /// than looking like a free one — `attachInstrument` already displaces whatever instrument
    /// was there (freeing it) once picked, this just makes that outcome visible up front.
    private func label(for role: SceneRole) -> String {
        guard let attachedID = role.attachedTrackID, let occupant = session.tracks.first(where: { $0.id == attachedID }) else {
            return role.name
        }
        return "\(role.name) (occupe par \(occupant.label))"
    }

    private func attach(to role: SceneRole) {
        do {
            try session.attachInstrument(track.id, toRole: role.id)
        } catch {
            onError("\(error)")
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

    private func attach(_ trackID: TrackID) {
        do {
            try session.attachInstrument(trackID, toRole: role.id)
        } catch {
            onError("\(error)")
        }
    }

    private func detach() {
        do {
            try session.detachInstrument(fromRole: role.id)
        } catch {
            onError("\(error)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(role.name).font(.headline)
                Spacer()
                // A real dropdown instead of plain "libre" text: every currently-unassigned
                // instrument is reachable directly from the role's own row, not just from the
                // "Instruments non affectes" block's own "Attacher a..." menu.
                Menu {
                    if role.attachedTrackID != nil {
                        Button("Detacher", role: .destructive) { detach() }
                    }
                    ForEach(session.unassignedInstruments()) { track in
                        Button(track.label) { attach(track.id) }
                    }
                } label: {
                    if let trackID = role.attachedTrackID, let track = session.tracks.first(where: { $0.id == trackID }) {
                        Text(track.label).foregroundStyle(.green)
                    } else {
                        Text("libre").foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Text("Son")
                Spacer()
                if sampleFiles.isEmpty {
                    Text("choisis un dossier de sons (JamShack > Dossiers)").font(.caption).foregroundStyle(.secondary)
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
    SceneLayoutView(session: ImprovSession())
}
