import SwiftUI
import AppCore
import JamShackUI
import Localization
import SoundFontModel

/// "Favoris" sub-tab of "Sons": a flat list of every favorited sound (see
/// `ImprovSession.soundEntries`/`SoundEntry.isFavorite`), independent of which file each one
/// belongs to — the favorites-only counterpart of `SoundLibraryView`'s per-file browsing, same
/// test/rename capabilities, just flattened since a favorite is already a specific, named
/// choice the user made (no need to navigate file → preset to reach it again).
///
/// Unlike `ImprovSession.favoriteSounds` (used by `PiecesPlayView`/`SceneLayoutView`'s pickers,
/// which only ever want to show something immediately playable), this screen shows EVERY
/// favorite regardless of download state — a `.synced` favorite not yet materialized on this
/// device still appears here, with a download button instead of a test button, so marking
/// something a favorite on one device and finding it again on another always works.
struct FavoriteSoundsView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge
    let controller: SoundTestModeController

    @State private var searchText = ""
    @State private var actionError: String?
    @State private var editingAliasFor: String?
    @State private var aliasDraft = ""
    @State private var downloadingHash: String?

    /// One favorited (soundfont, preset) pair, joined against `session.soundFonts` for its
    /// display name/original preset name/file size — built fresh from `session.soundEntries` +
    /// `session.soundFonts` each time either changes, same "no separate cache to drift" approach
    /// `favoriteSounds` itself uses.
    private struct FavoriteRow: Identifiable {
        let hash: String
        let preset: SoundFontPresetIdentity?
        let fileDisplayName: String
        let originalName: String
        var id: String {
            guard let preset else { return "\(hash)|_default" }
            return "\(hash)|\(preset.program):\(preset.bank)"
        }
    }

    private var rows: [FavoriteRow] {
        let all = session.soundEntries.filter(\.isFavorite).compactMap { entry -> FavoriteRow? in
            guard let soundFont = session.soundFonts.first(where: { $0.hash == entry.soundFontHash }) else { return nil }
            let identity = entry.preset ?? SoundFontPresetIdentity(program: 0, bank: 0)
            let originalName = soundFont.presets.first { $0.identity == identity }?.name ?? soundFont.displayName
            return FavoriteRow(hash: entry.soundFontHash, preset: entry.preset, fileDisplayName: soundFont.displayName, originalName: originalName)
        }
        .sorted { (session.soundAlias(forHash: $0.hash, preset: $0.preset) ?? $0.originalName) < (session.soundAlias(forHash: $1.hash, preset: $1.preset) ?? $1.originalName) }
        guard !searchText.isEmpty else { return all }
        return all.filter { row in
            row.originalName.localizedCaseInsensitiveContains(searchText)
                || row.fileDisplayName.localizedCaseInsensitiveContains(searchText)
                || (session.soundAlias(forHash: row.hash, preset: row.preset)?.localizedCaseInsensitiveContains(searchText) ?? false)
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
            HStack(alignment: .top, spacing: 0) {
                Form { favoritesColumnContent }
                    #if os(macOS)
                    .formStyle(.grouped)
                    #endif
                Divider()
                TestModeColumn(session: session, bridge: bridge, controller: controller)
            }
        }
    }

    @ViewBuilder
    private var favoritesColumnContent: some View {
        if session.soundEntries.contains(where: \.isFavorite) {
            Section {
                TextField(L10n.string(.appPlaceholderRechercherSonAlias, session.currentLanguage), text: $searchText)
            } header: {
                Text(L10n.string(.appTabFavoris, session.currentLanguage))
            }
            Section {
                ForEach(rows) { row in
                    favoriteRow(row)
                }
            } header: {
                Text(L10n.string(.appFormatSonsCompte, session.currentLanguage, rows.count, rows.count))
            }
        } else {
            Section {
                Text(L10n.string(.appPlaceholderAucunFavori, session.currentLanguage)).foregroundStyle(.secondary)
            } header: {
                Text(L10n.string(.appTabFavoris, session.currentLanguage))
            }
        }
    }

    @ViewBuilder
    private func favoriteRow(_ row: FavoriteRow) -> some View {
        let editKey = row.id
        let isDownloaded = session.soundFontPath(forHash: row.hash) != nil
        HStack {
            Button {
                unfavorite(row)
            } label: {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }
            .buttonStyle(.borderless)

            IconAssignmentButton(
                currentIcon: session.soundIcon(forHash: row.hash, preset: row.preset),
                defaultIcon: "music.note",
                canUseAI: session.currentLLMConnection != nil,
                language: session.currentLanguage,
                onSuggestAI: {
                    let icon = try session.suggestIcon(kind: "instrument", name: session.soundAlias(forHash: row.hash, preset: row.preset) ?? row.originalName)
                    try session.setSoundIcon(forHash: row.hash, preset: row.preset, iconSystemName: icon)
                },
                onPickManual: { icon in
                    try? session.setSoundIcon(forHash: row.hash, preset: row.preset, iconSystemName: icon)
                },
                onError: { actionError = $0 }
            )

            VStack(alignment: .leading, spacing: 2) {
                if editingAliasFor == editKey {
                    TextField(L10n.string(.appFieldAlias, session.currentLanguage), text: $aliasDraft, onCommit: { commitAlias(row, editKey) })
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                } else {
                    let alias = session.soundAlias(forHash: row.hash, preset: row.preset)
                    Text(alias ?? "\(row.fileDisplayName) — \(row.originalName)")
                    if alias != nil {
                        Text("\(row.fileDisplayName) — \(row.originalName)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if controller.isTestModeOn, controller.testSourceID != nil {
                if !isDownloaded {
                    if downloadingHash == row.hash {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            downloadSoundFont(row.hash)
                        } label: {
                            Image(systemName: "icloud.and.arrow.down")
                        }
                        .buttonStyle(.borderless)
                    }
                } else if controller.testingSoundKey == editKey {
                    ProgressView().controlSize(.small)
                } else {
                    let isCurrent = row.hash == controller.currentlyTestedHash && row.preset == controller.currentlyTestedPreset
                    Button {
                        controller.testSound(hash: row.hash, preset: row.preset, key: editKey)
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
                    commitAlias(row, editKey)
                } else {
                    aliasDraft = session.soundAlias(forHash: row.hash, preset: row.preset) ?? ""
                    editingAliasFor = editKey
                }
            } label: {
                Image(systemName: editingAliasFor == editKey ? "checkmark.circle" : "pencil")
            }
            .buttonStyle(.borderless)
        }
    }

    private func unfavorite(_ row: FavoriteRow) {
        do {
            try session.setSoundFavorite(forHash: row.hash, preset: row.preset, isFavorite: false)
        } catch {
            actionError = "\(error)"
        }
    }

    private func commitAlias(_ row: FavoriteRow, _ editKey: String) {
        do {
            try session.setSoundAlias(forHash: row.hash, preset: row.preset, alias: aliasDraft)
        } catch {
            actionError = "\(error)"
        }
        if editingAliasFor == editKey {
            editingAliasFor = nil
        }
        aliasDraft = ""
    }

    /// Deliberately NOT `Task.detached` — `requestDownload` only kicks off an async system
    /// download (`startDownloadingUbiquitousItem`, returns immediately) and reads `soundFonts`,
    /// both of which belong on the same thread/actor `ImprovSession`'s `modelContext` is
    /// confined to (see `SoundLibraryView.importFile`'s own doc comment for why that matters —
    /// this class of mistake elsewhere caused soundfonts to silently vanish).
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
}
