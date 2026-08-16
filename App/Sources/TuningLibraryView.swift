import SwiftUI
import AppCore
import JamShackUI
import MusicTheoryKit
import PieceModel
import Localization

/// Théorie's "Intonations" tab — picks a fixed temperament + A4 reference (`TuningConfiguration`,
/// persisted via `session.setTuningConfiguration(_:)`, same pattern as `NotationStyleSettingsView`),
/// AND its own tonic + mode (mirrors `ProgressionLibraryView`'s simpler tonic/scale picker,
/// restricted to family 1 — the 7 classic modes — since `ChordProgressionResolver
/// .diatonicChordReferences(in:)` only resolves a full diatonic-chord table for that family), so
/// this screen is self-sufficient: pick a temperament, pick a tonic/mode, and immediately hear
/// its notes and diatonic chords both "non tempéré" (plain 12-TET) and "tempéré" (with the
/// picked temperament's correction), A/B style. Being active registers this mode as
/// `session.contextualMode` exactly like Modes/Progressions/Exploration do, so this screen's own
/// pick becomes the temperament's live anchor everywhere else too while it's the active tab.
struct TuningLibraryView: View {
    let session: ImprovSession
    /// See `ChordLibraryView.isActive`'s own doc comment — feeds `session.setContextualMode`.
    let isActive: Bool
    /// See `ChordLibraryView.isDetachedWindow`'s own doc comment — self-adapts `detachButton`.
    var isDetachedWindow: Bool = false

    @Environment(AppModel.self) private var appModel
    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    @State private var actionError: String?
    @State private var referenceA4Text: String = ""
    @State private var playbackGeneration = 0
    /// Whole-octave shift applied to both staffs/keyboards/playback — per explicit request, so
    /// this screen's notes/chords can be brought low enough to land on the bass (fa) clef
    /// instead of always sitting around middle C.
    @State private var octaveShift: Int = 0
    /// Which staff column is currently sounding — separate vars (not one shared index) since
    /// the two staves have entirely different column counts/meanings; sharing one would
    /// highlight the wrong column on whichever staff isn't actually playing. Driven by the
    /// sequence buttons (`playScale`/`playChordSequence`) AND, per explicit request, by tapping
    /// a column directly or pressing a single note/chord's own play button below — same visual
    /// highlight either way.
    @State private var playingNoteIndex: Int?
    @State private var playingChordIndex: Int?
    /// One note being spectrum-compared per `SpectrumNoteInput` entry — a single tapped scale
    /// degree (1 entry) or every tone of a tapped chord (one per chord tone), each rendered as a
    /// raw + corrected pair (see `spectrumTones`). `nil` before anything's been tapped, or while a
    /// render is in flight (see `spectrumGeneration`). Ephemeral by design, same as
    /// `DissonancesLibraryView.rawSpectra` — see `NoteSpectrumView`'s own doc comment for why this
    /// doesn't cache/persist spectra for every note/chord ever explored.
    private struct SpectrumNoteInput {
        let pitch: Int
        let cents: Double
        let label: String
        let color: Color
    }
    @State private var spectrumNotes: [SpectrumNoteInput] = []
    @State private var rawSpectraByNote: [RawNoteSpectrum]?
    /// Guards against an in-flight render for an already-superseded note/chord tap completing
    /// late and overwriting a newer selection's result — same pattern `DissonancesLibraryView
    /// .spectrumGeneration` already uses for its own analogous race.
    @State private var spectrumGeneration = 0

