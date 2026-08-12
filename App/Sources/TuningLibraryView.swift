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
    @State private var playingIndex: Int?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Same breakpoint every other Théorie library screen uses for its own side-by-side columns
    /// (`ModeLibraryView`/`ChordLibraryView`/`ProgressionLibraryView`) — lets "Notes de la gamme"
    /// and "Accords du mode" sit next to each other instead of one below the other when there's
    /// room, per explicit request.
    private var usesTwoColumns: Bool { TheoryLibraryLayoutMode.usesTwoColumns(horizontalSizeClass: horizontalSizeClass) }

    private var mode: Mode {
        Mode(tonic: PitchClass(selectedTonic), scale: ScaleLibrary.byID(selectedScaleID) ?? ScaleLibrary.scales(inFamily: 1)[0])
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
            ChordStaffView(events: noteStaffEvents, heightScale: 0.8, widthScale: 0.7, highlightedIndex: playingIndex)
            HStack {
                Button(L10n.string(.appButtonJouerNonTempere, session.currentLanguage)) { playScale(tempered: false) }
                Button(L10n.string(.appButtonJouerTempere, session.currentLanguage)) { playScale(tempered: true) }
            }
            ForEach(Array(spelledDegrees.enumerated()), id: \.offset) { _, spelled in
                HStack {
                    Text(spelledName(spelled))
                    Text(String(format: "%+.1f ¢", cents(for: spelled.pitchClass))).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Button { playSingleNote(pitchClass: spelled.pitchClass.value, tempered: false) } label: {
                        Image(systemName: "play")
                    }.accessibilityLabel(L10n.string(.appButtonJouerNonTempere, session.currentLanguage))
                    Button { playSingleNote(pitchClass: spelled.pitchClass.value, tempered: true) } label: {
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
            ChordStaffView(events: chordStaffEvents, heightScale: 0.8, widthScale: 0.7, highlightedIndex: playingIndex)
            HStack {
                Button(L10n.string(.appButtonJouerNonTempere, session.currentLanguage)) { playChordSequence(tempered: false) }
                Button(L10n.string(.appButtonJouerTempere, session.currentLanguage)) { playChordSequence(tempered: true) }
            }
            ForEach(Array(diatonicChordReferences.enumerated()), id: \.offset) { _, reference in
                HStack {
                    Text(chordDisplayName(reference))
                    Spacer()
                    Button { playSingleChord(reference, tempered: false) } label: {
                        Image(systemName: "play")
                    }.accessibilityLabel(L10n.string(.appButtonJouerNonTempere, session.currentLanguage))
                    Button { playSingleChord(reference, tempered: true) } label: {
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

    private func playSingleNote(pitchClass: Int, tempered: Bool) {
        playPitches([60 + pitchClass], tempered: tempered, durationSeconds: 0.7)
    }

    private func playSingleChord(_ reference: ChordReference, tempered: Bool) {
        guard let chord = reference.resolve() else { return }
        let pitches = PitchSequencing.ascendingPitches(forPitchClasses: chord.pitchClasses.map(\.value), startingAbove: 47)
        playPitches(pitches, tempered: tempered, durationSeconds: 1.2)
    }

    private func playPitches(_ pitches: [Int], tempered: Bool, durationSeconds: Double) {
        guard let sourceID else { return }
        session.releaseAllKeys(track: sourceID)
        for pitch in pitches { session.pressKey(pitch: pitch, track: sourceID, applyTuning: tempered) }
        playbackGeneration += 1
        let generation = playbackGeneration
        Task {
            try? await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))
            if generation == playbackGeneration {
                for pitch in pitches { session.releaseKey(pitch: pitch, track: sourceID) }
            }
        }
    }

    private func playScale(tempered: Bool) {
        let pitches = PitchSequencing.ascendingPitches(forPitchClasses: scaleDegreesWithOctave, startingAbove: 47)
        playSequence(pitches.map { [$0] }, tempered: tempered, stepSeconds: 0.35)
    }

    private func playChordSequence(tempered: Bool) {
        let chordPitches = diatonicChordReferences.compactMap { $0.resolve() }.map {
            PitchSequencing.ascendingPitches(forPitchClasses: $0.pitchClasses.map(\.value), startingAbove: 47)
        }
        playSequence(chordPitches, tempered: tempered, stepSeconds: 0.9)
    }

    private func playSequence(_ items: [[Int]], tempered: Bool, stepSeconds: Double) {
        guard let sourceID else { return }
        session.releaseAllKeys(track: sourceID)
        playbackGeneration += 1
        let generation = playbackGeneration
        Task {
            for (index, pitches) in items.enumerated() {
                guard generation == playbackGeneration else { return }
                playingIndex = index
                for pitch in pitches { session.pressKey(pitch: pitch, track: sourceID, applyTuning: tempered) }
                try? await Task.sleep(nanoseconds: UInt64(stepSeconds * 0.85 * 1_000_000_000))
                guard generation == playbackGeneration else { return }
                for pitch in pitches { session.releaseKey(pitch: pitch, track: sourceID) }
                try? await Task.sleep(nanoseconds: UInt64(stepSeconds * 0.15 * 1_000_000_000))
            }
            if generation == playbackGeneration { playingIndex = nil }
        }
    }
}

#Preview {
    TuningLibraryView(session: ImprovSession(), isActive: true)
}
