import SwiftUI

/// The big primary pill (Start / Pause / Resume / Dismiss). Always a filled,
/// legible button; the state is also signaled by the ring, so color alone never
/// carries meaning.
struct PomoPrimaryButtonStyle: ButtonStyle {
    let fill: Color
    let label: Color
    let glow: Color
    // 2026-08-21: the sizes became parameters so the menu-bar popover can use this
    // style too. It used to be stuck at the main window's 150x48, which is why the
    // popover reached for `.borderedProminent` instead — and thereby skipped the
    // fill/label pair this style exists to enforce.
    var minWidth: CGFloat = 150
    var height: CGFloat = 48
    var fontSize: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(label)
            .frame(minWidth: minWidth)
            .frame(height: height)
            .background(Capsule().fill(fill))
            .shadow(color: glow.opacity(0.30), radius: 8, y: 2)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// A quiet circular icon button (Reset, gear, heart, the stepper's +/-). Lifts
/// gently on hover. (The "+1 min" button it also used to serve went in PR #13.)
struct CircleIconButton: View {
    let systemName: String
    let tint: Color
    var soft: Color = .clear
    var size: CGFloat = 40
    var font: Font = .system(size: 16, weight: .medium)
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(font)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(soft.opacity(hovering ? 0.6 : 0)))
                .scaleEffect(hovering && !reduceMotion ? 1.06 : 1.0)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// A soft preset/duration chip. Selected = deepened accent fill with a legible
/// label; at rest = a pale accentSoft candy.
struct PresetChip: View {
    let title: String
    let selected: Bool
    let palette: Palette
    var hPadding: CGFloat = 14
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(selected ? palette.buttonLabel : palette.onAccentSoft)
                .fixedSize()
                .padding(.horizontal, hPadding)
                .frame(height: 30)
                .background(
                    Capsule().fill(selected ? palette.buttonFill : palette.accentSoft)
                )
                .scaleEffect(hovering && !reduceMotion ? 1.03 : 1.0)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
