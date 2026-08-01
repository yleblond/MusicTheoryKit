import SwiftUI
#if os(iOS) || os(visionOS)
import UIKit
#else
import AppKit
#endif

/// "#RRGGBB" <-> `Color` round-trip for the LUMI settings (`rootColorHex`/`scaleColorHex`),
/// which `ColorPicker` needs as a `Color` binding but `ImprovSession` stores/sends as hex
/// strings (same wire shape the web console's LUMI panel uses).
extension Color {
    init(hex: String) {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            self = .black
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }

    var hexString: String {
        #if os(iOS) || os(visionOS)
        let components = UIColor(self).cgColor.components ?? [0, 0, 0]
        #else
        let components = NSColor(self).usingColorSpace(.deviceRGB)?.cgColor.components ?? [0, 0, 0]
        #endif
        let r = Int((components.count > 0 ? components[0] : 0) * 255)
        let g = Int((components.count > 1 ? components[1] : 0) * 255)
        let b = Int((components.count > 2 ? components[2] : 0) * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
