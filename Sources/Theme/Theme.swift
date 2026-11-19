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
    // Recipe tuned by the color team (Fable 5 + GPT-5.5): bright "candy pastels"
    // — high saturation kept soft by high lightness — plus a clearly-tinted
    // background. text/textSecondary/ringFill are WCAG-auto-corrected in Palette.
    private static func pastel(_ id: String, _ name: String, hue h: Double) -> Theme {
        // Yellows are intrinsically light → darken only the BACKGROUND a touch so its
        // tint stays visible (NOT the accent/ring — that would make yellow olive).
        // Cyans/blues read flatter → nudge their saturation up.
        let bgYellowDip = (40.0 ..< 95.0).contains(h) ? 0.03 : 0.0
        let cyanBoost = (170.0 ..< 255.0).contains(h) ? 0.06 : 0.0
        func clampS(_ s: Double) -> Double { min(s + cyanBoost, 1.0) }
        func hex(s: Double, l: Double) -> String { RGB(h: h, s: s, l: l).hexString }

        let light = ThemeColors(
            bg:            hex(s: 0.85, l: 0.95 - bgYellowDip),
            surface:       hex(s: 0.70, l: 0.982),
            accent:        hex(s: clampS(0.89), l: 0.74),
            accentSoft:    hex(s: 0.88, l: 0.87),
            text:          hex(s: 0.45, l: 0.25),
            textSecondary: hex(s: 0.30, l: 0.47),
            ringTrack:     hex(s: 0.74, l: 0.89),
            ringFill:      hex(s: clampS(0.84), l: 0.62))
        let dark = ThemeColors(
            bg:            hex(s: 0.46, l: 0.12),
            surface:       hex(s: 0.40, l: 0.17),
            accent:        hex(s: clampS(0.86), l: 0.70),
            accentSoft:    hex(s: 0.52, l: 0.30),
            text:          hex(s: 0.22, l: 0.92),
            textSecondary: hex(s: 0.17, l: 0.71),
            ringTrack:     hex(s: 0.43, l: 0.25),
            ringFill:      hex(s: clampS(0.82), l: 0.67))
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

/// The palette resolved to raw `RGB` — the one place every contrast decision is
/// actually made. `Palette` below is just this converted to SwiftUI `Color`s.
///
/// It exists separately because `Color` is not introspectable: anything that wants
/// to VERIFY a ratio (`Scripts/contrast_audit.sh`, the unit tests) has to read the
/// numbers. Keeping the math here means those checks run the real derivation
/// instead of a copy that can silently drift.
struct ResolvedPalette {
    // 🚨 2026-08-21 — every role below is labelled FILL or FOREGROUND, and the two
    // are not interchangeable. FILL colours are the pastels this palette is built
    // from; they are chosen to sit UNDER dark ink and are far too light to draw ON.
    // FOREGROUND colours have been pushed until they clear a contrast tier.
    //
    // This is written down because the donation heart asked for `accent` as its
    // foreground from the day it was written and nobody noticed for months — an
    // AppKit control was overriding the colour, so the request never reached the
    // screen. The first build that honoured it measured 1.13:1 against the window,
    // where 3:1 is the floor for an icon. Reach for a FILL as a foreground and you
    // get something invisible, on every theme, not just an unlucky one.

    // MARK: FILL — safe to draw ON, never safe to draw WITH
    let bg: RGB
    let bgDeep: RGB            // slightly deeper bg for a soft vertical gradient
    let surface: RGB
    let accent: RGB            // raw accent: glow, idle ring, swatch. NEVER a foreground.
    let accentSoft: RGB        // soft fills (chips at rest, halos)
    let ringTrack: RGB
    let buttonFill: RGB        // accent (or deepened accent) that hosts a legible label

    // MARK: FOREGROUND — each one clears a tier against what it sits on
    let ringFill: RGB          // >= 3:1 vs ringTrack
    let timerText: RGB         // >= 7:1 vs bg AND surface (the hero numerals)
    let primaryText: RGB       // >= 7:1 vs bg AND surface
    let secondaryText: RGB     // >= 4.5:1 vs bg AND surface
    let controlIcon: RGB       // >= 3:1 vs bg AND surface — top-bar glyph (the gear)
    let buttonLabel: RGB       // >= 4.5:1 vs buttonFill
    let onAccentSoft: RGB      // legible label on an accentSoft fill

    init(_ c: ThemeColors) {
        let bg = RGB(hex: c.bg)
        let surface = RGB(hex: c.surface)
        let accent = RGB(hex: c.accent)
        let accentSoft = RGB(hex: c.accentSoft)
        let text = RGB(hex: c.text)
        let secondary = RGB(hex: c.textSecondary)
        let ringTrack = RGB(hex: c.ringTrack)
        let ringFill = RGB(hex: c.ringFill)

        self.bg = bg
        self.bgDeep = RGB(bg.r * 0.965, bg.g * 0.965, bg.b * 0.965)
        self.surface = surface
        self.accent = accent
        self.accentSoft = accentSoft
        self.ringTrack = ringTrack

        // 2026-11-03: the bg → surface order is part of the result; reversed, 8 of 30 shipped secondaryTexts change.
        func clearingBgThenSurface(_ ink: RGB, minRatio: Double) -> RGB {
            ink.enforcingContrast(against: bg, minRatio: minRatio)
                .enforcingContrast(against: surface, minRatio: minRatio)
        }

        // The AAA (7:1) ink, cleared against bg and then surface (the helper above).
        // 2026-11-03: this used to say "against whichever backdrop is harder" — nothing picks one.
        // Every shipped theme ends >= 7:1 on both (ContrastTests); a light bg under a dark surface
        // does not (ResolvedPaletteTests.testMixedBackdropsAreRecordedBitForBit).
        let aaaInk = clearingBgThenSurface(text, minRatio: 7.0)
        // 2026-08-15: timerText and primaryText were two copies of this exact
        // formula. Deriving both from one value means they can no longer drift
        // apart by accident. The two NAMES stay because they answer different
        // questions — "the hero numerals" vs "every other primary label" — and a
        // future tweak (say, a slightly bolder ink for the big countdown) should
        // have somewhere to land. Change one only when that is the intent.
        self.timerText = aaaInk
        self.primaryText = aaaInk
        self.secondaryText = clearingBgThenSurface(secondary, minRatio: 4.5)
        // The top-bar glyphs share secondaryText rather than deriving their own:
        // an icon only needs 3:1, so the 4.5:1 ink already clears it with room, and
        // one colour kept the gear and the donation heart reading as a pair (the heart
        // went 2026-11-19, #6). The role has
        // its own NAME so that pointing these icons somewhere else is a deliberate
        // edit to a tested contract, not a quiet `.foregroundStyle` swap.
        self.controlIcon = self.secondaryText

        // Ring fill must be distinguishable from its track (UI element, 3:1).
        self.ringFill = ringFill.enforcingContrast(against: ringTrack, minRatio: 3.0)

        // Deepen accent until a label clears AA, for filled buttons/chips. Every
        // filled button in the app draws from this pair — the main window's primary
        // action, the preset chips, and (since 2026-08-21) the menu-bar popover.
        let legible = LegibleFill(accent: accent)
        self.buttonFill = legible.fill
        self.buttonLabel = legible.label

        // Legible label on the pale accentSoft fill.
        self.onAccentSoft = text
            .enforcingContrast(against: accentSoft, minRatio: 4.5)
    }
}

struct Palette {
    let bg: Color
    let bgDeep: Color          // slightly deeper bg for a soft vertical gradient
    let surface: Color
    let accent: Color          // FILL: glow, idle ring, swatch. NEVER a foreground — see ResolvedPalette.
    let accentSoft: Color      // soft fills (chips at rest, halos)
    let ringTrack: Color
    let ringFill: Color        // >= 3:1 vs ringTrack
    let timerText: Color       // >= 7:1 vs bg AND surface (the hero numerals)
    let primaryText: Color     // >= 7:1 vs surface/bg
    let secondaryText: Color   // >= 4.5:1 vs surface/bg
    let controlIcon: Color     // >= 3:1 vs surface/bg — top-bar glyph (the gear)
    let buttonFill: Color      // accent (or deepened accent) that hosts a legible label
    let buttonLabel: Color     // >= 4.5:1 vs buttonFill
    let onAccentSoft: Color    // legible label on an accentSoft fill

    init(_ c: ThemeColors) {
        let r = ResolvedPalette(c)
        self.bg = r.bg.color
        self.bgDeep = r.bgDeep.color
        self.surface = r.surface.color
        self.accent = r.accent.color
        self.accentSoft = r.accentSoft.color
        self.ringTrack = r.ringTrack.color
        self.ringFill = r.ringFill.color
        self.timerText = r.timerText.color
        self.primaryText = r.primaryText.color
        self.secondaryText = r.secondaryText.color
        self.controlIcon = r.controlIcon.color
        self.buttonFill = r.buttonFill.color
        self.buttonLabel = r.buttonLabel.color
        self.onAccentSoft = r.onAccentSoft.color
    }
}
