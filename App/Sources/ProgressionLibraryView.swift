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
/// chord symbols; the detail side shows the chord list, then the keyboard + guitar tablature for
/// whichever chord is current (tap a row to scrub, or press play to advance automatically — the
/// staff highlights the currently-sounding column too). The instrument itself is picked once, in
/// Settings > Théorie, and read via `ImprovSession.theoryAuditionSound()`. Two side-by-side
/// columns on macOS/visionOS/iPad-width iOS, push list→detail navigation on iPhone-width iOS —
/// see `TheoryLibraryLayout`.
struct ProgressionLibraryView: View {
    let session: ImprovSession

    @State private var screen: TheoryLibraryScreen = .list
    @State private var selectedTonic: Int = 0
    @State private var selectedScaleID: String = "ionian"
    @State private var selectedTemplateName: String?
    @State private var currentChordIndex: Int = 0
    /// Bumped on every `playProgression()`/`stopProgression()` call — guards the scheduled
    /// `currentChordIndex` advances below so a Stop (or a fresh Play before the previous
    /// sequence finished) invalidates any still-pending ones, same generation-counter idiom
    /// `GuideAuditionPlayer`/`ImprovSession`'s own audition state already uses.
    @State private var playbackGeneration = 0

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesTwoColumns: Bool { TheoryLibraryLayoutMode.usesTwoColumns(horizontalSizeClass: horizontalSizeClass) }

    private var mode: Mode {
        Mode(tonic: PitchClass(selectedTonic), scale: ScaleLibrary.byID(selectedScaleID) ?? ScaleLibrary.byID("ionian")!)
    }

    /// `session.chordProgressionTemplates` de-duplicated by name, first occurrence wins,
    /// order preserved — the underlying store can (and, on at least one real device, does)
    /// end up with more than one record sharing the same name (e.g. after a CloudKit/local
    /// store reconciliation re-seeds built-ins that were already there); this is the one
    /// screen that lists every template at once, so it's the one place that needs to guard
    /// against showing the same progression twice rather than relying on the store being
    /// perfectly deduplicated upstream.
    private var uniqueTemplates: [ChordProgressionTemplate] {
        var seen = Set<String>()
        return session.chordProgressionTemplates.filter { seen.insert($0.name).inserted }
    }

    private var selectedTemplate: ChordProgressionTemplate? {
        guard let selectedTemplateName else { return nil }
        return uniqueTemplates.first { $0.name == selectedTemplateName }
    }

    private var resolvedReferences: [ChordReference] {
        guard let selectedTemplate else { return [] }
        return ChordProgressionResolver.resolveRich(selectedTemplate, in: mode)
    }

    var body: some View {
        TheoryLibraryLayout(screen: $screen, sidebarWidth: 360) {
            listContent
        } detailContent: { showBackButton, onBack in
            detailContent(showBackButton: showBackButton, onBack: onBack)
        }
        .onAppear {
            // Keeps the right/detail column non-empty in two-column mode even before any tap —
            // Accords/Modes already default to a real selection, this matches that.
            if selectedTemplateName == nil {
                selectedTemplateName = uniqueTemplates.first?.name
            }
        }
    }

