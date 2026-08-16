import Foundation
import AudioEngine
import SoundFontModel

/// The raw Hann-windowed FFT magnitude spectrum for one rendered note — see
/// `FFTPitchAnalyzer.spectrumSnapshot`'s own doc comment. Deliberately NOT part of
/// `OctaveSpectrumGrid` (which only ever keeps `dominantPartials`' reduced peak list, the data
/// `SensoryDissonance` actually needs): this is purely for a caller that wants to SHOW the full
/// spectrum of a specific, currently-of-interest note (e.g. the Dissonances screen's optional
/// spectrum panel) — ephemeral, computed on demand for whichever notes are currently selected,
/// not cached to disk.
public struct RawNoteSpectrum: Sendable {
    public let magnitudes: [Float]
    public let binHz: Double

    public init(magnitudes: [Float], binHz: Double) {
        self.magnitudes = magnitudes
        self.binHz = binHz
    }
}

public enum RawSpectrumRenderer {
    /// Renders each `(pitch, cents)` pair with the SAME instrument (one `OfflineNoteRenderer`
    /// load, reused across all of them — loading the sample is the expensive part) and returns
    /// its own raw magnitude spectrum, in the same order. Uses the exact same render duration/
    /// attack-skip/FFT window convention as `OctaveSpectrumGridBuilder.build`, so a note shown
    /// here is analyzed under the same conditions as the ones baked into the dissonance
    /// landscape — just without reducing the result to `dominantPartials` afterward. `async` —
    /// routes through `OfflineRenderQueue` so it can never run concurrently with another offline
    /// render (an octave-grid build, another call to this function for a different chord, or a
    /// rapid re-selection racing itself) — see that type's own doc comment for the crash this
    /// fixes.
    public static func render(
        pitches: [(pitch: Int, cents: Double)], soundFontURL: URL, preset: SoundFontPresetIdentity?
    ) async throws -> [RawNoteSpectrum] {
        try await OfflineRenderQueue.shared.run {
            let renderer = try OfflineNoteRenderer()
            try renderer.loadSample(at: soundFontURL, preset: preset)
            return try render(pitches: pitches, renderer: renderer)
        }
    }

    /// Renders `pitches` TOGETHER as one chord (see `OfflineNoteRenderer.renderChord`'s own doc
    /// comment) TWICE — once with every `cents` forced to 0 ("raw", i.e. the chord exactly as the
    /// instrument provides it) and once with each pitch's own real `cents` (the same mode's
    /// temperament correction, per tone) — and returns ONE consolidated spectrum pair for the
    /// WHOLE chord, instead of one pair per tone. This is what lets a chord's comparison show as
    /// two curves (like a single note's) rather than 2×N — the tradeoff: since a chord's tones
    /// aren't each individually identifiable in a mixed FFT, this can't show which specific
    /// harmonic belongs to which tone, only how the chord's overall spectral shape shifts between
    /// the two tunings.
    public static func renderChord(
        pitches: [(pitch: Int, cents: Double)], soundFontURL: URL, preset: SoundFontPresetIdentity?
    ) async throws -> (raw: RawNoteSpectrum, corrected: RawNoteSpectrum) {
        try await OfflineRenderQueue.shared.run {
            let renderer = try OfflineNoteRenderer()
            try renderer.loadSample(at: soundFontURL, preset: preset)
            return try renderChord(pitches: pitches, renderer: renderer)
        }
    }

    /// The actual render-both-versions logic, factored out from
    /// `renderChord(pitches:soundFontURL:preset:)` so a test can drive it against an
    /// `OfflineNoteRenderer` that never had `loadSample` called — same reasoning as
    /// `render(pitches:renderer:)`'s own analogous split.
    static func renderChord(pitches: [(pitch: Int, cents: Double)], renderer: OfflineNoteRenderer) throws -> (raw: RawNoteSpectrum, corrected: RawNoteSpectrum) {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let skipSamples = Int(OctaveSpectrumGridBuilder.attackSkipSeconds * renderer.sampleRate)
        func snapshot(cents: [Double]) throws -> RawNoteSpectrum {
            let entries = zip(pitches, cents).map { (pitch: $0.0.pitch, cents: $0.1) }
            let samples = try renderer.renderChord(pitches: entries, durationSeconds: OctaveSpectrumGridBuilder.renderDurationSeconds)
            let windowStart = min(skipSamples, max(0, samples.count - analyzer.size))
            var window = Array(samples[windowStart..<min(windowStart + analyzer.size, samples.count)])
            if window.count < analyzer.size { window += [Float](repeating: 0, count: analyzer.size - window.count) }
            guard let result = analyzer.spectrumSnapshot(of: window, sampleRate: renderer.sampleRate) else {
                return RawNoteSpectrum(magnitudes: [], binHz: 0)
            }
            return RawNoteSpectrum(magnitudes: result.magnitudes, binHz: result.binHz)
        }
        let raw = try snapshot(cents: pitches.map { _ in 0 })
        let corrected = try snapshot(cents: pitches.map(\.cents))
        return (raw, corrected)
    }

    /// The actual render-every-pitch loop, factored out from `render(pitches:soundFontURL:preset:)`
    /// so a test can drive it against an `OfflineNoteRenderer` that never had `loadSample` called
    /// (exercising `AVAudioUnitSampler`'s own built-in default instrument) — same reasoning as
    /// `OctaveSpectrumGridBuilder.build`'s own analogous split.
    static func render(pitches: [(pitch: Int, cents: Double)], renderer: OfflineNoteRenderer) throws -> [RawNoteSpectrum] {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let skipSamples = Int(OctaveSpectrumGridBuilder.attackSkipSeconds * renderer.sampleRate)

        return try pitches.map { entry in
            let samples = try renderer.renderNote(pitch: entry.pitch, cents: entry.cents, durationSeconds: OctaveSpectrumGridBuilder.renderDurationSeconds)
            let windowStart = min(skipSamples, max(0, samples.count - analyzer.size))
            var window = Array(samples[windowStart..<min(windowStart + analyzer.size, samples.count)])
            if window.count < analyzer.size { window += [Float](repeating: 0, count: analyzer.size - window.count) }
            guard let snapshot = analyzer.spectrumSnapshot(of: window, sampleRate: renderer.sampleRate) else {
                return RawNoteSpectrum(magnitudes: [], binHz: 0)
            }
            return RawNoteSpectrum(magnitudes: snapshot.magnitudes, binHz: snapshot.binHz)
        }
    }
}
