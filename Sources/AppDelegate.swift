import AppKit
import os
import UserNotifications

/// Minimal AppKit delegate: keeps the app resident when the window is closed (so
/// the menu-bar timer keeps running) and nothing else.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "com.vismo.pomolight", category: "quit")

    /// How long quitting may block while the notification daemon confirms the
    /// backup alarm. Long enough for a healthy XPC round trip, short enough that
    /// a wedged daemon can never hold the app open in the user's face.
    private static let backupNotificationTimeout: DispatchTimeInterval = .milliseconds(700)

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
        // 2026-08-15: wait for the daemon to acknowledge — add() hands the request
        // over by async XPC, and this is the last moment of the process. Fire-and-
        // forget raced the exit: if we died before the request reached the daemon
        // the alarm was simply lost, silently, which is exactly the "quit with a
        // timer running and nothing ever rang" report. await is not available here
        // (applicationWillTerminate is synchronous and the runloop is ending), so
        // a semaphore is the only way to hold the thread. The timeout is not
        // optional: without it an unresponsive notification daemon would hang the
        // quit forever. Missing the backup alarm is bad; an app that won't quit is
        // worse — so we bound the wait and log whichever way it goes.
        let handoff = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "pl.widget.finish", content: content, trigger: trigger)
        ) { error in
            if let error {
                Self.log.error("backup alarm rejected at quit: \(error.localizedDescription, privacy: .public)")
            }
            handoff.signal()
        }
        if handoff.wait(timeout: .now() + Self.backupNotificationTimeout) == .timedOut {
            Self.log.error("backup alarm not confirmed before quit — it may not fire")
        }
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
