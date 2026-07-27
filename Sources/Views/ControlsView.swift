import SwiftUI

/// The action row beneath the dial: the primary button, plus Reset while a timer
/// is active. Buttons appear/disappear by state so an irrelevant action is never
/// shown.
///
/// There used to be a "+1 min" button here. It was removed: one minute is the wrong
/// unit for the ask it served (wanting five or ten meant five or ten clicks), the
/// bare `+` never said what it did, and the widget — which offers start/pause/reset
/// only — had always managed without it. With no session history in the app, resetting
/// and picking a new duration loses nothing but the countdown's position.
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
                // Balances the Reset button so the primary action stays centred under
                // the dial instead of sliding ~28 pt to the right.
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
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
