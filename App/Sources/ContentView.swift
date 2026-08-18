import SwiftUI
import AppCore
import JamShackUI
import Localization
import MusicTheoryKit

struct ContentView: View {
    /// Which of the 4 flat tab sets is showing — replaces the old first-level `AppTab` TabView
    /// (2026-07-29), itself later a 2-state (studio/settings) toggle. Split into 3 (2026-08) once
    /// Théorie (see `TheorieTab`) had grown well past "a reference tool browsed while
    /// performing" — sharing Studio's own tab bar no longer matched what it had become, and
    /// deserved the same "top-level mode" standing as Studio/Settings rather than being folded
    /// into either. Split into 4 (2026-08) the same way again for `.composition`, once Guide's
    /// own edition/Composition/Morceaux stopped being "what you're actively performing," and
    /// became "material you prepare before performing" instead — see `CompositionTab`'s own doc
    /// comment.
    /// Studio's own tabs — what you're actively PERFORMING right now, per explicit request
    /// ("Scène, En Direct, Guide" order). `.guide` here is `StudioGuidePlayTabContent` — PLAYING
    /// an already-authored guide — deliberately distinct from Composition mode's own `.guide`
    /// (`GuideView`, editing) even though both act on the same `session.currentGuide`; see
    /// `AppModel.GuideNavigationDestination`'s own doc comment for how the two cross-navigate.
    /// `.recordings` stays here (not moved to Composition) since capturing a live take is still
    /// squarely a Studio activity — Composition's own "IA" tab reads FROM a recording, but doesn't
    /// make one. `.jamSession` (`StudioJamSessionTabContent`) moved here FROM Settings (2026-08-09,
    /// per explicit request) — inviting others in is something you reach for while performing, not
    /// a setting; see that view's own doc comment.
    /// Composition mode's own tabs — material you PREPARE before performing, moved out of Studio
    /// (2026-08, see `AppMode`'s own doc comment): `.guide` here is `GuideView`, EDITING a guide
    /// sequence (Studio's own `.guide` tab plays one instead — see `StudioTab`'s own doc comment).
    private enum CompositionTab: CaseIterable, Identifiable {
        case guide, composition, pieces

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .guide: return "map"
            case .composition: return "wand.and.stars"
            case .pieces: return "music.note.list"
            }
        }

        func label(_ language: AppLanguage) -> String {
            switch self {
            case .guide: return L10n.string(.headingGuide, language)
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
    /// tonic/scale picker, per explicit request. `.accords`/`.modes`/`.progressions`/
    /// `.exploration`/`.tonnetz` all detach into their own window on macOS/visionOS
    /// (`ChordTabContent`/`TheoryTabContent`/`ProgressionTabContent`/`ExplorationTabContent`/
    /// `TonnetzTabContent`, each its own `AuxiliaryWindowID`) — `.intonations` doesn't yet.
    private enum TheorieTab: CaseIterable, Identifiable {
        case accords, modes, progressions, exploration, tonnetz, intonations, dissonances

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .accords: return "music.quarternote.3"
            case .modes: return "text.book.closed"
            case .exploration: return "atom"
            case .progressions: return "list.number"
            case .tonnetz: return "triangle.fill"
            case .intonations: return "tuningfork"
            case .dissonances: return "waveform"
            }
        }

        func label(_ language: AppLanguage) -> String {
            switch self {
            case .accords: return L10n.string(.appTabAccords, language)
            case .modes: return L10n.string(.appTabModes, language)
            case .exploration: return L10n.string(.appHeadingExplorationFonctionnelle, language)
            case .progressions: return L10n.string(.appTabProgressions, language)
            case .tonnetz: return L10n.string(.appTabTonnetz, language)
            case .intonations: return L10n.string(.appTabIntonations, language)
            case .dissonances: return L10n.string(.appTabDissonances, language)
            }
        }
    }

    // `SettingsTab` (was `JamShackView`'s own internal sub-tab rail) moved to `AppModel`/
    // `MainKeyboardMode.swift` alongside `AppMode`/`StudioTab` — see `AppModel.mode`'s own doc
    // comment.
    @Environment(AppModel.self) private var appModel
    /// Only used to hide the Tonnetz tab on iPhone-width layouts (see `.theorie`'s `TabView`
    /// below) — the Tonnetz screen needs the two-graph-plus-legend layout's own space, which an
    /// iPhone can't offer. A runtime check, not `#if os()`, per this file's own `.sidebarAdaptable`
    /// rationale just below (one tab structure, no platform forks) — iPhone and iPad share the
    /// same OS, so only the size class actually distinguishes them.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    // `mode`/`selectedStudioTab`/`selectedSettingsTab` moved to `AppModel` (2026-08) so the
    // detached `ComputerKeyboardWindow` can read them too — see `AppModel.mode`'s own doc
    // comment. Same default as the old `StudioView` — that's where you set up which instrument
    // sounds through which role before playing, so it's the natural first screen.
    @State private var selectedTheorieTab: TheorieTab = .modes
    @State private var selectedCompositionTab: CompositionTab = .guide
    /// Drives the bottom bar's tuning-fork button (see `temperamentQuickPickerButton`) — lets
    /// the temperament/A4 reference be changed from any Théorie tab without navigating to
    /// Intonations, per explicit request.
    @State private var showsTuningQuickPicker = false

    /// Studio/Théorie always show the main-keyboard bar's own controls (toggle, detach,
    /// source picker); Settings only does while its own "Sons" sub-tab is active (testing a
    /// soundfont there plays through the same "source principale" — see `SoundsView`), per
    /// explicit request. Composition never does.
    private var showsMainKeyboardControls: Bool {
        appModel.mode == .studio || appModel.mode == .theorie || (appModel.mode == .settings && appModel.selectedSettingsTab == .sons)
    }

    var body: some View {
        @Bindable var appModel = appModel
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
                        switch appModel.mode {
                        case .home:
                            #if os(macOS) || os(visionOS)
                            if appModel.openAuxiliaryWindows.contains(.home) {
                                DetachedPlaceholderView(
                                    message: L10n.string(.appLabelOuvertDansFenetreSeparee, session.currentLanguage),
                                    language: session.currentLanguage,
                                    onReintegrate: { dismissWindow(id: AuxiliaryWindowID.home.rawValue) }
                                )
                            } else {
                                StatusGraphView(session: session)
                                    .registerContextualHelp(id: HelpTopicID.home.rawValue, isActive: appModel.mode == .home) {
                                        HelpTopicID.home.content(language: session.currentLanguage)
                                    }
                            }
                            #else
                            StatusGraphView(session: session)
                                .registerContextualHelp(id: HelpTopicID.home.rawValue, isActive: appModel.mode == .home) {
                                    HelpTopicID.home.content(language: session.currentLanguage)
                                }
                            #endif
                        case .studio:
                            TabView(selection: $appModel.selectedStudioTab) {
                                Tab(StudioTab.scene.label(session.currentLanguage), systemImage: StudioTab.scene.systemImage, value: StudioTab.scene) {
                                    SceneManagementView(session: session, isActive: appModel.mode == .studio && appModel.selectedStudioTab == .scene)
                                }
                                Tab(StudioTab.live.label(session.currentLanguage), systemImage: StudioTab.live.systemImage, value: StudioTab.live) {
                                    LiveTabContent(session: session, bridge: bridge, isActive: appModel.mode == .studio && appModel.selectedStudioTab == .live)
                                }
                                Tab(StudioTab.guide.label(session.currentLanguage), systemImage: StudioTab.guide.systemImage, value: StudioTab.guide) {
                                    StudioGuidePlayTabContent(session: session, bridge: bridge, isActive: appModel.mode == .studio && appModel.selectedStudioTab == .guide)
                                }
                                Tab(StudioTab.recordings.label(session.currentLanguage), systemImage: StudioTab.recordings.systemImage, value: StudioTab.recordings) {
                                    RecordingsView(session: session)
                                        .registerContextualHelp(id: HelpTopicID.studioRecordings.rawValue, isActive: appModel.mode == .studio && appModel.selectedStudioTab == .recordings) {
                                            HelpTopicID.studioRecordings.content(language: session.currentLanguage)
                                        }
                                }
                                Tab(StudioTab.jamSession.label(session.currentLanguage), systemImage: StudioTab.jamSession.systemImage, value: StudioTab.jamSession) {
                                    StudioJamSessionTabContent(session: session)
                                        .registerContextualHelp(id: HelpTopicID.studioJamSession.rawValue, isActive: appModel.mode == .studio && appModel.selectedStudioTab == .jamSession) {
                                            HelpTopicID.studioJamSession.content(language: session.currentLanguage)
                                        }
                                }
                            }
                        case .composition:
                            TabView(selection: $selectedCompositionTab) {
                                Tab(CompositionTab.guide.label(session.currentLanguage), systemImage: CompositionTab.guide.systemImage, value: CompositionTab.guide) {
                                    GuideView(session: session, bridge: bridge)
                                        .registerContextualHelp(id: HelpTopicID.compositionGuide.rawValue, isActive: appModel.mode == .composition && selectedCompositionTab == .guide) {
                                            HelpTopicID.compositionGuide.content(language: session.currentLanguage)
                                        }
                                }
                                Tab(CompositionTab.composition.label(session.currentLanguage), systemImage: CompositionTab.composition.systemImage, value: CompositionTab.composition) {
                                    CompositionView(session: session)
                                        .registerContextualHelp(id: HelpTopicID.compositionComposition.rawValue, isActive: appModel.mode == .composition && selectedCompositionTab == .composition) {
                                            HelpTopicID.compositionComposition.content(language: session.currentLanguage)
                                        }
                                }
                                Tab(CompositionTab.pieces.label(session.currentLanguage), systemImage: CompositionTab.pieces.systemImage, value: CompositionTab.pieces) {
                                    PiecesView(session: session)
                                        .registerContextualHelp(id: HelpTopicID.compositionPieces.rawValue, isActive: appModel.mode == .composition && selectedCompositionTab == .pieces) {
                                            HelpTopicID.compositionPieces.content(language: session.currentLanguage)
                                        }
                                }
                            }
                        case .theorie:
                            TabView(selection: $selectedTheorieTab) {
                                Tab(TheorieTab.accords.label(session.currentLanguage), systemImage: TheorieTab.accords.systemImage, value: TheorieTab.accords) {
                                    ChordTabContent(session: session, isActive: appModel.mode == .theorie && selectedTheorieTab == .accords)
                                }
                                Tab(TheorieTab.modes.label(session.currentLanguage), systemImage: TheorieTab.modes.systemImage, value: TheorieTab.modes) {
                                    TheoryTabContent(session: session, isActive: appModel.mode == .theorie && selectedTheorieTab == .modes)
                                }
                                Tab(TheorieTab.progressions.label(session.currentLanguage), systemImage: TheorieTab.progressions.systemImage, value: TheorieTab.progressions) {
                                    ProgressionTabContent(session: session, isActive: appModel.mode == .theorie && selectedTheorieTab == .progressions)
                                }
                                Tab(TheorieTab.exploration.label(session.currentLanguage), systemImage: TheorieTab.exploration.systemImage, value: TheorieTab.exploration) {
                                    ExplorationTabContent(session: session, isActive: appModel.mode == .theorie && selectedTheorieTab == .exploration)
                                }
                                if horizontalSizeClass != .compact {
                                    Tab(TheorieTab.tonnetz.label(session.currentLanguage), systemImage: TheorieTab.tonnetz.systemImage, value: TheorieTab.tonnetz) {
                                        TonnetzTabContent(session: session, isActive: appModel.mode == .theorie && selectedTheorieTab == .tonnetz)
                                    }
                                }
                                Tab(TheorieTab.intonations.label(session.currentLanguage), systemImage: TheorieTab.intonations.systemImage, value: TheorieTab.intonations) {
                                    TuningTabContent(session: session, isActive: appModel.mode == .theorie && selectedTheorieTab == .intonations)
                                }
                                Tab(TheorieTab.dissonances.label(session.currentLanguage), systemImage: TheorieTab.dissonances.systemImage, value: TheorieTab.dissonances) {
                                    DissonancesTabContent(session: session, isActive: appModel.mode == .theorie && selectedTheorieTab == .dissonances)
                                }
                            }
                            // Narrower than the system default sidebar width — this menu's labels
                            // ("Progressions", "Intonations") are short enough not to need it.
                            .navigationSplitViewColumnWidth(min: 130, ideal: 150, max: 180)
                        case .settings:
                            TabView(selection: $appModel.selectedSettingsTab) {
                                Tab(SettingsTab.sons.label(session.currentLanguage), systemImage: SettingsTab.sons.systemImage, value: SettingsTab.sons) {
                                    SoundsView(session: session, isActive: appModel.mode == .settings && appModel.selectedSettingsTab == .sons)
                                }
                                Tab(SettingsTab.midi.label(session.currentLanguage), systemImage: SettingsTab.midi.systemImage, value: SettingsTab.midi) {
                                    JamShackMIDIView(session: session, bridge: bridge)
                                        .registerContextualHelp(id: HelpTopicID.settingsMidi.rawValue, isActive: appModel.mode == .settings && appModel.selectedSettingsTab == .midi) {
                                            HelpTopicID.settingsMidi.content(language: session.currentLanguage)
                                        }
                                }
                                Tab(SettingsTab.microphone.label(session.currentLanguage), systemImage: SettingsTab.microphone.systemImage, value: SettingsTab.microphone) {
                                    MicrophoneTabContent(session: session, bridge: bridge, isActive: appModel.mode == .settings && appModel.selectedSettingsTab == .microphone)
                                }
                                Tab(SettingsTab.console.label(session.currentLanguage), systemImage: SettingsTab.console.systemImage, value: SettingsTab.console) {
                                    ConsoleSettingsView(session: session)
                                        .registerContextualHelp(id: HelpTopicID.settingsConsole.rawValue, isActive: appModel.mode == .settings && appModel.selectedSettingsTab == .console) {
                                            HelpTopicID.settingsConsole.content(language: session.currentLanguage)
                                        }
                                }
                                Tab(SettingsTab.couleurs.label(session.currentLanguage), systemImage: SettingsTab.couleurs.systemImage, value: SettingsTab.couleurs) {
                                    JamShackColorsView(session: session)
                                        .registerContextualHelp(id: HelpTopicID.settingsCouleurs.rawValue, isActive: appModel.mode == .settings && appModel.selectedSettingsTab == .couleurs) {
                                            HelpTopicID.settingsCouleurs.content(language: session.currentLanguage)
                                        }
                                }
                                Tab(SettingsTab.llm.label(session.currentLanguage), systemImage: SettingsTab.llm.systemImage, value: SettingsTab.llm) {
                                    JamShackAIView(session: session)
                                        .registerContextualHelp(id: HelpTopicID.settingsLLM.rawValue, isActive: appModel.mode == .settings && appModel.selectedSettingsTab == .llm) {
                                            HelpTopicID.settingsLLM.content(language: session.currentLanguage)
                                        }
                                }
                                Tab(SettingsTab.langue.label(session.currentLanguage), systemImage: SettingsTab.langue.systemImage, value: SettingsTab.langue) {
                                    JamShackLanguageView(session: session)
                                        .registerContextualHelp(id: HelpTopicID.settingsLangue.rawValue, isActive: appModel.mode == .settings && appModel.selectedSettingsTab == .langue) {
                                            HelpTopicID.settingsLangue.content(language: session.currentLanguage)
                                        }
                                }
                                Tab(SettingsTab.notation.label(session.currentLanguage), systemImage: SettingsTab.notation.systemImage, value: SettingsTab.notation) {
                                    NotationStyleSettingsView(session: session)
                                        .registerContextualHelp(id: HelpTopicID.settingsNotation.rawValue, isActive: appModel.mode == .settings && appModel.selectedSettingsTab == .notation) {
                                            HelpTopicID.settingsNotation.content(language: session.currentLanguage)
                                        }
                                }
                            }
                        }
                    }
                    .tabViewStyle(.sidebarAdaptable)
                    // Tonnetz's `Tab` disappears at compact width (see above) — if it was the
                    // selected Théorie tab when that happens (iPad rotated into split-view, or a
                    // restored-state cold launch directly on iPhone), fall back to the same
                    // `.modes` default `selectedTheorieTab` already starts at.
                    .onChange(of: horizontalSizeClass) { _, newValue in
                        if newValue == .compact && selectedTheorieTab == .tonnetz {
                            selectedTheorieTab = .modes
                        }
                    }
                    .task {
                        if horizontalSizeClass == .compact && selectedTheorieTab == .tonnetz {
                            selectedTheorieTab = .modes
                        }
                    }
                    // Théorie's own "source principale" defaults to MIDI if connected, else the
                    // computer keyboard, the first time this mode is entered — per explicit
                    // request, rather than leaving it unset until the user happens to flip the
                    // "clavier ordinateur" toggle themselves. A no-op once any source is already
                    // picked (see `ensureTheoryLiveInputSourceHasADefault`'s own doc comment).
                    .onChange(of: appModel.mode, initial: true) { _, newMode in
                        if newMode == .theorie { session.ensureTheoryLiveInputSourceHasADefault() }
                    }

                    // Persistent, always-visible "long" keyboard — only while the computer
                    // keyboard mode is explicitly turned on (see `ComputerKeyboardSettingsView`,
                    // under Settings) AND the current screen doesn't hide it outright (see
                    // `MainKeyboardPresentation.isHidden`). Sits OUTSIDE the TabView so it stays
                    // put across every tab switch, a constant reminder that typing anywhere now
                    // plays notes. Placed ABOVE the mode-toggle bar (not below) so the toggle —
                    // the one thing you reach for constantly — stays pinned at the true bottom of
                    // the window and never shifts position when this keyboard appears/disappears,
                    // per explicit request ("stabilité de l'affichage").
                    let mainKeyboard = appModel.mainKeyboardPresentation(session: session)
                    if showsMainKeyboardControls && session.computerKeyboardInputEnabled && !mainKeyboard.isHidden {
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
                                heldPitches: mainKeyboard.heldPitches,
                                palette: bridge.state.palette, paletteTextColors: bridge.state.paletteTextColors,
                                label: appModel.mainKeyboardBarLabel(session: session),
                                octaveShift: session.computerKeyboardOctaveShift,
                                onNoteOn: { pitch in guard mainKeyboard.isClickable else { return }; session.pressKey(pitch: pitch) },
                                onNoteOff: { pitch in guard mainKeyboard.isClickable else { return }; session.releaseKey(pitch: pitch) },
                                onShiftOctave: { steps in session.shiftComputerKeyboardOctave(by: steps) },
                                modeTones: mainKeyboard.modeTones, showModeColoring: mainKeyboard.showModeColoring,
                                chordRoot: mainKeyboard.chordRoot, chordTones: mainKeyboard.chordTones, referenceChordPitches: mainKeyboard.referenceChordPitches,
                                showsPhysicalKeyLabels: session.theoryLiveInputSourceID == .computerKeyboard
                            )
                            .opacity(mainKeyboard.isClickable ? 1 : 0.5)
                        }
                        #else
                        ComputerKeyboardInputBar(
                            heldPitches: mainKeyboard.heldPitches,
                            palette: bridge.state.palette, paletteTextColors: bridge.state.paletteTextColors,
                            label: appModel.mainKeyboardBarLabel(session: session),
                            octaveShift: session.computerKeyboardOctaveShift,
                            onNoteOn: { pitch in guard mainKeyboard.isClickable else { return }; session.pressKey(pitch: pitch) },
                            onNoteOff: { pitch in guard mainKeyboard.isClickable else { return }; session.releaseKey(pitch: pitch) },
                            onShiftOctave: { steps in session.shiftComputerKeyboardOctave(by: steps) },
                            modeTones: mainKeyboard.modeTones, showModeColoring: mainKeyboard.showModeColoring,
                            chordRoot: mainKeyboard.chordRoot, chordTones: mainKeyboard.chordTones, referenceChordPitches: mainKeyboard.referenceChordPitches,
                            showsPhysicalKeyLabels: session.theoryLiveInputSourceID == .computerKeyboard
                        )
                        .opacity(mainKeyboard.isClickable ? 1 : 0.5)
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
                                appModel.mode = candidate
                            } label: {
                                Label(candidate.label(session.currentLanguage), systemImage: candidate.systemImage)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(appModel.mode == candidate ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(appModel.mode == candidate ? Color.accentColor : Color.primary)
                        }
                        if showsMainKeyboardControls {
                            // Separates the mode selector from the main-keyboard controls, per
                            // explicit request — and, with a `Spacer()` on BOTH sides, roughly
                            // centers this group in the remaining space instead of it hugging
                            // the divider, also per explicit request.
                            Divider().frame(height: 20)
                            Spacer()
                            Button {
                                session.setComputerKeyboardInputEnabled(!session.computerKeyboardInputEnabled)
                            } label: {
                                Label(L10n.string(.appTabClavierPrincipal, session.currentLanguage), systemImage: "keyboard")
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
                        // "Source principale" (see `ImprovSession.theoryLiveInputSourceID`'s own
                        // doc comment) + the shared audition sound, both right-aligned — per
                        // explicit request. Used to be Théorie-only; now shown in Studio too
                        // (not Settings, which isn't a "live playing" context — same gate the
                        // computer-keyboard toggle above already uses) since this is also what
                        // decides whether the computer-keyboard toggle's typing actually plays
                        // anything (see `.computerKeyboardInput(isActive:)` below) — independent
                        // of that toggle's own on/off state, per explicit request: hiding the
                        // main keyboard must NOT forget which source was picked. Live-match
                        // REACTION (selecting a chord/note as if tapped) only actually happens on
                        // Exploration, the one screen with anything to react on, but every other
                        // screen still benefits from simply being able to hear what's played.
                        if showsMainKeyboardControls {
                            theorieLiveInputSourcePicker(session: session)
                            if appModel.mode == .theorie {
                                FavoriteSoundPickerView(
                                    favoriteSounds: session.favoriteSounds,
                                    selectedID: Binding(
                                        get: { session.theoryAuditionSoundID },
                                        set: { try? session.setTheoryAuditionSoundID($0) }
                                    ),
                                    language: session.currentLanguage
                                )
                                .labelsHidden()
                                .font(.caption)
                                .frame(maxWidth: Self.bottomBarLabelMaxWidth)
                                // Quick access to the active temperament/A4 reference
                                // (`session.tuningConfiguration`) from any Théorie tab, without
                                // navigating to Intonations — per explicit request. Used to be a
                                // passive reminder, hidden for "Égal"; now always shown (it's a
                                // real control, not just a readout) — the tonic+mode line stays
                                // passive (Intonations' own tonic/scale picker is still the only
                                // place that changes it) and still hides for "Égal" alone, same
                                // as before, since a mode reminder next to the no-op default
                                // reads as noise.
                                Button {
                                    showsTuningQuickPicker = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "tuningfork")
                                        VStack(alignment: .trailing, spacing: 0) {
                                            Text(temperamentLabel(forID: session.tuningConfiguration.temperamentID, language: session.currentLanguage))
                                                .font(.caption)
                                            if session.tuningConfiguration.temperamentID != "equal", let contextualMode = session.contextualMode {
                                                Text(contextualMode.displayName)
                                                    .font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(session.tuningConfiguration.temperamentID != "equal" ? Color.accentColor : Color.secondary)
                                .popover(isPresented: $showsTuningQuickPicker) {
                                    TuningQuickPickerView(session: session)
                                }
                            } else if appModel.mode == .studio {
                                // Studio: read-only, per explicit request — see
                                // `studioAssignedSoundLabel(session:)`'s own doc comment for why
                                // this doesn't reuse Théorie's editable picker.
                                Text(appModel.studioAssignedSoundLabel(session: session))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: Self.bottomBarLabelMaxWidth, alignment: .trailing)
                            }
                            // Settings > Sons: no sound label here — the sound being tested is
                            // whichever one is picked in the library screen itself, not a
                            // dropdown, per explicit request ("pas de sens ici").
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
                    // Both conditions, not just the toggle — per explicit request: typing must
                    // stay silent whenever the main keyboard is hidden (even if "Clavier
                    // ordinateur" is still the picked source from a previous session), so a
                    // keystroke typed elsewhere in the UI can never surprise-trigger a note.
                    isActive: session.computerKeyboardInputEnabled && session.theoryLiveInputSourceID == .computerKeyboard,
                    focusRequestToken: session.computerKeyboardFocusRequestToken,
                    octaveShift: session.computerKeyboardOctaveShift,
                    onNoteOn: { pitch in session.pressKey(pitch: pitch) },
                    onNoteOff: { pitch in session.releaseKey(pitch: pitch) },
                    onShiftOctave: { steps in session.shiftComputerKeyboardOctave(by: steps) }
                )
                // "Jouer"/"éditer le guide" cross-mode navigation (see
                // `AppModel.GuideNavigationDestination`'s own doc comment) — `GuideView`/
                // `StudioGuidePlayTabContent` react to the SAME token to jump their own internal
                // screen; this is the one place that actually switches `mode`/the relevant tab.
                .onChange(of: appModel.guideNavigationRequestToken) { _, _ in
                    switch appModel.guideNavigationRequest {
                    case .playInStudio:
                        appModel.mode = .studio
                        appModel.selectedStudioTab = .guide
                    case .editInComposition:
                        appModel.mode = .composition
                        selectedCompositionTab = .guide
                    case nil:
                        break
                    }
                }
                #if !os(macOS) && !os(visionOS)
                // No independent-window equivalent on iOS/iPadOS — a dismissible sheet instead,
                // same convention `ModeLibraryView`'s own former legend sheet already used. Backed
                // by `appModel.showsContextualHelpSheet` (not a local `@State`) so any per-screen
                // help button (`TheoryHelpButton`), not just this bottom-bar one, can trigger it.
                .sheet(isPresented: Binding(get: { appModel.showsContextualHelpSheet }, set: { appModel.showsContextualHelpSheet = $0 })) {
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                // Same `pinnedHelpTopic`-first priority as `ContextualHelpWindow`
                                // — see `AppModel.pinnedHelpTopic`'s own doc comment.
                                if let pinned = appModel.pinnedHelpTopic {
                                    Button {
                                        appModel.pinnedHelpTopic = nil
                                    } label: {
                                        Label(L10n.string(.appHelpButtonRetour, session.currentLanguage), systemImage: "chevron.backward")
                                    }
                                    .buttonStyle(.plain)
                                    pinned.content(language: session.currentLanguage)
                                } else if let content = appModel.contextualHelpContent {
                                    content()
                                }
                            }
                            .padding()
                        }
                        // A separate SwiftUI hierarchy from `ContextualHelpWindow`'s own
                        // `WindowGroup` — `.environment(\.openURL, ...)` does NOT propagate
                        // between the two, so this needs its own independent installation.
                        .interceptHelpLinks(pinnedTopic: Binding(get: { appModel.pinnedHelpTopic }, set: { appModel.pinnedHelpTopic = $0 }))
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L10n.string(.appButtonFermer, session.currentLanguage)) { appModel.showsContextualHelpSheet = false }
                            }
                        }
                    }
                }
                #endif
        }
    }

    /// Same id → display-name mapping `TuningLibraryView.label(forTemperamentID:)` uses for its
    /// own picker — duplicated rather than shared since one is a `View` method and this is a
    /// free-standing label used inline in a string format, not worth a new shared type for 4 ids.
    private func temperamentLabel(forID id: String, language: AppLanguage) -> String {
        switch id {
        case "equal": return "\(L10n.string(.appTemperamentEqual, language)) \(L10n.string(.appLabelParDefaut, language))"
        case "pythagorean": return L10n.string(.appTemperamentPythagorean, language)
        case "justIntonation": return L10n.string(.appTemperamentJustIntonation, language)
        case "werckmeisterIII": return L10n.string(.appTemperamentWerckmeisterIII, language)
        default: return id
        }
    }

    /// The generalized contextual-help button — opens `AuxiliaryWindowID.contextualHelp`
    /// (macOS/visionOS) or `appModel.showsContextualHelpSheet` (elsewhere) to show whichever
    /// screen is currently active's own registered help (see `View.registerContextualHelp`).
    /// Only ever shown by its own call site when `appModel.contextualHelpContent != nil`. Same
    /// underlying trigger `TheoryHelpButton` uses for its own per-screen equivalent.
    private func contextualHelpButton(session: ImprovSession) -> some View {
        Button {
            // Reset before opening — see `AppModel.pinnedHelpTopic`'s own doc comment.
            appModel.pinnedHelpTopic = nil
            #if os(macOS) || os(visionOS)
            openWindow(id: AuxiliaryWindowID.contextualHelp.rawValue)
            #else
            appModel.showsContextualHelpSheet = true
            #endif
        } label: {
            Image(systemName: "questionmark.circle")
        }
        .buttonStyle(.plain)
    }

    /// A dumb `Picker` over `session.theoryLiveInputSources` — all the arm/disarm side effects
    /// (e.g. starting the microphone) live in `ImprovSession.setTheoryLiveInputSource`, not here.
    /// Shared width for the source/son labels in the bottom bar — wide enough that a longer MIDI
    /// device name or sound title stays on one line instead of wrapping and stretching the bar's
    /// own height, per explicit request.
    private static let bottomBarLabelMaxWidth: CGFloat = 220

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
        .font(.caption)
        .frame(maxWidth: Self.bottomBarLabelMaxWidth)
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
