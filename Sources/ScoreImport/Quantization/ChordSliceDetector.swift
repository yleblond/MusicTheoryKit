import Foundation
import MusicTheoryKit
import PieceModel

/// Batch chord detection for an imported score: either mapping the source's own explicit chord
/// symbols (MusicXML/MuseScore `<harmony>`) directly, or — for MIDI, which has no such notion —
/// slicing the timeline into fixed windows and scoring each window's sounding pitch classes
/// against `ChordVocabulary`.
///
/// The scoring itself mirrors `RecognitionEngine.recognizeChord`'s Jaccard-overlap logic, but as
/// a pure, stateless function: `RecognitionEngine` is built around a live, mutable
/// `heldPitches: Set<Int>` for real-time input, not a batch pass over an already-known note
/// list, so its scoring loop is re-implemented here rather than instantiating that class.
public enum ChordSliceDetector {
    /// The best-matching chord for a set of simultaneously-sounding pitch classes, or nil if
    /// fewer than 2 classes are given or nothing clears `minimumConfidence`.
    public static func bestChord(
        forPitchClasses heldClasses: Set<PitchClass>, minimumConfidence: Double = 0.5
    ) -> (root: PitchClass, chordTemplateID: String, confidence: Double)? {
        guard heldClasses.count >= 2 else { return nil }
        var best: (root: PitchClass, template: ChordTemplate, score: Double)?
        for rootValue in 0..<12 {
            let root = PitchClass(rootValue)
            for template in ChordVocabulary.seed {
                let candidate = Set(template.intervalsFromRoot.map { root + $0 })
                let intersection = heldClasses.intersection(candidate).count
                let union = heldClasses.union(candidate).count
                let score = union == 0 ? 0 : Double(intersection) / Double(union)
                if best == nil || score > best!.score {
                    best = (root, template, score)
                }
            }
        }
        guard let best, best.score >= minimumConfidence else { return nil }
        return (best.root, best.template.id, best.score)
    }

    /// Slices `[0, totalTicks)` into fixed `sliceTicks`-wide windows, detects the best chord per
    /// *harmonically stable* window (a note counts as sounding in a window if it overlaps it at
    /// all), and merges consecutive windows that land on the same chord into one longer
    /// `ChordEvent`.
    ///
    /// A window is stable only if ≥3 distinct pitch classes sound in it — fewer than that and a
    /// single passing/neighbor tone can make 2 notes look like a "chord" that isn't one (the
    /// exact defect a music21-based analysis of a real piece hit: spurious labels like "V6532"
    /// on what was really just a passing tone over a held chord). An unstable window inherits
    /// the *previous stable window's* label (extending its `ChordEvent` rather than starting a
    /// new one) instead of being re-evaluated on its own, incomplete pitch-class set. A window
    /// with no PRECEDING stable window yet (or a stable window with no confident match) is
    /// simply skipped — a known v1 limitation (a chordless passage stays chordless rather than
    /// repeating a neighbor's chord).
    public static func detectChordProgression(
        notes: [(startTick: Int, durationTicks: Int, pitch: Int)],
        totalTicks: Int, sliceTicks: Int, ticksPerBeatUnit: Int, measureLengthTicks: Int
    ) -> [ChordEvent] {
        guard sliceTicks > 0, totalTicks > 0, ticksPerBeatUnit > 0 else { return [] }

        var merged: [(startTick: Int, endTick: Int, root: PitchClass, templateID: String)] = []
        var sliceStart = 0
        while sliceStart < totalTicks {
            let sliceEnd = min(sliceStart + sliceTicks, totalTicks)
            let sounding = Set(notes
                .filter { $0.startTick < sliceEnd && ($0.startTick + $0.durationTicks) > sliceStart }
                .map { PitchClass($0.pitch) })

            if sounding.count >= 3, let best = bestChord(forPitchClasses: sounding) {
                if let last = merged.last, last.root == best.root, last.templateID == best.chordTemplateID, last.endTick == sliceStart {
                    merged[merged.count - 1].endTick = sliceEnd
                } else {
                    merged.append((sliceStart, sliceEnd, best.root, best.chordTemplateID))
                }
            } else if let last = merged.last, last.endTick == sliceStart {
                // Unstable (or too-sparse) window right after a stable one — inherit its label
                // rather than guessing from an incomplete pitch-class set.
                merged[merged.count - 1].endTick = sliceEnd
            }
            sliceStart = sliceEnd
        }

        return merged.map { entry in
            let (measure, beat) = BeatQuantizer.measureBeat(forTick: entry.startTick, measureLengthTicks: measureLengthTicks, ticksPerBeatUnit: ticksPerBeatUnit)
            let durationBeats = Double(entry.endTick - entry.startTick) / Double(ticksPerBeatUnit)
            return ChordEvent(
                measure: measure, beat: beat, durationBeats: durationBeats,
                chord: ChordReference(root: entry.root.value, chordTemplateID: entry.templateID)
            )
        }
    }

    /// Best-effort mapping from MusicXML/MuseScore's own chord-quality vocabulary to a
    /// `ChordVocabulary` id — covers the MusicXML `<kind>` element's standard values (the
    /// MuseScore `.mscx` dialect uses similar jazz-notation words, close enough to reuse this
    /// same table when that parser lands). Falls back to a plain major triad ("Ma") for
    /// anything unrecognized, since some chord is more useful downstream than none — callers
    /// should surface a warning when this fallback is hit (see `RawScoreComposer`).
    public static func chordVocabularyID(forExplicitKind kind: String) -> String? {
        let table: [String: String] = [
            "major": "Ma", "minor": "mi", "augmented": "aug", "diminished": "dim",
            "dominant": "7", "major-seventh": "Ma7", "minor-seventh": "mi7",
            "diminished-seventh": "dim7", "augmented-seventh": "7#5", "half-diminished": "mi7b5",
            "major-minor": "miMa7", "major-sixth": "6", "minor-sixth": "mi6",
            "dominant-ninth": "9", "major-ninth": "Ma9", "minor-ninth": "mi9",
            "suspended-second": "sus2", "suspended-fourth": "sus4", "power": "5",
        ]
        return table[kind]
    }
}
