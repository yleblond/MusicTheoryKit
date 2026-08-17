import Foundation
import MusicTheoryKit
import PieceModel

/// Batch key/mode detection for an imported score — nothing like this existed anywhere in the
/// codebase before (confirmed during the score-import feasibility research). This is a v1
/// heuristic, NOT real Krumhansl-Schmuckler-style key-finding: a duration-weighted pitch-class
/// histogram scored against every `(tonic, scale)` pair in `ScaleLibrary`, mirroring
/// `RecognitionEngine.recognizeModes`'s own scoring shape (matched weight / total weight) but
/// over a static histogram instead of a live decayed-weight map. Expected to misfire on
/// genuinely ambiguous or chromatic material — refine if real imported files show that.
public enum KeyModeDetector {
    /// `notes` pairs each sounding pitch with how long it sounds (ticks, or any consistent
    /// weight unit) — a long held tonic note should outweigh a passing sixteenth, so duration
    /// is the weight, not raw note count.
    public static func detect(notes: [(pitch: Int, durationTicks: Int)], minimumConfidence: Double = 0.7) -> ModeReference? {
        guard !notes.isEmpty else { return nil }

        var weights: [PitchClass: Double] = [:]
        for note in notes {
            weights[PitchClass(note.pitch), default: 0] += Double(max(note.durationTicks, 1))
        }
        let totalWeight = weights.values.reduce(0, +)
        guard totalWeight > 0 else { return nil }

        var best: (tonic: PitchClass, scaleID: String, score: Double, noteCount: Int)?
        for rootValue in 0..<12 {
            let tonic = PitchClass(rootValue)
            for scale in ScaleLibrary.all {
                let scaleSet = Mode(tonic: tonic, scale: scale).pitchClassSet
                let matchedWeight = weights.reduce(into: 0.0) { acc, entry in
                    if scaleSet.contains(entry.key) { acc += entry.value }
                }
                let score = matchedWeight / totalWeight
                // Ties (e.g. a major scale and its relative minor cover identical pitch
                // classes) prefer the scale with fewer notes — the more specific candidate —
                // same tie-break RecognitionEngine.recognizeModes already uses.
                if best == nil || score > best!.score || (score == best!.score && scale.noteCount < best!.noteCount) {
                    best = (tonic, scale.id, score, scale.noteCount)
                }
            }
        }
        guard let best, best.score >= minimumConfidence else { return nil }
        return ModeReference(tonic: best.tonic.value, scaleID: best.scaleID)
    }
}
