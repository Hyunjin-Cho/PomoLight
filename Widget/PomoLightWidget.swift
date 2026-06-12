import WidgetKit
import SwiftUI

/// A glanceable PomoLight widget for the desktop / Notification Center. It reads
/// the shared timer snapshot the app publishes and shows a live countdown (the
/// number self-ticks while running, with no constant timeline reloads).
struct PomoEntry: TimelineEntry {
    let date: Date
    let snapshot: TimerSnapshot
}

struct PomoProvider: TimelineProvider {
    func placeholder(in context: Context) -> PomoEntry {
        PomoEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PomoEntry) -> Void) {
        completion(PomoEntry(date: Date(), snapshot: SharedStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PomoEntry>) -> Void) {
        let snap = SharedStore.read()
        let entry = PomoEntry(date: Date(), snapshot: snap)
        // While running, refresh once at the deadline (to flip to "done"). Otherwise
        // the app drives reloads when state changes.
        let policy: TimelineReloadPolicy
        if snap.phase == .running, let deadline = snap.deadline, deadline > Date() {
            policy = .after(deadline)
        } else {
            policy = .never
        }
        completion(Timeline(entries: [entry], policy: policy))
    }
}

struct PomoLightWidgetView: View {
    let entry: PomoEntry
    @Environment(\.widgetFamily) private var family

    private var snap: TimerSnapshot { entry.snapshot }
    private var accent: Color { Color(appHex: snap.accentHex) }
    private var isLiveRunning: Bool {
        if case .running = snap.phase, let d = snap.deadline, d > entry.date { return true }
        return false
    }
    /// Snapshot may still say "running" after its deadline passed while the app was
    /// closed — display (and label buttons for) the truth.
    private var effectivePhase: TimerSnapshot.Phase {
        if case .running = snap.phase, let d = snap.deadline, d <= entry.date { return .finished }
        return snap.phase
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            default:           large    // systemLarge
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [accent.opacity(0.20), accent.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "pomolight://open"))
    }

    // MARK: Small (1/4 of large)

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                header
                Spacer()
                toggleButton(size: 28, font: 11)
            }
            Spacer(minLength: 2)
            countdown
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 4)
            progress
        }
    }

    // MARK: Large (big ring)

    private var large: some View {
        VStack(spacing: 10) {
            HStack {
                header
                Spacer()
            }
            ZStack {
                Circle().stroke(accent.opacity(0.18), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: max(0.001, snap.fractionRemaining))
                    .stroke(accent, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                countdown
                    .font(.system(size: 50, weight: .medium, design: .rounded))
            }
            .padding(4)
            HStack(spacing: 14) {
                if effectivePhase == .running || effectivePhase == .paused {
                    Button(intent: TimerResetIntent()) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(accent.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset")
                }
                toggleButton(size: 44, font: 17)
            }
        }
    }

    /// The state-aware primary control (start / pause / resume / dismiss).
    private func toggleButton(size: CGFloat, font: CGFloat) -> some View {
        Button(intent: TimerToggleIntent()) {
            Image(systemName: toggleIcon)
                .font(.system(size: font, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(accent))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(toggleLabel)
    }

    private var toggleIcon: String {
        switch effectivePhase {
        case .idle, .paused: return "play.fill"
        case .running:       return "pause.fill"
        case .finished:      return "checkmark"
        }
    }

    private var toggleLabel: LocalizedStringKey {
        switch effectivePhase {
        case .idle:     return "Start"
        case .running:  return "Pause"
        case .paused:   return "Resume"
        case .finished: return "Dismiss"
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(accent)
            Text(statusKey)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var countdown: some View {
        if isLiveRunning, let d = snap.deadline {
            Text(timerInterval: entry.date...d, countsDown: true)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        } else if effectivePhase == .finished {
            Text(snap.formatted(0))
                .monospacedDigit()
                .foregroundStyle(.primary)
        } else {
            Text(snap.formatted(snap.remaining))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder private var progress: some View {
        if isLiveRunning, let d = snap.deadline {
            ProgressView(timerInterval: entry.date...d, countsDown: true) {
                EmptyView()
            } currentValueLabel: { EmptyView() }
                .tint(accent)
                .labelsHidden()
        } else {
            ProgressView(value: max(0, min(1, snap.fractionRemaining)))
                .tint(accent)
        }
    }

    private var statusKey: LocalizedStringKey {
        switch effectivePhase {
        case .idle:     return "ready"
        case .running:  return "left"
        case .paused:   return "paused"
        case .finished: return "done"
        }
    }

    private var icon: String {
        switch effectivePhase {
        case .idle:     return "timer"
        case .running:  return "hourglass"
        case .paused:   return "pause.circle"
        case .finished: return "bell.fill"
        }
    }
}

struct PomoLightWidget: Widget {
    let kind = "PomoLightWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PomoProvider()) { entry in
            PomoLightWidgetView(entry: entry)
        }
        .configurationDisplayName("PomoLight")
        .description("Glance at your focus timer.")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

@main
struct PomoLightWidgetBundle: WidgetBundle {
    var body: some Widget {
        PomoLightWidget()
    }
}
