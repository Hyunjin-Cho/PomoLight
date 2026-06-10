import AppKit

/// Minimal AppKit delegate: keeps the app resident when the window is closed (so
/// the menu-bar timer keeps running) and nothing else.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        Snapshot.runIfRequested()
        #endif
        // Become the active app so the window is key and controls respond to the
        // very first click (otherwise the first click only focuses the window).
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Reopen the main window when the dock icon is clicked and no window is visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppActivation.openMainWindow() }
        return true
    }
}
