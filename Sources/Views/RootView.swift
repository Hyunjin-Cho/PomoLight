import SwiftUI

/// The main window: a calm pastel card with the timer dial at its heart, the
/// duration controls below, and a quiet gear/heart top bar. The settings panel
/// slides over this same window — you never leave the timer.
struct RootView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(ThemeStore.self) private var theme
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme

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
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.5), value: theme.current)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showSettings)
        }
        .onChange(of: showSettings) { _, open in
            // Make sure the window is key so the panel's controls take the first click.
            if open { AppActivation.openMainWindow() }
        }
    }

    private func topBar(_ palette: Palette) -> some View {
        HStack {
            CircleIconButton(systemName: "gearshape.fill",
                             tint: palette.secondaryText,
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
