import SwiftUI
import AppCore
import JamShackUI
import MusicTheoryKit
import PieceModel
import RecognitionEngine
import ScoreImport
import Localization

/// Which of the two peer Théorie tabs this instance is — see `ContentView.TheorieTab`. Both
/// share every other part of this view (the tonic/scale picker, all the underlying
/// state/helpers) since they're really "the same screen, showing a different half of its
/// content" — factored as one parameterized `ModeLibraryView` rather than two near-duplicate
/// files, with each `Tab()` in `ContentView` constructing its OWN separate instance. Until
/// 2026-08-16 "Mode"'s and "Exploration"'s tonic/scale picks were kept entirely independent
/// (`usesSharedModeSelection: false` for Exploration) — reversed by explicit request: Exploration
/// now shares `AppModel.sharedMode` like every other MusicLab screen, so picking a mode on either
/// tab (or Progressions/Intonations/Tonnetz/Dissonances) is reflected everywhere. The two still
/// need separate `ModeLibraryView` instances regardless (different `contentFocus`/layout), this
/// just no longer means separate STATE.
enum ModeLibraryContentFocus {
    case overview, exploration
}

/// "Modes"/"Exploration" tabs — pick a tonic + mode/scale (`ScaleLibrary`), then see either:
///
/// - `.overview`: a 2-column × 3-row `Grid` (narrow notation column on the left, wide keyboard
///   column on the right — see `ChordStaffView`'s `widthScale`): row 1 is the mode's own scale
///   (+ Asc/Desc/Asc-et-Desc, each button plays immediately) next to the mode's keyboard (with
///   note-name bullets and degree badges); row 2 is the mode's harmonized chords (+ a "play the
///   sequence" button) next to whichever chord was last tapped, on its own keyboard; row 3 is
///   the chord list (each playable on tap, labeled with its functional-harmony role — see
///   `FunctionalHarmonyTable`) next to a circle-of-fifths section reusing
///   `CircleOfFifthsWheelView` for an arbitrary picked tonic (see `ImprovSession.wheelState`).
/// - `.exploration`: the functional (orbit/attractions/progressions) + melodic-vocabulary
///   playground — see `functionalExplorationSection`'s own doc comment. Only has anything to
///   show for the 7 classic modes today (`ModalFunctionalMapBuilder`'s own `familyID == 1`
///   restriction) — an empty-state message shows instead for any other scale family.
///
/// The instrument itself is picked once, in Settings > Théorie, and read via
/// `ImprovSession.theoryAuditionSound()`. The `.overview` grid only shows on macOS/visionOS/
/// iPad-width iOS; iPhone-width iOS keeps the original push list→detail navigation instead —
/// see `TheoryLibraryLayout`. Both `.overview` and `.exploration` detach into their OWN window
/// on macOS/visionOS (`isDetachedWindow`/`auxiliaryWindowID`) — same as every other Théorie tab.
struct ModeLibraryView: View {
    let session: ImprovSession
    var contentFocus: ModeLibraryContentFocus = .overview
    var isDetachedWindow: Bool = false
    /// Whether THIS instance is the one currently on screen — always `true` for a detached
    /// window (nothing else competes for its own dedicated window) and for `.overview` (no
    /// contextual help registered there yet), so only `ExplorationTabContent` actually overrides
    /// it. Feeds `.registerContextualHelp` in `detailContent` below — see that call site's own
    /// doc comment for why this can't just use `.onAppear`/`.onDisappear` instead.
    var isActive: Bool = true
    /// Whether this instance's tonic/scale picker reads/writes `AppModel.sharedMode` (so picking
    /// a mode here is reflected on every other MusicLab screen, including detached windows) or
    /// keeps its own independent local selection. `true` for every caller as of 2026-08-16 (see
    /// this file's own top doc comment — `ExplorationTabContent` used to pass `false`, per
    /// explicit request at the time; that request was reversed, since an unsynced Exploration mode
    /// read as a bug once other screens started sharing). Kept as a real parameter (not just
    /// deleted) rather than assuming no screen will ever want independent state again.
    var usesSharedModeSelection: Bool = true

    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif
    @Environment(AppModel.self) private var appModel

    /// Backing storage used only when `usesSharedModeSelection` is `false` — otherwise
    /// `tonicBinding`/`scaleIDBinding` below route to `appModel.sharedMode` instead. Kept (rather
    /// than removed) so `ExplorationTabContent`'s independent instance still has somewhere to
    /// store its own pick.
    @State private var selectedTonic: Int = 0
    @State private var selectedScaleID: String = ScaleLibrary.all[0].id
    /// Whole-octave shift applied to everything this screen's staffs/keyboards/playback show
    /// (the scale run, the diatonic chords, and the currently-selected chord's own keyboard) —
    /// per explicit request, so a mode's notes/chords can be brought low enough to land on the
    /// bass (fa) clef instead of always sitting around middle C.
    @State private var octaveShift: Int = 0
    /// Triad by default, seventh as an opt-in — per explicit request ("priorité aux triades").
    /// Only affects `diatonicChordReferences` (the harmonized-scale staff/list/keyboard, column
    /// 2/3) — the scale run above it (row 1) has no chord quality of its own to toggle.
    @State private var chordQualityTier: ChordProgressionResolver.ChordQualityTier = .triad

    private var tonicBinding: Binding<Int> {
        usesSharedModeSelection
            ? Binding(get: { appModel.sharedMode.tonic }, set: { appModel.sharedMode.tonic = $0 })
            : $selectedTonic
    }
    private var scaleIDBinding: Binding<String> {
        usesSharedModeSelection
            ? Binding(get: { appModel.sharedMode.scaleID }, set: { appModel.sharedMode.scaleID = $0 })
            : $selectedScaleID
    }

    /// What the tonic picker should actually DISPLAY as selected — `mode.tonic` (the piece's own
    /// ground truth) while `modeFollowsPlayback`, since `tonicBinding` itself is never written to
    /// while following (see `mode`'s own doc comment) and would otherwise keep showing whatever
    /// tonic was last manually picked, disagreeing with the mode actually in effect. Writes still
    /// go through `tonicBinding` — irrelevant in practice since the picker is `.disabled` whenever
    /// this diverges from it, kept only so the type-checker has a real setter.
    private var displayedTonicBinding: Binding<Int> {
        Binding(get: { modeFollowsPlayback ? mode.tonic.value : tonicBinding.wrappedValue }, set: { tonicBinding.wrappedValue = $0 })
    }
    /// Same reasoning as `displayedTonicBinding`, for the scale list's own highlighted row.
    private var displayedScaleID: String {
        modeFollowsPlayback ? mode.scale.id : scaleIDBinding.wrappedValue
    }
    /// Same reasoning as `displayedTonicBinding`, as a `Binding` for `ModePickerBadge` (which
    /// needs read/write even though writes are moot while `.disabled`).
    private var displayedScaleIDBinding: Binding<String> {
        Binding(get: { displayedScaleID }, set: { scaleIDBinding.wrappedValue = $0 })
    }
    /// Which of `diatonicChordReferences` the right column's mini keyboard currently shows —
    /// defaults to the tonic chord (index 0), same "always populated" convention the other
    /// Library screens already follow. Also doubles as "which chord is currently sounding": every
    /// path that changes it (a tap, or `playAllChords()`'s own scheduled advance) also plays that
    /// chord, so the list highlight/keyboard/circle-of-fifths ring all stay in lockstep with it.
    @State private var selectedChordIndex: Int = 0
    /// Which column of `staffEvents`/note of the ascending scale is currently sounding during
    /// Asc/Desc/Asc-et-Desc playback — `nil` once stopped or finished. Drives both the row-1
    /// staff's `highlightedIndex` and the row-1 keyboard's `heldPitches`.
    @State private var playingNoteIndex: Int?
    /// Bumped on every new playback/tap in this view (scale notes AND diatonic chords) — guards
    /// every scheduled highlight update below the same way `ProgressionLibraryView.playbackGeneration`
    /// guards its own, so a Stop (or starting something else before a sequence finishes)
    /// invalidates any still-pending ones instead of them firing late over whatever comes next.
    @State private var playbackGeneration = 0
    /// Replaces `session.isAuditioningTheoryLibrary` (the old isolated-audition player's own
    /// flag) as `scalePlaybackControls`' own "show the Arrêter button" gate, now that playback
    /// goes through real `pressKey`/`releaseKey` — see `play(direction:)`'s own doc comment.
    @State private var isPlayingScale = false

