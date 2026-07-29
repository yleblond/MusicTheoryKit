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
///
/// A plain, borderless title `TextField` sits above the two columns when a scene is active —
/// typing a name and moving focus away calls `renameCurrentScene(to:)`, which both renames an
/// already-saved scene in place and performs the FIRST save of a brand-new anonymous scene (no
/// separate "give it a name" dialog). `titleDraft` mirrors `scene.title` via `.onChange` rather
/// than via a `.task(id:)`-style keyed reset, specifically so it also resets correctly when
/// switching from one anonymous scene to another new one (both have no record id to key on).
struct SceneLayoutView: View {
    let session: ImprovSession

    @State private var newRoleName = ""
    @State private var showNewRoleAlert = false
    @State private var actionError: String?
    @State private var titleDraft = ""
    @FocusState private var titleFieldFocused: Bool

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
                        files: session.sceneNames,
                        onActivate: { try session.useScene(named: $0) },
                        createButtonLabel: L10n.string(.appButtonCreerUneScene, session.currentLanguage),
                        createAlertTitle: L10n.string(.appNouvelleScene, session.currentLanguage),
                        createFieldPlaceholder: L10n.string(.appFieldNomScene, session.currentLanguage),
                        onCreate: { session.newScene(title: $0) },
                        language: session.currentLanguage
                    )
                }
            } else if let scene {
                VStack(spacing: 0) {
                    if let actionError {
                        Text(actionError).foregroundStyle(.red).font(.caption).padding(.horizontal)
                    }
                    TextField(
                        L10n.string(.appPlaceholderSceneSansNom, session.currentLanguage),
                        text: $titleDraft
                    )
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
                    .focused($titleFieldFocused)
                    .padding([.horizontal, .top])
                    .onAppear { titleDraft = scene.title }
                    .onChange(of: scene.title) { _, newValue in
                        if !titleFieldFocused { titleDraft = newValue }
                    }
                    .onChange(of: titleFieldFocused) { wasFocused, isFocused in
                        guard wasFocused, !isFocused, titleDraft != scene.title, !titleDraft.isEmpty else { return }
                        do {
                            try session.renameCurrentScene(to: titleDraft)
                        } catch {
                            actionError = "\(error)"
                        }
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
                SceneRoleRow(session: session, role: role, sounds: session.favoriteSounds, onError: { actionError = $0 })
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

    @State private var showNewRoleSheet = false
    // `attachInstrument` can load a sample-based instrument onto the target role (see
    // `ImprovSession.applyRoleConfiguration`/`setInstrument`) — real disk I/O (and, for a
    // sample under an iCloud-synced folder not yet downloaded locally, a real network wait),
    // so it must not run on the main thread: same `Task { await Task.detached { ... } }`
    // bridge already used for LLM composing (`CompositionComposerView`), not a plain
    // synchronous call. Reported symptom before this fix: the whole app froze on iPhone while
    // attaching an instrument to a scene, if that instrument's sample file wasn't already
    // downloaded locally.
    @State private var isAttaching = false

    var body: some View {
        HStack {
            Text(session.labelWithChannel(track))
            Spacer()
            if isAttaching {
                ProgressView().controlSize(.small)
            } else {
                Menu(L10n.string(.appMenuAttacherA, session.currentLanguage)) {
                    ForEach(scene.roles) { role in
                        Button(label(for: role)) { attach(to: role) }
                    }
                    if !scene.roles.isEmpty { Divider() }
                    Button(L10n.string(.appButtonAjouterUnRoleEllipsis, session.currentLanguage)) { showNewRoleSheet = true }
                }
            }
        }
        .sheet(isPresented: $showNewRoleSheet) {
            NewRoleFromInstrumentSheet(session: session, track: track, onError: onError)
        }
    }

    /// Marks an already-occupied role so picking it reads as "take over this role" rather
    /// than looking like a free one — `attachInstrument` already displaces whatever instrument
    /// was there (freeing it) once picked, this just makes that outcome visible up front.
    private func label(for role: SceneRole) -> String {
        guard let attachedID = role.attachedTrackID, let occupant = session.tracks.first(where: { $0.id == attachedID }) else {
            return role.name
        }
        return L10n.string(.appFormatOccupeParRole, session.currentLanguage, role.name, session.labelWithChannel(occupant))
    }

    private func attach(to role: SceneRole) {
        isAttaching = true
        Task {
            let outcome = await Task.detached {
                Result { try session.attachInstrument(track.id, toRole: role.id) }
            }.value
            isAttaching = false
            if case .failure(let error) = outcome { onError("\(error)") }
            session.requestComputerKeyboardFocus()
        }
    }
}

/// The "Ajouter un rôle..." flow FROM a specific unassigned instrument — unlike
/// `SceneLayoutView`'s own bare "Ajouter un role" button (a name only, nothing to attach or
/// play through yet), this one already has a real source in hand, so it also offers picking a
/// sound right away and — since the whole point of attaching a source is to hear it — leaves
/// the new role ready to play: listening on, volume at 100%. A `.sheet` rather than the plain
/// `.alert` this used to be: an `alert` can't host a `Picker` on either platform.
private struct NewRoleFromInstrumentSheet: View {
    let session: ImprovSession
    let track: TrackInfo
    let onError: (String) -> Void

    @State private var name = ""
    @State private var selectedSoundID: String?
    @State private var isCreating = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.string(.appPlaceholderNomExPiano1, session.currentLanguage), text: $name)
                } header: {
                    Text(L10n.string(.fieldRole, session.currentLanguage))
                }
                Section {
                    if session.favoriteSounds.isEmpty {
                        Text(L10n.string(.appPlaceholderAucunSonFavoriParenthese, session.currentLanguage))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker(L10n.string(.fieldSon, session.currentLanguage), selection: $selectedSoundID) {
                            Text(L10n.string(.appButtonAucun, session.currentLanguage)).tag(String?.none)
                            ForEach(session.favoriteSounds) { sound in
                                Text(sound.displayName).tag(String?.some(sound.id))
                            }
                        }
                    }
                } header: {
                    Text(L10n.string(.fieldSon, session.currentLanguage))
                }
            }
            .disabled(isCreating)
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle(L10n.string(.appAlertNouveauRole, session.currentLanguage))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string(.appAnnuler, session.currentLanguage)) { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(L10n.string(.appButtonCreerEtAttacher, session.currentLanguage)) { createAndAttach() }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 260)
        #endif
    }

    /// `setSceneRoleVolume(..., volume: 1.0)` duplicates `SceneRole.init`'s own default — kept
    /// explicit anyway, since this screen's whole point is "this role is ready to play right
    /// now," not just "this role exists at its constructor defaults."
    ///
    /// Runs off the main thread (same `Task { await Task.detached { ... } }` bridge as
    /// `UnassignedInstrumentRow.attach(to:)`): `attachInstrument`/`setSceneRoleSound` can load
    /// a sample-based instrument, real disk/network I/O that must not block the UI thread.
    private func createAndAttach() {
        isCreating = true
        let selectedSound = session.favoriteSounds.first(where: { $0.id == selectedSoundID })
        let roleName = name.isEmpty ? L10n.string(.fieldRole, session.currentLanguage) : name
        Task {
            let outcome = await Task.detached {
                Result {
                    let roleID = try session.addSceneRole(name: roleName)
                    try session.attachInstrument(track.id, toRole: roleID)
                    if let selectedSound {
                        try session.setSceneRoleSound(roleID, soundName: selectedSound.path, preset: selectedSound.preset)
                    }
                    try session.setSceneRoleListening(roleID, isListening: true)
                    try session.setSceneRoleVolume(roleID, volume: 1.0)
                }
            }.value
            isCreating = false
            if case .failure(let error) = outcome { onError("\(error)") }
            session.requestComputerKeyboardFocus()
            dismiss()
        }
    }
}

