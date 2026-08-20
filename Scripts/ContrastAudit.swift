// Contrast audit for the 15-hue pastel palette.
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

        // 2026-08-21: the widget section that stood here is gone with the widget —
        // it audited WidgetChrome's icon-on-fill and 3:1 control outline.

        print("")
        if failures.isEmpty {
            print("✅ PASS — \(Theme.presets.count) themes meet WCAG tiers in light & dark.")
            exit(0)
        }
        print("❌ FAIL — \(failures.count) pair(s) below tier:")
        for f in failures { print("   • \(f)") }
        exit(1)
    }
}
