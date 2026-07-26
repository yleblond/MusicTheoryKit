import SwiftUI
import AppCore

/// A 3-octave `PitchKeyboardView` excerpt, auto-centered on wherever `heldPitches` actually
/// are (see `MiniPianoOverviewView.bestWindow`), with the full-range mini overview above it —
/// the reusable "one track's live keyboard" card. Used by the Live screen WITH chord/mode
/// recognition (`chordRoot`/`chordTones`/`modeTones` all populated); reused as-is, with those
/// left empty, by any screen that just wants to show which notes are coming in right now with
/// no recognition overlay at all (the Microphone/MIDI sub-tabs of the "JamShack" tab).
public struct AutoCenteredKeyboardView: View {
    public let heldPitches: [Int]
    public let chordRoot: Int?
    public let chordTones: [Int]
    public let modeTones: [Int]
    public let palette: [String]
    public let paletteTextColors: [String]
    public let onNoteOn: ((Int) -> Void)?
    public let onNoteOff: ((Int) -> Void)?
    /// Forwarded as-is to the underlying `PitchKeyboardView.height` (default 144, same as that
    /// view's own default) — exposed here so a specific caller (the Live screen) can shrink it
    /// without affecting every other screen reusing this same card (Microphone/MIDI sub-tabs).
    public let keyboardHeight: CGFloat

    public init(
        heldPitches: [Int],
        chordRoot: Int? = nil,
        chordTones: [Int] = [],
        modeTones: [Int] = [],
        palette: [String] = PitchKeyboardView.defaultPalette,
        paletteTextColors: [String] = PitchKeyboardView.defaultPaletteTextColors,
        onNoteOn: ((Int) -> Void)? = nil,
        onNoteOff: ((Int) -> Void)? = nil,
        keyboardHeight: CGFloat = 144
    ) {
        self.heldPitches = heldPitches
        self.chordRoot = chordRoot
        self.chordTones = chordTones
        self.modeTones = modeTones
        self.palette = palette
        self.paletteTextColors = paletteTextColors
        self.onNoteOn = onNoteOn
        self.onNoteOff = onNoteOff
        self.keyboardHeight = keyboardHeight
    }

    /// 3 octaves (C3...B5 by default — same default range `StaticAssets.swift`'s
    /// `MIN_MIDI`/`MAX_MIDI` use), re-anchored on the lowest held note's own nearest-C-at-or-
    /// below every time something is held, left alone while nothing is (see
    /// `MiniPianoOverviewView.bestWindow`'s doc comment).
    @State private var windowMinMidi = 48
    @State private var windowMaxMidi = 83

    public var body: some View {
        VStack(spacing: 4) {
            MiniPianoOverviewView(
                highlightMinMidi: windowMinMidi,
                highlightMaxMidi: windowMaxMidi,
                heldPitches: heldPitches,
                chordRoot: chordRoot,
                chordTones: chordTones
            )
            PitchKeyboardView(
                minMidi: windowMinMidi,
                maxMidi: windowMaxMidi,
                heldPitches: Set(heldPitches),
                chordRoot: chordRoot,
                chordTones: chordTones,
                modeTones: modeTones,
                palette: palette,
                paletteTextColors: paletteTextColors,
                onNoteOn: onNoteOn,
                onNoteOff: onNoteOff,
                height: keyboardHeight
            )
        }
        .task(id: heldPitches) {
            guard !heldPitches.isEmpty else { return }
            let window = MiniPianoOverviewView.bestWindow(forHeldPitches: heldPitches, width: 36)
            windowMinMidi = window.min
            windowMaxMidi = window.max
        }
    }
}

#Preview {
    AutoCenteredKeyboardView(heldPitches: [60, 64, 67], chordRoot: 0, chordTones: [0, 4, 7], modeTones: [0, 2, 4, 5, 7, 9, 11])
        .padding()
}
