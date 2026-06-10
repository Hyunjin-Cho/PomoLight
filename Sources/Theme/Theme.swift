import SwiftUI

/// The eight raw color tokens for one appearance (light or dark) of a theme.
/// Stored as hex strings so a theme is trivially Codable and editable.
struct ThemeColors: Codable, Hashable {
    var bg: String
    var surface: String
    var accent: String
    var accentSoft: String
    var text: String
    var textSecondary: String
    var ringTrack: String
    var ringFill: String
}

/// A named pastel theme with fully authored light AND dark color sets.
struct Theme: Identifiable, Hashable {
    let id: String
    let name: String
    let mood: String
    let light: ThemeColors
    let dark: ThemeColors
    var isCustom: Bool = false

    func colors(for scheme: ColorScheme) -> ThemeColors {
        scheme == .dark ? dark : light
    }

    /// A representative swatch color (the light accent) for the picker dots.
    var swatch: Color { RGB(hex: light.accent).color }
}

// MARK: - Built-in pastel presets — a 15-swatch rainbow

extension Theme {
    /// Generates a cozy pastel palette (light + dark) from a single hue. The Palette
    /// layer enforces WCAG contrast on top, so legibility is guaranteed for any hue.
    private static func pastel(_ id: String, _ name: String,
                               hue h: Double, sat: Double = 0.58) -> Theme {
        let light = ThemeColors(
            bg:            RGB(h: h, s: min(sat, 0.42), l: 0.965).hexString,
            surface:       RGB(h: h, s: min(sat, 0.30), l: 0.992).hexString,
            accent:        RGB(h: h, s: sat,            l: 0.68).hexString,
            accentSoft:    RGB(h: h, s: min(sat, 0.52), l: 0.88).hexString,
            text:          RGB(h: h, s: min(sat, 0.32), l: 0.26).hexString,
            textSecondary: RGB(h: h, s: min(sat, 0.22), l: 0.50).hexString,
            ringTrack:     RGB(h: h, s: min(sat, 0.38), l: 0.90).hexString,
            ringFill:      RGB(h: h, s: sat,            l: 0.62).hexString)
        let dark = ThemeColors(
            bg:            RGB(h: h, s: min(sat, 0.24), l: 0.10).hexString,
            surface:       RGB(h: h, s: min(sat, 0.20), l: 0.155).hexString,
            accent:        RGB(h: h, s: min(sat, 0.60), l: 0.70).hexString,
            accentSoft:    RGB(h: h, s: min(sat, 0.35), l: 0.30).hexString,
            text:          RGB(h: h, s: min(sat, 0.16), l: 0.92).hexString,
            textSecondary: RGB(h: h, s: min(sat, 0.14), l: 0.70).hexString,
            ringTrack:     RGB(h: h, s: min(sat, 0.26), l: 0.26).hexString,
            ringFill:      RGB(h: h, s: min(sat, 0.60), l: 0.68).hexString)
        return Theme(id: id, name: name, mood: "", light: light, dark: dark)
    }

    /// 15 distinct pastels sweeping the hue wheel (warm → cool → neutral).
    static let presets: [Theme] = [
        pastel("butter",     "Butter",     hue: 48),
        pastel("peach",      "Peach",      hue: 26),
        pastel("coral",      "Coral",      hue: 8),
        pastel("rose",       "Rose",       hue: 342),
        pastel("orchid",     "Orchid",     hue: 312),
        pastel("lavender",   "Lavender",   hue: 278),
        pastel("periwinkle", "Periwinkle", hue: 250),
        pastel("bluebell",   "Bluebell",   hue: 224),
        pastel("sky",        "Sky",        hue: 204),
        pastel("aqua",       "Aqua",       hue: 190),
        pastel("mint",       "Mint",       hue: 168),
        pastel("meadow",     "Meadow",     hue: 145),
        pastel("sage",       "Sage",       hue: 112),
        pastel("lime",       "Lime",       hue: 84),
        pastel("greige",     "Greige",     hue: 40, sat: 0.10),
    ]

    static var `default`: Theme { preset(id: "peach") ?? presets[0] }

    static func preset(id: String) -> Theme? { presets.first { $0.id == id } }
}

// MARK: - Resolved, contrast-guaranteed palette used by the views
//
// Every color a view actually draws comes from here. Text and ring colors are
// passed through WCAG enforcement so legibility never depends on the pastel.

struct Palette {
    let bg: Color
    let surface: Color
    let accent: Color          // raw accent — used only for non-text accents (glow, idle ring, swatch)
    let accentSoft: Color      // soft fills (chips at rest, halos)
    let ringTrack: Color
    let ringFill: Color        // >= 3:1 vs ringTrack
    let timerText: Color       // >= 7:1 vs background (the hero numerals)
    let primaryText: Color     // >= 7:1 vs surface/bg
    let secondaryText: Color   // >= 4.5:1 vs surface/bg
    let buttonFill: Color      // deepened accent so a white label is legible
    let buttonLabel: Color
    let onAccentSoft: Color    // legible label on an accentSoft fill

    init(_ c: ThemeColors) {
        let bg = RGB(hex: c.bg)
        let surface = RGB(hex: c.surface)
        let accent = RGB(hex: c.accent)
        let accentSoft = RGB(hex: c.accentSoft)
        let text = RGB(hex: c.text)
        let secondary = RGB(hex: c.textSecondary)
        let ringTrack = RGB(hex: c.ringTrack)
        let ringFill = RGB(hex: c.ringFill)

        self.bg = bg.color
        self.surface = surface.color
        self.accent = accent.color
        self.accentSoft = accentSoft.color
        self.ringTrack = ringTrack.color

        // Hero numerals: AAA (7:1) against whichever backdrop is harder.
        self.timerText = text
            .enforcingContrast(against: bg, minRatio: 7.0)
            .enforcingContrast(against: surface, minRatio: 7.0)
            .color
        self.primaryText = text
            .enforcingContrast(against: bg, minRatio: 7.0)
            .enforcingContrast(against: surface, minRatio: 7.0)
            .color
        self.secondaryText = secondary
            .enforcingContrast(against: bg, minRatio: 4.5)
            .enforcingContrast(against: surface, minRatio: 4.5)
            .color

        // Ring fill must be distinguishable from its track (UI element, 3:1).
        self.ringFill = ringFill.enforcingContrast(against: ringTrack, minRatio: 3.0).color

        // Deepen accent until a white label clears AA, for filled buttons/chips.
        let legible = LegibleFill(accent: accent)
        self.buttonFill = legible.fill.color
        self.buttonLabel = legible.label.color

        // Legible label on the pale accentSoft fill.
        self.onAccentSoft = text
            .enforcingContrast(against: accentSoft, minRatio: 4.5)
            .color
    }
}
