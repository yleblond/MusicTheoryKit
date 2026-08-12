import SwiftUI
import AppCore
import AudioEngine
import JamShackUI
import MusicTheoryKit
import Localization

/// Théorie's "Dissonances" tab — a continuous 2D sensory-dissonance landscape (William Sethares'
/// model, see `SensoryDissonance`) for a triad above a fixed root, built from the REAL spectrum
/// of the currently active instrument (`OctaveSpectrumGrid`), not an idealized harmonic
/// approximation. Two-step workflow, per explicit request:
///
/// 1. Pick a base note + instrument, then "Analyser cette octave" builds (or loads from its own
///    disk cache) the dense set of real captured spectra spanning that octave — the expensive
///    half, isolated behind an explicit button rather than triggered on every picker change.
/// 2. Once built, explore triads on that same root: the heatmap (x = middle note's ratio to the
///    root, y = top note's ratio) is recomputed instantly from the already-captured spectra;
///    switching which triad quality is marked/played never re-triggers step 1.
struct DissonancesLibraryView: View {
    let session: ImprovSession
    let isActive: Bool

    /// The 4 three-note qualities this screen's [1, 2] (one octave) axes can represent — each
    /// as (semitones to the middle note, semitones to the top note) above the root. Anything
    /// with a 4th tone, or an interval past an octave, is out of scope for a 2-axis landscape.
    private static let referenceTriads: [(id: String, label: String, intervals: (Int, Int))] = [
        ("Ma", "Majeur", (4, 7)),
        ("mi", "Mineur", (3, 7)),
        ("dim", "Diminué", (3, 6)),
        ("aug", "Augmenté", (4, 8)),
    ]
    private static let densityOptions = [12, 24, 48, 100]
    private static let heatmapResolution = 64

    @State private var baseMidiPitch = 60 // C4
    @State private var samplesPerOctave = 24
    @State private var grid: OctaveSpectrumGrid?
    @State private var isBuilding = false
    @State private var buildProgress: Double = 0
    @State private var buildError: String?
    @State private var selectedTriadID = "Ma"
    @State private var playbackGeneration = 0

    private var sourceID: TrackID? { session.theoryLiveInputSourceID }

    private var baseNoteLabel: String {
        let pc = ((baseMidiPitch % 12) + 12) % 12
        let octave = baseMidiPitch / 12 - 1
        return "\(session.notationStyle.rootName(PitchClass(pc), preferFlats: false))\(octave)"
    }

    private var mode: Mode {
        Mode(tonic: PitchClass(((baseMidiPitch % 12) + 12) % 12), scale: ScaleLibrary.byID("ionian")!)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsSection
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
        .onChange(of: baseMidiPitch) { _, _ in
            grid = nil // the previous grid's octave no longer matches the picker
            guard isActive else { return }
            session.setContextualMode(mode)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                Picker(L10n.string(.appFieldNoteDeBase, session.currentLanguage), selection: $baseMidiPitch) {
                    ForEach(Array(stride(from: 36, through: 84, by: 1)), id: \.self) { midi in
                        Text(noteLabel(forMidiPitch: midi)).tag(midi)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(isBuilding)

                Picker("Densité", selection: $samplesPerOctave) {
                    ForEach(Self.densityOptions, id: \.self) { count in
                        Text("\(count)/octave").tag(count)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(isBuilding)

                Button(L10n.string(.appButtonAnalyserOctave, session.currentLanguage)) { analyzeOctave() }
                    .disabled(isBuilding || session.theoryAuditionSound() == nil)
            }
            if let sound = session.theoryAuditionSound() {
                Text(sound.displayName).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func landscapeSection(grid: OctaveSpectrumGrid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DissonanceHeatmapView(
                grid: grid, resolution: Self.heatmapResolution,
                referenceTicks: Self.referenceTriads.map { (label: $0.label, ratios: markerRatios(intervals: $0.intervals)) },
                markerRatios: markerRatios(intervals: Self.referenceTriads.first { $0.id == selectedTriadID }!.intervals)
            )
            .frame(width: 320, height: 320)

            HStack(spacing: 20) {
                Picker(L10n.string(.appFieldQualite, session.currentLanguage), selection: $selectedTriadID) {
                    ForEach(Self.referenceTriads, id: \.id) { triad in
                        Text(triad.label).tag(triad.id)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Button(L10n.string(.appButtonJouerTempere, session.currentLanguage)) { playSelectedTriad() }
            }
        }
    }

    private func noteLabel(forMidiPitch midi: Int) -> String {
        let pc = ((midi % 12) + 12) % 12
        let octave = midi / 12 - 1
        return "\(session.notationStyle.rootName(PitchClass(pc), preferFlats: false))\(octave)"
    }

    /// The (x, y) ratios-to-root a triad's own middle/top notes land at, under the ACTIVE
    /// temperament (`session.tuningConfiguration`) — the same reason the marker moves slightly
    /// if the temperament changes without the triad itself changing, per explicit request.
    private func markerRatios(intervals: (Int, Int)) -> (x: Double, y: Double) {
        let tonic = PitchClass(((baseMidiPitch % 12) + 12) % 12)
        let rootHz = hz(forMidiPitch: baseMidiPitch)
        func ratio(forSemitonesAboveRoot semitones: Int) -> Double {
            let midi = baseMidiPitch + semitones
            let cents = fixedTemperamentCents(forPitchClass: PitchClass(midi), tonic: tonic, configuration: session.tuningConfiguration)
            return hz(forMidiPitch: midi, cents: cents) / rootHz
        }
        return (ratio(forSemitonesAboveRoot: intervals.0), ratio(forSemitonesAboveRoot: intervals.1))
    }

    private func analyzeOctave() {
        guard let sound = session.theoryAuditionSound() else { return }
        isBuilding = true
        buildProgress = 0
        buildError = nil
        let midi = baseMidiPitch
        let density = samplesPerOctave
        let soundFontURL = URL(fileURLWithPath: sound.path)
        let preset = sound.preset
        Task.detached {
            do {
                let built = try OctaveSpectrumGridBuilder.buildOrLoad(
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

    private func playSelectedTriad() {
        guard let sourceID, let triad = Self.referenceTriads.first(where: { $0.id == selectedTriadID }) else { return }
        session.releaseAllKeys(track: sourceID)
        let pitches = [baseMidiPitch, baseMidiPitch + triad.intervals.0, baseMidiPitch + triad.intervals.1]
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
