// Contrast audit for the 15-hue pastel palette AND the widget's toggle button.
//
// Unlike the old version of this audit, nothing here re-implements the palette:
// it compiles against the app's own `Theme`/`ResolvedPalette`/`LegibleFill`, so a
// change to the real derivation shows up here instead of drifting silently.
//
// Gates (exit 1 on any failure):
//   timer numerals   >= 7:1   vs bg AND surface
//   secondary text   >= 4.5:1 vs bg AND surface
//   ring fill        >= 3:1   vs ring track
//   button label     >= 4.5:1 vs button fill   (app buttons, light + dark)
//   widget icon      >= 4.5:1 vs widget button fill
//
// Run: bash Scripts/contrast_audit.sh

import Foundation

private func fmt(_ x: Double) -> String { String(format: "%.2f", x) }

private func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? s : s.padding(toLength: n, withPad: " ", startingAt: 0)
}

/// Flattens a translucent color over a backdrop in sRGB space — an approximation
/// of what the compositor does, used only for the advisory widget-backdrop line.
private func over(_ backdrop: RGB, _ top: RGB, alpha: Double) -> RGB {
    RGB(top.r * alpha + backdrop.r * (1 - alpha),
        top.g * alpha + backdrop.g * (1 - alpha),
        top.b * alpha + backdrop.b * (1 - alpha))
}

private struct Check {
    let label: String
    let ratio: Double
    let tier: Double
    var passes: Bool { ratio >= tier - 0.001 }
}

@main
struct ContrastAudit {
    static func main() {
        var failures: [String] = []

        print("PomoLight contrast audit — \(Theme.presets.count) generated pastels")
        print("(ratios come from the app's own ResolvedPalette / LegibleFill)\n")

        // MARK: App palette — every theme, both appearances
        for theme in Theme.presets {
            for dark in [false, true] {
                let p = ResolvedPalette(dark ? theme.dark : theme.light)
                let checks = [
                    Check(label: "timer",
                          ratio: min(WCAG.contrast(p.timerText, p.bg),
                                     WCAG.contrast(p.timerText, p.surface)), tier: 7.0),
                    Check(label: "text",
                          ratio: min(WCAG.contrast(p.secondaryText, p.bg),
                                     WCAG.contrast(p.secondaryText, p.surface)), tier: 4.5),
                    Check(label: "ring",
                          ratio: WCAG.contrast(p.ringFill, p.ringTrack), tier: 3.0),
                    Check(label: "button",
                          ratio: WCAG.contrast(p.buttonLabel, p.buttonFill), tier: 4.5),
                ]
                var line = "  \(pad(theme.name, 11)) [\(dark ? "dark " : "light")] "
                for c in checks {
                    if !c.passes {
                        failures.append("\(theme.name) \(dark ? "dark" : "light") \(c.label): \(fmt(c.ratio)) < \(fmt(c.tier))")
                    }
                    line += "\(c.label)=\(fmt(c.ratio))\(c.passes ? "✓" : "✗")  "
                }
                print(line)
            }
        }

        // MARK: Widget toggle button
        //
        // The widget process can't see the app's palette — it rebuilds the button
        // colors from the single accent hex in the shared snapshot, which
        // `AppModel.publishSnapshot()` fills with the theme's LIGHT accent. Derive
        // it exactly that way here. (Before PR #2 the icon was hardcoded white,
        // which failed 3:1 on 14 of the 15 themes.)
        print("\nWidget toggle button — icon on button fill (widget uses the LIGHT accent)\n")
        // Approximate widget backdrops: the container gradient is accent at 20%…6%
        // over the system widget material. Advisory only — see note below.
        let lightBackdrop = RGB(1, 1, 1)
        let darkBackdrop = RGB(0.12, 0.12, 0.13)
        for theme in Theme.presets {
            let accent = RGB(hex: theme.light.accent)
            let legible = LegibleFill(accent: accent)
            let icon = Check(label: "icon",
                             ratio: WCAG.contrast(legible.label, legible.fill), tier: 4.5)
            if !icon.passes {
                failures.append("\(theme.name) widget icon: \(fmt(icon.ratio)) < 4.50")
            }
            // Advisory: can a low-vision user FIND the circular button at all?
            let onLight = WCAG.contrast(legible.fill, over(lightBackdrop, accent, alpha: 0.20))
            let onDark = WCAG.contrast(legible.fill, over(darkBackdrop, accent, alpha: 0.20))
            let shape = min(onLight, onDark)
            print("  \(pad(theme.name, 11)) icon=\(fmt(icon.ratio))\(icon.passes ? "✓" : "✗")"
                  + "   shape-vs-backdrop≈\(fmt(shape))\(shape >= 3.0 ? "" : " (advisory)")")
        }

        print("""

              Note: "shape-vs-backdrop" is advisory, not a gate — it approximates the
              translucent widget background and is about spotting the button, not
              reading the icon in it.
              """)

        print("")
        if failures.isEmpty {
            print("✅ PASS — \(Theme.presets.count) themes meet WCAG tiers in light & dark, widget button included.")
            exit(0)
        }
        print("❌ FAIL — \(failures.count) pair(s) below tier:")
        for f in failures { print("   • \(f)") }
        exit(1)
    }
}
