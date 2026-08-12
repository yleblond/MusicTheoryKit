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

    @State private var actionError: String?
    @State private var referenceA4Text: String = ""
    @State private var selectedTonic: Int = 0
    @State private var selectedScaleID: String = "ionian"
    @State private var playbackGeneration = 0
    /// Which staff column is currently sounding — separate vars (not one shared index) since
    /// the two staves have entirely different column counts/meanings; sharing one would
    /// highlight the wrong column on whichever staff isn't actually playing. Driven by the
    /// sequence buttons (`playScale`/`playChordSequence`) AND, per explicit request, by tapping
    /// a column directly or pressing a single note/chord's own play button below — same visual
    /// highlight either way.
    @State private var playingNoteIndex: Int?
    @State private var playingChordIndex: Int?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Same breakpoint every other Théorie library screen uses for its own side-by-side columns
    /// (`ModeLibraryView`/`ChordLibraryView`/`ProgressionLibraryView`) — lets "Notes de la gamme"
    /// and "Accords du mode" sit next to each other instead of one below the other when there's
    /// room, per explicit request.
    private var usesTwoColumns: Bool { TheoryLibraryLayoutMode.usesTwoColumns(horizontalSizeClass: horizontalSizeClass) }

    private var mode: Mode {
        Mode(tonic: PitchClass(selectedTonic), scale: ScaleLibrary.byID(selectedScaleID) ?? ScaleLibrary.scales(inFamily: 1)[0])
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

    private var diatonicChordReferences: [ChordReference] {
        ChordProgressionResolver.diatonicChordReferences(in: mode)
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
        ChordStaffView.ascendingSequence(pitchClasses: scaleDegreesWithOctave, chordRoot: mode.tonic.value, chordTones: mode.pitchClasses.map(\.value))
    }

    private var chordStaffEvents: [StaffEvent] {
        let references = diatonicChordReferences
        return references.compactMap { reference in
            guard let chord = reference.resolve() else { return nil }
            return ChordStaffView.chordEvent(root: chord.root.value, tones: chord.pitchClasses.map(\.value))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let actionError {
                    Text(actionError).foregroundStyle(.red).font(.caption)
                }
                settingsSection
                if usesTwoColumns {
                    HStack(alignment: .top, spacing: 20) {
                        notesColumn
                        chordsColumn
                    }
                } else {
                    notesColumn
                    chordsColumn
                }
                if !heldPitches.isEmpty {
                    heldNotesSection
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

                Picker(L10n.string(.fieldTonique, session.currentLanguage), selection: $selectedTonic) {
                    ForEach(0..<12, id: \.self) { pitchClass in
                        Text(session.notationStyle.rootName(PitchClass(pitchClass), preferFlats: false)).tag(pitchClass)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Picker(L10n.string(.fieldGamme, session.currentLanguage), selection: $selectedScaleID) {
                    ForEach(ScaleLibrary.scales(inFamily: 1), id: \.id) { scale in
                        Text(scale.popularName).tag(scale.id)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Spacer()
            }
            Text(mode.displayName).font(.title2).bold()
        }
    }

    private var notesColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string(.appHeadingNotesDeLaGamme, session.currentLanguage)).font(.headline)
            ChordStaffView(
                events: noteStaffEvents,
                colorScheme: .noteBased(rootPitchClass: mode.tonic, palette: session.activeColorPalette.colors),
                heightScale: 0.8, widthScale: 0.7, highlightedIndex: playingNoteIndex, keySignature: modeKeySignature,
                onColumnTap: { index in playSingleNote(columnIndex: index, tempered: true) }
            )
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
            ChordStaffView(
                events: chordStaffEvents, notePalette: session.activeColorPalette.colors,
                // widthScale widened from 0.7 to 1.1 — more room between chords, per explicit
                // request; heightScale unchanged (only horizontal spacing was cramped).
                heightScale: 0.8, widthScale: 1.1, highlightedIndex: playingChordIndex, keySignature: modeKeySignature,
                onColumnTap: { index in playSingleChord(columnIndex: index, tempered: true) }
            )
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

    private func cents(for pitchClass: PitchClass) -> Double {
        temperamentCents(forPitch: 60 + pitchClass.value, mode: mode, configuration: session.tuningConfiguration)
    }

    private func chordDisplayName(_ reference: ChordReference) -> String {
        guard let chord = reference.resolve() else { return "?" }
        return session.notationStyle.displayName(for: chord)
    }

    private func label(forTemperamentID id: String) -> String {
        switch id {
        case "equal": return L10n.string(.appTemperamentEqual, session.currentLanguage)
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
        playPitches([60 + scaleDegreesWithOctave[columnIndex]], tempered: tempered, durationSeconds: 0.7, highlight: $playingNoteIndex, highlightIndex: columnIndex)
    }

    /// See `playSingleNote(columnIndex:tempered:)`'s own doc comment — same idea, for
    /// `diatonicChordReferences`/the "accords du mode" staff instead.
    private func playSingleChord(columnIndex: Int, tempered: Bool) {
        guard diatonicChordReferences.indices.contains(columnIndex), let chord = diatonicChordReferences[columnIndex].resolve() else { return }
        let pitches = PitchSequencing.ascendingPitches(forPitchClasses: chord.pitchClasses.map(\.value), startingAbove: 47)
        playPitches(pitches, tempered: tempered, durationSeconds: 1.2, highlight: $playingChordIndex, highlightIndex: columnIndex)
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
        let pitches = PitchSequencing.ascendingPitches(forPitchClasses: scaleDegreesWithOctave, startingAbove: 47)
        playSequence(pitches.map { [$0] }, tempered: tempered, stepSeconds: 0.35, highlight: $playingNoteIndex)
    }

    private func playChordSequence(tempered: Bool) {
        let chordPitches = diatonicChordReferences.compactMap { $0.resolve() }.map {
            PitchSequencing.ascendingPitches(forPitchClasses: $0.pitchClasses.map(\.value), startingAbove: 47)
        }
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
