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

        // MARK: Widget controls
        //
        // The widget process can't see the app's palette — it rebuilds its colors
        // from the single accent hex in the shared snapshot, which
        // `AppModel.publishSnapshot()` fills with the theme's LIGHT accent. Derive
        // them exactly that way here. Two independent jobs:
        //
        //   icon    — readable ON the button (4.5:1). Before PR #2 the icon was
        //             hardcoded white and failed even 3:1 on 14 of the 15 themes.
        //   outline — the button distinguishable FROM the widget's own accent tint
        //             (3:1, WCAG 1.4.11). The fills are shades of that same accent,
        //             so without the outline the control has no visible shape:
        //             `fill-vs-bg` below is what it would be on its own.
        print("\nWidget controls — icon on the button, outline against the widget tint\n")
        for theme in Theme.presets {
            let accent = RGB(hex: theme.light.accent)
            let legible = LegibleFill(accent: accent)
            let icon = Check(label: "icon",
                             ratio: WCAG.contrast(legible.label, legible.fill), tier: 4.5)
            if !icon.passes {
                failures.append("\(theme.name) widget icon: \(fmt(icon.ratio)) < 4.50")
            }

            var line = "  \(pad(theme.name, 11)) icon=\(fmt(icon.ratio))\(icon.passes ? "✓" : "✗")  "
            for dark in [false, true] {
                let backdrop = WidgetChrome.backdrop(accent: accent, dark: dark)
                let outline = Check(label: dark ? "outline[dark ]" : "outline[light]",
                                    ratio: WCAG.contrast(WidgetChrome.controlOutline(accent: accent, dark: dark),
                                                         backdrop), tier: 3.0)
                if !outline.passes {
                    failures.append("\(theme.name) widget \(outline.label): \(fmt(outline.ratio)) < 3.00")
                }
                // Informational: what the un-outlined fill would have scored.
                let bare = WCAG.contrast(legible.fill, backdrop)
                line += "\(outline.label)=\(fmt(outline.ratio))\(outline.passes ? "✓" : "✗")"
                    + " (fill-vs-bg \(fmt(bare)))  "
            }
            print(line)
        }

        print("""

              Note: the widget's background is translucent, so `backdrop` is modelled —
              the accent at 20% over near-white / near-black. The outline is derived
              from that same model in the widget itself, so both agree by construction.
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
