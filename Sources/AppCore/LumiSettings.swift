/// Persisted LUMI configuration: the two colors + brightness the "run"/"guide" live
/// displays use, and whether the Run/Guide Musical screens should automatically drive the
/// LUMI at all (see `ImprovSession.notifyActiveScreen`) rather than needing `lumi-run`/
/// `lumi-guide-sync` typed by hand every session. Mirrors `LanguageSettingFile`'s "singleton
/// value file" shape (`Sources/Localization/Localization.swift`), persisted to `lumi.json`
/// in the settings folder the same way `ImprovSession.setLanguage` persists `language.json`.
///
/// Defaults: root red / everything-else blue (not green — an earlier manual-testing default,
/// deliberately not carried over here), both auto-propagate toggles on, full brightness —
/// so a fresh install already lights up the LUMI automatically rather than needing every
/// setting touched by hand first.
public struct LumiSettingsFile: Codable, Equatable {
    public var rootColorHex: String
    public var scaleColorHex: String
    public var brightnessPercentage: Int
    public var autoPropagateRunMode: Bool
    public var autoPropagateGuideMode: Bool

    public init(
        rootColorHex: String = "#FF0000",
        scaleColorHex: String = "#0000FF",
        brightnessPercentage: Int = 100,
        autoPropagateRunMode: Bool = true,
        autoPropagateGuideMode: Bool = true
    ) {
        self.rootColorHex = rootColorHex
        self.scaleColorHex = scaleColorHex
        self.brightnessPercentage = brightnessPercentage
        self.autoPropagateRunMode = autoPropagateRunMode
        self.autoPropagateGuideMode = autoPropagateGuideMode
    }
}

/// Turns a `#RRGGBB` (or bare `RRGGBB`) string into the `UInt8` triple `LumiSysex.setColor`
/// takes — `nil` for anything else (wrong length, non-hex characters). A near-duplicate of
/// `ColorPalette`'s own private `rgb(fromHex:)`: that one returns `(Int, Int, Int)` for
/// palette/text-color-contrast math, this one needs `UInt8` specifically for the SysEx
/// encoder — not worth changing that existing, already-tested helper's signature just to
/// share four lines.
public enum LumiColorHex {
    public static func rgb(_ hex: String) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        var digits = hex
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return (UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF))
    }
}
