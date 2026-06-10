#!/usr/bin/env swift
// Waits for PomoLight's window to appear and prints "x y w h" (screen coords).
import CoreGraphics
import Foundation

func pomoBounds() -> CGRect? {
    let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
    guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return nil }
    for w in list {
        guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "PomoLight",
              let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
              let b = w[kCGWindowBounds as String] as? [String: CGFloat],
              let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
              width > 200 else { continue }
        return CGRect(x: x, y: y, width: width, height: height)
    }
    return nil
}

for _ in 0..<50 {
    if let r = pomoBounds() {
        print("\(Int(r.minX)) \(Int(r.minY)) \(Int(r.width)) \(Int(r.height))")
        exit(0)
    }
    usleep(200_000)
}
exit(1)
