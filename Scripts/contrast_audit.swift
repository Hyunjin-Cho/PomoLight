#!/usr/bin/env swift
// Independent contrast audit for every shipped theme × appearance.
// Enforces the design-critic's guardrails (timer >= 7:1, body text >= 4.5:1,
// ring fill vs track >= 3:1) on the RESOLVED palette and fails (exit 1) if any
// pair misses its tier. Run:  swift Scripts/contrast_audit.swift
//
// This mirrors the same WCAG + enforcement logic the app uses at runtime in
// Color+Contrast.swift / Theme.swift, as a build-time check.

import Foundation

struct RGB {
    var r, g, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    init(hex: String) {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0x808080
        self.init(Double((v >> 16) & 0xFF)/255, Double((v >> 8) & 0xFF)/255, Double(v & 0xFF)/255)
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

typealias Colors = [String: String]
let themes: [(String, Colors, Colors)] = [
    ("Peach Cream",
     ["bg":"#FBF3EC","surface":"#FFFBF7","text":"#4A3A30","textSecondary":"#9A8576","ringTrack":"#F3E5D8","ringFill":"#EC8B62"],
     ["bg":"#221A15","surface":"#2E241D","text":"#F3E6DC","textSecondary":"#B59C8A","ringTrack":"#3D2F26","ringFill":"#F4A883"]),
    ("Sage Mist",
     ["bg":"#EEF3ED","surface":"#FAFCF9","text":"#33433A","textSecondary":"#7E938A","ringTrack":"#E0EBE1","ringFill":"#74B189"],
     ["bg":"#161E1A","surface":"#202A24","text":"#E2EFE7","textSecondary":"#94AC9E","ringTrack":"#2A362E","ringFill":"#92C5A4"]),
    ("Lavender Haze",
     ["bg":"#F2EFF7","surface":"#FCFAFE","text":"#3F3850","textSecondary":"#8B829F","ringTrack":"#E8E3F2","ringFill":"#9686CC"],
     ["bg":"#1A1722","surface":"#251F30","text":"#EBE6F5","textSecondary":"#A096B5","ringTrack":"#2E2838","ringFill":"#AE9FD9"]),
    ("Sky Linen",
     ["bg":"#ECF2F6","surface":"#FAFCFE","text":"#2F3F4A","textSecondary":"#788D99","ringTrack":"#DEEAF1","ringFill":"#67A4CE"],
     ["bg":"#141B21","surface":"#1E272E","text":"#E1EDF4","textSecondary":"#8FA3AF","ringTrack":"#27323A","ringFill":"#87BADD"]),
    ("Rose Quartz",
     ["bg":"#FAEFF1","surface":"#FFFAFB","text":"#4D353B","textSecondary":"#A4838C","ringTrack":"#F4E2E6","ringFill":"#D9869A"],
     ["bg":"#221619","surface":"#2E2024","text":"#F4E3E8","textSecondary":"#B8979F","ringTrack":"#3B2A2E","ringFill":"#E6A3B4"]),
    ("Butter Honey",
     ["bg":"#FBF6E9","surface":"#FFFDF6","text":"#48402B","textSecondary":"#9A8C6A","ringTrack":"#F3EAD2","ringFill":"#DDB347"],
     ["bg":"#211C12","surface":"#2D271A","text":"#F4ECD7","textSecondary":"#B5A580","ringTrack":"#3A3322","ringFill":"#EAC774"]),
    ("Glacier Mint",
     ["bg":"#EAF4F2","surface":"#F8FDFC","text":"#2C433F","textSecondary":"#769590","ringTrack":"#DCEEEA","ringFill":"#5DBBAE"],
     ["bg":"#131F1D","surface":"#1D2B28","text":"#DFF0ED","textSecondary":"#8AACA6","ringTrack":"#26352F","ringFill":"#84CFC4"]),
    ("Greige Stone",
     ["bg":"#F2EFEA","surface":"#FBF9F6","text":"#403B34","textSecondary":"#928A7E","ringTrack":"#E8E3DB","ringFill":"#A0937F"],
     ["bg":"#1C1A17","surface":"#272421","text":"#EDE9E2","textSecondary":"#A89F92","ringTrack":"#332F2A","ringFill":"#C2B8A7"]),
]

func fmt(_ x: Double) -> String { String(format: "%.2f", x) }
var failures = 0

func audit(_ name: String, _ scheme: String, _ c: Colors) {
    let bg = RGB(hex: c["bg"]!), surface = RGB(hex: c["surface"]!)
    let text = RGB(hex: c["text"]!), sec = RGB(hex: c["textSecondary"]!)
    let track = RGB(hex: c["ringTrack"]!), fill = RGB(hex: c["ringFill"]!)

    let timer = enforce(enforce(text, against: bg, 7.0), against: surface, 7.0)
    let body = enforce(enforce(sec, against: bg, 4.5), against: surface, 4.5)
    let rf = enforce(fill, against: track, 3.0)

    let checks: [(String, Double, Double)] = [
        ("timer/bg", contrast(timer, bg), 7.0),
        ("timer/surface", contrast(timer, surface), 7.0),
        ("secondary/bg", contrast(body, bg), 4.5),
        ("secondary/surface", contrast(body, surface), 4.5),
        ("ringFill/track", contrast(rf, track), 3.0),
    ]
    var line = "  [\(scheme)] "
    for (label, ratio, tier) in checks {
        let ok = ratio >= tier - 0.001
        if !ok { failures += 1 }
        line += "\(label)=\(fmt(ratio))\(ok ? "✓" : "✗(<\(fmt(tier)))")  "
    }
    print(line)
}

print("PomoLight contrast audit — enforced (resolved) palette\n")
for (name, light, dark) in themes {
    print("\(name):")
    audit(name, "light", light)
    audit(name, "dark ", dark)
}
print("")
if failures == 0 {
    print("✅ PASS — all themes meet WCAG tiers (timer 7:1, text 4.5:1, ring 3:1).")
    exit(0)
} else {
    print("❌ FAIL — \(failures) contrast pair(s) below tier.")
    exit(1)
}
