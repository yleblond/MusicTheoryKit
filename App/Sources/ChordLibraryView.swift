import SwiftUI
import AppCore
import JamShackUI
import MusicTheoryKit
import Localization

/// "Accords" tab — pick a root + quality, then see its name (via the active `NotationStyle`, see
/// `NotationStyleSettingsView`), its notes on the grand staff, a guitar diagram (with an
/// inversion-aware position picker, see
/// `GuitarChordShape.diagram(forRoot:chordTemplateID:inversion:)`), and the same chord
/// highlighted on a keyboard with note-name bullets — plus a play button (the instrument itself
/// is picked once, in Settings > Théorie, and read via `ImprovSession.theoryAuditionSound()`).
/// Two side-by-side columns on macOS/visionOS/iPad-width iOS, push list→detail navigation on
/// iPhone-width iOS — see `TheoryLibraryLayout`.
struct ChordLibraryView: View {
    let session: ImprovSession
    var isDetachedWindow: Bool = false
    /// See `ModeLibraryView.isActive`'s own doc comment. Feeds `.registerMainKeyboardChord` in
    /// `body` below.
    var isActive: Bool = true

    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    @State private var screen: TheoryLibraryScreen = .list
    @State private var selectedRoot: Int = 0
    @State private var selectedTemplateID: String = "Ma"
    /// Drives the staff/keyboard display — independent of `guitarPosition`, since the guitar
    /// diagram only has verified shapes up to the 3rd inversion (see `GuitarChordShape`'s own
    /// doc comment) while the staff/keyboard can show any inversion a chord's own tone count
    /// allows.
    @State private var inversion: Int = 0
    @State private var guitarPosition: Int = 0

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesTwoColumns: Bool { TheoryLibraryLayoutMode.usesTwoColumns(horizontalSizeClass: horizontalSizeClass) }

