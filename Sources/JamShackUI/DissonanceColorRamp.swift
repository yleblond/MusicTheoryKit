import SwiftUI

/// The diverging (blue → neutral gray → red) color ramp shared by every Dissonances-screen
/// rendering mode (`DissonanceHeatmapView`'s 2D cells, `DissonanceSurfaceView`'s 3D mesh faces) —
/// factored out so both stay visually identical rather than drifting apart. Matches a reference
/// palette supplied by the user, sampled directly from its color-bar image (13 evenly-spaced
/// stops) rather than generated — blue nearest zero/consonant, gray at the midpoint, red nearest
/// the loudest roughness peak.
public enum DissonanceColorRamp {
    private static let stops: [(step: Double, hex: String)] = [
        (100, "#0c13ab"), (150, "#242dbb"), (200, "#3a49ca"), (250, "#5365db"),
        (300, "#6980eb"), (350, "#8b9add"), (400, "#b2b5c3"), (450, "#c9b3a1"),
        (500, "#d6a57e"), (550, "#d99364"), (600, "#ca7653"), (650, "#bd5b43"), (700, "#af4034"),
    ]

    public static func color(forNormalized t: Double) -> Color {
        let clamped = max(0, min(1, t))
        let steps = stops.map(\.step)
        let target = steps.first! + clamped * (steps.last! - steps.first!)
        guard let upperIndex = steps.firstIndex(where: { $0 >= target }), upperIndex > 0 else {
            return Color(hex: stops[clamped < 0.5 ? 0 : stops.count - 1].hex)
        }
        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let localT = (target - lower.step) / (upper.step - lower.step)
        return blendedHex(lower.hex, upper.hex, fraction: localT)
    }

    /// Direct hex→hex linear RGB blend (0 = `hexA`, 1 = `hexB`) — computed straight from the hex
    /// components (like `Color.pastel`/`Tonnetz.pastel`), not by resolving either `Color` back to
    /// RGB (unsafe inside a `Canvas` draw closure, no live environment there).
    private static func blendedHex(_ hexA: String, _ hexB: String, fraction: Double) -> Color {
        guard let a = rgbComponents(fromHex: hexA), let b = rgbComponents(fromHex: hexB) else { return Color(hex: hexB) }
        let t = max(0, min(1, fraction))
        return Color(red: a.r + (b.r - a.r) * t, green: a.g + (b.g - a.g) * t, blue: a.b + (b.b - a.b) * t)
    }

    private static func rgbComponents(fromHex hex: String) -> (r: Double, g: Double, b: Double)? {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}
