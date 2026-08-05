import SwiftUI
import AppCore
import JamShackUI
import MusicTheoryKit
import PieceModel
import Localization

/// "Progressions" tab — pick a tonic + mode (restricted to the 7 classic major-family modes,
/// where `ChordProgressionResolver`'s rich diatonic resolution and `ProgressionNameAliases`'s
/// common-name matching are both meaningful), then browse `session.chordProgressionTemplates`
/// (built-ins + anything added via `chordprogressions.json`): each row previews its resolved
/// chord symbols; the detail screen shows the full sequence on the staff, lets you scrub/play
/// any single chord on the keyboard, and plays the whole progression back to back. Same
/// list/detail idiom as `ChordLibraryView`/`ModeLibraryView`.
struct ProgressionLibraryView: View {
    let session: ImprovSession

    private enum Screen { case list, detail }

    @State private var screen: Screen = .list
    @State private var selectedTonic: Int = 0
    @State private var selectedScaleID: String = "ionian"
    @State private var selectedTemplateName: String?
    @State private var currentChordIndex: Int = 0
    @State private var auditionSoundID: String?

    private var mode: Mode {
        Mode(tonic: PitchClass(selectedTonic), scale: ScaleLibrary.byID(selectedScaleID) ?? ScaleLibrary.byID("ionian")!)
    }

    private var selectedTemplate: ChordProgressionTemplate? {
        guard let selectedTemplateName else { return nil }
        return session.chordProgressionTemplates.first { $0.name == selectedTemplateName }
    }

    private var resolvedReferences: [ChordReference] {
        guard let selectedTemplate else { return [] }
        return ChordProgressionResolver.resolveRich(selectedTemplate, in: mode)
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

    private var listScreen: some View {
        Form {
            Section {
                Picker(L10n.string(.fieldTonique, session.currentLanguage), selection: $selectedTonic) {
                    ForEach(0..<12, id: \.self) { pitchClass in
                        Text(session.notationStyle.rootName(PitchClass(pitchClass), preferFlats: false)).tag(pitchClass)
                    }
                }
                .pickerStyle(.segmented)
                Picker(L10n.string(.fieldGamme, session.currentLanguage), selection: $selectedScaleID) {
                    ForEach(ScaleLibrary.scales(inFamily: 1), id: \.id) { scale in
                        Text(scale.popularName).tag(scale.id)
                    }
                }
            } header: {
                Text(L10n.string(.appHeadingBibliothequeProgressions, session.currentLanguage))
            }
            Section {
                ForEach(session.chordProgressionTemplates, id: \.name) { template in
                    Button {
                        selectedTemplateName = template.name
                        currentChordIndex = 0
                        screen = .detail
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                            Text(chordSymbolsPreview(template)).font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(L10n.string(.appFieldProgressionChoisie, session.currentLanguage))
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    private func chordSymbolsPreview(_ template: ChordProgressionTemplate) -> String {
        ChordProgressionResolver.chordSymbols(for: template, in: mode, style: session.notationStyle).joined(separator: " - ")
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

                Text(selectedTemplate?.name ?? "").font(.largeTitle).bold()
                commonNamesSection

                ChordStaffView(events: progressionStaffEvents)

                PitchKeyboardView(
                    chordRoot: currentChord?.root.value,
                    chordTones: currentChord?.pitchClasses.map(\.value) ?? [],
                    alwaysShowChord: true,
                    keyLabels: PitchKeyboardView.noteNameKeyLabels(forPitches: currentChordKeyboardPitches, style: session.notationStyle)
                )

                chordListSection

                SequenceTransportView(
                    favoriteSounds: session.favoriteSounds,
                    selectedSoundID: $auditionSoundID,
                    isPlaying: session.isAuditioningTheoryLibrary,
                    language: session.currentLanguage,
                    onPlay: playProgression,
                    onStop: { session.stopTheoryLibraryAudition() }
                )
            }
            .padding()
        }
    }

    /// Every name `ProgressionNameAliases.matchingNames(for:)` finds for the selected template's
    /// shape, EXCLUDING its own name (already shown as this screen's title) — so this section is
    /// specifically "what else is this progression also known as," not a restatement.
    private var alternateNames: [String] {
        ProgressionNameAliases.matchingNames(for: selectedTemplate?.degrees ?? []).filter { $0 != selectedTemplate?.name }
    }

    @ViewBuilder
    private var commonNamesSection: some View {
        if !alternateNames.isEmpty {
            Text("\(L10n.string(.appLabelNomUsuel, session.currentLanguage)) : \(alternateNames.joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text(L10n.string(.appLabelAucunNomUsuel, session.currentLanguage))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var progressionStaffEvents: [StaffEvent] {
        resolvedReferences.compactMap { reference in
            guard let chord = reference.resolve() else { return nil }
            return ChordStaffView.chordEvent(root: chord.root.value, tones: chord.pitchClasses.map(\.value))
        }
    }

    private var currentReference: ChordReference? {
        resolvedReferences.indices.contains(currentChordIndex) ? resolvedReferences[currentChordIndex] : nil
    }

    private var currentChord: Chord? { currentReference?.resolve() }

    private var currentChordKeyboardPitches: [Int] {
        guard let currentChord else { return [] }
        let tones = Set(currentChord.pitchClasses.map(\.value))
        return (48...72).filter { tones.contains((($0 % 12) + 12) % 12) }
    }

    @ViewBuilder
    private var chordListSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(resolvedReferences.enumerated()), id: \.offset) { index, reference in
                Button {
                    currentChordIndex = index
                    playSingleChord(reference)
                } label: {
                    HStack {
                        Text("\(index + 1).").foregroundStyle(.secondary)
                        Text(chordDisplayName(reference))
                        Spacer()
                        if index == currentChordIndex {
                            Image(systemName: "arrowtriangle.right.fill").foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
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

    private func playProgression() {
        guard let auditionSoundID, let sound = session.favoriteSounds.first(where: { $0.id == auditionSoundID }) else { return }
        try? session.loadTheoryLibraryAuditionSample(sound)
        let stepDuration = 1.0
        var notes: [ImprovSession.TheoryAuditionNote] = []
        for (index, reference) in resolvedReferences.enumerated() {
            guard let chord = reference.resolve() else { continue }
            let pitches = PitchSequencing.ascendingPitches(forPitchClasses: chord.pitchClasses.map(\.value), startingAbove: 47)
            notes.append(ImprovSession.TheoryAuditionNote(pitches: pitches, startSeconds: Double(index) * stepDuration, durationSeconds: stepDuration * 0.9))
        }
        session.playTheoryLibraryAudition(notes)
    }
}

#Preview {
    ProgressionLibraryView(session: ImprovSession())
}
