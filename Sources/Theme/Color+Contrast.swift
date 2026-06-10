import SwiftUI

/// A plain sRGB color value (components 0...1) that we can do math on.
/// SwiftUI's `Color` isn't introspectable, so all palette math happens on `RGB`
/// and only converts to `Color` at the very end.
struct RGB: Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    /// Parse "#RRGGBB" or "RRGGBB" (also tolerates "#RGB"). Falls back to mid-grey.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self.init(0.5, 0.5, 0.5); return
        }
        self.init(
            Double((v >> 16) & 0xFF) / 255.0,
            Double((v >> 8) & 0xFF) / 255.0,
            Double(v & 0xFF) / 255.0
        )
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

    var hexString: String {
        func c(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

// MARK: - WCAG 2.1 relative luminance & contrast

enum WCAG {
    private static func linearize(_ c: Double) -> Double {
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Relative luminance per WCAG 2.1 (0 = black, 1 = white).
    static func luminance(_ c: RGB) -> Double {
        0.2126 * linearize(c.r) + 0.7152 * linearize(c.g) + 0.0722 * linearize(c.b)
    }

    /// Contrast ratio between two colors (1...21). Order-independent.
    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        let hi = max(la, lb), lo = min(la, lb)
        return (hi + 0.05) / (lo + 0.05)
    }
}

// MARK: - Contrast enforcement (the design-critic's hard guardrail)
//
// Pastels are low-contrast by nature. To guarantee legibility we never trust a
// raw token: we nudge a foreground color toward black or white (whichever the
// background calls for) just until it clears a WCAG target — staying as close to
// the original designed color as possible.

extension RGB {
    private func mix(toward t: RGB, _ amount: Double) -> RGB {
        RGB(r + (t.r - r) * amount,
            g + (t.g - g) * amount,
            b + (t.b - b) * amount)
    }

    /// Returns this color, darkened or lightened the minimal amount needed so that
    /// `WCAG.contrast(result, background) >= minRatio`. If already passing, returns self.
    func enforcingContrast(against background: RGB, minRatio: Double) -> RGB {
        if WCAG.contrast(self, background) >= minRatio { return self }
        // Move away from the background's luminance: dark bg -> lighten, light bg -> darken.
        let target: RGB = WCAG.luminance(background) > 0.5 ? RGB(0, 0, 0) : RGB(1, 1, 1)
        var amount = 0.0
        var best = self
        while amount <= 1.0 {
            let candidate = mix(toward: target, amount)
            best = candidate
            if WCAG.contrast(candidate, background) >= minRatio { return candidate }
            amount += 0.02
        }
        return best // fully toward black/white — best achievable
    }
}

// MARK: - Legible filled-button derivation
//
// A pastel accent is too pale to carry a white label. We deepen the accent just
// enough that white text clears AA (4.5:1), giving a richer-but-on-brand button.

struct LegibleFill {
    let fill: RGB
    let label: RGB

    init(accent: RGB) {
        let white = RGB(1, 1, 1)
        let ink = RGB(0.16, 0.16, 0.18)
        // Prefer white text (the classic filled look); deepen the accent until it passes.
        var fill = accent
        var amount = 0.0
        while amount <= 1.0 {
            if WCAG.contrast(white, fill) >= 4.5 {
                self.fill = fill; self.label = white; return
            }
            amount += 0.04
            fill = RGB(accent.r * (1 - amount),
                       accent.g * (1 - amount),
                       accent.b * (1 - amount))
        }
        // Extremely unlikely fallback: dark accent already, use ink on the raw accent.
        self.fill = accent
        self.label = WCAG.contrast(white, accent) >= WCAG.contrast(ink, accent) ? white : ink
    }
}
