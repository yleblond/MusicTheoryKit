import SwiftUI
import AppCore

/// Colors for each `PitchDisplayRole`, plus the plain white/black key backgrounds. Defaults
/// are a reasonable starting palette, independent of `NoteColorSettingsFile` (the app's
/// user-configurable root/tone colors) — a call site that has those loaded should build its
/// own `PitchKeyboardColorScheme` from them instead of relying on these defaults.
public struct PitchKeyboardColorScheme: Sendable {
    public var chordRoot: Color
    public var chordTone: Color
    public var heldOutsideChord: Color
    public var held: Color
    public var modeRoot: Color
    public var modeTone: Color
    public var whiteKey: Color
    public var blackKey: Color

    public init(
        chordRoot: Color = .red,
        chordTone: Color = .yellow,
        heldOutsideChord: Color = .green,
        held: Color = .gray,
        modeRoot: Color = .blue,
        modeTone: Color = .cyan,
        whiteKey: Color = .white,
        blackKey: Color = .black
    ) {
        self.chordRoot = chordRoot
        self.chordTone = chordTone
        self.heldOutsideChord = heldOutsideChord
        self.held = held
        self.modeRoot = modeRoot
        self.modeTone = modeTone
        self.whiteKey = whiteKey
        self.blackKey = blackKey
    }

    func fillColor(for role: PitchDisplayRole, isWhiteKey: Bool) -> Color {
        switch role {
        case .chordRoot: return chordRoot
        case .chordTone: return chordTone
        case .heldOutsideChord: return heldOutsideChord
        case .held: return held
        case .modeRoot: return modeRoot
        case .modeTone: return modeTone
        case .none: return isWhiteKey ? whiteKey : blackKey
        }
    }
}

/// One key's laid-out rectangle, shared between drawing and tap/drag hit-testing so the two
/// can never disagree about where a key actually is.
private struct KeyRect {
    let pitch: Int
    let rect: CGRect
}

/// A vectorial piano keyboard over an absolute MIDI pitch range, colored via
/// `pitchDisplayState(...)` (`Sources/AppCore/PitchDisplayState.swift`) — the same
/// classification logic the ASCII terminal keyboard and the web console's `keyboardHTML`
/// use, so all three surfaces agree on what "root/tone/outside/held/mode" means for a given
/// pitch. Pure `Canvas`/`Path` (no `UIViewRepresentable`/`NSViewRepresentable`) so it hosts
/// cleanly on iOS, macOS, and later visionOS without a rewrite.
///
/// When `onNoteOn`/`onNoteOff` are supplied (non-nil), the keyboard is also playable — tap or
/// click a key to sound it, drag across the keys for a glissando (each newly-entered key
/// fires its own note-on, the previously-held one fires note-off) — the "clavier virtuel"
/// counterpart to the web console's own clickable virtual-keyboard page. Left `nil` (the
/// default) for a read-only display, e.g. showing another track's/the recognized chord's
/// notes where tapping shouldn't inject anything.
public struct PitchKeyboardView: View {
    public let minMidi: Int
    public let maxMidi: Int
    public let heldPitches: Set<Int>
    public let chordRoot: Int?
    public let chordTones: [Int]
    public let modeTones: [Int]
    public let alwaysShowChord: Bool
    public let showModeColoring: Bool
    public let colorScheme: PitchKeyboardColorScheme
    public let onNoteOn: ((Int) -> Void)?
    public let onNoteOff: ((Int) -> Void)?

    public init(
        minMidi: Int = 48,
        maxMidi: Int = 72,
        heldPitches: Set<Int> = [],
        chordRoot: Int? = nil,
        chordTones: [Int] = [],
        modeTones: [Int] = [],
        alwaysShowChord: Bool = false,
        showModeColoring: Bool = false,
        colorScheme: PitchKeyboardColorScheme = PitchKeyboardColorScheme(),
        onNoteOn: ((Int) -> Void)? = nil,
        onNoteOff: ((Int) -> Void)? = nil
    ) {
        self.minMidi = minMidi
        self.maxMidi = maxMidi
        self.heldPitches = heldPitches
        self.chordRoot = chordRoot
        self.chordTones = chordTones
        self.modeTones = modeTones
        self.alwaysShowChord = alwaysShowChord
        self.showModeColoring = showModeColoring
        self.colorScheme = colorScheme
        self.onNoteOn = onNoteOn
        self.onNoteOff = onNoteOff
    }

