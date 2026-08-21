import AppKit

/// Brings PomoLight to the foreground when a timer finishes, so a buried window
/// surfaces and the user can't miss the gentle alarm.
enum AppActivation {
    static func bringToFront() {
        // NSApp is nil during very early App.main() startup — activating then would
        // crash. (It used to say "e.g. background launch for a widget intent"; the
        // widget went in PR #33, but an early call can still land here.)
        guard NSApp != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            // 🚨 2026-08-21: this loop skipped miniaturized windows, so a timer that
            // finished while the window sat in the Dock left it there — measured: the
            // window stayed minimised for 20+ s after the chime fired. The chime, the
            // banner and the dock bounce still landed, but the finished screen (the
            // thing this function exists to show) never came up. Neither `activate`
            // nor `makeKeyAndOrderFront` un-minimises on their own, so ask explicitly.
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        // A single soft dock bounce — informational, not the relentless kind.
        NSApp.requestUserAttention(.informationalRequest)
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
