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
    // Recipe tuned by the color team for a genuine soft-pastel feel (master
    // saturation 0.44, raised lightness) — pastel yet still 15 distinct hues.
    private static func pastel(_ id: String, _ name: String,
                               hue h: Double, sat: Double = 0.44) -> Theme {
        let light = ThemeColors(
            bg:            RGB(h: h, s: min(sat, 0.30), l: 0.972).hexString,
            surface:       RGB(h: h, s: min(sat, 0.22), l: 0.994).hexString,
            accent:        RGB(h: h, s: sat,            l: 0.74).hexString,
            accentSoft:    RGB(h: h, s: min(sat, 0.40), l: 0.91).hexString,
            text:          RGB(h: h, s: min(sat, 0.30), l: 0.26).hexString,
            textSecondary: RGB(h: h, s: min(sat, 0.20), l: 0.50).hexString,
            ringTrack:     RGB(h: h, s: min(sat, 0.30), l: 0.915).hexString,
            ringFill:      RGB(h: h, s: sat,            l: 0.64).hexString)
        let dark = ThemeColors(
            bg:            RGB(h: h, s: min(sat, 0.20), l: 0.105).hexString,
            surface:       RGB(h: h, s: min(sat, 0.17), l: 0.16).hexString,
            accent:        RGB(h: h, s: min(sat, 0.48), l: 0.72).hexString,
            accentSoft:    RGB(h: h, s: min(sat, 0.32), l: 0.32).hexString,
            text:          RGB(h: h, s: min(sat, 0.16), l: 0.92).hexString,
            textSecondary: RGB(h: h, s: min(sat, 0.14), l: 0.70).hexString,
            ringTrack:     RGB(h: h, s: min(sat, 0.24), l: 0.265).hexString,
            ringFill:      RGB(h: h, s: min(sat, 0.48), l: 0.68).hexString)
        return Theme(id: id, name: name, mood: "", light: light, dark: dark)
    }

    /// 15 pastels in a rainbow sweep — pink → red → orange → yellow → green →
    /// blue → indigo → violet → magenta (빨주노초파남보 + pinks). No greys.
    static let presets: [Theme] = [
        pastel("pink",    "Pink",    hue: 334),
        pastel("rose",    "Rose",    hue: 350),
        pastel("red",     "Red",     hue: 8),
        pastel("coral",   "Coral",   hue: 22),
        pastel("orange",  "Orange",  hue: 36),
        pastel("yellow",  "Yellow",  hue: 52),
        pastel("lime",    "Lime",    hue: 84),
        pastel("green",   "Green",   hue: 128),
        pastel("mint",    "Mint",    hue: 158),
        pastel("teal",    "Teal",    hue: 182),
        pastel("sky",     "Sky",     hue: 202),
        pastel("blue",    "Blue",    hue: 224),
        pastel("indigo",  "Indigo",  hue: 252),
        pastel("violet",  "Violet",  hue: 282),
        pastel("magenta", "Magenta", hue: 312),
    ]

    static var `default`: Theme { preset(id: "coral") ?? presets[0] }

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
