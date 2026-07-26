import SwiftUI
import AppCore
import JamShackUI
import Localization

struct ContentView: View {
    private enum AppTab: Hashable {
        // `.live` kept as the case name (renamed to "Studio" only in its displayed label,
        // `.appTabStudio`) — no need to touch every reference to this enum value for a label
        // change. `.recording` no longer exists as its own tab: merged into `.live`/Studio
        // (2026-07-26), see `StudioView`.
        case jamShack, scene, live, guide, pieces, composition
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
                    // Custom label (not `systemImage:`) so the tab shows the app's own icon
                    // artwork, in color, instead of an SF Symbol — per explicit user request.
                    // `AppIconTabIcon` is a plain imageset (NOT the `AppIcon` appiconset itself,
                    // which the OS consumes for app-bundling purposes and isn't meant to be
                    // loaded as a regular `Image` at runtime) holding the same artwork PRE-
                    // SCALED to 24/48/72px (1x/2x/3x) — marked "original" rendering so it's
                    // never tinted like a monochrome symbol. Deliberately NOT `.resizable()` +
                    // `.frame(...)`: that combination rendered correctly in isolation but, once
                    // placed as a `Label`'s icon inside `Tab(value:content:label:)` under
                    // `.sidebarAdaptable`, the icon stretched to fill the ENTIRE sidebar height
                    // (confirmed via a real screenshot, not guessed) — some interaction between
                    // a resizable image and this specific container's layout on this OS version.
                    // A plain, non-resizable, already-correctly-sized `Image` sidesteps the bug
                    // entirely by never entering that resizing code path, the same way a plain
                    // SF Symbol (also never explicitly resized here) renders at its own natural
                    // size without issue.
                    Tab(value: AppTab.jamShack) {
                        JamShackView(session: session, bridge: bridge)
                    } label: {
                        Label {
                            Text(L10n.string(.catJamShack, session.currentLanguage))
                        } icon: {
                            Image("AppIconTabIcon")
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    Tab(L10n.string(.tabScene, session.currentLanguage), systemImage: "theatermasks", value: AppTab.scene) {
                        SceneManagementView(session: session)
                    }
                    // "Studio" — merges what used to be two separate tabs, Live and
                    // Enregistrement (2026-07-26): recording is something you do WHILE playing
                    // live, not a separate destination. See `StudioView`.
                    Tab(L10n.string(.appTabStudio, session.currentLanguage), systemImage: "pianokeys", value: AppTab.live) {
                        StudioView(session: session, bridge: bridge)
                    }
                    Tab(L10n.string(.headingGuide, session.currentLanguage), systemImage: "map", value: AppTab.guide) {
                        GuideView(session: session, bridge: bridge)
                    }
                    Tab(L10n.string(.catComposition, session.currentLanguage), systemImage: "wand.and.stars", value: AppTab.composition) {
                        CompositionView(session: session)
                    }
                    // "Morceaux" moved to last position, per explicit user request (2026-07-26).
                    Tab(L10n.string(.catMorceaux, session.currentLanguage), systemImage: "music.note.list", value: AppTab.pieces) {
                        PiecesView(session: session)
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
                ProgressView(L10n.string(.appStatusDemarrage, session.currentLanguage))
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
