import SwiftUI
import AppCore
import JamShackUI
import MusicTheoryKit

/// Identifies each of the screens that can detach into their own `WindowGroup` (macOS/
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
    case theorieAccords, theorieExploration, theorieProgressions, theorieTonnetz
    case theorieDissonances, theorieIntonation
    case home
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

    /// iOS/iPadOS-only fallback for `contextualHelpContent` — no independent-window equivalent
    /// there (see `ContentView`'s own sheet presentation). Hoisted up from a local `ContentView`
    /// `@State` so any per-screen help button (`TheoryHelpButton`), not just the shared bottom-bar
    /// one, can trigger it directly without a binding threaded down through every screen.
    var showsContextualHelpSheet = false

    /// When non-nil, the help window/sheet shows THIS topic's content instead of whichever
    /// screen is currently active's own `contextualHelpContent` — set by tapping a
    /// `[label](jamshackhelp://<id>)` cross-reference inside another topic's own help text (see
    /// `View.interceptHelpLinks`). Reset to `nil` every time help is freshly opened
    /// (`ContentView.contextualHelpButton`/`TheoryHelpButton`), so a stale navigated-to topic
    /// from a previous session never leaks into a fresh "?" tap on a different screen.
    var pinnedHelpTopic: HelpTopicID?

    /// The mode (tonic + scale) whichever Théorie screen is currently active wants the persistent
    /// main-keyboard bar (`ComputerKeyboardInputBar`, in `ContentView`) to color itself by —
    /// mode-tone fill + scale-degree badges, same as any other mode-aware keyboard in the app
    /// (see `PitchKeyboardView.modeTones`/`showModeColoring`). `nil` when no active screen has
    /// one (Studio, Settings, or a Théorie screen that hasn't registered one) — the bar then
    /// falls back to its own plain "what's the physical keyboard playing" look. Use
    /// `View.registerMainKeyboardMode` rather than setting this directly; same owner-ID guard as
    /// `contextualHelpOwnerID` above, for the same reason.
    private(set) var mainKeyboardMode: Mode?
    private var mainKeyboardModeOwnerID: String?

    func setMainKeyboardMode(id: String, mode: Mode?) {
        mainKeyboardModeOwnerID = id
        mainKeyboardMode = mode
    }

    func clearMainKeyboardMode(id: String) {
        guard mainKeyboardModeOwnerID == id else { return }
        mainKeyboardModeOwnerID = nil
        mainKeyboardMode = nil
    }

    /// The chord (root pitch class + tones) the Accords screen wants the persistent main-keyboard
    /// bar to show as a centered reference voicing — see `ContentView.mainKeyboardPresentation`'s
    /// own use of `PitchKeyboardView.referenceChordPitches` for why this needs its own root+tones
    /// pair rather than reusing `mainKeyboardMode`. Use `View.registerMainKeyboardChord` rather
    /// than setting this directly; same owner-ID guard as `mainKeyboardModeOwnerID` above.
    private(set) var mainKeyboardChord: MainKeyboardChordSpec?
    private var mainKeyboardChordOwnerID: String?

    func setMainKeyboardChord(id: String, chord: MainKeyboardChordSpec?) {
        mainKeyboardChordOwnerID = id
        mainKeyboardChord = chord
    }

    func clearMainKeyboardChord(id: String) {
        guard mainKeyboardChordOwnerID == id else { return }
        mainKeyboardChordOwnerID = nil
        mainKeyboardChord = nil
    }

    /// One shared tonic+scale selection for every MusicLab screen that picks a mode (Modes,
    /// Progressions, Intonations, Tonnetz, Dissonances) — per explicit request, so picking a
    /// mode on one screen is reflected on every other, including across detached windows (this
    /// property lives on `AppModel`, already `.environment()`-injected into every `WindowGroup`).
    /// `ModeLibraryView`'s own Exploration instance opts out via `usesSharedModeSelection: false`
    /// and keeps its own independent local state instead — see that view's own doc comment.
    struct SharedModeSelection: Equatable {
        var tonic: Int = 0
        var scaleID: String = ScaleLibrary.all[0].id
    }
    var sharedMode = SharedModeSelection()

    /// Top-level app section + Studio/Settings sub-tab — promoted from `ContentView`'s own
    /// `@State` (2026-08) so `ComputerKeyboardWindow` (a separate detached window) can reproduce
    /// the exact same main-keyboard coloring/gating logic as the embedded bar — see
    /// `mainKeyboardPresentation(session:)` in `MainKeyboardMode.swift`, which reads these
    /// directly instead of taking them as parameters.
    var mode: AppMode = .studio
    var selectedStudioTab: StudioTab = .scene
    var selectedSettingsTab: SettingsTab = .sons

    /// Cross-mode navigation for the Guide screens — per explicit request: "jouer le guide" in
    /// Composition mode's own Guide screen (editing) jumps to Studio's Guide tab (playing), and
    /// "éditer le guide" there jumps back. Both screens act on the SAME `session.currentGuide` —
    /// there's no separate "guide loaded for editing" vs "for playing" — so this only needs to
    /// carry a destination, not a guide identity.
    ///
    /// A request/token pair rather than a single "pending request, cleared once consumed" value
    /// — `ContentView` (switches `mode`/`selectedStudioTab`/`selectedCompositionTab`),
    /// `GuideView` (jumps its own internal screen to `.configuration`), and
    /// `StudioGuidePlayTabContent` (jumps its own internal screen to `.lecture`) all need to react
    /// independently to the SAME request; a single "first reader clears it" value would race
    /// between them. Each observer instead reacts to `guideNavigationRequestToken` changing (same
    /// idiom as `computerKeyboardFocusRequestToken`) and reads `guideNavigationRequest` to decide
    /// whether THIS particular request concerns it — the value is simply left in place rather
    /// than cleared, since only the token transition (not presence/absence) ever matters.
    enum GuideNavigationDestination: Equatable {
        case playInStudio
        case editInComposition
    }
    private(set) var guideNavigationRequest: GuideNavigationDestination?
    private(set) var guideNavigationRequestToken = 0

    func requestGuideNavigation(_ destination: GuideNavigationDestination) {
        guideNavigationRequest = destination
        guideNavigationRequestToken += 1
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
