import AppKit
import os
import UserNotifications
import WidgetKit

/// Minimal AppKit delegate: keeps the app resident when the window is closed (so
/// the menu-bar timer keeps running) and ends the session outright on quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "com.vismo.pomolight", category: "quit")

    /// How long quitting may block while the notification daemon confirms the
    /// pending alarm is gone. Long enough for a healthy XPC round trip, short
    /// enough that a wedged daemon can never hold the app open in the user's face.
    private static let daemonHandoffTimeout: DispatchTimeInterval = .milliseconds(700)

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        Snapshot.runIfRequested()
        #endif
        // Become the active app so the window is key and controls respond to the
        // very first click (otherwise the first click only focuses the window).
        NSApp.activate(ignoringOtherApps: true)
    }

    // 🚨 2026-08-20 (owner's decision): QUITTING STOPS THE TIMER.
    //
    // This used to do the opposite. On quit it handed the rest of the countdown to
    // the notification daemon so the alarm would still ring with the app gone. The
    // intent was kind; the result was not. That daemon rings when it next gets the
    // chance, NOT at the deadline — a Mac that reboots or sleeps through the
    // deadline delivers the alarm at the following login. Measured on this machine:
    // a timer due at 12:50:19 rang at 13:07:55, seventeen minutes late, with the
    // app closed the whole time. To the user that is not an alarm, it is a mystery
    // "ding" from an app they never launched, and there is no API to tell macOS
    // "skip it if you're late".
    //
    // So the quit path no longer schedules anything. Instead it does the two things
    // that make Cmd-Q mean what it looks like it means: rewind the shared snapshot
    // to idle, and cancel any alarm the WIDGET may have left pending.
    //
    // Note this only governs quitting. Closing the window keeps the app resident
    // (see applicationShouldTerminateAfterLastWindowClosed) with the timer running
    // and the real in-app chime intact, so nobody loses an alarm by tidying their
    // desktop — you lose it only by explicitly ending the app.
    func applicationWillTerminate(_ notification: Notification) {
        stopSharedTimerState()
        cancelBackupAlarm()
    }

    /// Rewind the shared snapshot to idle so neither the widget nor the next launch
    /// resurrects a countdown the user already ended by quitting. Without this the
    /// snapshot keeps saying "running" forever — nobody is left alive to write the
    /// finish — and `AppModel.init` adopts that ghost on the next launch.
    private func stopSharedTimerState() {
        let snap = SharedStore.read()
        guard snap.phase == .running || snap.phase == .paused else { return }
        SharedStore.write(snap.stopped())
        // `set` hands the value to cfprefsd by async XPC and this is the last moment
        // this process gets, which is the same race that used to swallow the
        // quit-time notification. Force the flush before we die.
        SharedStore.flush()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Drop any pending end-of-timer notification. The widget schedules one when it
    /// starts a countdown with the app closed; if the app was then opened and quit,
    /// that alarm is still armed and would ring after the session it belongs to has
    /// been ended.
    private func cancelBackupAlarm() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [SharedStore.backupAlarmID])
        // removePendingNotificationRequests has no completion handler and hands the
        // request over by async XPC, so it can lose the race against exit exactly
        // the way `add` used to (2026-08-15). A follow-up read on the same, ordered
        // connection only comes back once the removal ahead of it has been
        // processed — that round trip is the acknowledgement we cannot ask for
        // directly. Bounded, because an unresponsive daemon must never be able to
        // hold the quit open: a surviving alarm is bad, an app that won't quit is
        // worse.
        let handoff = DispatchSemaphore(value: 0)
        center.getPendingNotificationRequests { _ in handoff.signal() }
        if handoff.wait(timeout: .now() + Self.daemonHandoffTimeout) == .timedOut {
            Self.log.error("pending alarm removal not confirmed before quit — it may still fire")
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
