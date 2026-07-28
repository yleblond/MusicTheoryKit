import XCTest
@testable import JamShackUI

/// Regression coverage for a real bug: `layout(for:)` used to compute each key's octave as
/// `(pitch - minMidi) / 12`, which only lines up with `whiteSlotBySemitone`/
/// `blackAfterWhiteSlot` (both defined relative to an octave STARTING ON C) when `minMidi`
/// itself is a C. A full 88-key piano starts on A0 (`minMidi = 21`) — the first bug report:
/// three keys visually reappearing detached at the right edge, and the keyboard not filling
/// its full width.
@MainActor
final class PitchKeyboardViewLayoutTests: XCTestCase {
    func testEightyEightKeyRangeHasExactlyFiftyTwoWhiteAndThirtySixBlackKeys() {
        let view = PitchKeyboardView(minMidi: 21, maxMidi: 108)
        XCTAssertEqual(view.whiteKeyCount, 52)

        let (white, black) = view.layout(for: CGSize(width: 1040, height: 100))
        XCTAssertEqual(white.count, 52)
        XCTAssertEqual(black.count, 36)
    }

    /// The actual bug: with the OLD `(pitch - minMidi) / 12` math, A0 (pitch 21, a white key)
    /// landed at the same "octave 0" group as C1 (pitch 24) but at a LATER slot within it,
    /// putting C1 to A0's LEFT instead of its right. Every key's x position must instead be
    /// strictly increasing with pitch, and the very first key must start flush at x = 0.
    func testWhiteKeyXPositionsAreStrictlyIncreasingAndStartAtZero() {
        let view = PitchKeyboardView(minMidi: 21, maxMidi: 108)
        let (white, _) = view.layout(for: CGSize(width: 1040, height: 100))
        let sortedByPitch = white.sorted { $0.pitch < $1.pitch }

        XCTAssertEqual(Double(sortedByPitch.first?.rect.minX ?? -1), 0, accuracy: 0.01)
        for (a, b) in zip(sortedByPitch, sortedByPitch.dropFirst()) {
            XCTAssertLessThan(a.rect.minX, b.rect.minX, "pitch \(a.pitch) must sit strictly left of pitch \(b.pitch)")
        }
    }

    /// The keyboard must fill its ENTIRE given width — the last white key's right edge should
    /// reach the container's full width, not stop short (the bug's second symptom: extra
    /// unused space at the right because `whiteKeyCount` used to over-count).
    func testLastWhiteKeyReachesTheFullContainerWidth() {
        let view = PitchKeyboardView(minMidi: 21, maxMidi: 108)
        let containerWidth: CGFloat = 1040
        let (white, _) = view.layout(for: CGSize(width: containerWidth, height: 100))
        let last = white.max { $0.rect.minX < $1.rect.minX }
        XCTAssertEqual(Double(last?.rect.maxX ?? 0), Double(containerWidth), accuracy: 0.01)
    }

    /// A range that already started on a C (every pre-existing call site in the app) must keep
    /// behaving exactly as before this fix — same key count, still flush against both edges.
    func testCAlignedRangeStillFillsWidthExactly() {
        let view = PitchKeyboardView(minMidi: 48, maxMidi: 72) // C3...C5
        XCTAssertEqual(view.whiteKeyCount, 15)
        let containerWidth: CGFloat = 300
        let (white, _) = view.layout(for: CGSize(width: containerWidth, height: 100))
        let sorted = white.sorted { $0.pitch < $1.pitch }
        XCTAssertEqual(Double(sorted.first?.rect.minX ?? -1), 0, accuracy: 0.01)
        XCTAssertEqual(Double(sorted.last?.rect.maxX ?? 0), Double(containerWidth), accuracy: 0.01)
    }
}