private struct SceneRoleRow: View {
    let session: ImprovSession
    let role: SceneRole
    let sounds: [ImprovSession.FavoriteSound]
    let onError: (String) -> Void

    // Both actions below can load a sample-based instrument (`setInstrument`, called from
    // `setSceneRoleSound`/`attachInstrument`'s own `applyRoleConfiguration`) — real disk I/O,
    // and a real network wait for a sample under an iCloud-synced folder not yet downloaded
    // locally — so neither runs synchronously on the main thread anymore. Same
    // `Task { await Task.detached { ... } }` bridge as `UnassignedInstrumentRow.attach(to:)`.
    @State private var isBusy = false

    private func setSound(_ sound: ImprovSession.FavoriteSound?) {
        isBusy = true
        Task {
            let outcome = await Task.detached {
                Result { try session.setSceneRoleSound(role.id, soundName: sound?.path, preset: sound?.preset) }
            }.value
            isBusy = false
            if case .failure(let error) = outcome { onError("\(error)") }
            session.requestComputerKeyboardFocus()
        }
    }

    private func attach(_ trackID: TrackID) {
        isBusy = true
        Task {
            let outcome = await Task.detached {
                Result { try session.attachInstrument(trackID, toRole: role.id) }
            }.value
            isBusy = false
            if case .failure(let error) = outcome { onError("\(error)") }
            session.requestComputerKeyboardFocus()
        }
    }

    private func detach() {
        do {
            try session.detachInstrument(fromRole: role.id)
        } catch {
            onError("\(error)")
        }
        session.requestComputerKeyboardFocus()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(role.name).font(.headline)
                Spacer()
                // A real dropdown instead of plain "libre" text: every currently-unassigned
                // instrument is reachable directly from the role's own row, not just from the
                // "Instruments non affectes" block's own "Attacher a..." menu.
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Menu {
                        if role.attachedTrackID != nil {
                            Button(L10n.string(.appButtonDetacher, session.currentLanguage), role: .destructive) { detach() }
                        }
                        ForEach(session.unassignedInstruments()) { track in
                            Button(session.labelWithChannel(track)) { attach(track.id) }
                        }
                    } label: {
                        if let trackID = role.attachedTrackID, let track = session.tracks.first(where: { $0.id == trackID }) {
                            Text(session.labelWithChannel(track)).foregroundStyle(.green)
                        } else {
                            Text(L10n.string(.appLabelLibre, session.currentLanguage)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack {
                Text(L10n.string(.fieldSon, session.currentLanguage))
                Spacer()
                if isBusy {
                    ProgressView().controlSize(.small)
                } else if sounds.isEmpty {
                    Text(L10n.string(.appPlaceholderAucunSonFavoriParenthese, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
                } else {
                    Menu(role.soundName.map { session.displayName(forSamplePath: $0, preset: role.soundPreset) } ?? L10n.string(.appButtonAucun, session.currentLanguage)) {
                        Button(L10n.string(.appButtonAucun, session.currentLanguage)) { setSound(nil) }
                        ForEach(sounds) { sound in
                            Button(sound.displayName) { setSound(sound) }
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
