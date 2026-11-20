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

    /// Ask for notification permission. No-op once the user has decided either way.
    ///
    /// 🚨 2026-08-21: this doc-comment (and the one on `notifyTimerFinished`) said the
    /// opposite of what the app does — "the first time the user starts a timer (in
    /// context, not at launch)" — while `AppModel.init` has called it AT LAUNCH the
    /// whole time. The code was right and the prose was wrong, which is the dangerous
    /// way round: the next reader could have deleted the launch call as a "bug" and
    /// lost the banner on the very first finish. Asking at launch is deliberate — see
    /// `AppModel.init` for why (the prompt must not land on top of the first alarm).
    func requestAuthorizationIfNeeded() {
        Task {
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Fire the finished notification. Permission is normally already settled by the
    /// launch-time request; the `.notDetermined` branch below is the safety net for
    /// the case where a timer finishes before that request has come back.
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

    /// 2026-11-20 (#70 F-9): 예전엔 알림마다 `UUID().uuidString` 을 새로 붙이고 지우지 않아서,
    /// 타이머를 끝낼 때마다 "Time's up" 이 알림 센터에 한 장씩 쌓였다(열 번 쓰면 열 장). 지난
    /// 회차의 "끝났다" 는 다음 회차가 끝나면 쓸모가 없으니, 이름을 하나로 고정해 늘 한 장만 남긴다.
    static let finishedIdentifier = "com.vismo.pomolight.timerFinished"

    private func post() {
        let content = UNMutableNotificationContent()
        content.title = "PomoLight"
        content.body = String(localized: "Time's up — your timer finished.")
        content.sound = nil   // we play our own gentle chime; avoid a double sound
        // 같은 이름으로 다시 올리면 대기 중인 것은 바뀌지만, 이미 전달된 것까지 치워지는지는
        // 문서에 없다 — 그래서 먼저 그 이름의 것만 지우고 올린다. `removeAllDelivered…` 로
        // 예전 판이 UUID 로 쌓아 둔 것까지 치울 수도 있었지만, 그러면 이름이 없는 남의 알림
        // (같은 번들 ID 의 다른 사본이 올린 것 포함)까지 지운다 — 고른 것만 지운다.
        center.removeDeliveredNotifications(withIdentifiers: [Self.finishedIdentifier])
        let request = UNNotificationRequest(identifier: Self.finishedIdentifier,
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
