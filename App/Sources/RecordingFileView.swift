import SwiftUI
import AppCore

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
                Text("Aucun dossier de soundtracks choisi — JamShack > Dossiers.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(session.soundTrackFiles, id: \.self) { name in
                    Button(name) {
                        do {
                            try session.loadSoundTrack(named: name)
                            onLoaded()
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
                if session.currentSoundTrack != nil {
                    Button("Sauvegarder dans ce dossier") {
                        do {
                            try session.saveSoundTrack(as: (session.currentSoundTrack?.title ?? "Enregistrement") + ".json")
                        } catch {
                            actionError = "\(error)"
                        }
                    }
                }
            }
        } header: {
            Text("Dossier de soundtracks")
        }
    }
}

#Preview {
    RecordingFileView(session: ImprovSession(), onLoaded: {})
}
