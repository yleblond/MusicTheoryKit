import Foundation
import AudioEngine
import SoundFontModel

/// Identifies one built spectrum grid — which octave (`baseMidiPitch` up to `baseMidiPitch +
/// 12`), which instrument, and at what density. Two grids built with the same key are, by
/// construction, identical (the render points are deterministic, evenly spaced), so this key
/// doubles as the cache lookup.
public struct OctaveSpectrumGridKey: Codable, Hashable, Sendable {
    public let soundFontPath: String
    public let preset: SoundFontPresetIdentity?
    public let baseMidiPitch: Int
    public let samplesPerOctave: Int

    public init(soundFontPath: String, preset: SoundFontPresetIdentity?, baseMidiPitch: Int, samplesPerOctave: Int) {
        self.soundFontPath = soundFontPath
        self.preset = preset
        self.baseMidiPitch = baseMidiPitch
        self.samplesPerOctave = samplesPerOctave
    }
}

/// A dense set of REAL, measured spectra spanning one octave of one instrument — the "Dissonances"
/// screen's whole reason for existing (see `SensoryDissonance`'s own doc comment): rather than
/// assuming one idealized harmonic series, or transposing a single reference spectrum across the
/// whole octave (both rejected — see the approved plan), every point here is its own genuine
/// offline render + FFT analysis (`OfflineNoteRenderer`/`FFTPitchAnalyzer.dominantPartials`) of
/// the nearest MIDI note, fine-tuned to the exact target frequency via cents pitch-bend — so even
/// a `samplesPerOctave` far denser than 12 stays faithful to the real instrument, not an
/// approximation between distant real notes.
public struct OctaveSpectrumGrid: Codable, Sendable {
    public struct CapturedSpectrumPoint: Codable, Sendable {
        /// 0...12 — 0 is `key.baseMidiPitch` itself, 12 is one full octave above.
        public let semitoneOffset: Double
        /// The actual physical frequency this point was rendered at (standard A440/12-TET
        /// reference — grid points are NOT tied to any `TuningConfiguration`; only the marker
        /// for a specific played chord is, see `DissonancesLibraryView`).
        public let frequencyHz: Double
        public let partials: [SpectralPartial]
    }

    public let key: OctaveSpectrumGridKey
    /// Sorted ascending by `semitoneOffset`, `key.samplesPerOctave + 1` points (both octave
    /// endpoints included).
    public let points: [CapturedSpectrumPoint]

    public init(key: OctaveSpectrumGridKey, points: [CapturedSpectrumPoint]) {
        self.key = key
        self.points = points
    }

    /// The partials to use for a tone at `targetHz`, anywhere within (or slightly beyond) this
    /// grid's own octave — a crossfade between the two captured points bracketing `targetHz`
    /// (each frequency-scaled to `targetHz` first, same small-ratio scale as before), weighted
    /// by how close `targetHz` sits to each in LOG-frequency space (matches the grid's own even
    /// semitone spacing). Outside the grid's own range, falls back to scaling the single nearest
    /// endpoint (no second point to fade toward).
    ///
    /// Earlier version snapped to the single nearest point with no blending — cheap, but a sweep
    /// across `targetHz` (as `DissonanceHeatmapView`'s heatmap does, independently on both axes)
    /// stepped abruptly at each point's own boundary, visible as a checkerboard/moiré artifact
    /// once the heatmap's resolution ran denser than `samplesPerOctave`. Blending by CROSSFADING
    /// the two neighbors' own (frequency-scaled) partials — rather than trying to match/interpolate
    /// individual partials pairwise between them — sidesteps the "different partial counts/
    /// orderings" ambiguity noted before: each side's amplitudes are simply scaled by its own
    /// fade weight and the two lists concatenated, which is exactly a linear mix of two sound
    /// sources and keeps `SensoryDissonance`'s pairwise-product math (bilinear in amplitude)
    /// continuous in `targetHz`.
    public func partials(atFrequencyHz targetHz: Double) -> [SpectralPartial] {
        guard let first = points.first, let last = points.last else { return [] }
        if targetHz <= first.frequencyHz { return Self.scaled(first, toFrequencyHz: targetHz) }
        if targetHz >= last.frequencyHz { return Self.scaled(last, toFrequencyHz: targetHz) }
        guard let upperIndex = points.firstIndex(where: { $0.frequencyHz >= targetHz }), upperIndex > 0 else {
            return Self.scaled(last, toFrequencyHz: targetHz)
        }
        let low = points[upperIndex - 1]
        let high = points[upperIndex]
        let t = log(targetHz / low.frequencyHz) / log(high.frequencyHz / low.frequencyHz)
        let lowPartials = Self.scaled(low, toFrequencyHz: targetHz).map { SpectralPartial(frequencyHz: $0.frequencyHz, amplitude: $0.amplitude * (1 - t)) }
        let highPartials = Self.scaled(high, toFrequencyHz: targetHz).map { SpectralPartial(frequencyHz: $0.frequencyHz, amplitude: $0.amplitude * t) }
        return lowPartials + highPartials
    }

