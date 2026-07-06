import Accelerate

/// One pitch estimate: the raw detected frequency, plus the nearest MIDI note number
/// derived from it.
public struct DetectedPitch: Equatable, Sendable {
    public var frequencyHz: Double
    public var midiPitch: Int

    public init(frequencyHz: Double, midiPitch: Int) {
        self.frequencyHz = frequencyHz
        self.midiPitch = midiPitch
    }

    /// Nearest MIDI note number for a frequency in Hz (A4 = 440Hz = MIDI 69), rounded to
    /// the closest semitone — no microtonal/cents tracking.
    public static func midiPitch(forFrequencyHz frequencyHz: Double) -> Int {
        Int((69.0 + 12.0 * log2(frequencyHz / 440.0)).rounded())
    }
}

/// Estimates dominant frequencies in a fixed-size window of audio samples via FFT
/// (Accelerate/vDSP): a Hann-windowed magnitude spectrum, peak-bin search restricted to a
/// plausible musical range, then parabolic interpolation across each peak's neighboring
/// bins for sub-bin frequency resolution.
///
/// **Known limitations, deliberately not solved here**: this is simple peak-picking, not a
/// harmonic-aware pitch tracker. For a tone with a weak fundamental and a strong second
/// harmonic (some instruments/registers), it can lock onto the harmonic instead of the true
/// fundamental — a real, occasionally-audible inaccuracy. `dominantFrequencies` extends this
/// to multiple simultaneous peaks (a step toward "detect a chord") but is still a heuristic,
/// not real multi-pitch estimation: a genuine chord's higher harmonics routinely land close
/// to (or exactly on) another note's fundamental, which can both manufacture phantom extra
/// "notes" from one loud tone's harmonic series and, more often, correctly-but-coincidentally
/// detect a real chord tone that's also a harmonic. Distinguishing "this peak is a
/// fundamental" from "this peak is another note's harmonic" would need real harmonic
/// analysis (comparing candidate fundamentals against the full harmonic series, or a
/// harmonic product spectrum) — real complexity, out of scope for a first version. Treat
/// multi-peak results as "the most prominent pitches in the sound right now", not a
/// guaranteed note list.
public final class FFTPitchAnalyzer {
    public let size: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private var window: [Float]
    private let realp: UnsafeMutablePointer<Float>
    private let imagp: UnsafeMutablePointer<Float>

