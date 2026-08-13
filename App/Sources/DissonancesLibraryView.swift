import SwiftUI
import AppCore
import AudioEngine
import JamShackUI
import MusicTheoryKit
import Localization

/// Théorie's "Dissonances" tab — a continuous 2D sensory-dissonance landscape (William Sethares'
/// model, see `SensoryDissonance`) for a triad above a fixed root, built from the REAL spectrum
/// of the currently active instrument (`OctaveSpectrumGrid`), not an idealized harmonic
/// approximation.
///
/// Fully reactive workflow, per explicit request — no manual "build" step: picking a base note on
/// the keyboard at the top, or changing the density picker, immediately (re)triggers
/// `analyzeOctave()` (defaults to C4 on first appearance). While that's running, both inputs are
/// disabled and a progress indicator shows — deliberately BLOCKING a second request rather than
/// queuing/cancelling one, since the keyboard/picker being the only way to start a rebuild means
/// disabling them is enough to prevent any race between two in-flight builds.
///
/// Once built, explore triads on that same root: the heatmap (x = middle note's ratio to the
/// root, y = top note's ratio) is recomputed instantly from the already-captured spectra — pick a
/// triad from the row below the graph, or tap a point directly on the graph, either way it plays
/// right away and becomes the one marker shown. A triad picked from the list is colored (its own
/// root's palette color, same convention as every other mini-keyboard in the app); a point tapped
/// directly on the graph is shown in neutral gray instead — it's an arbitrary point in the
/// landscape, not necessarily a named chord.
struct DissonancesLibraryView: View {
    let session: ImprovSession
    let isActive: Bool

    private static let densityOptions = [12, 24, 48, 100, 300, 600, 1000]
    private static let heatmapResolution = 64
    /// 1.5× the screen's original 360×340 heatmap, then -10%, per explicit request.
    private static let heatmapSize = CGSize(width: 486, height: 459)
    private static let toneColors: [Color] = [.red, .green, .blue]

    /// The two rendering modes for the same landscape data — flat 2D heatmap (`DissonanceHeatmapView`)
    /// or a rotatable 3D height-field surface (`DissonanceSurfaceView`), per explicit request.
    private enum DrawingMode: String, CaseIterable, Identifiable {
        case twoD = "2D", threeD = "3D"
        var id: String { rawValue }
    }

    /// Where the current `selectedSemitones` came from — drives whether the base-note keyboard
    /// (and the marker) colors it as a real chord or shows it as neutral gray, per explicit
    /// request: "ce n'est pas un accord" for an arbitrary tapped point. `none` is the "just picked
    /// a base note, no chord actively shown" state — picking a NEW base note on the keyboard
    /// always resets here, clearing whatever chord was previously colored, per explicit request
    /// ("retour au point de départ").
    private enum SelectionSource: Equatable {
        case triad(ChordTemplate)
        case graphTap
        case none
    }

    /// One render request per currently-selected chord — see `computeSpectrumTones`'s own doc
    /// comment for why a stale, superseded render must never overwrite a newer one.
    private struct SpectrumRenderKey: Equatable {
        let gridKey: OctaveSpectrumGridKey
        let baseMidiPitch: Int
        let semitoneX: Int
        let semitoneY: Int
    }

    @State private var drawingMode: DrawingMode = .twoD
    /// Purely graphical Gaussian blur strength shared by both drawing modes (0 = raw/disabled) —
    /// see `DissonanceLandscape`'s own doc comment for why denser captures need this to look
    /// smooth again without changing the underlying density.
    @State private var smoothingSigma: Double = 0
    /// C4 — "un do médian" — the explicit default, immediately analyzed on first appearance (see
    /// the `.onChange(of: baseMidiPitch, initial: true)` below).
    @State private var baseMidiPitch = 60
    @State private var selectedScaleID = "ionian"
    @State private var samplesPerOctave = 24
    @State private var grid: OctaveSpectrumGrid?
    @State private var isBuilding = false
    @State private var buildProgress: Double = 0
    @State private var buildError: String?
    /// Semitones above the root for the middle/top note — the same 2 axes the heatmap itself
    /// plots. Defaults to the major triad, the previous screen's own default quality.
    @State private var selectedSemitones: (x: Int, y: Int) = (4, 7)
    @State private var selectionSource: SelectionSource = ChordVocabulary.byID("Ma").map { .triad($0) } ?? .graphTap
    @State private var playbackGeneration = 0
    /// Held only while the base-note keyboard is actively being clicked — the momentary gray
    /// flash "juste le temps du clic," separate from the persistent `pitchBadges` marker.
    @State private var pressedBasePitch: Int?
    /// The current chord's own full FFT spectra (root/middle/top, in that order) — ephemeral,
    /// replaced (never accumulated) whenever the selected chord changes. `nil` while computing or
    /// before any chord has ever been rendered.
    @State private var rawSpectra: [RawNoteSpectrum]?
    @State private var spectrumGeneration = 0

