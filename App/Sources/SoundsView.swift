import SwiftUI
import AppCore
import Localization

/// "Sons" sub-tab of the "JamShack" tab: curates `session.sampleFiles` (every .sf2/.dls/
/// .aupreset file found under "Sons (samples)", subfolders included — see
/// `ImprovSession.listSampleFiles`) into a small, named set worth actually picking from
/// elsewhere. Shows EVERY sound found, unlike `PiecesPlayView`/`RecordingPlayView`/
/// `SceneLayoutView`'s sound pickers (which show only favorites, via
/// `session.favoriteSampleFiles`) — this is the one screen where the full, possibly huge,
/// decompressed-library list needs to be visible at all, so favorites can be chosen from it in
/// the first place.
struct SoundsView: View {
    let session: ImprovSession

    @State private var searchText = ""
    @State private var actionError: String?
    @State private var editingAliasFor: String?
    @State private var aliasDraft = ""

    private var filteredSounds: [String] {
        guard !searchText.isEmpty else { return session.sampleFiles }
        return session.sampleFiles.filter { path in
            path.localizedCaseInsensitiveContains(searchText)
                || (session.soundAlias(forPath: path)?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            if session.sampleFiles.isEmpty {
                Section {
                    Text(L10n.string(.appPlaceholderAucunSonTrouve, session.currentLanguage, L10n.string(.appLabelDossierSons, session.currentLanguage)))
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    TextField(L10n.string(.appPlaceholderRechercherSonAlias, session.currentLanguage), text: $searchText)
                }
                Section {
                    ForEach(filteredSounds, id: \.self) { path in
                        soundRow(path)
                    }
                } header: {
                    Text(L10n.string(.appFormatSonsCompte, session.currentLanguage, filteredSounds.count, session.sampleFiles.count))
                } footer: {
                    Text(L10n.string(.appHintCocheEtoileFavoris, session.currentLanguage))
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    @ViewBuilder
    private func soundRow(_ path: String) -> some View {
        HStack {
            Button {
                toggleFavorite(path)
            } label: {
                Image(systemName: session.isSoundFavorite(path) ? "star.fill" : "star")
                    .foregroundStyle(session.isSoundFavorite(path) ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                if editingAliasFor == path {
                    TextField(L10n.string(.appFieldAlias, session.currentLanguage), text: $aliasDraft, onCommit: { commitAlias(path) })
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                } else {
                    Text(session.soundAlias(forPath: path) ?? path)
                    if session.soundAlias(forPath: path) != nil {
                        Text(path).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                if editingAliasFor == path {
                    commitAlias(path)
                } else {
                    aliasDraft = session.soundAlias(forPath: path) ?? ""
                    editingAliasFor = path
                }
            } label: {
                Image(systemName: editingAliasFor == path ? "checkmark.circle" : "pencil")
            }
            .buttonStyle(.borderless)
        }
    }

    private func toggleFavorite(_ path: String) {
        do {
            try session.setSoundFavorite(path, isFavorite: !session.isSoundFavorite(path))
        } catch {
            actionError = "\(error)"
        }
    }

    private func commitAlias(_ path: String) {
        do {
            try session.setSoundAlias(path, alias: aliasDraft)
        } catch {
            actionError = "\(error)"
        }
        editingAliasFor = nil
        aliasDraft = ""
    }
}

#Preview {
    SoundsView(session: ImprovSession())
}
