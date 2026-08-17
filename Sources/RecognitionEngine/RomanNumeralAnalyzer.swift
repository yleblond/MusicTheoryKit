import Foundation

/// Whether a `RomanNumeralLabel` is well-determined (diatonic, or a confirmed secondary
/// dominant/applied leading tone) or a generic chromatic fallback that likely needs a human's
/// eye — surfaced in the UI as a "review this" marker rather than silently presented as fact.
public enum RomanNumeralConfidence: Equatable, Sendable {
    case high
    case low
}

public struct RomanNumeralLabel: Equatable, Sendable {
    public let numeral: String
    public let confidence: RomanNumeralConfidence

    public init(numeral: String, confidence: RomanNumeralConfidence) {
        self.numeral = numeral
        self.confidence = confidence
    }
}

/// Roman-numeral functional analysis for one already-detected chord (root + `ChordVocabulary`
/// template id), relative to a key context — reimplements, in Swift, the "heuristic layer" a
/// music21-based analysis needed manual correction for (see the harmonic-analysis feature's own
/// planning notes): music21's own stacked-thirds chord guessing gets the chord template right on
/// complete chords but has no notion of scale-degree function or secondary dominants at all.
///
/// Pure and `PieceModel`-agnostic (same precedent as `PitchDisplayState.swift` in this module) —
/// everything is plain pitch-class integers, so a caller elsewhere (e.g. `AppCore`) does the
/// `ChordReference`/`ModeReference` unwrapping rather than this module taking on that
/// dependency.
public enum RomanNumeralAnalyzer {
    private static let romanNumerals = ["I", "II", "III", "IV", "V", "VI", "VII"]

    /// Chord qualities that can plausibly function as a secondary DOMINANT (resolving down a
    /// perfect fifth to their target) when their root isn't the plain diatonic expectation.
    private static let dominantFunctionTemplates: Set<String> = ["Ma", "7"]
    /// Chord qualities that can plausibly function as an applied LEADING TONE (resolving up a
    /// half step to their target) — the "sensible secondaire" chords in the reference analysis.
    private static let leadingToneFunctionTemplates: Set<String> = ["dim", "dim7", "mi7b5"]

    /// - Parameters:
    ///   - chordRoot: absolute pitch class (any integer; normalized mod 12) of the chord's root.
    ///   - chordTemplateID: a `ChordVocabulary` id (e.g. `"Ma"`, `"mi7"`, `"dim7"`).
    ///   - keyTonic: the key's tonic pitch class.
    ///   - modeTones: the key's own pitch classes in scale-degree order (index 0 = tonic) — e.g.
    ///     `Mode.pitchClasses` already gives exactly this shape.
    ///   - lookahead: the next few stable chords' roots, nearest first, used to confirm a
    ///     secondary dominant/applied leading tone by where the progression actually goes next.
    ///     More than one entry deliberately tolerates a decorative chord (most commonly a
    ///     cadential 6/4 built on the tonic) landing between the secondary chord and its real
    ///     target — the exact case that produced `G#m7(b5) → viiø7/V` in the reference analysis,
    ///     where the immediately-next stable chord is a passing tonic, not the V itself.
    public static func label(
        chordRoot: Int, chordTemplateID: String,
        keyTonic: Int, modeTones: [Int],
        lookahead: [Int]
    ) -> RomanNumeralLabel {
        let rootPC = normalizePitchClass(chordRoot)

        if let match = closestDegree(forPitchClass: rootPC, modeTones: modeTones), match.alteration == 0 {
            let expectedQuality = diatonicTriadQuality(forDegreeIndex: match.degree - 1, modeTones: modeTones)
            if isCompatible(detected: chordTemplateID, expectedQuality: expectedQuality, degreeIndex: match.degree - 1) {
                return RomanNumeralLabel(numeral: numeralString(degree: match.degree, alteration: 0, templateID: chordTemplateID), confidence: .high)
            }
        }

        // Not a plain diatonic chord (either a chromatic root, or a diatonic root whose quality
        // doesn't match what's diatonically expected there, e.g. a "7"-quality chord on a
        // non-dominant scale degree) — test secondary dominant / applied leading tone.
        let normalizedLookahead = lookahead.map(normalizePitchClass)
        if dominantFunctionTemplates.contains(chordTemplateID) {
            let target = normalizePitchClass(rootPC - 7) // resolves down a perfect fifth
            if normalizedLookahead.contains(target), let targetDegree = closestDegree(forPitchClass: target, modeTones: modeTones), targetDegree.alteration == 0 {
                return RomanNumeralLabel(numeral: "\(secondaryDominantPrefix(templateID: chordTemplateID))/\(denominatorLabel(forDegreeIndex: targetDegree.degree - 1, modeTones: modeTones))", confidence: .high)
            }
        }
        if leadingToneFunctionTemplates.contains(chordTemplateID) {
            let target = normalizePitchClass(rootPC + 1) // resolves up a half step
            if normalizedLookahead.contains(target), let targetDegree = closestDegree(forPitchClass: target, modeTones: modeTones), targetDegree.alteration == 0 {
                return RomanNumeralLabel(numeral: "\(secondaryLeadingTonePrefix(templateID: chordTemplateID))/\(denominatorLabel(forDegreeIndex: targetDegree.degree - 1, modeTones: modeTones))", confidence: .high)
            }
        }

        // Generic chromatic fallback — labeled by nearest scale degree + alteration, but flagged
        // low-confidence for the UI: this is exactly the layer that needs a human's eye.
        let fallback = closestDegree(forPitchClass: rootPC, modeTones: modeTones) ?? (degree: 1, alteration: 0)
        return RomanNumeralLabel(numeral: numeralString(degree: fallback.degree, alteration: fallback.alteration, templateID: chordTemplateID), confidence: .low)
    }

