import SwiftUI
import AppCore
import SoundTrackModel
import Localization

/// "Enregistrement actuel" sub-tab of the Enregistrements tab: play/stop the current recording —
/// the sound it plays through is no longer picked manually here (removed 2026-07-26): it's
/// derived automatically from the active scene's own attached instrument/sound (see
/// `ImprovSession.applyCurrentSceneSoundToSoundTrackPlayer`), applied once when this view
/// appears. Recording happens on Studio's own "Live" sub-tab (`RunScreen`); loading a
/// previously-saved one happens in the sibling "Fichier" sub-tab.
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
            } else {
                Section { Text(L10n.string(.appPlaceholderAucunEnregistrementRecordFichier, session.currentLanguage)).foregroundStyle(.secondary) }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .onAppear { session.applyCurrentSceneSoundToSoundTrackPlayer() }
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

}

#Preview {
    RecordingPlayView(session: ImprovSession())
}
