#!/usr/bin/env swift
// Generates the PomoLight app icon set (a soft pastel rounded square with a
// peach progress ring) at all required macOS sizes, headless via CoreGraphics.
// Run:  swift Scripts/make_icon.swift

import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let outDir = "Sources/Assets.xcassets/AppIcon.appiconset"
let sizes = [16, 32, 64, 128, 256, 512, 1024]

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func makeIcon(_ size: Int) -> CGImage? {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // Rounded-square body (macOS icons carry their own shape + margin).
    let inset = s * 0.085
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let body = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    // Soft vertical pastel gradient (cream -> peach).
    let colors = [rgb(0.992, 0.953, 0.925), rgb(0.965, 0.741, 0.616)] as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    }
    ctx.restoreGState()

    // Progress ring.
    let center = CGPoint(x: s / 2, y: s / 2)
    let ringRadius = rect.width * 0.30
    let lineWidth = rect.width * 0.075

    // Track.
    ctx.setLineWidth(lineWidth)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.55))
    ctx.setLineCap(.round)
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Filled arc (~72% remaining), deeper peach, starting at 12 o'clock.
    ctx.setStrokeColor(rgb(0.925, 0.545, 0.384))
    let start = CGFloat.pi / 2
    let sweep = CGFloat.pi * 2 * 0.72
    ctx.addArc(center: center, radius: ringRadius, startAngle: start, endAngle: start - sweep, clockwise: true)
    ctx.strokePath()

    // Center dot.
    ctx.setFillColor(rgb(0.925, 0.545, 0.384))
    let dot = ringRadius * 0.16
    ctx.fillEllipse(in: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2))

    return ctx.makeImage()
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

for size in sizes {
    guard let img = makeIcon(size) else { print("failed \(size)"); continue }
    write(img, to: "\(outDir)/icon_\(size).png")
    print("wrote icon_\(size).png")
}
print("done")
