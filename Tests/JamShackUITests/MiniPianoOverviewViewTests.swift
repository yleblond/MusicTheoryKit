import XCTest
@testable import JamShackUI

/// Covers `MiniPianoOverviewView.bestWindow` — the auto-centering logic behind the Live
/// screen's 3-octave keyboard excerpt, ported from the web console's Observer tab
/// (`bestObserverWindow`/`nearestOctaveStopAtOrBelow` in `Sources/WebConsole/StaticAssets.swift`).
final class MiniPianoOverviewViewTests: XCTestCase {
    func testAnchorsOnNearestCAtOrBelowTheLowestHeldNote() {
        // 64 = E4, nearest C at or below is 60 (C4).
        let window = MiniPianoOverviewView.bestWindow(forHeldPitches: [64, 67, 72], width: 36)
        XCTAssertEqual(window.min, 60)
        XCTAssertEqual(window.max, 95)
    }

    func testExactCDoesNotShiftDownAnOctave() {
        let window = MiniPianoOverviewView.bestWindow(forHeldPitches: [60], width: 36)
        XCTAssertEqual(window.min, 60)
    }

    func testClampsAtTheBottomOfTheMIDIRange() {
        let window = MiniPianoOverviewView.bestWindow(forHeldPitches: [3], width: 36)
        XCTAssertEqual(window.min, 0)
        XCTAssertEqual(window.max, 35)
    }

    func testClampsAtTheTopOfTheMIDIRange() {
        let window = MiniPianoOverviewView.bestWindow(forHeldPitches: [127], width: 36)
        XCTAssertEqual(window.max, 127)
        XCTAssertEqual(window.min, 92)
    }

    func testEmptyHeldPitchesFallsBackToTheDefaultC3Window() {
        let window = MiniPianoOverviewView.bestWindow(forHeldPitches: [], width: 36)
        XCTAssertEqual(window.min, 48)
        XCTAssertEqual(window.max, 83)
    }

    func testOnlyTheLowestNoteAnchorsTheWindowRegardlessOfHigherNotes() {
        let window = MiniPianoOverviewView.bestWindow(forHeldPitches: [100, 40, 90], width: 36)
        XCTAssertEqual(window.min, 36) // nearest C at or below 40
    }
}
