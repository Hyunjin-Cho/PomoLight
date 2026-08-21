import SwiftUI

/// The main window: a calm pastel card with the timer dial at its heart, the
/// duration controls below, and a quiet gear/heart top bar. The settings panel
/// slides over this same window — you never leave the timer.
struct RootView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(ThemeStore.self) private var theme
    // 2026-08-21: `@Environment(AppModel.self) private var app` sat here unused. It
    // is not free — `@Environment` traps when nothing injected it, so an unused one
    // is a false requirement on every place that assembles this view by hand
    // (`Snapshot.swift` does).
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showSettings = false

    var body: some View {
        let palette = theme.palette(for: scheme)

        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [palette.bg, palette.bgDeep],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar(palette)
                    Spacer(minLength: 8)
                    TimerDial(palette: palette, diameter: dialDiameter(in: geo.size))
                    Spacer(minLength: 18)
                    bottomArea(palette)
                    Spacer(minLength: 6)
                }
                .padding(20)

                if showSettings {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture { showSettings = false }
                        .transition(.opacity)

                    SettingsPanelView(palette: palette, isPresented: $showSettings)
                        // 2026-08-21: the dial, the chips and the hover lifts have
                        // honoured Reduce Motion since they were written; this screen
                        // — the settings card zooming in on a spring, the biggest
                        // movement in the app — did not. A cross-fade is the
                        // substitution Apple asks for, so the panel still reads as
                        // arriving without anything travelling.
                        .transition(reduceMotion ? AnyTransition.opacity
                                                 : AnyTransition.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            // The theme swap stays animated either way: it is a colour cross-fade,
            // which is what Reduce Motion asks for INSTEAD of movement, not a thing
            // to switch off.
            .animation(.easeInOut(duration: 0.5), value: theme.current)
            .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                    : .spring(response: 0.35, dampingFraction: 0.85),
                       value: showSettings)
        }
        .onChange(of: showSettings) { _, open in
            // Make sure the window is key so the panel's controls take the first click.
            if open { AppActivation.openMainWindow() }
        }
    }

    private func topBar(_ palette: Palette) -> some View {
        HStack {
            CircleIconButton(systemName: "gearshape.fill",
                             tint: palette.controlIcon,
                             soft: palette.accentSoft, size: 32,
                             font: .system(size: 14)) {
                showSettings = true
            }
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings")
            .accessibilityLabel("Settings")

            Spacer()

            DonateButton(palette: palette)
        }
    }

    @ViewBuilder
    private func bottomArea(_ palette: Palette) -> some View {
        VStack(spacing: 18) {
            if engine.phase == .idle {
                DurationPickerView(palette: palette)
                    .transition(.opacity)
            }
            ControlsView(palette: palette)
        }
        .animation(.easeInOut(duration: 0.25), value: engine.phase)
    }

    private func dialDiameter(in size: CGSize) -> CGFloat {
        let available = min(size.width - 56, size.height - 240)
        return max(180, min(available, 360))
    }
}
