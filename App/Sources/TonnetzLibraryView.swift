import SwiftUI
import AppCore
import JamShackUI
import MusicTheoryKit
import PieceModel
import RecognitionEngine
import Localization

/// Théorie's Tonnetz screen — three graphs, coupled to the app's single "clavier principal"
/// (`session.theoryLiveInputSourceID`, the same source picker every other Théorie screen shares —
/// see `ChordLibraryView`'s own analogous `liveHeldPitches`). Layout: a top row (mode/color
/// controls, with the current selection's name centered over the whole row), then two columns —
/// the full Performance lattice on the left (all the available height/most of the width), and the
/// Harmonic condensation stacked above the Circle-of-fifths (when a family-1 mode is active — the
/// one place a diminished chord renders properly) on the right. `RegisteredTonnetzView` bands its
/// narrow axis on major thirds rather than fifths (fifths matter more musically, so they're the
/// axis that gets to range freely) — see that type's own doc comment — which is what lets it
/// deploy itself wide/short and work well as a column rather than needing a full-width band. The
/// legend (`TonnetzLegendView`) isn't shown inline — it's embedded in the "Théorie" pop-up
/// (`TonnetzHelpContent`, via `TheoryHelpButton`) instead. Tapping a node/edge/triangle here always plays
/// through that same live track (`pressKey`/`releaseKey`), so a tap-triggered note/dyad/chord
/// becomes real, recognized `heldPitches` exactly like any other played note — closing the
/// harmonic/performance loop the same way a real instrument would. Unlike Studio's tabs, Théorie's
/// own `setTheoryLiveInputSource` already turns the picked track's sound on, so playing here needs
/// no extra "is this wired to a scene role with a sound" gate — just a source being picked at all.
/// Lives in the App target (not `JamShackUI`, unlike `PitchClassTonnetzView`/
/// `RegisteredTonnetzView`/`CircleOfFifthsWheelView` themselves) because
/// `.registerMainKeyboardChord`/`MainKeyboardChordSpec`/the detach-window plumbing — conventions
/// every other Théorie screen already uses — are App-target-only.
struct TonnetzLibraryView: View {
    let session: ImprovSession
    /// See `ChordLibraryView.isActive`'s own doc comment — feeds `.registerMainKeyboardChord`,
    /// `.registerContextualHelp`, and `session.setContextualMode`.
    var isActive: Bool = true
    /// See `ChordLibraryView.isDetachedWindow`'s own doc comment — self-adapts `detachButton`.
    var isDetachedWindow: Bool = false

    @State private var selection: TonnetzSelection? = .triad(Tonnetz.triad(quality: .major, anchoredAt: TonnetzCoordinate(q: 0, r: 0)))
    @State private var colorByIdentity = true
    @State private var auditionGeneration = 0

    /// Optional, unlike Modes/Progressions/Intonations — Tonnetz has always worked fine with just
    /// a bare chord/note (like Accords), so a tonic/mode here is opt-in rather than mandatory.
    @State private var isModeEnabled = false

    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif
    @Environment(AppModel.self) private var appModel

    /// `false` when the shared mode (picked on another screen) isn't one of the 7 classic modes
    /// `diatonicTriads`/`circleOfFifthsWheel` actually support — per explicit request. Unlike
    /// Progression/Intonations, this doesn't gate the whole screen (Tonnetz already works fine
    /// with no mode at all) — only the mode-specific highlighting/wheel silently stay empty
    /// (their own existing `familyID == 1` guard), with a small inline notice instead so it
    /// reads as "not supported here" rather than "nothing happened."
    private var isSharedModeSupported: Bool {
        let scaleID = session.theoryDisplayModeReference?.scaleID ?? appModel.sharedMode.scaleID
        return (ScaleLibrary.byID(scaleID)?.familyID ?? 1) == 1
    }

