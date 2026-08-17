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

        // Common/simple modes preferred over the more exotic church modes when nothing else
        // breaks a tie — most pieces are major or (natural) minor, not dorian/phrygian/lydian/
        // mixolydian/locrian.
        let commonModeIDs: Set<String> = ["ionian", "aeolian"]

        var best: (tonic: PitchClass, scaleID: String, score: Double, noteCount: Int, tonicWeight: Double, isCommonMode: Bool)?
        for rootValue in 0..<12 {
            let tonic = PitchClass(rootValue)
            let tonicWeight = weights[tonic] ?? 0
            for scale in ScaleLibrary.all {
                let scaleSet = Mode(tonic: tonic, scale: scale).pitchClassSet
                let matchedWeight = weights.reduce(into: 0.0) { acc, entry in
                    if scaleSet.contains(entry.key) { acc += entry.value }
                }
                let score = matchedWeight / totalWeight
                let isCommonMode = commonModeIDs.contains(scale.id)
                let candidate = (tonic, scale.id, score, scale.noteCount, tonicWeight, isCommonMode)
                guard let current = best else { best = candidate; continue }
                // Ties (e.g. a major scale and every other mode sharing its exact pitch-class
                // set, such as the relative minor, or any other rotation of the same collection)
                // are broken by: (1) fewer notes in the scale — the more specific candidate, same
                // tie-break `RecognitionEngine.recognizeModes` already uses; (2) which candidate's
                // OWN tonic pitch class is held the longest in the piece — the strongest signal
                // for "this note is actually home," which a bare pitch-class-set match can't see
                // at all (all 7 rotations of one diatonic collection score identically otherwise);
                // (3) plain major/minor over the rarer church modes.
                if score > current.score
                    || (score == current.score && scale.noteCount < current.noteCount)
                    || (score == current.score && scale.noteCount == current.noteCount && tonicWeight > current.tonicWeight)
                    || (score == current.score && scale.noteCount == current.noteCount && tonicWeight == current.tonicWeight && isCommonMode && !current.isCommonMode) {
                    best = candidate
                }
            }
        }
        guard let best, best.score >= minimumConfidence else { return nil }
        return ModeReference(tonic: best.tonic.value, scaleID: best.scaleID)
    }
}