    /// Which of the two `ModalFunctionalMapBuilder.build(for:source:)` sources currently drives
    /// the functional-exploration panel — a user-facing choice (see that type's own doc comment
    /// for why neither is presented as "the" answer).
    @State private var functionalRoleSource: FunctionalRoleSource = .computed
    /// Which note the melodic-vocabulary panel's own detail card shows — `nil` until the first
    /// tap, at which point `effectiveSelectedMelodicNote` falls back to the current chord's own
    /// root, same "always populated" convention every other Library screen already follows.
    @State private var selectedMelodicNote: PitchClass?
    /// Last few notes tapped in the melodic-vocabulary row/keyboard (oldest first, capped at 4) —
    /// purely a "what did I just explore" memory aid, per this feature's own explicit "not an
    /// editable progression/phrase" scope decision; also the only input `detectApproachResolution`
    /// needs.
    @State private var recentPlayedNotes: [PitchClass] = []
    /// Last few distinct diatonic degrees selected anywhere in this mode's detail screen (oldest
    /// first, capped at 4) — same "memory aid, not a builder" scope as `recentPlayedNotes`.
    @State private var recentChordDegrees: [Int] = []
    /// Which of `session.chordProgressionTemplates` the "Progressions type" block is currently
    /// previewing — purely a reference/reminder of how this mode's already-known progressions
    /// are put together (per explicit request), never an editable progression of the user's own.
    @State private var selectedProgressionName: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesTwoColumns: Bool { TheoryLibraryLayoutMode.usesTwoColumns(horizontalSizeClass: horizontalSizeClass) }

    /// Follows the piece's own ground-truth mode (`session.theoryDisplayModeReference`) instead of
    /// the manually-picked `tonicBinding`/`scaleIDBinding` while playback is being observed — for
    /// BOTH `.overview` ("Modes") and `.exploration`, per explicit request. This is also what lets
    /// `reactToLiveChordMatch` (fed by `theoryLiveInputRecognizedChord`, which returns the piece's
    /// own ground-truth chord while observing) actually find a match in `diatonicChordReferences`:
    /// that lookup is keyed by (root, quality) against THIS mode's own diatonic chords, so a
    /// mismatched tonic/scale would silently never match anything, even with the chord data itself
    /// correct — matches `theoryLiveInputRecognizedChord`'s note about the mode-following fix.
    private var mode: Mode {
        if let ref = session.theoryDisplayModeReference {
            return Mode(tonic: PitchClass(ref.tonic), scale: ScaleLibrary.byID(ref.scaleID) ?? ScaleLibrary.all[0])
        }
        return Mode(tonic: PitchClass(tonicBinding.wrappedValue), scale: ScaleLibrary.byID(scaleIDBinding.wrappedValue) ?? ScaleLibrary.all[0])
    }

    /// Whether `mode` above is currently following piece playback rather than the manual picker —
    /// `overviewContent`/`functionalExplorationSection` show a small hint, and `listContent`
    /// disables its tonic/scale pickers, when this is `true`, since changing them wouldn't
    /// actually change what's displayed while a piece is being observed.
    private var modeFollowsPlayback: Bool {
        session.theoryDisplayModeReference != nil
    }

    /// Whichever live track is the app's current "source principale" — same convention
    /// `ChordLibraryView.liveHeldPitches`/`TonnetzLibraryView.sourceID` already use. Every
    /// playback function below plays through THIS track via real `pressKey`/`releaseKey` (see
    /// `pressAndScheduleRelease(pitches:track:durationSeconds:generation:)`) rather than the
    /// isolated `playTheoryLibraryAudition` player — per explicit request, so this screen acts as
    /// a genuine pre-input to the main keyboard (a simulated key-press): what's played here now
    /// shows up on the persistent main-keyboard bar and drives Dissonances' own live triad
    /// detection, exactly like really typing. Silently does nothing when no source is picked —
    /// same gate Tonnetz already has, not a regression (previously played regardless of source).
    private var sourceID: TrackID? { session.theoryLiveInputSourceID }

