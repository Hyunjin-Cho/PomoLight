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
func palette(hue h: Double, dark: Bool) -> (bg: RGB, surface: RGB, text: RGB, sec: RGB, track: RGB, fill: RGB) {
    let yellowDip = (40.0 ..< 100.0).contains(h) ? 0.05 : 0.0
    let cyanBoost = (170.0 ..< 255.0).contains(h) ? 0.06 : 0.0
    func cs(_ s: Double) -> Double { min(s + cyanBoost, 1.0) }
    if dark {
        return (RGB(h:h,s:0.46,l:0.12), RGB(h:h,s:0.40,l:0.17), RGB(h:h,s:0.22,l:0.92),
                RGB(h:h,s:0.17,l:0.71), RGB(h:h,s:0.43,l:0.25), RGB(h:h,s:cs(0.82),l:0.67))
    }
    return (RGB(h:h,s:0.85,l:0.95 - yellowDip*0.4), RGB(h:h,s:0.70,l:0.982), RGB(h:h,s:0.45,l:0.25),
            RGB(h:h,s:0.30,l:0.47), RGB(h:h,s:0.74,l:0.89), RGB(h:h,s:cs(0.84),l:0.62 - yellowDip))
}

let themes: [(String, Double, Double)] = [
    ("Pink",334,0.44),("Rose",350,0.44),("Red",8,0.44),("Coral",22,0.44),("Orange",36,0.44),
    ("Yellow",52,0.44),("Lime",84,0.44),("Green",128,0.44),("Mint",158,0.44),("Teal",182,0.44),
    ("Sky",202,0.44),("Blue",224,0.44),("Indigo",252,0.44),("Violet",282,0.44),("Magenta",312,0.44),
]
func fmt(_ x: Double) -> String { String(format: "%.2f", x) }
var failures = 0
print("PomoLight contrast audit — 15 generated pastels (resolved/enforced)\n")
for (name, hue, _) in themes {
    for dark in [false, true] {
        let p = palette(hue: hue, dark: dark)
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
