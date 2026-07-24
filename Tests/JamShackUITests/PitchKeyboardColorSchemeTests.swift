import XCTest
import SwiftUI
@testable import JamShackUI
import AppCore

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
}
