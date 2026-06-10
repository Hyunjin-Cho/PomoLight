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
/// Dark sets are hand-tuned (not derived) so pastels never turn to mud at night.
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

// MARK: - Built-in pastel presets (authored by the design team)

extension Theme {
    static let presets: [Theme] = [
        Theme(
            id: "peach", name: "Peach Cream",
            mood: "Warm, cozy — late-afternoon sunlight on a wall.",
            light: ThemeColors(bg: "#FBF3EC", surface: "#FFFBF7", accent: "#F0A07A", accentSoft: "#FBDFCF",
                               text: "#4A3A30", textSecondary: "#9A8576", ringTrack: "#F3E5D8", ringFill: "#EC8B62"),
            dark: ThemeColors(bg: "#221A15", surface: "#2E241D", accent: "#F0A07A", accentSoft: "#5A3E2E",
                              text: "#F3E6DC", textSecondary: "#B59C8A", ringTrack: "#3D2F26", ringFill: "#F4A883")
        ),
        Theme(
            id: "sage", name: "Sage Mist",
            mood: "Calm, grounded, herbal — a misty greenhouse at morning.",
            light: ThemeColors(bg: "#EEF3ED", surface: "#FAFCF9", accent: "#8FC0A0", accentSoft: "#D6EADC",
                               text: "#33433A", textSecondary: "#7E938A", ringTrack: "#E0EBE1", ringFill: "#74B189"),
            dark: ThemeColors(bg: "#161E1A", surface: "#202A24", accent: "#8FC0A0", accentSoft: "#2D4438",
                              text: "#E2EFE7", textSecondary: "#94AC9E", ringTrack: "#2A362E", ringFill: "#92C5A4")
        ),
        Theme(
            id: "lavender", name: "Lavender Haze",
            mood: "Dreamy, soft-focus — dusk just after the sun drops.",
            light: ThemeColors(bg: "#F2EFF7", surface: "#FCFAFE", accent: "#A99BD4", accentSoft: "#E2DBF1",
                               text: "#3F3850", textSecondary: "#8B829F", ringTrack: "#E8E3F2", ringFill: "#9686CC"),
            dark: ThemeColors(bg: "#1A1722", surface: "#251F30", accent: "#A99BD4", accentSoft: "#3C3350",
                              text: "#EBE6F5", textSecondary: "#A096B5", ringTrack: "#2E2838", ringFill: "#AE9FD9")
        ),
        Theme(
            id: "sky", name: "Sky Linen",
            mood: "Airy, clear — a cotton shirt drying in a sea breeze.",
            light: ThemeColors(bg: "#ECF2F6", surface: "#FAFCFE", accent: "#84B6D9", accentSoft: "#D3E6F2",
                               text: "#2F3F4A", textSecondary: "#788D99", ringTrack: "#DEEAF1", ringFill: "#67A4CE"),
            dark: ThemeColors(bg: "#141B21", surface: "#1E272E", accent: "#84B6D9", accentSoft: "#2A3F4D",
                              text: "#E1EDF4", textSecondary: "#8FA3AF", ringTrack: "#27323A", ringFill: "#87BADD")
        ),
        Theme(
            id: "rose", name: "Rose Quartz",
            mood: "Tender, blush — a peony at full bloom.",
            light: ThemeColors(bg: "#FAEFF1", surface: "#FFFAFB", accent: "#E29DAE", accentSoft: "#F6DBE2",
                               text: "#4D353B", textSecondary: "#A4838C", ringTrack: "#F4E2E6", ringFill: "#D9869A"),
            dark: ThemeColors(bg: "#221619", surface: "#2E2024", accent: "#E29DAE", accentSoft: "#553339",
                              text: "#F4E3E8", textSecondary: "#B8979F", ringTrack: "#3B2A2E", ringFill: "#E6A3B4")
        ),
        Theme(
            id: "butter", name: "Butter Honey",
            mood: "Sunny, mellow — warm beeswax and pale honey.",
            light: ThemeColors(bg: "#FBF6E9", surface: "#FFFDF6", accent: "#E6C168", accentSoft: "#F6E9C2",
                               text: "#48402B", textSecondary: "#9A8C6A", ringTrack: "#F3EAD2", ringFill: "#DDB347"),
            dark: ThemeColors(bg: "#211C12", surface: "#2D271A", accent: "#E6C168", accentSoft: "#544830",
                              text: "#F4ECD7", textSecondary: "#B5A580", ringTrack: "#3A3322", ringFill: "#EAC774")
        ),
        Theme(
            id: "glacier", name: "Glacier Mint",
            mood: "Cool, clean — fresh eucalyptus and sea glass.",
            light: ThemeColors(bg: "#EAF4F2", surface: "#F8FDFC", accent: "#7FCBC0", accentSoft: "#CFEBE6",
                               text: "#2C433F", textSecondary: "#769590", ringTrack: "#DCEEEA", ringFill: "#5DBBAE"),
            dark: ThemeColors(bg: "#131F1D", surface: "#1D2B28", accent: "#7FCBC0", accentSoft: "#274641",
                              text: "#DFF0ED", textSecondary: "#8AACA6", ringTrack: "#26352F", ringFill: "#84CFC4")
        ),
        Theme(
            id: "greige", name: "Greige Stone",
            mood: "Neutral, architectural — warm concrete and oatmeal linen.",
            light: ThemeColors(bg: "#F2EFEA", surface: "#FBF9F6", accent: "#B0A595", accentSoft: "#E5DFD6",
                               text: "#403B34", textSecondary: "#928A7E", ringTrack: "#E8E3DB", ringFill: "#A0937F"),
            dark: ThemeColors(bg: "#1C1A17", surface: "#272421", accent: "#BFB5A4", accentSoft: "#433E36",
                              text: "#EDE9E2", textSecondary: "#A89F92", ringTrack: "#332F2A", ringFill: "#C2B8A7")
        ),
    ]

    static var `default`: Theme { presets[0] }

    static func preset(id: String) -> Theme? { presets.first { $0.id == id } }

    /// Builds a "Custom" theme from a user-picked accent, seated on a neutral
    /// greige base so the chosen color is the only colored element. The Palette
    /// layer guarantees legibility regardless of how pale the pick is.
    static func custom(accent: RGB) -> Theme {
        let softLight = RGB(accent.r + (1 - accent.r) * 0.72,
                            accent.g + (1 - accent.g) * 0.72,
                            accent.b + (1 - accent.b) * 0.72)
        let softDark = RGB(accent.r * 0.42, accent.g * 0.42, accent.b * 0.42)
        let greige = Theme.preset(id: "greige")!
        var light = greige.light
        var dark = greige.dark
        light.accent = accent.hexString
        light.accentSoft = softLight.hexString
        light.ringFill = accent.hexString
        dark.accent = accent.hexString
        dark.accentSoft = softDark.hexString
        dark.ringFill = accent.hexString
        return Theme(id: "custom", name: "Custom", mood: "Your own color.",
                     light: light, dark: dark, isCustom: true)
    }
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
