import AppKit

/// Brings PomoLight to the foreground when a timer finishes, so a buried window
/// surfaces and the user can't miss the gentle alarm.
enum AppActivation {
    static func bringToFront() {
        // NSApp is nil during very early App.main() startup (e.g. background launch
        // for a widget intent) — activating then would crash.
        guard NSApp != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain && !window.isMiniaturized {
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
