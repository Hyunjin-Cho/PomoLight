import UserNotifications
import AppKit

/// Posts a local "Time's up" notification when a timer finishes, as a backup for
/// when PomoLight is in the background or on another Space. The in-app chime +
/// window-raise is the PRIMARY alarm — notifications are best-effort and the app
/// never blocks on the permission.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    func configureDelegate() {
        center.delegate = self
    }

    /// Ask for permission the first time the user starts a timer (in context, not at
    /// launch) so the first completion can deliver a banner. No-op if already decided.
    func requestAuthorizationIfNeeded() {
        Task {
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Fire the finished notification. Requests permission in-context the first
    /// time (per the UX spec — no upfront prompt at launch).
    func notifyTimerFinished(enabled: Bool) {
        guard enabled else { return }
        Task {
            switch await center.notificationSettings().authorizationStatus {
            case .authorized, .provisional:
                post()
            case .notDetermined:
                if let granted = try? await center.requestAuthorization(options: [.alert, .sound]), granted {
                    post()
                }
            default:
                break   // denied — the in-app chime + window-raise still alert the user
            }
        }
    }

    private func post() {
        let content = UNMutableNotificationContent()
        content.title = "PomoLight"
        content.body = String(localized: "Time's up — your timer finished.")
        content.sound = nil   // we play our own gentle chime; avoid a double sound
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        center.add(request)
    }

    // Show the banner even while the app is frontmost (no sound — the chime covers it).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
