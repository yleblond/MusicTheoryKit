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
    private enum AppMode: CaseIterable, Identifiable, Hashable {
        case studio, theorie, composition, settings
        var id: Self { self }

        var systemImage: String {
            switch self {
            case .studio: return "pianokeys"
            case .theorie: return "flask.fill"
            case .composition: return "pencil.and.outline"
            case .settings: return "gearshape"
            }
        }

        func label(_ language: AppLanguage) -> String {
            switch self {
            case .studio: return L10n.string(.appTabStudio, language)
            case .theorie: return L10n.string(.appTabTheorie, language)
            case .composition: return L10n.string(.catComposition, language)
            case .settings: return L10n.string(.appButtonReglages, language)
            }
        }
    }

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
    private enum StudioTab: CaseIterable, Identifiable {
        case scene, live, guide, recordings, jamSession

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .scene: return "theatermasks"
            case .live: return "pianokeys"
            case .guide: return "map"
            case .recordings: return "record.circle"
            case .jamSession: return "person.2.fill"
            }
        }

        func label(_ language: AppLanguage) -> String {
            switch self {
            case .scene: return L10n.string(.tabScene, language)
            case .live: return L10n.string(.appLabelEnDirect, language)
            case .guide: return L10n.string(.headingGuide, language)
            case .recordings: return L10n.string(.appTabEnregistrements, language)
            case .jamSession: return L10n.string(.catJamSession, language)
            }
        }
    }

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

    /// The settings-mode tabs — was `JamShackView`'s own internal sub-tab rail, hoisted here
    /// (now that there's no wrapping "JamShack" tab to hold them), pared down since (Dossiers,
    /// Cadrages merged into I.A., and Clavier ordinateur all removed as redundant/vestigial —
    /// see each removal's own commit/doc history). No dedicated "Clavier ordinateur" tab: its
    /// entire content was a single on/off toggle for `computerKeyboardInputEnabled`, already
    /// exposed via the quick-toggle button in the bottom bar below (Studio mode only) — keeping
    /// both was pure duplication with zero extra capability in the tab.
    private enum SettingsTab: CaseIterable, Identifiable {
        // `.console` used to be `.jamSession`, hosting the web-console server card AND the
        // collaborative jam-session flows (clavier virtuel + appareils connectés) together — the
        // latter moved to Studio's own new "Jam Session" tab (`StudioTab.jamSession`), per
        // explicit request (inviting others to play is a Studio activity, not a setting), leaving
        // only the web console here.
        case sons, midi, microphone, console, couleurs, llm, langue, notation

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .sons: return "music.note.list"
            case .midi: return "pianokeys"
            case .microphone: return "mic"
            case .console: return "network"
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
            case .console: return L10n.string(.appTabConsole, language)
            case .couleurs: return L10n.string(.appTabCouleurs, language)
            case .llm: return L10n.string(.appTabLLM, language)
            case .langue: return L10n.string(.appTabLangue, language)
            case .notation: return L10n.string(.appTabNotation, language)
            }
        }
    }

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

    @State private var mode: AppMode = .studio
    // Same default as the old `StudioView` — that's where you set up which instrument sounds
    // through which role before playing, so it's the natural first screen.
    @State private var selectedStudioTab: StudioTab = .scene
    @State private var selectedTheorieTab: TheorieTab = .modes
    @State private var selectedCompositionTab: CompositionTab = .guide
    @State private var selectedSettingsTab: SettingsTab = .sons
    /// Drives the bottom bar's tuning-fork button (see `temperamentQuickPickerButton`) — lets
    /// the temperament/A4 reference be changed from any Théorie tab without navigating to
    /// Intonations, per explicit request.
    @State private var showsTuningQuickPicker = false

    /// Studio/Théorie always show the main-keyboard bar's own controls (toggle, detach,
    /// source picker); Settings only does while its own "Sons" sub-tab is active (testing a
    /// soundfont there plays through the same "source principale" — see `SoundsView`), per
    /// explicit request. Composition never does.
    private var showsMainKeyboardControls: Bool {
        mode == .studio || mode == .theorie || (mode == .settings && selectedSettingsTab == .sons)
    }

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
                                Tab(StudioTab.scene.label(session.currentLanguage), systemImage: StudioTab.scene.systemImage, value: StudioTab.scene) {
                                    SceneManagementView(session: session)
                                }
                                Tab(StudioTab.live.label(session.currentLanguage), systemImage: StudioTab.live.systemImage, value: StudioTab.live) {
                                    LiveTabContent(session: session, bridge: bridge)
                                }
                                Tab(StudioTab.guide.label(session.currentLanguage), systemImage: StudioTab.guide.systemImage, value: StudioTab.guide) {
                                    StudioGuidePlayTabContent(session: session, bridge: bridge)
                                }
                                Tab(StudioTab.recordings.label(session.currentLanguage), systemImage: StudioTab.recordings.systemImage, value: StudioTab.recordings) {
                                    RecordingsView(session: session)
                                }
                                Tab(StudioTab.jamSession.label(session.currentLanguage), systemImage: StudioTab.jamSession.systemImage, value: StudioTab.jamSession) {
                                    StudioJamSessionTabContent(session: session)
                                }
                            }
                        case .composition:
                            TabView(selection: $selectedCompositionTab) {
                                Tab(CompositionTab.guide.label(session.currentLanguage), systemImage: CompositionTab.guide.systemImage, value: CompositionTab.guide) {
                                    GuideView(session: session, bridge: bridge)
                                }
                                Tab(CompositionTab.composition.label(session.currentLanguage), systemImage: CompositionTab.composition.systemImage, value: CompositionTab.composition) {
                                    CompositionView(session: session)
                                }
                                Tab(CompositionTab.pieces.label(session.currentLanguage), systemImage: CompositionTab.pieces.systemImage, value: CompositionTab.pieces) {
                                    PiecesView(session: session)
                                }
                            }
                        case .theorie:
                            TabView(selection: $selectedTheorieTab) {
                                Tab(TheorieTab.accords.label(session.currentLanguage), systemImage: TheorieTab.accords.systemImage, value: TheorieTab.accords) {
                                    ChordTabContent(session: session, isActive: mode == .theorie && selectedTheorieTab == .accords)
                                }
                                Tab(TheorieTab.modes.label(session.currentLanguage), systemImage: TheorieTab.modes.systemImage, value: TheorieTab.modes) {
                                    TheoryTabContent(session: session, isActive: mode == .theorie && selectedTheorieTab == .modes)
                                }
                                Tab(TheorieTab.progressions.label(session.currentLanguage), systemImage: TheorieTab.progressions.systemImage, value: TheorieTab.progressions) {
                                    ProgressionTabContent(session: session, isActive: mode == .theorie && selectedTheorieTab == .progressions)
                                }
                                Tab(TheorieTab.exploration.label(session.currentLanguage), systemImage: TheorieTab.exploration.systemImage, value: TheorieTab.exploration) {
                                    ExplorationTabContent(session: session, isActive: mode == .theorie && selectedTheorieTab == .exploration)
                                }
                                if horizontalSizeClass != .compact {
                                    Tab(TheorieTab.tonnetz.label(session.currentLanguage), systemImage: TheorieTab.tonnetz.systemImage, value: TheorieTab.tonnetz) {
                                        TonnetzTabContent(session: session, isActive: mode == .theorie && selectedTheorieTab == .tonnetz)
                                    }
                                }
                                Tab(TheorieTab.intonations.label(session.currentLanguage), systemImage: TheorieTab.intonations.systemImage, value: TheorieTab.intonations) {
                                    TuningTabContent(session: session, isActive: mode == .theorie && selectedTheorieTab == .intonations)
                                }
                                Tab(TheorieTab.dissonances.label(session.currentLanguage), systemImage: TheorieTab.dissonances.systemImage, value: TheorieTab.dissonances) {
                                    DissonancesTabContent(session: session, isActive: mode == .theorie && selectedTheorieTab == .dissonances)
                                }
                            }
                        case .settings:
                            TabView(selection: $selectedSettingsTab) {
                                Tab(SettingsTab.sons.label(session.currentLanguage), systemImage: SettingsTab.sons.systemImage, value: SettingsTab.sons) {
                                    SoundsView(session: session, isActive: mode == .settings && selectedSettingsTab == .sons)
                                }
                                Tab(SettingsTab.midi.label(session.currentLanguage), systemImage: SettingsTab.midi.systemImage, value: SettingsTab.midi) {
                                    JamShackMIDIView(session: session, bridge: bridge)
                                }
                                Tab(SettingsTab.microphone.label(session.currentLanguage), systemImage: SettingsTab.microphone.systemImage, value: SettingsTab.microphone) {
                                    MicrophoneTabContent(session: session, bridge: bridge)
                                }
                                Tab(SettingsTab.console.label(session.currentLanguage), systemImage: SettingsTab.console.systemImage, value: SettingsTab.console) {
                                    ConsoleSettingsView(session: session)
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

                    // Persistent, always-visible "long" keyboard — only while the computer
                    // keyboard mode is explicitly turned on (see `ComputerKeyboardSettingsView`,
                    // under Settings) AND the current screen doesn't hide it outright (see
                    // `MainKeyboardPresentation.isHidden`). Sits OUTSIDE the TabView so it stays
                    // put across every tab switch, a constant reminder that typing anywhere now
                    // plays notes. Placed ABOVE the mode-toggle bar (not below) so the toggle —
                    // the one thing you reach for constantly — stays pinned at the true bottom of
                    // the window and never shifts position when this keyboard appears/disappears,
                    // per explicit request ("stabilité de l'affichage").
                    let mainKeyboard = mainKeyboardPresentation(session: session)
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
                                label: mainKeyboardBarLabel(session: session),
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
                            label: mainKeyboardBarLabel(session: session),
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
                            if mode == .theorie {
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
                            } else if mode == .studio {
                                // Studio: read-only, per explicit request — see
                                // `studioAssignedSoundLabel(session:)`'s own doc comment for why
                                // this doesn't reuse Théorie's editable picker.
                                Text(studioAssignedSoundLabel(session: session))
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
                        mode = .studio
                        selectedStudioTab = .guide
                    case .editInComposition:
                        mode = .composition
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
                            if let content = appModel.contextualHelpContent { content().padding() }
                        }
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

    /// Everything the persistent main-keyboard bar needs to render for the CURRENT screen —
    /// unified across Théorie (`AppModel.mainKeyboardMode`, a fixed reference mode picked on that
    /// screen) and Studio (per explicit request: "En Direct" mirrors whichever track is picked as
    /// "source principale" exactly like that track's own row in the circle-of-fifths list already
    /// does; "Scène" shows the same track plain, no coloring; "Guide" colors by the current step's
    /// own mode ONLY while a guide sequence is actually running; "Enregistrements"/"Composition"/
    /// "Morceaux" hide the bar outright, since it serves no purpose there) — computed once so
    /// `body` only ever reads ONE value instead of re-deriving this per branch.
    private struct MainKeyboardPresentation {
        var isHidden = false
        var heldPitches: Set<Int> = []
        var chordRoot: Int?
        var chordTones: [Int] = []
        var modeTones: [Int] = []
        var showModeColoring = false
        /// Non-empty when the Accords screen wants this bar to show ITS OWN chord as a centered
        /// reference voicing (one occurrence of each tone), per explicit request — see
        /// `AppModel.mainKeyboardChord`/`PitchKeyboardView.referenceChordPitches`.
        var referenceChordPitches: Set<Int> = []
        /// Whether tapping/clicking the bar's own on-screen keys should do anything — per
        /// explicit request, ONLY when the picked source really is `.computerKeyboard` (any other
        /// source is already played through its own real input — a MIDI keyboard, the
        /// microphone — not by clicking this reference bar) AND, in Studio, that source is
        /// actually wired to a role with a sound in the active scene (nothing to play otherwise).
        var isClickable = true
    }

    private func mainKeyboardPresentation(session: ImprovSession) -> MainKeyboardPresentation {
        let sourceID = session.theoryLiveInputSourceID
        var presentation = MainKeyboardPresentation()
        // Always whatever's held on the picked source track, regardless of screen — the bar is
        // "clavier principal," not "clavier ordinateur," so it should never stay hardcoded to
        // showing only the `.computerKeyboard` track's own held notes.
        presentation.heldPitches = sourceID.flatMap { id in session.tracks.first { $0.id == id } }?.heldPitches ?? []
        let isComputerKeyboardSource = sourceID == .computerKeyboard

        switch mode {
        case .theorie:
            if let theoryMode = appModel.mainKeyboardMode {
                presentation.modeTones = theoryMode.pitchClasses.map(\.value)
                presentation.showModeColoring = true
            }
            // The Accords screen's own chord, centered (one voicing, not repeated every
            // octave) — per explicit request. Mutually exclusive with `mainKeyboardMode` in
            // practice (only one Théorie sub-tab is ever active at a time).
            if let chordSpec = appModel.mainKeyboardChord {
                presentation.chordRoot = chordSpec.root
                presentation.chordTones = chordSpec.tones
                presentation.referenceChordPitches = Set(PitchSequencing.ascendingPitches(forPitchClasses: chordSpec.tones, startingAbove: 47))
            }
            presentation.isClickable = isComputerKeyboardSource
        case .studio:
            switch selectedStudioTab {
            case .recordings, .jamSession:
                presentation.isHidden = true
            case .live:
                if let sourceID {
                    let recognized = session.recognizedChordAndModeTones(for: sourceID)
                    presentation.chordRoot = recognized.chordRoot
                    presentation.chordTones = recognized.chordTones
                    presentation.modeTones = recognized.modeTones
                    presentation.showModeColoring = !recognized.modeTones.isEmpty
                }
                presentation.isClickable = isComputerKeyboardSource && studioSourceHasAssignedSound(session: session, sourceID: sourceID)
            case .scene:
                // Plain — no chord/mode coloring, per explicit request ("sans coloration").
                presentation.isClickable = isComputerKeyboardSource && studioSourceHasAssignedSound(session: session, sourceID: sourceID)
            case .guide:
                // Only while a guide sequence is actually running (`currentGuideStepIndex`) —
                // per explicit request ("si le guide n'est pas démarré, pas de coloration").
                if session.currentGuideStepIndex != nil, let guideMode = session.currentGuideStepMode() {
                    presentation.modeTones = guideMode.pitchClasses.map(\.value)
                    presentation.showModeColoring = true
                }
                presentation.isClickable = isComputerKeyboardSource && studioSourceHasAssignedSound(session: session, sourceID: sourceID)
            }
        case .settings:
            // Only "Sons" — the one Settings sub-tab that actually plays sound (testing a
            // soundfont, see `SoundsView`/`SoundTestModeController`) — per explicit request;
            // every other sub-tab hides the bar just like Composition does. Plain, no
            // coloring: there's no chord/mode context to reflect here, just a way to hear what
            // gets picked in the library.
            if selectedSettingsTab == .sons {
                presentation.isClickable = isComputerKeyboardSource
            } else {
                presentation.isHidden = true
            }
        case .composition:
            presentation.isHidden = true
        }
        return presentation
    }

    /// Whether `sourceID` is attached to a role WITH a sound in the active scene — Studio's own
    /// gate for `MainKeyboardPresentation.isClickable` (see that property's own doc comment) and
    /// for `studioAssignedSoundLabel(session:)`'s "aucun son affecté" fallback.
    private func studioSourceHasAssignedSound(session: ImprovSession, sourceID: TrackID?) -> Bool {
        guard let sourceID else { return false }
        return session.currentScene?.roles.contains { $0.attachedTrackID == sourceID && $0.soundName != nil } ?? false
    }

    /// Studio's own read-only counterpart to Théorie's editable `FavoriteSoundPickerView` — per
    /// explicit request, the sound here is whatever the active scene already assigns to the
    /// picked source's role, not a separate independent pick (editing that belongs to the Scene
    /// screen's own role editor). "Aucun son affecté" whenever that source isn't wired to any
    /// role with a sound — per explicit request, a visible non-answer rather than silently
    /// falling back to Théorie's own generic audition sound, which would misleadingly suggest
    /// something is really about to play.
    private func studioAssignedSoundLabel(session: ImprovSession) -> String {
        guard let sourceID = session.theoryLiveInputSourceID,
              let role = session.currentScene?.roles.first(where: { $0.attachedTrackID == sourceID }),
              let soundName = role.soundName
        else {
            return L10n.string(.appLabelAucunSonAffecte, session.currentLanguage)
        }
        return session.displayName(forSamplePath: soundName, preset: role.soundPreset)
    }

    /// Same id → display-name mapping `TuningLibraryView.label(forTemperamentID:)` uses for its
    /// own picker — duplicated rather than shared since one is a `View` method and this is a
    /// free-standing label used inline in a string format, not worth a new shared type for 4 ids.
    private func temperamentLabel(forID id: String, language: AppLanguage) -> String {
        switch id {
        case "equal": return L10n.string(.appTemperamentEqual, language)
        case "pythagorean": return L10n.string(.appTemperamentPythagorean, language)
        case "justIntonation": return L10n.string(.appTemperamentJustIntonation, language)
        case "werckmeisterIII": return L10n.string(.appTemperamentWerckmeisterIII, language)
        default: return id
        }
    }

    /// "Notes du mode" whenever a Théorie screen has registered one for the persistent
    /// main-keyboard bar (`AppModel.mainKeyboardMode`, see `.registerMainKeyboardMode`), or
    /// Studio's Guide screen is actively coloring by its own current step, else the bar's own
    /// plain "clavier principal actif" label.
    private func mainKeyboardBarLabel(session: ImprovSession) -> String {
        if mode == .studio, selectedStudioTab == .guide, session.currentGuideStepIndex != nil {
            return L10n.string(.appLabelNotesDuMode, session.currentLanguage)
        }
        return appModel.mainKeyboardMode != nil
            ? L10n.string(.appLabelNotesDuMode, session.currentLanguage)
            : L10n.string(.appLabelClavierPrincipalActif, session.currentLanguage)
    }

    /// The generalized contextual-help button — opens `AuxiliaryWindowID.contextualHelp`
    /// (macOS/visionOS) or `appModel.showsContextualHelpSheet` (elsewhere) to show whichever
    /// screen is currently active's own registered help (see `View.registerContextualHelp`).
    /// Only ever shown by its own call site when `appModel.contextualHelpContent != nil`. Same
    /// underlying trigger `TheoryHelpButton` uses for its own per-screen equivalent.
    private func contextualHelpButton(session: ImprovSession) -> some View {
        Button {
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
