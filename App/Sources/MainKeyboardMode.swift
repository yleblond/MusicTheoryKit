import SwiftUI
import AppCore
import Localization
import MusicTheoryKit

/// Which of the 4 flat tab sets is showing — moved here from `ContentView` (2026-08) so
/// `AppModel.mode` can be typed with it; see `AppModel.mode`'s own doc comment for why.
enum AppMode: CaseIterable, Identifiable, Hashable {
    /// `.home` — the app's live-topology diagram (`StatusGraphView`), read-only for now — per
    /// explicit request, its own top-level mode (not a Settings sub-tab) so it can double as an
    /// easy-to-find, self-explanatory entry point; first in `allCases` so it's the leading tab.
    case home, studio, theorie, composition, settings
    var id: Self { self }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .studio: return "pianokeys"
        case .theorie: return "flask.fill"
        case .composition: return "pencil.and.outline"
        case .settings: return "gearshape"
        }
    }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .home: return L10n.string(.appTabAccueil, language)
        case .studio: return L10n.string(.appTabStudio, language)
        case .theorie: return L10n.string(.appTabTheorie, language)
        case .composition: return L10n.string(.catComposition, language)
        case .settings: return L10n.string(.appButtonReglages, language)
        }
    }
}

/// Studio's own tabs — moved here from `ContentView` (2026-08) alongside `AppMode`, same reason.
enum StudioTab: CaseIterable, Identifiable {
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

/// The settings-mode tabs — moved here from `ContentView` (2026-08) alongside `AppMode`, same
/// reason (only `.sons` is actually read by `mainKeyboardPresentation`, but the whole enum moves
/// since `AppModel.selectedSettingsTab` needs it as its type).
enum SettingsTab: CaseIterable, Identifiable {
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

extension AppModel {
    /// Everything the persistent main-keyboard bar needs to render for the CURRENT screen —
    /// moved here from `ContentView` (2026-08) as an `AppModel` extension (reading `self.mode`/
    /// `self.selectedStudioTab`/`self.selectedSettingsTab`/`self.mainKeyboardMode`/
    /// `self.mainKeyboardChord` directly instead of taking them as parameters) so BOTH
    /// `ContentView`'s embedded bar AND the detached `ComputerKeyboardWindow` compute the exact
    /// same presentation from the exact same shared state — previously `ComputerKeyboardWindow`
    /// hand-rolled a simplified subset that didn't know which Studio tab (if any) was active.
    struct MainKeyboardPresentation {
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

