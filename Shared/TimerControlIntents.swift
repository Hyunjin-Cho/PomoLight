import AppIntents
import WidgetKit
import UserNotifications
import Foundation

// Interactive-widget controls. These intents run in the WIDGET process (the app
// may not be running), so they operate purely on the shared snapshot:
//   widget button → mutate snapshot → reload widget → Darwin-ping the app.
// A running app adopts the change instantly (and owns the gentle chime); if the
// app is closed, a pre-scheduled local notification covers the alarm instead.

private let widgetFinishNotificationID = "pl.widget.finish"

/// Schedules the backup "Time's up" notification for a widget-driven timer.
/// Returns whether the user will actually be alerted when the timer ends:
/// `false` means the alarm CANNOT fire (permission missing or scheduling failed)
/// — the widget surfaces that instead of counting down toward silence. A user
/// who turned notifications off in the app gets `true`: that's their choice,
/// not a failure.
private func scheduleFinishNotification(at deadline: Date, soundFile: String?, enabled: Bool?) async -> Bool {
    guard enabled ?? true else { return true }
    let center = UNUserNotificationCenter.current()
    // Widgets can't prompt for permission — verify it was granted to the app.
    let status = await center.notificationSettings().authorizationStatus
    guard status == .authorized || status == .provisional else { return false }
    let content = UNMutableNotificationContent()
    content.title = "PomoLight"
    content.body = String(localized: "Time's up — your timer finished.")
    // Play the user's chosen chime (pre-rendered .caf in the app bundle); fall
    // back to the system sound if the file is missing.
    if let soundFile {
        content.sound = UNNotificationSound(named: UNNotificationSoundName(soundFile))
    } else {
        content.sound = .default
    }
    let interval = max(1, deadline.timeIntervalSinceNow)
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
    do {
        try await center.add(UNNotificationRequest(identifier: widgetFinishNotificationID,
                                                   content: content, trigger: trigger))
        return true
    } catch {
        return false
    }
}

private func cancelFinishNotification() {
    UNUserNotificationCenter.current()
        .removePendingNotificationRequests(withIdentifiers: [widgetFinishNotificationID])
}

private func commit(_ snapshot: TimerSnapshot) {
    SharedStore.write(snapshot)
    WidgetCenter.shared.reloadAllTimelines()
    SharedStore.postWidgetChange()
}

/// Start / pause / resume / dismiss — one state-aware primary action.
struct TimerToggleIntent: AppIntent {
    static let title: LocalizedStringResource = "Start or Pause Timer"
    static let description = IntentDescription("Starts, pauses, or resumes the PomoLight timer.")

    func perform() async throws -> some IntentResult {
        var snap = SharedStore.read()
        let now = Date()
        let duration = snap.configuredDuration > 0 ? snap.configuredDuration : 30 * 60

        switch snap.phase {
        case .idle:
            snap.phase = .running
            // Persist the fallback duration too — the progress bar's session
            // anchor and the app's adopt() both derive from configuredDuration.
            snap.configuredDuration = duration
            snap.deadline = now.addingTimeInterval(duration)
            snap.remaining = duration
            snap.fractionRemaining = 1
            snap.backupAlarmScheduled = await scheduleFinishNotification(
                at: snap.deadline!, soundFile: snap.alarmSoundFile, enabled: snap.notificationsEnabled)
        case .running:
            let remaining = max(0, snap.deadline?.timeIntervalSince(now) ?? 0)
            cancelFinishNotification()
            snap.backupAlarmScheduled = nil           // nothing pending anymore
            if remaining <= 0 {                       // it actually finished — dismiss
                snap.phase = .idle
                snap.deadline = nil
                snap.remaining = duration
                snap.fractionRemaining = 1
            } else {                                  // pause
                snap.phase = .paused
                snap.deadline = nil
                snap.remaining = remaining
                snap.fractionRemaining = duration > 0 ? remaining / duration : 0
            }
        case .paused:
            snap.phase = .running
            snap.deadline = now.addingTimeInterval(snap.remaining)
            snap.backupAlarmScheduled = await scheduleFinishNotification(
                at: snap.deadline!, soundFile: snap.alarmSoundFile, enabled: snap.notificationsEnabled)
        case .finished:
            snap.phase = .idle
            snap.deadline = nil
            snap.remaining = duration
            snap.fractionRemaining = 1
            cancelFinishNotification()
            snap.backupAlarmScheduled = nil
        }

        snap.updatedAt = now
        commit(snap)
        return .result()
    }
}

/// Back to the chosen duration, idle.
struct TimerResetIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset Timer"
    static let description = IntentDescription("Resets the PomoLight timer.")

    func perform() async throws -> some IntentResult {
        var snap = SharedStore.read()
        let duration = snap.configuredDuration > 0 ? snap.configuredDuration : 30 * 60
        snap.phase = .idle
        snap.configuredDuration = duration
        snap.deadline = nil
        snap.remaining = duration
        snap.fractionRemaining = 1
        snap.backupAlarmScheduled = nil
        snap.updatedAt = Date()
        cancelFinishNotification()
        commit(snap)
        return .result()
    }
}
