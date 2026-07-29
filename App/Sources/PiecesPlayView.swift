import SwiftUI
import AppCore
import Localization

/// Screen 2 of the Morceaux tab: play/stop the currently-loaded piece, and pick which sound it
/// plays through — loading/choosing the piece itself happens in screen 1, `PiecesFileView`.
/// `onBackToList` returns to screen 1.
struct PiecesPlayView: View {
    let session: ImprovSession
    let onBackToList: () -> Void

    @State private var actionError: String?
    /// `session.loadSample` does real disk I/O (and, for a sample under an iCloud-synced
    /// folder not yet downloaded locally, a real network wait) — must not run on the main
    /// thread. Also the currently-loading sound's id, so only that one row shows a spinner.
    @State private var loadingSoundID: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBackToList()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(L10n.string(.appHeadingDossierMorceaux, session.currentLanguage))
                Spacer()
            }
            .padding([.horizontal, .top])
            Form {
                if let actionError {
                    Section { Text(actionError).foregroundStyle(.red).font(.caption) }
                }
                playSection
                soundSection
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
        }
    }

    @ViewBuilder
    private var playSection: some View {
        Section {
            if let piece = session.piece {
                Text(piece.title).font(.headline)
                PlaybackControlButton(
                    isPlaying: session.isPlaying,
                    language: session.currentLanguage,
                    onPlay: {
                        do {
                            try session.play()
                        } catch {
                            actionError = "\(error)"
                        }
                    },
                    onStop: { session.stopPlayback() }
                )
            } else {
                Text(L10n.string(.appPlaceholderAucunMorceauChargeOnglet, session.currentLanguage)).foregroundStyle(.secondary)
            }
        } header: {
            Text(L10n.string(.appHeadingJouer, session.currentLanguage))
        }
    }

    @ViewBuilder
    private var soundSection: some View {
        Section {
            if session.favoriteSounds.isEmpty {
                Text(L10n.string(.appPlaceholderAucunSonFavori, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(session.favoriteSounds) { sound in
                    if loadingSoundID == sound.id {
                        HStack { Text(sound.displayName); Spacer(); ProgressView().controlSize(.small) }
                    } else {
                        Button(sound.displayName) { loadSample(sound) }
                            .disabled(loadingSoundID != nil)
                    }
                }
            }
        } header: {
            Text(L10n.string(.appHeadingSonDeLecture, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintSonParDefaut, session.currentLanguage))
        }
    }

    private func loadSample(_ sound: ImprovSession.FavoriteSound) {
        guard loadingSoundID == nil else { return }
        loadingSoundID = sound.id
        Task {
            let outcome = await Task.detached {
                Result { try session.loadSample(named: sound.path, preset: sound.preset) }
            }.value
            loadingSoundID = nil
            if case .failure(let error) = outcome { actionError = "\(error)" }
        }
    }
}

#Preview {
    PiecesPlayView(session: ImprovSession(), onBackToList: {})
}