    /// Which of the two staffs (with their play buttons/degree list) column 1 currently shows —
    /// per explicit request: notes/chords used to sit side by side as their own columns; now a
    /// toggle picks one at a time, freeing column 1's width for the spectrum graph in column 2.
    private enum IntonationsColumnKind: String, CaseIterable, Identifiable {
        case notes, chords
        var id: Self { self }
    }
    @State private var selectedColumnKind: IntonationsColumnKind = .notes
    /// Column 1's actual measured width (`.onGeometryChange`, not a `GeometryReader` — the same
    /// reason `ProgressionLibraryView.columnsRowWidth` doesn't use one: a `GeometryReader` wants
    /// to fill all available height too, which collapses to nothing useful inside this screen's
    /// `ScrollView`) — feeds `ChordStaffView.maxColumnCount(forWidth:widthScale:keySignature:)` so
    /// a scale/chord run that doesn't fit column 1's now-fixed ~1/3 width wraps onto further rows
    /// instead of clipping, same technique `ProgressionLibraryView.progressionStaffRows` already
    /// uses for its own staff.
    @State private var column1Width: CGFloat = 0

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Same breakpoint every other Théorie library screen uses for its own side-by-side columns
    /// (`ModeLibraryView`/`ChordLibraryView`/`ProgressionLibraryView`) — lets "Notes de la gamme"
    /// and "Accords du mode" sit next to each other instead of one below the other when there's
    /// room, per explicit request.
    private var usesTwoColumns: Bool { TheoryLibraryLayoutMode.usesTwoColumns(horizontalSizeClass: horizontalSizeClass) }

    /// Reads/writes the ONE shared tonic+scale selection (`AppModel.sharedMode`) instead of a
    /// local `@State`, so picking a mode here is reflected on every other MusicLab screen,
    /// including detached windows — per explicit request. This screen's own tonic/scale picker
    /// stays restricted to the 7 classic modes (see this struct's own doc comment), but the
    /// SHARED value can be set to something outside that list by another screen — see
    /// `isSharedModeSupported`.
    private var mode: Mode {
        Mode(tonic: PitchClass(appModel.sharedMode.tonic), scale: ScaleLibrary.byID(appModel.sharedMode.scaleID) ?? ScaleLibrary.scales(inFamily: 1)[0])
    }

    /// `false` when the shared mode (picked on another screen) isn't one of the 7 classic modes
    /// this screen's diatonic-chord table actually supports — per explicit request, the screen
    /// then gates its main content behind an empty-state message, while its own (family-
    /// restricted) picker stays active so a valid mode can be re-picked right here.
    private var isSharedModeSupported: Bool {
        (ScaleLibrary.byID(appModel.sharedMode.scaleID)?.familyID ?? 1) == 1
    }

    private var sharedTonicBinding: Binding<Int> {
        Binding(get: { appModel.sharedMode.tonic }, set: { appModel.sharedMode.tonic = $0 })
    }
    private var sharedScaleIDBinding: Binding<String> {
        Binding(get: { appModel.sharedMode.scaleID }, set: { appModel.sharedMode.scaleID = $0 })
    }

    /// The mode's parent major key's conventional signature — same derivation as
    /// `ModeLibraryView.modeKeySignature` (see there for why `CircleOfFifths.parentTonic`, not
    /// `MajorKeySignature.forMajorTonic(mode.tonic.value)` directly), shared by both staves
    /// below so accidentals show at the clef instead of on every affected note.
    private var modeKeySignature: MajorKeySignature? {
        CircleOfFifths.parentTonic(for: mode).map { MajorKeySignature.forMajorTonic($0.value) }
    }

    private var scaleDegreesWithOctave: [Int] {
        mode.pitchClasses.map(\.value) + [mode.tonic.value]
    }

    /// Triads only, per explicit request — matches `ChordProgressionResolver`'s own default
    /// (Mode/Progression screens already use `.triad`); this screen previously pinned `.seventh`
    /// deliberately, but that's no longer wanted here either.
    private var diatonicChordReferences: [ChordReference] {
        ChordProgressionResolver.diatonicChordReferences(in: mode, qualityTier: .triad)
    }

    private var sourceID: TrackID? { session.theoryLiveInputSourceID }

    /// The mode's own 7 degrees, correctly spelled (e.g. Ab, not G#, in Ab major) — `nil` only in
    /// principle, since the scale picker above is already restricted to family 1 (see
    /// `DiatonicSpelling.spelledDegrees(for:)`'s own doc comment).
    private var spelledDegrees: [SpelledPitch] {
        DiatonicSpelling.spelledDegrees(for: mode) ?? mode.pitchClasses.map(DiatonicSpelling.canonicalSpelling(forPitchClass:))
    }

    private func spelledName(_ spelled: SpelledPitch) -> String {
        "\(spelled.letter)\(spelled.accidental.symbol)"
    }

