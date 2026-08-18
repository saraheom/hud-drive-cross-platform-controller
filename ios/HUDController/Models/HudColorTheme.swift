import SwiftUI

/// Exact palette reverse-engineered from the original HUDWAY Drive 1.4.6
/// `HwColorTable.kt`.
///
/// The labels and raw RGB values intentionally look unusual. Do not replace
/// these with conventional named colors: these are the values the stock app
/// sends to the physical HUD.
enum HudColorTheme: String, CaseIterable, Identifiable {
    case red = "Red"
    case green = "Green"
    case blue = "Blue"
    case magenta = "Magenta"
    case black = "Black"
    case yellow = "Yellow"
    case grey = "Grey"
    case cyan = "Cyan"
    case ivory = "Ivory"
    case maroon = "Maroon"

    var id: String { rawValue }

    /// Android `Color.parseColor(...)` source value from HwColorTable.
    var rgbHex: String {
        switch self {
        case .red:     return "25E6F5"
        case .green:   return "F2357B"
        case .blue:    return "25F553"
        case .magenta: return "4091F0"
        case .black:   return "995EE5"
        case .yellow:  return "D825F5"
        case .grey:    return "1229F6"
        case .cyan:    return "FFFFFF"
        case .ivory:   return "F49238"
        case .maroon:  return "F1F525"
        }
    }

    /// Stock Android path:
    /// Color.parseColor("#RRGGBB") -> ARGB Int -> Integer.toHexString(int)
    /// -> setHudBaseColor("#" + hex).
    ///
    /// For these opaque colors that produces "#ffRRGGBB".
    var originalWireValue: String {
        "#ff\(rgbHex.lowercased())"
    }

    var previewColor: Color {
        let value = UInt64(rgbHex, radix: 16) ?? 0
        let r = Double((value >> 16) & 0xff) / 255.0
        let g = Double((value >> 8) & 0xff) / 255.0
        let b = Double(value & 0xff) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