    /// `size` must be a power of two (this is a radix-2 real FFT) — 4096 at a typical
    /// 44.1kHz input rate is ~93ms per analysis window, a reasonable latency/accuracy
    /// tradeoff for note detection (low frequencies need enough samples to resolve).
    public init(size: Int) {
        precondition(size > 0 && (size & (size - 1)) == 0, "FFT size must be a power of two, got \(size)")
        self.size = size
        log2n = vDSP_Length(log2(Double(size)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        realp = .allocate(capacity: size / 2)
        imagp = .allocate(capacity: size / 2)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
        realp.deallocate()
        imagp.deallocate()
    }

    /// Minimum RMS level (see `rms(of:)`) for detection to even be attempted. Exposed so a
    /// caller can compare a live level reading against the exact value gating detection,
    /// instead of guessing why nothing is being detected.
    public static let minimumRMSForDetection: Float = 0.003

    /// Root-mean-square level of `samples` — the raw signal energy, independent of any
    /// FFT/pitch analysis. Useful on its own as a simple "is anything even reaching the
    /// input" meter, distinct from "was a clear pitch found" (a signal can be well above
    /// the noise floor and still not resolve to a confident pitch, e.g. percussive/noisy
    /// sounds) — surfacing this separately is what makes "no pitch detected" diagnosable
    /// instead of just a silent dead end.
    public static func rms(of samples: [Float]) -> Float {
        var sumOfSquares: Float = 0
        vDSP_svesq(samples, 1, &sumOfSquares, vDSP_Length(samples.count))
        return (sumOfSquares / Float(samples.count)).squareRoot()
    }

    /// Windows, FFTs, and returns the magnitude spectrum (length `size / 2`) — or `nil` if
    /// `samples` is the wrong length or too quiet (see `rms(of:)`/`minimumRMSForDetection`).
    /// Shared by `dominantFrequency` and `dominantFrequencies` so the actual FFT only
    /// happens once per window regardless of how many peaks the caller wants out of it.
    private func magnitudeSpectrum(of samples: [Float]) -> [Float]? {
        guard samples.count == size else { return nil }
        guard Self.rms(of: samples) > Self.minimumRMSForDetection else { return nil }

        var windowed = [Float](repeating: 0, count: size)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(size))

        var splitComplex = DSPSplitComplex(realp: realp, imagp: imagp)
        windowed.withUnsafeBufferPointer { pointer in
            pointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) { complexPointer in
                vDSP_ctoz(complexPointer, 2, &splitComplex, 1, vDSP_Length(size / 2))
            }
        }
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

        var magnitudes = [Float](repeating: 0, count: size / 2)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(size / 2))
        return magnitudes
    }

    /// Parabolic interpolation across `bin` and its two neighbors, for sub-bin frequency
    /// resolution (a single FFT bin alone is much coarser than one semitone at low
    /// frequencies). `bin` must be strictly between the first and last index of `magnitudes`.
    private func interpolatedFrequency(forPeakBin bin: Int, magnitudes: [Float], binHz: Double) -> Double {
        let alpha = Double(magnitudes[bin - 1])
        let beta = Double(magnitudes[bin])
        let gamma = Double(magnitudes[bin + 1])
        let denominator = alpha - 2 * beta + gamma
        let offset = denominator != 0 ? 0.5 * (alpha - gamma) / denominator : 0
        return (Double(bin) + offset) * binHz
    }

    /// Returns the estimated fundamental frequency in Hz, or `nil` when `samples` is too
    /// quiet/noisy for a confident estimate (including plain silence), or when
    /// `samples.count` doesn't match `size`. Equivalent to the strongest entry of
    /// `dominantFrequencies(maxPeaks: 1)`.
    public func dominantFrequency(in samples: [Float], sampleRate: Double, minHz: Double = 60, maxHz: Double = 2000) -> Double? {
        dominantFrequencies(in: samples, sampleRate: sampleRate, minHz: minHz, maxHz: maxHz, maxPeaks: 1).first
    }

    /// Returns up to `maxPeaks` distinct dominant frequencies (Hz), strongest first — a
    /// step toward "detect a chord" rather than only ever the single loudest note. Each
    /// candidate is a genuine local maximum in the magnitude spectrum (not just among the
    /// globally loudest bins, which would often just be several adjacent bins of the *same*
    /// spectral lobe), gated the same way a single-peak search would (edge-leakage
    /// rejection, standing out from the band average), and thinned so no two accepted peaks
    /// are closer than `minSemitoneSeparation` apart — without this, one note's main lobe
    /// can register as two or three "different" close-together peaks. See the type's doc
    /// comment for why this is a heuristic, not real multi-pitch estimation.
    public func dominantFrequencies(
        in samples: [Float],
        sampleRate: Double,
        minHz: Double = 60,
        maxHz: Double = 2000,
        maxPeaks: Int = 6,
        minSemitoneSeparation: Double = 0.5
    ) -> [Double] {
        guard let magnitudes = magnitudeSpectrum(of: samples) else { return [] }

        let binHz = sampleRate / Double(size)
        let minBin = max(1, Int(minHz / binHz))
        let maxBin = min(magnitudes.count - 2, Int(maxHz / binHz))
        guard minBin < maxBin else { return [] }

        let band = magnitudes[minBin...maxBin]
        let bandAverage = band.reduce(0, +) / Float(band.count)
        guard bandAverage > 0 else { return [] }

        var candidates: [(bin: Int, magnitude: Float)] = []
        for bin in minBin...maxBin {
            // A genuine local maximum: strictly louder than both immediate neighbors (using
            // `>`, not `>=`, so a flat run of equal values doesn't register every position
            // in it as its own "peak").
            guard magnitudes[bin] > magnitudes[bin - 1], magnitudes[bin] > magnitudes[bin + 1] else { continue }
            // Spectral-shape gate: must clearly stand out from the band's average energy —
            // not just be *a* real tone somewhere (the RMS gate already ruled out silence),
            // but specifically a real tone within [minHz, maxHz].
            guard magnitudes[bin] > 8 * bandAverage else { continue }
            // Edge-leakage gate: see `dominantFrequency`'s original version of this check —
            // a loud tone just outside the range can leak a decaying tail whose strongest
            // in-band point sits right at the boundary; if the very next bin *outside* the
            // range (still readable — `magnitudes` covers the whole spectrum) is louder, the
            // real source is out of band.
            if bin == minBin, magnitudes[minBin - 1] > magnitudes[bin] { continue }
            if bin == maxBin, magnitudes[maxBin + 1] > magnitudes[bin] { continue }
            candidates.append((bin, magnitudes[bin]))
        }

        candidates.sort { $0.magnitude > $1.magnitude }

        let separationRatio = pow(2.0, minSemitoneSeparation / 12.0)
        var accepted: [Double] = []
        for candidate in candidates {
            guard accepted.count < maxPeaks else { break }
            let frequency = interpolatedFrequency(forPeakBin: candidate.bin, magnitudes: magnitudes, binHz: binHz)
            let tooCloseToAnAlreadyAcceptedPeak = accepted.contains { existing in
                max(frequency, existing) / min(frequency, existing) < separationRatio
            }
            guard !tooCloseToAnAlreadyAcceptedPeak else { continue }
            accepted.append(frequency)
        }
        return accepted
    }
}
