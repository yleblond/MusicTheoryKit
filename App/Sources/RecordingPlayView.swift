import SwiftUI
import AppCore
import SoundTrackModel

/// "Play" sub-tab of the Enregistrement tab: play/stop the current recording, and pick which
/// sound it plays through — recording/loading it happens in the sibling "Record"/"Fichier"
/// sub-tabs.
struct RecordingPlayView: View {
    let session: ImprovSession

    @State private var actionError: String?

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            if let soundTrack = session.currentSoundTrack {
                playSection(soundTrack)
                soundSection
            } else {
                Section { Text("Aucun enregistrement — va dans l'onglet Record ou Fichier.").foregroundStyle(.secondary) }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    @ViewBuilder
    private func playSection(_ soundTrack: SoundTrack) -> some View {
        Section {
            Text(soundTrack.title).font(.headline)
            Text("\(soundTrack.events.count) evenement(s), \(String(format: "%.1f", soundTrack.durationSeconds))s")
                .font(.caption).foregroundStyle(.secondary)
            PlaybackControlButton(
                isPlaying: session.isPlayingSoundTrack,
                onPlay: {
                    do {
                        try session.playSoundTrack()
                    } catch {
                        actionError = "\(error)"
                    }
                },
                onStop: { session.stopSoundTrackPlayback() }
            )
        } header: {
            Text("Enregistrement actuel")
        }
    }

    @ViewBuilder
    private var soundSection: some View {
        Section {
            if session.sampleFiles.isEmpty {
                Text("Aucun son trouve — JamShack > Dossiers > Sons (samples).").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(session.sampleFiles, id: \.self) { name in
                    Button(name) {
                        do {
                            try session.loadSoundTrackSample(named: name)
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
    RecordingPlayView(session: ImprovSession())
}
