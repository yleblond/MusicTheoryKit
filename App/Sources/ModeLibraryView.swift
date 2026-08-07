import SwiftUI
import AppCore
import JamShackUI
import MusicTheoryKit
import PieceModel
import Localization

/// "Modes" section of the Théorie tab — pick a tonic + mode/scale (`ScaleLibrary`), then see it
/// in a 2-column × 3-row `Grid` (narrow notation column on the left, wide keyboard column on the
/// right — see `ChordStaffView`'s `widthScale`): row 1 is the mode's own scale (+ Asc/Desc/
/// Asc-et-Desc, each button plays immediately) next to the mode's keyboard (with note-name
/// bullets and degree badges); row 2 is the mode's harmonized chords (+ a "play the sequence"
/// button) next to whichever chord was last tapped, on its own keyboard; row 3 is the chord
/// list (each playable on tap, labeled with its functional-harmony role — see
/// `FunctionalHarmonyTable`) next to a circle-of-fifths section reusing `CircleOfFifthsWheelView`
/// for an arbitrary picked tonic (see `ImprovSession.wheelState`). The instrument itself is
/// picked once, in `TheoryView`'s shared header, and threaded down via `auditionSoundID`. This
/// whole grid only shows on macOS/visionOS/iPad-width iOS; iPhone-width iOS keeps the original
/// push list→detail navigation instead — see `TheoryLibraryLayout`.
struct ModeLibraryView: View {
    let session: ImprovSession
    @Binding var auditionSoundID: String?

    @State private var screen: TheoryLibraryScreen = .list
    @State private var selectedTonic: Int = 0
    @State private var selectedScaleID: String = ScaleLibrary.all[0].id
    /// Which of `diatonicChordReferences` the right column's mini keyboard currently shows —
    /// defaults to the tonic chord (index 0), same "always populated" convention the other
    /// Library screens already follow.
    @State private var selectedChordIndex: Int = 0

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesTwoColumns: Bool { TheoryLibraryLayoutMode.usesTwoColumns(horizontalSizeClass: horizontalSizeClass) }

    private var mode: Mode {
        Mode(tonic: PitchClass(selectedTonic), scale: ScaleLibrary.byID(selectedScaleID) ?? ScaleLibrary.all[0])
    }

    var body: some View {
        TheoryLibraryLayout(screen: $screen, sidebarWidth: 320) {
            listContent
        } detailContent: { showBackButton, onBack in
            detailContent(showBackButton: showBackButton, onBack: onBack)
        }
    }

    // MARK: - List

    private struct FamilyGroup: Identifiable {
        let family: ScaleFamily
        let scales: [ScaleDefinition]
        var id: Int { family.id }
    }

    private var familyGroups: [FamilyGroup] {
        ScaleFamilies.all.keys.sorted().map { id in
            FamilyGroup(family: ScaleFamilies.family(id), scales: ScaleLibrary.scales(inFamily: id))
        }
    }

