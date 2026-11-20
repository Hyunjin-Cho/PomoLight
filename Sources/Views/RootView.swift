import SwiftUI

/// The main window: a calm pastel card with the timer dial at its heart, the
/// duration controls below, and a quiet gear in the top bar. Settings come down as a
/// sheet from this window's title bar — you never leave the timer.
/// 2026-11-20 (#72, 오너 결정 시안 B): 예전엔 설정을 이 창 안에 겹쳐 그려서 320 폭 창에 갇혀 4화면을 스크롤했다.
/// 시트는 부모 창보다 넓게 뜬다(2026-11-20 실측 580 폭, 시트 위 NSAlert 정상). 시트는 모달이라 뒤 화면의 단축키
/// (Space·R·숫자)도 들어가지 않는다(#70 F-10).
struct RootView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(ThemeStore.self) private var theme
    // 2026-08-21: `@Environment(AppModel.self) private var app` sat here unused. It
    // is not free — `@Environment` traps when nothing injected it, so an unused one
    // is a false requirement on every place that assembles this view by hand
    // (`Snapshot.swift` does).
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
            }
            // The theme swap stays animated either way: it is a colour cross-fade,
            // which is what Reduce Motion asks for INSTEAD of movement, not a thing
            // to switch off.
            .animation(.easeInOut(duration: 0.5), value: theme.current)
        }
        // The sheet's arrival is the system's own animation (it follows Reduce Motion
        // as macOS does for every sheet). The palette is passed in fresh on every
        // change, so a theme picked inside the sheet recolours the sheet at once.
        .sheet(isPresented: $showSettings) {
            SettingsPanelView(palette: palette, isPresented: $showSettings)
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

            // 2026-11-19 (#6): the donation heart sat on the right until donations
            // were dropped; the Spacer keeps the gear where it was.
            Spacer()
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
