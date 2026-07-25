import SwiftUI
import AppCore

/// A read-only, full-range (MIDI 0...108) overview piano sitting above a `PitchKeyboardView`
/// excerpt — same idea as the web console's Observer tab own mini-piano overview
/// (`renderObserverMiniPianoOverview` in `Sources/WebConsole/StaticAssets.swift`), except each
/// held note colors its ENTIRE key (root/tone/outside/held, via the same `colorScheme` the
/// paired `PitchKeyboardView` uses) rather than just a small dot at its center — reads the
/// same way at a glance as the full-size keyboard below it. An unfilled RED rectangle marks
/// whichever window that excerpt is currently showing.
public struct MiniPianoOverviewView: View {
    public static let minMidi = 0
    public static let maxMidi = 108

    public let highlightMinMidi: Int
    public let highlightMaxMidi: Int
    public let heldPitches: [Int]
    public let chordRoot: Int?
    public let chordTones: [Int]
    public let colorScheme: PitchKeyboardColorScheme

    public init(
        highlightMinMidi: Int, highlightMaxMidi: Int, heldPitches: [Int], chordRoot: Int?, chordTones: [Int],
        colorScheme: PitchKeyboardColorScheme = PitchKeyboardColorScheme()
    ) {
        self.highlightMinMidi = highlightMinMidi
        self.highlightMaxMidi = highlightMaxMidi
        self.heldPitches = heldPitches
        self.chordRoot = chordRoot
        self.chordTones = chordTones
        self.colorScheme = colorScheme
    }

    private static let whiteSlotBySemitone: [Int: Int] = [0: 0, 2: 1, 4: 2, 5: 3, 7: 4, 9: 5, 11: 6]
    private static let blackAfterWhiteSlot: [Int: Int] = [1: 0, 3: 1, 6: 3, 8: 4, 10: 5]
    private static let octaveBase = minMidi / 12

    private static func whiteSlot(_ pitch: Int) -> Int {
        let pitchClass = ((pitch % 12) + 12) % 12
        let octave = pitch / 12 - octaveBase
        return octave * 7 + (whiteSlotBySemitone[pitchClass] ?? 0)
    }

    /// Anchors the window on the lowest held note's own nearest-C-at-or-below — mirrors
    /// `bestObserverWindow`/`nearestOctaveStopAtOrBelow` in `StaticAssets.swift`. Falls back to
    /// `(48, 48+width-1)` (C3-based) when nothing is held, since there's no "lowest note" to
    /// anchor on yet — callers are expected to only apply this when `heldPitches` isn't empty
    /// and otherwise keep whatever window was already showing (see `bestObserverWindow`'s own
    /// doc comment for why: "don't snap away during a silent moment").
    public nonisolated static func bestWindow(forHeldPitches heldPitches: [Int], width: Int) -> (min: Int, max: Int) {
        guard let lowest = heldPitches.min() else { return (48, 48 + width - 1) }
        let pitchClass = ((lowest % 12) + 12) % 12
        let nearestCAtOrBelow = lowest - pitchClass
        let clampedMin = max(0, Swift.min(127 - width + 1, nearestCAtOrBelow))
        return (clampedMin, clampedMin + width - 1)
    }

    public var body: some View {
        Canvas { context, size in
            let totalWhiteKeys = Self.whiteSlot(Self.maxMidi) + 1
            let whiteWidth = size.width / CGFloat(totalWhiteKeys)
            let blackWidth = whiteWidth * 0.6
            let blackHeight = size.height * 0.62
            let held = Set(heldPitches)

            for pitch in Self.minMidi...Self.maxMidi {
                let pitchClass = ((pitch % 12) + 12) % 12
                guard let slot = Self.whiteSlotBySemitone[pitchClass] else { continue }
                let octave = pitch / 12 - Self.octaveBase
                let x = CGFloat(octave * 7 + slot) * whiteWidth
                let rect = CGRect(x: x, y: 0, width: whiteWidth, height: size.height)
                let state = pitchDisplayState(pitch: pitch, heldPitches: held, chordRoot: chordRoot, chordTones: chordTones, modeTones: [])
                context.fill(Path(rect), with: .color(colorScheme.fillColor(for: state.role, isWhiteKey: true)))
                context.stroke(Path(rect), with: .color(.black.opacity(0.3)), lineWidth: 0.5)
            }
            for pitch in Self.minMidi...Self.maxMidi {
                let pitchClass = ((pitch % 12) + 12) % 12
                guard Self.whiteSlotBySemitone[pitchClass] == nil, let whiteSlotBefore = Self.blackAfterWhiteSlot[pitchClass] else { continue }
                let octave = pitch / 12 - Self.octaveBase
                let slot = octave * 7 + whiteSlotBefore + 1
                let x = CGFloat(slot) * whiteWidth - blackWidth / 2
                let rect = CGRect(x: x, y: 0, width: blackWidth, height: blackHeight)
                let state = pitchDisplayState(pitch: pitch, heldPitches: held, chordRoot: chordRoot, chordTones: chordTones, modeTones: [])
                context.fill(Path(rect), with: .color(colorScheme.fillColor(for: state.role, isWhiteKey: false)))
            }

            // Highlighted "you are here" window — unfilled red rectangle, matching the web's
            // `.mini-piano-active { fill: none; stroke: #e91e63; }`.
            let x1 = CGFloat(Self.whiteSlot(highlightMinMidi)) * whiteWidth
            let x2 = CGFloat(Self.whiteSlot(highlightMaxMidi) + 1) * whiteWidth
            let highlightRect = CGRect(x: x1, y: 0, width: x2 - x1, height: size.height)
            context.stroke(Path(highlightRect), with: .color(.red), lineWidth: 1.5)
        }
        .frame(height: 22)
    }
}

#Preview {
    MiniPianoOverviewView(highlightMinMidi: 48, highlightMaxMidi: 83, heldPitches: [60, 64, 67], chordRoot: 0, chordTones: [0, 4, 7])
        .padding()
}
