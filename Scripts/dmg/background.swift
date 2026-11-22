import Cocoa
// PomoLight DMG 설치 창 배경 (2026-11-22, #11) — 닦아(ddaka) 설치 창과 같은 꼴, 색만 PomoLight 아이콘(크림·복숭아·코랄)에 맞췄다.
//   swift Scripts/dmg/background.swift <out-dir>   →  <out-dir>/background.png, background@2x.png
// 🔒 W x H 와 아이콘 중심 두 점은 Scripts/dmg/settings.py 의 window_rect · icon_locations 와 같은 값이어야 한다.
//    한쪽만 고치면 화살표가 엉뚱한 곳을 가리키거나 아래 줄이 잘린다.
// 높이 440: Finder 창은 제목 표시줄만큼 안쪽이 줄어들어서, 400·430 으로는 맨 아래 영어 줄이 잘렸다(닦아 2026-09-22 오너 실물 확인).
// 좌표는 전부 위에서부터(yTop · Finder 좌표) 잰다.
let W: CGFloat = 640, H: CGFloat = 440
let appCenter = CGPoint(x: 165, y: 195)
let applicationsCenter = CGPoint(x: 475, y: 195)

// 아이콘(Scripts/make_icon.swift)의 색
let coral = NSColor(srgbRed: 0.925, green: 0.545, blue: 0.384, alpha: 1)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // 배경은 거의 흰색의 따뜻한 크림 — 복숭아색 아이콘이 묻히지 않게 물러난다.
    NSGradient(starting: NSColor(srgbRed: 0.997, green: 0.990, blue: 0.984, alpha: 1),
               ending: NSColor(srgbRed: 0.980, green: 0.949, blue: 0.929, alpha: 1))!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    func center(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, yTop: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
        let s = text as NSString
        let measured = s.size(withAttributes: attributes)
        s.draw(at: NSPoint(x: (W - measured.width) / 2, y: H - yTop - measured.height), withAttributes: attributes)
    }
    // 위: 작고 옅은 안내 / 가운데: 크고 진한 지시 — 시선이 두 번째 줄에 꽂히게
    center("PomoLight를 설치하려면", size: 15, weight: .regular, color: NSColor(white: 0.42, alpha: 1), yTop: 22)
    center("아이콘을 응용 프로그램 폴더로 드래그하세요", size: 22, weight: .bold,
           color: NSColor(srgbRed: 0.16, green: 0.11, blue: 0.09, alpha: 1), yTop: 48)
    center("Drag the icon into the Applications folder", size: 14, weight: .medium, color: NSColor(white: 0.38, alpha: 1), yTop: 84)

    // 화살표 — 짧고 굵게, 아이콘 링과 같은 코랄. 아이콘 128px 기준으로 양옆 78 띄운다.
    let y = H - appCenter.y
    let x1 = appCenter.x + 78, x2 = applicationsCenter.x - 78
    let head: CGFloat = 30
    coral.setFill(); coral.setStroke()
    let bar = NSBezierPath()
    bar.move(to: NSPoint(x: x1, y: y))
    bar.line(to: NSPoint(x: x2 - head + 2, y: y))
    bar.lineWidth = 15
    bar.lineCapStyle = .butt
    bar.stroke()
    let tip = NSBezierPath()
    tip.move(to: NSPoint(x: x2, y: y))
    tip.line(to: NSPoint(x: x2 - head, y: y + head * 0.72))
    tip.line(to: NSPoint(x: x2 - head, y: y - head * 0.72))
    tip.close()
    tip.fill()

    // DMG 안에서 바로 띄우면 읽기 전용 디스크라 앱 안 업데이트(OnePercent)가 설치를 거절한다 — 그래서 옮긴 뒤 실행을 당부한다.
    center("여기서 바로 실행하지 말고, 옮긴 뒤에 실행해 주세요", size: 12, weight: .medium,
           color: NSColor(srgbRed: 0.55, green: 0.30, blue: 0.10, alpha: 1), yTop: 320)
    center("Move it to Applications first, then open", size: 11, weight: .regular, color: NSColor(white: 0.48, alpha: 1), yTop: 340)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dir = CommandLine.arguments[1]
for (name, scale) in [("background.png", CGFloat(1)), ("background@2x.png", CGFloat(2))] {
    try! render(scale: scale).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
}
print("✅ DMG background drawn (\(Int(W))x\(Int(H)), 1x + 2x)")
