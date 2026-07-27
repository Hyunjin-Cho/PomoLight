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

    /// How often the dial redraws while running.
    ///
    /// Every update rebuilds the ring, its glow and the numerals, and each one costs a
    /// full window layout pass — so this one number is essentially the whole cost of
    /// having PomoLight open. It used to ask for 30 fps, which measured **11.3% of a
    /// CPU core on an M1 Max**, and nearly all of that bought nothing visible: the
    /// ring advances by *distance*, and a 25-minute session moves it ≈0.7 px per
    /// SECOND at this size — about 1/40 px per frame at 30 fps.
    ///
    /// Measured (Release build, 30-minute timer, window visible, avg CPU over 3-5 min):
    ///
    ///     30 fps 11.25%  |  2 fps 2.38%  |  1 fps 1.93%  |  no redraws 1.40%
    ///
    /// 2 fps keeps the numerals within half a second of the clock and the
    /// final-10-second glow ramp smooth, for a fifth of the power. The 1.40% floor is
    /// the 1 Hz menu-bar label plus the engine's ticker, which this doesn't control —
    /// so 1 fps would only save 0.45 pp more while doubling the lag.
    private static let frameInterval: Double = 0.5

    var body: some View {
        let running = engine.phase == .running
        TimelineView(.animation(minimumInterval: running ? Self.frameInterval : nil,
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
