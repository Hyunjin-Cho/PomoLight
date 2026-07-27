import XCTest

/// Legibility is a promise the app makes in its README, and it's enforced in code
/// rather than by hand-picking colors — so it deserves a test that runs the real
/// derivation (`ResolvedPalette`, `LegibleFill`) over every shipped theme.
///
/// `Scripts/contrast_audit.sh` prints the same numbers for humans; this is the
/// version that fails a build.
final class ContrastTests: XCTestCase {

    private let epsilon = 0.001   // ratios are compared at 2 decimals elsewhere

    func testEveryPresetMeetsItsTierInBothAppearances() {
        for theme in Theme.presets {
            for (appearance, colors) in [("light", theme.light), ("dark", theme.dark)] {
                let p = ResolvedPalette(colors)
                let where_ = "\(theme.name) \(appearance)"

                // Hero numerals: AAA against whichever backdrop is harder.
                assertRatio(p.timerText, p.bg, atLeast: 7.0, "\(where_) timer vs bg")
                assertRatio(p.timerText, p.surface, atLeast: 7.0, "\(where_) timer vs surface")
                assertRatio(p.primaryText, p.bg, atLeast: 7.0, "\(where_) primary vs bg")
                assertRatio(p.primaryText, p.surface, atLeast: 7.0, "\(where_) primary vs surface")

                // Supporting copy: AA.
                assertRatio(p.secondaryText, p.bg, atLeast: 4.5, "\(where_) secondary vs bg")
                assertRatio(p.secondaryText, p.surface, atLeast: 4.5, "\(where_) secondary vs surface")

                // Non-text UI: the ring must be tellable from its track.
                assertRatio(p.ringFill, p.ringTrack, atLeast: 3.0, "\(where_) ring vs track")

                // Filled buttons and chips.
                assertRatio(p.buttonLabel, p.buttonFill, atLeast: 4.5, "\(where_) button label")
                assertRatio(p.onAccentSoft, p.accentSoft, atLeast: 4.5, "\(where_) label on accentSoft")
            }
        }
    }

    /// Regression gate for the 2026-07-10 review finding: the widget's toggle button
    /// used to draw a hardcoded white icon on the raw pastel accent, which failed
    /// even 3:1 on 14 of the 15 themes (white on Lime was 1.22:1).
    ///
    /// The widget process can't read the app's palette — it rebuilds the pair from
    /// the single accent hex in the shared snapshot, which `publishSnapshot()` fills
    /// with the theme's LIGHT accent. This derives it the same way on purpose: if
    /// either side of that arrangement changes, this test should be the thing that
    /// notices.
    func testWidgetToggleButtonIconIsLegibleOnEveryTheme() {
        for theme in Theme.presets {
            let fromSnapshot = RGB(hex: theme.light.accent)
            let legible = LegibleFill(accent: fromSnapshot)
            assertRatio(legible.label, legible.fill, atLeast: 4.5,
                        "\(theme.name) widget icon on button fill")
        }
    }

    /// The second, independent contrast job on the same button: its icon being
    /// readable says nothing about whether you can SEE that a control is there. Both
    /// widget buttons are filled with a shade of the accent the widget container is
    /// also tinted with, so the outline is what identifies them — WCAG 2.1 SC 1.4.11
    /// wants 3:1 for that. Without it the toggle measured 1.17:1 on Lime, and the
    /// reset button (a 16% fill on a 20% tint) was effectively invisible.
    func testWidgetControlOutlineClears3To1OnEveryThemeAndAppearance() {
        for theme in Theme.presets {
            let accent = RGB(hex: theme.light.accent)   // the widget only ever gets this one
            for dark in [false, true] {
                assertRatio(WidgetChrome.controlOutline(accent: accent, dark: dark),
                            WidgetChrome.backdrop(accent: accent, dark: dark),
                            atLeast: 3.0,
                            "\(theme.name) widget outline (\(dark ? "dark" : "light"))")
            }
        }
    }

    func testWidgetControlOutlineHoldsForAnyAccent() {
        for hue in stride(from: 0.0, to: 360.0, by: 5.0) {
            for lightness in [0.15, 0.35, 0.5, 0.7, 0.74, 0.9] {
                let accent = RGB(h: hue, s: 0.89, l: lightness)
                for dark in [false, true] {
                    assertRatio(WidgetChrome.controlOutline(accent: accent, dark: dark),
                                WidgetChrome.backdrop(accent: accent, dark: dark),
                                atLeast: 3.0,
                                "h\(Int(hue)) l\(lightness) (\(dark ? "dark" : "light"))")
                }
            }
        }
    }

