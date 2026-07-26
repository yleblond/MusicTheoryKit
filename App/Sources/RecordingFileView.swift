import SwiftUI
import AppCore
import Localization

/// "Fichier" sub-tab of the Enregistrement tab: the folder-based soundtrack browser (list/
/// load/save-into-folder — the folder itself is picked from the "JamShack" tab's "Dossiers"
/// sub-tab).
struct RecordingFileView: View {
    let session: ImprovSession
    /// Called after a soundtrack is actually loaded from the folder — `RecordingView`
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
            if session.soundTrackFiles.isEmpty {
                Text(L10n.string(.appPlaceholderAucunDossierSoundtracks, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(session.soundTrackFiles, id: \.self) { name in
                    Button(name.strippingJSONExtension) {
                        do {
                            try session.loadSoundTrack(named: name)
                            onLoaded()
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
                if session.currentSoundTrack != nil {
                    Button(L10n.string(.appButtonSauvegarderDansCeDossier, session.currentLanguage)) {
                        do {
                            try session.saveSoundTrack(as: (session.currentSoundTrack?.title ?? L10n.string(.catEnregistrement, session.currentLanguage)) + ".json")
                        } catch {
                            actionError = "\(error)"
                        }
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