    /// Whether `selectedMode` below is currently following piece playback rather than the manual
    /// "Mode optionnel" toggle/tonic/scale pickers — deliberately independent of `isModeEnabled`
    /// (a mode being OBSERVED from playback is shown regardless of whether the user separately
    /// flipped that manual toggle on — see `selectedMode`'s own doc comment for why the two used
    /// to conflict). `controlsRow` disables the toggle/pickers and shows a hint when this is
    /// `true`, since changing them would otherwise silently do nothing.
    private var modeFollowsPlayback: Bool {
        session.theoryDisplayModeReference != nil
    }

    private var sharedTonicBinding: Binding<Int> {
        Binding(get: { appModel.sharedMode.tonic }, set: { appModel.sharedMode.tonic = $0 })
    }
    private var sharedScaleIDBinding: Binding<String> {
        Binding(get: { appModel.sharedMode.scaleID }, set: { appModel.sharedMode.scaleID = $0 })
    }

    /// What the tonic/scale pickers should actually DISPLAY while `modeFollowsPlayback` — the
    /// piece's own ground-truth mode (`selectedMode`), never `sharedTonicBinding`/
    /// `sharedScaleIDBinding` themselves (untouched while following, so they'd otherwise keep
    /// showing whatever was last manually picked). Writes still go through the shared binding —
    /// moot in practice since both pickers are `.disabled` whenever this diverges from them.
    private var displayedTonicBinding: Binding<Int> {
        Binding(
            get: { modeFollowsPlayback ? (selectedMode?.tonic.value ?? sharedTonicBinding.wrappedValue) : sharedTonicBinding.wrappedValue },
            set: { sharedTonicBinding.wrappedValue = $0 }
        )
    }
    private var displayedScaleIDBinding: Binding<String> {
        Binding(
            get: { modeFollowsPlayback ? (selectedMode?.scale.id ?? sharedScaleIDBinding.wrappedValue) : sharedScaleIDBinding.wrappedValue },
            set: { sharedScaleIDBinding.wrappedValue = $0 }
        )
    }

    private var sourceID: TrackID? { session.theoryLiveInputSourceID }

    /// Includes piece-playback notes when `session.piecePlaybackObservationScope` is set (Music
    /// Lab's own "observe playback" feature) — same `theoryLiveInputHeldPitches` every other
    /// Théorie-only held-pitches read now goes through.
    private var heldPitches: Set<Int> {
        session.theoryLiveInputHeldPitches
    }

    private var heldPitchClasses: Set<PitchClass> { Set(heldPitches.map { PitchClass($0) }) }

    /// Whether tapping this screen should actually sound anything — mirrors every other Théorie
    /// screen's implicit assumption (`ChordLibraryView`/`ModeLibraryView`/`ProgressionLibraryView`
    /// never re-check this themselves either): `setTheoryLiveInputSource` already enables sound
    /// on whichever track is picked, so simply having a source picked is enough.
    private var canPlay: Bool { sourceID != nil }

    /// A piece being observed for playback (`theoryDisplayModeReference`) always wins over the
    /// manual "Mode optionnel" toggle — checked FIRST, unconditionally, rather than only once
    /// `isModeEnabled` is separately turned on. Before this, the two were combined
    /// (`isModeEnabled && theoryDisplayModeReference`), so observing a piece silently did nothing
    /// here unless the user ALSO happened to flip that toggle on — confirmed as the actual reason
    /// "the mode doesn't reach Tonnetz" even though it correctly reached Exploration fonctionnelle
    /// (which has no such gate of its own).
    private var selectedMode: Mode? {
        if let ref = session.theoryDisplayModeReference {
            return Mode(tonic: PitchClass(ref.tonic), scale: ScaleLibrary.byID(ref.scaleID) ?? ScaleLibrary.scales(inFamily: 1)[0])
        }
        guard isModeEnabled else { return nil }
        return Mode(tonic: PitchClass(appModel.sharedMode.tonic), scale: ScaleLibrary.byID(appModel.sharedMode.scaleID) ?? ScaleLibrary.scales(inFamily: 1)[0])
    }

