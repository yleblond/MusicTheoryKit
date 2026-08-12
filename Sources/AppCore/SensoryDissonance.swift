import Foundation

/// A single sinusoidal component of a real, analyzed instrument spectrum — one partial's
/// frequency and its own amplitude (see `FFTPitchAnalyzer.dominantPartials`, which is where
/// these actually come from: a real captured/rendered note, not an idealized harmonic series).
public struct SpectralPartial: Equatable, Sendable, Codable {
    public let frequencyHz: Double
    public let amplitude: Double

    public init(frequencyHz: Double, amplitude: Double) {
        self.frequencyHz = frequencyHz
        self.amplitude = amplitude
    }
}

/// William Sethares' sensory dissonance ("roughness") model (JASA 1993, *Tuning, Timbre,
/// Spectrum, Scale*) — quantifies the perceptual roughness between two sinusoidal partials as
/// a function of their frequency separation, via the Plomp-Levelt consonance curve encoded as a
/// difference of two exponentials. Used here to score a full chord's REAL, measured spectrum
/// (see `OctaveSpectrumGrid`) rather than an idealized harmonic approximation — the whole point
/// of the Dissonances screen.
///
/// Constants (`b1`/`b2`/`s1`/`s2`/`dStar`) are the version of this formula widely republished in
/// computer-music literature and reference implementations of Sethares' own dissonance-curve
/// software — not verified character-for-character against the original 1993 JASA paper or
/// *Tuning, Timbre, Spectrum, Scale* itself (their exact typeset formulas live in the PDF/book,
/// not the plain-text pages this was sourced from). Revisit if a plotted curve doesn't match the
/// shape of Sethares' own published dissonance curves (single sharp peak near unison, smooth
/// decay, near-zero past roughly a critical bandwidth).
public enum SensoryDissonance {
    private static let b1 = 3.5
    private static let b2 = 5.75
    private static let s1 = 0.0207
    private static let s2 = 18.96
    private static let dStar = 0.24

    /// Roughness contributed by one pair of partials (one from each tone, or from the same
    /// tone — this function doesn't care which) — zero when the two frequencies coincide
    /// exactly (`deltaF == 0` collapses both exponentials to 1), rising to a peak at a small
    /// separation, then decaying back toward zero as the separation grows well past what the
    /// ear treats as "the same critical band" — the Plomp-Levelt shape.
    public static func pairwiseDissonance(f1: Double, a1: Double, f2: Double, a2: Double) -> Double {
        guard f1 > 0, f2 > 0 else { return 0 }
        let fmin = min(f1, f2)
        let s = dStar / (s1 * fmin + s2)
        let deltaF = abs(f2 - f1)
        return a1 * a2 * (exp(-b1 * s * deltaF) - exp(-b2 * s * deltaF))
    }

    /// Total roughness between two complex tones — sums `pairwiseDissonance` over every CROSS
    /// pair (one partial from `toneA`, one from `toneB`). Deliberately excludes pairs drawn
    /// from the SAME tone: those don't depend on how `toneA`/`toneB` relate to each other, so
    /// they'd only ever add a constant offset to a dissonance landscape swept over their
    /// relative frequency — not part of what makes one interval more consonant than another.
    public static func dissonance(between toneA: [SpectralPartial], and toneB: [SpectralPartial]) -> Double {
        var total = 0.0
        for partialA in toneA {
            for partialB in toneB {
                total += pairwiseDissonance(f1: partialA.frequencyHz, a1: partialA.amplitude, f2: partialB.frequencyHz, a2: partialB.amplitude)
            }
        }
        return total
    }

    /// Total roughness of a whole chord (2 or more real tones) — sums `dissonance(between:and:)`
    /// over every distinct PAIR OF TONES (not every pair of individual partials across the
    /// whole chord at once, which would double-count and also mix in same-tone pairs). For a
    /// triad (root + 2 swept notes) this is exactly the 3 pairs `dissonance` sweeps a landscape
    /// over: root-note2, root-note3, note2-note3.
    public static func totalDissonance(ofTones tones: [[SpectralPartial]]) -> Double {
        guard tones.count > 1 else { return 0 }
        var total = 0.0
        for i in 0..<(tones.count - 1) {
            for j in (i + 1)..<tones.count {
                total += dissonance(between: tones[i], and: tones[j])
            }
        }
        return total
    }
}
