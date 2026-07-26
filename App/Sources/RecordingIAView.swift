import SwiftUI
import AppCore
import LLMEngine
import Localization

/// "IA" sub-tab of the Enregistrement tab: compose a piece from the current recording via the
/// active LLM connection (see the "JamShack" tab's own "LLM" sub-tab).
struct RecordingIAView: View {
    let session: ImprovSession

    @State private var actionError: String?
    @State private var composeCandidateCount = "1"
    @State private var composeTitle = ""
    @State private var isComposing = false
    @State private var composeResultMessage: String?

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            if session.currentSoundTrack != nil {
                composeSection
            } else {
                Section { Text(L10n.string(.appPlaceholderAucunEnregistrementRecord, session.currentLanguage)).foregroundStyle(.secondary) }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
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
    RecordingIAView(session: ImprovSession())
}
