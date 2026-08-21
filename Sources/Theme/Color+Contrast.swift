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

    /// HSL → RGB. `h` in degrees 0...360, `s`/`l` in 0...1. Used to generate the
    /// rainbow pastel theme palette from evenly-spaced hues.
    init(h: Double, s: Double, l: Double) {
        if s == 0 { self.init(l, l, l); return }
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func hue2rgb(_ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        self.init(hue2rgb(hh + 1.0 / 3), hue2rgb(hh), hue2rgb(hh - 1.0 / 3))
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
        // Move to whichever end of the scale this background actually allows more
        // contrast against — black if darkening wins, white if lightening does.
        //
        // 🚨 2026-08-21: this used to split on `luminance(background) > 0.5`, which is
        // the wrong crossover. Black and white tie where (L+0.05)^2 = 0.0525, i.e. at
        // L ≈ 0.1791 — so every background between 0.1791 and 0.5 was pushed toward
        // white when black was the better direction. Measured on a mid-grey (L 0.214)
        // asking for 4.5:1: the old rule returned 3.84:1 where black reaches 5.28:1.
        // None of the 15 shipped themes has a backdrop in that band (checked bg,
        // surface, ringTrack and accentSoft in light and dark), so nothing on screen
        // changes today — this is the latent half of the bug, fixed before a
        // mid-luminance theme walks into it.
        let black = RGB(0, 0, 0), white = RGB(1, 1, 1)
        let target: RGB = WCAG.contrast(black, background) >= WCAG.contrast(white, background)
            ? black : white
        var amount = 0.0
        var best = self
        while amount <= 1.0 {
            let candidate = mix(toward: target, amount)
            best = candidate
            if WCAG.contrast(candidate, background) >= minRatio { return candidate }
            amount += 0.02
        }
        // Target unreachable against this background (e.g. 7:1 on a mid-grey): give
        // back the far end of the search — the last 0.02 step, so ~98% of the way to
        // black/white rather than exactly there. Close enough that the difference is
        // invisible, and none of the shipped themes take this path.
        return best
    }
}

// 2026-08-21: a "Widget control chrome" block sat here describing `WidgetChrome`,
// the 3:1 outline the widget's round buttons needed (PR #10). The widget went in
// PR #33 and took the code with it; only the prose was left, and it broke off
// mid-sentence. Removed.

// MARK: - Legible filled-button derivation
//
// A pastel accent is too pale to carry a white label. We deepen the accent just
// enough that white text clears AA (4.5:1), giving a richer-but-on-brand button.

struct LegibleFill {
    let fill: RGB
    let label: RGB

    init(accent: RGB) {
        let white = RGB(1, 1, 1)
        let ink = RGB(0.13, 0.12, 0.15)
        let cWhite = WCAG.contrast(white, accent)
        let cInk = WCAG.contrast(ink, accent)
        // KEEP the bright candy accent whenever a label reads well on it — light
        // accents (yellow, mint…) take dark ink. This avoids muddy "deepened"
        // buttons (e.g. yellow turning olive to host white text).
        if max(cWhite, cInk) >= 4.5 {
            self.fill = accent
            self.label = cInk >= cWhite ? ink : white
            return
        }
        // Mid-tone accent that neither label clears: deepen until white passes.
        var fill = accent
        var amount = 0.0
        while amount < 1.0 {
            amount += 0.04
            fill = RGB(accent.r * (1 - amount),
                       accent.g * (1 - amount),
                       accent.b * (1 - amount))
            if WCAG.contrast(white, fill) >= 4.5 { break }
        }
        self.fill = fill
        self.label = white
    }
}
