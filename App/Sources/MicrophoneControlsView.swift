import SwiftUI
import AppCore

/// Start/stop the microphone track — used as the "Microphone" sub-tab of the "JamShack" tab.
/// A plain `View`, not a `Form`/`Section` itself, so it composes cleanly inside another Form.
struct MicrophoneControlsView: View {
    let session: ImprovSession

    @State private var microphoneError: String?

    private var isMicrophoneListening: Bool {
        session.tracks.first { $0.id == .microphone }?.isListening ?? false
    }

    var body: some View {
        Form {
            Section {
                if let microphoneError {
                    Text(microphoneError).foregroundStyle(.red).font(.caption)
                }
                if isMicrophoneListening {
                    Text("Microphone actif").foregroundStyle(.green)
                    Button("Arreter", role: .destructive) { session.stopTrack(.microphone) }
                } else {
                    Button("Demarrer l'ecoute du microphone") {
                        microphoneError = nil
                        do {
                            try session.startTrack(.microphone)
                        } catch {
                            microphoneError = "\(error)"
                        }
                    }
                }
            } header: {
                Text("Microphone")
            } footer: {
                Text("Detection d'accords/notes jouees a la voix ou a un instrument acoustique, par analyse spectrale (FFT).")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }
}

#Preview {
    MicrophoneControlsView(session: ImprovSession())
}