    func mainKeyboardPresentation(session: ImprovSession) -> MainKeyboardPresentation {
        let sourceID = session.theoryLiveInputSourceID
        var presentation = MainKeyboardPresentation()
        // Always whatever's held on the picked source track, regardless of screen — the bar is
        // "clavier principal," not "clavier ordinateur," so it should never stay hardcoded to
        // showing only the `.computerKeyboard` track's own held notes.
        presentation.heldPitches = sourceID.flatMap { id in session.tracks.first { $0.id == id } }?.heldPitches ?? []
        let isComputerKeyboardSource = sourceID == .computerKeyboard

        switch mode {
        case .theorie:
            if let theoryMode = mainKeyboardMode {
                presentation.modeTones = theoryMode.pitchClasses.map(\.value)
                presentation.showModeColoring = true
            }
            // The Accords screen's own chord, centered (one voicing, not repeated every
            // octave) — per explicit request. Mutually exclusive with `mainKeyboardMode` in
            // practice (only one Théorie sub-tab is ever active at a time).
            if let chordSpec = mainKeyboardChord {
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
        case .home:
            // A read-only status diagram, not a "play here" screen — same "no purpose here"
            // reasoning as Composition; the diagram's own per-source activity markers already
            // show what's live, per explicit request that this screen stays observational.
            presentation.isHidden = true
        }
        return presentation
    }

    /// Whether `sourceID` is attached to a role WITH a sound in the active scene — Studio's own
    /// gate for `MainKeyboardPresentation.isClickable` (see that property's own doc comment) and
    /// for `studioAssignedSoundLabel(session:)`'s "aucun son affecté" fallback.
    func studioSourceHasAssignedSound(session: ImprovSession, sourceID: TrackID?) -> Bool {
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
    func studioAssignedSoundLabel(session: ImprovSession) -> String {
        guard let sourceID = session.theoryLiveInputSourceID,
              let role = session.currentScene?.roles.first(where: { $0.attachedTrackID == sourceID }),
              let soundName = role.soundName
        else {
            return L10n.string(.appLabelAucunSonAffecte, session.currentLanguage)
        }
        return session.displayName(forSamplePath: soundName, preset: role.soundPreset)
    }

    /// "Notes du mode" whenever a Théorie screen has registered one for the persistent
    /// main-keyboard bar (`mainKeyboardMode`, see `.registerMainKeyboardMode`), or Studio's Guide
    /// screen is actively coloring by its own current step, else the bar's own plain "clavier
    /// principal actif" label.
    func mainKeyboardBarLabel(session: ImprovSession) -> String {
        if mode == .studio, selectedStudioTab == .guide, session.currentGuideStepIndex != nil {
            return L10n.string(.appLabelNotesDuMode, session.currentLanguage)
        }
        return mainKeyboardMode != nil
            ? L10n.string(.appLabelNotesDuMode, session.currentLanguage)
            : L10n.string(.appLabelClavierPrincipalActif, session.currentLanguage)
    }
}

extension View {
    /// Registers `mode` as driving the persistent main-keyboard bar's own coloring (mode-tone
    /// fill + scale-degree badges — see `AppModel.mainKeyboardMode`'s own doc comment) whenever
    /// `isActive` is true. Same `isActive`-driven design as `registerContextualHelp` — see that
    /// modifier's own doc comment for why `.onAppear`/`.onDisappear` can't be trusted here (tab
    /// content stays mounted across switches in this app). Also reacts to `mode` itself changing
    /// while already active (e.g. picking a different tonic/scale on the same screen), which
    /// `registerContextualHelp` never needed to since its content doesn't vary that way.
    func registerMainKeyboardMode(id: String, isActive: Bool, mode: Mode?) -> some View {
        modifier(MainKeyboardModeRegistration(id: id, isActive: isActive, mode: mode))
    }
}

private struct MainKeyboardModeRegistration: ViewModifier {
    @Environment(AppModel.self) private var appModel
    let id: String
    let isActive: Bool
    let mode: Mode?

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive, initial: true) { _, active in
                if active {
                    appModel.setMainKeyboardMode(id: id, mode: mode)
                } else {
                    appModel.clearMainKeyboardMode(id: id)
                }
            }
            .onChange(of: mode) { _, newMode in
                guard isActive else { return }
                appModel.setMainKeyboardMode(id: id, mode: newMode)
            }
    }
}

/// See `AppModel.mainKeyboardChord`'s own doc comment — root pitch class + tones (pitch
/// classes, including the root), the Chord Library's own equivalent of `Mode` for this purpose.
public struct MainKeyboardChordSpec: Equatable {
    public let root: Int
    public let tones: [Int]

    public init(root: Int, tones: [Int]) {
        self.root = root
        self.tones = tones
    }
}

extension View {
    /// Registers `chord` as driving the persistent main-keyboard bar's own centered reference
    /// voicing (see `AppModel.mainKeyboardChord`'s own doc comment) whenever `isActive` is true —
    /// the Chord Library's own counterpart to `registerMainKeyboardMode` above (same design,
    /// same reasoning for why `isActive` rather than `.onAppear`/`.onDisappear`).
    func registerMainKeyboardChord(id: String, isActive: Bool, chord: MainKeyboardChordSpec?) -> some View {
        modifier(MainKeyboardChordRegistration(id: id, isActive: isActive, chord: chord))
    }
}

private struct MainKeyboardChordRegistration: ViewModifier {
    @Environment(AppModel.self) private var appModel
    let id: String
    let isActive: Bool
    let chord: MainKeyboardChordSpec?

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive, initial: true) { _, active in
                if active {
                    appModel.setMainKeyboardChord(id: id, chord: chord)
                } else {
                    appModel.clearMainKeyboardChord(id: id)
                }
            }
            .onChange(of: chord) { _, newChord in
                guard isActive else { return }
                appModel.setMainKeyboardChord(id: id, chord: newChord)
            }
    }
}