    /// Its own toggle is only shown once a mode is active (see `controlsRow`) — per explicit
    /// request/verification: with no mode, the Tonnetz always shows the standard per-pitch-class
    /// palette (the same one the Circle-of-fifths uses), i.e. exactly what `colorByIdentity: true`
    /// already produces — so this forces `true` rather than `false` whenever no mode is active,
    /// the opposite of an earlier (wrong) version of this property. Once a mode IS active
    /// (manually or via `modeFollowsPlayback`), the checked (default) state keeps that same
    /// palette coloring plus a contrast highlight for the mode's own notes/chords
    /// (`nodeAppearance`/`triangleAppearance`'s own `role`/`isDiatonic` handling); unchecking it
    /// switches to the role-based blue scheme (mode root/tone notes, light-sky-blue diatonic
    /// triangles) instead.
    private var effectiveColorByIdentity: Bool { !(isModeEnabled || modeFollowsPlayback) || colorByIdentity }

    /// The mode's own diatonic major/minor triads, outlined on both lattices — `"dim"` (the vii°)
    /// is excluded, since no lattice triangle can represent a diminished triad (no perfect fifth
    /// to anchor one); `circleOfFifthsWheel` below is where that one gets shown properly instead.
    private var diatonicTriads: Set<TonnetzTriadKey> {
        guard let mode = selectedMode, mode.scale.familyID == 1 else { return [] }
        return Set(ChordProgressionResolver.diatonicChordReferences(in: mode).compactMap { ref in
            switch ref.chordTemplateID {
            case "Ma": return TonnetzTriadKey(root: PitchClass(ref.root), quality: .major)
            case "mi": return TonnetzTriadKey(root: PitchClass(ref.root), quality: .minor)
            default: return nil
            }
        })
    }

    /// The mode's parent-key wheel — `nil` unless a family-1 mode is active, the same restriction
    /// as `diatonicTriads` (both derive from "does this scale have a well-defined parent key
    /// signature"). Where the diminished vii° actually gets shown properly (outer ring, "°"
    /// suffix) — see `MusicTheoryKit/CircleOfFifths.swift`. `listeningTracks` feeds whichever
    /// chord is actually being played right now on the live source into the wheel's own
    /// per-track outline ring (`CircleOfFifthsWheelView`'s `cell.trackLabels`), so a played chord
    /// that's on the wheel shows up there as "selected" too — per explicit request.
    private var circleOfFifthsWheel: WebConsoleWheelState? {
        guard let mode = selectedMode, mode.scale.familyID == 1, let parentTonic = CircleOfFifths.parentTonic(for: mode) else { return nil }
        let liveTrack = sourceID.flatMap { id in session.tracks.first { $0.id == id } }
        return ImprovSession.wheelState(forTonic: parentTonic, activeTonic: mode.tonic, activeModeName: mode.scale.systematicName, listeningTracks: liveTrack.map { [$0] } ?? [])
    }

    private struct RecognitionSnapshot: Equatable {
        let heldPitchClasses: Set<PitchClass>
        let recognizedChord: RecognizedChord?
    }

    private var recognitionSnapshot: RecognitionSnapshot {
        RecognitionSnapshot(heldPitchClasses: heldPitchClasses, recognizedChord: session.theoryLiveInputRecognizedChord)
    }

