import SwiftUI

/// Maps a typed character to a MIDI pitch, mirroring GarageBand's "Musical Typing" layout —
/// same mapping `Sources/JamShack/main.swift`'s own `computerKeyboardNoteMap` uses (kept as a
/// separate copy here rather than a shared module: the CLI's copy lives in an executable
/// target, not a library, so sharing it would mean restructuring a working terminal app for
/// no functional gain — same "can't share code across these presentation layers" situation as
/// WebConsole's JS). "ASDFGHJKL;" plays the white keys of one octave starting at C4,
/// "WE_TYU_OP" fills in the black keys above the gaps.
public let computerKeyboardNoteMap: [Character: Int] = [
    "a": 60, "w": 61, "s": 62, "e": 63, "d": 64, "f": 65, "t": 66, "g": 67,
    "y": 68, "h": 69, "u": 70, "j": 71, "k": 72, "o": 73, "l": 74, "p": 75, ";": 76,
]

/// Every character `computerKeyboardNoteMap` recognizes — passed to `.onKeyPress(characters:
/// phases:action:)` so only these specific keys are ever intercepted, and everything else
/// (arrow keys, Cmd-shortcuts, plain typing in a search/alias field elsewhere) bubbles through
/// completely untouched.
public let computerKeyboardCharacterSet = CharacterSet(charactersIn: String(computerKeyboardNoteMap.keys))

public extension View {
    /// Plays notes from the physical/hardware keyboard while `isActive` and this view (or one
    /// of its descendants) holds keyboard focus, via `computerKeyboardNoteMap`. Built on plain
    /// SwiftUI (`.focusable()`/`.onKeyPress`, macOS 14+/iOS 17+ — same mechanism
    /// `GuideLectureView` already uses for its own arrow-key navigation) rather than a hidden
    /// `NSViewRepresentable`/`UIViewRepresentable`: an earlier version of this used exactly that
    /// hack, attached once at the whole app's root, always "on" — which meant any other native
    /// control anywhere (a `Picker`, a `TextField`) that ever took focus left it permanently
    /// stuck there for the rest of the session, with no reliable way to reclaim it back. This
    /// version is only ever focusable/registered when explicitly turned on (default off, see
    /// `ImprovSession.computerKeyboardInputEnabled`), and since it's real SwiftUI focus, an
    /// unrecognized key (an arrow key, say) simply falls through this view's `.onKeyPress` (it
    /// returns `.ignored`) and continues bubbling up/down the normal SwiftUI focus chain to
    /// whatever else wants it — e.g. `GuideLectureView`'s own arrow-key handlers, which run
    /// first whenever that screen itself holds focus, well before this reaches the ancestor
    /// level this modifier is attached at.
    /// `focusRequestToken`: bump `ImprovSession.computerKeyboardFocusRequestToken` (via
    /// `requestComputerKeyboardFocus()`) after any interaction with a native `Picker`/`Menu`
    /// elsewhere that would otherwise permanently keep SwiftUI keyboard focus — this modifier
    /// reclaims it back every time that counter changes, on top of its usual "became active"
    /// reclaim. `octaveShift`/`onShiftOctave`: see `ImprovSession.computerKeyboardOctaveShift`/
    /// `shiftComputerKeyboardOctave(by:)` — Left/Right arrow keys shift it by a whole octave.
    /// Deliberately harmless around `GuideLectureView`'s OWN left/right arrow handling (previous/
    /// next chord): that view claims focus and returns `.handled` for arrows itself whenever
    /// it's the active screen, so this ancestor-level handler only ever sees an arrow key that
    /// NOTHING closer to the focused view already consumed.
    func computerKeyboardInput(
        isActive: Bool, focusRequestToken: Int, octaveShift: Int,
        onNoteOn: @escaping (Int) -> Void, onNoteOff: @escaping (Int) -> Void,
        onShiftOctave: @escaping (Int) -> Void
    ) -> some View {
        modifier(ComputerKeyboardInputModifier(
            isActive: isActive, focusRequestToken: focusRequestToken, octaveShift: octaveShift,
            onNoteOn: onNoteOn, onNoteOff: onNoteOff, onShiftOctave: onShiftOctave
        ))
    }
}

