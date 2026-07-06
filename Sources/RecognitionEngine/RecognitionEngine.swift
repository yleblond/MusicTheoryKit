import Foundation
import MusicTheoryKit

public struct RecognizedChord: Equatable, Sendable {
    public var root: PitchClass
    public var chordTemplateID: String
    public var bass: PitchClass
    /// Jaccard-style overlap between the held notes and the template's pitch-class set, in 0...1.
    public var confidence: Double

    public init(root: PitchClass, chordTemplateID: String, bass: PitchClass, confidence: Double) {
        self.root = root
        self.chordTemplateID = chordTemplateID
        self.bass = bass
        self.confidence = confidence
    }
}

public struct RecognizedMode: Equatable, Sendable {
    public var tonic: PitchClass
    public var scaleID: String
    /// Share of recently-played (decay-weighted) pitch classes that fit this scale, in 0...1.
    public var confidence: Double

    public init(tonic: PitchClass, scaleID: String, confidence: Double) {
        self.tonic = tonic
        self.scaleID = scaleID
        self.confidence = confidence
    }
}

/// Listens to a stream of note on/off events and, on demand, reports the chord currently
/// held down and the scale(s)/mode(s) that best explain what's been played recently.
///
/// Chords are read from literally-held notes (exact simultaneity). Modes are read from a
/// decayed history of recent note-ons — a scale is played melodically, not held — so each
/// pitch class's influence fades with an exponential half-life rather than being an
/// all-or-nothing "still down" flag.
public final class RecognitionEngine {
    private var heldPitches: Set<Int> = []
    private var lastNoteOnAt: [PitchClass: Date] = [:]
    private let modeHalfLife: TimeInterval

    public init(modeHalfLife: TimeInterval = 4.0) {
        self.modeHalfLife = modeHalfLife
    }

    public func noteOn(pitch: Int, at date: Date = Date()) {
        heldPitches.insert(pitch)
        lastNoteOnAt[PitchClass(pitch)] = date
    }

    public func noteOff(pitch: Int) {
        heldPitches.remove(pitch)
    }

    public func reset() {
        heldPitches.removeAll()
        lastNoteOnAt.removeAll()
    }

    /// The best-matching chord for the currently held-down notes, or nil if fewer than two
    /// notes are held or nothing clears `minimumConfidence`.
    public func recognizeChord(minimumConfidence: Double = 0.5) -> RecognizedChord? {
        let heldClasses = Set(heldPitches.map { PitchClass($0) })
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
        let bass = PitchClass(heldPitches.min() ?? best.root.value)
        return RecognizedChord(root: best.root, chordTemplateID: best.template.id, bass: bass, confidence: best.score)
    }

    /// The scale(s)/mode(s) that best cover the recently-played (decay-weighted) pitch
    /// classes, ranked by confidence then by fewest notes (the more specific candidate is
    /// listed first when two scales explain the notes equally well — e.g. a major scale
    /// and its relative minor share every pitch class).
    public func recognizeModes(
        at date: Date = Date(),
        activityThreshold: Double = 0.15,
        minimumConfidence: Double = 0.85,
        maxResults: Int = 3
    ) -> [RecognizedMode] {
        var weights: [PitchClass: Double] = [:]
        for pc in PitchClass.allCases {
            let weight = decayedWeight(for: pc, at: date)
            if weight >= activityThreshold { weights[pc] = weight }
        }
        guard !weights.isEmpty else { return [] }
        let totalWeight = weights.values.reduce(0, +)
        guard totalWeight > 0 else { return [] }

        var candidates: [(mode: RecognizedMode, noteCount: Int)] = []
        for rootValue in 0..<12 {
            let tonic = PitchClass(rootValue)
            for scale in ScaleLibrary.all {
                let scaleSet = Mode(tonic: tonic, scale: scale).pitchClassSet
                let matchedWeight = weights.reduce(into: 0.0) { acc, entry in
                    if scaleSet.contains(entry.key) { acc += entry.value }
                }
                let score = matchedWeight / totalWeight
                if score >= minimumConfidence {
                    candidates.append((RecognizedMode(tonic: tonic, scaleID: scale.id, confidence: score), scale.noteCount))
                }
            }
        }

        candidates.sort { lhs, rhs in
            if lhs.mode.confidence != rhs.mode.confidence { return lhs.mode.confidence > rhs.mode.confidence }
            return lhs.noteCount < rhs.noteCount
        }
        return candidates.prefix(maxResults).map(\.mode)
    }

    /// Exponential decay with half-life `modeHalfLife`: weight halves every `modeHalfLife`
    /// seconds since the pitch class's last note-on.
    private func decayedWeight(for pitchClass: PitchClass, at date: Date) -> Double {
        guard let lastHit = lastNoteOnAt[pitchClass] else { return 0 }
        let elapsed = date.timeIntervalSince(lastHit)
        guard elapsed > 0 else { return 1 }
        return exp(-elapsed * log(2) / modeHalfLife)
    }
}
