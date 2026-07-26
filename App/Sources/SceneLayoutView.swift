import SwiftUI
import AppCore
import Localization

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
                    Label(L10n.string(.appLabelAucuneSceneActiveCourt, session.currentLanguage), systemImage: "theatermasks")
                } description: {
                    Text(L10n.string(.appHintActiveSceneExistante, session.currentLanguage))
                } actions: {
                    ActivateOrCreateBlock(
                        files: session.sceneFiles,
                        onActivate: { try session.loadScene(named: $0) },
                        createButtonLabel: L10n.string(.appButtonCreerUneScene, session.currentLanguage),
                        createAlertTitle: L10n.string(.appNouvelleScene, session.currentLanguage),
                        createFieldPlaceholder: L10n.string(.appFieldNomScene, session.currentLanguage),
                        onCreate: { session.newScene(title: $0) },
                        language: session.currentLanguage
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
        .alert(L10n.string(.appAlertNouveauRole, session.currentLanguage), isPresented: $showNewRoleAlert) {
            TextField(L10n.string(.appPlaceholderNomExPiano1, session.currentLanguage), text: $newRoleName)
            Button(L10n.string(.appButtonAjouter, session.currentLanguage)) {
                do {
                    try session.addSceneRole(name: newRoleName.isEmpty ? L10n.string(.fieldRole, session.currentLanguage) : newRoleName)
                } catch {
                    actionError = "\(error)"
                }
                newRoleName = ""
            }
            Button(L10n.string(.appAnnuler, session.currentLanguage), role: .cancel) {}
        }
    }

    @ViewBuilder
    private var unassignedInstrumentsSection: some View {
        let unassigned = session.unassignedInstruments()
        Section {
            if unassigned.isEmpty {
                Text(L10n.string(.appPlaceholderTousInstrumentsAffectes, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
            } else if let scene {
                ForEach(unassigned) { track in
                    UnassignedInstrumentRow(session: session, track: track, scene: scene, onError: { actionError = $0 })
                }
            }
        } header: {
            Text(L10n.string(.appHeadingInstrumentsNonAffectes, session.currentLanguage))
        }
    }

    @ViewBuilder
    private var rolesSection: some View {
        Section {
            ForEach(scene?.roles ?? []) { role in
                SceneRoleRow(session: session, role: role, sampleFiles: session.favoriteSampleFiles, onError: { actionError = $0 })
            }
            Button(L10n.string(.appButtonAjouterUnRole, session.currentLanguage)) { showNewRoleAlert = true }
        } header: {
            Text(L10n.string(.headerRoles, session.currentLanguage))
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
            Menu(L10n.string(.appMenuAttacherA, session.currentLanguage)) {
                ForEach(scene.roles) { role in
                    Button(label(for: role)) { attach(to: role) }
                }
                if !scene.roles.isEmpty { Divider() }
                Button(L10n.string(.appButtonAjouterUnRoleEllipsis, session.currentLanguage)) { showNewRoleAlert = true }
            }
        }
        .alert(L10n.string(.appAlertNouveauRole, session.currentLanguage), isPresented: $showNewRoleAlert) {
            TextField(L10n.string(.appPlaceholderNomExPiano1, session.currentLanguage), text: $newRoleName)
            Button(L10n.string(.appButtonCreerEtAttacher, session.currentLanguage)) {
                do {
                    let roleID = try session.addSceneRole(name: newRoleName.isEmpty ? L10n.string(.fieldRole, session.currentLanguage) : newRoleName)
                    try session.attachInstrument(track.id, toRole: roleID)
                } catch {
                    onError("\(error)")
                }
                newRoleName = ""
            }
            Button(L10n.string(.appAnnuler, session.currentLanguage), role: .cancel) {}
        }
    }

    /// Marks an already-occupied role so picking it reads as "take over this role" rather
    /// than looking like a free one — `attachInstrument` already displaces whatever instrument
    /// was there (freeing it) once picked, this just makes that outcome visible up front.
    private func label(for role: SceneRole) -> String {
        guard let attachedID = role.attachedTrackID, let occupant = session.tracks.first(where: { $0.id == attachedID }) else {
            return role.name
        }
        return L10n.string(.appFormatOccupeParRole, session.currentLanguage, role.name, occupant.label)
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
                        Button(L10n.string(.appButtonDetacher, session.currentLanguage), role: .destructive) { detach() }
                    }
                    ForEach(session.unassignedInstruments()) { track in
                        Button(track.label) { attach(track.id) }
                    }
                } label: {
                    if let trackID = role.attachedTrackID, let track = session.tracks.first(where: { $0.id == trackID }) {
                        Text(track.label).foregroundStyle(.green)
                    } else {
                        Text(L10n.string(.appLabelLibre, session.currentLanguage)).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Text(L10n.string(.fieldSon, session.currentLanguage))
                Spacer()
                if sampleFiles.isEmpty {
                    Text(L10n.string(.appPlaceholderAucunSonFavoriParenthese, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
                } else {
                    Menu(role.soundName.map(session.displayName(forSamplePath:)) ?? L10n.string(.appButtonAucun, session.currentLanguage)) {
                        Button(L10n.string(.appButtonAucun, session.currentLanguage)) { setSound(nil) }
                        ForEach(sampleFiles, id: \.self) { name in
                            Button(session.displayName(forSamplePath: name)) { setSound(name) }
                        }
                    }
                }
            }
            HStack {
                Text(L10n.string(.appFieldVolume, session.currentLanguage))
                Slider(value: Binding(
                    get: { role.volume },
                    set: { newValue in
                        do {
                            try session.setSceneRoleVolume(role.id, volume: newValue)
                        } catch {
                            onError("\(error)")
                        }
                    }
                ), in: 0...1)
            }
            HStack {
                Toggle(L10n.string(.fieldEcoute, session.currentLanguage), isOn: Binding(
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
                Button(L10n.string(.appButtonSupprimer, session.currentLanguage), role: .destructive) {
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
