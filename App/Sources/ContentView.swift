import SwiftUI
import AppCore
import JamShackUI
import Localization

struct ContentView: View {
    /// Whether the app is showing the 6 flat "studio" tabs or the 9 flat "settings" tabs (what
    /// used to be the standalone "JamShack" tab's own sub-tabs) — replaces the old first-level
    /// `AppTab` TabView (2026-07-29): there's no longer a top-level "JamShack" destination to
    /// navigate to, just a toggle at the bottom that swaps which flat tab set is showing.
    private enum AppMode { case studio, settings }

    /// The 6 studio-mode tabs — merges what used to be `StudioView`'s own 3 sub-tabs (Live,
    /// Scene, Guide) with the 3 tabs that used to sit alongside the old "Studio" top-level tab
    /// (Enregistrements, Composition, Morceaux): all 6 are "what you're actively performing
    /// with right now," now flat at the same level instead of nested one level deeper.
    private enum StudioTab: CaseIterable, Identifiable {
        case live, scene, guide, recordings, composition, pieces
        // Théorie (Accords/Modes/Progressions, navigated via a horizontal picker inside
        // `TheoryView`) — a reference/practice tool browsed while playing, added 2026-08
        // alongside the rest of the flat Studio tab set (per user decision: a tab here rather
        // than a separate sidebar). Originally 3 separate tabs, merged into one 2026-08 per
        // usage feedback (also detachable into its own window, see `AuxiliaryWindowID.theorie`).
        case theorie

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .live: return "pianokeys"
            case .scene: return "theatermasks"
            case .guide: return "map"
            case .recordings: return "record.circle"
            case .composition: return "wand.and.stars"
            case .pieces: return "music.note.list"
            case .theorie: return "text.book.closed"
            }
        }

        func label(_ language: AppLanguage) -> String {
            switch self {
            case .live: return L10n.string(.appLabelEnDirect, language)
            case .scene: return L10n.string(.tabScene, language)
            case .guide: return L10n.string(.headingGuide, language)
            case .recordings: return L10n.string(.appTabEnregistrements, language)
            case .composition: return L10n.string(.catComposition, language)
            case .pieces: return L10n.string(.catMorceaux, language)
            case .theorie: return L10n.string(.appTabTheorie, language)
            }
        }
    }

    /// The settings-mode tabs — was `JamShackView`'s own internal sub-tab rail, hoisted here
    /// (now that there's no wrapping "JamShack" tab to hold them), pared down since (Dossiers,
    /// Cadrages merged into I.A., and Clavier ordinateur all removed as redundant/vestigial —
    /// see each removal's own commit/doc history). No dedicated "Clavier ordinateur" tab: its
    /// entire content was a single on/off toggle for `computerKeyboardInputEnabled`, already
    /// exposed via the quick-toggle button in the bottom bar below (Studio mode only) — keeping
    /// both was pure duplication with zero extra capability in the tab.
    private enum SettingsTab: CaseIterable, Identifiable {
        case sons, midi, microphone, jamSession, couleurs, llm, langue, notation

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .sons: return "music.note.list"
            case .midi: return "pianokeys"
            case .microphone: return "mic"
            case .jamSession: return "person.2.fill"
            case .couleurs: return "paintpalette"
            case .llm: return "brain"
            case .langue: return "globe"
            case .notation: return "textformat.abc"
            }
        }

        func label(_ language: AppLanguage) -> String {
            switch self {
            case .sons: return L10n.string(.appTabSons, language)
            case .midi: return L10n.string(.appTabMIDI, language)
            case .microphone: return L10n.string(.appTabMicrophone, language)
            case .jamSession: return L10n.string(.catJamSession, language)
            case .couleurs: return L10n.string(.appTabCouleurs, language)
            case .llm: return L10n.string(.appTabLLM, language)
            case .langue: return L10n.string(.appTabLangue, language)
            case .notation: return L10n.string(.appTabNotation, language)
            }
        }
    }

    @Environment(AppModel.self) private var appModel
    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    @State private var mode: AppMode = .studio
    // Same default as the old `StudioView` — that's where you set up which instrument sounds
    // through which role before playing, so it's the natural first screen.
    @State private var selectedStudioTab: StudioTab = .scene
    @State private var selectedSettingsTab: SettingsTab = .sons

    var body: some View {
        SessionGatedView { session, bridge in
                // `Tab(_:systemImage:)` + `.sidebarAdaptable`, not the older `.tabItem { Label }`
                // — confirmed empirically (off-screen test app, not guessed) that on macOS's
                // current top "pill" tab bar style, NEITHER API shows an icon next to the
                // label, only text; `.sidebarAdaptable` is the one style that actually renders
                // both. Adaptive by design on iOS too (collapses to a normal bottom tab bar on
                // iPhone-width, can show as a sidebar on iPad) — chosen so this one change
                // covers both platforms without a `#if os()` fork of the whole TabView.
                VStack(spacing: 0) {
                    Group {
                        switch mode {
                        case .studio:
                            TabView(selection: $selectedStudioTab) {
                                Tab(StudioTab.live.label(session.currentLanguage), systemImage: StudioTab.live.systemImage, value: StudioTab.live) {
                                    LiveTabContent(session: session, bridge: bridge)
                                }
                                Tab(StudioTab.scene.label(session.currentLanguage), systemImage: StudioTab.scene.systemImage, value: StudioTab.scene) {
                                    SceneManagementView(session: session)
                                }
                                Tab(StudioTab.guide.label(session.currentLanguage), systemImage: StudioTab.guide.systemImage, value: StudioTab.guide) {
                                    GuideView(session: session, bridge: bridge)
                                }
                                Tab(StudioTab.recordings.label(session.currentLanguage), systemImage: StudioTab.recordings.systemImage, value: StudioTab.recordings) {
                                    RecordingsView(session: session)
                                }
                                Tab(StudioTab.composition.label(session.currentLanguage), systemImage: StudioTab.composition.systemImage, value: StudioTab.composition) {
                                    CompositionView(session: session)
                                }
                                Tab(StudioTab.pieces.label(session.currentLanguage), systemImage: StudioTab.pieces.systemImage, value: StudioTab.pieces) {
                                    PiecesView(session: session)
                                }
                                Tab(StudioTab.theorie.label(session.currentLanguage), systemImage: StudioTab.theorie.systemImage, value: StudioTab.theorie) {
                                    TheoryTabContent(session: session)
                                }
                            }
                        case .settings:
                            TabView(selection: $selectedSettingsTab) {
                                Tab(SettingsTab.sons.label(session.currentLanguage), systemImage: SettingsTab.sons.systemImage, value: SettingsTab.sons) {
                                    SoundsView(session: session, bridge: bridge, isActive: mode == .settings && selectedSettingsTab == .sons)
                                }
                                Tab(SettingsTab.midi.label(session.currentLanguage), systemImage: SettingsTab.midi.systemImage, value: SettingsTab.midi) {
                                    JamShackMIDIView(session: session, bridge: bridge)
                                }
                                Tab(SettingsTab.microphone.label(session.currentLanguage), systemImage: SettingsTab.microphone.systemImage, value: SettingsTab.microphone) {
                                    MicrophoneTabContent(session: session, bridge: bridge)
                                }
                                Tab(SettingsTab.jamSession.label(session.currentLanguage), systemImage: SettingsTab.jamSession.systemImage, value: SettingsTab.jamSession) {
                                    JamSessionView(session: session)
                                }
                                Tab(SettingsTab.couleurs.label(session.currentLanguage), systemImage: SettingsTab.couleurs.systemImage, value: SettingsTab.couleurs) {
                                    JamShackColorsView(session: session)
                                }
                                Tab(SettingsTab.llm.label(session.currentLanguage), systemImage: SettingsTab.llm.systemImage, value: SettingsTab.llm) {
                                    JamShackAIView(session: session)
                                }
                                Tab(SettingsTab.langue.label(session.currentLanguage), systemImage: SettingsTab.langue.systemImage, value: SettingsTab.langue) {
                                    JamShackLanguageView(session: session)
                                }
                                Tab(SettingsTab.notation.label(session.currentLanguage), systemImage: SettingsTab.notation.systemImage, value: SettingsTab.notation) {
                                    NotationStyleSettingsView(session: session)
                                }
                            }
                        }
                    }
                    .tabViewStyle(.sidebarAdaptable)

                    // Bottom block, always visible regardless of tab/mode: the studio/settings
                    // mode toggle, plus (studio mode only, per explicit user request) a quick
                    // shortcut to turn the computer keyboard on/off without leaving Studio — the
                    // full setting (same underlying `computerKeyboardInputEnabled`) still lives
                    // in Settings > Clavier ordinateur (`ComputerKeyboardSettingsView`).
                    Divider()
                    HStack {
                        Button {
                            mode = (mode == .studio) ? .settings : .studio
                        } label: {
                            Label(
                                mode == .studio
                                    ? L10n.string(.appButtonReglages, session.currentLanguage)
                                    : L10n.string(.appTabStudio, session.currentLanguage),
                                systemImage: mode == .studio ? "gearshape" : "pianokeys"
                            )
                        }
                        if mode == .studio {
                            Button {
                                session.setComputerKeyboardInputEnabled(!session.computerKeyboardInputEnabled)
                            } label: {
                                Label(L10n.string(.appTabClavierOrdinateur, session.currentLanguage), systemImage: "keyboard")
                            }
                            .foregroundStyle(session.computerKeyboardInputEnabled ? Color.accentColor : Color.primary)
                            #if os(macOS) || os(visionOS)
                            if session.computerKeyboardInputEnabled && !appModel.openAuxiliaryWindows.contains(.computerKeyboard) {
                                Button {
                                    openWindow(id: AuxiliaryWindowID.computerKeyboard.rawValue)
                                } label: {
                                    Image(systemName: "rectangle.on.rectangle")
                                }
                            }
                            #endif
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    // Persistent, always-visible "long" keyboard — only while the computer
                    // keyboard mode is explicitly turned on (see `ComputerKeyboardSettingsView`,
                    // under Settings). Sits OUTSIDE the TabView so it stays put across every tab
                    // switch, a constant reminder that typing anywhere now plays notes.
                    if mode == .studio && session.computerKeyboardInputEnabled {
                        Divider()
                        #if os(macOS) || os(visionOS)
                        if appModel.openAuxiliaryWindows.contains(.computerKeyboard) {
                            DetachedPlaceholderView(
                                message: L10n.string(.appLabelOuvertDansFenetreSeparee, session.currentLanguage),
                                language: session.currentLanguage,
                                onReintegrate: { dismissWindow(id: AuxiliaryWindowID.computerKeyboard.rawValue) }
                            )
                            .frame(height: 120)
                        } else {
                            ComputerKeyboardInputBar(
                                heldPitches: session.tracks.first { $0.id == .computerKeyboard }?.heldPitches ?? [],
                                palette: bridge.state.palette, paletteTextColors: bridge.state.paletteTextColors,
                                label: L10n.string(.appLabelClavierOrdinateurActif, session.currentLanguage),
                                octaveShift: session.computerKeyboardOctaveShift,
                                onNoteOn: { pitch in session.pressKey(pitch: pitch) },
                                onNoteOff: { pitch in session.releaseKey(pitch: pitch) },
                                onShiftOctave: { steps in session.shiftComputerKeyboardOctave(by: steps) }
                            )
                        }
                        #else
                        ComputerKeyboardInputBar(
                            heldPitches: session.tracks.first { $0.id == .computerKeyboard }?.heldPitches ?? [],
                            palette: bridge.state.palette, paletteTextColors: bridge.state.paletteTextColors,
                            label: L10n.string(.appLabelClavierOrdinateurActif, session.currentLanguage),
                            octaveShift: session.computerKeyboardOctaveShift,
                            onNoteOn: { pitch in session.pressKey(pitch: pitch) },
                            onNoteOff: { pitch in session.releaseKey(pitch: pitch) },
                            onShiftOctave: { steps in session.shiftComputerKeyboardOctave(by: steps) }
                        )
                        #endif
                    }
                }
                .computerKeyboardInput(
                    isActive: session.computerKeyboardInputEnabled,
                    focusRequestToken: session.computerKeyboardFocusRequestToken,
                    octaveShift: session.computerKeyboardOctaveShift,
                    onNoteOn: { pitch in session.pressKey(pitch: pitch) },
                    onNoteOff: { pitch in session.releaseKey(pitch: pitch) },
                    onShiftOctave: { steps in session.shiftComputerKeyboardOctave(by: steps) }
                )
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