    private static func scaled(_ point: CapturedSpectrumPoint, toFrequencyHz targetHz: Double) -> [SpectralPartial] {
        let ratio = targetHz / point.frequencyHz
        return point.partials.map { SpectralPartial(frequencyHz: $0.frequencyHz * ratio, amplitude: $0.amplitude) }
    }
}

/// Builds (rendering + analyzing every point live) or loads (from a persistent disk cache) an
/// `OctaveSpectrumGrid`. Building is the expensive half — one offline render + FFT per point,
/// see `OfflineNoteRenderer`'s own doc comment for why nothing in this app could do this before —
/// so every built grid is cached to disk, keyed by `OctaveSpectrumGridKey`, and survives between
/// app launches: the same instrument/octave/density is only ever paid for once.
public enum OctaveSpectrumGridBuilder {
    /// How long each rendered note plays before being analyzed — long enough that a
    /// `steadyStateWindowStart` skip still leaves a full FFT window of genuine sustain, short
    /// enough that a `samplesPerOctave` in the hundreds stays practical (each point is this
    /// many seconds of OFFLINE rendering, not realtime — see `OfflineNoteRendererTests`, which
    /// measured well under realtime speed for a 0.5s render).
    public static let renderDurationSeconds = 0.6
    /// Skipped at the start of every render before analysis — clears the attack transient
    /// (onset click/chiff, pitch instability) so the FFT window reads the instrument's actual
    /// sustained timbre.
    public static let attackSkipSeconds = 0.15

