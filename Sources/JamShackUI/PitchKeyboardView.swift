import SwiftUI
import AppCore
import MusicTheoryKit

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
/// can never disagree about where a key actually is. Internal (not `private`), same as
/// `PitchKeyboardView.layout(for:)` below, purely so `PitchKeyboardViewLayoutTests` can call it
/// directly instead of only inferring layout correctness from rendered pixels.
struct KeyRect: Equatable {
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
    /// The active palette's 12 hex colors (index 0 = C ... 11 = B) — same values
    /// `WebConsoleState.palette` sends, used ONLY for the degree badges (each badge is
    /// colored by its own note's identity, same as the web's `.degree-badge`), never for the
    /// key fill itself (that stays `colorScheme`, a role/state color, not a note-identity one).
    public let palette: [String]
    /// See `palette`'s doc comment — the legible text color painted OVER each badge.
    public let paletteTextColors: [String]
    public let onNoteOn: ((Int) -> Void)?
    public let onNoteOff: ((Int) -> Void)?
    /// Overridable per call site — e.g. the Guide screen's own static mode/chord reference
    /// keyboards render noticeably smaller than the live "En direct" one, per explicit user
    /// request. Defaults to the height every other call site already used before this became
    /// configurable.
    public let height: CGFloat
    /// A discreet one-character label drawn near the bottom of a key, e.g. the physical
    /// computer-keyboard letter that plays it (`ComputerKeyboardInputBar`'s own use) — empty
    /// (the default) draws nothing extra, every other call site is unaffected.
    public let keyLabels: [Int: String]
    /// When set, an accent-colored (red) outline is drawn around the bounding box of every key
    /// in this pitch range — `ComputerKeyboardInputBar` uses it to mark exactly which keys the
    /// physical keyboard's letters currently reach. `nil` (the default) draws no outline.
    public let highlightedPitches: ClosedRange<Int>?
    /// Keyed by PITCH CLASS (0...11, not absolute MIDI pitch) — overrides `colorScheme`'s own
    /// role-based fill for every octave of that pitch class at once, e.g. the melodic-vocabulary
    /// panel's own mini keyboard (colored by `MelodicRole`, a dimension `PitchDisplayState` has
    /// no concept of). A pitch class with no entry here keeps its normal role-based fill —
    /// existing call sites are unaffected by the empty default.
    public let customFillColors: [Int: Color]

