import SwiftUI

/// The action row beneath the dial: the primary button, plus Reset and +1 min
/// while a timer is active. Buttons appear/disappear by state so an irrelevant
/// action is never shown.
struct ControlsView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(AppModel.self) private var app
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            if engine.isActive {
                CircleIconButton(systemName: "arrow.counterclockwise",
                                 tint: palette.secondaryText,
                                 soft: palette.accentSoft, size: 44) {
                    app.resetTimer()
                }
                .keyboardShortcut("r", modifiers: [])
                .help("Reset")
                .accessibilityLabel("Reset")
            }

            Button(action: { app.primaryAction() }) {
                HStack(spacing: 8) {
                    Image(systemName: primaryIcon)
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 18, height: 18)   // fixed slot — icon swap can't shift the label
                    Text(primaryTitle)
                }
                .animation(nil, value: engine.phase)    // no morph/jitter on Start↔Pause
            }
            .buttonStyle(PomoPrimaryButtonStyle(fill: palette.buttonFill,
                                                label: palette.buttonLabel,
                                                glow: palette.accent))
            .keyboardShortcut(.space, modifiers: [])
            .help(primaryTitle)
            .accessibilityLabel(primaryTitle)

            if engine.isActive {
                CircleIconButton(systemName: "plus",
                                 tint: palette.secondaryText,
                                 soft: palette.accentSoft, size: 44) {
                    app.addMinute()
                }
                .keyboardShortcut("=", modifiers: [])
                .help("Add one minute")
                .accessibilityLabel("Add one minute")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: engine.isActive)
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
