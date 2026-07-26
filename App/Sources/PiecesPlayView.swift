import SwiftUI
import AppCore
import Localization

/// "Play" sub-tab of the Morceaux tab: play/stop the currently-loaded piece, and pick which
/// sound it plays through — loading/choosing the piece itself happens in the "Fichier" sub-tab.
struct PiecesPlayView: View {
    let session: ImprovSession

    @State private var actionError: String?

    var body: some View {
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
            if session.favoriteSampleFiles.isEmpty {
                Text(L10n.string(.appPlaceholderAucunSonFavori, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(session.favoriteSampleFiles, id: \.self) { name in
                    Button(session.displayName(forSamplePath: name)) {
                        do {
                            try session.loadSample(named: name)
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
            }
        } header: {
            Text(L10n.string(.appHeadingSonDeLecture, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintSonParDefaut, session.currentLanguage))
        }
    }
}

#Preview {
    PiecesPlayView(session: ImprovSession())
}
