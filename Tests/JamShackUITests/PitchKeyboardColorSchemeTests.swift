import XCTest
import SwiftUI
@testable import JamShackUI
import AppCore
import MusicTheoryKit

final class PitchKeyboardColorSchemeTests: XCTestCase {

    func testEachRoleMapsToItsOwnConfiguredColor() {
        let scheme = PitchKeyboardColorScheme(
            chordRoot: .red, chordTone: .yellow, heldOutsideChord: .green,
            held: .gray, modeRoot: .blue, modeTone: .cyan, whiteKey: .white, blackKey: .black
        )
        XCTAssertEqual(scheme.fillColor(for: .chordRoot, isWhiteKey: true), .red)
        XCTAssertEqual(scheme.fillColor(for: .chordTone, isWhiteKey: true), .yellow)
        XCTAssertEqual(scheme.fillColor(for: .heldOutsideChord, isWhiteKey: true), .green)
        XCTAssertEqual(scheme.fillColor(for: .held, isWhiteKey: true), .gray)
        XCTAssertEqual(scheme.fillColor(for: .modeRoot, isWhiteKey: true), .blue)
        XCTAssertEqual(scheme.fillColor(for: .modeTone, isWhiteKey: true), .cyan)
    }

    func testUnmarkedRoleFallsBackToPlainKeyColorByKeyColor() {
        let scheme = PitchKeyboardColorScheme(whiteKey: .white, blackKey: .black)
        XCTAssertEqual(scheme.fillColor(for: .none, isWhiteKey: true), .white)
        XCTAssertEqual(scheme.fillColor(for: .none, isWhiteKey: false), .black)
    }

    func testNoteBasedDerivesChordRootAndToneFromThePaletteEntryAtTheRootPitchClass() {
        let palette = PitchKeyboardView.defaultPalette
        let scheme = PitchKeyboardColorScheme.noteBased(rootPitchClass: PitchClass(2), palette: palette)
        XCTAssertEqual(scheme.chordRoot, Color(hex: palette[2]))
        XCTAssertEqual(scheme.chordTone, Color.pastel(hex: palette[2], fraction: 0.45))
        XCTAssertNotEqual(scheme.chordTone, scheme.chordRoot)
    }

    func testNoteBasedLeavesEveryOtherRoleUntouched() {
        let base = PitchKeyboardColorScheme(heldOutsideChord: .green, held: .gray, modeRoot: .blue, modeTone: .cyan)
        let scheme = PitchKeyboardColorScheme.noteBased(rootPitchClass: PitchClass(0), palette: PitchKeyboardView.defaultPalette, base: base)
        XCTAssertEqual(scheme.heldOutsideChord, .green)
        XCTAssertEqual(scheme.held, .gray)
        XCTAssertEqual(scheme.modeRoot, .blue)
        XCTAssertEqual(scheme.modeTone, .cyan)
    }

    func testNoteBasedModeDerivesModeRootAndToneFromThePaletteEntryAtTheRootPitchClass() {
        let palette = PitchKeyboardView.defaultPalette
        let scheme = PitchKeyboardColorScheme.noteBasedMode(rootPitchClass: PitchClass(5), palette: palette)
        XCTAssertEqual(scheme.modeRoot, Color(hex: palette[5]))
        XCTAssertEqual(scheme.modeTone, Color.pastel(hex: palette[5], fraction: 0.45))
        XCTAssertNotEqual(scheme.modeTone, scheme.modeRoot)
    }

    func testNoteBasedModeLeavesEveryOtherRoleUntouched() {
        let base = PitchKeyboardColorScheme(chordRoot: .red, chordTone: .yellow, heldOutsideChord: .green, held: .gray)
        let scheme = PitchKeyboardColorScheme.noteBasedMode(rootPitchClass: PitchClass(0), palette: PitchKeyboardView.defaultPalette, base: base)
        XCTAssertEqual(scheme.chordRoot, .red)
        XCTAssertEqual(scheme.chordTone, .yellow)
        XCTAssertEqual(scheme.heldOutsideChord, .green)
        XCTAssertEqual(scheme.held, .gray)
    }
}
