import AppKit

/// Minimal AppKit delegate: keeps the app resident when the window is closed (so
/// the menu-bar timer keeps running) and nothing else.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 2026-11-22 (#14): quitting closes the settings sheet first — without it, quit was ignored
        // while the sheet was open (Remove PomoLight left the app running). See QuitClosesSheets.
        QuitClosesSheets.install()
        #if DEBUG
        Snapshot.runIfRequested()
        Uninstaller.runSelfTestIfRequested()
        #endif
        // Become the active app so the window is key and controls respond to the
        // very first click (otherwise the first click only focuses the window).
        NSApp.activate(ignoringOtherApps: true)
    }

    // 🚨 2026-08-21: applicationWillTerminate is gone, and its absence is the point.
    //
    // #24 gave it two jobs, both of which only existed because the widget did: rewind
    // the App Group snapshot to idle, so no ghost countdown outlived the process, and
    // cancel any end-of-timer notification the widget had scheduled. With the widget
    // removed there is no snapshot and no scheduled notification — the timer lives
    // entirely inside this process, so quitting stops it by definition and there is
    // nothing left to clean up. Quit still means stop; it just needs no code now.
    //
    // Closing the window is unaffected: the app stays resident (below) with the
    // timer running and the menu-bar countdown live.

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Reopen the main window when the dock icon is clicked and no window is visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppActivation.openMainWindow() }
        return true
    }
}