    // White key slot (0...6) within its octave, for the 7 white pitch classes.
    private static let whiteSlotBySemitone: [Int: Int] = [0: 0, 2: 1, 4: 2, 5: 3, 7: 4, 9: 5, 11: 6]
    // For each black pitch class, the white slot it sits directly after.
    private static let blackAfterWhiteSlot: [Int: Int] = [1: 0, 3: 1, 6: 3, 8: 4, 10: 5]

    private var octaveCount: Int { max(1, Int(ceil(Double(maxMidi - minMidi + 1) / 12.0))) }

    // The pitch currently held down by a tap/click/drag, if any — nil whenever nothing is
    // being played through this view (as opposed to `heldPitches`, which reflects the
    // session's actual state and may include notes held via other input methods entirely,
    // e.g. a MIDI keyboard playing the same track simultaneously).
    @State private var pressedPitch: Int?

    private func layout(for size: CGSize) -> (white: [KeyRect], black: [KeyRect]) {
        let whiteKeyCount = octaveCount * 7
        let whiteW = size.width / CGFloat(whiteKeyCount)
        let blackW = whiteW * 0.6
        let blackH = size.height * 0.62
        var white: [KeyRect] = []
        var black: [KeyRect] = []

        for pitch in minMidi...maxMidi {
            let pitchClass = ((pitch % 12) + 12) % 12
            let octave = (pitch - minMidi) / 12
            if let whiteSlotInOctave = Self.whiteSlotBySemitone[pitchClass] {
                let slot = octave * 7 + whiteSlotInOctave
                let x = CGFloat(slot) * whiteW
                white.append(KeyRect(pitch: pitch, rect: CGRect(x: x, y: 0, width: whiteW, height: size.height)))
            } else if let whiteSlotBefore = Self.blackAfterWhiteSlot[pitchClass] {
                let slot = octave * 7 + whiteSlotBefore + 1
                let x = CGFloat(slot) * whiteW - blackW / 2
                black.append(KeyRect(pitch: pitch, rect: CGRect(x: x, y: 0, width: blackW, height: blackH)))
            }
        }
        return (white, black)
    }

    /// Black keys are drawn on top, so they're also hit-tested first.
    private func pitch(at point: CGPoint, in size: CGSize) -> Int? {
        let (white, black) = layout(for: size)
        if let hit = black.first(where: { $0.rect.contains(point) }) { return hit.pitch }
        if let hit = white.first(where: { $0.rect.contains(point) }) { return hit.pitch }
        return nil
    }

    public var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let (white, black) = layout(for: size)
                // White keys first (background layer), then black keys on top — matches a
                // real keyboard's visual stacking.
                for key in white {
                    let state = pitchDisplayState(
                        pitch: key.pitch, heldPitches: heldPitches, chordRoot: chordRoot,
                        chordTones: chordTones, modeTones: modeTones,
                        alwaysShowChord: alwaysShowChord, showModeColoring: showModeColoring
                    )
                    let path = Path(key.rect.insetBy(dx: 0.5, dy: 0.5))
                    context.fill(path, with: .color(colorScheme.fillColor(for: state.role, isWhiteKey: true)))
                    context.stroke(path, with: .color(.black.opacity(0.4)), lineWidth: 1)
                }
                for key in black {
                    let state = pitchDisplayState(
                        pitch: key.pitch, heldPitches: heldPitches, chordRoot: chordRoot,
                        chordTones: chordTones, modeTones: modeTones,
                        alwaysShowChord: alwaysShowChord, showModeColoring: showModeColoring
                    )
                    context.fill(Path(key.rect), with: .color(colorScheme.fillColor(for: state.role, isWhiteKey: false)))
                }
            }
            .contentShape(Rectangle())
            // Always attached: `onNoteOn?`/`onNoteOff?` are no-ops when nil (a read-only
            // display), so there's no need to conditionally install a different gesture.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let newPitch = pitch(at: value.location, in: proxy.size) else { return }
                        guard newPitch != pressedPitch else { return }
                        if let oldPitch = pressedPitch { onNoteOff?(oldPitch) }
                        pressedPitch = newPitch
                        onNoteOn?(newPitch)
                    }
                    .onEnded { _ in
                        if let pitch = pressedPitch { onNoteOff?(pitch) }
                        pressedPitch = nil
                    }
            )
        }
        .frame(minHeight: 80)
    }
}

#Preview {
    PitchKeyboardView(
        minMidi: 48, maxMidi: 72,
        heldPitches: [60, 64, 67],
        chordRoot: 0,
        chordTones: [0, 4, 7],
        modeTones: [0, 2, 4, 5, 7, 9, 11]
    )
    .padding()
}
