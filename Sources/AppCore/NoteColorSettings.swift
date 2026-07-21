/// Persisted role-based note colors, shared by the terminal, the read-only web console, and
/// the virtual keyboard page — a "role" here is a fixed highlight meaning (mode root, chord
/// root, held-but-not-in-chord...), not a specific pitch class (see `ColorPalette` for the
/// 12-hex-colors-by-pitch-class system, an entirely separate, already-configurable axis).
/// Mirrors `LumiSettingsFile`'s "singleton value file" shape, persisted to `note-colors.json`
/// in the settings folder.
///
/// Defaults intentionally match the values already hand-picked for the web console's/virtual
/// keyboard's CSS (`.pkey.root` etc. in `WebConsole/StaticAssets.swift`/`VirtualKeyboardAssets
/// .swift`) — those were designed first; the terminal's own `KeyboardColor` now renders these
/// same hex values as 24-bit ANSI instead of its old fixed 16-color codes, so a color looks
/// the same regardless of which surface is showing it (previously the terminal's "bold
/// magenta"/"bold yellow"/etc. rendered however the user's own terminal theme happened to
/// define those 16 colors — a real, if minor, behavior change: these highlights now ignore
/// the terminal color theme in favor of an exact, cross-surface-consistent hex value).
///
/// No editing UI (menu items/web actions) yet, unlike `LumiSettingsFile` — hand-edit
/// `note-colors.json` and reload the settings folder (or relaunch) to pick up a change. Add
/// one if hand-editing turns out to be too much friction in practice.
public struct NoteColorSettingsFile: Codable, Equatable {
    /// The mode keyboard's tonic (see the Guide screen's mode keyboard, and any future
    /// mode-degree-line reuse elsewhere).
    public var modeRootHex: String
    /// The mode keyboard's other in-mode notes.
    public var modeOtherHex: String
    /// A recognized/proposed chord's root.
    public var chordRootHex: String
    /// A recognized/proposed chord's other tones.
    public var chordToneHex: String
    /// A held pitch with no chord context to judge it against (too few notes, or nothing
    /// recognized yet).
    public var heldNoChordHex: String
    /// A held pitch that IS accompanied by a recognized chord, but isn't part of it.
    public var heldOutsideChordHex: String

    public init(
        modeRootHex: String = "#ff9800",
        modeOtherHex: String = "#00bcd4",
        chordRootHex: String = "#e91e63",
        chordToneHex: String = "#fdd835",
        heldNoChordHex: String = "#ffffff",
        heldOutsideChordHex: String = "#4caf50"
    ) {
        self.modeRootHex = modeRootHex
        self.modeOtherHex = modeOtherHex
        self.chordRootHex = chordRootHex
        self.chordToneHex = chordToneHex
        self.heldNoChordHex = heldNoChordHex
        self.heldOutsideChordHex = heldOutsideChordHex
    }
}
