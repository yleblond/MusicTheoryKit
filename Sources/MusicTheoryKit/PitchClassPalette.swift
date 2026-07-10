/// A fixed color per chromatic pitch class (index 0 = C ... 11 = B), "mycolormusic"-style:
/// a note keeps the same color no matter which mode/key it's functioning in. Extracted by
/// sampling the physical wheel photographed in `Sources/Colors/Colors.PNG` (project root,
/// sibling to `MusicTheoryKit/`) — each of the 12 shapes' fill color, read off and matched
/// to its own pitch class. Reading these in ascending-fifths (physical wheel) order rather
/// than chromatic order reveals why they were chosen: they form a smooth rainbow around the
/// wheel (C=red ... F#=green ... F=magenta, back to C=red) — NOT smooth in raw chromatic
/// order, which is expected, since the physical wheel is arranged by fifths, not by semitone.
///
/// This is only ever the *fallback* default now — see `AppCore.ImprovSession`'s color-palette
/// loading (`ColorPalette`/`palettes.json`) for the actual, user-selectable, per-instance
/// active palette this seeds the first time that file is created. `WebConsole` has no
/// dependency on `MusicTheoryKit` by design, so `StaticAssets.swift`/`VirtualKeyboardAssets.swift`
/// keep a hand-written JS mirror of this exact table (`PITCH_CLASS_COLORS`) as their own
/// fallback, overwritten at runtime by whichever palette `GET /state` reports active — same
/// "no compiler-enforced contract, kept in sync by hand" convention as the JSON contract
/// documented on `webConsoleIndexHTML`/`webConsoleAppJS`.
public enum PitchClassPalette {
    public static let hex: [String] = [
        "#DB2A52", "#0AAD9A", "#F7872D", "#4169B7", "#F2DE18", "#AE2F93",
        "#44B853", "#F15830", "#249CD7", "#FEBC20", "#884A9C", "#ABD144",
    ]
}