    // MARK: - List

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
                Picker(L10n.string(.fieldGamme, session.currentLanguage), selection: $selectedScaleID) {
                    ForEach(ScaleLibrary.scales(inFamily: 1), id: \.id) { scale in
                        Text(scale.popularName).tag(scale.id)
                    }
                }
            } header: {
                Text(L10n.string(.appHeadingBibliothequeProgressions, session.currentLanguage))
            }
            Section {
                ForEach(uniqueTemplates, id: \.name) { template in
                    Button {
                        selectedTemplateName = template.name
                        currentChordIndex = 0
                        screen = .detail
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .foregroundStyle(template.name == selectedTemplateName ? Color.accentColor : .primary)
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

                Text(selectedTemplate?.name ?? "").font(.largeTitle).bold()
                commonNamesSection

                ChordStaffView(events: progressionStaffEvents, highlightedIndex: currentChordIndex)

                chordListSection

                keyboardAndTablature

                SequenceTransportView(
                    isPlaying: session.isAuditioningTheoryLibrary,
                    language: session.currentLanguage,
                    onPlay: playProgression,
                    onStop: stopProgression
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

    /// A row of compact tappable chips (not a vertical list — a progression's chords read
    /// naturally left-to-right, and this is far more compact than one row per chord) — tap to
    /// scrub/audition, or watch it highlight on its own during `playProgression()`.
    @ViewBuilder
    private var chordListSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(resolvedReferences.enumerated()), id: \.offset) { index, reference in
                    Button {
                        currentChordIndex = index
                        playSingleChord(reference)
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                            Text(chordDisplayName(reference)).fontWeight(index == currentChordIndex ? .bold : .regular)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(index == currentChordIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Keyboard + guitar tablature for whichever chord is current (root position — a
    /// progression has no inversion concept of its own, unlike the Chord Library).
    @ViewBuilder
    private var keyboardAndTablature: some View {
        HStack(alignment: .top, spacing: 16) {
            PitchKeyboardView(
                chordRoot: currentChord?.root.value,
                chordTones: currentChord?.pitchClasses.map(\.value) ?? [],
                alwaysShowChord: true,
                keyLabels: PitchKeyboardView.noteNameKeyLabels(forPitches: currentChordKeyboardPitches, style: session.notationStyle)
            )
            if let currentReference {
                GuitarChordDiagramView(root: currentReference.root, chordTemplateID: currentReference.chordTemplateID, language: session.currentLanguage)
            }
        }
    }

    private func chordDisplayName(_ reference: ChordReference) -> String {
        guard let chord = reference.resolve() else { return "?" }
        return session.notationStyle.displayName(for: chord)
    }

    private func playSingleChord(_ reference: ChordReference) {
        guard let sound = session.theoryAuditionSound(), let chord = reference.resolve() else { return }
        try? session.loadTheoryLibraryAuditionSample(sound)
        playbackGeneration += 1
        let pitches = PitchSequencing.ascendingPitches(forPitchClasses: chord.pitchClasses.map(\.value), startingAbove: 47)
        session.playTheoryLibraryAudition([ImprovSession.TheoryAuditionNote(pitches: pitches, startSeconds: 0, durationSeconds: 1.5)])
    }

    /// Plays the whole progression back to back AND advances `currentChordIndex` in step (so
    /// the keyboard and the staff's highlighted column follow along) — scheduled separately
    /// from the audio itself (`ImprovSession.playTheoryLibraryAudition` has no per-step
    /// callback), guarded by `playbackGeneration` so a Stop (or restarting playback) cancels
    /// any still-pending advances instead of them firing late over whatever comes next.
    private func playProgression() {
        guard let sound = session.theoryAuditionSound() else { return }
        try? session.loadTheoryLibraryAuditionSample(sound)
        playbackGeneration += 1
        let generation = playbackGeneration
        let stepDuration = 1.0
        var notes: [ImprovSession.TheoryAuditionNote] = []
        for (index, reference) in resolvedReferences.enumerated() {
            guard let chord = reference.resolve() else { continue }
            let pitches = PitchSequencing.ascendingPitches(forPitchClasses: chord.pitchClasses.map(\.value), startingAbove: 47)
            notes.append(ImprovSession.TheoryAuditionNote(pitches: pitches, startSeconds: Double(index) * stepDuration, durationSeconds: stepDuration * 0.9))
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * stepDuration) {
                guard playbackGeneration == generation else { return }
                currentChordIndex = index
            }
        }
        session.playTheoryLibraryAudition(notes)
    }

    private func stopProgression() {
        playbackGeneration += 1
        session.stopTheoryLibraryAudition()
    }
}

#Preview {
    ProgressionLibraryView(session: ImprovSession())
}