    private var listContent: some View {
        Form {
            Section {
                if usesTwoColumns {
                    Picker(L10n.string(.fieldTonique, session.currentLanguage), selection: $selectedTonic) {
                        ForEach(0..<12, id: \.self) { pitchClass in
                            Text(session.notationStyle.rootName(PitchClass(pitchClass), preferFlats: false)).tag(pitchClass)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Picker(L10n.string(.fieldTonique, session.currentLanguage), selection: $selectedTonic) {
                        ForEach(0..<12, id: \.self) { pitchClass in
                            Text(session.notationStyle.rootName(PitchClass(pitchClass), preferFlats: false)).tag(pitchClass)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text(L10n.string(.appHeadingBibliothequeModes, session.currentLanguage))
            }
            ForEach(familyGroups) { group in
                Section {
                    ForEach(group.scales, id: \.id) { scale in
                        Button {
                            selectedScaleID = scale.id
                            selectedChordIndex = 0
                            screen = .detail
                        } label: {
                            HStack {
                                Text("\(scale.popularName) (\(scale.systematicName))")
                                    .foregroundStyle(scale.id == selectedScaleID ? Color.accentColor : .primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(group.family.name)
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

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

                Text(mode.displayName).font(.largeTitle).bold()

                // A true 2-column × 3-row grid (not two independently-stacked VStacks — those
                // drift out of horizontal alignment as soon as either column's own content
                // varies in height) — `Grid` sizes each row to its tallest cell and each column
                // to its widest, so e.g. row 2's chords staff and its neighboring chord keyboard
                // always start at the same y regardless of either one's own natural height.
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 12) {
                    // Row 1: the mode's own scale (+ Asc/Desc/Asc-et-Desc right under it) next
                    // to the mode's keyboard.
                    GridRow {
                        VStack(alignment: .leading, spacing: 8) {
                            ChordStaffView(events: staffEvents, widthScale: 0.7, keySignature: modeKeySignature)
                            scalePlaybackControls
                        }
                        // No custom `height:` — `PitchKeyboardView`'s own default (144) is
                        // already tuned to look natural; forcing it to match the staff's much
                        // taller height (or an arbitrarily smaller one) either stretched or
                        // squished it, per feedback.
                        PitchKeyboardView(
                            modeTones: mode.pitchClasses.map(\.value),
                            showModeColoring: true,
                            keyLabels: PitchKeyboardView.noteNameKeyLabels(forPitches: modeTonePitchesInKeyboardRange, style: session.notationStyle)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // Row 2: the mode's harmonized chords (+ a "play the sequence" button)
                    // next to whichever chord was last tapped, on its own keyboard.
                    GridRow {
                        VStack(alignment: .leading, spacing: 8) {
                            ChordStaffView(events: chordsStaffEvents, widthScale: 0.7, keySignature: modeKeySignature)
                            playChordSequenceButton
                        }
                        selectedChordKeyboard
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // Row 3: the chord list (tap one to hear it + update row 2's keyboard)
                    // next to the circle of fifths.
                    GridRow(alignment: .top) {
                        diatonicChordsSection
                        circleOfFifthsSection
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
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
        ChordStaffView.ascendingSequence(pitchClasses: scaleDegreesWithOctave, chordRoot: mode.tonic.value, chordTones: mode.pitchClasses.map(\.value))
    }

    private var modeTonePitchesInKeyboardRange: [Int] {
        let tones = Set(mode.pitchClasses.map(\.value))
        return (48...72).filter { tones.contains((($0 % 12) + 12) % 12) }
    }

    /// Plays `direction`'s sequence immediately — no separate "démarrer" step, per explicit
    /// request (Asc/Desc/Asc-et-Desc are buttons, not a picker + a start button).
    private func play(direction: SequencePlayDirection) {
        guard let auditionSoundID, let sound = session.favoriteSounds.first(where: { $0.id == auditionSoundID }) else { return }
        try? session.loadTheoryLibraryAuditionSample(sound)
        let ascending = PitchSequencing.ascendingPitches(forPitchClasses: scaleDegreesWithOctave, startingAbove: 47)
        let sequence: [Int]
        switch direction {
        case .ascending: sequence = ascending
        case .descending: sequence = ascending.reversed()
        case .both: sequence = ascending + ascending.reversed().dropFirst()
        }
        let stepDuration = 0.35
        let notes = sequence.enumerated().map { index, pitch in
            ImprovSession.TheoryAuditionNote(pitches: [pitch], startSeconds: Double(index) * stepDuration, durationSeconds: stepDuration * 0.9)
        }
        session.playTheoryLibraryAudition(notes)
    }

    private var scalePlaybackControls: some View {
        HStack(spacing: 8) {
            Button(L10n.string(.appButtonAscendant, session.currentLanguage)) { play(direction: .ascending) }
            Button(L10n.string(.appButtonDescendant, session.currentLanguage)) { play(direction: .descending) }
            Button(L10n.string(.appButtonAscEtDescendant, session.currentLanguage)) { play(direction: .both) }
            if session.isAuditioningTheoryLibrary {
                Button(L10n.string(.appButtonArreter, session.currentLanguage), role: .destructive) {
                    session.stopTheoryLibraryAudition()
                }
            }
            Spacer()
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Diatonic chords

    private var diatonicChordReferences: [ChordReference] { ChordProgressionResolver.diatonicChordReferences(in: mode) }

    @ViewBuilder
    private var diatonicChordsSection: some View {
        if !diatonicChordReferences.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(.appHeadingAccordsDuMode, session.currentLanguage)).font(.headline)
                ForEach(Array(diatonicChordReferences.enumerated()), id: \.offset) { index, reference in
                    Button {
                        selectedChordIndex = index
                        playSingleChord(reference)
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
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// All of the mode's diatonic chords, one stacked-chord column each (root position) — the
    /// harmonized-scale staff shown under the chord list.
    private var chordsStaffEvents: [StaffEvent] {
        diatonicChordReferences.compactMap { reference in
            guard let chord = reference.resolve() else { return nil }
            return ChordStaffView.chordEvent(root: chord.root.value, tones: chord.pitchClasses.map(\.value))
        }
    }

    private var selectedChordReference: ChordReference? {
        diatonicChordReferences.indices.contains(selectedChordIndex) ? diatonicChordReferences[selectedChordIndex] : nil
    }

    @ViewBuilder
    private var selectedChordKeyboard: some View {
        if let chord = selectedChordReference?.resolve() {
            let tones = Set(chord.pitchClasses.map(\.value))
            let keyboardPitches = (48...72).filter { tones.contains((($0 % 12) + 12) % 12) }
            PitchKeyboardView(
                chordRoot: chord.root.value,
                chordTones: chord.pitchClasses.map(\.value),
                alwaysShowChord: true,
                keyLabels: PitchKeyboardView.noteNameKeyLabels(forPitches: keyboardPitches, style: session.notationStyle)
            )
        }
    }

    /// Plays every diatonic chord back to back (root position, same fixed-per-chord-duration
    /// simplification `ProgressionLibraryView.playProgression()` already uses).
    private func playAllChords() {
        guard let auditionSoundID, let sound = session.favoriteSounds.first(where: { $0.id == auditionSoundID }) else { return }
        try? session.loadTheoryLibraryAuditionSample(sound)
        let stepDuration = 1.0
        var notes: [ImprovSession.TheoryAuditionNote] = []
        for (index, reference) in diatonicChordReferences.enumerated() {
            guard let chord = reference.resolve() else { continue }
            let pitches = PitchSequencing.ascendingPitches(forPitchClasses: chord.pitchClasses.map(\.value), startingAbove: 47)
            notes.append(ImprovSession.TheoryAuditionNote(pitches: pitches, startSeconds: Double(index) * stepDuration, durationSeconds: stepDuration * 0.9))
        }
        session.playTheoryLibraryAudition(notes)
    }

    @ViewBuilder
    private var playChordSequenceButton: some View {
        if !diatonicChordReferences.isEmpty {
            Button(L10n.string(.appButtonJouerLaSuiteDAccords, session.currentLanguage), action: playAllChords)
                .buttonStyle(.bordered)
        }
    }

    private func chordDisplayName(_ reference: ChordReference) -> String {
        guard let chord = reference.resolve() else { return "?" }
        return session.notationStyle.displayName(for: chord)
    }

    private func playSingleChord(_ reference: ChordReference) {
        guard let auditionSoundID, let sound = session.favoriteSounds.first(where: { $0.id == auditionSoundID }),
              let chord = reference.resolve() else { return }
        try? session.loadTheoryLibraryAuditionSample(sound)
        let pitches = PitchSequencing.ascendingPitches(forPitchClasses: chord.pitchClasses.map(\.value), startingAbove: 47)
        session.playTheoryLibraryAudition([ImprovSession.TheoryAuditionNote(pitches: pitches, startSeconds: 0, durationSeconds: 1.5)])
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
                    wheel: ImprovSession.wheelState(forTonic: parentTonic, activeTonic: mode.tonic, activeModeName: mode.scale.systematicName),
                    palette: session.activeColorPalette.colors,
                    paletteTextColors: session.activeColorPalette.textColors
                )
                .frame(maxWidth: 420)
            }
        }
    }
}

#Preview {
    ModeLibraryView(session: ImprovSession(), auditionSoundID: .constant(nil))
}
