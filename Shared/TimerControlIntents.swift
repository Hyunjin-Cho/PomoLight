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

private func scheduleFinishNotification(at deadline: Date, soundFile: String?, enabled: Bool?) {
    guard enabled ?? true else { return }
    let center = UNUserNotificationCenter.current()
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
    center.add(UNNotificationRequest(identifier: widgetFinishNotificationID,
                                     content: content, trigger: trigger))
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
            snap.deadline = now.addingTimeInterval(duration)
            snap.remaining = duration
            snap.fractionRemaining = 1
            scheduleFinishNotification(at: snap.deadline!, soundFile: snap.alarmSoundFile, enabled: snap.notificationsEnabled)
        case .running:
            let remaining = max(0, snap.deadline?.timeIntervalSince(now) ?? 0)
            cancelFinishNotification()
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
            scheduleFinishNotification(at: snap.deadline!, soundFile: snap.alarmSoundFile, enabled: snap.notificationsEnabled)
        case .finished:
            snap.phase = .idle
            snap.deadline = nil
            snap.remaining = duration
            snap.fractionRemaining = 1
            cancelFinishNotification()
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
        snap.deadline = nil
        snap.remaining = duration
        snap.fractionRemaining = 1
        snap.updatedAt = Date()
        cancelFinishNotification()
        commit(snap)
        return .result()
    }
}
