import SwiftUI
import AppCore
import Localization

/// "Fichier" sub-tab of the Enregistrements tab: the store-based soundtrack browser (list/
/// load/save/delete — soundtracks live in a private SwiftData store, no folder to pick
/// anymore).
struct RecordingFileView: View {
    let session: ImprovSession
    /// Called after a soundtrack is actually loaded from the folder — `RecordingsView`
    /// switches to the "Play" sub-tab, per explicit user request.
    let onLoaded: () -> Void

    @State private var actionError: String?

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            folderSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    @ViewBuilder
    private var folderSection: some View {
        Section {
            if session.soundTrackNames.isEmpty {
                Text(L10n.string(.appPlaceholderAucunDossierSoundtracks, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(session.soundTrackNames.enumerated()), id: \.offset) { index, name in
                    HStack {
                        Button(name) {
                            do {
                                try session.useSoundTrack(named: name)
                                onLoaded()
                            } catch {
                                actionError = "\(error)"
                            }
                        }
                        Spacer()
                        Button {
                            do {
                                try session.deleteSoundTrack(atIndex: index)
                            } catch {
                                actionError = "\(error)"
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }
            }
            if session.currentSoundTrack != nil {
                Button(L10n.string(.appButtonSauvegarderDansCeDossier, session.currentLanguage)) {
                    do {
                        try session.saveSoundTrack(as: session.currentSoundTrack?.title ?? L10n.string(.catEnregistrement, session.currentLanguage))
                    } catch {
                        actionError = "\(error)"
                    }
                }
            }
        } header: {
            Text(L10n.string(.appHeadingDossierSoundtracks, session.currentLanguage))
        }
    }
}

#Preview {
    RecordingFileView(session: ImprovSession(), onLoaded: {})
}
