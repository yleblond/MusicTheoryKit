/// A fixed color per chromatic pitch class (index 0 = C ... 11 = B), "mycolormusic"-style:
/// a note keeps the same color no matter which mode/key it's functioning in. Values are a
/// starting aesthetic choice (distinct, colorblind-friendly-ish hues), not a reproduction of
/// any specific physical product's exact printed colors.
///
/// `WebConsole` has no dependency on `MusicTheoryKit` by design, so `StaticAssets.swift`
/// keeps a hand-written JS mirror of this exact table (`PITCH_CLASS_COLORS`) — same
/// "no compiler-enforced contract, kept in sync by hand" convention as the JSON contract
/// documented on `webConsoleIndexHTML`/`webConsoleAppJS`.
public enum PitchClassPalette {
    public static let hex: [String] = [
        "#e6194B", "#f58231", "#ffe119", "#bfef45", "#3cb44b", "#42d4f4",
        "#4363d8", "#911eb4", "#f032e6", "#fabed4", "#469990", "#9A6324",
    ]
}
