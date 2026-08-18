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
    @Environment(AppModel.self) private var appModel

    @State private var screen: TheoryLibraryScreen = .list
    @State private var selectedTemplateName: String?
    /// Whole-octave shift applied to the progression staff/keyboard/playback — per explicit
    /// request, so a progression can be brought low enough to land on the bass (fa) clef instead
    /// of always sitting around middle C.
    @State private var octaveShift: Int = 0
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
    /// Triad by default, seventh as an opt-in — per explicit request ("priorité aux triades").
    @State private var chordQualityTier: ChordProgressionResolver.ChordQualityTier = .triad
    /// Replaces `session.isAuditioningTheoryLibrary` (the old isolated-audition player's own
    /// flag) as `SequenceTransportView`'s own "is playing" state, now that playback goes through
    /// real `pressKey`/`releaseKey` — see `playProgression()`'s own doc comment.
    @State private var isPlayingProgression = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesTwoColumns: Bool { TheoryLibraryLayoutMode.usesTwoColumns(horizontalSizeClass: horizontalSizeClass) }

    /// Reads/writes the ONE shared tonic+scale selection (`AppModel.sharedMode`) instead of a
    /// local `@State`, so picking a mode here is reflected on every other MusicLab screen,
    /// including detached windows — per explicit request. This screen's own tonic/scale picker
    /// stays restricted to the 7 classic major-family modes (see this struct's own doc comment),
    /// but the SHARED value can be set to something outside that list by another screen (e.g.
    /// "Modes") — `isSharedModeSupported` gates the rest of this screen's content for that case,
    /// while the picker itself keeps reading/writing the real shared value directly.
    private var mode: Mode {
        Mode(tonic: PitchClass(appModel.sharedMode.tonic), scale: ScaleLibrary.byID(appModel.sharedMode.scaleID) ?? ScaleLibrary.byID("ionian")!)
    }

    /// `false` when the shared mode (picked on another screen) isn't one of the 7 classic modes
    /// this screen's own diatonic resolution actually supports — per explicit request, the
    /// screen then gates its main content behind an empty-state message instead of showing a
    /// progression resolved against a scale family `ChordProgressionResolver` was never meant
    /// for, while its own (family-restricted) picker stays active so a valid mode can be
    /// re-picked right here.
    private var isSharedModeSupported: Bool {
        (ScaleLibrary.byID(appModel.sharedMode.scaleID)?.familyID ?? 1) == 1
    }

    private var sharedTonicBinding: Binding<Int> {
        Binding(get: { appModel.sharedMode.tonic }, set: { appModel.sharedMode.tonic = $0 })
    }
    private var sharedScaleIDBinding: Binding<String> {
        Binding(get: { appModel.sharedMode.scaleID }, set: { appModel.sharedMode.scaleID = $0 })
    }

    /// Whichever live track is the app's current "source principale" — same convention
    /// `ChordLibraryView`/`ModeLibraryView`/`TonnetzLibraryView` already use. Every playback
    /// function below plays through THIS track via real `pressKey`/`releaseKey` rather than the
    /// isolated `playTheoryLibraryAudition` player — per explicit request, so this screen acts as
    /// a genuine pre-input to the main keyboard. Silently does nothing when no source is picked.
    private var sourceID: TrackID? { session.theoryLiveInputSourceID }

    /// Presses `pitches` on `track` now, then releases them after `durationSeconds` — guarded by
    /// `generation`, same shared primitive `ModeLibraryView.pressAndScheduleRelease` uses.
    private func pressAndScheduleRelease(pitches: [Int], track: TrackID, durationSeconds: Double, generation: Int) {
        for pitch in pitches { session.pressKey(pitch: pitch, track: track) }
        DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds) {
            guard playbackGeneration == generation else { return }
            for pitch in pitches { session.releaseKey(pitch: pitch, track: track) }
        }
    }

    /// The mode's parent major key's conventional signature — same derivation as
    /// `ModeLibraryView.modeKeySignature` (see there for why `CircleOfFifths.parentTonic`, not
    /// `MajorKeySignature.forMajorTonic(mode.tonic.value)` directly); `nil` for any scale
    /// outside the 7 classic modes, same restriction `parentTonic` itself already has — the
    /// staff below just falls back to its original per-note accidentals in that case.
    private var modeKeySignature: MajorKeySignature? {
        CircleOfFifths.parentTonic(for: mode).map { MajorKeySignature.forMajorTonic($0.value) }
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
        return ChordProgressionResolver.resolveRich(selectedTemplate, in: mode, qualityTier: chordQualityTier)
    }

    /// Triad/seventh toggle for `resolvedReferences` — per explicit request, defaults to triads
    /// with sevenths as an opt-in (see `chordQualityTier`'s own doc comment).
    private var chordQualityTierPicker: some View {
        Picker("", selection: $chordQualityTier) {
            Text(L10n.string(.appOptionTriades, session.currentLanguage)).tag(ChordProgressionResolver.ChordQualityTier.triad)
            Text(L10n.string(.appOptionSeptiemes, session.currentLanguage)).tag(ChordProgressionResolver.ChordQualityTier.seventh)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS) || os(visionOS)
            HStack {
                Spacer()
                detachButton
                TheoryHelpButton(session: session)
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
        // Feeds Intonations' fixed-temperament tuning its mode — see `ModeLibraryView`'s own
        // identical pair of `.onChange`s for why leaving this screen clears it back to `nil`.
        .onChange(of: isActive, initial: true) { _, active in
            session.setContextualMode(active ? mode : nil)
        }
        .onChange(of: mode) { _, newMode in
            guard isActive else { return }
            session.setContextualMode(newMode)
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
                ModePickerBadge(
                    session: session, tonic: sharedTonicBinding, scaleID: sharedScaleIDBinding,
                    allowedScales: ScaleLibrary.scales(inFamily: 1), fillsAvailableWidth: true
                )
                chordQualityTierPicker
            } header: {
                Text(L10n.string(.appHeadingBibliothequeProgressions, session.currentLanguage))
            }
            if isSharedModeSupported {
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
            } else {
                Section {
                    Text(L10n.string(.appHintExplorationFamilleUn, session.currentLanguage))
                        .foregroundStyle(.secondary)
                }
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

                if isSharedModeSupported {
                    Text(selectedTemplate?.name ?? "").font(.largeTitle).bold()
                    commonNamesSection
                    octaveShiftControl

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
                        isPlaying: isPlayingProgression,
                        language: session.currentLanguage,
                        onPlay: playProgression,
                        onStop: stopProgression
                    )
                } else {
                    Text(L10n.string(.appHintExplorationFamilleUn, session.currentLanguage))
                        .foregroundStyle(.secondary)
                }
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
            return ChordStaffView.chordEvent(root: chord.root.value, tones: chord.pitchClasses.map(\.value), octaveOffset: octaveShift)
        }
    }

    /// Compact -2...+2 octave control shared by the staff (`progressionStaffEvents`) and the
    /// mini keyboard (`currentChordVoicingPitches`) — one control, applied to everything this
    /// screen shows, per explicit request.
    private var octaveShiftControl: some View {
        Stepper(value: $octaveShift, in: -2...2) {
            Text("\(L10n.string(.appFieldOctave, session.currentLanguage)) : \(octaveShift >= 0 ? "+\(octaveShift)" : "\(octaveShift)")")
                .font(.caption)
        }
        .fixedSize()
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
        return PitchSequencing.ascendingPitches(forPitchClasses: currentChord.pitchClasses.map(\.value), startingAbove: 47 + octaveShift * 12)
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
        guard let index = ImprovSession.matchingChordIndex(chord, in: resolvedReferences, reference: { $0 }, preferring: currentChordIndex) else { return }
        currentChordIndex = index
    }

    /// -30% off `ChordStaffView`'s own default scale, per explicit request.
    private static let progressionStaffHeightScale: CGFloat = 0.7
    /// Widened from the same 0.7 as `progressionStaffHeightScale` (used for both until now) —
    /// more room between chords, per explicit request ("plus de place entre les accords");
    /// height stays compact since only the horizontal spacing was cramped.
    private static let progressionStaffWidthScale: CGFloat = 1.1
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
                // Filled with this chord's own root note color (active palette) instead of a
                // plain accent tint — "which chord is current" now reads from the border/bold
                // text alone, since the fill is spoken for by note identity. The text color is
                // the palette's own precomputed legible pairing for that root (`ColorPalette
                // .textColors`), not a fixed `.secondary`/`.primary`, since a saturated fill can
                // need either black or white to stay readable depending on the note.
                let rootHex = session.activeColorPalette.colors[reference.root]
                let textColor = Color(hex: session.activeColorPalette.textColors[reference.root])
                Button {
                    currentChordIndex = index
                    playSingleChord(reference)
                } label: {
                    VStack(spacing: 2) {
                        Text("\(index + 1)").font(.caption2).foregroundStyle(textColor.opacity(0.75))
                        Text(chordDisplayName(reference)).fontWeight(index == currentChordIndex ? .bold : .regular).foregroundStyle(textColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: rootHex)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(index == currentChordIndex ? Color.accentColor : Color.black.opacity(0.15), lineWidth: index == currentChordIndex ? 2 : 1)
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
                        events: row.map(\.event), notePalette: session.activeColorPalette.colors,
                        heightScale: Self.progressionStaffHeightScale, widthScale: Self.progressionStaffWidthScale,
                        highlightedIndex: row.firstIndex(where: { $0.offset == currentChordIndex }),
                        keySignature: modeKeySignature,
                        onColumnTap: { localIndex in
                            guard row.indices.contains(localIndex) else { return }
                            let globalIndex = row[localIndex].offset
                            currentChordIndex = globalIndex
                            playSingleChord(resolvedReferences[globalIndex])
                        }
                    )
                    // This row's own chord names + notes in parens — a diagnostic readout (per
                    // explicit request) letting a wrong chord be spotted directly, same style as
                    // `DissonancesLibraryView.noteReadoutSection`.
                    Text(row.compactMap { entry in
                        resolvedReferences[entry.offset].resolve().map { chord in
                            let names = chord.pitchClasses.map { session.notationStyle.rootName($0, preferFlats: false) }.joined(separator: ", ")
                            return "\(session.notationStyle.displayName(for: chord)) (\(names))"
                        }
                    }.joined(separator: "  |  "))
                    .font(.caption)
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
        let perRow = ChordStaffView.maxColumnCount(forWidth: width, widthScale: Self.progressionStaffWidthScale)
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
                GuitarChordDiagramView(
                    root: currentReference.root, chordTemplateID: currentReference.chordTemplateID,
                    colorScheme: .noteBased(rootPitchClass: PitchClass(currentReference.root), palette: session.activeColorPalette.colors),
                    notationStyle: session.notationStyle,
                    language: session.currentLanguage
                )
                    .frame(width: Self.progressionKeyboardSize.width / 2)
            }
            PitchKeyboardView(
                heldPitches: liveHeldPitches,
                chordRoot: currentChord?.root.value,
                chordTones: currentChord?.pitchClasses.map(\.value) ?? [],
                colorScheme: currentChord.map { .noteBased(rootPitchClass: $0.root, palette: session.activeColorPalette.colors) } ?? PitchKeyboardColorScheme(),
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
        guard let chord = reference.resolve(), let sourceID else { return }
        session.releaseAllKeys(track: sourceID)
        playbackGeneration += 1
        let generation = playbackGeneration
        let pitches = PitchSequencing.ascendingPitches(forPitchClasses: chord.pitchClasses.map(\.value), startingAbove: 47 + octaveShift * 12)
        pressAndScheduleRelease(pitches: pitches, track: sourceID, durationSeconds: 1.5, generation: generation)
    }

    /// Plays the whole progression back to back AND advances `currentChordIndex` in step (so
    /// the keyboard and the staff's highlighted column follow along), guarded by
    /// `playbackGeneration` so a Stop (or restarting playback) cancels any still-pending advances
    /// instead of them firing late over whatever comes next. Plays through the "clavier
    /// principal" — real `pressKey`/`releaseKey` on the picked source track, same mechanism
    /// `TonnetzLibraryView.play(_:)` already uses — per explicit request, so this screen acts as
    /// a genuine pre-input to the main keyboard (a simulated key-press), not an isolated preview.
    /// Silently does nothing when no "source principale" is picked — same gate Tonnetz already
    /// has, not a regression (previously played regardless of source).
    private func playProgression() {
        guard let sourceID else { return }
        session.releaseAllKeys(track: sourceID)
        playbackGeneration += 1
        let generation = playbackGeneration
        isPlayingProgression = true
        let stepDuration = 1.0
        for (index, reference) in resolvedReferences.enumerated() {
            guard let chord = reference.resolve() else { continue }
            let pitches = PitchSequencing.ascendingPitches(forPitchClasses: chord.pitchClasses.map(\.value), startingAbove: 47 + octaveShift * 12)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * stepDuration) {
                guard playbackGeneration == generation else { return }
                currentChordIndex = index
                pressAndScheduleRelease(pitches: pitches, track: sourceID, durationSeconds: stepDuration * 0.9, generation: generation)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(resolvedReferences.count) * stepDuration) {
            guard playbackGeneration == generation else { return }
            isPlayingProgression = false
        }
    }

    private func stopProgression() {
        playbackGeneration += 1
        isPlayingProgression = false
        if let sourceID { session.releaseAllKeys(track: sourceID) }
    }
}

#Preview {
    ProgressionLibraryView(session: ImprovSession())
}
