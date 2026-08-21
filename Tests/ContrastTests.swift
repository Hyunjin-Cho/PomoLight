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

    // 2026-08-21: three widget tests lived here — the toggle button's icon and its
    // 3:1 control outline, both derived by `WidgetChrome`, which went with the
    // widget. `LegibleFill` below stays: the app's own filled buttons use it.

    /// Regression gate for the 2026-08-20 donation-heart bug. The heart asked for
    /// `accent` as its foreground for months; an AppKit control was overriding the
    /// colour, so nobody saw that the request itself was unusable — drawn correctly
    /// it measured 1.13:1 against the window, where 3:1 is the floor for an icon.
    ///
    /// The top-bar glyphs now name their colour (`controlIcon`) instead of reaching
    /// for a palette entry directly, so pointing them somewhere illegible means
    /// breaking this test rather than shipping quietly.
    func testControlIconClears3To1OnEveryThemeAndAppearance() {
        for theme in Theme.presets {
            for (appearance, colors) in [("light", theme.light), ("dark", theme.dark)] {
                let p = ResolvedPalette(colors)
                assertRatio(p.controlIcon, p.bg, atLeast: 3.0,
                            "\(theme.name) \(appearance) control icon vs bg")
                assertRatio(p.controlIcon, p.surface, atLeast: 3.0,
                            "\(theme.name) \(appearance) control icon vs surface")
            }
        }
    }

    /// The bug was not one unlucky theme: `accent` is a FILL in this palette, picked
    /// to sit under dark ink. Pinning that here means the rule is a measured fact,
    /// not a comment someone can talk themselves out of.
    func testRawAccentWouldFailAsAForegroundOnEveryTheme() {
        for theme in Theme.presets {
            let p = ResolvedPalette(theme.light)
            XCTAssertLessThan(WCAG.contrast(p.accent, p.bg), 3.0,
                              "\(theme.name): accent now clears 3:1 on bg — if the palette " +
                              "really changed, revisit the FILL/FOREGROUND split in Theme.swift")
        }
    }

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
    ///
    /// 🚨 2026-08-21: this test used to assert the search ran toward WHITE here, and
    /// pinned the ~3.98:1 that white can manage against this grey. That was the bug
    /// written down as the contract. Mid-grey is L 0.214, and black/white tie at
    /// L ≈ 0.1791 — so black is the better direction and reaches 5.20:1. The old
    /// `luminance(background) > 0.5` split sent it the losing way for every
    /// background between 0.1791 and 0.5.
    func testEnforcingContrastFallsBackToTheBestFarEndWhenTheTargetIsImpossible() {
        let grey = RGB(0.5, 0.5, 0.5)
        let result = RGB(h: 200, s: 0.5, l: 0.5).enforcingContrast(against: grey, minRatio: 21.0)

        // This grey is dark enough that darkening wins — the search runs toward black.
        XCTAssertLessThan(max(result.r, result.g, result.b), 0.03,
                          "expected nearly-black, got \(result)")
        let best = max(WCAG.contrast(RGB(0, 0, 0), grey), WCAG.contrast(RGB(1, 1, 1), grey))
        XCTAssertEqual(WCAG.contrast(result, grey), best, accuracy: best * 0.05,
                       "should land within a few percent of the best achievable ratio")
    }

    /// The direction has to be chosen by which one actually wins, not by a guessed
    /// midpoint. Every background in 0.1791 < L <= 0.5 is a background the old rule
    /// pushed the wrong way; on those, a target that black can reach was reported as
    /// unreachable. Sweep the whole scale and require the achievable ratio.
    func testEnforcingContrastPicksTheDirectionThatActuallyWins() {
        for step in 0...50 {
            let level = Double(step) / 50.0
            let background = RGB(level, level, level)
            let best = max(WCAG.contrast(RGB(0, 0, 0), background),
                           WCAG.contrast(RGB(1, 1, 1), background))
            // Ask for something the better direction can just about deliver.
            let target = min(4.5, best * 0.95)
            let fixed = RGB(h: 200, s: 0.5, l: 0.5).enforcingContrast(against: background,
                                                                     minRatio: target)
            assertRatio(fixed, background, atLeast: target,
                        "grey \(String(format: "%.2f", level)) (luminance \(String(format: "%.4f", WCAG.luminance(background))))")
        }
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
