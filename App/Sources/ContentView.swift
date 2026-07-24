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
                    RunScreen(
                        bridge: bridge,
                        interactiveTrackID: TrackID.computerKeyboard.wireIDText,
                        onNoteOn: { pitch in session.pressKey(pitch: pitch) },
                        onNoteOff: { pitch in session.releaseKey(pitch: pitch) }
                    )
                        .tabItem { Label("Run", systemImage: "pianokeys") }
                    CircleOfFifthsWheelView(wheel: bridge.state.wheel)
                        .padding()
                        .tabItem { Label("Roue", systemImage: "circle.grid.3x3") }
                    ServerControlsView(session: session)
                        .tabItem { Label("Reseau", systemImage: "network") }
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
