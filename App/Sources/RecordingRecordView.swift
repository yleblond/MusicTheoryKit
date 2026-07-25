import SwiftUI
import AppCore
import JamShackUI

/// "Record" sub-tab of the Enregistrement tab: choose which currently-listening tracks to
/// record, and start/stop the recording — playback of the resulting recording lives in the
/// sibling "Play" sub-tab.
struct RecordingRecordView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    @State private var selectedTrackWireIDs: Set<String> = []
    @State private var actionError: String?

    var body: some View {
        Form {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red).font(.caption) }
            }
            recordingSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    @ViewBuilder
    private var recordingSection: some View {
        Section {
            if session.isRecording {
                Text("Enregistrement en cours...").foregroundStyle(.red)
                Button("Arreter l'enregistrement", role: .destructive) {
                    do {
                        _ = try session.stopRecording()
                    } catch {
                        actionError = "\(error)"
                    }
                }
            } else {
                ForEach(bridge.state.tracks, id: \.id) { track in
                    Toggle(track.label, isOn: Binding(
                        get: { selectedTrackWireIDs.contains(track.id) },
                        set: { isOn in
                            if isOn { selectedTrackWireIDs.insert(track.id) } else { selectedTrackWireIDs.remove(track.id) }
                        }
                    ))
                }
                Button("Demarrer l'enregistrement") {
                    let trackIDs = Set(selectedTrackWireIDs.compactMap { TrackID(wireIDText: $0) })
                    do {
                        try session.startRecording(title: "Enregistrement", tracks: trackIDs)
                    } catch {
                        actionError = "\(error)"
                    }
                }
            }
        } header: {
            Text("Enregistrement")
        } footer: {
            Text("Choisis les pistes a enregistrer — aucune coche = toutes les pistes en ecoute.")
        }
    }
}

#Preview {
    let session = ImprovSession()
    return RecordingRecordView(session: session, bridge: SessionUIBridge(session: session))
}