    private var noteStaffEvents: [StaffEvent] {
        ChordStaffView.ascendingSequence(
            pitchClasses: scaleDegreesWithOctave, chordRoot: mode.tonic.value, chordTones: mode.pitchClasses.map(\.value),
            startingAbove: 59 + octaveShift * 12
        )
    }

    /// Ascending, octave-correct root anchor for each of `mode`'s own 7 diatonic degrees, one
    /// entry per `mode.pitchClasses` in degree order — same anchor mechanism
    /// (`PitchSequencing.ascendingPitches`) `noteStaffEvents` already uses for the SCALE run, at
    /// that same visual register (`59`, matching `noteStaffEvents`'s own `startingAbove`). Real
    /// bug fix: `chordStaffEvents` used to place each chord independently via
    /// `ChordStaffView.chordEvent(root:...)`, which anchors purely from that chord's OWN root
    /// pitch class (`60 + root`) with no regard for scale-degree order — so any degree whose root
    /// pitch class is numerically LOWER than an earlier degree's (e.g. every non-tonic degree of
    /// B natural minor, tonic pitch class 11) was drawn (and played, see `diatonicVoicingPitches`
    /// below) a full octave too low. See `ModeLibraryView`'s own identical fix/doc comment.
    private var diatonicDegreeRootAnchorsForStaff: [Int] {
        PitchSequencing.ascendingPitches(forPitchClasses: mode.pitchClasses.map(\.value), startingAbove: 59 + octaveShift * 12)
    }

    /// Same idea as `diatonicDegreeRootAnchorsForStaff`, at the lower register the "non tempéré"/
    /// "tempéré" playback buttons use (`47`) — feeds `diatonicVoicingPitches`, shared by every
    /// chord PLAYBACK site below.
    private var diatonicDegreeRootAnchorsForPlayback: [Int] {
        PitchSequencing.ascendingPitches(forPitchClasses: mode.pitchClasses.map(\.value), startingAbove: 47 + octaveShift * 12)
    }

    /// `chord`'s own tones, voiced from whichever of `diatonicDegreeRootAnchorsForPlayback`
    /// matches its root (always one of `mode`'s own 7 diatonic degrees here, unlike
    /// `ModeLibraryView`'s equivalent — this screen has no separate progression-chip caller with
    /// a borrowed/chromatic root to fall back for).
    private func diatonicVoicingPitches(for chord: Chord) -> [Int] {
        let degreeRoots = mode.pitchClasses.map(\.value)
        guard let index = degreeRoots.firstIndex(of: chord.root.value) else {
            return PitchSequencing.ascendingPitches(forPitchClasses: chord.pitchClasses.map(\.value), startingAbove: 47 + octaveShift * 12)
        }
        let rootMidi = diatonicDegreeRootAnchorsForPlayback[index]
        return chord.pitchClasses.map { pc in rootMidi + (((pc.value - chord.root.value) % 12) + 12) % 12 }
    }

    private var chordStaffEvents: [StaffEvent] {
        let references = diatonicChordReferences
        let anchors = diatonicDegreeRootAnchorsForStaff
        return references.enumerated().compactMap { index, reference in
            guard let chord = reference.resolve(), anchors.indices.contains(index) else { return nil }
            let rootMidi = anchors[index]
            let pitches = chord.pitchClasses.map { pc in rootMidi + (((pc.value - chord.root.value) % 12) + 12) % 12 }
            return StaffEvent(pitches: pitches, chordRoot: chord.root.value, chordTones: chord.pitchClasses.map(\.value))
        }
    }

