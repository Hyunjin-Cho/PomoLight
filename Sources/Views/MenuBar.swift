import SwiftUI

/// The live countdown shown in the macOS menu bar (MM:SS while active, a small
/// timer glyph when idle). The engine's 0.2 s ticker bumps `menuBarTick` only when
/// the whole second changes, so this label refreshes at ~1 Hz instead of five times
/// a second. Unrelated to the dial's frame rate — the two redraw independently.
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
            // Two Text branches so "Time's up" goes through localization
            // (a String ternary would render the raw English key).
            (engine.phase == .finished ? Text("Time's up")
                                       : Text(verbatim: engine.formatted(engine.remaining())))
                .font(.system(size: 36, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.timerText)

            HStack(spacing: 10) {
                Button(action: { app.primaryAction() }) {
                    Label(primaryTitle, systemImage: primaryIcon)
                        .frame(maxWidth: .infinity)
                }
                // 🚨 2026-08-21: this was `.borderedProminent` + `.tint(palette.accent)`,
                // which handed the ink choice to AppKit. Measured on macOS 26.5.2: the
                // system does flip the label by tint brightness (yellow/lime/mint/sky/
                // coral got dark ink and were fine), but on the darker accents it chose
                // WHITE — Magenta 2.27:1, Violet 2.52:1, Blue 2.54:1, Indigo 3.13:1 —
                // exactly where `LegibleFill` picks dark ink at 5.22–7.21:1. So the same
                // "Start" was legible in the main window and washed out in the popover.
                // Using the app's own pair puts this button back under the 4.5:1 that
                // `Scripts/contrast_audit.sh` already checks for every theme.
                .buttonStyle(PomoPrimaryButtonStyle(fill: palette.buttonFill,
                                                    label: palette.buttonLabel,
                                                    glow: palette.accent,
                                                    minWidth: 0, height: 34, fontSize: 14))

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