    /// Presses `pitches` on `track` now, then releases them after `durationSeconds` — guarded by
    /// `generation` so a superseded/stopped playback never releases notes a NEWER one is still
    /// holding. The shared "one note/chord event" primitive every playback function below builds
    /// its own scheduling on top of.
    private func pressAndScheduleRelease(pitches: [Int], track: TrackID, durationSeconds: Double, generation: Int) {
        for pitch in pitches { session.pressKey(pitch: pitch, track: track) }
        DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds) {
            guard playbackGeneration == generation else { return }
            for pitch in pitches { session.releaseKey(pitch: pitch, track: track) }
        }
    }

    var body: some View {
        // Used to be `TheoryLibraryLayout`'s sidebar+detail split (a "pick a mode from the full
        // list" column next to this content) — the full list is now redundant with
        // `ModePickerBadge`'s own popover list, and the badge itself moved INTO this content
        // (next to `octaveShiftControl` for `.overview`, above `roleSourceBlock` for
        // `.exploration`), so there's nothing left for a separate list column to do. Removed per
        // explicit request rather than kept as an empty sidebar.
        detailContent(showBackButton: false, onBack: {})
        #if os(macOS) || os(visionOS)
        // Floats over the screen's own top-right corner instead of reserving a whole extra row
        // above everything else just for one small icon — per explicit request ("on perd encore
        // beaucoup de place"). Lands over the title row's own trailing `Spacer()` (see
        // `detailContent`), which is otherwise empty there, so nothing real gets covered.
        .overlay(alignment: .topTrailing) {
            // `.exploration` deliberately has NO per-screen help icon (see this file's own doc
            // comment on `registerContextualHelp` above) — only `.overview` ("Modes") gets one.
            HStack(spacing: 8) {
                detachButton
                if contentFocus == .overview {
                    TheoryHelpButton(session: session)
                }
            }
            .padding(.horizontal)
            .padding(.top, 6)
        }
        #endif
        // Colors the persistent main-keyboard bar (`ContentView`) by this screen's own picked
        // mode while it's the active tab, per explicit request — covers BOTH `.overview` ("Modes")
        // and `.exploration`, each its own peer tab, hence the distinct id per `contentFocus`.
        .registerMainKeyboardMode(
            id: contentFocus == .overview ? "theorie.modes" : "theorie.exploration",
            isActive: isActive, mode: mode
        )
        // Feeds Intonations' fixed-temperament tuning its mode — same isActive-driven set/clear
        // as `.registerMainKeyboardMode` just above, so leaving this screen (e.g. for Accords/
        // Tonnetz, neither of which has a tonic of its own) reverts to no correction rather than
        // leaving a stale one behind.
        .onChange(of: isActive, initial: true) { _, active in
            session.setContextualMode(active ? mode : nil)
        }
        .onChange(of: mode) { _, newMode in
            guard isActive else { return }
            session.setContextualMode(newMode)
        }
    }

    #if os(macOS) || os(visionOS)
    /// `.overview` and `.exploration` detach into two DIFFERENT windows/ids — each is its own
    /// peer tab now (see `ModeLibraryContentFocus`'s own doc comment), so each needs its own
    /// independent "is this one open elsewhere" state rather than sharing `.theorie`.
    private var auxiliaryWindowID: AuxiliaryWindowID {
        contentFocus == .overview ? .theorie : .theorieExploration
    }

    @ViewBuilder
    private var detachButton: some View {
        if isDetachedWindow {
            Button {
                dismissWindow(id: auxiliaryWindowID.rawValue)
            } label: {
                Label(L10n.string(.appButtonReintegrer, session.currentLanguage), systemImage: "arrow.down.right.and.arrow.up.left")
            }
        } else {
            Button {
                openWindow(id: auxiliaryWindowID.rawValue)
            } label: {
                Image(systemName: "rectangle.on.rectangle")
            }
        }
    }
    #endif

    // MARK: - Detail

    private func detailContent(showBackButton: Bool, onBack: @escaping () -> Void) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showBackButton {
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                        }
                        Spacer()
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    // Suppressed for `.exploration` on a family-1 mode: `progressionAndDetailColumn`
                    // already shows the mode's own name as that screen's first element, so this
                    // page-level title would just be a 2nd, redundant copy of it — per explicit
                    // request. Every other case (`.overview`, or a non-family-1 `.exploration`
                    // showing only the empty-state hint) has nowhere else this name is shown, so
                    // it stays there.
                    if !(contentFocus == .exploration && mode.scale.familyID == 1) {
                        Text(mode.displayName).font(.largeTitle).bold()
                    }
                    Spacer()
                }

                switch contentFocus {
                case .overview:
                    overviewContent
                        .registerContextualHelp(id: HelpTopicID.theorieModes.rawValue, isActive: isActive) {
                            HelpTopicID.theorieModes.content(language: session.currentLanguage)
                        }
                case .exploration:
                    // The `.registerContextualHelp` call used to be a per-screen "?" button here
                    // instead — moved into `ContentView`'s shared bottom bar per explicit request,
                    // to reclaim the space that button took. `isActive` (rather than
                    // `.onAppear`/`.onDisappear`) also covers the family-1 gate itself: it goes
                    // false the moment `mode.scale.familyID` stops being 1, exactly when this
                    // help would otherwise stop applying.
                    Group {
                        if mode.scale.familyID == 1 {
                            functionalExplorationSection
                        } else {
                            Text(L10n.string(.appHintExplorationFamilleUn, session.currentLanguage))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .registerContextualHelp(id: HelpTopicID.theorieExploration.rawValue, isActive: isActive && mode.scale.familyID == 1) {
                        HelpTopicID.theorieExploration.content(language: session.currentLanguage)
                    }
                }
            }
            // Tracks every distinct diatonic degree selected anywhere in this screen (tap in the
            // overview's chord list/staff, the functional-orbit graphs, or the melodic panel's
            // own chord stepper) into `recentChordDegrees` — one shared history regardless of
            // which sub-screen the selection came from.
            .onChange(of: selectedFunctionalDegree) { _, newDegree in
                guard let newDegree, recentChordDegrees.last != newDegree else { return }
                recentChordDegrees.append(newDegree)
                if recentChordDegrees.count > 4 { recentChordDegrees.removeFirst() }
            }
            .onChange(of: session.theoryLiveInputRecognizedChord) { _, newChord in
                reactToLiveChordMatch(newChord)
            }
            .padding()
        }
    }

    /// 3 columns, per explicit request (was a 2-column × 3-row `Grid`, paired by ROW instead —
    /// the mode's own scale next to the mode's keyboard, the mode's chords next to whichever
    /// chord was last tapped, the chord list next to the circle of fifths): now paired by
    /// COLUMN instead — (1) the mode's own scale + its keyboard, (2) the mode's harmonized
    /// chords + the diatonic chord list, (3) whichever chord is current + the circle of fifths.
    /// A plain `HStack` of independent `VStack`s suffices now (unlike the old `Grid`, nothing
    /// needs to align across columns the way row 1/2's two cells used to need to start at the
    /// same y) — narrow widths fall back to stacking all 3 vertically, same breakpoint as
    /// everywhere else in this screen.
    @ViewBuilder
    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if modeFollowsPlayback {
                Text(L10n.string(.appHintModeSuitLecture, session.currentLanguage))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ModePickerBadge(
                    session: session, tonic: displayedTonicBinding, scaleID: displayedScaleIDBinding,
                    allowedScales: ScaleLibrary.all, isEnabled: !modeFollowsPlayback
                )
                octaveShiftControl
            }
            // `.staffCenter` (not `.top`) — per explicit request, so the selected-chord keyboard
            // in `circleColumn` lines up on the two staffs' own shared height instead of the top
            // of whatever happens to sit above it (`selectedChordKeyboard`'s own title text).
            if usesTwoColumns {
                HStack(alignment: .staffCenter, spacing: 16) {
                    scaleColumn
                    chordsColumn
                    circleColumn
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    scaleColumn
                    chordsColumn
                    circleColumn
                }
            }
        }
    }

    /// Column 1 — the mode's own scale (+ Asc/Desc/Asc-et-Desc right under it), then its own
    /// keyboard directly below (used to sit beside it instead).
    private var scaleColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Each scale degree gets its OWN note color on the staff (active palette,
            // `perPitchClassColors`) — unlike a chord's root/tones, no single degree should
            // visually dominate the others here, per explicit request. The keyboard right below
            // deliberately keeps its plain mode-role coloring (blue/cyan `showModeColoring`)
            // instead, per explicit request — only the staff changed.
            ChordStaffView(
                events: staffEvents, perPitchClassColors: session.activeColorPalette.colors,
                heightScale: 0.8, widthScale: 0.56, highlightedIndex: playingNoteIndex, keySignature: modeKeySignature,
                minimumColumnCount: sharedStaffColumnCount, onColumnTap: playSingleNote(atColumnIndex:)
            )
            .alignmentGuide(.staffCenter) { $0[VerticalAlignment.center] }
            // The scale's own note names, in degree order — a diagnostic readout (per explicit
            // request) letting a wrong note be spotted directly, same style as
            // `DissonancesLibraryView.noteReadoutSection`.
            Text(mode.pitchClasses.map { session.notationStyle.rootName($0, preferFlats: false) }.joined(separator: ", "))
                .font(.subheadline)
            scalePlaybackControls
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.displayName).font(.headline)
                PitchKeyboardView(
                    heldPitches: playingNotePitches,
                    modeTones: mode.pitchClasses.map(\.value),
                    showModeColoring: true,
                    height: Self.modeKeyboardHeight,
                    keyLabels: PitchKeyboardView.noteNameKeyLabels(forPitches: modeTonePitchesInKeyboardRange, style: session.notationStyle)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// -20% off `PitchKeyboardView`'s own default height (144), per explicit request.
    private static let modeKeyboardHeight: CGFloat = 115

    /// Column 2 — the mode's harmonized chords (+ a "play the sequence" button), then the
    /// diatonic chord list directly below (used to sit beside the circle of fifths instead).
    private var chordsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            chordQualityTierPicker
            ChordStaffView(
                events: chordsStaffEvents, notePalette: session.activeColorPalette.colors,
                heightScale: 0.8, widthScale: 0.56, highlightedIndex: selectedChordIndex, keySignature: modeKeySignature,
                minimumColumnCount: sharedStaffColumnCount, onColumnTap: tapChordStaffColumn(at:)
            )
            .alignmentGuide(.staffCenter) { $0[VerticalAlignment.center] }
            diatonicChordsReadout
            playChordSequenceButton
            diatonicChordsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Column 3 — whichever chord is current, on its own keyboard, then the circle of fifths
    /// directly below (used to sit beside the mode's own chord staff instead).
    private var circleColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            selectedChordKeyboard
            circleOfFifthsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The mode's parent major key's conventional signature (e.g. D Dorian's parent is C
    /// major, so no accidentals at all; A harmonic minor-family scale has no family-1 parent,
    /// so `nil` — same restriction `CircleOfFifths.parentTonic(for:)` already has) — shared by
    /// both staves above so their notes read cleanly instead of an accidental on every one.
    private var modeKeySignature: MajorKeySignature? {
        CircleOfFifths.parentTonic(for: mode).map { MajorKeySignature.forMajorTonic($0.value) }
    }

    /// The mode's own scale-degree pitch classes plus the octave-completing tonic (matches the
    /// reference "1, 2, b3, 4, 5, b6, 7, 8" degree listing) — reused for both the staff display
    /// and the ascending playback sequence.
    private var scaleDegreesWithOctave: [Int] {
        mode.pitchClasses.map(\.value) + [mode.tonic.value]
    }

    private var staffEvents: [StaffEvent] {
        ChordStaffView.ascendingSequence(
            pitchClasses: scaleDegreesWithOctave, chordRoot: mode.tonic.value, chordTones: mode.pitchClasses.map(\.value),
            startingAbove: 59 + octaveShift * 12
        )
    }

    /// Compact -2...+2 octave control shared by both staffs in `overviewContent` (`staffEvents`/
    /// `chordsStaffEvents`) and their paired playback/keyboard pitches — one control, applied to
    /// everything this screen shows, per explicit request.
    private var octaveShiftControl: some View {
        Stepper(value: $octaveShift, in: -2...2) {
            Text("\(L10n.string(.appFieldOctave, session.currentLanguage)) : \(octaveShift >= 0 ? "+\(octaveShift)" : "\(octaveShift)")")
                .font(.caption)
        }
        .fixedSize()
    }

    /// The longer of the two staffs' own column counts — passed as `minimumColumnCount` to
    /// BOTH `ChordStaffView`s below so they render at the same total length regardless of
    /// which one actually has more columns (a mode's own scale is always 8 notes, but its
    /// diatonic-chords count varies by scale family).
    private var sharedStaffColumnCount: Int { max(staffEvents.count, chordsStaffEvents.count) }

    private var modeTonePitchesInKeyboardRange: [Int] {
        let tones = Set(mode.pitchClasses.map(\.value))
        return (48...72).filter { tones.contains((($0 % 12) + 12) % 12) }
    }

    /// Plays `direction`'s sequence immediately — no separate "démarrer" step, per explicit
    /// request (Asc/Desc/Asc-et-Desc are buttons, not a picker + a start button). Also schedules
    /// `playingNoteIndex` to track whichever note is currently sounding, guarded by
    /// `playbackGeneration` — see that property's doc comment.
    private func play(direction: SequencePlayDirection) {
        guard let sourceID else { return }
        session.releaseAllKeys(track: sourceID)
        let ascending = PitchSequencing.ascendingPitches(forPitchClasses: scaleDegreesWithOctave, startingAbove: 47 + octaveShift * 12)
        let sequence: [Int]
        switch direction {
        case .ascending: sequence = ascending
        case .descending: sequence = ascending.reversed()
        case .both: sequence = ascending + ascending.reversed().dropFirst()
        }
        playbackGeneration += 1
        let generation = playbackGeneration
        isPlayingScale = true
        let stepDuration = 0.35
        for (index, pitch) in sequence.enumerated() {
            // Each pitch in `sequence` is one of `ascending`'s own (unique) values regardless of
            // direction, so its index there is exactly the staff column it corresponds to.
            let columnIndex = ascending.firstIndex(of: pitch)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * stepDuration) {
                guard playbackGeneration == generation else { return }
                playingNoteIndex = columnIndex
                pressAndScheduleRelease(pitches: [pitch], track: sourceID, durationSeconds: stepDuration * 0.9, generation: generation)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(sequence.count) * stepDuration) {
            guard playbackGeneration == generation else { return }
            playingNoteIndex = nil
            isPlayingScale = false
        }
    }

    private func stopScalePlayback() {
        playbackGeneration += 1
        playingNoteIndex = nil
        isPlayingScale = false
        if let sourceID { session.releaseAllKeys(track: sourceID) }
    }

    /// Plays a single tapped scale note (from the row-1 staff, see `onColumnTap` below) —
    /// highlighted the same way a scheduled Asc/Desc/Asc-et-Desc step is.
    private func playSingleNote(atColumnIndex index: Int) {
        let ascending = PitchSequencing.ascendingPitches(forPitchClasses: scaleDegreesWithOctave, startingAbove: 47 + octaveShift * 12)
        guard ascending.indices.contains(index), let sourceID else { return }
        session.releaseAllKeys(track: sourceID)
        playbackGeneration += 1
        let generation = playbackGeneration
        playingNoteIndex = index
        let duration = 0.6
        pressAndScheduleRelease(pitches: [ascending[index]], track: sourceID, durationSeconds: duration * 0.9, generation: generation)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard playbackGeneration == generation else { return }
            playingNoteIndex = nil
        }
    }

    private var playingNotePitches: Set<Int> {
        guard let playingNoteIndex else { return [] }
        let ascending = PitchSequencing.ascendingPitches(forPitchClasses: scaleDegreesWithOctave, startingAbove: 47 + octaveShift * 12)
        guard ascending.indices.contains(playingNoteIndex) else { return [] }
        return [ascending[playingNoteIndex]]
    }

    private var scalePlaybackControls: some View {
        HStack(spacing: 8) {
            Button(L10n.string(.appButtonAscendant, session.currentLanguage)) { play(direction: .ascending) }
            Button(L10n.string(.appButtonDescendant, session.currentLanguage)) { play(direction: .descending) }
            Button(L10n.string(.appButtonAscEtDescendant, session.currentLanguage)) { play(direction: .both) }
            if isPlayingScale {
                Button(L10n.string(.appButtonArreter, session.currentLanguage), role: .destructive, action: stopScalePlayback)
            }
            Spacer()
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Diatonic chords

    /// Triad/seventh toggle for `diatonicChordReferences` — per explicit request, defaults to
    /// triads with sevenths as an opt-in (see `chordQualityTier`'s own doc comment).
    private var chordQualityTierPicker: some View {
        Picker("", selection: $chordQualityTier) {
            Text(L10n.string(.appOptionTriades, session.currentLanguage)).tag(ChordProgressionResolver.ChordQualityTier.triad)
            Text(L10n.string(.appOptionSeptiemes, session.currentLanguage)).tag(ChordProgressionResolver.ChordQualityTier.seventh)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    /// The mode's own diatonic chords (I...VII) plus one appended trailing entry duplicating
    /// the first (the "VIII"/octave chord) — mirrors `scaleDegreesWithOctave` appending the
    /// octave-completing tonic to the scale run, so the chords list/staff read the same way:
    /// one entry per scale degree, ending back on the tonic an octave up.
    private var diatonicChordReferences: [ChordReference] {
        let base = ChordProgressionResolver.diatonicChordReferences(in: mode, qualityTier: chordQualityTier)
        guard let first = base.first else { return base }
        return base + [first]
    }

    @ViewBuilder
    private var diatonicChordsSection: some View {
        if !diatonicChordReferences.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(.appHeadingAccordsDuMode, session.currentLanguage)).font(.headline)
                ForEach(Array(diatonicChordReferences.enumerated()), id: \.offset) { index, reference in
                    Button {
                        selectedChordIndex = index
                        playSingleChord(reference, diatonicIndex: index)
                    } label: {
                        HStack {
                            Image(systemName: "play.circle")
                            Text(chordDisplayName(reference))
                                .foregroundStyle(index == selectedChordIndex ? Color.accentColor : .primary)
                            if let role = FunctionalHarmonyTable.role(forDegree: index + 1, familyID: mode.scale.familyID) {
                                Text(functionalName(role)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Ascending, octave-correct root anchor for each of `mode`'s own 7 diatonic degrees (index 0
    /// = degree i ... 6 = degree vii), one entry per `mode.pitchClasses` in degree order — same
    /// anchor mechanism (`PitchSequencing.ascendingPitches`) `staffEvents`/`play(direction:)`
    /// already use for the SCALE run, at that same visual register (`59`, matching
    /// `staffEvents`'s own `startingAbove`). Real bug fix: `chordsStaffEvents` used to place each
    /// chord independently via `ChordStaffView.chordEvent(root:...)`, which anchors purely from
    /// that chord's OWN root pitch class (`60 + root`) with no regard for scale-degree order —
    /// so any degree whose root pitch class is numerically LOWER than an earlier degree's (e.g.
    /// every non-tonic degree of B natural minor, tonic pitch class 11) was drawn (and played,
    /// see `diatonicVoicingPitches(for:)` below) a full octave too low.
    private var diatonicDegreeRootAnchorsForStaff: [Int] {
        PitchSequencing.ascendingPitches(forPitchClasses: mode.pitchClasses.map(\.value), startingAbove: 59 + octaveShift * 12)
    }

    /// Same idea as `diatonicDegreeRootAnchorsForStaff`, at the lower register
    /// `play(direction:)`'s own audio anchor uses (`47`) — feeds `diatonicVoicingPitches(for:)`,
    /// shared by every chord PLAYBACK/keyboard site below.
    private var diatonicDegreeRootAnchorsForPlayback: [Int] {
        PitchSequencing.ascendingPitches(forPitchClasses: mode.pitchClasses.map(\.value), startingAbove: 47 + octaveShift * 12)
    }

    /// `chord`'s own tones, voiced from whichever of `diatonicDegreeRootAnchorsForPlayback`
    /// matches its root when it's one of `mode`'s own 7 diatonic degrees (the common case, and
    /// what keeps a played/kept-on-screen chord's register consistent with the staff above);
    /// falls back to independent per-chord anchoring — the original behavior — for anything else
    /// (e.g. a borrowed/chromatic progression chord with no scale degree of its own to anchor to).
    ///
    /// `diatonicIndex`, when given, is `chord`'s own position in `diatonicChordReferences` —
    /// callers that already know it (the diatonic chord list/staff, not some other progression)
    /// should always pass it. Real bug fix: the appended "VIII"/octave entry (see
    /// `diatonicChordReferences`) has the SAME root pitch class as degree I by construction, so
    /// looking it up by VALUE (`degreeRoots.firstIndex(of:)`, the `diatonicIndex == nil` fallback
    /// below) always resolved to degree I's anchor — the octave chord played/showed a full
    /// octave too low instead of +12. `chordsStaffEvents` already avoided this by anchoring from
    /// each entry's own POSITION instead of its value; this mirrors that fix for playback.
    private func diatonicVoicingPitches(for chord: Chord, diatonicIndex: Int? = nil) -> [Int] {
        let anchors = diatonicDegreeRootAnchorsForPlayback
        if let diatonicIndex {
            let references = diatonicChordReferences
            guard references.indices.contains(diatonicIndex) else {
                return PitchSequencing.ascendingPitches(forPitchClasses: chord.pitchClasses.map(\.value), startingAbove: 47 + octaveShift * 12)
            }
            let isOctaveEntry = references.count > 1 && diatonicIndex == references.count - 1
            let anchorIndex = isOctaveEntry ? 0 : diatonicIndex
            guard anchors.indices.contains(anchorIndex) else {
                return PitchSequencing.ascendingPitches(forPitchClasses: chord.pitchClasses.map(\.value), startingAbove: 47 + octaveShift * 12)
            }
            let rootMidi = anchors[anchorIndex] + (isOctaveEntry ? 12 : 0)
            return chord.pitchClasses.map { pc in rootMidi + (((pc.value - chord.root.value) % 12) + 12) % 12 }
        }
        let degreeRoots = mode.pitchClasses.map(\.value)
        if let index = degreeRoots.firstIndex(of: chord.root.value), anchors.indices.contains(index) {
            let rootMidi = anchors[index]
            return chord.pitchClasses.map { pc in rootMidi + (((pc.value - chord.root.value) % 12) + 12) % 12 }
        }
        return PitchSequencing.ascendingPitches(forPitchClasses: chord.pitchClasses.map(\.value), startingAbove: 47 + octaveShift * 12)
    }

    /// All of the mode's diatonic chords, one stacked-chord column each (root position) — the
    /// harmonized-scale staff shown under the chord list. The appended octave entry (see
    /// `diatonicChordReferences`) is drawn one octave higher than degree I, same as the scale
    /// run's own octave-completing tonic.
    private var chordsStaffEvents: [StaffEvent] {
        let references = diatonicChordReferences
        let anchors = diatonicDegreeRootAnchorsForStaff
        return references.enumerated().compactMap { index, reference in
            guard let chord = reference.resolve() else { return nil }
            let isOctaveEntry = references.count > 1 && index == references.count - 1
            let anchorIndex = isOctaveEntry ? 0 : index
            guard anchors.indices.contains(anchorIndex) else { return nil }
            let rootMidi = anchors[anchorIndex] + (isOctaveEntry ? 12 : 0)
            let pitches = chord.pitchClasses.map { pc in rootMidi + (((pc.value - chord.root.value) % 12) + 12) % 12 }
            return StaffEvent(pitches: pitches, chordRoot: chord.root.value, chordTones: chord.pitchClasses.map(\.value))
        }
    }

    /// One line per diatonic degree — chord name + its notes in parens — a diagnostic readout
    /// (per explicit request) letting a wrong chord be spotted directly, same style as
    /// `DissonancesLibraryView.noteReadoutSection`.
    private var diatonicChordsReadout: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(diatonicChordReferences.enumerated()), id: \.offset) { _, reference in
                if let chord = reference.resolve() {
                    let names = chord.pitchClasses.map { session.notationStyle.rootName($0, preferFlats: false) }.joined(separator: ", ")
                    Text("\(session.notationStyle.displayName(for: chord)) (\(names))")
                        .font(.caption)
                }
            }
        }
    }

    private var selectedChordReference: ChordReference? {
        diatonicChordReferences.indices.contains(selectedChordIndex) ? diatonicChordReferences[selectedChordIndex] : nil
    }

    /// Feeds `circleOfFifthsSection`'s wheel — one synthetic "track" for the currently
    /// selected/playing diatonic chord, reusing the same track-outline-ring mechanism the live
    /// recognition view uses to mark a track's recognized chord. See
    /// `ImprovSession.syntheticListeningTrack`'s own doc comment.
    private var playingChordListeningTracks: [TrackInfo] {
        guard let selectedChordReference else { return [] }
        return [ImprovSession.syntheticListeningTrack(chordRoot: selectedChordReference.root, chordTemplateID: selectedChordReference.chordTemplateID)]
    }

    @ViewBuilder
    private var selectedChordKeyboard: some View {
        if let reference = selectedChordReference, let chord = reference.resolve() {
            // Root position (a diatonic-chord reference here has no inversion concept of its
            // own, same as the Progression Library) — one occurrence of each tone instead of
            // every octave in range, per explicit request.
            let voicingPitches = diatonicVoicingPitches(for: chord, diatonicIndex: selectedChordIndex)
            VStack(alignment: .leading, spacing: 4) {
                Text(chordDisplayName(reference)).font(.headline)
                PitchKeyboardView(
                    chordRoot: chord.root.value,
                    chordTones: chord.pitchClasses.map(\.value),
                    colorScheme: .noteBased(rootPitchClass: chord.root, palette: session.activeColorPalette.colors),
                    height: Self.modeKeyboardHeight,
                    keyLabels: PitchKeyboardView.noteNameKeyLabels(forPitches: voicingPitches, style: session.notationStyle),
                    referenceChordPitches: Set(voicingPitches)
                )
                .alignmentGuide(.staffCenter) { $0[VerticalAlignment.center] }
            }
        }
    }

    /// Tapping a note in the chords staff (row 2) plays and selects the whole chord that note's
    /// column belongs to — same effect as tapping that chord in `diatonicChordsSection` below.
    private func tapChordStaffColumn(at index: Int) {
        guard diatonicChordReferences.indices.contains(index) else { return }
        selectedChordIndex = index
        playSingleChord(diatonicChordReferences[index], diatonicIndex: index)
    }

    /// How `playAllChords()` renders each chord within its own time window — "Lié" (the
    /// original behavior: every tone held together) plus a few common arpeggiated/detached
    /// alternatives, picked from `chordPlaybackStylePicker`.
    private enum ChordPlaybackStyle: String, CaseIterable, Identifiable {
        case linked, arpeggioUp, arpeggioDown, arpeggioUpDown, staccato
        var id: String { rawValue }
    }

    @State private var chordPlaybackStyle: ChordPlaybackStyle = .linked

    private func chordPlaybackStyleLabel(_ style: ChordPlaybackStyle) -> String {
        switch style {
        case .linked: return L10n.string(.appOptionJeuLie, session.currentLanguage)
        case .arpeggioUp: return L10n.string(.appOptionArpegeMontant, session.currentLanguage)
        case .arpeggioDown: return L10n.string(.appOptionArpegeDescendant, session.currentLanguage)
        case .arpeggioUpDown: return L10n.string(.appOptionArpegeAllerRetour, session.currentLanguage)
        case .staccato: return L10n.string(.appOptionJeuStaccato, session.currentLanguage)
        }
    }

    /// Renders one chord's own `windowStart..<windowStart+windowDuration` slot according to
    /// `style` — "Lié"/"Staccato" each stay one simultaneous note (just held for a different
    /// share of the window), while the arpeggio styles split the window evenly across the
    /// chord's own tones, played one at a time.
    private func chordPlaybackNotes(pitches: [Int], style: ChordPlaybackStyle, windowStart: Double, windowDuration: Double) -> [ImprovSession.TheoryAuditionNote] {
        switch style {
        case .linked:
            return [ImprovSession.TheoryAuditionNote(pitches: pitches, startSeconds: windowStart, durationSeconds: windowDuration * 0.9)]
        case .staccato:
            return [ImprovSession.TheoryAuditionNote(pitches: pitches, startSeconds: windowStart, durationSeconds: windowDuration * 0.35)]
        case .arpeggioUp, .arpeggioDown, .arpeggioUpDown:
            let ordered: [Int]
            switch style {
            case .arpeggioUp: ordered = pitches
            case .arpeggioDown: ordered = pitches.reversed()
            default: ordered = pitches + pitches.reversed().dropFirst()
            }
            let subDuration = windowDuration / Double(ordered.count)
            return ordered.enumerated().map { index, pitch in
                ImprovSession.TheoryAuditionNote(pitches: [pitch], startSeconds: windowStart + Double(index) * subDuration, durationSeconds: subDuration * 0.9)
            }
        }
    }

    /// Plays every diatonic chord back to back (root position), rendered per-chord according to
    /// `chordPlaybackStyle`. Also schedules `selectedChordIndex` to advance in step, guarded by
    /// `playbackGeneration`, so the chord list's own highlight, the row-2 keyboard, and the
    /// circle-of-fifths ring all follow along live instead of only updating on an explicit tap.
    private func playAllChords() {
        guard let sourceID else { return }
        session.releaseAllKeys(track: sourceID)
        playbackGeneration += 1
        let generation = playbackGeneration
        let stepDuration = 1.0
        for (index, reference) in diatonicChordReferences.enumerated() {
            guard let chord = reference.resolve() else { continue }
            let pitches = diatonicVoicingPitches(for: chord, diatonicIndex: index)
            let windowStart = Double(index) * stepDuration
            let notes = chordPlaybackNotes(pitches: pitches, style: chordPlaybackStyle, windowStart: windowStart, windowDuration: stepDuration)
            for note in notes {
                DispatchQueue.main.asyncAfter(deadline: .now() + note.startSeconds) {
                    guard playbackGeneration == generation else { return }
                    pressAndScheduleRelease(pitches: note.pitches, track: sourceID, durationSeconds: note.durationSeconds, generation: generation)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + windowStart) {
                guard playbackGeneration == generation else { return }
                selectedChordIndex = index
            }
        }
    }

    @ViewBuilder
    private var playChordSequenceButton: some View {
        if !diatonicChordReferences.isEmpty {
            HStack(spacing: 8) {
                Button(L10n.string(.appButtonJouerLaSuiteDAccords, session.currentLanguage), action: playAllChords)
                    .buttonStyle(.bordered)
                Picker(L10n.string(.appFieldModeDeJeu, session.currentLanguage), selection: $chordPlaybackStyle) {
                    ForEach(ChordPlaybackStyle.allCases) { style in
                        Text(chordPlaybackStyleLabel(style)).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private func chordDisplayName(_ reference: ChordReference) -> String {
        guard let chord = reference.resolve() else { return "?" }
        return session.notationStyle.displayName(for: chord)
    }

    /// `diatonicIndex`: see `diatonicVoicingPitches(for:diatonicIndex:)`'s own doc comment — pass
    /// it whenever `reference` is known to be one of `diatonicChordReferences`' own entries
    /// (leave `nil` for a chord from some other list, e.g. a previewed progression's own chips).
    private func playSingleChord(_ reference: ChordReference, diatonicIndex: Int? = nil) {
        guard let chord = reference.resolve(), let sourceID else { return }
        session.releaseAllKeys(track: sourceID)
        playbackGeneration += 1
        let generation = playbackGeneration
        let pitches = diatonicVoicingPitches(for: chord, diatonicIndex: diatonicIndex)
        pressAndScheduleRelease(pitches: pitches, track: sourceID, durationSeconds: 1.5, generation: generation)
    }

    private func functionalName(_ role: FunctionalHarmonyRole) -> String {
        switch role {
        case .tonic: return L10n.string(.appFunctionalTonique, session.currentLanguage)
        case .supertonic: return L10n.string(.appFunctionalSusTonique, session.currentLanguage)
        case .mediant: return L10n.string(.appFunctionalMediante, session.currentLanguage)
        case .subdominant: return L10n.string(.appFunctionalSousDominante, session.currentLanguage)
        case .dominant: return L10n.string(.appFunctionalDominante, session.currentLanguage)
        case .submediant: return L10n.string(.appFunctionalSusDominante, session.currentLanguage)
        case .leadingTone: return L10n.string(.appFunctionalSensible, session.currentLanguage)
        }
    }

    // MARK: - Circle of fifths

    @ViewBuilder
    private var circleOfFifthsSection: some View {
        if let parentTonic = CircleOfFifths.parentTonic(for: mode) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string(.headingCercleDesQuintes, session.currentLanguage)).font(.headline)
                CircleOfFifthsWheelView(
                    wheel: ImprovSession.wheelState(
                        forTonic: parentTonic, activeTonic: mode.tonic, activeModeName: mode.scale.systematicName,
                        listeningTracks: playingChordListeningTracks
                    ),
                    palette: session.activeColorPalette.colors,
                    paletteTextColors: session.activeColorPalette.textColors
                )
                .frame(maxWidth: 420)
            }
        }
    }

    // MARK: - Functional exploration

    /// Built fresh from `mode`/`functionalRoleSource` on every access (both graphs below take
    /// their own `map` parameter directly rather than this view holding one in `@State`) — cheap
    /// pure computation, same convention `staffEvents`/`chordsStaffEvents` above already use.
    private var functionalMap: ModeFunctionalMap {
        ModalFunctionalMapBuilder.build(for: mode, source: functionalRoleSource)
    }

    /// The single source of truth for "which chord is selected" across BOTH this panel's graphs
    /// AND the overview panel's own `selectedChordIndex` — derived rather than a separate
    /// `@State`, so the two panels can never disagree about which chord is current. Degree 8 (the
    /// overview's own appended octave duplicate, see `diatonicChordReferences`) maps back to
    /// degree 1, since the functional map only ever has 7 entries.
    private var selectedFunctionalDegree: Int? {
        let degree = selectedChordIndex + 1
        return degree > 7 ? 1 : degree
    }

    /// Selecting a chord in either graph plays it AND updates `selectedChordIndex` — so the
    /// overview panel's own keyboard/list/circle-of-fifths ring reflect it too if the user
    /// switches back, exactly as if they'd tapped it there directly.
    private func playFunctionalChord(atDegree degree: Int) {
        guard let chordFunction = functionalMap.chords.first(where: { $0.degree == degree }) else { return }
        selectedChordIndex = degree - 1
        playSingleChord(chordFunction.reference, diatonicIndex: degree - 1)
    }

    /// Everything about exploring the mode from a chosen chord's own point of view — harmonic
    /// geography (row 1: the two functional graphs + a reference list of this mode's known
    /// progressions) and melodic vocabulary (row 3: "accord"/"mélodie" reference keyboards side
    /// by side, each with its own note-by-note breakdown against whichever chord row 1 currently
    /// has selected, then the mode's own playable keyboard spanning the full width below both) in
    /// ONE screen, deliberately not split across tabs: once someone is at the keyboard trying out
    /// what a note sounds like
    /// against the current chord, they're not going to navigate away first — per explicit
    /// request.
    private var functionalExplorationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if modeFollowsPlayback {
                Text(L10n.string(.appHintModeSuitLecture, session.currentLanguage))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            // Row 1: a column stacking the mode's own name, the role-source toggle, the
            // progression picker, its chord-chip preview, and (per explicit request) the
            // role-color legend, each directly under the previous one — to the LEFT of the two
            // harmonic graphs (per explicit request, to save horizontal space).
            if usesTwoColumns {
                HStack(alignment: .top, spacing: 20) {
                    progressionAndDetailColumn
                    orbitGraphBlock
                    attractionGraphBlock
                }
            } else {
                VStack(spacing: 20) {
                    progressionAndDetailColumn
                    orbitGraphBlock
                    attractionGraphBlock
                }
            }

            Divider()

            // Row 3: "accord" (left) next to "mélodie" (right), each its own mini keyboard plus
            // its own detail card underneath, and (per explicit request) the note-role legend as
            // a 3rd column. The mode's own notes used to have a 4th, full-width keyboard of their
            // own here (`extendedModeKeyboardRow`) — removed per explicit request now that the
            // persistent main-keyboard bar (`ContentView`) shows the same thing (mode-tone
            // coloring + scale-degree badges, see `.registerMainKeyboardMode` in `body`) whenever
            // this screen is active, labeled "Notes du mode" there instead.
            if usesTwoColumns {
                HStack(alignment: .top, spacing: 20) {
                    accordColumn
                    melodieColumn
                    melodicLegendColumn
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    accordColumn
                    melodieColumn
                    melodicLegendColumn
                }
            }
        }
        .onChange(of: liveInputHeldPitchClasses) { _, newValue in
            reactToLiveInputMatch(heldPitchClasses: newValue)
        }
    }

    /// This mode's own known progressions (deduplicated by name, same rule
    /// `ProgressionLibraryView.uniqueTemplates` already uses) — picking one in `progressionPicker`
    /// only PREVIEWS it in `progressionChordChipsRow` below; there is no editing here, per explicit
    /// request (a progression BUILDER belongs to Composition/Guide, not Exploration).
    private var uniqueProgressionTemplates: [ChordProgressionTemplate] {
        var seen = Set<String>()
        return session.chordProgressionTemplates.filter { seen.insert($0.name).inserted }
    }

    /// Row 1's own leading column — the mode's own name (first, per explicit request, since this
    /// column now sits ahead of the two harmonic graphs instead of after them), the role-source
    /// toggle, the progression picker, its chord-chip preview, and (per explicit request) the
    /// harmonic-role legend itself, stacked directly one under the other (rather than spread
    /// across separate rows) — the legend is shown here as a vertical list (see
    /// `FunctionalMapLegendView.axis`) since this column is too narrow for its original
    /// horizontal row. The currently-played chord's own info line used to live here too; it's
    /// now under `accordColumn`'s own "Accord actuel" label instead, per explicit request.
    private var progressionAndDetailColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Now the ONLY place the mode's own name shows on this screen (see the page-level
            // title's own suppression above) — sized up from a plain `.headline` to carry that
            // weight on its own, per explicit request.
            Text(mode.displayName).font(.title2).bold()
            ModePickerBadge(
                session: session, tonic: displayedTonicBinding, scaleID: displayedScaleIDBinding,
                allowedScales: ScaleLibrary.all, isEnabled: !modeFollowsPlayback, fillsAvailableWidth: true
            )
            roleSourceBlock
            progressionPicker
            progressionChordChipsRow
            FunctionalMapLegendView(language: session.currentLanguage, axis: .vertical)
        }
        .frame(maxWidth: 260, alignment: .leading)
    }

    /// The role-source toggle (unrelated to which progression is previewed below it — see
    /// `FunctionalRoleSource`'s own doc comment) — its own small block purely to save space
    /// elsewhere, not because the two are connected.
    private var roleSourceBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string(.appFieldSourceFonctionnelle, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $functionalRoleSource) {
                Text(L10n.string(.appOptionFormuleCalculee, session.currentLanguage)).tag(FunctionalRoleSource.computed)
                Text(L10n.string(.appOptionTableStandard, session.currentLanguage)).tag(FunctionalRoleSource.standardTable)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// A dropdown (not a scrollable list, per explicit request) over this mode's own known
    /// progressions, plus an explicit "Aucune" entry so a previewed progression can be
    /// deselected again (per explicit request) — `nil` binds to that same entry.
    private var progressionPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string(.appHeadingProgressionsTypeDuMode, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { selectedProgressionName },
                set: { newValue in
                    selectedProgressionName = newValue
                    selectedProgressionChordIndex = nil
                }
            )) {
                Text(L10n.string(.appOptionAucuneFem, session.currentLanguage)).tag(String?.none)
                ForEach(uniqueProgressionTemplates, id: \.name) { template in
                    Text(template.name).tag(String?.some(template.name))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    /// Which chip of `progressionChordChipsRow` was tapped last — purely a highlight,
    /// same "tap to scrub/audition" convention `ProgressionLibraryView.chordListSection` already
    /// uses for its own chip row (this is intentionally the same interaction, just recolored by
    /// harmonic role instead of a flat accent color — see `progressionChipFill(for:)`).
    @State private var selectedProgressionChordIndex: Int?

    /// This mode's own diatonic degree (and therefore harmonic role/color) that `reference`'s
    /// root matches, if any — a progression chord built from a different quality than that
    /// degree's own "richest" one (rare) still matches by root; a chord foreign to this mode's 7
    /// diatonic roots (e.g. a borrowed/chromatic one some progression template might use) simply
    /// gets no color override.
    private func matchingFunctionalChord(for reference: ChordReference) -> ModalChordFunction? {
        functionalMap.chords.first { $0.reference.root == reference.root }
    }

    private func progressionChipFill(for reference: ChordReference) -> Color {
        matchingFunctionalChord(for: reference).map { FunctionalRoleColors.fill(for: $0.role) } ?? Color.secondary.opacity(0.25)
    }

    private func progressionChipTextColor(for reference: ChordReference) -> Color {
        matchingFunctionalChord(for: reference).map { FunctionalRoleColors.textColor(for: $0.role) } ?? .primary
    }

    /// The chosen progression's own chords, previewed as a chip row directly under
    /// `progressionPicker` (see `progressionAndDetailColumn`) — same "tap to scrub/hear, current
    /// one highlighted" interaction as `ProgressionLibraryView.chordListSection`, recolored per
    /// chord by its harmonic role in THIS mode's own orbit/attraction graphs (see
    /// `progressionChipFill(for:)`), so a progression's own functional shape (e.g. "away, away,
    /// tension, home") reads at a glance. Tapping a chip ALSO updates `selectedChordIndex` when
    /// that chord matches one of this mode's own diatonic degrees (see `matchingFunctionalChord`),
    /// so the functional-detail/melodic-vocabulary panels below react exactly as they already do
    /// for a tap in the orbit/attraction graphs, instead of staying stuck on whatever was selected
    /// before — per explicit bug report. Wrapped with `FlowLayout` rather than a horizontal
    /// `ScrollView` (per explicit request) so a longer progression wraps onto further lines
    /// instead of scrolling past this narrow column's own edge, unseen.
    @ViewBuilder
    private var progressionChordChipsRow: some View {
        if let name = selectedProgressionName, let template = uniqueProgressionTemplates.first(where: { $0.name == name }) {
            let references = ChordProgressionResolver.resolveRich(template, in: mode)
            VStack(alignment: .leading, spacing: 6) {
                Text(template.name).font(.subheadline).bold()
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(Array(references.enumerated()), id: \.offset) { index, reference in
                        Button {
                            selectedProgressionChordIndex = index
                            if let matched = matchingFunctionalChord(for: reference) {
                                selectedChordIndex = matched.degree - 1
                            }
                            playSingleChord(reference)
                        } label: {
                            Text(chordDisplayName(reference))
                                .fontWeight(index == selectedProgressionChordIndex ? .bold : .regular)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(progressionChipFill(for: reference), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(progressionChipTextColor(for: reference))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.white, lineWidth: index == selectedProgressionChordIndex ? 2 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .font(.callout)
        }
    }

    private var orbitGraphBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(.appHeadingOrbiteFonctionnelle, session.currentLanguage)).font(.headline)
            FunctionalOrbitGraphView(
                map: functionalMap, notationStyle: session.notationStyle, language: session.currentLanguage,
                selectedDegree: selectedFunctionalDegree, onSelect: playFunctionalChord(atDegree:)
            )
            .frame(maxWidth: 380)
        }
    }

    private var attractionGraphBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(.appHeadingAttractions, session.currentLanguage)).font(.headline)
            FunctionalAttractionGraphView(
                map: functionalMap, notationStyle: session.notationStyle, language: session.currentLanguage,
                selectedDegree: selectedFunctionalDegree, onSelect: playFunctionalChord(atDegree:)
            )
            .frame(maxWidth: 380)
        }
    }

    @ViewBuilder
    private var selectedFunctionalChordDetail: some View {
        if let degree = selectedFunctionalDegree,
           let chordFunction = functionalMap.chords.first(where: { $0.degree == degree }),
           let chord = chordFunction.reference.resolve() {
            HStack(spacing: 12) {
                Text(session.notationStyle.displayName(for: chord)).font(.headline)
                Text(romanNumeral(degree: degree, quality: triadQuality(of: chord))).foregroundStyle(.secondary)
                Text("\(L10n.string(.appFieldRoleFonctionnel, session.currentLanguage)) : \(functionalRoleLabel(chordFunction.role, language: session.currentLanguage))")
                if chordFunction.isModalCharacteristic {
                    let noteNames = chordFunction.characteristicNotes.map { session.notationStyle.rootName($0, preferFlats: false) }.joined(separator: ", ")
                    Text("\(L10n.string(.appLabelNoteCaracteristique, session.currentLanguage)) : \(noteNames)")
                        .foregroundStyle(.purple)
                }
                Spacer()
            }
            .font(.callout)
        }
    }

    // MARK: - Melodic vocabulary

    /// The current chord (shared with the functional-exploration panel via
    /// `selectedFunctionalDegree`, so switching sub-screens never loses "what am I looking at")
    /// re-read as the mode's own notes' melodic function against it — see
    /// `MelodicVocabularyAnalyzer`'s own doc comment for why this works for any scale, not just
    /// the 7 classic modes (only the SURROUNDING UI — this picker's own visibility — stays
    /// gated to family 1, matching `functionalMap`'s own restriction).
    private var melodicAnalysis: MelodicVocabularyAnalysis {
        let chord = selectedFunctionalDegree.flatMap { degree in
            functionalMap.chords.first { $0.degree == degree }?.reference.resolve()
        } ?? diatonicChordReferences.first?.resolve() ?? Chord(root: mode.tonic, template: ChordVocabulary.seed[0])
        return MelodicVocabularyAnalyzer.analyze(mode: mode, chord: chord)
    }

    private var effectiveSelectedMelodicNote: PitchClass? {
        selectedMelodicNote ?? melodicAnalysis.notes.first { $0.chordToneType == .root }?.note ?? melodicAnalysis.notes.first?.note
    }

    /// Plays the tapped note alone (short, like `playSingleNote`) and remembers it in
    /// `recentPlayedNotes` — the only input this panel's "recently played" history needs.
    /// `atPitch`, when given, is the EXACT key that was tapped on the actual keyboard (so a C an
    /// octave up sounds an octave up, not always the same canonical octave near middle C — see
    /// this parameter's own call site for the bug that motivated it); left `nil` for taps that
    /// only ever carry a pitch class to begin with (the note-chip row has no octave of its own).
    private func playMelodicNote(_ pitchClass: PitchClass, atPitch pitch: Int? = nil) {
        selectedMelodicNote = pitchClass
        guard let sourceID else { return }
        session.releaseAllKeys(track: sourceID)
        playbackGeneration += 1
        let generation = playbackGeneration
        let pitches = pitch.map { [$0] } ?? PitchSequencing.ascendingPitches(forPitchClasses: [pitchClass.value], startingAbove: 47)
        pressAndScheduleRelease(pitches: pitches, track: sourceID, durationSeconds: 0.55, generation: generation)
        recentPlayedNotes.append(pitchClass)
        if recentPlayedNotes.count > 4 { recentPlayedNotes.removeFirst() }
    }

    /// Row 3a's left column — the current chord's own mini keyboard (see `currentChordFillColors`)
    /// with its own detail card (name + harmonic role) and recently-explored-chords reminder
    /// underneath, per explicit request (moved here from Row 1's own leading column — see
    /// `progressionAndDetailColumn`'s own doc comment — and paired with "mélodie" as a peer
    /// column instead of stacking under the melodic-vocabulary keyboard as before).
    private var accordColumn: some View {
        let analysis = melodicAnalysis
        let chord = analysis.chord
        let chordTones = Set(chord.pitchClasses.map(\.value))
        let chordKeyboardPitches = (48...72).filter { chordTones.contains((($0 % 12) + 12) % 12) }
        return VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string(.appLabelAccordActuel, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
            PitchKeyboardView(
                height: Self.melodicKeyboardSize.height,
                keyLabels: PitchKeyboardView.noteNameKeyLabels(forPitches: chordKeyboardPitches, style: session.notationStyle),
                customFillColors: currentChordFillColors(for: analysis)
            )
            .frame(width: Self.melodicKeyboardSize.width)
            selectedFunctionalChordDetail
            recentChordDegreesRow
        }
        .frame(width: Self.melodicKeyboardSize.width, alignment: .leading)
    }

    /// Row 3a's right column — the melodic-vocabulary mini keyboard (colored/badged by role
    /// against the current chord) with the currently-selected note's own detail card (name,
    /// role — e.g. "Ton de l'accord" — and consonance/couleur/tension qualifiers), its possible
    /// resolutions, and the recently-played-notes reminder underneath, per explicit request
    /// (paired with "accord" as a peer column — see `accordColumn`'s own doc comment).
    private var melodieColumn: some View {
        let analysis = melodicAnalysis
        return VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string(.appHeadingVocabulaireMelodique, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
            PitchKeyboardView(
                height: Self.melodicKeyboardSize.height,
                keyLabels: PitchKeyboardView.noteNameKeyLabels(forPitches: modeTonePitchesInKeyboardRange, style: session.notationStyle),
                customFillColors: melodicRoleFillColors(for: analysis),
                resolutionArrows: resolutionArrowPitchClasses(for: analysis),
                modalCharacteristicPitchClasses: modalCharacteristicPitchClasses(for: analysis),
                noteBadges: noteBadges(for: analysis)
            )
            .frame(width: Self.melodicKeyboardSize.width)
            if let note = effectiveSelectedMelodicNote, let profile = analysis.notes.first(where: { $0.note == note }) {
                MelodicNoteDetailView(
                    profile: profile, noteName: session.notationStyle.rootName(note, preferFlats: false), language: session.currentLanguage
                )
            }
            recentPlayedNotesRow
            if let note = effectiveSelectedMelodicNote, let profile = analysis.notes.first(where: { $0.note == note }) {
                MelodicResolutionsRowView(
                    profile: profile, language: session.currentLanguage,
                    resolutionNoteName: { session.notationStyle.rootName($0, preferFlats: false) }
                )
            }
        }
        .frame(width: Self.melodicKeyboardSize.width, alignment: .leading)
    }

    /// The shared size for `accordColumn`/`melodieColumn`'s own mini keyboards — `height` alone
    /// wasn't enough to make them look the same (differing outer column widths stretched them
    /// unevenly), so this is the single source both pull from for `.frame(width:height:)`, not
    /// just `height:`.
    private static let melodicKeyboardSize = CGSize(width: 390, height: 115) // -20% off the shared 144 default, per explicit request.

    /// The current chord's own harmonic-role color (see `FunctionalRoleColors.fill(for:)`) — the
    /// same color `progressionChipFill`/the orbit-attraction graphs already use for this chord,
    /// reused here instead of `PitchKeyboardView`'s own generic red-root/yellow-tone chord
    /// coloring, per explicit request.
    private func currentChordFunctionalRole() -> ModalFunctionalRole? {
        guard let degree = selectedFunctionalDegree else { return nil }
        return functionalMap.chords.first { $0.degree == degree }?.role
    }

    /// Feeds the "Accord actuel" keyboard's own `customFillColors` — every chord tone gets the
    /// chord's harmonic-role color, with the root reinforced (mixed toward black, so it stays
    /// visibly darker/more saturated) and the rest of the triad a lighter tint of that same color
    /// (mixed toward white instead), per explicit request. Both mixes use `Color.mixed(with:amount:)`
    /// (real RGB blending) rather than `.opacity()` — a translucent fill on a BLACK key otherwise
    /// lets the white keys' own separator line underneath bleed through, per explicit bug report;
    /// solid blended colors also make root vs. rest easier to tell apart than opacity alone did.
    private func currentChordFillColors(for analysis: MelodicVocabularyAnalysis) -> [Int: Color] {
        guard let role = currentChordFunctionalRole() else { return [:] }
        let base = FunctionalRoleColors.fill(for: role)
        let rootColor = base.mixed(with: .black, amount: 0.25)
        let otherColor = base.mixed(with: .white, amount: 0.55)
        let root = ((analysis.chord.root.value % 12) + 12) % 12
        var result: [Int: Color] = [:]
        for tone in analysis.chord.pitchClasses.map(\.value) {
            let pitchClass = ((tone % 12) + 12) % 12
            result[pitchClass] = pitchClass == root ? rootColor : otherColor
        }
        return result
    }

    /// Feeds the "Vocabulaire mélodique" keyboard's own `noteBadges` — the same interval-from-
    /// chord-root label and role color `MelodicNoteChipView`'s own row used to show underneath
    /// the big playable keyboard, moved here (per explicit request) into small circles above the
    /// keys themselves, the same style the mode's own scale-degree badge already uses elsewhere.
    private func noteBadges(for analysis: MelodicVocabularyAnalysis) -> [Int: KeyBadge] {
        Dictionary(uniqueKeysWithValues: analysis.notes.map { profile in
            (profile.note.value, KeyBadge(
                text: intervalLabel(for: profile),
                fillColor: MelodicRoleColors.fill(for: profile.defaultRole),
                textColor: MelodicRoleColors.textColor(for: profile.defaultRole)
            ))
        })
    }

    /// The role-color legend for `accordColumn`/`melodieColumn`'s own mini keyboards, as a 3rd
    /// column to their right — a vertical list (see `MelodicMapLegendView.axis`) since this
    /// column is narrow.
    private var melodicLegendColumn: some View {
        MelodicMapLegendView(language: session.currentLanguage, axis: .vertical)
            .frame(maxWidth: 160, alignment: .leading)
    }

    private func melodicRoleFillColors(for analysis: MelodicVocabularyAnalysis) -> [Int: Color] {
        Dictionary(uniqueKeysWithValues: analysis.notes.map { ($0.note.value, MelodicRoleColors.fill(for: $0.defaultRole)) })
    }

    /// Every resolution TARGET across all of `analysis.notes`' own candidates, keyed by pitch
    /// class — feeds `PitchKeyboardView.resolutionArrows` so the vocabulary keyboard marks each
    /// candidate key directly, same information as `MelodicResolutionsRowView`'s list, per
    /// explicit request.
    private func resolutionArrowPitchClasses(for analysis: MelodicVocabularyAnalysis) -> [Int: ResolutionDirection] {
        var result: [Int: ResolutionDirection] = [:]
        for profile in analysis.notes {
            for resolution in profile.resolutions {
                result[resolution.targetNote.value] = resolution.direction
            }
        }
        return result
    }

    /// This mode's own characteristic notes (independent of the current chord) — feeds
    /// `PitchKeyboardView.modalCharacteristicPitchClasses` for the purple on-key marker, per
    /// explicit request (same threshold `MelodicNoteChipView`'s own diamond badge already uses).
    private func modalCharacteristicPitchClasses(for analysis: MelodicVocabularyAnalysis) -> Set<Int> {
        Set(analysis.notes.filter { $0.modalIdentity >= 0.5 }.map { $0.note.value })
    }

    @ViewBuilder
    private var recentPlayedNotesRow: some View {
        if !recentPlayedNotes.isEmpty {
            HStack(spacing: 6) {
                Text(L10n.string(.appLabelNotesJoueesRecemment, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
                ForEach(Array(recentPlayedNotes.enumerated()), id: \.offset) { index, pitchClass in
                    Text(session.notationStyle.rootName(pitchClass, preferFlats: false))
                        .font(.caption).bold(index == recentPlayedNotes.count - 1)
                }
            }
        }
    }

    @ViewBuilder
    private var recentChordDegreesRow: some View {
        if !recentChordDegrees.isEmpty {
            HStack(spacing: 6) {
                Text(L10n.string(.appLabelAccordsExploresRecemment, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
                ForEach(Array(recentChordDegrees.enumerated()), id: \.offset) { index, degree in
                    if let chord = diatonicChordReferences.indices.contains(degree - 1) ? diatonicChordReferences[degree - 1].resolve() : nil {
                        Text(session.notationStyle.displayName(for: chord))
                            .font(.caption).bold(index == recentChordDegrees.count - 1)
                    }
                }
            }
        }
    }

    // MARK: - Live-input matching

    /// The pitch classes currently held on `session.theoryLiveInputSourceID`'s own track, if one
    /// is picked — the single input this whole live-matching feature reacts to.
    private var liveInputHeldPitchClasses: Set<Int> {
        guard let sourceID = session.theoryLiveInputSourceID,
              let heldPitches = session.tracks.first(where: { $0.id == sourceID })?.heldPitches else { return [] }
        return Set(heldPitches.map { ((($0 % 12) + 12) % 12) })
    }

    /// Reacts to a single held note exactly as if it had been tapped directly, selecting it as
    /// the melodic-vocabulary panel's current note — per explicit request ("un grand saut
    /// technique"). Chord recognition needs at least 2 held notes (see `RecognitionEngine
    /// .recognizeChord()`'s own guard), so it's handled separately by `reactToLiveChordMatch(_:)`
    /// below rather than here.
    private func reactToLiveInputMatch(heldPitchClasses: Set<Int>) {
        guard heldPitchClasses.count == 1, let pitchClass = heldPitchClasses.first else { return }
        selectedMelodicNote = PitchClass(pitchClass)
    }

    /// Reacts to whatever chord `RecognitionEngine` recognizes live on the chosen live-input
    /// track exactly as if the matching diatonic chord had been tapped directly (and, in
    /// `.exploration` with a progression previewed and containing it, scrubs to it there too) —
    /// shared by both `.overview` ("Modes") and `.exploration`, since both key their own chord
    /// display off the same `selectedChordIndex`/`diatonicChordReferences`. Deliberately does NOT
    /// call `playSingleChord`'s own audition playback: the live source is already sounding
    /// through its own track, so re-triggering the audition sample here would double the audio.
    private func reactToLiveChordMatch(_ chord: RecognizedChord?) {
        guard let chord else { return }
        guard let index = ImprovSession.matchingChordIndex(chord, in: diatonicChordReferences, reference: { $0 }, preferring: selectedChordIndex) else { return }
        selectedChordIndex = index
        guard contentFocus == .exploration,
              let name = selectedProgressionName,
              let template = uniqueProgressionTemplates.first(where: { $0.name == name }) else { return }
        let references = ChordProgressionResolver.resolveRich(template, in: mode)
        // Same "prefer the already-selected occurrence" fix as `matchingChordIndex` above — this
        // one isn't expressed as a `ChordReference` match (it's matched by functional degree
        // instead), so it can't reuse that helper directly, but the bug and fix are identical: a
        // progression with a repeated degree (e.g. I...IV-V-I) would otherwise always scrub back
        // to its FIRST occurrence.
        let alreadyOnAMatch: Bool
        if let current = selectedProgressionChordIndex, references.indices.contains(current) {
            alreadyOnAMatch = matchingFunctionalChord(for: references[current])?.degree == index + 1
        } else {
            alreadyOnAMatch = false
        }
        if !alreadyOnAMatch, let progressionIndex = references.firstIndex(where: { matchingFunctionalChord(for: $0)?.degree == index + 1 }) {
            selectedProgressionChordIndex = progressionIndex
        }
    }

}

#Preview {
    ModeLibraryView(session: ImprovSession())
}