    /// Compact -2...+2 octave control shared by both staffs (`noteStaffEvents`/
    /// `chordStaffEvents`) and their paired playback pitches — one control, applied to
    /// everything this screen shows, per explicit request.
    private var octaveShiftControl: some View {
        Stepper(value: $octaveShift, in: -2...2) {
            Text("\(L10n.string(.appFieldOctave, session.currentLanguage)) : \(octaveShift >= 0 ? "+\(octaveShift)" : "\(octaveShift)")")
                .font(.caption)
        }
        .fixedSize()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                #if os(macOS) || os(visionOS)
                HStack {
                    Spacer()
                    detachButton
                    TheoryHelpButton(session: session)
                }
                #endif
                if let actionError {
                    Text(actionError).foregroundStyle(.red).font(.caption)
                }
                settingsSection
                if isSharedModeSupported {
                    octaveShiftControl
                    // Column 1 (staff/values, toggled notes<->chords) : column 2 (spectrum graph).
                    // Column 1 gets a real fixed width — widened from the original 320
                    // (`TheoryLibraryLayout.sidebarWidth`'s convention) to 500 per explicit
                    // request, so the 7-chord "accords du mode" staff fits on one row instead of
                    // wrapping even at the widest key signatures (7 accidentals) — see
                    // `column1Width`'s own doc comment for how it wraps onto further rows instead
                    // of clipping if 500pt still isn't enough at the current `widthScale`. Column
                    // 2 (spectrum graph) narrows accordingly, but `NoteSpectrumView`'s own height
                    // is fixed (`minHeight: 160` + a 56pt keyboard strip), not width-derived, so
                    // this doesn't actually shrink the spectrum graph's height.
                    if usesTwoColumns {
                        HStack(alignment: .top, spacing: 20) {
                            notesOrChordsColumn
                                .frame(width: 500, alignment: .leading)
                            spectrumSection
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        notesOrChordsColumn
                        spectrumSection
                    }
                    if !heldPitches.isEmpty {
                        heldNotesSection
                    }
                } else {
                    Text(L10n.string(.appHintExplorationFamilleUn, session.currentLanguage))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .onAppear { referenceA4Text = formattedA4(session.tuningConfiguration.referenceA4) }
        .onChange(of: isActive, initial: true) { _, active in
            session.setContextualMode(active ? mode : nil)
        }
        .onChange(of: mode) { _, newMode in
            guard isActive else { return }
            session.setContextualMode(newMode)
        }
    }

    #if os(macOS) || os(visionOS)
    @ViewBuilder
    private var detachButton: some View {
        if isDetachedWindow {
            Button {
                dismissWindow(id: AuxiliaryWindowID.theorieIntonation.rawValue)
            } label: {
                Label(L10n.string(.appButtonReintegrer, session.currentLanguage), systemImage: "arrow.down.right.and.arrow.up.left")
            }
        } else {
            Button {
                openWindow(id: AuxiliaryWindowID.theorieIntonation.rawValue)
            } label: {
                Image(systemName: "rectangle.on.rectangle")
            }
        }
    }
    #endif

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                Picker(L10n.string(.appFieldTemperament, session.currentLanguage), selection: Binding(
                    get: { session.tuningConfiguration.temperamentID },
                    set: { newID in updateConfiguration { $0.temperamentID = newID } }
                )) {
                    ForEach(TemperamentLibrary.all) { temperament in
                        Text(label(forTemperamentID: temperament.id)).tag(temperament.id)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                HStack {
                    Text(L10n.string(.appFieldReferenceA4, session.currentLanguage))
                    TextField("440", text: $referenceA4Text)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .onSubmit(commitReferenceA4)
                        #if os(macOS)
                        .onChange(of: referenceA4Text) { _, _ in commitReferenceA4() }
                        #endif
                }

                Picker(L10n.string(.fieldTonique, session.currentLanguage), selection: sharedTonicBinding) {
                    ForEach(0..<12, id: \.self) { pitchClass in
                        Text(session.notationStyle.rootName(PitchClass(pitchClass), preferFlats: false)).tag(pitchClass)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Picker(L10n.string(.fieldGamme, session.currentLanguage), selection: sharedScaleIDBinding) {
                    ForEach(ScaleLibrary.scales(inFamily: 1), id: \.id) { scale in
                        Text(scale.popularName).tag(scale.id)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Spacer()

                // Same "get back to the modern-standard temperament without remembering which
                // one that was" affordance as `TuningQuickPickerView`'s own reset button.
                if session.tuningConfiguration != TuningConfiguration() {
                    Button {
                        updateConfiguration { $0 = TuningConfiguration() }
                    } label: {
                        Label(L10n.string(.appButtonReinitialiser, session.currentLanguage), systemImage: "arrow.counterclockwise")
                    }
                }
            }
            Text(mode.displayName).font(.title2).bold()
        }
    }

    private static let noteStaffWidthScale: CGFloat = 0.7
    // widened from 0.7 to 1.1 — more room between chords, per explicit request.
    private static let chordStaffWidthScale: CGFloat = 1.1

    /// Column 1 — a segmented toggle picking which of the two staffs (+ its play buttons/degree
    /// list) shows below, replacing the old side-by-side notes/chords columns now that column 1
    /// only has ~1/3 of the width to work with (see `body`'s own doc comment).
    private var notesOrChordsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $selectedColumnKind) {
                Text(L10n.string(.appHeadingNotesDeLaGamme, session.currentLanguage)).tag(IntonationsColumnKind.notes)
                Text(L10n.string(.appHeadingAccordsDuMode, session.currentLanguage)).tag(IntonationsColumnKind.chords)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch selectedColumnKind {
            case .notes: notesColumn
            case .chords: chordsColumn
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { column1Width = $0 }
    }

    /// Chunks `events` into as many `ChordStaffView`-column-sized rows as fit `column1Width` at
    /// `widthScale` (see `ChordStaffView.maxColumnCount`) instead of one wide staff that would
    /// clip or force horizontal scrolling in column 1's now-fixed, narrower width — same
    /// technique `ProgressionLibraryView.progressionStaffRows` already uses for its own staff.
    private func staffRows(_ events: [StaffEvent], widthScale: CGFloat) -> [[(offset: Int, event: StaffEvent)]] {
        let indexed = events.enumerated().map { (offset: $0.offset, event: $0.element) }
        let perRow = max(1, ChordStaffView.maxColumnCount(forWidth: column1Width, widthScale: widthScale, keySignature: modeKeySignature))
        return stride(from: 0, to: indexed.count, by: perRow).map { Array(indexed[$0..<min($0 + perRow, indexed.count)]) }
    }

    private var notesColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(.appHeadingNotesDeLaGamme, session.currentLanguage)).font(.headline)
            ForEach(Array(staffRows(noteStaffEvents, widthScale: Self.noteStaffWidthScale).enumerated()), id: \.offset) { _, row in
                ChordStaffView(
                    events: row.map(\.event),
                    colorScheme: .noteBased(rootPitchClass: mode.tonic, palette: session.activeColorPalette.colors),
                    heightScale: 0.8, widthScale: Self.noteStaffWidthScale,
                    highlightedIndex: row.firstIndex(where: { $0.offset == playingNoteIndex }), keySignature: modeKeySignature,
                    onColumnTap: { localIndex in
                        guard row.indices.contains(localIndex) else { return }
                        playSingleNote(columnIndex: row[localIndex].offset, tempered: true)
                    }
                )
            }
            HStack {
                Button(L10n.string(.appButtonJouerNonTempere, session.currentLanguage)) { playScale(tempered: false) }
                Button(L10n.string(.appButtonJouerTempere, session.currentLanguage)) { playScale(tempered: true) }
            }
            ForEach(Array(spelledDegrees.enumerated()), id: \.offset) { index, spelled in
                HStack {
                    Text(spelledName(spelled))
                    Text(String(format: "%+.1f ¢", cents(for: spelled.pitchClass))).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Button { playSingleNote(columnIndex: index, tempered: false) } label: {
                        Image(systemName: "play")
                    }.accessibilityLabel(L10n.string(.appButtonJouerNonTempere, session.currentLanguage))
                    Button { playSingleNote(columnIndex: index, tempered: true) } label: {
                        Image(systemName: "play.fill")
                    }.accessibilityLabel(L10n.string(.appButtonJouerTempere, session.currentLanguage))
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chordsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(.appHeadingAccordsDuMode, session.currentLanguage)).font(.headline)
            ForEach(Array(staffRows(chordStaffEvents, widthScale: Self.chordStaffWidthScale).enumerated()), id: \.offset) { _, row in
                ChordStaffView(
                    events: row.map(\.event), notePalette: session.activeColorPalette.colors,
                    heightScale: 0.8, widthScale: Self.chordStaffWidthScale,
                    highlightedIndex: row.firstIndex(where: { $0.offset == playingChordIndex }), keySignature: modeKeySignature,
                    onColumnTap: { localIndex in
                        guard row.indices.contains(localIndex) else { return }
                        playSingleChord(columnIndex: row[localIndex].offset, tempered: true)
                    }
                )
            }
            HStack {
                Button(L10n.string(.appButtonJouerNonTempere, session.currentLanguage)) { playChordSequence(tempered: false) }
                Button(L10n.string(.appButtonJouerTempere, session.currentLanguage)) { playChordSequence(tempered: true) }
            }
            ForEach(Array(diatonicChordReferences.enumerated()), id: \.offset) { index, reference in
                HStack {
                    Text(chordDisplayName(reference))
                    Spacer()
                    Button { playSingleChord(columnIndex: index, tempered: false) } label: {
                        Image(systemName: "play")
                    }.accessibilityLabel(L10n.string(.appButtonJouerNonTempere, session.currentLanguage))
                    Button { playSingleChord(columnIndex: index, tempered: true) } label: {
                        Image(systemName: "play.fill")
                    }.accessibilityLabel(L10n.string(.appButtonJouerTempere, session.currentLanguage))
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heldNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(.appHeadingNotesTenuesEtCorrection, session.currentLanguage)).font(.headline)
            ForEach(heldPitches, id: \.self) { pitch in
                HStack {
                    Text(session.notationStyle.rootName(PitchClass(pitch), preferFlats: false))
                    Spacer()
                    Text(String(format: "%+.1f ¢", fixedTemperamentCents(forPitchClass: PitchClass(pitch), tonic: mode.tonic, configuration: session.tuningConfiguration)))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }

    private var heldPitches: [Int] {
        guard let sourceID else { return [] }
        return (session.tracks.first { $0.id == sourceID }?.heldPitches ?? []).sorted()
    }

    /// Overlays each last-tapped note/chord tone's raw ("SF2 (égal)", 0 cents — filled, per
    /// `NoteSpectrumView.Tone.isBase`) and temperament-corrected (line only) full FFT spectra on
    /// one shared axis — one tone for a tapped scale degree, one PER TONE for a tapped chord
    /// (root/3rd/5th/7th can each carry a different correction under a non-equal temperament, so
    /// a chord's comparison isn't just its root's). Deliberately a single STEADY-STATE snapshot,
    /// not a live/animated spectrum — same `RawSpectrumRenderer`/`OfflineNoteRenderer` pipeline
    /// `DissonancesLibraryView` already uses (renders the note offline, skips the attack
    /// transient, takes one FFT window from the sustained portion): a played note's timbre does
    /// evolve over its attack/decay, but what this graph needs to show is WHERE the correction
    /// moves each harmonic, which a steady-state snapshot already answers — an animation would add
    /// real complexity (live audio-tap FFT is a completely different, not-reused mechanism, see
    /// `ImprovSession.currentMicrophoneSpectrum`) for no comparison benefit, since the correction
    /// itself doesn't change over the note's duration. The correction itself needs no separate
    /// "difference" visualization either: since both spectra are rendered from the SAME real
    /// audio (just pitch-shifted), on this view's pitch-LINEAR (log-Hz) x-axis a cents offset
    /// shows up as a uniform lateral shift between the two curves' peaks — the gap IS the shift,
    /// visible directly, not something to compute/draw separately.
    @ViewBuilder
    private var spectrumSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(.appHeadingSpectreNote, session.currentLanguage)).font(.headline)
            if let spectrumTones {
                NoteSpectrumView(tones: spectrumTones)
            } else if !spectrumNotes.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            } else {
                Text(L10n.string(.appHintSpectreAucuneNote, session.currentLanguage))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// One color per chord-tone position (root/3rd/5th/7th) — same 3-color convention
    /// `DissonancesLibraryView.toneColors` uses for its own 3 tones, extended to 4 for a seventh
    /// chord; cycles if a chord ever had more tones than colors (shouldn't happen for a triad/7th).
    private static let spectrumToneColors: [Color] = [.blue, .green, .orange, .purple]

    private var spectrumTones: [NoteSpectrumView.Tone]? {
        guard let rawSpectraByNote, rawSpectraByNote.count == spectrumNotes.count * 2 else { return nil }
        return spectrumNotes.enumerated().flatMap { index, note -> [NoteSpectrumView.Tone] in
            let raw = rawSpectraByNote[index * 2]
            let corrected = rawSpectraByNote[index * 2 + 1]
            let rawLabel = "\(note.label) (\(L10n.string(.appLabelSpectreBrut, session.currentLanguage)))"
            let correctedLabel = "\(note.label) (\(L10n.string(.appLabelSpectreCorrige, session.currentLanguage)) \(String(format: "%+.1f¢", note.cents)))"
            return [
                NoteSpectrumView.Tone(label: rawLabel, pitch: note.pitch, color: note.color, spectrum: raw, isBase: true),
                NoteSpectrumView.Tone(label: correctedLabel, pitch: note.pitch, color: note.color, spectrum: corrected),
            ]
        }
    }

    /// Renders `notes.count * 2` spectra (raw + corrected per note) with the same instrument,
    /// loaded once — see `RawSpectrumRenderer.render(pitches:soundFontURL:preset:)`'s own doc
    /// comment. Used for both a single tapped scale degree (1 note) and every tone of a tapped
    /// chord (N notes).
    private func computeSpectrum(for notes: [SpectrumNoteInput]) async {
        spectrumNotes = notes
        rawSpectraByNote = nil
        spectrumGeneration += 1
        let generation = spectrumGeneration
        guard let sound = session.theoryAuditionSound() else { return }
        let pitches = notes.flatMap { [($0.pitch, 0.0), ($0.pitch, $0.cents)] }
        let soundFontURL = URL(fileURLWithPath: sound.path)
        let preset = sound.preset
        let result = try? await RawSpectrumRenderer.render(pitches: pitches, soundFontURL: soundFontURL, preset: preset)
        guard generation == spectrumGeneration else { return } // superseded by a newer note/chord tap
        rawSpectraByNote = result
    }

    private func cents(for pitchClass: PitchClass) -> Double {
        temperamentCents(forPitch: 60 + pitchClass.value, mode: mode, configuration: session.tuningConfiguration)
    }

    private func chordDisplayName(_ reference: ChordReference) -> String {
        guard let chord = reference.resolve() else { return "?" }
        return session.notationStyle.displayName(for: chord)
    }

    private func label(forTemperamentID id: String) -> String {
        switch id {
        case "equal": return "\(L10n.string(.appTemperamentEqual, session.currentLanguage)) \(L10n.string(.appLabelParDefaut, session.currentLanguage))"
        case "pythagorean": return L10n.string(.appTemperamentPythagorean, session.currentLanguage)
        case "justIntonation": return L10n.string(.appTemperamentJustIntonation, session.currentLanguage)
        case "werckmeisterIII": return L10n.string(.appTemperamentWerckmeisterIII, session.currentLanguage)
        default: return id
        }
    }

    private func formattedA4(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }

    private func commitReferenceA4() {
        guard let value = Double(referenceA4Text.replacingOccurrences(of: ",", with: ".")), value > 0 else { return }
        updateConfiguration { $0.referenceA4 = value }
    }

    private func updateConfiguration(_ mutate: (inout TuningConfiguration) -> Void) {
        var configuration = session.tuningConfiguration
        mutate(&configuration)
        do {
            try session.setTuningConfiguration(configuration)
        } catch {
            actionError = "\(error)"
        }
    }

    // MARK: - Playback (always through `theoryLiveInputSourceID`, so both the "unchanged" and
    // "tempéré" sides of the comparison go through the exact same sampler/voice path — only
    // `applyTuning` differs — for a fair A/B rather than comparing two different playback engines)

    /// `columnIndex` is both which `scaleDegreesWithOctave` entry to play AND which staff
    /// column to highlight while it sounds — tapping the staff directly passes its own tapped
    /// index; the per-degree play buttons below pass their `ForEach` loop index (the same
    /// index, since `spelledDegrees`/`scaleDegreesWithOctave` share the same degree order).
    private func playSingleNote(columnIndex: Int, tempered: Bool) {
        guard scaleDegreesWithOctave.indices.contains(columnIndex) else { return }
        let pitch = 60 + scaleDegreesWithOctave[columnIndex] + octaveShift * 12
        playPitches([pitch], tempered: tempered, durationSeconds: 0.7, highlight: $playingNoteIndex, highlightIndex: columnIndex)
        // Always shows BOTH the raw and corrected spectra, regardless of which of the two
        // "Jouer non tempéré"/"Jouer tempéré" buttons was actually pressed — `tempered` only
        // picks which one you HEAR, the graph compares both either way.
        let noteCents = temperamentCents(forPitch: pitch, mode: mode, configuration: session.tuningConfiguration)
        let label = session.notationStyle.rootName(PitchClass(pitch), preferFlats: false)
        Task { await computeSpectrum(for: [SpectrumNoteInput(pitch: pitch, cents: noteCents, label: label, color: Self.spectrumToneColors[0])]) }
    }

    /// See `playSingleNote(columnIndex:tempered:)`'s own doc comment — same idea, for
    /// `diatonicChordReferences`/the "accords du mode" staff instead, except the spectrum compares
    /// EVERY tone of the chord (not just its root), since each can carry its own correction.
    private func playSingleChord(columnIndex: Int, tempered: Bool) {
        guard diatonicChordReferences.indices.contains(columnIndex), let chord = diatonicChordReferences[columnIndex].resolve() else { return }
        let pitches = diatonicVoicingPitches(for: chord)
        playPitches(pitches, tempered: tempered, durationSeconds: 1.2, highlight: $playingChordIndex, highlightIndex: columnIndex)
        let notes = pitches.enumerated().map { index, pitch in
            SpectrumNoteInput(
                pitch: pitch, cents: temperamentCents(forPitch: pitch, mode: mode, configuration: session.tuningConfiguration),
                label: session.notationStyle.rootName(PitchClass(pitch), preferFlats: false),
                color: Self.spectrumToneColors[index % Self.spectrumToneColors.count]
            )
        }
        Task { await computeSpectrum(for: notes) }
    }

    /// `highlight`/`highlightIndex` mirror the corresponding staff's `highlightedIndex` for as
    /// long as `pitches` stays held — same highlight a sequence step gets in `playSequence`
    /// below, just for a single, explicitly tapped/pressed note or chord instead of a step in
    /// an animated run. `nil` (the default) skips highlighting entirely — not every caller of
    /// this shared helper is tied to a staff column.
    private func playPitches(_ pitches: [Int], tempered: Bool, durationSeconds: Double, highlight: Binding<Int?>? = nil, highlightIndex: Int? = nil) {
        guard let sourceID else { return }
        session.releaseAllKeys(track: sourceID)
        highlight?.wrappedValue = highlightIndex
        for pitch in pitches { session.pressKey(pitch: pitch, track: sourceID, applyTuning: tempered) }
        playbackGeneration += 1
        let generation = playbackGeneration
        Task {
            try? await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))
            if generation == playbackGeneration {
                for pitch in pitches { session.releaseKey(pitch: pitch, track: sourceID) }
                highlight?.wrappedValue = nil
            }
        }
    }

    private func playScale(tempered: Bool) {
        let pitches = PitchSequencing.ascendingPitches(forPitchClasses: scaleDegreesWithOctave, startingAbove: 47 + octaveShift * 12)
        playSequence(pitches.map { [$0] }, tempered: tempered, stepSeconds: 0.35, highlight: $playingNoteIndex)
    }

    private func playChordSequence(tempered: Bool) {
        let chordPitches = diatonicChordReferences.compactMap { $0.resolve() }.map(diatonicVoicingPitches(for:))
        playSequence(chordPitches, tempered: tempered, stepSeconds: 0.9, highlight: $playingChordIndex)
    }

    private func playSequence(_ items: [[Int]], tempered: Bool, stepSeconds: Double, highlight: Binding<Int?>) {
        guard let sourceID else { return }
        session.releaseAllKeys(track: sourceID)
        playbackGeneration += 1
        let generation = playbackGeneration
        Task {
            for (index, pitches) in items.enumerated() {
                guard generation == playbackGeneration else { return }
                highlight.wrappedValue = index
                for pitch in pitches { session.pressKey(pitch: pitch, track: sourceID, applyTuning: tempered) }
                try? await Task.sleep(nanoseconds: UInt64(stepSeconds * 0.85 * 1_000_000_000))
                guard generation == playbackGeneration else { return }
                for pitch in pitches { session.releaseKey(pitch: pitch, track: sourceID) }
                try? await Task.sleep(nanoseconds: UInt64(stepSeconds * 0.15 * 1_000_000_000))
            }
            if generation == playbackGeneration { highlight.wrappedValue = nil }
        }
    }
}

#Preview {
    TuningLibraryView(session: ImprovSession(), isActive: true)
}
