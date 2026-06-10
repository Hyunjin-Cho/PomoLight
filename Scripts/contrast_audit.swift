#!/usr/bin/env swift
// Independent contrast audit for the generated 15-hue pastel palette.
// Mirrors the app's HSL generator (Theme.swift) + WCAG enforcement (Color+Contrast.swift)
// and fails (exit 1) if any resolved pair misses its tier:
//   timer text >= 7:1, body text >= 4.5:1, ring fill vs track >= 3:1.
// Run:  swift Scripts/contrast_audit.swift

import Foundation

struct RGB {
    var r, g, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    init(h: Double, s: Double, l: Double) {
        if s == 0 { self.init(l, l, l); return }
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func f(_ t0: Double) -> Double {
            var t = t0; if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            if t < 1.0/6 { return p + (q - p) * 6 * t }
            if t < 1.0/2 { return q }
            if t < 2.0/3 { return p + (q - p) * (2.0/3 - t) * 6 }
            return p
        }
        self.init(f(hh + 1.0/3), f(hh), f(hh - 1.0/3))
    }
}
func lin(_ c: Double) -> Double { c <= 0.03928 ? c/12.92 : pow((c+0.055)/1.055, 2.4) }
func lum(_ c: RGB) -> Double { 0.2126*lin(c.r) + 0.7152*lin(c.g) + 0.0722*lin(c.b) }
func contrast(_ a: RGB, _ b: RGB) -> Double {
    let la = lum(a), lb = lum(b); return (max(la,lb)+0.05)/(min(la,lb)+0.05)
}
func enforce(_ fg: RGB, against bg: RGB, _ minRatio: Double) -> RGB {
    if contrast(fg, bg) >= minRatio { return fg }
    let t: RGB = lum(bg) > 0.5 ? RGB(0,0,0) : RGB(1,1,1)
    var amount = 0.0, best = fg
    while amount <= 1.0 {
        let c = RGB(fg.r+(t.r-fg.r)*amount, fg.g+(t.g-fg.g)*amount, fg.b+(t.b-fg.b)*amount)
        best = c
        if contrast(c, bg) >= minRatio { return c }
        amount += 0.02
    }
    return best
}

// Same recipe as Theme.pastel(...)
func palette(hue h: Double, sat: Double, dark: Bool) -> (bg: RGB, surface: RGB, text: RGB, sec: RGB, track: RGB, fill: RGB) {
    func m(_ x: Double) -> Double { min(sat, x) }
    if dark {
        return (RGB(h:h,s:m(0.24),l:0.10), RGB(h:h,s:m(0.20),l:0.155), RGB(h:h,s:m(0.16),l:0.92),
                RGB(h:h,s:m(0.14),l:0.70), RGB(h:h,s:m(0.26),l:0.26), RGB(h:h,s:m(0.60),l:0.68))
    }
    return (RGB(h:h,s:m(0.42),l:0.965), RGB(h:h,s:m(0.30),l:0.992), RGB(h:h,s:m(0.32),l:0.26),
            RGB(h:h,s:m(0.22),l:0.50), RGB(h:h,s:m(0.38),l:0.90), RGB(h:h,s:sat,l:0.62))
}

let themes: [(String, Double, Double)] = [
    ("Butter",48,0.58),("Peach",26,0.58),("Coral",8,0.58),("Rose",342,0.58),("Orchid",312,0.58),
    ("Lavender",278,0.58),("Periwinkle",250,0.58),("Bluebell",224,0.58),("Sky",204,0.58),("Aqua",190,0.58),
    ("Mint",168,0.58),("Meadow",145,0.58),("Sage",112,0.58),("Lime",84,0.58),("Greige",40,0.10),
]
func fmt(_ x: Double) -> String { String(format: "%.2f", x) }
var failures = 0
print("PomoLight contrast audit — 15 generated pastels (resolved/enforced)\n")
for (name, hue, sat) in themes {
    for dark in [false, true] {
        let p = palette(hue: hue, sat: sat, dark: dark)
        let timer = enforce(enforce(p.text, against: p.bg, 7.0), against: p.surface, 7.0)
        let body = enforce(enforce(p.sec, against: p.bg, 4.5), against: p.surface, 4.5)
        let rf = enforce(p.fill, against: p.track, 3.0)
        let checks: [(String, Double, Double)] = [
            ("timer", min(contrast(timer, p.bg), contrast(timer, p.surface)), 7.0),
            ("text",  min(contrast(body, p.bg), contrast(body, p.surface)), 4.5),
            ("ring",  contrast(rf, p.track), 3.0),
        ]
        var line = "  \(name.padding(toLength: 11, withPad: " ", startingAt: 0)) [\(dark ? "dark " : "light")] "
        for (label, ratio, tier) in checks {
            let ok = ratio >= tier - 0.001
            if !ok { failures += 1 }
            line += "\(label)=\(fmt(ratio))\(ok ? "✓" : "✗")  "
        }
        print(line)
    }
}
print("")
if failures == 0 { print("✅ PASS — all 15 themes meet WCAG tiers in light & dark."); exit(0) }
else { print("❌ FAIL — \(failures) pair(s) below tier."); exit(1) }
