import SwiftUI
import AppCore

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
                Text("Aucun morceau charge — va dans l'onglet Fichier.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Jouer")
        }
    }

    @ViewBuilder
    private var soundSection: some View {
        Section {
            if session.favoriteSampleFiles.isEmpty {
                Text("Aucun son favori — JamShack > Sons pour en marquer.").font(.caption).foregroundStyle(.secondary)
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
            Text("Son de lecture")
        } footer: {
            Text("Son par defaut (synthese) si aucun choisi.")
        }
    }
}

#Preview {
    PiecesPlayView(session: ImprovSession())
}
