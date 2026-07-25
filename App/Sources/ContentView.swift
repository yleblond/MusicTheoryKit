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
                // `Tab(_:systemImage:)` + `.sidebarAdaptable`, not the older `.tabItem { Label }`
                // — confirmed empirically (off-screen test app, not guessed) that on macOS's
                // current top "pill" tab bar style, NEITHER API shows an icon next to the
                // label, only text; `.sidebarAdaptable` is the one style that actually renders
                // both. Adaptive by design on iOS too (collapses to a normal bottom tab bar on
                // iPhone-width, can show as a sidebar on iPad) — chosen so this one change
                // covers both platforms without a `#if os()` fork of the whole TabView.
                TabView(selection: $selectedTab) {
                    Tab("JamShack", systemImage: "folder", value: AppTab.jamShack) {
                        JamShackView(session: session, bridge: bridge)
                    }
                    Tab("Scene", systemImage: "theatermasks", value: AppTab.scene) {
                        SceneManagementView(session: session)
                    }
                    Tab("Live", systemImage: "pianokeys", value: AppTab.live) {
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
                    }
                    Tab("Guide", systemImage: "map", value: AppTab.guide) {
                        GuideView(session: session, bridge: bridge)
                    }
                    Tab("Enregistrement", systemImage: "record.circle", value: AppTab.recording) {
                        RecordingView(session: session, bridge: bridge)
                    }
                    Tab("Morceaux", systemImage: "music.note.list", value: AppTab.pieces) {
                        PiecesView(session: session)
                    }
                    Tab("Composition", systemImage: "wand.and.stars", value: AppTab.composition) {
                        CompositionView(session: session)
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
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
                // `.individual` (the session's own default — see `midiFusionMode`) creates
                // one `.midiSource(index)` track per visible MIDI port instead of a single
                // `.midiMerged` one. An earlier version of this code forced `.merged` here,
                // which silently overrode that default on every launch — fixed by starting
                // every currently-visible MIDI-source track instead of the one track
                // `.merged` mode would have had.
                try session.startTrack(.computerKeyboard)
                for track in session.tracks {
                    switch track.id {
                    case .midiMerged, .midiSource:
                        try? session.startTrack(track.id)
                        try? session.setSoundEnabled(true, for: track.id)
                    default:
                        break
                    }
                }
                // Real bug fix: `startTrack` only starts LISTENING (recognition, held-note
                // display) — it never touches `TrackInfo.soundEnabled` (defaults to `false`)
                // or creates that track's `SamplerUnit`, both of which `setSoundEnabled` does
                // lazily. Without this, playing live (computer keyboard or a MIDI keyboard)
                // was completely silent on a fresh launch — notes registered and showed as
                // held, but nothing was ever routed to a sampler. Piece/soundtrack playback
                // was never affected by this, since `PiecePlayer`/`SoundTrackPlayer` each own
                // their own always-ready sampler, entirely independent of this per-track
                // enable step.
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
