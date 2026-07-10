import Foundation
import MusicTheoryKit

/// One named set of 12 colors, one per chromatic pitch class (index 0 = C ... 11 = B), plus a
/// matching text color per note for legibility (a light background needs dark text and vice
/// versa) — see `ImprovSession.loadColorPalettes`/`activeColorPalette`. Which palette is
/// *active* is per-instance and never persisted across a relaunch (defaults to the first one
/// in the file every time) — only the available palettes themselves live in `palettes.json`.
public struct ColorPalette: Codable, Equatable, Sendable {
    public var name: String
    public var colors: [String]
    /// One text color per note, same indexing as `colors` — deliberately a hand-picked
    /// per-palette choice, not purely formulaic (see `builtInDefaults`'s "Default": white
    /// for every note except A/E/B, its 3 brightest background colors, which need black
    /// text — a choice a luminance formula alone wouldn't have reliably reproduced for every
    /// note, e.g. D and F# sit close in brightness to A/E/B but read fine in white).
    public var textColors: [String]

    public init(name: String, colors: [String], textColors: [String]) {
        self.name = name
        self.colors = colors
        self.textColors = textColors
    }

    /// `textColors` is `decodeIfPresent` — older `palettes.json` files (or a hand-added
    /// palette that only bothers to list `colors`) fall back to `Self.legibleTextColors(for:)`
    /// rather than failing to decode at all.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        colors = try container.decode([String].self, forKey: .colors)
        textColors = try container.decodeIfPresent([String].self, forKey: .textColors) ?? Self.legibleTextColors(for: colors)
    }

    private enum CodingKeys: String, CodingKey {
        case name, colors, textColors
    }

    /// White-or-black-per-color fallback for any palette that doesn't specify its own
    /// `textColors` by hand — perceived-brightness (YIQ) threshold, tuned to read reasonably
    /// across a wide range of hues rather than to reproduce `builtInDefaults`'s own
    /// hand-picked exceptions exactly (those are always explicit, never fall back to this).
    public static func legibleTextColors(for colors: [String]) -> [String] {
        colors.map { hex in
            guard let (r, g, b) = Self.rgb(fromHex: hex) else { return "#ffffff" }
            let yiq = (Double(r) * 299 + Double(g) * 587 + Double(b) * 114) / 1000
            return yiq > 150 ? "#111111" : "#ffffff"
        }
    }

    private static func rgb(fromHex hex: String) -> (Int, Int, Int)? {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }

    /// Seeded into a fresh `palettes.json` the first time none exists (see
    /// `ImprovSession.loadOrCreateColorPalettes`) — "Default" mirrors
    /// `MusicTheoryKit.PitchClassPalette.hex` (itself sampled from the physical wheel in
    /// `Sources/Colors/Colors.PNG`, project root); "Contraste" and "Pastel" are two
    /// deliberately different-looking sets, mostly so there's something to actually pick
    /// between the first time this feature is tried.
    public static let builtInDefaults: [ColorPalette] = [
        ColorPalette(
            name: "Default",
            colors: PitchClassPalette.hex,
            // C  Db   D   Eb   E    F   F#   G   Ab   A   Bb   B
            textColors: [
                "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#111111", "#ffffff",
                "#ffffff", "#ffffff", "#ffffff", "#111111", "#ffffff", "#111111",
            ]
        ),
        ColorPalette(
            name: "Contraste",
            colors: [
                "#e6194B", "#f58231", "#ffe119", "#bfef45", "#3cb44b", "#42d4f4",
                "#4363d8", "#911eb4", "#f032e6", "#fabed4", "#469990", "#9A6324",
            ],
            textColors: legibleTextColors(for: [
                "#e6194B", "#f58231", "#ffe119", "#bfef45", "#3cb44b", "#42d4f4",
                "#4363d8", "#911eb4", "#f032e6", "#fabed4", "#469990", "#9A6324",
            ])
        ),
        ColorPalette(
            name: "Pastel",
            colors: [
                "#FFADAD", "#FFD6A5", "#FDFFB6", "#CAFFBF", "#9BF6FF", "#A0C4FF",
                "#BDB2FF", "#FFC6FF", "#FFC9DE", "#C9C9FF", "#B5EAD7", "#E2F0CB",
            ],
            // Every pastel is light enough that black reads best across the board — no
            // exceptions needed here, unlike "Default"/"Contraste".
            textColors: Array(repeating: "#111111", count: 12)
        ),
    ]
}

/// The on-disk shape of `palettes.json` — a flat list under one key, not one file per palette
/// (unlike `Scene`/`GuideSequence`): there are only ever a handful of palettes, and picking
/// one is a single quick choice, not something that benefits from its own folder of
/// individually-named files.
struct ColorPaletteFile: Codable {
    var palettes: [ColorPalette]
}
