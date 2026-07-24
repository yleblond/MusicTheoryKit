import SwiftUI
import AppCore
import JamShackUI

struct ContentView: View {
    @State private var session = ImprovSession()
    @State private var bridge: SessionUIBridge?
    @State private var startError: String?

    var body: some View {
        Group {
            if let bridge {
                TabView {
                    JamShackView(session: session)
                        .tabItem { Label("JamShack", systemImage: "folder") }
                    SceneManagementView(session: session)
                        .tabItem { Label("Scene", systemImage: "theatermasks") }
                    RunScreen(
                        bridge: bridge,
                        interactiveTrackID: TrackID.computerKeyboard.wireIDText,
                        onNoteOn: { pitch in session.pressKey(pitch: pitch) },
                        onNoteOff: { pitch in session.releaseKey(pitch: pitch) }
                    )
                        .tabItem { Label("Live", systemImage: "pianokeys") }
                }
                .computerKeyboardInput(
                    onNoteOn: { pitch in session.pressKey(pitch: pitch) },
                    onNoteOff: { pitch in session.releaseKey(pitch: pitch) }
                )
            } else if let startError {
                Text(startError).foregroundStyle(.red).padding()
            } else {
                ProgressView("Demarrage...")
            }
        }
        .task {
            do {
                try session.start()
                // .individual (the default) creates one .midiSource(index) track per
                // visible port instead of a single .midiMerged one — .merged is simpler
                // for this first milestone (one external keyboard, no need to distinguish
                // multiple MIDI devices yet).
                session.setMIDIFusionMode(.merged)
                try session.startTrack(.midiMerged)
                try session.startTrack(.computerKeyboard)
                bridge = SessionUIBridge(session: session)
            } catch {
                startError = "\(error)"
            }
        }
    }
}

#Preview {
    ContentView()
}
