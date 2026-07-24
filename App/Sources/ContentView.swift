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
                    RunScreen(bridge: bridge)
                        .tabItem { Label("Run", systemImage: "pianokeys") }
                    CircleOfFifthsWheelView(wheel: bridge.state.wheel)
                        .padding()
                        .tabItem { Label("Roue", systemImage: "circle.grid.3x3") }
                }
            } else if let startError {
                Text(startError).foregroundStyle(.red).padding()
            } else {
                ProgressView("Demarrage...")
            }
        }
        .task {
            do {
                try session.start()
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