    private var sourceID: TrackID? { session.theoryLiveInputSourceID }

    private var basePitchClass: PitchClass { PitchClass(((baseMidiPitch % 12) + 12) % 12) }

    private var baseNoteLabel: String { noteLabel(forMidiPitch: baseMidiPitch) }

    private var mode: Mode {
        Mode(tonic: basePitchClass, scale: ScaleLibrary.byID(selectedScaleID) ?? ScaleLibrary.all[0])
    }

    /// The root + middle + top absolute MIDI pitches of whatever's currently selected/playing.
    private var currentPitches: [Int] { [baseMidiPitch, baseMidiPitch + selectedSemitones.x, baseMidiPitch + selectedSemitones.y] }

    private var currentPitchClasses: Set<PitchClass> { Set(currentPitches.map { PitchClass((($0 % 12) + 12) % 12) }) }

    /// The triad-shaped qualities in the shared chord vocabulary (root + exactly 2 more tones,
    /// both within one octave) — the only shapes this screen's 2-axis `[1, 2]` landscape can
    /// represent at all (anything with a 4th tone, or an interval past an octave, is out of
    /// scope). Sourced from `ChordVocabulary` (same catalog "Accords" browses), so a
    /// `chords.json`-registered triad quality shows up here too, rather than a fixed list.
    private var triadTemplates: [ChordTemplate] {
        ChordVocabulary.allIDs().compactMap(ChordVocabulary.byID).filter {
            $0.intervalsFromRoot.count == 3 && $0.intervalsFromRoot.first == 0 && $0.intervalsFromRoot.allSatisfy { $0 < 12 }
        }
    }

