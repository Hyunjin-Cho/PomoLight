import SwiftUI

/// The live countdown shown in the macOS menu bar (MM:SS while active, a small
/// timer glyph when idle). `menuBarTick` drives a ~1 Hz refresh without redrawing
/// the menu bar 30×/second.
struct MenuBarLabel: View {
    @Environment(TimerEngine.self) private var engine

    var body: some View {
        let _ = engine.menuBarTick
        if engine.phase == .finished {
            Image(systemName: "bell.fill")
        } else if engine.isActive {
            Text(engine.formatted(engine.remaining()))
                .monospacedDigit()
        } else {
            Image(systemName: "timer")
        }
    }
}

/// The menu-bar popover: a glanceable countdown plus mini controls.
struct MenuBarContent: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(AppModel.self) private var app
    @Environment(ThemeStore.self) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let palette = theme.palette(for: scheme)
        let _ = engine.menuBarTick
        VStack(spacing: 14) {
            Text(engine.phase == .finished ? "Time's up" : engine.formatted(engine.remaining()))
                .font(.system(size: 36, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.timerText)

            HStack(spacing: 10) {
                Button(action: { app.primaryAction() }) {
                    Label(primaryTitle, systemImage: primaryIcon)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .tint(palette.accent)
                .buttonStyle(.borderedProminent)

                if engine.isActive {
                    Button(action: { app.resetTimer() }) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .controlSize(.large)
                }
            }

            Button("Open PomoLight") {
                openWindow(id: WindowID.main)
                NSApp.activate(ignoringOtherApps: true)
            }
                .buttonStyle(.plain)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(palette.secondaryText)
        }
        .padding(16)
        .frame(width: 220)
        .background(palette.surface)
    }

    private var primaryTitle: LocalizedStringKey {
        switch engine.phase {
        case .idle:     return "Start"
        case .running:  return "Pause"
        case .paused:   return "Resume"
        case .finished: return "Dismiss"
        }
    }

    private var primaryIcon: String {
        switch engine.phase {
        case .idle, .paused: return "play.fill"
        case .running:       return "pause.fill"
        case .finished:      return "checkmark"
        }
    }
}
