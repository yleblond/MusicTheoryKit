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
        TheoryLibraryLayout(screen: $screen, sidebarWidth: 320) {
            listContent
        } detailContent: { showBackButton, onBack in
            detailContent(showBackButton: showBackButton, onBack: onBack)
        }
    }

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

                ChordStaffView(events: [staffEvent])

                PitchKeyboardView(
                    chordRoot: chord.root.value,
                    chordTones: chord.pitchClasses.map(\.value),
                    alwaysShowChord: true,
                    keyLabels: PitchKeyboardView.noteNameKeyLabels(forPitches: keyboardTonePitches, style: session.notationStyle)
                )

                if maxInversion > 0 {
                    Stepper(value: $inversion, in: 0...maxInversion) {
                        Text("\(L10n.string(.appFieldInversion, session.currentLanguage)) : \(inversion)")
                    }
                }

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

    /// One close-position voicing of the current inversion, anchored just above middle C —
    /// each successive tone placed in the next octave up so the shape actually reflects which
    /// tone is the bass, unlike `ChordStaffView.chordEvent(root:tones:)` (root-position only).
    private var staffEvent: StaffEvent {
        ChordStaffView.ascendingVoicing(
            pitchClasses: chord.voicing(inversion: inversion).orderedPitchClasses.map(\.value),
            chordRoot: chord.root.value, chordTones: chord.pitchClasses.map(\.value)
        )
    }

    private var keyboardTonePitches: [Int] {
        let tones = Set(chord.pitchClasses.map(\.value))
        return (48...72).filter { tones.contains((($0 % 12) + 12) % 12) }
    }

    private func play() {
        guard let sound = session.theoryAuditionSound() else { return }
        try? session.loadTheoryLibraryAuditionSample(sound)
        let pitches = PitchSequencing.ascendingPitches(
            forPitchClasses: chord.voicing(inversion: inversion).orderedPitchClasses.map(\.value), startingAbove: 47
        )
        session.playTheoryLibraryAudition([ImprovSession.TheoryAuditionNote(pitches: pitches, startSeconds: 0, durationSeconds: 2)])
    }
}

#Preview {
    ChordLibraryView(session: ImprovSession())
}
