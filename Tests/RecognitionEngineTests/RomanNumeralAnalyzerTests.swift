import XCTest
@testable import RecognitionEngine

/// D major's own pitch classes in scale-degree order (index 0 = tonic D) — the `modeTones` shape
/// `RomanNumeralAnalyzer` expects, matching `Mode.pitchClasses` for D major.
private let dMajorTones = [2, 4, 6, 7, 9, 11, 1] // D E F# G A B C#
private let aMinorTones = [9, 11, 0, 2, 4, 5, 7] // A B C D E F G

final class RomanNumeralAnalyzerTests: XCTestCase {

    // MARK: - Plain diatonic

    func testTonicTriadInMajorIsUppercaseI() {
        let label = RomanNumeralAnalyzer.label(chordRoot: 2, chordTemplateID: "Ma", keyTonic: 2, modeTones: dMajorTones, lookahead: [])
        XCTAssertEqual(label.numeral, "I")
        XCTAssertEqual(label.confidence, .high)
    }

    func testSupertonicTriadInMajorIsLowercaseIi() {
        let label = RomanNumeralAnalyzer.label(chordRoot: 4, chordTemplateID: "mi", keyTonic: 2, modeTones: dMajorTones, lookahead: [])
        XCTAssertEqual(label.numeral, "ii")
    }

    func testLeadingToneTriadInMajorIsDiminished() {
        // C# (degree vii, index 6) in D major is diatonically a diminished triad.
        let label = RomanNumeralAnalyzer.label(chordRoot: 1, chordTemplateID: "dim", keyTonic: 2, modeTones: dMajorTones, lookahead: [])
        XCTAssertEqual(label.numeral, "vii\u{b0}")
    }

    func testDominantSeventhOnVIsOrdinaryDiatonicV7() {
        // A7 (the V7 of D major) is a completely ordinary diatonic dominant seventh, not a
        // secondary function — must NOT get routed to secondary-dominant testing.
        let label = RomanNumeralAnalyzer.label(chordRoot: 9, chordTemplateID: "7", keyTonic: 2, modeTones: dMajorTones, lookahead: [2])
        XCTAssertEqual(label.numeral, "V7")
        XCTAssertEqual(label.confidence, .high)
    }

    func testMinorSeventhOnViIsOrdinaryDiatonicVi7() {
        // Bm7 (m.9 in the reference analysis) — a diatonic vi7, not a secondary function.
        let label = RomanNumeralAnalyzer.label(chordRoot: 11, chordTemplateID: "mi7", keyTonic: 2, modeTones: dMajorTones, lookahead: [9])
        XCTAssertEqual(label.numeral, "vi7")
        XCTAssertEqual(label.confidence, .high)
    }

    func testTonicTriadInMinorIsLowercaseI() {
        let label = RomanNumeralAnalyzer.label(chordRoot: 9, chordTemplateID: "mi", keyTonic: 9, modeTones: aMinorTones, lookahead: [])
        XCTAssertEqual(label.numeral, "i")
    }

    // MARK: - Chromatic, no confirmed secondary function

    func testUnconfirmedChromaticRootIsLowConfidence() {
        // A root a half step above the tonic (D#, not diatonic in D major) with no lookahead
        // confirming any secondary function — generic chromatic fallback, flagged low confidence.
        let label = RomanNumeralAnalyzer.label(chordRoot: 3, chordTemplateID: "Ma", keyTonic: 2, modeTones: dMajorTones, lookahead: [])
        XCTAssertEqual(label.confidence, .low)
    }

    func testAugmentedSeventhOnDiatonicRootWithNoConfirmedTargetIsChromaticLowConfidence() {
        // G+7 (m.22): root G IS diatonic (degree IV) but "7#5" quality isn't a diatonic
        // extension of a major-quality degree — falls through to the chromatic fallback, which
        // (since G's root already exactly matches degree IV) labels it "IV+7", low confidence.
        let label = RomanNumeralAnalyzer.label(chordRoot: 7, chordTemplateID: "7#5", keyTonic: 2, modeTones: dMajorTones, lookahead: [4])
        XCTAssertEqual(label.numeral, "IV+7")
        XCTAssertEqual(label.confidence, .low)
    }

    // MARK: - Secondary dominants / applied leading tones (the reference analysis's 3 cases)

    func testHalfDiminishedAppliedLeadingToneToV() {
        // G#m7(b5) → viiø7/V (m.4): resolves up a half step to A (V of D major), confirmed by
        // a stable A appearing within the lookahead window even though the immediately-next
        // stable chord is a passing tonic 6/4 (D) — the cadential-6/4 case from the reference.
        let label = RomanNumeralAnalyzer.label(
            chordRoot: 8, chordTemplateID: "mi7b5", keyTonic: 2, modeTones: dMajorTones,
            lookahead: [2, 6, 9] // D (passing I6/4), F# (iii7, passing), then A (the real target)
        )
        XCTAssertEqual(label.numeral, "vii\u{f8}7/V")
        XCTAssertEqual(label.confidence, .high)
    }

    func testHalfDiminishedAppliedLeadingToneToVi() {
        // A#m7(b5) → viiø7/vi (m.8): resolves up a half step to B (vi of D major).
        let label = RomanNumeralAnalyzer.label(
            chordRoot: 10, chordTemplateID: "mi7b5", keyTonic: 2, modeTones: dMajorTones,
            lookahead: [11]
        )
        XCTAssertEqual(label.numeral, "vii\u{f8}7/vi")
        XCTAssertEqual(label.confidence, .high)
    }

    func testDominantSeventhSecondaryDominantToVi() {
        // F#7 → V7/vi (m.16): resolves down a fifth to B (vi of D major).
        let label = RomanNumeralAnalyzer.label(
            chordRoot: 6, chordTemplateID: "7", keyTonic: 2, modeTones: dMajorTones,
            lookahead: [11]
        )
        XCTAssertEqual(label.numeral, "V7/vi")
        XCTAssertEqual(label.confidence, .high)
    }

    func testDominantSeventhSecondaryDominantToIV() {
        // D7 → V7/IV (m.14): root D IS the tonic itself, but "7" quality isn't a diatonic
        // extension of degree I (only degree V gets that pass) — resolves down a fifth to G (IV).
        let label = RomanNumeralAnalyzer.label(
            chordRoot: 2, chordTemplateID: "7", keyTonic: 2, modeTones: dMajorTones,
            lookahead: [7]
        )
        XCTAssertEqual(label.numeral, "V7/IV")
        XCTAssertEqual(label.confidence, .high)
    }

    func testDiminishedSeventhAppliedLeadingToneToVUsesDegreeSymbol() {
        // G#dim7 → vii°7/V (m.15): same target as the half-diminished case, different quality
        // symbol (°7, not ø7).
        let label = RomanNumeralAnalyzer.label(
            chordRoot: 8, chordTemplateID: "dim7", keyTonic: 2, modeTones: dMajorTones,
            lookahead: [9]
        )
        XCTAssertEqual(label.numeral, "vii\u{b0}7/V")
    }
}