    /// One tick per chromatic semitone `[0, 12]` above the root (the octave-up tonic included) —
    /// shared by both heatmap axes, which cover the exact same `[1, 2]` ratio range. `isInScale`
    /// flags the current mode's own notes, so the rendering views can draw the OTHER (altered/
    /// chromatic, outside the scale) notes as lighter secondary ticks rather than omitting them
    /// entirely — per explicit request, so e.g. a Dorian mode's own natural 3rd/7th are still
    /// visible even though they're not part of that mode's scale. The scale picker driving this
    /// only ever affects these tick labels (and the persistent main-keyboard-bar coloring
    /// elsewhere) — never the landscape's own data — per explicit clarification.
    private var axisTicks: [(ratio: Double, label: String, isInScale: Bool)] {
        let scaleOffsets = Set(mode.scale.pitchClassesFromRoot + [12])
        return (0...12).map { offset in
            (ratio(forSemitonesAboveRoot: offset), noteLabel(forMidiPitch: baseMidiPitch + offset), scaleOffsets.contains(offset))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topRow

                if let grid {
                    landscapeSection(grid: grid)
                } else if isBuilding {
                    ProgressView(value: buildProgress) {
                        Text(L10n.string(.appLabelAnalyseEnCours, session.currentLanguage))
                    }
                } else if let buildError {
                    Text(buildError).foregroundStyle(.red).font(.caption)
                }
            }
            .padding()
        }
        .onChange(of: isActive, initial: true) { _, active in
            session.setContextualMode(active ? mode : nil)
        }
        .onChange(of: baseMidiPitch, initial: true) { _, _ in
            grid = nil // the previous grid's octave no longer matches the picker
            if isActive { session.setContextualMode(mode) }
            analyzeOctave()
        }
        .onChange(of: samplesPerOctave) { _, _ in
            grid = nil
            analyzeOctave()
        }
        .onChange(of: selectedScaleID) { _, _ in
            guard isActive else { return }
            session.setContextualMode(mode)
        }
    }

    /// Row 1: the base-note keyboard (widened +20%, per explicit request) and, alongside it —
    /// roughly above where the spectrum graph sits in row 2 — the playable-triad row, since this
    /// row's own job is now "place the base note and propose the chords."
    private var topRow: some View {
        HStack(alignment: .top, spacing: 20) {
            baseNoteKeyboardSection
                .frame(width: 576)
            chordButtonsRow
            Spacer(minLength: 0)
        }
    }

    /// Picking the base note is now a tap on this keyboard rather than a `Picker` — "vu que les
    /// calculs sont rapides," per explicit request, so exploring different base notes is as
    /// direct as playing them. Thinned to the same slim profile as the app's own persistent
    /// main-keyboard bar (`ComputerKeyboardInputBar`, also 90pt/full 21...108 range), rather than
    /// the tall 2-octave `PitchKeyboardView` default. Disabled (read-only, dimmed) while a build
    /// is already running — see this type's own doc comment on why that's the chosen way to
    /// block a second concurrent request rather than queuing/cancelling one.
    ///
    /// Two DISTINCT interactions, deliberately kept visually separate per explicit request:
    /// - Picking a base note: a momentary gray flash on exactly the clicked key for as long as
    ///   it's held (`pressedBasePitch`/`.held`'s neutral gray), then a small persistent "pastille"
    ///   above it (`pitchBadges`) marking which note is the current base — and nothing else
    ///   colored, even if a chord was previously shown (`selectionSource` resets to `.none`).
    /// - Playing a chord (from the row below the graph, or a graph tap): colors all 3 of its
    ///   notes — in the root's own palette color when it's a real listed triad, or in the color
    ///   scheme's neutral `.held` gray when it isn't (`SelectionSource.graphTap`) — until the next
    ///   base-note pick resets it.
    private var baseNoteKeyboardSection: some View {
        PitchKeyboardView(
            minMidi: 21, maxMidi: 108,
            heldPitches: keyboardHeldPitches,
            chordRoot: chordRootForKeyboard,
            chordTones: chordTonesForKeyboard,
            colorScheme: keyboardColorScheme,
            onNoteOn: isBuilding ? nil : { pitch in
                pressedBasePitch = pitch
                baseMidiPitch = pitch
                selectionSource = .none
            },
            onNoteOff: isBuilding ? nil : { _ in pressedBasePitch = nil },
            height: 90,
            pitchBadges: [baseMidiPitch: Self.baseNoteBadge]
        )
        .opacity(isBuilding ? 0.5 : 1)
    }

    private static let baseNoteBadge = KeyBadge(text: "", fillColor: .accentColor, textColor: .white)

    private var keyboardHeldPitches: Set<Int> {
        guard case .none = selectionSource else { return Set(currentPitches) }
        return Set(pressedBasePitch.map { [$0] } ?? [])
    }

    private var densityPickerSection: some View {
        Picker("Densité", selection: $samplesPerOctave) {
            ForEach(Self.densityOptions, id: \.self) { count in
                Text("\(count)/octave").tag(count)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(isBuilding)
    }

    /// The 3 currently selected notes' own names, plus — in parentheses — the name of whichever
    /// chord (ANY root, not just this screen's own base note) those exact 3 pitch classes form,
    /// if any. Shown under the spectrum graph, per explicit request.
    private var noteReadoutSection: some View {
        let names = currentPitches.map(noteLabel(forMidiPitch:)).joined(separator: " – ")
        let suffix = ChordVocabulary.exactMatch(forPitchClasses: currentPitchClasses)
            .map { " (\(session.notationStyle.displayName(for: $0)))" } ?? ""
        return Text(names + suffix).font(.subheadline)
    }

    /// The currently PLAYED note on each axis (the middle/top tone) — ticked in green/blue on the
    /// dissonance graph, matching `NoteSpectrumView`'s own per-tone colors, per explicit request.
    private var playedXNote: (ratio: Double, label: String) {
        (ratio(forSemitonesAboveRoot: selectedSemitones.x), noteLabel(forMidiPitch: baseMidiPitch + selectedSemitones.x))
    }

    private var playedYNote: (ratio: Double, label: String) {
        (ratio(forSemitonesAboveRoot: selectedSemitones.y), noteLabel(forMidiPitch: baseMidiPitch + selectedSemitones.y))
    }

    /// Row 2: the dissonance graph (with density/2D-3D/scale — the 3 params that drive the graph
    /// and its display — directly below it), its legend + smoothing slider, then the spectrum
    /// graph (with the note readout directly below IT) — per explicit request.
    @ViewBuilder
    private func landscapeSection(grid: OctaveSpectrumGrid) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    switch drawingMode {
                    case .twoD:
                        DissonanceHeatmapView(
                            grid: grid, resolution: Self.heatmapResolution,
                            baseNoteLabel: baseNoteLabel, axisTicks: axisTicks,
                            markerRatios: markerRatios(semitoneX: selectedSemitones.x, semitoneY: selectedSemitones.y),
                            playedXNote: playedXNote, playedYNote: playedYNote,
                            smoothingSigma: smoothingSigma,
                            onTapRatios: { x, y in selectAndPlay(semitoneX: semitonesFromRatio(x), semitoneY: semitonesFromRatio(y), source: .graphTap) }
                        )
                    case .threeD:
                        DissonanceSurfaceView(
                            grid: grid, baseNoteLabel: baseNoteLabel, axisTicks: axisTicks,
                            markerRatios: markerRatios(semitoneX: selectedSemitones.x, semitoneY: selectedSemitones.y),
                            playedXNote: playedXNote, playedYNote: playedYNote,
                            smoothingSigma: smoothingSigma,
                            onTapRatios: { x, y in selectAndPlay(semitoneX: semitonesFromRatio(x), semitoneY: semitonesFromRatio(y), source: .graphTap) }
                        )
                    }
                }
                .frame(width: Self.heatmapSize.width, height: Self.heatmapSize.height)

                parametersRow
            }

            HStack(alignment: .top, spacing: 12) {
                DissonanceColorScaleView()
                verticalSmoothingSlider
            }
            .frame(height: Self.heatmapSize.height)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spectre").font(.caption).foregroundStyle(.secondary)
                    Group {
                        if let spectrumTones {
                            NoteSpectrumView(tones: spectrumTones)
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(width: 468, height: Self.heatmapSize.height)
                    .border(Color.gray.opacity(0.25))
                }
                .task(id: SpectrumRenderKey(gridKey: grid.key, baseMidiPitch: baseMidiPitch, semitoneX: selectedSemitones.x, semitoneY: selectedSemitones.y)) {
                    await computeSpectrumTones()
                }

                noteReadoutSection
            }
        }
    }

    /// Rotated via the standard SwiftUI trick (size as if horizontal, rotate, then re-declare the
    /// frame so the PARENT layout reserves the post-rotation footprint) — no vertical `Slider`
    /// existed anywhere else in this codebase to copy.
    private var verticalSmoothingSlider: some View {
        let trackLength = Self.heatmapSize.height - 40
        return VStack(spacing: 6) {
            Text(smoothingSigma == 0 ? "brut" : String(format: "%.1f", smoothingSigma))
                .font(.caption2).foregroundStyle(.secondary)
            Slider(value: $smoothingSigma, in: 0...4)
                .frame(width: trackLength)
                .rotationEffect(.degrees(-90))
                .frame(width: 24, height: trackLength)
            Text("Lissage").font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Below the graph, horizontally: density, then the 2D/3D drawing-mode picker, then the scale
    /// picker (its own effect limited to the axis-tick legend, see `axisTicks`' own doc comment)
    /// — the 3 parameters that drive the graph's own data and display, grouped together, per
    /// explicit request.
    private var parametersRow: some View {
        HStack(alignment: .center, spacing: 16) {
            densityPickerSection
            drawingModePicker
            scalePickerRow
        }
    }

    private var drawingModePicker: some View {
        Picker("", selection: $drawingMode) {
            ForEach(DrawingMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 120)
    }

    private var scalePickerRow: some View {
        Picker(L10n.string(.fieldGamme, session.currentLanguage), selection: $selectedScaleID) {
            ForEach(ScaleLibrary.all) { scale in Text(scale.popularName).tag(scale.id) }
        }
        .pickerStyle(.menu)
        .fixedSize()
    }

    @ViewBuilder
    private var chordButtonsRow: some View {
        let rootHex = session.activeColorPalette.colors[basePitchClass.value]
        let textColor = Color(hex: session.activeColorPalette.textColors[basePitchClass.value])
        FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(triadTemplates) { template in
                let intervals = (template.intervalsFromRoot[1], template.intervalsFromRoot[2])
                let isSelected = isSelectedTriad(template)
                Button {
                    selectAndPlay(semitoneX: intervals.0, semitoneY: intervals.1, source: .triad(template))
                } label: {
                    Text(session.notationStyle.displayName(for: Chord(root: basePitchClass, template: template)))
                        .fontWeight(isSelected ? .bold : .regular)
                        .foregroundStyle(textColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: rootHex)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func isSelectedTriad(_ template: ChordTemplate) -> Bool {
        guard case .triad(let selected) = selectionSource else { return false }
        return selected.id == template.id
    }

    private var chordRootForKeyboard: Int? {
        guard case .triad = selectionSource else { return nil }
        return basePitchClass.value
    }

    private var chordTonesForKeyboard: [Int] {
        guard case .triad = selectionSource else { return [] }
        return currentPitchClasses.map(\.value)
    }

    private var keyboardColorScheme: PitchKeyboardColorScheme {
        guard case .triad = selectionSource else { return PitchKeyboardColorScheme() }
        return .noteBased(rootPitchClass: basePitchClass, palette: session.activeColorPalette.colors)
    }

    private func noteLabel(forMidiPitch midi: Int) -> String {
        let pc = ((midi % 12) + 12) % 12
        let octave = midi / 12 - 1
        return "\(session.notationStyle.rootName(PitchClass(pc), preferFlats: false))\(octave)"
    }

    /// The ACTIVE temperament's own cents deviation for a note `semitones` above the root — shared
    /// by `ratio(forSemitonesAboveRoot:)` (display math) and `computeSpectrumTones` (actually
    /// rendering that exact pitch), so a note's spectrum always reflects the same tuning its
    /// marker position and its audible playback (`pressKey`'s own `applyTuning`) already do.
    private func cents(forSemitonesAboveRoot semitones: Int) -> Double {
        let midi = baseMidiPitch + semitones
        return fixedTemperamentCents(forPitchClass: PitchClass(midi), tonic: basePitchClass, configuration: session.tuningConfiguration)
    }

    /// The frequency ratio-to-root a note `semitones` above the root lands at, under the ACTIVE
    /// temperament — the same reason a marker moves slightly if the temperament changes without
    /// the triad itself changing, per explicit request.
    private func ratio(forSemitonesAboveRoot semitones: Int) -> Double {
        let midi = baseMidiPitch + semitones
        return hz(forMidiPitch: midi, cents: cents(forSemitonesAboveRoot: semitones)) / hz(forMidiPitch: baseMidiPitch)
    }

    private func markerRatios(semitoneX: Int, semitoneY: Int) -> (x: Double, y: Double) {
        (ratio(forSemitonesAboveRoot: semitoneX), ratio(forSemitonesAboveRoot: semitoneY))
    }

    /// Snaps a tapped ratio to the nearest EQUAL-TEMPERED semitone — good enough to pick which
    /// note on the `[0, 12]` axis was tapped; the marker/playback themselves still resolve the
    /// exact position under the ACTIVE temperament afterward (`markerRatios`/`pressKey`'s own
    /// `applyTuning`), so this never needs to invert `fixedTemperamentCents` itself.
    private func semitonesFromRatio(_ ratio: Double) -> Int {
        max(0, min(12, Int((log2(ratio) * 12).rounded())))
    }

    /// `rawSpectra` (root/middle/top, in that order) paired back up with their own labels/pitches/
    /// colors for `NoteSpectrumView` — `nil` while `computeSpectrumTones` hasn't produced a result
    /// yet for the current selection.
    private var spectrumTones: [NoteSpectrumView.Tone]? {
        guard let rawSpectra, rawSpectra.count == 3 else { return nil }
        let pitches = currentPitches
        return (0..<3).map { index in
            NoteSpectrumView.Tone(
                label: noteLabel(forMidiPitch: pitches[index]), pitch: pitches[index], color: Self.toneColors[index],
                spectrum: rawSpectra[index], isBase: index == 0
            )
        }
    }

    /// Renders the FULL FFT spectrum (not `SensoryDissonance`'s reduced `dominantPartials`) of
    /// exactly the 3 currently selected notes — ephemeral and didactic (see `NoteSpectrumView`'s
    /// own doc comment): a fresh render per chord, immediately discarding whatever the previous
    /// chord's spectra were (`rawSpectra = nil` up front), never accumulated into a persistent
    /// table. `spectrumGeneration` guards against an in-flight render for an ALREADY-superseded
    /// chord selection completing late and overwriting a newer (or nil'd) result — same pattern
    /// `selectAndPlay`'s own `playbackGeneration` already uses for its release-after-delay race.
    private func computeSpectrumTones() async {
        rawSpectra = nil
        spectrumGeneration += 1
        let generation = spectrumGeneration
        guard let sound = session.theoryAuditionSound() else { return }
        let pitches: [(pitch: Int, cents: Double)] = [
            (baseMidiPitch, cents(forSemitonesAboveRoot: 0)),
            (baseMidiPitch + selectedSemitones.x, cents(forSemitonesAboveRoot: selectedSemitones.x)),
            (baseMidiPitch + selectedSemitones.y, cents(forSemitonesAboveRoot: selectedSemitones.y)),
        ]
        let soundFontURL = URL(fileURLWithPath: sound.path)
        let preset = sound.preset
        let result = try? await RawSpectrumRenderer.render(pitches: pitches, soundFontURL: soundFontURL, preset: preset)
        guard generation == spectrumGeneration else { return } // superseded by a newer chord selection
        rawSpectra = result
    }

    /// Blocked from re-entering while already running (see this type's own doc comment) — the
    /// keyboard/density picker are both disabled during a build so nothing else should be able to
    /// call this concurrently, but the guard stays as a backstop against ANY other trigger.
    private func analyzeOctave() {
        guard !isBuilding, let sound = session.theoryAuditionSound() else { return }
        isBuilding = true
        buildProgress = 0
        buildError = nil
        let midi = baseMidiPitch
        let density = samplesPerOctave
        let soundFontURL = URL(fileURLWithPath: sound.path)
        let preset = sound.preset
        Task.detached {
            do {
                let built = try await OctaveSpectrumGridBuilder.buildOrLoad(
                    baseMidiPitch: midi, soundFontURL: soundFontURL, preset: preset, samplesPerOctave: density,
                    progress: { fraction in Task { @MainActor in buildProgress = fraction } }
                )
                await MainActor.run {
                    grid = built
                    isBuilding = false
                }
            } catch {
                await MainActor.run {
                    buildError = "\(error)"
                    isBuilding = false
                }
            }
        }
    }

    private func selectAndPlay(semitoneX: Int, semitoneY: Int, source: SelectionSource) {
        selectedSemitones = (semitoneX, semitoneY)
        selectionSource = source
        guard let sourceID else { return }
        session.releaseAllKeys(track: sourceID)
        let pitches = [baseMidiPitch, baseMidiPitch + semitoneX, baseMidiPitch + semitoneY]
        for pitch in pitches { session.pressKey(pitch: pitch, track: sourceID, applyTuning: true) }
        playbackGeneration += 1
        let generation = playbackGeneration
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard generation == playbackGeneration else { return }
            for pitch in pitches { session.releaseKey(pitch: pitch, track: sourceID) }
        }
    }
}

#Preview {
    DissonancesLibraryView(session: ImprovSession(), isActive: true)
        .padding()
}
