import AppKit
import UserNotifications

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

    // If the user quits mid-countdown, the widget keeps showing the timer but the
    // app can no longer play the chime — leave a backup notification at the deadline.
    func applicationWillTerminate(_ notification: Notification) {
        let snap = SharedStore.read()
        guard snap.phase == .running, let deadline = snap.deadline,
              deadline.timeIntervalSinceNow > 0,
              snap.notificationsEnabled ?? true else { return }
        let content = UNMutableNotificationContent()
        content.title = "PomoLight"
        content.body = String(localized: "Time's up — your timer finished.")
        if let file = snap.alarmSoundFile {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(file))
        } else {
            content.sound = .default
        }
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "pl.widget.finish", content: content, trigger: trigger))
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
