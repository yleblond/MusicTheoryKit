import SwiftUI
import UniformTypeIdentifiers
import AppCore
import JamShackUI
import Localization
import SoundFontModel

/// "Bibliotheque" sub-tab of "Sons": curates `session.soundFonts` (the hash-indexed soundfont
/// library — see `SoundFontLibrary`/`ImprovSession.startSoundFontLibrary`) into a small, named
/// set worth actually picking from elsewhere. Shows EVERY known soundfont, unlike
/// `PiecesPlayView`/`GuideEditionView`/`SceneLayoutView`'s sound pickers (which show only
/// favorites, via `session.favoriteSounds`) — this is the one screen where the full, possibly
/// huge, library list needs to be visible at all, so favorites can be chosen from it in the
/// first place (see `FavoriteSoundsView` for the favorites-only counterpart).
///
/// A soundfont known to the index isn't necessarily downloaded on THIS device (a `.synced`
/// entry discovered via iCloud Drive might not be materialized here yet — see
/// `ImprovSession.soundFontPath(forHash:)`) — this screen shows a sync/download badge and file
/// size per soundfont, lets the user download one on demand, and lets them delete one entirely
/// (see `ImprovSession.deleteSoundFont(hash:)` for what that means for a `.synced` entry).
///
/// Two-column browser, not a flat list: a `.sf2` can bundle dozens of presets (a full General
/// MIDI bank), and a favorite/alias/test always applies to one SPECIFIC sound within a file,
/// never to the file as a whole — so the left column picks the FILE, the right column picks
/// (and curates) one of ITS sounds.
///
/// Storage-profile/threshold management and the destructive "Nettoyer la bibliothèque" reset
/// live in the sibling "Stockage" tab (`SoundStorageView`), not here — this screen is scoped to
/// browsing/importing/curating files.
struct SoundLibraryView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge
    let controller: SoundTestModeController

    private enum Screen { case list, detail }

    @State private var screen: Screen = .list
    @State private var fileSearchText = ""
    @State private var actionError: String?

    // MARK: - Import
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var showCatalog = false

    // MARK: - File/sound navigation
    @State private var selectedHash: String?
    @State private var soundRows: [SoundRow] = []
    @State private var soundSearchText = ""
    /// Identifies the row currently being alias-edited as `"<hash>|<row.id>"` (not just
    /// `row.id`) so switching files can never collide with a same-shaped id in the new file's
    /// own row list (e.g. two different single-preset files both use `row.id == "_default"`).
    @State private var editingAliasFor: String?
    @State private var aliasDraft = ""
    @State private var downloadingHash: String?
    /// Hash pending a delete confirmation — one shared alert instead of one per row.
    @State private var pendingDeleteHash: String?
    /// Hash currently moving between the synced/local-only folders (see
    /// `ImprovSession.setSoundFontSyncPreference`) — shows a spinner instead of the "Partage"
    /// toggle while in flight, and prevents a duplicate concurrent move.
    @State private var changingSyncPreferenceHash: String?
    /// The entry the info sheet is showing, if any (see `SoundFontInfoSheet`).
    @State private var infoEntry: SoundFontEntry?

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
            if let controllerError = controller.actionError {
                Text(controllerError).foregroundStyle(.red).font(.caption).padding(.horizontal).padding(.top, 4)
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
                // the shared test-mode column (see `TestModeColumn`).
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
                            #if os(macOS)
                            .formStyle(.grouped)
                            #endif
                        Divider()
                        TestModeColumn(session: session, bridge: bridge, controller: controller)
                    }
                }
            }
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
        .alert(
            L10n.string(.appAlertSupprimerSoundFont, session.currentLanguage),
            isPresented: Binding(get: { pendingDeleteHash != nil }, set: { if !$0 { pendingDeleteHash = nil } })
        ) {
            Button(L10n.string(.appButtonSupprimer, session.currentLanguage), role: .destructive) {
                if let hash = pendingDeleteHash { deleteSoundFont(hash) }
                pendingDeleteHash = nil
            }
            Button(L10n.string(.appAnnuler, session.currentLanguage), role: .cancel) { pendingDeleteHash = nil }
        } message: {
            Text(L10n.string(.appHintSupprimerSoundFont, session.currentLanguage))
        }
        .sheet(item: $infoEntry) { entry in
            SoundFontInfoSheet(session: session, entry: entry, isDownloaded: session.soundFontPath(forHash: entry.hash) != nil)
        }
        .sheet(isPresented: $showCatalog) {
            SoundFontCatalogView(session: session)
        }
    }

    // MARK: - Import

    /// Always imports `.localOnly` — the simplest, safest default (never spends the user's
    /// iCloud quota without being asked) and the only choice this button itself makes; sharing a
    /// soundfont across devices afterward is one tap away via the "Partage" toggle on its row
    /// (see `toggleSyncPreference`), so there's no need for a picker/popup at import time too.
    private func importFile(at url: URL) {
        guard !isImporting else { return }
        isImporting = true
        Task {
            // Yields once so SwiftUI actually paints the spinner above before the import call
            // below blocks this thread for however long hashing+copying the file takes. That
            // call itself must run on THIS (main) thread/actor, not a detached background one:
            // `ImprovSession`'s `modelContext` is thread-confined to wherever it was created
            // (the main thread — see `ImprovSession.modelContainer`'s own doc comment), and
            // running a SwiftData mutation from a different thread at the same time as anything
            // else touching the same context is exactly the kind of race that can silently drop
            // or corrupt records — confirmed the hard way (soundfonts vanishing after a sync
            // toggle) before this fix.
            await Task.yield()
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
                isImporting = false
            }
            do {
                try session.importSoundFont(at: url, syncPreference: .localOnly)
            } catch {
                actionError = "\(error)"
            }
        }
    }

    // MARK: - Files column

    @ViewBuilder
    private var filesColumnContent: some View {
        Section {
            HStack {
                Button {
                    showFileImporter = true
                } label: {
                    if isImporting {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    } else {
                        Label(L10n.string(.appButtonImporter, session.currentLanguage), systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isImporting)

                // Same hierarchical level as "Importer", never behind it — the catalog is a
                // convenience that downloads a file the app already knows about, not a
                // replacement for bringing your own (see `SoundFontCatalogView`'s own doc
                // comment). Side by side with "Importer" (equal width) rather than stacked.
                Button {
                    showCatalog = true
                } label: {
                    Label(L10n.string(.appButtonParcourirCatalogue, session.currentLanguage), systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
            }
            #if os(macOS)
            .buttonStyle(.bordered)
            #endif
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
                ForEach(filteredSoundFonts) { entry in
                    fileRow(entry)
                }
            } header: {
                Text(L10n.string(.appFormatFichiersCompte, session.currentLanguage, filteredSoundFonts.count, session.soundFonts.count))
            } footer: {
                Text(L10n.string(.appHintSyncBadgeToggle, session.currentLanguage))
            }
        }
    }

    @ViewBuilder
    private func fileRow(_ entry: SoundFontEntry) -> some View {
        let isDownloaded = session.soundFontPath(forHash: entry.hash) != nil
        HStack {
            Button {
                selectFile(entry.hash)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayName)
                            .foregroundStyle(selectedHash == entry.hash ? Color.accentColor : .primary)
                        Text("\(syncStatusText(entry: entry, isDownloaded: isDownloaded)) — \(ByteCountFormatter.string(fromByteCount: entry.fileSize, countStyle: .file))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if entry.hash == controller.currentlyTestedHash {
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

            Button {
                infoEntry = entry
            } label: {
                Image(systemName: "info.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.borderless)

            if changingSyncPreferenceHash == entry.hash {
                ProgressView().controlSize(.small)
            } else {
                // The label sits immediately beside the switch it belongs to (its own `HStack`,
                // tight spacing) rather than relying on `Toggle`'s built-in label layout, which
                // can end up reading closer to whatever text precedes it in the row than to its
                // own switch.
                HStack(spacing: 4) {
                    Text(L10n.string(.appToggleFichierPartage, session.currentLanguage)).font(.caption)
                    Toggle("", isOn: Binding(
                        get: { entry.syncPreference == .synced },
                        set: { _ in toggleSyncPreference(entry) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                // A `.synced` entry not yet downloaded here has nothing local to move to
                // local-only with — download it first (see `toggleSyncPreference`'s own doc
                // comment).
                .disabled(entry.syncPreference == .synced && !isDownloaded)
            }

            Button {
                pendingDeleteHash = entry.hash
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .tint(.red)
        }
    }

    private func syncStatusText(entry: SoundFontEntry, isDownloaded: Bool) -> String {
        switch entry.syncPreference {
        case .localOnly:
            return L10n.string(.appLabelLocalUniquement, session.currentLanguage)
        case .synced:
            return isDownloaded
                ? L10n.string(.appLabelSynchronise, session.currentLanguage)
                : L10n.string(.appLabelNonTelecharge, session.currentLanguage)
        }
    }

    /// Switches a soundfont between synced (iCloud Drive, every device signed into the account)
    /// and local-only (this device alone) — see `ImprovSession.setSoundFontSyncPreference` for
    /// exactly what moves. A `.synced` entry not yet downloaded here has nothing to move to
    /// local-only with, so the "Partage" toggle is disabled for that case at all (download it
    /// first). Deliberately NOT `Task.detached`: this touches `modelContext` (via
    /// `SoundFontLibrary`), which is thread-confined to the main thread/actor — see
    /// `importFile`'s own doc comment for the bug this class of mistake caused (soundfonts
    /// silently vanishing) before the fix.
    private func toggleSyncPreference(_ entry: SoundFontEntry) {
        guard changingSyncPreferenceHash == nil else { return }
        let newPreference: SoundFontSyncPreference = entry.syncPreference == .synced ? .localOnly : .synced
        changingSyncPreferenceHash = entry.hash
        Task {
            await Task.yield()
            defer { changingSyncPreferenceHash = nil }
            do {
                try session.setSoundFontSyncPreference(hash: entry.hash, to: newPreference)
            } catch {
                actionError = "\(error)"
            }
        }
    }

    /// Deliberately NOT `Task.detached` — `requestDownload` only kicks off an async system
    /// download (`startDownloadingUbiquitousItem`, returns immediately) and reads `soundFonts`,
    /// both of which belong on the same thread/actor as the rest of this session's state.
    private func downloadSoundFont(_ hash: String) {
        guard downloadingHash == nil else { return }
        downloadingHash = hash
        Task {
            await Task.yield()
            defer { downloadingHash = nil }
            do {
                try session.downloadSoundFont(hash: hash)
            } catch {
                actionError = "\(error)"
            }
        }
    }

    /// Deliberately NOT `Task.detached` — see `importFile`'s own doc comment: `deleteSoundFont`
    /// mutates `modelContext` directly, which must happen on the same thread/actor it was
    /// created on.
    private func deleteSoundFont(_ hash: String) {
        if selectedHash == hash {
            selectedHash = nil
            screen = .list
        }
        Task {
            await Task.yield()
            session.deleteSoundFont(hash: hash)
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

            if controller.isTestModeOn, controller.testSourceID != nil {
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
                } else if controller.testingSoundKey == editKey {
                    ProgressView().controlSize(.small)
                } else {
                    let isCurrent = hash == controller.currentlyTestedHash && row.preset == controller.currentlyTestedPreset
                    Button {
                        controller.testSound(hash: hash, preset: row.preset, key: editKey)
                    } label: {
                        Image(systemName: isCurrent ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .foregroundStyle(isCurrent ? .blue : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(controller.testingSoundKey != nil)
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
}
