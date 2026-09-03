import Foundation

/// How a picked colour is written to the clipboard.
public enum ColorFormat: String, Codable, CaseIterable {
    case hex          // #4A90D9
    case hexLower     // #4a90d9
    case rgb          // rgb(74, 144, 217)
    case rgba         // rgba(74, 144, 217, 1)
    case hsl          // hsl(211, 65%, 57%)
    case swiftUI      // Color(red: 0.290, green: 0.565, blue: 0.851)
    case nsColor      // NSColor(srgbRed: 0.290, green: 0.565, blue: 0.851, alpha: 1.000)
    case components   // 74, 144, 217

    public var title: String {
        switch self {
        case .hex:        return "Hex — #4A90D9"
        case .hexLower:   return "Hex lowercase — #4a90d9"
        case .rgb:        return "CSS rgb()"
        case .rgba:       return "CSS rgba()"
        case .hsl:        return "CSS hsl()"
        case .swiftUI:    return "SwiftUI Color"
        case .nsColor:    return "AppKit NSColor"
        case .components: return "Plain components"
        }
    }
}

public enum ColorFormatter {

    /// Formats a colour given components in the 0...1 range.
    ///
    /// Values are clamped rather than trusted: `NSColorSampler` can hand back
    /// components slightly outside 0...1 for colours in a wide-gamut display
    /// profile, which would otherwise produce nonsense like `#10A` or a
    /// negative percentage.
    public static func string(red: Double, green: Double, blue: Double, alpha: Double = 1,
                              format: ColorFormat) -> String {
        let r = clamp(red), g = clamp(green), b = clamp(blue), a = clamp(alpha)
        let r255 = Int((r * 255).rounded())
        let g255 = Int((g * 255).rounded())
        let b255 = Int((b * 255).rounded())

        switch format {
        case .hex:
            return String(format: "#%02X%02X%02X", r255, g255, b255)
        case .hexLower:
            return String(format: "#%02x%02x%02x", r255, g255, b255)
        case .rgb:
            return "rgb(\(r255), \(g255), \(b255))"
        case .rgba:
            return "rgba(\(r255), \(g255), \(b255), \(trimmed(a)))"
        case .hsl:
            let (h, s, l) = hsl(r: r, g: g, b: b)
            return "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
        case .swiftUI:
            return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", r, g, b)
        case .nsColor:
            return String(format: "NSColor(srgbRed: %.3f, green: %.3f, blue: %.3f, alpha: %.3f)", r, g, b, a)
        case .components:
            return "\(r255), \(g255), \(b255)"
        }
    }

    /// Hue in degrees, saturation and lightness in 0...1.
    public static func hsl(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let l = (maxC + minC) / 2
        let delta = maxC - minC

        guard delta > 1e-9 else { return (0, 0, l) }   // grey: hue is undefined

        // Denominator flips at l = 0.5; both branches are the standard formula.
        let s = l > 0.5 ? delta / (2 - maxC - minC) : delta / (maxC + minC)

        var h: Double
        if maxC == r {
            h = (g - b) / delta + (g < b ? 6 : 0)
        } else if maxC == g {
            h = (b - r) / delta + 2
        } else {
            h = (r - g) / delta + 4
        }
        h *= 60
        return (h, s, l)
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }

    /// Drops a trailing ".0" so alpha reads as `1` rather than `1.0`.
    private static func trimmed(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }
}