    /// A custom accent can be any color the user picks, so the derivation itself —
    /// not just the 15 presets — has to hold.
    func testLegibleFillClearsAAForAnyAccent() {
        for hue in stride(from: 0.0, to: 360.0, by: 5.0) {
            for saturation in [0.0, 0.45, 0.9, 1.0] {
                for lightness in [0.05, 0.2, 0.35, 0.5, 0.62, 0.74, 0.88, 0.97] {
                    let accent = RGB(h: hue, s: saturation, l: lightness)
                    let legible = LegibleFill(accent: accent)
                    assertRatio(legible.label, legible.fill, atLeast: 4.5,
                                "accent h\(Int(hue)) s\(saturation) l\(lightness)")
                }
            }
        }
    }

    func testEnforcingContrastLeavesAPassingColorExactlyAlone() {
        let white = RGB(1, 1, 1)
        let ink = RGB(0.1, 0.1, 0.1)
        XCTAssertEqual(ink.enforcingContrast(against: white, minRatio: 7.0), ink)
    }

    func testEnforcingContrastReachesAnAchievableTarget() {
        for hue in stride(from: 0.0, to: 360.0, by: 15.0) {
            let foreground = RGB(h: hue, s: 0.6, l: 0.7)
            for background in [RGB(1, 1, 1), RGB(0, 0, 0)] {
                let fixed = foreground.enforcingContrast(against: background, minRatio: 7.0)
                assertRatio(fixed, background, atLeast: 7.0, "h\(Int(hue)) on \(background)")
            }
        }
    }

    /// Against a mid-grey nothing can reach 21:1. The guarantee is that the search
    /// terminates and hands back the far end of its grid — not an infinite loop, not
    /// the original unreadable color. It stops ~98% of the way to the extreme (the
    /// last 0.02 step), which is visually the extreme.
    func testEnforcingContrastFallsBackToTheFarEndWhenTheTargetIsImpossible() {
        let grey = RGB(0.5, 0.5, 0.5)
        let result = RGB(h: 200, s: 0.5, l: 0.5).enforcingContrast(against: grey, minRatio: 21.0)

        // Grey is the lighter side, so the search runs toward white.
        XCTAssertGreaterThan(min(result.r, result.g, result.b), 0.97,
                             "expected nearly-white, got \(result)")
        let best = WCAG.contrast(RGB(1, 1, 1), grey)
        XCTAssertEqual(WCAG.contrast(result, grey), best, accuracy: best * 0.05,
                       "should land within a few percent of the best achievable ratio")
    }

    // MARK: - Hex round-trip
    //
    // Themes are generated in HSL, stored as hex, then parsed back for the contrast
    // math — so every shipped color is 8-bit quantized. (An audit that skipped this
    // round-trip is exactly why the old standalone script's numbers drifted from
    // the app's real ones.)

    func testHexRoundTripStaysWithin8BitPrecision() {
        for hue in stride(from: 0.0, to: 360.0, by: 5.0) {
            let generated = RGB(h: hue, s: 0.89, l: 0.74)
            let stored = RGB(hex: generated.hexString)
            XCTAssertEqual(stored.r, generated.r, accuracy: 1.0 / 255)
            XCTAssertEqual(stored.g, generated.g, accuracy: 1.0 / 255)
            XCTAssertEqual(stored.b, generated.b, accuracy: 1.0 / 255)
        }
    }

    func testHexParsingHandlesShorthandAndJunk() {
        XCTAssertEqual(RGB(hex: "#FFFFFF"), RGB(1, 1, 1))
        XCTAssertEqual(RGB(hex: "000000"), RGB(0, 0, 0))
        XCTAssertEqual(RGB(hex: "#fff"), RGB(1, 1, 1), "3-digit shorthand expands")
        XCTAssertEqual(RGB(hex: "  #FFFFFF  "), RGB(1, 1, 1), "whitespace is trimmed")
        XCTAssertEqual(RGB(hex: "not a color"), RGB(0.5, 0.5, 0.5), "junk falls back to mid-grey")
        XCTAssertEqual(RGB(hex: ""), RGB(0.5, 0.5, 0.5))
    }

    func testContrastIsSymmetricAndBounded() {
        let a = RGB(hex: "#E79A86")
        let b = RGB(hex: "#1F1D24")
        XCTAssertEqual(WCAG.contrast(a, b), WCAG.contrast(b, a), accuracy: epsilon)
        XCTAssertEqual(WCAG.contrast(RGB(1, 1, 1), RGB(0, 0, 0)), 21, accuracy: 0.01)
        XCTAssertEqual(WCAG.contrast(a, a), 1, accuracy: epsilon)
    }

    // MARK: - Helper

    private func assertRatio(_ foreground: RGB, _ background: RGB,
                             atLeast tier: Double, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let ratio = WCAG.contrast(foreground, background)
        XCTAssertGreaterThanOrEqual(ratio, tier - epsilon,
                                    "\(label): \(String(format: "%.2f", ratio)):1 < \(tier):1",
                                    file: file, line: line)
    }
}
