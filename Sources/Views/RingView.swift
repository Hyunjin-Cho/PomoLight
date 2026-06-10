import SwiftUI

/// The circular progress ring. A full ring means full time; it depletes clockwise
/// from 12 o'clock as the countdown runs. Round caps keep it soft, never sharp.
struct RingView: View {
    let fractionRemaining: Double      // 1 = full, 0 = empty
    let palette: Palette
    let lineWidth: CGFloat
    var dimmed: Bool = false           // idle / paused look
    var glowStrength: CGFloat = 0      // 0...1, used near the end & on finish

    var body: some View {
        ZStack {
            // Soft halo seats the ring on the surface.
            Circle()
                .fill(palette.accentSoft.opacity(dimmed ? 0.18 : 0.30))
                .padding(lineWidth / 2)

            // Empty groove.
            Circle()
                .stroke(palette.ringTrack, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // Remaining arc.
            Circle()
                .trim(from: 0, to: max(0.0001, fractionRemaining))
                .stroke(palette.ringFill.opacity(dimmed ? 0.55 : 1.0),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: palette.ringFill.opacity(Double(glowStrength) * 0.7),
                        radius: glowStrength * 18)
        }
    }
}