    private var chord: Chord {
        Chord(root: PitchClass(selectedRoot), template: ChordVocabulary.byID(selectedTemplateID) ?? ChordVocabulary.seed[0])
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS) || os(visionOS)
            HStack {
                Spacer()
                detachButton
            }
            .padding(.horizontal)
            .padding(.top, 6)
            #endif
            TheoryLibraryLayout(screen: $screen, sidebarWidth: 320) {
                listContent
            } detailContent: { showBackButton, onBack in
                detailContent(showBackButton: showBackButton, onBack: onBack)
            }
        }
        // Colors the persistent main-keyboard bar (`ContentView`) with this screen's own chord,
        // centered, while this tab is active, per explicit request — same mechanism
        // `ModeLibraryView`/`ProgressionLibraryView` use for their own mode.
        .registerMainKeyboardChord(
            id: "theorie.accords", isActive: isActive,
            chord: MainKeyboardChordSpec(root: chord.root.value, tones: chord.pitchClasses.map(\.value))
        )
    }

    #if os(macOS) || os(visionOS)
    @ViewBuilder
    private var detachButton: some View {
        if isDetachedWindow {
            Button {
                dismissWindow(id: AuxiliaryWindowID.theorieAccords.rawValue)
            } label: {
                Label(L10n.string(.appButtonReintegrer, session.currentLanguage), systemImage: "arrow.down.right.and.arrow.up.left")
            }
        } else {
            Button {
                openWindow(id: AuxiliaryWindowID.theorieAccords.rawValue)
            } label: {
                Image(systemName: "rectangle.on.rectangle")
            }
        }
    }
    #endif

    // MARK: - List (left column / first screen)

    private var listContent: some View {
        Form {
            Section {
                if usesTwoColumns {
                    // A 12-way segmented control doesn't fit a fixed-width sidebar column —
                    // same reasoning `JamShackLanguageView` already documents for its own
                    // language picker.
                    Picker(L10n.string(.fieldTonique, session.currentLanguage), selection: $selectedRoot) {
                        ForEach(0..<12, id: \.self) { pitchClass in
                            Text(session.notationStyle.rootName(PitchClass(pitchClass), preferFlats: false)).tag(pitchClass)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Picker(L10n.string(.fieldTonique, session.currentLanguage), selection: $selectedRoot) {
                        ForEach(0..<12, id: \.self) { pitchClass in
                            Text(session.notationStyle.rootName(PitchClass(pitchClass), preferFlats: false)).tag(pitchClass)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text(L10n.string(.appHeadingBibliothequeAccords, session.currentLanguage))
            }
            Section {
                ForEach(ChordVocabulary.allIDs(), id: \.self) { id in
                    Button {
                        selectedTemplateID = id
                        inversion = 0
                        guitarPosition = 0
                        screen = .detail
                    } label: {
                        HStack {
                            Text(displayName(forTemplateID: id))
                                .foregroundStyle(id == selectedTemplateID ? Color.accentColor : .primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(L10n.string(.appFieldQualite, session.currentLanguage))
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    private func displayName(forTemplateID id: String) -> String {
        guard let template = ChordVocabulary.byID(id) else { return id }
        return session.notationStyle.displayName(for: Chord(root: PitchClass(selectedRoot), template: template))
    }

    // MARK: - Detail (right column / second screen)

    private var maxInversion: Int { Chord.maxInversion(for: chord.template) }

    /// Fondamentale (always available) plus every inversion `GuitarChordShape` actually has a
    /// curated shape for, at the current quality — see `hasVerifiedInversionShape`'s doc comment.
    private var availableGuitarPositions: [Int] {
        [0] + [1, 2, 3].filter { GuitarChordShape.hasVerifiedInversionShape(chordTemplateID: selectedTemplateID, inversion: $0) }
    }

    private func guitarPositionLabel(_ position: Int) -> String {
        switch position {
        case 1: return L10n.string(.appOptionPosition1ereInversion, session.currentLanguage)
        case 2: return L10n.string(.appOptionPosition2emeInversion, session.currentLanguage)
        case 3: return L10n.string(.appOptionPosition3emeInversion, session.currentLanguage)
        default: return L10n.string(.appOptionPositionFondamentale, session.currentLanguage)
        }
    }

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

                Text(session.notationStyle.displayName(for: chord)).font(.largeTitle).bold()

                // Staff / keyboard / tablature side by side, per explicit request (used to be
                // stacked top to bottom) — narrow widths fall back to stacking, same breakpoint
                // as everywhere else. `.staffCenter` (not `.top`) so the keyboard lines up on
                // the staff itself, not the inversion stepper sitting above it — per explicit
                // request.
                if usesTwoColumns {
                    HStack(alignment: .staffCenter, spacing: 16) {
                        staffColumn
                        keyboardColumn
                        tablatureColumn
                    }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        staffColumn
                        keyboardColumn
                        tablatureColumn
                    }
                }

                SequenceTransportView(
                    isPlaying: session.isAuditioningTheoryLibrary,
                    language: session.currentLanguage,
                    onPlay: play,
                    onStop: { session.stopTheoryLibraryAudition() }
                )
            }
            .padding()
        }
    }

    private var staffColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Above the staff, per explicit request (used to sit below it).
            if maxInversion > 0 {
                Stepper(value: $inversion, in: 0...maxInversion) {
                    Text("\(L10n.string(.appFieldInversion, session.currentLanguage)) : \(inversion)")
                }
            }
            // Widened (no `widthScale` reduction, plus a minimum column count) — a single-chord
            // staff is normally just one narrow column, too cramped next to a 300pt keyboard and
            // the played-notes label right under it, per explicit request ("est-elle assez
            // large ?").
            ChordStaffView(events: [staffEvent], heightScale: 0.85, minimumColumnCount: 3)
                .alignmentGuide(.staffCenter) { $0[VerticalAlignment.center] }
            // Directly under the staff, per explicit request: what's ACTUALLY being played right
            // now on the "source principale" track, not just this chord's own reference notes.
            livePlayedNotesLabel
        }
    }

    /// Shows only this inversion's own specific voicing (see `voicingPitches`), not every
    /// occurrence of each tone across 2 octaves — per explicit request — via
    /// `referenceChordPitches` rather than `alwaysShowChord`. `heldPitches` overlays whatever's
    /// actually captured on the "source principale" track live, per explicit request — a real
    /// held note outside the chord still gets its own `.heldOutsideChord` role since `chordRoot`
    /// is set, so a wrong note reads clearly as "not this chord" rather than being ignored.
    private var keyboardColumn: some View {
        PitchKeyboardView(
            heldPitches: liveHeldPitches,
            chordRoot: chord.root.value,
            chordTones: chord.pitchClasses.map(\.value),
            height: Self.chordKeyboardSize.height,
            keyLabels: PitchKeyboardView.noteNameKeyLabels(forPitches: voicingPitches, style: session.notationStyle),
            referenceChordPitches: Set(voicingPitches)
        )
        .frame(width: Self.chordKeyboardSize.width)
        .alignmentGuide(.staffCenter) { $0[VerticalAlignment.center] }
    }

    @ViewBuilder
    private var tablatureColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Only offer positions that actually produce a distinct diagram (see
            // `GuitarChordShape.hasVerifiedInversionShape`) — most qualities beyond
            // "Ma"/"mi" have no curated inversion shape yet, so showing those options
            // here would look tappable but silently do nothing.
            if availableGuitarPositions.count > 1 {
                Text(L10n.string(.appFieldPosition, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
                Picker(L10n.string(.appFieldPosition, session.currentLanguage), selection: $guitarPosition) {
                    ForEach(availableGuitarPositions, id: \.self) { position in
                        Text(guitarPositionLabel(position)).tag(position)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            GuitarChordDiagramView(
                root: selectedRoot, chordTemplateID: selectedTemplateID, inversion: guitarPosition,
                language: session.currentLanguage
            )
        }
    }

    /// -50%-ish off `PitchKeyboardView`'s own default (144×fluid width) — now that the keyboard
    /// only ever shows one voicing (3-5 keys) instead of the same tones repeated across 2
    /// octaves, a compact fixed size reads better next to the staff/tablature, per explicit
    /// request ("ajuster les tailles pour que ce soit proportionnellement agréable").
    private static let chordKeyboardSize = CGSize(width: 300, height: 130)

    /// One close-position voicing of the current inversion, anchored just above middle C —
    /// each successive tone placed in the next octave up so the shape actually reflects which
    /// tone is the bass, unlike `ChordStaffView.chordEvent(root:tones:)` (root-position only).
    private var staffEvent: StaffEvent {
        ChordStaffView.ascendingVoicing(
            pitchClasses: chord.voicing(inversion: inversion).orderedPitchClasses.map(\.value),
            chordRoot: chord.root.value, chordTones: chord.pitchClasses.map(\.value)
        )
    }

    /// The current inversion's own ascending voicing as absolute pitches — feeds both
    /// `staffEvent` (already did) and `keyboardColumn`'s `referenceChordPitches`, so the staff
    /// and the mini keyboard always agree on which exact notes represent "this inversion."
    private var voicingPitches: [Int] {
        PitchSequencing.ascendingPitches(
            forPitchClasses: chord.voicing(inversion: inversion).orderedPitchClasses.map(\.value), startingAbove: 47
        )
    }

    /// Whichever live track is the app's current "source principale" — read directly (not
    /// cached in `@State`; `session.tracks` already triggers a SwiftUI refresh on change) so
    /// `keyboardColumn`/`livePlayedNotesLabel` always reflect what's actually being played,
    /// live, per explicit request.
    private var liveHeldPitches: Set<Int> {
        guard let sourceID = session.theoryLiveInputSourceID else { return [] }
        return session.tracks.first { $0.id == sourceID }?.heldPitches ?? []
    }

    @ViewBuilder
    private var livePlayedNotesLabel: some View {
        if !liveHeldPitches.isEmpty {
            let names = liveHeldPitches.sorted().map { session.notationStyle.rootName(PitchClass((($0 % 12) + 12) % 12), preferFlats: false) }
            Text("\(L10n.string(.appLabelNotesJouees, session.currentLanguage)) : \(names.joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func play() {
        guard let sound = session.theoryAuditionSound() else { return }
        try? session.loadTheoryLibraryAuditionSample(sound)
        session.playTheoryLibraryAudition([ImprovSession.TheoryAuditionNote(pitches: voicingPitches, startSeconds: 0, durationSeconds: 2)])
    }
}

#Preview {
    ChordLibraryView(session: ImprovSession())
}
