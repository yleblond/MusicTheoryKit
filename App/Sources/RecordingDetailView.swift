import SwiftUI
import AppCore
import SoundTrackModel
import LLMEngine
import Localization

/// Screen 2 of the Enregistrements tab: play/stop the current recording (the sound it plays
/// through is derived automatically from the active scene's own attached instrument/sound, see
/// `ImprovSession.applyCurrentSceneSoundToSoundTrackPlayer`, applied once when this view appears)
/// and compose a piece from it via the active LLM connection (see the "JamShack" tab's own "LLM"
/// sub-tab) — merges what used to be two separate sub-tabs (`RecordingPlayView`/`RecordingIAView`)
/// into one screen, per explicit user request. Recording happens on Studio's own "Live" sub-tab
/// (`RunScreen`); loading a previously-saved recording happens in screen 1, `RecordingFileView`.
/// `onBackToList` returns to screen 1.
struct RecordingDetailView: View {
    let session: ImprovSession
    let onBackToList: () -> Void

    @State private var actionError: String?
    @State private var composeCandidateCount = "1"
    @State private var composeTitle = ""
    @State private var isComposing = false
    @State private var composeResultMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBackToList()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(L10n.string(.appHeadingDossierSoundtracks, session.currentLanguage))
                Spacer()
            }
            .padding([.horizontal, .top])
            Form {
                if let actionError {
                    Section { Text(actionError).foregroundStyle(.red).font(.caption) }
                }
                if let soundTrack = session.currentSoundTrack {
                    playSection(soundTrack)
                    composeSection
                } else {
                    Section { Text(L10n.string(.appPlaceholderAucunEnregistrementRecordFichier, session.currentLanguage)).foregroundStyle(.secondary) }
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
        }
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

    @ViewBuilder
    private var composeSection: some View {
        Section {
            TextField(L10n.string(.appPlaceholderTitreOptionnel, session.currentLanguage), text: $composeTitle)
            TextField(L10n.string(.fieldNombreCandidats, session.currentLanguage), text: $composeCandidateCount)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            if isComposing {
                HStack { ProgressView(); Text(L10n.string(.appStatusCompositionEnCours, session.currentLanguage)) }
            } else {
                Button(L10n.string(.appButtonComposerDepuisEnregistrement, session.currentLanguage)) { compose() }
            }
            if let composeResultMessage {
                Text(composeResultMessage).font(.caption).foregroundStyle(.green)
            }
        } header: {
            Text(L10n.string(.appHeadingCompositionIADepuisEnregistrement, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintUtiliseConnexionLLMEtDossier, session.currentLanguage))
        }
    }

    private func compose() {
        composeResultMessage = nil
        actionError = nil
        isComposing = true
        let count = Int(composeCandidateCount) ?? 1
        let title = composeTitle.isEmpty ? nil : composeTitle
        Task {
            let outcome = await Task.detached {
                Result { try session.composeSoundTrackToPieces(candidateCount: count, title: title) }
            }.value
            isComposing = false
            switch outcome {
            case .success(let paths):
                composeResultMessage = "\(paths.count) candidat(s) sauvegarde(s)."
            case .failure(let error):
                actionError = "\(error)"
            }
        }
    }
}

#Preview {
    RecordingDetailView(session: ImprovSession(), onBackToList: {})
}
