import AppKit

/// Brings PomoLight's window forward when a timer finishes, so a buried, closed or
/// minimised window surfaces and the user can't miss the gentle alarm — without
/// taking the keyboard away from the app they are typing in (#68).
enum AppActivation {
    static func bringToFront() {
        // NSApp is nil during very early App.main() startup — activating then would
        // crash. (It used to say "e.g. background launch for a widget intent"; the
        // widget went in PR #33, but an early call can still land here.)
        guard NSApp != nil else { return }
        // 🚨 2026-11-20 (#68): 여기는 `NSApp.activate(ignoringOtherApps: true)` 뒤
        // `for window in NSApp.windows where window.canBecomeMain` 를 돌며
        // deminiaturize·makeKeyAndOrderFront 를 했다. macOS 27.2.1 에서 완료 순간의
        // 창 목록을 앱 안에서 찍어 보니(다른 앱이 맨 앞):
        //   · 창을 닫아 둔 경우 — 본창 객체는 살아 있었다(visible=false). canBecomeMain=false.
        //   · 최소화한 경우 — mini=true, canBecomeMain=false. 그래서 2026-08-21 에 넣은
        //     deminiaturize 는 한 번도 불리지 않았다.
        //   · 열려 있고 뒤에 있는 경우만 canBecomeMain=true 라 올라왔다(그리고 키 입력을 가져갔다).
        // 보이지 않는 창은 canBecomeMain 필터를 못 지난다 — 이 함수가 올려야 할 창이 정확히
        // 그 창들이다. activate 도 닫힘·최소화에서는 active=false 그대로였다.
        //
        // 오너 결정(2026-11-20, 리뷰 F-5 → A): 완료 화면은 맨 앞에 보이게 올리되 키 입력은
        // 가져오지 않는다. 다른 앱에서 타이핑하던 사람의 다음 스페이스가 알람 '끄기'로
        // 들어가면 안 된다. 그래서 activate·makeKey 를 하지 않고 orderFrontRegardless 로
        // 창만 앞에 놓는다. 창을 누르면 그때 평소처럼 앱이 활성화된다.
        for window in mainWindows() {
            if window.isMiniaturized {
                window.deminiaturize(nil)
                // 최소화에서 되살린 창은 바로 아래 orderFrontRegardless 로 맨 위에 왔다가
                // 0.1초 안에 맨 앞 앱의 창 밑으로 다시 깔렸다(2026-11-20 실측 3회). 복원 완료
                // 알림(didDeminiaturize)은 deminiaturize 안에서 이미 지나가고, 깔리는 순간에는
                // 창 가림 상태 알림도 오지 않아 붙잡을 신호가 없다. 0.5초 뒤에 다시 올리니
                // 그대로 맨 위에 남았다 — 느린 기계를 생각해 1.5초에 한 번 더. 그사이 사람이
                // 다시 최소화·닫기를 했으면 건드리지 않는다.
                for delay in [0.5, 1.5] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak window] in
                        guard let window, window.isVisible, !window.isMiniaturized else { return }
                        window.orderFrontRegardless()
                    }
                }
            }
            window.orderFrontRegardless()
        }
        // A single soft dock bounce — informational, not the relentless kind.
        NSApp.requestUserAttention(.informationalRequest)
    }

    /// The app's own document-style windows, whatever state they are in — closed
    /// (ordered out), minimised or open. `canBecomeMain` is not usable for this: it
    /// is false for any window that is not on screen (measured on macOS 27.2.1,
    /// 2026-11-20, #68). Panels (About, alerts), the status bar's own windows and the
    /// menu-bar popover are left alone: the main window measured as a titled, non-panel
    /// window at the normal level, and the status-bar windows as untitled at level 25.
    /// The popover's window could not be opened by automation, so it was not measured —
    /// the level check is what keeps it out even if it turns out to be titled.
    private static func mainWindows() -> [NSWindow] {
        NSApp.windows.filter {
            $0.styleMask.contains(.titled) && !($0 is NSPanel) && $0.level == .normal
        }
    }

    static func openMainWindow() {
        guard NSApp != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}
