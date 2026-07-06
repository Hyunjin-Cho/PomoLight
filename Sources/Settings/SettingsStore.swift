import Foundation
import Observation
import SwiftUI

/// The gentle alarm sounds the user can choose from. All are synthesized in-app
/// (license-clean, fully tunable) — macOS system sounds are notification blips that
/// read as "button" sounds, so they're not used. Names stay English.
enum AlarmSound: String, CaseIterable, Identifiable {
    case synthBell      // rawValue kept for back-compat with stored prefs
    case marimba
    case bell
    case pulse

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .synthBell: return "Soft Chime"
        case .marimba:   return "Marimba"
        case .bell:      return "Bell"
        case .pulse:     return "Pulse"
        }
    }

    /// Pre-rendered .caf in the app bundle (Resources/NotificationSounds) so local
    /// notifications can play this voice when the app isn't running.
    var notificationSoundFile: String {
        switch self {
        case .synthBell: return "SoftChime.caf"
        case .marimba:   return "Marimba.caf"
        case .bell:      return "Bell.caf"
        case .pulse:     return "Pulse.caf"
        }
    }
}

/// Centralized, typed access to all persisted preferences. `@Observable` so views
/// update live; each setter writes through to UserDefaults immediately.
/// One way to support PomoLight. The heart button shows these as a small menu
/// (Stats-style) so Korean and international users each get a convenient option.
struct DonationLink: Identifiable {
    let id: String
    let title: String      // proper noun — shown as-is, not localized
    let urlString: String
}

@MainActor
@Observable
final class SettingsStore {
    /// Replace the URLs with the real accounts before release.
    static let donationLinks: [DonationLink] = [
        DonationLink(id: "toss", title: "Toss", urlString: "https://toss.me/pomolight"),
        DonationLink(id: "bmc", title: "Buy Me a Coffee", urlString: "https://www.buymeacoffee.com/pomolight"),
    ]

    private let defaults: UserDefaults

    private enum Key {
        static let lastDurationMinutes = "pl.lastDurationMinutes"
        static let selectedThemeID = "pl.selectedThemeID"
        static let alarmSound = "pl.alarmSound"
        static let alarmVolume = "pl.alarmVolume"
        static let repeatUntilDismissed = "pl.repeatUntilDismissed"
        static let showInMenuBar = "pl.showInMenuBar"
        static let keepAwake = "pl.keepAwake"
        static let showSeconds = "pl.showSeconds"
        static let notificationsEnabled = "pl.notificationsEnabled"
    }

    var lastDurationMinutes: Double { didSet { defaults.set(lastDurationMinutes, forKey: Key.lastDurationMinutes) } }
    var selectedThemeID: String { didSet { defaults.set(selectedThemeID, forKey: Key.selectedThemeID) } }
    var alarmSound: AlarmSound { didSet { defaults.set(alarmSound.rawValue, forKey: Key.alarmSound) } }
    var alarmVolume: Double { didSet { defaults.set(alarmVolume, forKey: Key.alarmVolume) } }
    var repeatUntilDismissed: Bool { didSet { defaults.set(repeatUntilDismissed, forKey: Key.repeatUntilDismissed) } }
    var showInMenuBar: Bool { didSet { defaults.set(showInMenuBar, forKey: Key.showInMenuBar) } }
    var keepAwake: Bool { didSet { defaults.set(keepAwake, forKey: Key.keepAwake) } }
    var showSeconds: Bool { didSet { defaults.set(showSeconds, forKey: Key.showSeconds) } }
    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.lastDurationMinutes: 30.0,
            Key.selectedThemeID: "coral",
            Key.alarmSound: AlarmSound.synthBell.rawValue,
            Key.alarmVolume: 0.7,
            Key.repeatUntilDismissed: false,
            Key.showInMenuBar: true,
            Key.keepAwake: false,
            Key.showSeconds: false,
            Key.notificationsEnabled: true,
        ])
        self.lastDurationMinutes = defaults.double(forKey: Key.lastDurationMinutes)
        self.selectedThemeID = defaults.string(forKey: Key.selectedThemeID) ?? "coral"
        self.alarmSound = AlarmSound(rawValue: defaults.string(forKey: Key.alarmSound) ?? "") ?? .synthBell
        self.alarmVolume = defaults.double(forKey: Key.alarmVolume)
        self.repeatUntilDismissed = defaults.bool(forKey: Key.repeatUntilDismissed)
        self.showInMenuBar = defaults.bool(forKey: Key.showInMenuBar)
        self.keepAwake = defaults.bool(forKey: Key.keepAwake)
        self.showSeconds = defaults.bool(forKey: Key.showSeconds)
        self.notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
    }
}
