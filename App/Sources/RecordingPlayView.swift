import SwiftUI
import AppCore
import SoundTrackModel
import Localization

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
                Section { Text(L10n.string(.appPlaceholderAucunEnregistrementRecordFichier, session.currentLanguage)).foregroundStyle(.secondary) }
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
            Text(L10n.string(.appFormatEvenementsDuree, session.currentLanguage, "\(soundTrack.events.count)", String(format: "%.1f", soundTrack.durationSeconds)))
                .font(.caption).foregroundStyle(.secondary)
            PlaybackControlButton(
                isPlaying: session.isPlayingSoundTrack,
                language: session.currentLanguage,
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
            Text(L10n.string(.appHeadingEnregistrementActuel, session.currentLanguage))
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
                            try session.loadSoundTrackSample(named: name)
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
    RecordingPlayView(session: ImprovSession())
}
