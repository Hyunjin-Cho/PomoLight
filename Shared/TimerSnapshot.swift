import Foundation
import SwiftUI

/// The App Group identifier shared by the app and the widget extension.
/// (App Groups need an Apple Developer account/provisioning for a notarized
/// release; locally with ad-hoc signing the shared container works for testing.)
enum AppGroup {
    static let id = "group.com.vismo.pomolight"
}

/// A small, Codable picture of the timer that the main app writes and the widget
/// reads. Kept intentionally tiny.
struct TimerSnapshot: Codable, Equatable {
    enum Phase: String, Codable { case idle, running, paused, finished }

    var phase: Phase
    var deadline: Date?            // set while running, for a self-ticking widget countdown
    var remaining: TimeInterval    // frozen remaining for idle/paused/finished display
    var configuredDuration: TimeInterval
    var fractionRemaining: Double  // 1 = full, 0 = empty
    var accentHex: String
    var updatedAt: Date
    /// Bundled .caf the widget's backup notification should play (optional so old
    /// stored snapshots still decode).
    var alarmSoundFile: String?
    /// Mirrors `SettingsStore.notificationsEnabled` so the widget process — which
    /// can't see the app's own UserDefaults — knows whether to skip its backup
    /// notification. Optional so old stored snapshots still decode; nil is
    /// treated as enabled (the prior, unconditional behavior).
    var notificationsEnabled: Bool?
    /// Whether a WIDGET-driven running timer managed to arrange an end-of-timer
    /// alert. `false` = it will end silently (notification permission missing or
    /// scheduling failed) — the widget shows a bell-slash badge for that. nil =
    /// not applicable (not widget-driven, or the open app owns the alarm).
    var backupAlarmScheduled: Bool? = nil

    static let placeholder = TimerSnapshot(
        phase: .idle, deadline: nil, remaining: 30 * 60,
        configuredDuration: 30 * 60, fractionRemaining: 1,
        accentHex: "#E79A86", updatedAt: Date(timeIntervalSince1970: 0),
        alarmSoundFile: "SoftChime.caf", notificationsEnabled: true)

    /// This snapshot rewound to a stopped, ready-to-start-again countdown.
    ///
    /// 2026-08-20: added for the quit path. Quitting the app ends the session, so
    /// the app has to leave "stopped" behind in the App Group — otherwise nobody
    /// is alive to write the finish, the snapshot says `running` forever, and the
    /// next launch adopts a countdown the user ended days ago. The widget's reset
    /// button means the same thing and shares this, so the two can't drift.
    ///
    /// The 30-minute floor is the same fallback the widget intents use for a
    /// snapshot with no duration in it — never zero, or the dial comes back empty.
    func stopped(at date: Date = Date()) -> TimerSnapshot {
        var s = self
        s.configuredDuration = configuredDuration > 0 ? configuredDuration : 30 * 60
        s.phase = .idle
        s.deadline = nil
        s.remaining = s.configuredDuration
        s.fractionRemaining = 1
        s.backupAlarmScheduled = nil
        s.updatedAt = date
        return s
    }

    /// "MM:SS" / "H:MM:SS" for the non-running (static) display.
    func formatted(_ t: TimeInterval) -> String {
        let total = max(0, Int(ceil(t)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%02d:%02d", m, s)
    }
}

/// Reads/writes the snapshot in the App Group's UserDefaults.
enum SharedStore {
    private static let key = "pl.snapshot"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.id) }

    /// Darwin notification posted by WIDGET intents after they mutate the snapshot,
    /// so a running app adopts the change instantly. (The app itself never posts
    /// this — that would echo back and loop.)
    static let widgetChangeNote = "com.vismo.pomolight.widgetStateChanged"

    /// Identifier of the end-of-timer notification the WIDGET schedules when it
    /// starts a countdown with the app closed. It lives here because BOTH sides
    /// touch it — the widget arms it, the app cancels it on launch, on adopting a
    /// widget change, when notifications are switched off, and at quit. Every copy
    /// of this string that drifts is an alarm nobody can turn off, so there is one.
    static let backupAlarmID = "pl.widget.finish"

    static func write(_ snapshot: TimerSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    static func read() -> TimerSnapshot {
        guard let data = defaults?.data(forKey: key),
              let snap = try? JSONDecoder().decode(TimerSnapshot.self, from: data) else {
            return .placeholder
        }
        return snap
    }

    /// Force a written snapshot out to the preferences daemon. `set` hands the
    /// value over asynchronously, which is fine everywhere except the one place it
    /// isn't: `applicationWillTerminate`, where the process has no runloop left to
    /// finish the handoff. `synchronize()` is soft-deprecated but still the only
    /// blocking flush UserDefaults offers. (2026-08-20)
    static func flush() {
        defaults?.synchronize()
    }

    static func postWidgetChange() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(widgetChangeNote as CFString),
            nil, nil, true)
    }
}

extension Color {
    /// Lightweight "#RRGGBB" parser for the widget (the app has its own RGB type).
    init(appHex hex: String) {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}