    /// `nil` `progress` runs silently; otherwise called after every point with `0...1`
    /// (`Double` fraction complete) — a `samplesPerOctave` of even a few dozen is easily a
    /// several-second operation, worth a progress indicator (see the approved plan's "barre de
    /// progression"). `async` — routes the actual rendering through `OfflineRenderQueue` so it
    /// can never run concurrently with another offline render (`RawSpectrumRenderer`, or another
    /// call to this same function) — see that type's own doc comment for the crash this fixes.
    public static func buildOrLoad(
        baseMidiPitch: Int, soundFontURL: URL, preset: SoundFontPresetIdentity?, samplesPerOctave: Int,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> OctaveSpectrumGrid {
        let key = OctaveSpectrumGridKey(soundFontPath: soundFontURL.path, preset: preset, baseMidiPitch: baseMidiPitch, samplesPerOctave: samplesPerOctave)
        if let cached = OctaveSpectrumGridStore.load(for: key) { return cached }

        let grid = try await OfflineRenderQueue.shared.run {
            let renderer = try OfflineNoteRenderer()
            try renderer.loadSample(at: soundFontURL, preset: preset)
            return try build(key: key, renderer: renderer, progress: progress)
        }
        try? OctaveSpectrumGridStore.save(grid) // best-effort — a cache-write failure shouldn't fail the whole build
        return grid
    }

    /// The actual render-every-point loop, factored out from `buildOrLoad` so a test can drive
    /// it against an `OfflineNoteRenderer` that never had `loadSample` called (exercising
    /// `AVAudioUnitSampler`'s own built-in default instrument, same stand-in
    /// `OfflineNoteRendererTests` already uses) — this repo has no `.sf2` fixture to load a real
    /// instrument from (see `PiecePlayerTests`'s own comment), and `loadSample` genuinely throws
    /// for a nonexistent path, so `buildOrLoad`'s own cache-then-load-then-build flow isn't
    /// testable end to end without one.
    static func build(key: OctaveSpectrumGridKey, renderer: OfflineNoteRenderer, progress: ((Double) -> Void)?) throws -> OctaveSpectrumGrid {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let skipSamples = Int(attackSkipSeconds * renderer.sampleRate)

        let totalPoints = key.samplesPerOctave + 1
        var points: [OctaveSpectrumGrid.CapturedSpectrumPoint] = []
        points.reserveCapacity(totalPoints)
        for i in 0...key.samplesPerOctave {
            let semitoneOffset = Double(i) * 12.0 / Double(key.samplesPerOctave)
            let nearestMidi = key.baseMidiPitch + Int(semitoneOffset.rounded())
            let residualCents = (semitoneOffset - Double(nearestMidi - key.baseMidiPitch)) * 100.0
            let frequencyHz = hz(forMidiPitch: key.baseMidiPitch, cents: semitoneOffset * 100.0)

            let samples = try renderer.renderNote(pitch: nearestMidi, cents: residualCents, durationSeconds: renderDurationSeconds)
            let windowStart = min(skipSamples, max(0, samples.count - analyzer.size))
            var window = Array(samples[windowStart..<min(windowStart + analyzer.size, samples.count)])
            if window.count < analyzer.size { window += [Float](repeating: 0, count: analyzer.size - window.count) }

            let partials = capturedPartials(fromWindow: window, analyzer: analyzer, sampleRate: renderer.sampleRate)
            points.append(.init(semitoneOffset: semitoneOffset, frequencyHz: frequencyHz, partials: partials))
            progress?(Double(i + 1) / Double(totalPoints))
        }
        return OctaveSpectrumGrid(key: key, points: points)
    }

    /// `FFTPitchAnalyzer.dominantPartials`' own "must clearly stand out from the band average"
    /// gate is tuned for LIVE PITCH DETECTION (if nothing's clearly dominant, report nothing) —
    /// shared with this grid, but here "nothing" is the wrong answer: a captured point left with
    /// ZERO partials registers as UNCONDITIONALLY near-zero dissonance against every other tone
    /// in `SensoryDissonance`'s pairwise sum (there's nothing to sum), which shows up as a whole
    /// cross of anomalously blue rows/columns cutting through the landscape at that point's own
    /// ratio — worse than a single, ungated best-effort peak. Falls back to just the single
    /// loudest in-band bin (same `[60, 8000]` Hz band `dominantPartials` itself defaults to)
    /// whenever the gated result comes back empty; genuine silence (`spectrumSnapshot` itself
    /// returning `nil`, e.g. below the RMS floor) still correctly yields no partials at all.
    static func capturedPartials(fromWindow window: [Float], analyzer: FFTPitchAnalyzer, sampleRate: Double) -> [SpectralPartial] {
        let detected = analyzer.dominantPartials(in: window, sampleRate: sampleRate)
        if !detected.isEmpty {
            return detected.map { SpectralPartial(frequencyHz: $0.frequencyHz, amplitude: $0.amplitude) }
        }
        guard let snapshot = analyzer.spectrumSnapshot(of: window, sampleRate: sampleRate) else { return [] }
        let minBin = max(1, Int(60.0 / snapshot.binHz))
        let maxBin = min(snapshot.magnitudes.count - 1, Int(8000.0 / snapshot.binHz))
        guard minBin < maxBin, let peakBin = (minBin...maxBin).max(by: { snapshot.magnitudes[$0] < snapshot.magnitudes[$1] }) else { return [] }
        let frequencyHz = Double(peakBin) * snapshot.binHz
        let amplitude = Double(snapshot.magnitudes[peakBin]).squareRoot()
        return [SpectralPartial(frequencyHz: frequencyHz, amplitude: amplitude)]
    }
}

/// Persistent (disk) cache for built grids — see `OctaveSpectrumGridBuilder`'s own doc comment
/// for why this matters (each grid is expensive to build, cheap to reuse).
enum OctaveSpectrumGridStore {
    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("DissonanceSpectra", isDirectory: true)
    }

    /// A stable, readable filename built directly from the key's own fields — deliberately NOT
    /// `Hasher`-based: `Hash.finalize()`'s seed is randomized per PROCESS LAUNCH by design (a
    /// security property of `Hashable`, not a bug), so a `Hasher`-derived filename would never
    /// match itself across two app launches, silently defeating the entire point of a
    /// persistent cache.
    private static func cacheURL(for key: OctaveSpectrumGridKey) -> URL {
        let sanitizedPath = key.soundFontPath.replacingOccurrences(of: "/", with: "_")
        let presetPart = key.preset.map { "p\($0.program)b\($0.bank)" } ?? "default"
        return cacheDirectory.appendingPathComponent("\(sanitizedPath)_\(presetPart)_m\(key.baseMidiPitch)_n\(key.samplesPerOctave).json")
    }

    static func load(for key: OctaveSpectrumGridKey) -> OctaveSpectrumGrid? {
        guard let data = try? Data(contentsOf: cacheURL(for: key)) else { return nil }
        guard let grid = try? JSONDecoder().decode(OctaveSpectrumGrid.self, from: data), grid.key == key else { return nil }
        return grid
    }

    static func save(_ grid: OctaveSpectrumGrid) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(grid)
        try data.write(to: cacheURL(for: grid.key), options: .atomic)
    }
}
