import SwiftUI

/// The centerpiece: the progress ring with the big MM:SS numerals inside it.
/// A `TimelineView(.animation)` recomputes everything from the engine's deadline on
/// a fixed cadence while running, so the ring drains continuously instead of
/// stepping once a second, and sleeps (no redraws at all) when idle/paused.
struct TimerDial: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let palette: Palette
    let diameter: CGFloat

    @State private var pulseScale: CGFloat = 1.0

    /// Redraw cadence, from the ring's own speed — see `DialFrameRate` for the rule
    /// and the power measurements behind it. Short timers get a fast ring and earn a
    /// high rate; a 25-minute ring crawls and doesn't.
    private var frameInterval: Double {
        DialFrameRate.interval(dialDiameter: Double(diameter),
                               duration: engine.configuredDuration)
    }

    var body: some View {
        let running = engine.phase == .running
        TimelineView(.animation(minimumInterval: running ? frameInterval : nil,
                                paused: !running)) { context in
            content(at: context.date)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(pulseScale)
        .onAppear { updatePulse(engine.phase) }
        .onChange(of: engine.phase) { _, phase in updatePulse(phase) }
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        let finished = engine.phase == .finished
        let remaining = engine.remaining(at: now)
        let fraction = engine.fractionRemaining(at: now)
        let dimmed = engine.phase == .idle || engine.phase == .paused
        let nearEnd = engine.phase == .running && remaining <= 10 && remaining > 0
        let glow: CGFloat = finished ? 0.9 : (nearEnd ? CGFloat((10 - remaining) / 10) : 0)

        ZStack {
            RingView(fractionRemaining: finished ? 1 : fraction,
                     palette: palette,
                     lineWidth: max(10, diameter * 0.062),
                     dimmed: dimmed,
                     glowStrength: reduceMotion ? 0 : glow)

            VStack(spacing: 6) {
                // Two Text branches, NOT one Text(ternary): a `String` ternary
                // silently picks the verbatim initializer and skips localization.
                (finished ? Text("Time's up") : Text(verbatim: engine.formatted(remaining)))
                    .font(finished
                          ? .system(size: diameter * 0.13, weight: .semibold, design: .rounded)
                          : .system(size: diameter * 0.25, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.timerText)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())

                Text(stateLabel)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
                    .textCase(.lowercase)
            }
            .padding(diameter * 0.2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(finished ? Text("Time's up")
                                     : Text(verbatim: engine.accessibleRemaining(remaining)))
    }

    private var stateLabel: LocalizedStringKey {
        switch engine.phase {
        case .idle:     return "ready"
        case .running:  return "left"
        case .paused:   return "paused"
        case .finished: return "done"
        }
    }

    private func updatePulse(_ phase: TimerEngine.Phase) {
        if phase == .finished && !reduceMotion {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulseScale = 1.025
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) { pulseScale = 1.0 }
        }
    }
}