private struct ComputerKeyboardInputModifier: ViewModifier {
    let isActive: Bool
    let focusRequestToken: Int
    let octaveShift: Int
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void
    let onShiftOctave: (Int) -> Void

    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable(isActive)
            .focusEffectDisabled()
            .focused($isFocused)
            .onChange(of: isActive) { _, active in
                if active { isFocused = true }
            }
            .onChange(of: focusRequestToken) { _, _ in
                if isActive { isFocused = true }
            }
            .onKeyPress(characters: computerKeyboardCharacterSet, phases: [.down, .up]) { press in
                guard isActive, let character = press.characters.lowercased().first,
                      let basePitch = computerKeyboardNoteMap[character]
                else { return .ignored }
                let pitch = basePitch + octaveShift
                switch press.phase {
                case .down: onNoteOn(pitch)
                case .up: onNoteOff(pitch)
                default: break
                }
                return .handled
            }
            .onKeyPress(.leftArrow) {
                guard isActive else { return .ignored }
                onShiftOctave(-1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                guard isActive else { return .ignored }
                onShiftOctave(1)
                return .handled
            }
    }
}

/// The persistent, always-visible "long" keyboard shown at the bottom of the window while
/// `ImprovSession.computerKeyboardInputEnabled` is on — deliberately distinct from every other
/// (auto-centered, per-screen) mini keyboard elsewhere in the app: this one specifically shows
/// what the PHYSICAL computer keyboard itself is currently playing, and stays put across every
/// tab, both a constant visual reminder that typing anywhere now plays notes and a click/tap-
/// able input surface of its own (same interactive `PitchKeyboardView` every other keyboard
/// card in the app already uses).
public struct ComputerKeyboardInputBar: View {
    public let heldPitches: Set<Int>
    public let palette: [String]
    public let paletteTextColors: [String]
    public let onNoteOn: (Int) -> Void
    public let onNoteOff: (Int) -> Void
    public let label: String
    /// See `ImprovSession.computerKeyboardOctaveShift` — drives both where the red "active zone"
    /// outline/key letters are drawn (below) AND (via `ContentView`'s own
    /// `.computerKeyboardInput(octaveShift:)`) which actual pitches typing produces; kept in
    /// sync by both reading from the same `ImprovSession` property.
    public let octaveShift: Int
    /// Steps by whole octaves (±1 = ±12 semitones) — see `ImprovSession
    /// .shiftComputerKeyboardOctave(by:)`.
    public let onShiftOctave: (Int) -> Void

    public init(
        heldPitches: Set<Int>, palette: [String], paletteTextColors: [String],
        label: String, octaveShift: Int,
        onNoteOn: @escaping (Int) -> Void, onNoteOff: @escaping (Int) -> Void,
        onShiftOctave: @escaping (Int) -> Void
    ) {
        self.heldPitches = heldPitches
        self.palette = palette
        self.paletteTextColors = paletteTextColors
        self.label = label
        self.octaveShift = octaveShift
        self.onNoteOn = onNoteOn
        self.onNoteOff = onNoteOff
        self.onShiftOctave = onShiftOctave
    }

    /// `computerKeyboardNoteMap`'s pitches, shifted by `octaveShift` and keyed by the resulting
    /// sounding pitch — what actually gets highlighted/labeled below always matches what typing
    /// actually plays right now.
    private var shiftedKeyLabels: [Int: String] {
        Dictionary(uniqueKeysWithValues: computerKeyboardNoteMap.map { character, pitch in
            (pitch + octaveShift, String(character).uppercased())
        })
    }

    private var highlightedRange: ClosedRange<Int> {
        let shiftedPitches = computerKeyboardNoteMap.values.map { $0 + octaveShift }
        return (shiftedPitches.min() ?? 60)...(shiftedPitches.max() ?? 76)
    }

    public var body: some View {
        VStack(spacing: 2) {
            HStack {
                Button { onShiftOctave(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Button { onShiftOctave(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
            }
            // A full 88-key piano (A0...C8) — deliberately not cropped to the note map's own
            // narrower mapped span; how this bar looks/scales can be refined later, this just
            // establishes "the whole keyboard is here." The red outline + letters mark exactly
            // which keys typing currently reaches (see `octaveShift`).
            PitchKeyboardView(
                minMidi: 21, maxMidi: 108, heldPitches: heldPitches,
                palette: palette, paletteTextColors: paletteTextColors,
                onNoteOn: onNoteOn, onNoteOff: onNoteOff, height: 90,
                keyLabels: shiftedKeyLabels, highlightedPitches: highlightedRange
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
