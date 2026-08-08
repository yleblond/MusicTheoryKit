import SwiftUI
import AppCore
import JamShackUI

/// Identifies each of the 6 screens that can detach into their own `WindowGroup` (macOS/
/// visionOS only — see `JamShackApp`). Doubles as the `WindowGroup(id:)` string and as the key
/// tracking which ones are currently open (`AppModel.openAuxiliaryWindows`), since SwiftUI has
/// no built-in "is this WindowGroup open" query.
///
/// `contextualHelp` is the one exception to "screen": it's a small read-only help window
/// (`ContextualHelpWindow`, showing whichever screen currently registered itself via
/// `AppModel.setContextualHelp` — see that method's own doc comment), not a detached LIVE
/// screen — it has no "réintégrer" placeholder counterpart and never calls
/// `markWindowOpen`/`markWindowClosed`, since nothing needs to know it's open. Riding on this
/// same enum/`WindowGroup(id:)` registration anyway rather than inventing a second, parallel
/// one just for a single extra window id.
enum AuxiliaryWindowID: String, CaseIterable {
    case computerKeyboard, runScreen, guideLecture, microphone, sceneLayout, theorie, contextualHelp
    case theorieAccords, theorieExploration, theorieProgressions
}

/// Owns the single, shared `ImprovSession`/`SessionUIBridge` pair for the whole process —
/// hoisted out of `ContentView` (which used to create both directly via `@State`) so every
/// `WindowGroup` (the main window + the 5 detachable auxiliary ones) can reach the SAME live
/// instances via `.environment(_:)`, instead of each window accidentally constructing its own
/// independent `ImprovSession`. There is exactly one `AppModel` for the app's lifetime,
/// instantiated once in `JamShackApp` and injected into every `Scene`.
@MainActor
@Observable
final class AppModel {
    let session = ImprovSession()
    private(set) var bridge: SessionUIBridge?
    private(set) var startError: String?
    /// Guards against `start()` running more than once — every window's root view (main +
    /// the 5 auxiliary ones) carries its own `.task { await appModel.start() }` (see
    /// `SessionGatedView`), since an auxiliary window can in principle be the first one the
    /// system brings up (e.g. window restoration on macOS) — but only the first caller,
    /// whichever window happens to appear first, actually does the work.
    private var didStart = false

    /// Which of the 4 auxiliary windows are currently open — set by each window's own root
    /// view (`ComputerKeyboardWindow`/etc.) via `onAppear`/`onDisappear`, read by `ContentView`
    /// (and `GuideConfigurationView`, for the Guide > Lecture case) to decide whether to show
    /// the real screen or a "réintégrer" placeholder in the main window.
    var openAuxiliaryWindows: Set<AuxiliaryWindowID> = []

    func markWindowOpen(_ id: AuxiliaryWindowID) { openAuxiliaryWindows.insert(id) }
    func markWindowClosed(_ id: AuxiliaryWindowID) { openAuxiliaryWindows.remove(id) }

    /// Whichever screen is currently active may register its own "?" help content here instead
    /// of drawing its own per-screen help button — `ContentView`'s shared bottom bar shows ONE
    /// generalized "?" whenever this is non-nil, opening `AuxiliaryWindowID.contextualHelp`
    /// (macOS/visionOS) or a sheet (elsewhere) to show it. Per explicit request, to reclaim the
    /// space every screen's own top-right "?" used to take. A content-producing CLOSURE, not a
    /// pre-built `AnyView` — `ContextualHelpWindow`/the sheet re-invoke it on every render, so it
    /// stays live against whatever the registering screen's own closure still reads fresh (e.g.
    /// `session.currentLanguage`) rather than freezing a snapshot from whenever it registered.
    /// Use `View.registerContextualHelp` rather than setting this directly.
    private(set) var contextualHelpContent: (() -> AnyView)?
    /// Guards `clearContextualHelp` against an outgoing screen's `false` transition clearing an
    /// incoming screen's already-registered content when their firing order isn't guaranteed
    /// (e.g. two screens both reacting to the same tab switch in the same view-update pass).
    private var contextualHelpOwnerID: String?

    func setContextualHelp(id: String, content: @escaping () -> some View) {
        contextualHelpOwnerID = id
        contextualHelpContent = { AnyView(content()) }
    }

    func clearContextualHelp(id: String) {
        guard contextualHelpOwnerID == id else { return }
        contextualHelpOwnerID = nil
        contextualHelpContent = nil
    }

    /// Identical body to `ContentView`'s old startup `.task { }` — moved here verbatim so
    /// behavior doesn't change, just ownership.
    func start() async {
        guard !didStart else { return }
        didStart = true
        do {
            session.loadPersistedAppSettings()
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
            // Soundfonts resolve to the app's own iCloud Drive container/`Application
            // Support` automatically (see `SoundFontLocations`) — no user-picked folder,
            // and no longer gated behind the old "Dossiers" root-folder bookmark (removed
            // 2026-07-30, along with the one-time JSON migrations it used to also trigger:
            // every device that needed that migration has already had it run).
            session.startSoundFontLibrary()
            // Idempotent (no-op once already resolved) — `sceneNames`/`guideSequenceNames`
            // come from the shared SwiftData store, independent of any folder, so this is
            // always safe to call unconditionally on every launch.
            session.ensureGuideReadyForLaunch()
            session.ensureSceneReadyForLaunch()
            #if os(macOS)
            // Off unless the user already turned it on in a previous session — see
            // `startMCPServerIfEnabled`'s own doc comment. macOS only (see `MCPServer.swift`
            // for why iOS/visionOS are structurally out of scope).
            session.startMCPServerIfEnabled()
            #endif
            bridge = SessionUIBridge(session: session)
        } catch {
            startError = "\(error)"
        }
    }
}
