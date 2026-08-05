import SwiftUI
import AppCore
import JamShackUI
import MusicTheoryKit
import PieceModel
import Localization

/// "Modes" tab — pick a tonic + mode/scale (`ScaleLibrary`), then see it highlighted on a
/// keyboard with note-name bullets, its notes in sequence on the grand staff, Asc/Desc/Asc-et-
/// Desc playback, its diatonic chords (each playable, labeled with its functional-harmony role
/// where known — see `FunctionalHarmonyTable`), and a circle-of-fifths section reusing
/// `CircleOfFifthsWheelView` for an arbitrary picked tonic (see `ImprovSession.wheelState`).
/// Same list/detail idiom as `ChordLibraryView`/`SoundLibraryView`.
struct ModeLibraryView: View {
    let session: ImprovSession

    private enum Screen { case list, detail }

    @State private var screen: Screen = .list
    @State private var selectedTonic: Int = 0
    @State private var selectedScaleID: String = ScaleLibrary.all[0].id
    @State private var direction: SequencePlayDirection = .ascending
    @State private var auditionSoundID: String?

    private var mode: Mode {
        Mode(tonic: PitchClass(selectedTonic), scale: ScaleLibrary.byID(selectedScaleID) ?? ScaleLibrary.all[0])
    }

    var body: some View {
        Group {
            switch screen {
            case .list: listScreen
            case .detail: detailScreen
            }
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

    private var listScreen: some View {
        Form {
            Section {
                Picker(L10n.string(.fieldTonique, session.currentLanguage), selection: $selectedTonic) {
                    ForEach(0..<12, id: \.self) { pitchClass in
                        Text(session.notationStyle.rootName(PitchClass(pitchClass), preferFlats: false)).tag(pitchClass)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(L10n.string(.appHeadingBibliothequeModes, session.currentLanguage))
            }
            ForEach(familyGroups) { group in
                Section {
                    ForEach(group.scales, id: \.id) { scale in
                        Button {
                            selectedScaleID = scale.id
                            screen = .detail
                        } label: {
                            HStack {
                                Text("\(scale.popularName) (\(scale.systematicName))")
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

    private var detailScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button {
                        screen = .list
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    Spacer()
                }

                Text(mode.displayName).font(.largeTitle).bold()

                PitchKeyboardView(
                    modeTones: mode.pitchClasses.map(\.value),
                    showModeColoring: true,
                    keyLabels: PitchKeyboardView.noteNameKeyLabels(forPitches: modeTonePitchesInKeyboardRange, style: session.notationStyle)
                )

                ChordStaffView(events: staffEvents)

                SequenceTransportView(
                    favoriteSounds: session.favoriteSounds,
                    selectedSoundID: $auditionSoundID,
                    direction: $direction,
                    isPlaying: session.isAuditioningTheoryLibrary,
                    language: session.currentLanguage,
                    onPlay: play,
                    onStop: { session.stopTheoryLibraryAudition() }
                )

                diatonicChordsSection
                circleOfFifthsSection
            }
            .padding()
        }
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

    private func play() {
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

    // MARK: - Diatonic chords

    private var diatonicChordReferences: [ChordReference] { ChordProgressionResolver.diatonicChordReferences(in: mode) }

    @ViewBuilder
    private var diatonicChordsSection: some View {
        if !diatonicChordReferences.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(.appHeadingAccordsDuMode, session.currentLanguage)).font(.headline)
                ForEach(Array(diatonicChordReferences.enumerated()), id: \.offset) { index, reference in
                    Button {
                        playSingleChord(reference)
                    } label: {
                        HStack {
                            Image(systemName: "play.circle")
                            Text(chordDisplayName(reference))
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
    ModeLibraryView(session: ImprovSession())
}