    var body: some View {
        VStack(spacing: 16) {
            topBand
            HStack(alignment: .top, spacing: 16) {
                performanceColumn
                secondColumn
            }
        }
        .padding()
        #if os(macOS) || os(visionOS)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) { detachButton; TheoryHelpButton(session: session) }
                .padding(.horizontal)
                .padding(.top, 6)
        }
        #endif
        // Colors the persistent main-keyboard bar (`ContentView`) with this screen's own
        // selected chord, centered, while this tab is active — same mechanism `ChordLibraryView`
        // uses for its own chord. Only a `.triad` selection has a chord to register; a bare note
        // or dyad clears it instead of showing a stale one.
        .registerMainKeyboardChord(
            id: "theorie.tonnetz", isActive: isActive,
            chord: selection?.chord.map { MainKeyboardChordSpec(root: $0.root.value, tones: $0.pitchClasses.map(\.value)) }
        )
        // Feeds Intonations' fixed-temperament tuning this screen's OPTIONAL mode — same
        // isActive-driven set/clear as Modes/Progressions/Intonations (see
        // `ImprovSession.contextualMode`'s own doc comment). Leaving the mode off (the default)
        // behaves exactly as Tonnetz always has: no tonic, no correction.
        .onChange(of: isActive, initial: true) { _, active in
            session.setContextualMode(active ? selectedMode : nil)
        }
        .onChange(of: selectedMode) { _, newMode in
            guard isActive else { return }
            session.setContextualMode(newMode)
        }
        .registerContextualHelp(id: HelpTopicID.theorieTonnetz.rawValue, isActive: isActive) {
            HelpTopicID.theorieTonnetz.content(language: session.currentLanguage)
        }
        .onChange(of: recognitionSnapshot) { _, snapshot in
            reactToLiveRecognition(snapshot)
        }
    }

    // MARK: - Bande du haut (A) : contrôles, Harmonique, cercle des quintes

    /// The controls row, then the current selection's name centered below it — per explicit
    /// request (moved down from an overlay centered over the row itself, no longer tucked into
    /// the Harmonic group either).
    private var topBand: some View {
        VStack(spacing: 8) {
            controlsRow
            selectionSummary
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var controlsRow: some View {
        HStack {
            Toggle(L10n.string(.appLabelModeOptionnel, session.currentLanguage), isOn: $isModeEnabled)
                .toggleStyle(.switch)
                .fixedSize()
                .disabled(modeFollowsPlayback)
            if isModeEnabled || modeFollowsPlayback {
                ModePickerBadge(
                    session: session, tonic: displayedTonicBinding, scaleID: displayedScaleIDBinding,
                    allowedScales: ScaleLibrary.scales(inFamily: 1), isEnabled: !modeFollowsPlayback
                )
                // Stuck to the mode controls, and only shown once a mode is active — see
                // `effectiveColorByIdentity`'s own doc comment.
                Toggle(L10n.string(.appToggleTonnetzCouleursIdentite, session.currentLanguage), isOn: $colorByIdentity)
                    .toggleStyle(.switch)
                    .fixedSize()
                if modeFollowsPlayback {
                    Text(L10n.string(.appHintModeSuitLecture, session.currentLanguage))
                        .font(.caption2).foregroundStyle(.secondary)
                } else if !isSharedModeSupported {
                    Text(L10n.string(.appHintExplorationFamilleUn, session.currentLanguage))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Colonnes du bas : Performance (toute la hauteur) + Harmonique/cercle des quintes empilés

    private var performanceColumn: some View {
        RegisteredTonnetzView(
            heldPitches: heldPitches,
            selection: selection,
            colorByIdentity: effectiveColorByIdentity,
            palette: session.activeColorPalette.colors,
            paletteTextColors: session.activeColorPalette.textColors,
            notationStyle: session.notationStyle,
            mode: selectedMode,
            diatonicTriads: diatonicTriads,
            onSelect: { newSelection in
                selection = newSelection
                guard canPlay else { return }
                play(newSelection)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Harmonic on top, Circle-of-fifths below — a narrow column next to `performanceColumn`,
    /// sized to whichever of the two is wider (the Harmonic lattice, 450pt).
    private var secondColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            harmonicGroup
            circleOfFifthsGroup
        }
    }

    /// Enlarged again (450 → 540, +20%) now that it's a full column rather than competing for
    /// space as a floating card, and centered within its own column width (matching
    /// `circleOfFifthsGroup`'s own centering) rather than leading-aligned.
    private var harmonicGroup: some View {
        PitchClassTonnetzView(
            heldPitchClasses: heldPitchClasses,
            selection: selection,
            colorByIdentity: effectiveColorByIdentity,
            palette: session.activeColorPalette.colors,
            paletteTextColors: session.activeColorPalette.textColors,
            notationStyle: session.notationStyle,
            mode: selectedMode,
            diatonicTriads: diatonicTriads,
            onSelect: { newSelection in
                selection = newSelection
                guard canPlay else { return }
                play(newSelection)
            }
        )
        .frame(width: 540)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// The mode's Circle-of-fifths, when there is one — see `circleOfFifthsWheel`'s own doc
    /// comment. No label (per explicit request — the wheel itself is unambiguous), shrunk back
    /// down proportionally (300 → 240, -20%) as the Harmonic group grows.
    /// Tapping a major/minor cell plays it and selects the matching triad on the Tonnetz too —
    /// per explicit request; a diminished cell has no lattice triangle to select (see
    /// `diatonicTriads`'s own doc comment), so taps there are silently ignored rather than
    /// playing something the Tonnetz can't also show.
    @ViewBuilder
    private var circleOfFifthsGroup: some View {
        if let wheel = circleOfFifthsWheel {
            CircleOfFifthsWheelView(
                wheel: wheel, palette: session.activeColorPalette.colors, paletteTextColors: session.activeColorPalette.textColors,
                onSelectCell: { pitchClass, quality in playCircleOfFifthsCell(pitchClass: pitchClass, quality: quality) }
            )
            .frame(width: 240, height: 240)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel(L10n.string(.appLabelCercleDesQuintes, session.currentLanguage))
        }
    }

    private func playCircleOfFifthsCell(pitchClass: Int, quality: String) {
        let tonnetzQuality: TonnetzTriadQuality
        switch quality {
        case "major": tonnetzQuality = .major
        case "minor": tonnetzQuality = .minor
        default: return
        }
        let tile = Tonnetz.paddedTile()
        guard let coordinate = Tonnetz.coordinate(forRoot: PitchClass(pitchClass), in: tile.primary + tile.halo) else { return }
        let triad = Tonnetz.triad(quality: tonnetzQuality, anchoredAt: coordinate)
        selection = .triad(triad)
        guard canPlay else { return }
        play(.triad(triad))
    }

    #if os(macOS) || os(visionOS)
    @ViewBuilder
    private var detachButton: some View {
        if isDetachedWindow {
            Button {
                dismissWindow(id: AuxiliaryWindowID.theorieTonnetz.rawValue)
            } label: {
                Label(L10n.string(.appButtonReintegrer, session.currentLanguage), systemImage: "arrow.down.right.and.arrow.up.left")
            }
        } else {
            Button {
                openWindow(id: AuxiliaryWindowID.theorieTonnetz.rawValue)
            } label: {
                Image(systemName: "rectangle.on.rectangle")
            }
        }
    }
    #endif

    /// Prefixed with "Accord"/"Note"/"Notes" — per explicit request, a bare root name alone
    /// doesn't say whether it's a single note or a chord (they can render identically, e.g. a
    /// plain "C").
    @ViewBuilder
    private var selectionSummary: some View {
        switch selection {
        case .triad:
            if let chord = selection?.chord {
                Text("\(L10n.string(.appLabelAccord, session.currentLanguage)) \(session.notationStyle.displayName(for: chord))").font(.title2).bold()
            }
        case .edge(let edge, _):
            let rootName = session.notationStyle.rootName(edge.root, preferFlats: false)
            let otherName = session.notationStyle.rootName(edge.other, preferFlats: false)
            Text("\(L10n.string(.appLabelNotes, session.currentLanguage)) \(rootName)-\(otherName)").font(.title2).bold()
        case .note(let pitchClass, _):
            Text("\(L10n.string(.appLabelNote, session.currentLanguage)) \(session.notationStyle.rootName(pitchClass, preferFlats: false))").font(.title2).bold()
        case nil:
            Text(L10n.string(.appModeTonnetzHarmonique, session.currentLanguage)).font(.title2).bold()
        }
    }

    /// Directly follows whatever's actually being played, exactly as if it had been tapped —
    /// same "live overrides the browsed selection" convention every other Théorie screen's
    /// live-match reaction already follows. Exactly 2 held notes takes priority as an edge
    /// (per explicit request: 2 notes should read as a dyad, not an arbitrarily-guessed triad);
    /// 3+ held notes forming a recognized major/minor triad reads as that triad. Any other
    /// quality (7ths, etc.) is ignored for now — Phase 1 only models plain triads/dyads on the
    /// lattice (see the plan's Phase 2 backlog).
    private func reactToLiveRecognition(_ snapshot: RecognitionSnapshot) {
        if snapshot.heldPitchClasses.count == 2, let match = Tonnetz.matchingEdge(forHeldPitchClasses: snapshot.heldPitchClasses) {
            let edge = TonnetzEdge(coordinate: TonnetzCoordinate(q: 0, r: 0), kind: match.kind, root: match.root, other: match.other)
            let realPitches = heldPitches.count == 2 ? Array(heldPitches) : nil
            selection = .edge(edge, realPitches: realPitches)
            return
        }
        guard let chord = snapshot.recognizedChord, chord.chordTemplateID == "Ma" || chord.chordTemplateID == "mi" else { return }
        let quality: TonnetzTriadQuality = chord.chordTemplateID == "Ma" ? .major : .minor
        let tile = Tonnetz.paddedTile()
        guard let coordinate = Tonnetz.coordinate(forRoot: chord.root, in: tile.primary + tile.halo) else { return }
        selection = .triad(Tonnetz.triad(quality: quality, anchoredAt: coordinate))
    }

    private func nearestRealPitch(forPitchClass pitchClass: PitchClass) -> Int {
        let anchor = heldPitches.isEmpty ? 60 : heldPitches.reduce(0, +) / heldPitches.count
        let candidates = stride(from: pitchClass.value, through: 120, by: 12).map { $0 }
        let best = candidates.min(by: { abs($0 - anchor) < abs($1 - anchor) }) ?? (pitchClass.value + 60)
        return min(max(best, 21), 108)
    }

    private func play(_ selection: TonnetzSelection) {
        guard sourceID != nil else { return }
        switch selection {
        case .note(let pitchClass, let realPitch):
            playSingleNote(realPitch ?? nearestRealPitch(forPitchClass: pitchClass))
        case .edge(let edge, let realPitches):
            if let realPitches, realPitches.count == 2 {
                playPitches(realPitches, releaseFirst: true)
            } else {
                let root = nearestRealPitch(forPitchClass: edge.root)
                let other = TonnetzVoicing.nearestOtherPitch(anchor: root, otherPitchClass: edge.other)
                playPitches([root, other], releaseFirst: true)
            }
        case .triad:
            guard let chord = selection.chord else { return }
            let targetPitches = TonnetzVoicing.nearestVoicing(forChord: chord, previousPitches: Array(heldPitches))
            playPitches(targetPitches, releaseFirst: true)
        }
    }

    private func playSingleNote(_ pitch: Int) {
        guard let sourceID else { return }
        session.releaseAllKeys(track: sourceID)
        session.pressKey(pitch: pitch, track: sourceID)
        auditionGeneration += 1
        let generation = auditionGeneration
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if generation == auditionGeneration {
                session.releaseKey(pitch: pitch, track: sourceID)
            }
        }
    }

    private func playPitches(_ pitches: [Int], releaseFirst: Bool = false) {
        guard let sourceID else { return }
        if releaseFirst { session.releaseAllKeys(track: sourceID) }
        for pitch in pitches { session.pressKey(pitch: pitch, track: sourceID) }
        auditionGeneration += 1
        let generation = auditionGeneration
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if generation == auditionGeneration {
                for pitch in pitches { session.releaseKey(pitch: pitch, track: sourceID) }
            }
        }
    }
}
