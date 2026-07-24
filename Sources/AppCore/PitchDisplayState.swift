/// What a given pitch's key should look like in any keyboard-shaped UI (ASCII terminal, the
/// web console's `keyboardHTML`, or a future SwiftUI `PitchKeyboardView`) — the classification
/// logic itself, extracted once here so it isn't re-derived per presentation layer. Mirrors
/// `Sources/WebConsole/StaticAssets.swift`'s `keyboardHTML` decision tree exactly; the web
/// console's own JS stays a separate implementation since JS can't share code with Swift, but
/// every Swift-side renderer (terminal, SwiftUI) should call this instead of re-deriving it.
public enum PitchDisplayRole: Equatable, Sendable {
    case chordRoot
    case chordTone
    case heldOutsideChord
    case held
    case modeRoot
    case modeTone
    case none
}

public struct PitchDisplayState: Equatable, Sendable {
    public let role: PitchDisplayRole
    /// The pitch class's scale degree (1-based) if it belongs to the current mode, else `nil`.
    public let degreeBadge: Int?

    public init(role: PitchDisplayRole, degreeBadge: Int?) {
        self.role = role
        self.degreeBadge = degreeBadge
    }
}

/// - Parameters:
///   - pitch: absolute MIDI pitch of the key being classified.
///   - heldPitches: absolute MIDI pitches currently held on this track.
///   - chordRoot: the recognized chord's root pitch class (0...11), or `nil` if none recognized.
///   - chordTones: the recognized chord's pitch classes (0...11), including the root.
///   - modeTones: the current mode's pitch classes in scale-degree order (index 0 = degree 1,
///     the tonic) — empty if no mode is being shown.
///   - alwaysShowChord: color the chord's root/tones even when not currently held (used by the
///     Guide screen's reference keyboard).
///   - showModeColoring: fall back to mode-root/mode-tone coloring for keys not already colored
///     by the held/chord branch above (used by the Guide screen's mode keyboard).
public func pitchDisplayState(
    pitch: Int,
    heldPitches: Set<Int>,
    chordRoot: Int?,
    chordTones: [Int],
    modeTones: [Int],
    alwaysShowChord: Bool = false,
    showModeColoring: Bool = false
) -> PitchDisplayState {
    let pitchClass = ((pitch % 12) + 12) % 12
    let tones = Set(chordTones)
    let modeRootPitchClass = modeTones.first
    let degreeByPitchClass = Dictionary(uniqueKeysWithValues: modeTones.enumerated().map { ($1, $0 + 1) })
    let degreeBadge = degreeByPitchClass[pitchClass]
    let isChordRoot = chordRoot != nil && pitchClass == chordRoot

    var role: PitchDisplayRole = .none
    if heldPitches.contains(pitch) {
        if isChordRoot {
            role = .chordRoot
        } else if tones.contains(pitchClass) {
            role = .chordTone
        } else if chordRoot != nil {
            role = .heldOutsideChord
        } else {
            role = .held
        }
    } else if alwaysShowChord {
        if isChordRoot {
            role = .chordRoot
        } else if tones.contains(pitchClass) {
            role = .chordTone
        }
    }

    if role == .none, showModeColoring {
        if pitchClass == modeRootPitchClass {
            role = .modeRoot
        } else if degreeBadge != nil {
            role = .modeTone
        }
    }

    return PitchDisplayState(role: role, degreeBadge: degreeBadge)
}
