import XCTest
import MusicTheoryKit
@testable import AppCore

/// `temperamentCents(forPitch:mode:configuration:)` is the exact function
/// `ImprovSession.updateRecognitionState` calls to decide the pitch-bend `SamplerUnit.startNote`
/// sends when `pressKey(applyTuning: true)` — i.e. the function that decides whether "Jouer
/// tempéré" actually sounds different from "Jouer non tempéré". Unlike its simpler sibling
/// `fixedTemperamentCents` (see `FixedTemperamentCentsTests`), it had no direct test coverage —
/// added 2026-08-16 verifying the audible-correction path, not just the underlying math.
final class TemperamentCentsTests: XCTestCase {
    private let ionian = ScaleLibrary.byID("ionian")!
    private let melodicMinor = ScaleLibrary.byID("melodic_minor")! // familyID 2 — no diatonic spelling table

    func testEqualTemperamentIsAlwaysZeroRegardlessOfModeOrPitch() {
        let configuration = TuningConfiguration(temperamentID: "equal", referenceA4: 440)
        let mode = Mode(tonic: PitchClass(2), scale: ionian) // D major
        for pitch in 60...71 {
            XCTAssertEqual(temperamentCents(forPitch: pitch, mode: mode, configuration: configuration), 0)
        }
    }

    /// Cross-checked against `FixedTemperamentCentsTests
    /// .testJustIntonationMajorThirdAboveTonicIsFlat` — D Ionian has no enharmonic ambiguity for
    /// its own major third (F#), so the mode-aware function must agree exactly with the plain
    /// pitch-class one for this same interval.
    func testJustIntonationMajorThirdInDIonianMatchesTheKnownFixedValue() {
        let configuration = TuningConfiguration(temperamentID: "justIntonation", referenceA4: 440)
        let mode = Mode(tonic: PitchClass(2), scale: ionian) // D major: D E F# G A B C#
        let fSharp = 60 + 6 // any octave — only the pitch class matters
        XCTAssertEqual(temperamentCents(forPitch: fSharp, mode: mode, configuration: configuration), -13.69, accuracy: 0.01)
    }

    /// Documented fallback #1: a scale outside family 1 has no `DiatonicSpelling` table, so this
    /// must degrade to exactly `fixedTemperamentCents`'s own (tonic-relative, spelling-agnostic)
    /// result rather than silently returning 0 or crashing.
    func testNonFamilyOneModeFallsBackToFixedTemperamentCentsExactly() {
        let configuration = TuningConfiguration(temperamentID: "werckmeisterIII", referenceA4: 440)
        let tonic = PitchClass(9) // A
        let mode = Mode(tonic: tonic, scale: melodicMinor)
        let pitch = 60 + 0 // C, some pitch class present in the scale
        let expected = fixedTemperamentCents(forPitchClass: PitchClass(0), tonic: tonic, configuration: configuration)
        XCTAssertEqual(temperamentCents(forPitch: pitch, mode: mode, configuration: configuration), expected)
    }

    /// Documented fallback #2: a pitch outside the mode's own 7 diatonic degrees (a chromatic
    /// passing tone) — C Ionian's degrees are C D E F G A B, so C# (pitch class 1) isn't one —
    /// must also degrade to `fixedTemperamentCents` rather than silently returning 0.
    func testChromaticPitchOutsideTheModesOwnDegreesFallsBackToFixedTemperamentCents() {
        let configuration = TuningConfiguration(temperamentID: "pythagorean", referenceA4: 440)
        let tonic = PitchClass(0) // C
        let mode = Mode(tonic: tonic, scale: ionian)
        let chromaticPitch = 60 + 1 // C#/Db — not a degree of C major
        let expected = fixedTemperamentCents(forPitchClass: PitchClass(1), tonic: tonic, configuration: configuration)
        XCTAssertEqual(temperamentCents(forPitch: chromaticPitch, mode: mode, configuration: configuration), expected)
    }

    /// The reference-pitch offset (`referenceA4`) must still apply on top of the temperament
    /// deviation through the mode-aware path too, exactly as `FixedTemperamentCentsTests
    /// .testReferenceA4OffsetIsAdditiveOnTopOfTheTemperament` already verifies for the simpler one.
    func testReferenceA4OffsetIsAdditiveThroughTheModeAwarePathToo() {
        let configuration = TuningConfiguration(temperamentID: "equal", referenceA4: 441)
        let mode = Mode(tonic: PitchClass(0), scale: ionian)
        let cents = temperamentCents(forPitch: 60, mode: mode, configuration: configuration)
        XCTAssertEqual(cents, 1200 * log2(441.0 / 440.0), accuracy: 0.0001)
    }
}
