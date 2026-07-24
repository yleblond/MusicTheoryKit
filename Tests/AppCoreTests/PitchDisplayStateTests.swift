import XCTest
@testable import AppCore

// Mirrors WebConsole's keyboardHTML decision tree (Sources/WebConsole/StaticAssets.swift) —
// every branch exercised here should match what that JS function would classify for the same
// inputs, since both are supposed to agree on what a given pitch's key looks like.
final class PitchDisplayStateTests: XCTestCase {

    func testHeldChordRootIsChordRoot() {
        let state = pitchDisplayState(pitch: 60, heldPitches: [60], chordRoot: 0, chordTones: [0, 4, 7], modeTones: [])
        XCTAssertEqual(state.role, .chordRoot)
    }

    func testHeldChordToneIsChordTone() {
        let state = pitchDisplayState(pitch: 64, heldPitches: [64], chordRoot: 0, chordTones: [0, 4, 7], modeTones: [])
        XCTAssertEqual(state.role, .chordTone)
    }

    func testHeldOutsideRecognizedChordIsHeldOutsideChord() {
        let state = pitchDisplayState(pitch: 62, heldPitches: [62], chordRoot: 0, chordTones: [0, 4, 7], modeTones: [])
        XCTAssertEqual(state.role, .heldOutsideChord)
    }

    func testHeldWithNoRecognizedChordIsHeld() {
        let state = pitchDisplayState(pitch: 62, heldPitches: [62], chordRoot: nil, chordTones: [], modeTones: [])
        XCTAssertEqual(state.role, .held)
    }

    func testNotHeldWithoutAlwaysShowChordIsNone() {
        let state = pitchDisplayState(pitch: 60, heldPitches: [], chordRoot: 0, chordTones: [0, 4, 7], modeTones: [])
        XCTAssertEqual(state.role, .none)
    }

    func testAlwaysShowChordColorsRootAndTonesEvenWhenNotHeld() {
        let root = pitchDisplayState(pitch: 60, heldPitches: [], chordRoot: 0, chordTones: [0, 4, 7], modeTones: [], alwaysShowChord: true)
        XCTAssertEqual(root.role, .chordRoot)
        let tone = pitchDisplayState(pitch: 64, heldPitches: [], chordRoot: 0, chordTones: [0, 4, 7], modeTones: [], alwaysShowChord: true)
        XCTAssertEqual(tone.role, .chordTone)
        let outside = pitchDisplayState(pitch: 62, heldPitches: [], chordRoot: 0, chordTones: [0, 4, 7], modeTones: [], alwaysShowChord: true)
        XCTAssertEqual(outside.role, .none, "alwaysShowChord only colors root/tones, not every other key")
    }

    func testModeColoringOnlyAppliesWhenNothingElseMatched() {
        let modeTones = [0, 2, 4, 5, 7, 9, 11] // C ionian, degree order
        let tonic = pitchDisplayState(pitch: 60, heldPitches: [], chordRoot: nil, chordTones: [], modeTones: modeTones, showModeColoring: true)
        XCTAssertEqual(tonic.role, .modeRoot)
        XCTAssertEqual(tonic.degreeBadge, 1)

        let other = pitchDisplayState(pitch: 62, heldPitches: [], chordRoot: nil, chordTones: [], modeTones: modeTones, showModeColoring: true)
        XCTAssertEqual(other.role, .modeTone)
        XCTAssertEqual(other.degreeBadge, 2)

        let outOfMode = pitchDisplayState(pitch: 61, heldPitches: [], chordRoot: nil, chordTones: [], modeTones: modeTones, showModeColoring: true)
        XCTAssertEqual(outOfMode.role, .none)
        XCTAssertNil(outOfMode.degreeBadge)
    }

    func testModeColoringNeverOverridesAHeldOrChordRole() {
        let modeTones = [0, 2, 4, 5, 7, 9, 11]
        let state = pitchDisplayState(pitch: 60, heldPitches: [60], chordRoot: 0, chordTones: [0, 4, 7], modeTones: modeTones, showModeColoring: true)
        XCTAssertEqual(state.role, .chordRoot, "held/chord roles take priority over mode coloring")
    }

    func testPitchClassNormalizationAcrossOctaves() {
        // Same pitch class (C=0), three different octaves — role/degree must agree regardless.
        let modeTones = [0, 2, 4, 5, 7, 9, 11]
        for pitch in [24, 60, 96] {
            let state = pitchDisplayState(pitch: pitch, heldPitches: [], chordRoot: nil, chordTones: [], modeTones: modeTones, showModeColoring: true)
            XCTAssertEqual(state.role, .modeRoot, "pitch \(pitch)")
            XCTAssertEqual(state.degreeBadge, 1, "pitch \(pitch)")
        }
    }
}
