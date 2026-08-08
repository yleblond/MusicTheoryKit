import SwiftUI
import AppCore
import JamShackUI
import Localization

struct ContentView: View {
    /// Which of the 3 flat tab sets is showing — replaces the old first-level `AppTab` TabView
    /// (2026-07-29), itself later a 2-state (studio/settings) toggle. Split into 3 (2026-08) once
    /// Théorie (see `TheorieTab`) had grown well past "a reference tool browsed while
    /// performing" — sharing Studio's own tab bar no longer matched what it had become, and
    /// deserved the same "top-level mode" standing as Studio/Settings rather than being folded
    /// into either.
    private enum AppMode: CaseIterable, Identifiable, Hashable {
        case studio, theorie, settings
        var id: Self { self }

        var systemImage: String {
            switch self {
            case .studio: return "pianokeys"
            case .theorie: return "flask.fill"
            case .settings: return "gearshape"
            }
        }

        func label(_ language: AppLanguage) -> String {
            switch self {
            case .studio: return L10n.string(.appTabStudio, language)
            case .theorie: return L10n.string(.appTabTheorie, language)
            case .settings: return L10n.string(.appButtonReglages, language)
            }
        }
    }

    /// The 6 studio-mode tabs — merges what used to be `StudioView`'s own 3 sub-tabs (Live,
    /// Scene, Guide) with the 3 tabs that used to sit alongside the old "Studio" top-level tab
    /// (Enregistrements, Composition, Morceaux): all 6 are "what you're actively performing
    /// with right now," now flat at the same level instead of nested one level deeper.
    private enum StudioTab: CaseIterable, Identifiable {
        case live, scene, guide, recordings, composition, pieces

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .live: return "pianokeys"
            case .scene: return "theatermasks"
            case .guide: return "map"
            case .recordings: return "record.circle"
            case .composition: return "wand.and.stars"
            case .pieces: return "music.note.list"
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
            }
        }
    }

    /// The 4 Théorie-mode tabs — a reference/practice tool browsed while playing, own top-level
    /// mode since 2026-08 (see `AppMode`'s own doc comment). Was 3 separate tabs, merged into one
    /// shared-picker tab 2026-08 per usage feedback, then SPLIT BACK into 3 plain tabs 2026-08
    /// once "Modes" grew enough of its own content (the functional/melodic exploration panel)
    /// that sharing one tab's screen space with Accords/Progressions no longer made sense — then,
    /// once that panel grew further still, "Modes" itself split again into `.modes` (the plain
    /// reference grid, `ModeLibraryContentFocus.overview`) and `.exploration` (the functional/
    /// melodic playground, `.exploration`) — each its own peer tab with its own independent
    /// tonic/scale picker, per explicit request. All 4 detach into their own window on macOS/
    /// visionOS (`ChordTabContent`/`TheoryTabContent`/`ProgressionTabContent`/
    /// `ExplorationTabContent`, each its own `AuxiliaryWindowID`).
    private enum TheorieTab: CaseIterable, Identifiable {
        case accords, modes, progressions, exploration

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .accords: return "music.quarternote.3"
            case .modes: return "text.book.closed"
            case .exploration: return "atom"
            case .progressions: return "list.number"
            }
        }

        func label(_ language: AppLanguage) -> String {
            switch self {
            case .accords: return L10n.string(.appTabAccords, language)
            case .modes: return L10n.string(.appTabModes, language)
            case .exploration: return L10n.string(.appHeadingExplorationFonctionnelle, language)
            case .progressions: return L10n.string(.appTabProgressions, language)
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
        // Which sound the Accords/Modes/Progressions tabs use for audition playback — moved
        // here from a picker inside those screens' own header (per explicit request), plus
        // (later) per-role color customization for those same screens (see
        // `Docs/BACKLOG_BRUT.md`). Reuses `appTabTheorie`'s own text ("Théorie"), freed up by
        // the Studio-tab split (see `StudioTab`'s own doc comment) rather than adding a
        // near-duplicate string.
        case theorie

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
            case .theorie: return "text.book.closed"
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
            case .theorie: return L10n.string(.appTabTheorie, language)
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
    @State private var selectedTheorieTab: TheorieTab = .modes
    @State private var selectedSettingsTab: SettingsTab = .sons
    /// iOS/iPadOS-only fallback for the generalized contextual-help button below — no
    /// independent-window equivalent there, same convention `ModeLibraryView`'s own former
    /// legend sheet already used.
    @State private var showsContextualHelpSheet = false

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
                            }
                        case .theorie:
                            TabView(selection: $selectedTheorieTab) {
                                Tab(TheorieTab.accords.label(session.currentLanguage), systemImage: TheorieTab.accords.systemImage, value: TheorieTab.accords) {
                                    ChordTabContent(session: session)
                                }
                                Tab(TheorieTab.modes.label(session.currentLanguage), systemImage: TheorieTab.modes.systemImage, value: TheorieTab.modes) {
                                    TheoryTabContent(session: session)
                                }
                                Tab(TheorieTab.progressions.label(session.currentLanguage), systemImage: TheorieTab.progressions.systemImage, value: TheorieTab.progressions) {
                                    ProgressionTabContent(session: session)
                                }
                                Tab(TheorieTab.exploration.label(session.currentLanguage), systemImage: TheorieTab.exploration.systemImage, value: TheorieTab.exploration) {
                                    ExplorationTabContent(session: session, isActive: mode == .theorie && selectedTheorieTab == .exploration)
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
                                Tab(SettingsTab.theorie.label(session.currentLanguage), systemImage: SettingsTab.theorie.systemImage, value: SettingsTab.theorie) {
                                    TheorieSettingsView(session: session)
                                }
                            }
                        }
                    }
                    .tabViewStyle(.sidebarAdaptable)

                    // Persistent, always-visible "long" keyboard — only while the computer
                    // keyboard mode is explicitly turned on (see `ComputerKeyboardSettingsView`,
                    // under Settings). Sits OUTSIDE the TabView so it stays put across every tab
                    // switch, a constant reminder that typing anywhere now plays notes. Placed
                    // ABOVE the mode-toggle bar (not below) so the toggle — the one thing you
                    // reach for constantly — stays pinned at the true bottom of the window and
                    // never shifts position when this keyboard appears/disappears, per explicit
                    // request ("stabilité de l'affichage").
                    if (mode == .studio || mode == .theorie) && session.computerKeyboardInputEnabled {
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

                    // Bottom block, always visible regardless of tab/mode: the 3-way mode
                    // toggle (current mode highlighted, per explicit request), plus
                    // (Studio/Théorie only — both actually play notes, per explicit decision —
                    // not Settings) a quick shortcut to turn the computer keyboard on/off
                    // without leaving either. The full setting (same underlying
                    // `computerKeyboardInputEnabled`) still lives in Settings > Clavier
                    // ordinateur (`ComputerKeyboardSettingsView`).
                    //
                    // Plain manual `Button`s, NOT a segmented `Picker` — same empirically-found
                    // platform quirk noted at the top of this file for `Tab()`/`.tabItem`: a
                    // `Label`'s icon doesn't reliably render inside a segmented control on
                    // macOS's current tab-bar style, only its text does. A plain `Button` with a
                    // `Label` always shows both, so that's what gets full manual control here —
                    // including the highlight fill for whichever mode is active.
                    Divider()
                    HStack(spacing: 8) {
                        ForEach(AppMode.allCases) { candidate in
                            Button {
                                mode = candidate
                            } label: {
                                Label(candidate.label(session.currentLanguage), systemImage: candidate.systemImage)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(mode == candidate ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(mode == candidate ? Color.accentColor : Color.primary)
                        }
                        if mode == .studio || mode == .theorie {
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
                        // Every Théorie tab (Accords/Modes/Progressions/Exploration alike, per
                        // explicit request): the single live-input source (see
                        // `ImprovSession.theoryLiveInputSourceID`'s own doc comment for why only
                        // one, unlike Studio) and the shared audition sound, both right-aligned —
                        // per explicit request ("dans la barre d'état du bas, aligné à droite").
                        // Live-match REACTION (selecting a chord/note as if tapped) only actually
                        // happens on Exploration, the one screen with anything to react on, but
                        // every tab benefits from simply being able to hear what's played.
                        if mode == .theorie {
                            theorieLiveInputSourcePicker(session: session)
                            FavoriteSoundPickerView(
                                favoriteSounds: session.favoriteSounds,
                                selectedID: Binding(
                                    get: { session.theoryAuditionSoundID },
                                    set: { try? session.setTheoryAuditionSoundID($0) }
                                ),
                                language: session.currentLanguage
                            )
                            .labelsHidden()
                            .frame(maxWidth: 160)
                        }
                        // Generalized "?" — whichever screen is currently active (per its own
                        // `.registerContextualHelp`), regardless of `mode`, per explicit request
                        // to reclaim the space every screen's own top-right "?" used to take.
                        // Hidden entirely when nothing registered any (most screens today).
                        if appModel.contextualHelpContent != nil {
                            contextualHelpButton(session: session)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .computerKeyboardInput(
                    isActive: session.computerKeyboardInputEnabled,
                    focusRequestToken: session.computerKeyboardFocusRequestToken,
                    octaveShift: session.computerKeyboardOctaveShift,
                    onNoteOn: { pitch in session.pressKey(pitch: pitch) },
                    onNoteOff: { pitch in session.releaseKey(pitch: pitch) },
                    onShiftOctave: { steps in session.shiftComputerKeyboardOctave(by: steps) }
                )
                #if !os(macOS) && !os(visionOS)
                // No independent-window equivalent on iOS/iPadOS — a dismissible sheet instead,
                // same convention `ModeLibraryView`'s own former legend sheet already used.
                .sheet(isPresented: $showsContextualHelpSheet) {
                    NavigationStack {
                        ScrollView {
                            if let content = appModel.contextualHelpContent { content().padding() }
                        }
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L10n.string(.appButtonFermer, session.currentLanguage)) { showsContextualHelpSheet = false }
                            }
                        }
                    }
                }
                #endif
        }
    }

    /// The generalized contextual-help button — opens `AuxiliaryWindowID.contextualHelp`
    /// (macOS/visionOS) or `showsContextualHelpSheet` (elsewhere) to show whichever screen is
    /// currently active's own registered help (see `View.registerContextualHelp`). Only ever
    /// shown by its own call site when `appModel.contextualHelpContent != nil`.
    private func contextualHelpButton(session: ImprovSession) -> some View {
        Button {
            #if os(macOS) || os(visionOS)
            openWindow(id: AuxiliaryWindowID.contextualHelp.rawValue)
            #else
            showsContextualHelpSheet = true
            #endif
        } label: {
            Image(systemName: "questionmark.circle")
        }
        .buttonStyle(.plain)
    }

    /// A dumb `Picker` over `session.theoryLiveInputSources`, same "`Text(...).tag(TrackID?...)`"
    /// shape `TestModeColumn`'s own test-source picker already uses — all the arm/disarm side
    /// effects (e.g. starting the microphone) live in `ImprovSession.setTheoryLiveInputSource`,
    /// not here.
    private func theorieLiveInputSourcePicker(session: ImprovSession) -> some View {
        Picker(L10n.string(.appFieldSourceTest, session.currentLanguage), selection: Binding(
            get: { session.theoryLiveInputSourceID },
            set: { session.setTheoryLiveInputSource($0) }
        )) {
            Text(L10n.string(.appOptionAucuneFem, session.currentLanguage)).tag(TrackID?.none)
            ForEach(session.theoryLiveInputSources) { track in
                Text(session.labelWithChannel(track)).tag(TrackID?.some(track.id))
            }
        }
        .labelsHidden()
        .frame(maxWidth: 180)
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