    /// Same fallback arrays `StaticAssets.swift`'s `PITCH_CLASS_COLORS`/`_TEXT_COLORS` use
    /// before the first real palette is known — a reasonable default for any call site that
    /// doesn't have (or care about) the session's actual active palette.
    public static let defaultPalette = [
        "#DB2A52", "#0AAD9A", "#F7872D", "#4169B7", "#F2DE18", "#AE2F93",
        "#44B853", "#F15830", "#249CD7", "#FEBC20", "#884A9C", "#ABD144",
    ]
    public static let defaultPaletteTextColors = [
        "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#111111", "#ffffff",
        "#ffffff", "#ffffff", "#ffffff", "#111111", "#ffffff", "#111111",
    ]

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
        palette: [String] = PitchKeyboardView.defaultPalette,
        paletteTextColors: [String] = PitchKeyboardView.defaultPaletteTextColors,
        onNoteOn: ((Int) -> Void)? = nil,
        onNoteOff: ((Int) -> Void)? = nil,
        height: CGFloat = 144,
        keyLabels: [Int: String] = [:],
        highlightedPitches: ClosedRange<Int>? = nil,
        customFillColors: [Int: Color] = [:]
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
        self.palette = palette
        self.paletteTextColors = paletteTextColors
        self.onNoteOn = onNoteOn
        self.onNoteOff = onNoteOff
        self.height = height
        self.keyLabels = keyLabels
        self.highlightedPitches = highlightedPitches
        self.customFillColors = customFillColors
    }

    // White key slot (0...6) within its octave, for the 7 white pitch classes.
    private static let whiteSlotBySemitone: [Int: Int] = [0: 0, 2: 1, 4: 2, 5: 3, 7: 4, 9: 5, 11: 6]
    // For each black pitch class, the white slot it sits directly after.
    private static let blackAfterWhiteSlot: [Int: Int] = [1: 0, 3: 1, 6: 3, 8: 4, 10: 5]
    /// Vertical space reserved above the keys themselves for degree badges — same idea as the
    /// web's `.degree-badge { top: -18px }` sitting above the key div, except here the keys
    /// are shifted down to make room rather than the badge overflowing the view's own bounds.
    private static let badgeTopInset: CGFloat = 18
    private static let badgeDiameter: CGFloat = 14

    /// Both `whiteSlotBySemitone`/`blackAfterWhiteSlot` are only correct relative to an octave
    /// that starts on C — `absoluteWhiteSlot` anchors that math to the pitch's own absolute
    /// octave (`pitch / 12`, never `(pitch - minMidi) / 12`), so ranges that DON'T start on a C
    /// (e.g. a full 88-key piano, `minMidi = 21` = A0) lay out correctly instead of wrapping
    /// early notes into the wrong slot. A black key sits at its preceding white slot + 0.5, a
    /// fractional placeholder only ever used to compute `baseSlot` below (real black-key x
    /// positions are still computed the same way as before).
    private static func absoluteWhiteSlot(forPitch pitch: Int) -> Double {
        let pitchClass = ((pitch % 12) + 12) % 12
        let octave = pitch / 12
        if let whiteSlot = whiteSlotBySemitone[pitchClass] {
            return Double(octave * 7 + whiteSlot)
        }
        return Double(octave * 7 + blackAfterWhiteSlot[pitchClass]!) + 0.5
    }

    /// `minMidi`'s own absolute slot — every key's x position is expressed relative to this, so
    /// the leftmost key in range always starts at x = 0 regardless of what `minMidi` itself is.
    private var baseSlot: Double { Self.absoluteWhiteSlot(forPitch: minMidi) }

    /// The exact count of white keys actually present in `minMidi...maxMidi` — NOT
    /// `octaveCount * 7` (which over-counts whenever the range doesn't start/end exactly on
    /// octave boundaries, leaving the keyboard short of the view's full width).
    var whiteKeyCount: Int {
        (minMidi...maxMidi).lazy.filter { Self.whiteSlotBySemitone[((($0 % 12) + 12) % 12)] != nil }.count
    }

    // The pitch currently held down by a tap/click/drag, if any — nil whenever nothing is
    // being played through this view (as opposed to `heldPitches`, which reflects the
    // session's actual state and may include notes held via other input methods entirely,
    // e.g. a MIDI keyboard playing the same track simultaneously).
    @State private var pressedPitch: Int?

    func layout(for size: CGSize) -> (white: [KeyRect], black: [KeyRect]) {
        let whiteW = size.width / CGFloat(max(1, whiteKeyCount))
        let blackW = whiteW * 0.6
        let keysHeight = max(0, size.height - Self.badgeTopInset)
        let blackH = keysHeight * 0.62
        let base = baseSlot
        var white: [KeyRect] = []
        var black: [KeyRect] = []

        for pitch in minMidi...maxMidi {
            let pitchClass = ((pitch % 12) + 12) % 12
            let octave = pitch / 12
            if let whiteSlotInOctave = Self.whiteSlotBySemitone[pitchClass] {
                let slot = Double(octave * 7 + whiteSlotInOctave) - base
                let x = CGFloat(slot) * whiteW
                white.append(KeyRect(pitch: pitch, rect: CGRect(x: x, y: Self.badgeTopInset, width: whiteW, height: keysHeight)))
            } else if let whiteSlotBefore = Self.blackAfterWhiteSlot[pitchClass] {
                let slot = Double(octave * 7 + whiteSlotBefore + 1) - base
                let x = CGFloat(slot) * whiteW - blackW / 2
                black.append(KeyRect(pitch: pitch, rect: CGRect(x: x, y: Self.badgeTopInset, width: blackW, height: blackH)))
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
                // One badge per key belonging to the current mode (`degreeBadge`, independent
                // of `role`/held state — see `PitchDisplayState`'s doc comment), drawn after
                // every key so it always reads on top — mirrors the web's `.degree-badge`,
                // always shown for every mode-tone key regardless of what's actually held.
                var badges: [(rect: CGRect, degree: Int, pitchClass: Int)] = []

                // White keys first (background layer), then black keys on top — matches a
                // real keyboard's visual stacking.
                for key in white {
                    let state = pitchDisplayState(
                        pitch: key.pitch, heldPitches: heldPitches, chordRoot: chordRoot,
                        chordTones: chordTones, modeTones: modeTones,
                        alwaysShowChord: alwaysShowChord, showModeColoring: showModeColoring
                    )
                    let path = Path(key.rect.insetBy(dx: 0.5, dy: 0.5))
                    let fill = customFillColors[((key.pitch % 12) + 12) % 12] ?? colorScheme.fillColor(for: state.role, isWhiteKey: true)
                    context.fill(path, with: .color(fill))
                    context.stroke(path, with: .color(.black.opacity(0.4)), lineWidth: 1)
                    if let degree = state.degreeBadge {
                        badges.append((key.rect, degree, ((key.pitch % 12) + 12) % 12))
                    }
                }
                for key in black {
                    let state = pitchDisplayState(
                        pitch: key.pitch, heldPitches: heldPitches, chordRoot: chordRoot,
                        chordTones: chordTones, modeTones: modeTones,
                        alwaysShowChord: alwaysShowChord, showModeColoring: showModeColoring
                    )
                    let path = Path(key.rect)
                    let customFill = customFillColors[((key.pitch % 12) + 12) % 12]
                    context.fill(path, with: .color(customFill ?? colorScheme.fillColor(for: state.role, isWhiteKey: false)))
                    // A colored black key otherwise has no edge of its own (unlike a white key,
                    // which always gets a stroke) — a thin outline keeps its shape legible
                    // against whatever bright fill color it just got. Left undrawn for the
                    // default (uncolored) black fill so every other, unrelated keyboard keeps
                    // its plain look.
                    if customFill != nil || state.role != .none {
                        context.stroke(path, with: .color(.black), lineWidth: 1)
                    }
                    if let degree = state.degreeBadge {
                        badges.append((key.rect, degree, ((key.pitch % 12) + 12) % 12))
                    }
                }

                for badge in badges {
                    let bg = palette.indices.contains(badge.pitchClass) ? Color(hex: palette[badge.pitchClass]) : .accentColor
                    let fg = paletteTextColors.indices.contains(badge.pitchClass) ? Color(hex: paletteTextColors[badge.pitchClass]) : .white
                    let center = CGPoint(x: badge.rect.midX, y: Self.badgeTopInset / 2)
                    let circleRect = CGRect(
                        x: center.x - Self.badgeDiameter / 2, y: center.y - Self.badgeDiameter / 2,
                        width: Self.badgeDiameter, height: Self.badgeDiameter
                    )
                    context.fill(Path(ellipseIn: circleRect), with: .color(bg))
                    context.draw(Text("\(badge.degree)").font(.system(size: 9, weight: .bold)).foregroundStyle(fg), at: center)
                }

                if !keyLabels.isEmpty {
                    for key in white + black {
                        guard let label = keyLabels[key.pitch] else { continue }
                        let isWhite = white.contains { $0.pitch == key.pitch }
                        let point = CGPoint(x: key.rect.midX, y: key.rect.maxY - 14)
                        context.draw(
                            Text(label).font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(isWhite ? .black.opacity(0.55) : .white.opacity(0.85)),
                            at: point
                        )
                    }
                }

                if let highlightedPitches {
                    let keysInRange = (white + black).filter { highlightedPitches.contains($0.pitch) }
                    if let union = keysInRange.map(\.rect).reduce(nil, { (acc: CGRect?, rect) in acc?.union(rect) ?? rect }) {
                        context.stroke(Path(union.insetBy(dx: -1, dy: -1)), with: .color(.red), lineWidth: 2)
                    }
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
        .frame(height: height) // default 144 = +50% over 96 — explicit user request.
    }
}

public extension PitchKeyboardView {
    /// Builds the `keyLabels` dictionary this view already accepts (currently used for the
    /// computer-keyboard letter overlay) from a set of MIDI pitches, naming each one via
    /// `style` — the mechanism the Chord and Mode Library screens both reuse for the
    /// note-name "bullet" on each highlighted key, rather than each hand-rolling its own label
    /// lookup.
    static func noteNameKeyLabels(forPitches pitches: [Int], style: any NotationStyle, preferFlats: Bool = false) -> [Int: String] {
        Dictionary(pitches.map { ($0, style.rootName(PitchClass($0), preferFlats: preferFlats)) }, uniquingKeysWith: { first, _ in first })
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
