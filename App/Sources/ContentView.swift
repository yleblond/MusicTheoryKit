import SwiftUI
import AppCore
import JamShackUI

struct ContentView: View {
    private enum AppTab: Hashable {
        case jamShack, scene, live, guide, recording, pieces, composition
    }

    @State private var session = ImprovSession()
    @State private var bridge: SessionUIBridge?
    @State private var startError: String?
    // Defaults to Scene per explicit user request — that's where you set up which
    // instrument sounds through which role before playing, so it's the natural first screen.
    @State private var selectedTab: AppTab = .scene

    var body: some View {
        Group {
            if let bridge {
                TabView(selection: $selectedTab) {
                    JamShackView(session: session, bridge: bridge)
                        .tabItem { Label("JamShack", systemImage: "folder") }
                        .tag(AppTab.jamShack)
                    SceneManagementView(session: session)
                        .tabItem { Label("Scene", systemImage: "theatermasks") }
                        .tag(AppTab.scene)
                    RunScreen(
                        bridge: bridge,
                        interactiveTrackID: TrackID.computerKeyboard.wireIDText,
                        onNoteOn: { pitch in session.pressKey(pitch: pitch) },
                        onNoteOff: { pitch in session.releaseKey(pitch: pitch) }
                    )
                        // Same LUMI-follows-the-active-screen wiring as Guide > Lecture (see
                        // that view's own `onAppear` doc comment) — never wired anywhere in
                        // this app before, for the "Run" mode either.
                        .onAppear { session.notifyActiveScreen(.run) }
                        .onDisappear { session.notifyActiveScreen(.other) }
                        .tabItem { Label("Live", systemImage: "pianokeys") }
                        .tag(AppTab.live)
                    GuideView(session: session, bridge: bridge)
                        .tabItem { Label("Guide", systemImage: "map") }
                        .tag(AppTab.guide)
                    RecordingView(session: session, bridge: bridge)
                        .tabItem { Label("Enregistrement", systemImage: "record.circle") }
                        .tag(AppTab.recording)
                    PiecesView(session: session)
                        .tabItem { Label("Morceaux", systemImage: "music.note.list") }
                        .tag(AppTab.pieces)
                    CompositionView(session: session)
                        .tabItem { Label("Composition", systemImage: "wand.and.stars") }
                        .tag(AppTab.composition)
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
                // Real bug fix: `startTrack` only starts LISTENING (recognition, held-note
                // display) — it never touches `TrackInfo.soundEnabled` (defaults to `false`)
                // or creates that track's `SamplerUnit`, both of which `setSoundEnabled` does
                // lazily. Without this, playing live (computer keyboard or a MIDI keyboard)
                // was completely silent on a fresh launch — notes registered and showed as
                // held, but nothing was ever routed to a sampler. Piece/soundtrack playback
                // was never affected by this, since `PiecePlayer`/`SoundTrackPlayer` each own
                // their own always-ready sampler, entirely independent of this per-track
                // enable step.
                try? session.setSoundEnabled(true, for: .midiMerged)
                try? session.setSoundEnabled(true, for: .computerKeyboard)
                // If a default root folder (iCloud Drive/JamShack by default) was already
                // chosen on a previous launch, restore it with no user interaction needed —
                // see DefaultFolderBookmark's doc comment.
                if let root = DefaultFolderBookmark.resolve() {
                    configureDefaultFolders(in: root, session: session)
                }
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
