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

// MARK: - Built-in pastel presets — eight soft pastels

extension Theme {
    /// Generates a soft pastel palette (light + dark) from a single OKLCH hue. The
    /// Palette layer enforces WCAG contrast on top, so legibility is guaranteed for
    /// any hue. text/textSecondary/ringFill are WCAG-auto-corrected in Palette.
    ///
    /// 2026-11-19 (#66): the owner asked for fewer, more pastel colours. This replaced
    /// the 2026-07 "candy pastel" recipe (HSL, accent saturation 0.89 at lightness
    /// 0.74, hand nudges for yellow and cyan). The owner picked recipe "A soft" from
    /// three rendered candidates (`~/Documents/Code-Reviews/20261119/pomolight/
    /// theme-candidates/`): every role is one fixed OKLCH lightness and chroma, only
    /// the hue moves. The expressions below are that renderer's, kept in the same
    /// order so the bytes match what the owner saw — reorder them and colours move.
    private static func pastel(_ id: String, _ name: String, hue h: Double) -> Theme {
        func hx(_ L: Double, _ C: Double) -> String { RGB(oklchL: L, c: C, h: h).hexString }
        // Yellow is a naturally light hue: at the shared lightness it came out
        // mustard/khaki (#E3D18C). Lifting only that band gives butter (#FAE8A2).
        let yellowLift = (80.0 ..< 115.0).contains(h) ? 0.07 : 0.0
        let c = 0.090                      // accent chroma
        let aL = 0.86 + yellowLift         // accent lightness

        let light = ThemeColors(
            bg: hx(0.965, 0.022), surface: hx(0.99, 0.008),
            accent: hx(aL, c), accentSoft: hx(0.925 + yellowLift * 0.4, c * 0.55),
            text: hx(0.32, 0.045), textSecondary: hx(0.50, 0.04),
            // The fill has to clear 3:1 against the track, and the Palette layer gets
            // there by mixing toward black — which greyed a pale fill to mud in the
            // first candidates. Starting at that lightness (L 0.60) with the chroma
            // already in keeps the ring coloured.
            ringTrack: hx(0.92, c * 0.5), ringFill: hx(0.60, min(c * 1.5, 0.13)))
        let dark = ThemeColors(
            bg: hx(0.21, 0.02), surface: hx(0.255, 0.022),
            accent: hx(aL - 0.04, c), accentSoft: hx(0.36, min(c * 0.5, 0.04)),
            text: hx(0.94, 0.012), textSecondary: hx(0.76, 0.018),
            ringTrack: hx(0.32, 0.03), ringFill: hx(aL - 0.06, c))
        return Theme(id: id, name: name, mood: "", light: light, dark: dark)
    }

    /// Eight pastels spaced around the wheel (OKLCH hue degrees). The ids are the
    /// old ones whose colour family they continue, so a stored choice among these
    /// eight survives; the seven that went (rose, red, orange, lime, teal, indigo,
    /// magenta) fall back to the default through `ThemeStore.resolve`.
    static let presets: [Theme] = [
        pastel("pink",   "Pink",   hue: 0),     // baby pink
        pastel("coral",  "Coral",  hue: 42),    // peach
        pastel("yellow", "Yellow", hue: 95),    // butter
        pastel("green",  "Green",  hue: 138),   // pistachio
        pastel("mint",   "Mint",   hue: 172),
        pastel("sky",    "Sky",    hue: 232),
        pastel("blue",   "Blue",   hue: 272),   // periwinkle
        pastel("violet", "Violet", hue: 306),   // lavender
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

/// The soft disc inside the timer ring (`RingView`): `accentSoft` at these opacities
/// over the window's bg → bgDeep gradient. The numerals (`timerText`) and the status
/// line (`secondaryText`) are drawn ON it, so that blend — not bg — is what they
/// have to read against.
///
/// 2026-11-19 (#66, review F-4 of 2026-11-15): the contract only ever checked bg and
/// surface, and the old candy themes gave the status line 3.99–4.48:1 on this disc
/// while passing 4.5:1 on bg. The opacities live here so `RingView` and
/// `ContrastTests` read the same two numbers.
enum DialHalo {
    static let opacity = 0.30
    static let dimmedOpacity = 0.18          // idle / paused

    /// The disc as it lands on `backdrop` (straight alpha blend, sRGB values).
    static func blend(_ palette: ResolvedPalette, over backdrop: RGB, dimmed: Bool) -> RGB {
        let a = dimmed ? dimmedOpacity : opacity
        let s = palette.accentSoft
        return RGB(s.r * a + backdrop.r * (1 - a),
                   s.g * a + backdrop.g * (1 - a),
                   s.b * a + backdrop.b * (1 - a))
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
