import SwiftUI
import AppCore
import JamShackUI
import MusicTheoryKit
import RecognitionEngine
import Localization

/// Théorie's Tonnetz screen — the mode toggle (Harmonique/Performance) plus whichever grid is
/// active, coupled to the app's single "clavier principal" (`session.theoryLiveInputSourceID`,
/// the same source picker every other Théorie screen shares — see `ChordLibraryView`'s own
/// analogous `liveHeldPitches`). Tapping a node/edge/triangle here always plays through that same
/// live track (`pressKey`/`releaseKey`), so a tap-triggered note/dyad/chord becomes real,
/// recognized `heldPitches` exactly like any other played note — closing the harmonic/performance
/// loop the same way a real instrument would. Unlike Studio's tabs, Théorie's own
/// `setTheoryLiveInputSource` already turns the picked track's sound on, so playing here needs no
/// extra "is this wired to a scene role with a sound" gate — just a source being picked at all.
/// Lives in the App target (not `JamShackUI`, unlike `PitchClassTonnetzView`/`RegisteredTonnetzView`
/// themselves) because `.registerMainKeyboardChord`/`MainKeyboardChordSpec` — the persistent
/// bottom-bar coupling every other Théorie screen already uses — are App-target-only types.
struct TonnetzLibraryView: View {
    let session: ImprovSession
    /// See `ChordLibraryView.isActive`'s own doc comment — feeds `.registerMainKeyboardChord`.
    let isActive: Bool

    private enum DisplayMode: String, CaseIterable, Identifiable {
        case harmonic, performance
        var id: Self { self }
        func label(_ language: AppLanguage) -> String {
            switch self {
            case .harmonic: return L10n.string(.appModeTonnetzHarmonique, language)
            case .performance: return L10n.string(.appModeTonnetzPerformance, language)
            }
        }
    }

    @State private var displayMode: DisplayMode = .harmonic
    @State private var selection: TonnetzSelection? = .triad(Tonnetz.triad(quality: .major, anchoredAt: TonnetzCoordinate(q: 0, r: 0)))
    @State private var colorByIdentity = true
    @State private var auditionGeneration = 0

    private var sourceID: TrackID? { session.theoryLiveInputSourceID }

    private var heldPitches: Set<Int> {
        guard let sourceID else { return [] }
        return session.tracks.first { $0.id == sourceID }?.heldPitches ?? []
    }

    private var heldPitchClasses: Set<PitchClass> { Set(heldPitches.map { PitchClass($0) }) }

    /// Whether tapping this screen should actually sound anything — mirrors every other Théorie
    /// screen's implicit assumption (`ChordLibraryView`/`ModeLibraryView`/`ProgressionLibraryView`
    /// never re-check this themselves either): `setTheoryLiveInputSource` already enables sound
    /// on whichever track is picked, so simply having a source picked is enough.
    private var canPlay: Bool { sourceID != nil }

    private struct RecognitionSnapshot: Equatable {
        let heldPitchClasses: Set<PitchClass>
        let recognizedChord: RecognizedChord?
    }

    private var recognitionSnapshot: RecognitionSnapshot {
        RecognitionSnapshot(heldPitchClasses: heldPitchClasses, recognizedChord: session.theoryLiveInputRecognizedChord)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.label(session.currentLanguage)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                Spacer()
                Toggle(L10n.string(.appToggleTonnetzCouleursIdentite, session.currentLanguage), isOn: $colorByIdentity)
                    .toggleStyle(.switch)
                    .fixedSize()
            }

            selectionSummary

            Group {
                switch displayMode {
                case .harmonic:
                    PitchClassTonnetzView(
                        heldPitchClasses: heldPitchClasses,
                        selection: selection,
                        colorByIdentity: colorByIdentity,
                        palette: session.activeColorPalette.colors,
                        paletteTextColors: session.activeColorPalette.textColors,
                        notationStyle: session.notationStyle,
                        onSelect: { newSelection in
                            selection = newSelection
                            guard canPlay else { return }
                            play(newSelection)
                        }
                    )
                case .performance:
                    RegisteredTonnetzView(
                        heldPitches: heldPitches,
                        selection: selection,
                        colorByIdentity: colorByIdentity,
                        palette: session.activeColorPalette.colors,
                        paletteTextColors: session.activeColorPalette.textColors,
                        notationStyle: session.notationStyle,
                        onSelect: { newSelection in
                            selection = newSelection
                            guard canPlay else { return }
                            play(newSelection)
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        // Colors the persistent main-keyboard bar (`ContentView`) with this screen's own
        // selected chord, centered, while this tab is active — same mechanism `ChordLibraryView`
        // uses for its own chord. Only a `.triad` selection has a chord to register; a bare note
        // or dyad clears it instead of showing a stale one.
        .registerMainKeyboardChord(
            id: "theorie.tonnetz", isActive: isActive,
            chord: selection?.chord.map { MainKeyboardChordSpec(root: $0.root.value, tones: $0.pitchClasses.map(\.value)) }
        )
        .onChange(of: recognitionSnapshot) { _, snapshot in
            reactToLiveRecognition(snapshot)
        }
    }

    @ViewBuilder
    private var selectionSummary: some View {
        switch selection {
        case .triad:
            if let chord = selection?.chord {
                Text(session.notationStyle.displayName(for: chord)).font(.title2).bold()
            }
        case .edge(let edge, _):
            let rootName = session.notationStyle.rootName(edge.root, preferFlats: false)
            let otherName = session.notationStyle.rootName(edge.other, preferFlats: false)
            Text("\(rootName) – \(otherName)").font(.title2).bold()
        case .note(let pitchClass, _):
            Text(session.notationStyle.rootName(pitchClass, preferFlats: false)).font(.title2).bold()
        case nil:
            EmptyView()
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
