import SwiftUI
import UniformTypeIdentifiers
import AppCore
import JamShackUI
import Localization
import SoundFontModel

/// "Sons" sub-tab of the "JamShack" tab: curates `session.soundFonts` (the hash-indexed
/// soundfont library — see `SoundFontLibrary`/`ImprovSession.startSoundFontLibrary`) into a
/// small, named set worth actually picking from elsewhere. Shows EVERY known soundfont, unlike
/// `PiecesPlayView`/`GuideEditionView`/`SceneLayoutView`'s sound pickers (which show only
/// favorites, via `session.favoriteSounds`) — this is the one screen where the full, possibly
/// huge, library list needs to be visible at all, so favorites can be chosen from it in the
/// first place.
///
/// A soundfont known to the index isn't necessarily downloaded on THIS device (a `.synced`
/// entry discovered via iCloud Drive might not be materialized here yet — see
/// `ImprovSession.soundFontPath(forHash:)`) — this screen shows a sync/download badge per
/// soundfont and lets the user download one on demand, instead of assuming every listed
/// soundfont can be played immediately.
///
/// Two-column browser, not a flat list: a `.sf2` can bundle dozens of presets (a full General
/// MIDI bank), and a favorite/alias/test always applies to one SPECIFIC sound within a file,
/// never to the file as a whole — so the left column picks the FILE, the right column picks
/// (and curates) one of ITS sounds.
struct SoundsView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge
    /// Whether this screen is genuinely the one visible right now — driven by `JamShackView`
    /// (its own `subTab == .sons`) combined with `ContentView`'s own active-tab check, NOT by
    /// `.onAppear`/`.onDisappear`: those are unreliable here, since `TabView` on macOS
    /// (`.sidebarAdaptable`) keeps every tab's content alive in the background rather than
    /// tearing it down on switch, so `.onDisappear` was never firing when leaving this screen
    /// for a DIFFERENT main tab (only when switching JamShack's own sub-tabs, which really does
    /// replace the view). Real bug this caused: test mode (and the tracks it pauses/resumes,
    /// including any scene's MIDI-sourced roles) stayed stuck active/paused indefinitely after
    /// leaving for another tab.
    let isActive: Bool

    private enum Screen { case list, detail }

    @State private var screen: Screen = .list
    @State private var fileSearchText = ""
    @State private var actionError: String?

    // MARK: - Import
    @State private var showFileImporter = false
    @State private var importSyncPreference: SoundFontSyncPreference = .localOnly
    @State private var isImporting = false

    // MARK: - Storage profile
    @State private var storageProfile: DeviceStorageProfile = DeviceStorageProfile.current

    // MARK: - File/sound navigation
    @State private var selectedHash: String?
    @State private var soundRows: [SoundRow] = []
    @State private var soundSearchText = ""
    /// Identifies the row currently being alias-edited as `"<hash>|<row.id>"` (not just
    /// `row.id`) so switching files can never collide with a same-shaped id in the new file's
    /// own row list (e.g. two different single-preset files both use `row.id == "_default"`).
    @State private var editingAliasFor: String?
    @State private var aliasDraft = ""

    // MARK: - Sound test mode
    @State private var isTestModeOn = false
    @State private var testSourceID: TrackID?
    /// Whether `testSourceID` was already listening BEFORE test mode picked it — so leaving
    /// test mode restores it to that same state instead of unconditionally stopping it (it
    /// might be the computer keyboard's always-on startup track, for instance).
    @State private var testSourceWasAlreadyListening = false
    /// Every other track that WAS listening when a test source was chosen — paused for the
    /// duration of the test (the user's explicit ask: avoid double-detection confusion from
    /// several tracks reacting to the same notes at once) and restarted once test mode ends
    /// or the source changes.
    @State private var pausedTrackIDs: Set<TrackID> = []
    /// The test source's own instrument, exactly as it was BEFORE testing touched it — restored
    /// on every source switch/test-mode exit so browsing sounds here can never permanently
    /// override what the active scene actually defines for that track (the user's own reported
    /// bug: a sound tried here stuck around after leaving this screen). `nil` name means no
    /// instrument was loaded at all, restored as "muted" (`testSourceOriginalSoundEnabled`)
    /// rather than left on whatever was last tested.
    @State private var testSourceOriginalInstrumentName: String?
    @State private var testSourceOriginalInstrumentPreset: SoundFontPresetIdentity?
    @State private var testSourceOriginalSoundEnabled = false
    /// Whether `ImprovSession.computerKeyboardInputEnabled` was already on before this screen
    /// turned test mode on (see `setTestMode`) — so leaving restores it to that same state
    /// instead of unconditionally turning it back off.
    @State private var computerKeyboardWasEnabledBeforeTestMode = false
    /// `"<hash>|<row.id>"` of the sound row a `testSound` call is currently loading, `nil`
    /// otherwise — `setInstrument` (see `testSound`) does real disk I/O (and, for a sample
    /// under an iCloud-synced folder not yet downloaded locally, a real network wait), so it
    /// must not run on the main thread. Also doubles as a simple lock: a second tap while one
    /// is already in flight is ignored rather than racing the same `SamplerUnit`.
    @State private var testingSoundKey: String?
    /// Same reasoning as `testingSoundKey`, for `applyTestSource`'s own instrument-restore step.
    @State private var isChangingTestSource = false
    /// Hash currently being downloaded (see `downloadSoundFont`) — shows a spinner instead of
    /// the download button while in flight, and prevents a duplicate concurrent request.
    @State private var downloadingHash: String?

    /// One row in the right-hand "sounds of the selected file" column — either a real preset
    /// read from a multi-preset `.sf2` (see `SoundFontPresetReader`), or the single stand-in
    /// row used for a `.dls` (no preset enumeration possible) and for a `.sf2` the reader
    /// couldn't parse (`preset == nil` either way means "this file's own default sound").
    private struct SoundRow: Identifiable {
        let preset: SoundFontPresetIdentity?
        let originalName: String
        var id: String {
            guard let preset else { return "_default" }
            return "\(preset.program):\(preset.bank)"
        }
    }

    /// Local, sound-capable tracks only — the same "clavier ordinateur / MIDI" choices the
    /// rest of the app already exposes as live-input sources. Excludes `.microphone` (can
    /// never have sound, feedback risk — see `TrackInfo.canHaveSound`'s doc comment) and
    /// `.webKeyboard`/`.remote` (not something to attach a local sample to for a quick test).
    private var testableSources: [TrackInfo] {
        session.tracks.filter { track in
            switch track.id {
            case .computerKeyboard, .midiMerged, .midiSource: return true
            default: return false
            }
        }
    }

    private var testTrackState: WebConsoleTrackState? {
        guard let wireID = testSourceID?.wireIDText else { return nil }
        return bridge.state.tracks.first { $0.id == wireID }
    }

    /// The test source's own track — read directly rather than cached separately, so
    /// `currentlyTestedHash`/`currentlyTestedPreset` can never drift from what's actually
    /// loaded (both `instrumentName`/`instrumentPreset` are only ever set by `setInstrument`).
    private var testTrack: TrackInfo? {
        guard let testSourceID else { return nil }
        return session.tracks.first { $0.id == testSourceID }
    }

    /// `setInstrument` stores whatever absolute path was loaded — resolve it back to a hash by
    /// matching the index, so the "currently playing" badge can key off `selectedHash`/`row.id`
    /// like everything else here, instead of carrying a second, path-based identity around.
    private var currentlyTestedHash: String? {
        guard let path = testTrack?.instrumentName else { return nil }
        return session.soundFonts.first { session.soundFontPath(forHash: $0.hash) == path }?.hash
    }
    private var currentlyTestedPreset: SoundFontPresetIdentity? { testTrack?.instrumentPreset }

    private var filteredSoundFonts: [SoundFontEntry] {
        let all = session.soundFonts.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        guard !fileSearchText.isEmpty else { return all }
        return all.filter {
            $0.displayName.localizedCaseInsensitiveContains(fileSearchText)
                || $0.fileName.localizedCaseInsensitiveContains(fileSearchText)
                || $0.userTags.contains { $0.localizedCaseInsensitiveContains(fileSearchText) }
        }
    }

    private var selectedSoundFont: SoundFontEntry? {
        guard let selectedHash else { return nil }
        return session.soundFonts.first { $0.hash == selectedHash }
    }

    private var filteredSoundRows: [SoundRow] {
        guard !soundSearchText.isEmpty, let selectedHash else { return soundRows }
        return soundRows.filter { row in
            row.originalName.localizedCaseInsensitiveContains(soundSearchText)
                || (session.soundAlias(forHash: selectedHash, preset: row.preset)?
                    .localizedCaseInsensitiveContains(soundSearchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let actionError {
                Text(actionError).foregroundStyle(.red).font(.caption).padding(.horizontal).padding(.top, 8)
            }
            switch screen {
            case .list:
                // Screen 1: pick a soundfont — a single, compact column instead of the old
                // always-visible 3-column layout.
                Form { filesColumnContent }
                    #if os(macOS)
                    .formStyle(.grouped)
                    #endif
                    // Drag & drop straight from Finder/Files — essential on macOS, appreciated
                    // on iPad (see `KnowledgeBase/SoundfontMgt/soundfontmgt.txt`). Each dropped
                    // item goes through the exact same `importFile(at:)` path as `.fileImporter`.
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        for provider in providers {
                            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                                guard let url else { return }
                                DispatchQueue.main.async { importFile(at: url) }
                            }
                        }
                        return !providers.isEmpty
                    }
            case .detail:
                // Screen 2: curate/test the selected file's sounds. Left: its sounds. Right:
                // the test-mode controls (source picker, keyboard, chord/mode commentary) —
                // same "Form / Divider / Form" split `SceneLayoutView` already uses for its
                // instruments/roles columns.
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            screen = .list
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel(L10n.string(.appHeadingFichiersSoundfont, session.currentLanguage))
                        Spacer()
                    }
                    .padding([.horizontal, .top])
                    HStack(alignment: .top, spacing: 0) {
                        Form { soundsColumnContent }
                        Divider()
                        Form { testModeSection }
                    }
                    #if os(macOS)
                    .formStyle(.grouped)
                    #endif
                }
            }
        }
        // `initial: true` covers the very first appearance too (this screen's whole purpose is
        // browsing/testing sounds, so it starts already in test mode with the computer keyboard
        // as the source, per explicit user request) — see `isActive`'s own doc comment for why
        // this reacts to that flag instead of `.onAppear`/`.onDisappear`. Arms regardless of
        // which screen (list/detail) is currently showing — only the test-mode UI itself is
        // screen-2-only, for a more compact screen 1.
        .onChange(of: isActive, initial: true) { _, active in
            setTestMode(active)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [
                UTType(importedAs: "com.jamshack.soundfont2"),
                UTType(importedAs: "com.jamshack.downloadable-sound"),
            ]
        ) { result in
            switch result {
            case .success(let url): importFile(at: url)
            case .failure(let error): actionError = "\(error)"
            }
        }
    }

    // MARK: - Import

    private func importFile(at url: URL) {
        guard !isImporting else { return }
        isImporting = true
        let accessed = url.startAccessingSecurityScopedResource()
        let syncPreference = importSyncPreference
        Task {
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
                isImporting = false
            }
            let outcome = await Task.detached {
                Result { try session.importSoundFont(at: url, syncPreference: syncPreference) }
            }.value
            if case .failure(let error) = outcome { actionError = "\(error)" }
        }
    }

    // MARK: - Files column

    @ViewBuilder
    private var filesColumnContent: some View {
        Section {
            Button {
                showFileImporter = true
            } label: {
                if isImporting {
                    ProgressView().controlSize(.small)
                } else {
                    Label(L10n.string(.appButtonImporter, session.currentLanguage), systemImage: "square.and.arrow.down")
                }
            }
            .disabled(isImporting)
            Picker(L10n.string(.fieldSon, session.currentLanguage), selection: $importSyncPreference) {
                Text(L10n.string(.appLabelSynchronise, session.currentLanguage)).tag(SoundFontSyncPreference.synced)
                Text(L10n.string(.appLabelLocalUniquement, session.currentLanguage)).tag(SoundFontSyncPreference.localOnly)
            }
            .pickerStyle(.segmented)
        } header: {
            Text(L10n.string(.appHeadingFichiersSoundfont, session.currentLanguage))
        }

        if session.soundFonts.isEmpty {
            Section {
                Text(L10n.string(.appPlaceholderAucunSonTrouve, session.currentLanguage, L10n.string(.appLabelDossierSons, session.currentLanguage)))
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                TextField(L10n.string(.appPlaceholderRechercherFichier, session.currentLanguage), text: $fileSearchText)
            }
            Section {
                ForEach(filteredSoundFonts) { entry in
                    fileRow(entry)
                }
            } header: {
                Text(L10n.string(.appFormatFichiersCompte, session.currentLanguage, filteredSoundFonts.count, session.soundFonts.count))
            }
        }

        Section {
            Picker(L10n.string(.appHeadingProfilStockage, session.currentLanguage), selection: $storageProfile) {
                Text(L10n.string(.appOptionProfilEconome, session.currentLanguage)).tag(DeviceStorageProfile.economical)
                Text(L10n.string(.appOptionProfilStandard, session.currentLanguage)).tag(DeviceStorageProfile.standard)
                Text(L10n.string(.appOptionProfilGenereux, session.currentLanguage)).tag(DeviceStorageProfile.generous)
            }
            .onChange(of: storageProfile) { _, newValue in DeviceStorageProfile.current = newValue }
            Text(L10n.string(.appFormatEspaceDisqueLibre, session.currentLanguage, ByteCountFormatter.string(fromByteCount: DeviceFreeSpace.availableBytes(), countStyle: .file)))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(L10n.string(.appHeadingProfilStockage, session.currentLanguage))
        }
    }

    @ViewBuilder
    private func fileRow(_ entry: SoundFontEntry) -> some View {
        let isDownloaded = session.soundFontPath(forHash: entry.hash) != nil
        Button {
            selectFile(entry.hash)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .foregroundStyle(selectedHash == entry.hash ? Color.accentColor : .primary)
                    Text(syncBadgeText(entry: entry, isDownloaded: isDownloaded))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if entry.hash == currentlyTestedHash {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(.blue)
                }
                if !isDownloaded {
                    if downloadingHash == entry.hash {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(L10n.string(.appButtonTelecharger, session.currentLanguage)) {
                            downloadSoundFont(entry.hash)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func syncBadgeText(entry: SoundFontEntry, isDownloaded: Bool) -> String {
        switch entry.syncPreference {
        case .localOnly:
            return L10n.string(.appLabelLocalUniquement, session.currentLanguage)
        case .synced:
            return isDownloaded
                ? L10n.string(.appLabelSynchronise, session.currentLanguage)
                : L10n.string(.appLabelNonTelecharge, session.currentLanguage)
        }
    }

    private func downloadSoundFont(_ hash: String) {
        guard downloadingHash == nil else { return }
        downloadingHash = hash
        Task {
            let outcome = await Task.detached {
                Result { try session.downloadSoundFont(hash: hash) }
            }.value
            downloadingHash = nil
            if case .failure(let error) = outcome { actionError = "\(error)" }
        }
    }

    private func selectFile(_ hash: String) {
        if selectedHash != hash {
            selectedHash = hash
            soundSearchText = ""
            editingAliasFor = nil
            aliasDraft = ""
            loadSoundRows(for: hash)
        }
        screen = .detail
    }

    /// Reads straight from the already-indexed `SoundFontEntry.presets` — no disk I/O, unlike
    /// the old path-based equivalent this replaces, which had to re-parse the file every time a
    /// row was selected. This also means a `.synced` soundfont not yet downloaded on this
    /// device still shows its full preset list (only actually playing one requires the
    /// download).
    private func loadSoundRows(for hash: String) {
        guard let entry = session.soundFonts.first(where: { $0.hash == hash }) else {
            soundRows = []
            return
        }
        soundRows = entry.presets.isEmpty
            ? [SoundRow(preset: nil, originalName: entry.displayName)]
            : entry.presets.map { SoundRow(preset: $0.identity, originalName: $0.name) }
    }

    // MARK: - Sounds column (the selected file's own sounds)

    @ViewBuilder
    private var soundsColumnContent: some View {
        if let selectedHash, let selectedSoundFont {
            Section {
                TextField(L10n.string(.appPlaceholderRechercherSonAlias, session.currentLanguage), text: $soundSearchText)
            } header: {
                Text(selectedSoundFont.displayName)
            }
            Section {
                ForEach(filteredSoundRows) { row in
                    soundRow(selectedHash, row)
                }
            } header: {
                Text(L10n.string(.appFormatSonsCompte, session.currentLanguage, filteredSoundRows.count, soundRows.count))
            } footer: {
                Text(L10n.string(.appHintCocheEtoileFavoris, session.currentLanguage))
            }
        } else {
            Section {
                Text(L10n.string(.appPlaceholderChoisirFichierSons, session.currentLanguage)).foregroundStyle(.secondary)
            } header: {
                Text(L10n.string(.fieldSon, session.currentLanguage))
            }
        }
    }

    @ViewBuilder
    private func soundRow(_ hash: String, _ row: SoundRow) -> some View {
        let editKey = "\(hash)|\(row.id)"
        let isDownloaded = session.soundFontPath(forHash: hash) != nil
        HStack {
            Button {
                toggleFavorite(hash, row.preset)
            } label: {
                Image(systemName: session.isSoundFavorite(forHash: hash, preset: row.preset) ? "star.fill" : "star")
                    .foregroundStyle(session.isSoundFavorite(forHash: hash, preset: row.preset) ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)

            IconAssignmentButton(
                currentIcon: session.soundIcon(forHash: hash, preset: row.preset),
                defaultIcon: "music.note",
                canUseAI: session.currentLLMConnection != nil,
                language: session.currentLanguage,
                onSuggestAI: {
                    let icon = try session.suggestIcon(kind: "instrument", name: session.soundAlias(forHash: hash, preset: row.preset) ?? row.originalName)
                    try session.setSoundIcon(forHash: hash, preset: row.preset, iconSystemName: icon)
                },
                onPickManual: { icon in
                    try? session.setSoundIcon(forHash: hash, preset: row.preset, iconSystemName: icon)
                },
                onError: { actionError = $0 }
            )

            VStack(alignment: .leading, spacing: 2) {
                if editingAliasFor == editKey {
                    TextField(L10n.string(.appFieldAlias, session.currentLanguage), text: $aliasDraft, onCommit: { commitAlias(hash, row.preset, editKey) })
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                } else {
                    let alias = session.soundAlias(forHash: hash, preset: row.preset)
                    Text(alias ?? row.originalName)
                    if alias != nil {
                        Text(row.originalName).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if isTestModeOn, let testSourceID {
                if !isDownloaded {
                    if downloadingHash == hash {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            downloadSoundFont(hash)
                        } label: {
                            Image(systemName: "icloud.and.arrow.down")
                        }
                        .buttonStyle(.borderless)
                    }
                } else if testingSoundKey == editKey {
                    ProgressView().controlSize(.small)
                } else {
                    let isCurrent = hash == currentlyTestedHash && row.preset == currentlyTestedPreset
                    Button {
                        testSound(hash: hash, preset: row.preset, testSourceID: testSourceID, key: editKey)
                    } label: {
                        Image(systemName: isCurrent ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .foregroundStyle(isCurrent ? .blue : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(testingSoundKey != nil)
                }
            }

            Button {
                if editingAliasFor == editKey {
                    commitAlias(hash, row.preset, editKey)
                } else {
                    aliasDraft = session.soundAlias(forHash: hash, preset: row.preset) ?? ""
                    editingAliasFor = editKey
                }
            } label: {
                Image(systemName: editingAliasFor == editKey ? "checkmark.circle" : "pencil")
            }
            .buttonStyle(.borderless)
        }
    }

    private func toggleFavorite(_ hash: String, _ preset: SoundFontPresetIdentity?) {
        do {
            try session.setSoundFavorite(forHash: hash, preset: preset, isFavorite: !session.isSoundFavorite(forHash: hash, preset: preset))
        } catch {
            actionError = "\(error)"
        }
    }

    private func commitAlias(_ hash: String, _ preset: SoundFontPresetIdentity?, _ editKey: String) {
        do {
            try session.setSoundAlias(forHash: hash, preset: preset, alias: aliasDraft)
        } catch {
            actionError = "\(error)"
        }
        if editingAliasFor == editKey {
            editingAliasFor = nil
        }
        aliasDraft = ""
    }

    private func testSound(hash: String, preset: SoundFontPresetIdentity?, testSourceID: TrackID, key: String) {
        guard testingSoundKey == nil, let path = session.soundFontPath(forHash: hash) else { return }
        testingSoundKey = key
        Task {
            let outcome = await Task.detached {
                Result { try session.setInstrument(named: path, for: testSourceID, preset: preset) }
            }.value
            testingSoundKey = nil
            if case .failure(let error) = outcome { actionError = "\(error)" }
        }
    }

    // MARK: - Test mode column

    @ViewBuilder
    private var testModeSection: some View {
        Section {
            Toggle(L10n.string(.appToggleModeTestSon, session.currentLanguage), isOn: Binding(
                get: { isTestModeOn },
                set: { setTestMode($0) }
            ))
            if isTestModeOn {
                if isChangingTestSource {
                    ProgressView().controlSize(.small)
                } else {
                    Picker(L10n.string(.appFieldSourceTest, session.currentLanguage), selection: Binding(
                        get: { testSourceID },
                        set: { applyTestSource($0) }
                    )) {
                        Text(L10n.string(.appOptionAucuneFem, session.currentLanguage)).tag(TrackID?.none)
                        ForEach(testableSources) { track in
                            Text(session.labelWithChannel(track)).tag(TrackID?.some(track.id))
                        }
                    }
                }
                if let track = testTrackState {
                    AutoCenteredKeyboardView(
                        heldPitches: track.heldPitches,
                        palette: bridge.state.palette,
                        paletteTextColors: bridge.state.paletteTextColors
                    )
                    if let chordLabel = track.chordLabel {
                        Text(chordLabel).font(.headline).foregroundStyle(Color.accentColor)
                    }
                    if let modesLabel = track.modesLabel {
                        Text(modesLabel).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(L10n.string(.appPlaceholderChoisirSourceTest, session.currentLanguage))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L10n.string(.appHeadingTesterLeSon, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintTesterLeSon, session.currentLanguage))
        }
    }

    /// Idempotent (a repeated call with the same value is a no-op) — `.onAppear`/`.onDisappear`
    /// both call this unconditionally, so neither has to track whether the other already ran.
    private func setTestMode(_ enabled: Bool) {
        guard enabled != isTestModeOn else { return }
        isTestModeOn = enabled
        if enabled {
            computerKeyboardWasEnabledBeforeTestMode = session.computerKeyboardInputEnabled
            if !session.computerKeyboardInputEnabled {
                session.setComputerKeyboardInputEnabled(true)
            }
            // Computer keyboard as the default test source, per explicit user request — it's
            // also what makes the persistent keyboard bar appear (see `ContentView`).
            applyTestSource(.computerKeyboard)
        } else {
            applyTestSource(nil)
            if !computerKeyboardWasEnabledBeforeTestMode {
                session.setComputerKeyboardInputEnabled(false)
            }
        }
    }

    /// The one place `testSourceID` ever changes: restores the PREVIOUS source's own original
    /// sound (see `testSourceOriginalInstrumentName`'s doc comment) and whatever else was
    /// listening, then — if a new source was picked — snapshots ITS current sound so it can
    /// be restored the same way later, pauses every other currently-listening track, and
    /// starts/enables the new one. Symmetric handling of `nil` (test mode's own "Aucune" choice,
    /// and turning test mode off) is what makes leaving the sound list exactly as it was found
    /// always safe, not just on the common "toggle off" path.
    /// Restoring the previous test source's own instrument (below) can load a sample-based
    /// instrument via `setInstrument` — real disk I/O, so that one step runs off the main
    /// thread (`Task.detached`, same bridge as `testSound`/`SceneLayoutView`'s fixes). Every
    /// other step here stays exactly as before/in the same order — none of them touch a
    /// sample file — `setSoundEnabled(testSourceOriginalSoundEnabled, for: previous)` in
    /// particular must still run right after the restore, since it can override what the
    /// restore itself just set.
    private func applyTestSource(_ newSource: TrackID?) {
        isChangingTestSource = true
        Task {
            defer { isChangingTestSource = false }
            if let previous = testSourceID {
                if !testSourceWasAlreadyListening {
                    session.stopTrack(previous)
                }
                let originalName = testSourceOriginalInstrumentName
                let originalPreset = testSourceOriginalInstrumentPreset
                let originalSoundEnabled = testSourceOriginalSoundEnabled
                await Task.detached {
                    if let originalName {
                        try? session.setInstrument(named: originalName, for: previous, preset: originalPreset)
                    }
                    try? session.setSoundEnabled(originalSoundEnabled, for: previous)
                }.value
            }
            for id in pausedTrackIDs {
                do {
                    try session.startTrack(id)
                } catch {
                    actionError = "\(error)"
                }
            }
            pausedTrackIDs = []
            testSourceWasAlreadyListening = false
            testSourceID = newSource
            // The Picker used to reach `newSource` is a native pop-up control that otherwise
            // keeps SwiftUI keyboard focus for the rest of the session — see
            // `ImprovSession.requestComputerKeyboardFocus`'s own doc comment.
            session.requestComputerKeyboardFocus()

            guard let newSource else {
                testSourceOriginalInstrumentName = nil
                testSourceOriginalInstrumentPreset = nil
                testSourceOriginalSoundEnabled = false
                return
            }
            let newTrack = session.tracks.first { $0.id == newSource }
            testSourceOriginalInstrumentName = newTrack?.instrumentName
            testSourceOriginalInstrumentPreset = newTrack?.instrumentPreset
            testSourceOriginalSoundEnabled = newTrack?.soundEnabled ?? false
            testSourceWasAlreadyListening = newTrack?.isListening ?? false
            pausedTrackIDs = Set(session.tracks.filter { $0.isListening && $0.id != newSource }.map(\.id))
            for id in pausedTrackIDs {
                session.stopTrack(id)
            }
            do {
                try session.startTrack(newSource)
                try session.setSoundEnabled(true, for: newSource)
            } catch {
                actionError = "\(error)"
            }
        }
    }
}

#Preview {
    let session = ImprovSession()
    return SoundsView(session: session, bridge: SessionUIBridge(session: session), isActive: true)
}