    // MARK: - Scale degree lookup

    private static func normalizePitchClass(_ value: Int) -> Int {
        ((value % 12) + 12) % 12
    }

    /// Nearest scale degree by signed semitone distance (wrapped into `-6...6`) — `alteration`
    /// is 0 exactly when `pitchClass` IS one of `modeTones` (a real diatonic degree); otherwise
    /// it's the signed offset from the nearest one (`+1` = raised, e.g. `#4`; `-1` = lowered).
    private static func closestDegree(forPitchClass pitchClass: Int, modeTones: [Int]) -> (degree: Int, alteration: Int)? {
        guard !modeTones.isEmpty else { return nil }
        var best: (index: Int, delta: Int)?
        for (index, tone) in modeTones.enumerated() {
            var delta = pitchClass - normalizePitchClass(tone)
            while delta > 6 { delta -= 12 }
            while delta <= -6 { delta += 12 }
            if best == nil || abs(delta) < abs(best!.delta) { best = (index, delta) }
        }
        guard let best else { return nil }
        return (best.index + 1, best.delta)
    }

    /// The triad quality a scale degree is expected to carry, derived by stacking thirds
    /// WITHIN the scale itself (degree, degree+2, degree+4, wrapping) rather than a hardcoded
    /// major/minor table — generalizes to any 7-tone mode in `ScaleLibrary`.
    private static func diatonicTriadQuality(forDegreeIndex index: Int, modeTones: [Int]) -> String {
        guard modeTones.count == 7 else { return "Ma" }
        let root = modeTones[index]
        let third = modeTones[(index + 2) % 7]
        let fifth = modeTones[(index + 4) % 7]
        let firstInterval = normalizePitchClass(third - root)
        let secondInterval = normalizePitchClass(fifth - third)
        switch (firstInterval, secondInterval) {
        case (4, 3): return "Ma"
        case (3, 4): return "mi"
        case (3, 3): return "dim"
        case (4, 4): return "aug"
        default: return "Ma"
        }
    }

    /// A detected chord template is "diatonically compatible" with a degree's expected triad
    /// quality if it's that quality itself, or a conventional diatonic extension of it — EXCEPT
    /// a dominant-seventh quality (`"7"`) is only a normal diatonic extension of a MAJOR-quality
    /// degree when that degree is actually V (`degreeIndex == 4`); a "7"-quality chord anywhere
    /// else always implies a secondary/applied dominant, by definition of what "7" quality means
    /// in tonal harmony (e.g. a `D7` chord in D major isn't "I7", it's `V7/IV`).
    private static func isCompatible(detected: String, expectedQuality: String, degreeIndex: Int) -> Bool {
        switch expectedQuality {
        case "Ma":
            if detected == "Ma" { return true }
            return detected == "7" && degreeIndex == 4
        case "mi":
            return detected == "mi" || detected == "mi7"
        case "dim":
            return detected == "dim" || detected == "dim7" || detected == "mi7b5"
        case "aug":
            return detected == "aug" || detected == "7#5"
        default:
            return detected == expectedQuality
        }
    }

    // MARK: - Formatting

    private static func numeralString(degree: Int, alteration: Int, templateID: String) -> String {
        let base = romanNumerals[degree - 1]
        let alterationPrefix = alteration > 0 ? String(repeating: "#", count: alteration) : (alteration < 0 ? String(repeating: "b", count: -alteration) : "")
        switch templateID {
        case "Ma": return alterationPrefix + base
        case "mi", "miMa7": return alterationPrefix + base.lowercased()
        case "dim": return alterationPrefix + base.lowercased() + "\u{b0}"
        case "dim7": return alterationPrefix + base.lowercased() + "\u{b0}7"
        case "mi7b5": return alterationPrefix + base.lowercased() + "\u{f8}7"
        case "aug": return alterationPrefix + base + "+"
        case "7#5": return alterationPrefix + base + "+7"
        case "Ma7#5": return alterationPrefix + base + "+Ma7"
        case "Ma7": return alterationPrefix + base + "Ma7"
        case "mi7": return alterationPrefix + base.lowercased() + "7"
        case "7": return alterationPrefix + base + "7"
        default: return alterationPrefix + base
        }
    }

    private static func secondaryDominantPrefix(templateID: String) -> String {
        templateID == "7" ? "V7" : "V"
    }

    private static func secondaryLeadingTonePrefix(templateID: String) -> String {
        switch templateID {
        case "dim7": return "vii\u{b0}7"
        case "mi7b5": return "vii\u{f8}7"
        default: return "vii\u{b0}"
        }
    }

    /// The denominator of a secondary label (e.g. the `"vi"` in `V7/vi`) is cased/decorated by
    /// that target degree's OWN diatonic quality in `K` — a major-quality target reads `V`, a
    /// minor-quality one reads lowercase `vi`, matching standard notation convention.
    private static func denominatorLabel(forDegreeIndex index: Int, modeTones: [Int]) -> String {
        let quality = diatonicTriadQuality(forDegreeIndex: index, modeTones: modeTones)
        let base = romanNumerals[index]
        switch quality {
        case "mi": return base.lowercased()
        case "dim": return base.lowercased() + "\u{b0}"
        case "aug": return base + "+"
        default: return base
        }
    }
}
