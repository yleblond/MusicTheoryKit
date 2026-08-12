import SwiftUI
import AppCore
import JamShackUI
import MusicTheoryKit
import PieceModel
import RecognitionEngine
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
    var isDetachedWindow: Bool = false
    /// Whether THIS instance is the one currently on screen — see `ModeLibraryView.isActive`'s
    /// own doc comment for why this can't just be `.onAppear`/`.onDisappear`. Feeds
    /// `.registerMainKeyboardMode` in `body` below.
    var isActive: Bool = true

    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    @State private var screen: TheoryLibraryScreen = .list
    @State private var selectedTonic: Int = 0
    @State private var selectedScaleID: String = "ionian"
    @State private var selectedTemplateName: String?
    @State private var currentChordIndex: Int = 0
    /// The width of the row holding both detail columns (measured via `.onGeometryChange`, not a
    /// fixed constant) — see `staffAvailableWidth`, which derives the staff's own share of it.
    /// Starts at 0 until the first layout pass reports the real value, same one-frame settling
    /// any geometry-fed layout has.
    @State private var columnsRowWidth: CGFloat = 0
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
        VStack(spacing: 0) {
            #if os(macOS) || os(visionOS)
            HStack {
                Spacer()
                detachButton
            }
            .padding(.horizontal)
            .padding(.top, 6)
            #endif
            TheoryLibraryLayout(screen: $screen, sidebarWidth: 360) {
                listContent
            } detailContent: { showBackButton, onBack in
                detailContent(showBackButton: showBackButton, onBack: onBack)
            }
            .onAppear {
                // Keeps the right/detail column non-empty in two-column mode even before any tap
                // — Accords/Modes already default to a real selection, this matches that.
                if selectedTemplateName == nil {
                    selectedTemplateName = uniqueTemplates.first?.name
                }
            }
        }
        // Colors the persistent main-keyboard bar (`ContentView`) by this screen's own picked
        // mode while it's the active tab, per explicit request — same mechanism `ModeLibraryView`
        // uses for its own "Modes"/"Exploration" tabs.
        .registerMainKeyboardMode(id: "theorie.progressions", isActive: isActive, mode: mode)
        // Feeds Intonations' fixed-temperament tuning its tonic — see `ModeLibraryView`'s own
        // identical pair of `.onChange`s for why leaving this screen clears it back to `nil`.
        .onChange(of: isActive, initial: true) { _, active in
            session.setContextualTonic(active ? mode.tonic : nil)
        }
        .onChange(of: mode) { _, newMode in
            guard isActive else { return }
            session.setContextualTonic(newMode.tonic)
        }
        .onChange(of: session.theoryLiveInputRecognizedChord) { _, newChord in
            reactToLiveChordMatch(newChord)
        }
    }

    #if os(macOS) || os(visionOS)
    @ViewBuilder
    private var detachButton: some View {
        if isDetachedWindow {
            Button {
                dismissWindow(id: AuxiliaryWindowID.theorieProgressions.rawValue)
            } label: {
                Label(L10n.string(.appButtonReintegrer, session.currentLanguage), systemImage: "arrow.down.right.and.arrow.up.left")
            }
        } else {
            Button {
                openWindow(id: AuxiliaryWindowID.theorieProgressions.rawValue)
            } label: {
                Image(systemName: "rectangle.on.rectangle")
            }
        }
    }
    #endif

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

                // Per explicit request: a wide column (staff + chord sequence) next to a
                // narrower one (tablature + keyboard) — used to be one column, top to bottom.
                Group {
                    if usesTwoColumns {
                        HStack(alignment: .top, spacing: 16) {
                            staffAndSequenceColumn
                            tablatureAndKeyboardColumn
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            staffAndSequenceColumn
                            tablatureAndKeyboardColumn
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { columnsRowWidth = $0 }

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

    /// One ascending, root-position voicing (a progression chord has no inversion concept of its
    /// own — see `keyboardAndTablature`'s former doc comment) — feeds `referenceChordPitches` so
    /// the mini keyboard shows each tone exactly once instead of at every octave in range, per
    /// explicit request.
    private var currentChordVoicingPitches: [Int] {
        guard let currentChord else { return [] }
        return PitchSequencing.ascendingPitches(forPitchClasses: currentChord.pitchClasses.map(\.value), startingAbove: 47)
    }

    /// Whichever live track is the app's current "source principale" — read directly (not cached
    /// in `@State`; `session.tracks` already triggers a SwiftUI refresh on change), same
    /// convention `ChordLibraryView.liveHeldPitches` already uses, so this screen's own keyboard
    /// overlays what's actually being played too.
    private var liveHeldPitches: Set<Int> {
        guard let sourceID = session.theoryLiveInputSourceID else { return [] }
        return session.tracks.first { $0.id == sourceID }?.heldPitches ?? []
    }

    /// Reacts to whatever chord is recognized live on the "source principale" track exactly as if
    /// it had been picked directly — only matches within the CURRENTLY selected progression's own
    /// resolved chords, never switching `selectedTemplateName`/tonic/scale, per explicit request
    /// (the progression being viewed stays a manual choice; only which step within it is current
    /// reacts live).
    private func reactToLiveChordMatch(_ chord: RecognizedChord?) {
        guard let chord else { return }
        guard let index = ImprovSession.matchingChordIndex(chord, in: resolvedReferences, reference: { $0 }) else { return }
        currentChordIndex = index
    }

    /// -30% off `ChordStaffView`'s own default scale, per explicit request.
    private static let progressionStaffScale: CGFloat = 0.7
    /// Off `PitchKeyboardView`'s own default height (144) — was -50% (72pt); bumped back up a
    /// bit per explicit follow-up request ("agrandir un peu le mini clavier"). Still narrow,
    /// since it only ever shows one voicing (3-5 keys) instead of the same tones repeated across
    /// 2 octaves.
    private static let progressionKeyboardSize = CGSize(width: 320, height: 92)

    /// Compact tappable chips (not a vertical list — a progression's chords read naturally
    /// left-to-right, and this is far more compact than one row per chord) — tap to scrub/
    /// audition, or watch it highlight on its own during `playProgression()`. Wraps onto further
    /// lines via `FlowLayout` rather than scrolling horizontally once there are many chords, per
    /// explicit request — same reasoning as `progressionStaffRows` above.
    @ViewBuilder
    private var chordListSection: some View {
        FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
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

    /// Column 1 — the progression's own staff (shrunk -30%, per explicit request), wrapped onto
    /// several lines once a row genuinely runs out of room (a single `ChordStaffView` never
    /// wraps on its own — it's one wide `Canvas`, so a long progression needs chunking into
    /// several stacked instances instead) — sized to `staffAvailableWidth`, NOT a fixed chord
    /// count, since the staff's own columns are much narrower than the chord-name chips below
    /// it (`chordListSection`, which already wraps need-based via `FlowLayout`) and so fit far
    /// more chords per line before actually needing to wrap, per explicit request. Directly
    /// above the chord-sequence chips. Each chord column is tappable, same "scrub/audition"
    /// behavior as the chip row below it.
    private var staffAndSequenceColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(progressionStaffRows(forWidth: staffAvailableWidth).enumerated()), id: \.offset) { _, row in
                    ChordStaffView(
                        events: row.map(\.event), heightScale: Self.progressionStaffScale, widthScale: Self.progressionStaffScale,
                        highlightedIndex: row.firstIndex(where: { $0.offset == currentChordIndex }),
                        onColumnTap: { localIndex in
                            guard row.indices.contains(localIndex) else { return }
                            let globalIndex = row[localIndex].offset
                            currentChordIndex = globalIndex
                            playSingleChord(resolvedReferences[globalIndex])
                        }
                    )
                }
            }
            chordListSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The staff's own share of `columnsRowWidth` — the full row's width when stacked (single
    /// column, no sibling), or that minus `tablatureAndKeyboardColumn`'s known fixed width (and
    /// the `HStack`'s own spacing) when side by side, since `columnsRowWidth` measures the WHOLE
    /// row, not this column alone — measuring the row rather than `staffAndSequenceColumn`
    /// itself sidesteps a chicken-and-egg problem: that column's own resolved width depends on
    /// how the HStack distributes space to its `.frame(maxWidth: .infinity)` flexible child,
    /// whereas the row's width is fixed by its (non-flexible) parent, known before any of that
    /// negotiation happens.
    private var staffAvailableWidth: CGFloat {
        guard usesTwoColumns else { return columnsRowWidth }
        return max(0, columnsRowWidth - Self.progressionKeyboardSize.width - 16)
    }

    /// `progressionStaffEvents`, chunked into as many columns as `ChordStaffView` itself reports
    /// fit `width` (see `ChordStaffView.maxColumnCount(forWidth:widthScale:keySignature:)`),
    /// each entry keeping its ORIGINAL index (`offset`) into the full progression — needed to
    /// translate a given row's own local `onColumnTap`/`highlightedIndex` back to (and from)
    /// `currentChordIndex`, which always refers to the whole progression, not any one row.
    private func progressionStaffRows(forWidth width: CGFloat) -> [[(offset: Int, event: StaffEvent)]] {
        let indexed = progressionStaffEvents.enumerated().map { (offset: $0.offset, event: $0.element) }
        let perRow = ChordStaffView.maxColumnCount(forWidth: width, widthScale: Self.progressionStaffScale)
        return stride(from: 0, to: indexed.count, by: perRow).map {
            Array(indexed[$0..<min($0 + perRow, indexed.count)])
        }
    }

    /// Column 2 — the guitar tablature for whichever chord is current, directly above its own
    /// keyboard (root position — a progression has no inversion concept of its own, unlike the
    /// Chord Library). The tablature is deliberately half the keyboard's own width, per explicit
    /// request (anticipating a future 2-shape-wide tablature display fitting the same column).
    @ViewBuilder
    private var tablatureAndKeyboardColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let currentReference {
                GuitarChordDiagramView(root: currentReference.root, chordTemplateID: currentReference.chordTemplateID, language: session.currentLanguage)
                    .frame(width: Self.progressionKeyboardSize.width / 2)
            }
            PitchKeyboardView(
                heldPitches: liveHeldPitches,
                chordRoot: currentChord?.root.value,
                chordTones: currentChord?.pitchClasses.map(\.value) ?? [],
                height: Self.progressionKeyboardSize.height,
                keyLabels: PitchKeyboardView.noteNameKeyLabels(forPitches: currentChordVoicingPitches, style: session.notationStyle),
                referenceChordPitches: Set(currentChordVoicingPitches)
            )
            .frame(width: Self.progressionKeyboardSize.width)
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
