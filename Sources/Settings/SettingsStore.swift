import Foundation
import Observation
import SwiftUI

/// The gentle alarm sounds the user can choose from. All are synthesized in-app
/// (license-clean, fully tunable) — macOS system sounds are notification blips that
/// read as "button" sounds, so they're not used. Names stay English.
///
/// 2026-11-17 (#61): the owner listened to eleven new voices and kept five; these
/// replaced all four before them (Soft Chime, Marimba, Bell, Pulse — every one built
/// from the same few sine partials). The order here is the order in Settings, and
/// Marimba is the default (the owner's pick).
/// Stored choices: `marimba` kept its rawValue, so a saved Marimba stays Marimba.
/// The other three old values — `synthBell`, `bell`, `pulse` — are no longer cases,
/// so `SettingsStore` reads them as unknown and lands on the default.
enum AlarmSound: String, CaseIterable, Identifiable {
    case marimba
    case kalimba
    case handpan
    case woodBlocks
    case softSynth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .marimba:    return "Marimba"
        case .kalimba:    return "Kalimba"
        case .handpan:    return "Handpan"
        case .woodBlocks: return "Wood Blocks"
        case .softSynth:  return "Soft Synth"
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

    var lastDurationMinutes: Double { didSet { write(lastDurationMinutes, Key.lastDurationMinutes) } }
    var selectedThemeID: String { didSet { write(selectedThemeID, Key.selectedThemeID) } }
    var alarmSound: AlarmSound { didSet { write(alarmSound.rawValue, Key.alarmSound) } }
    var alarmVolume: Double { didSet { write(alarmVolume, Key.alarmVolume) } }
    var repeatUntilDismissed: Bool { didSet { write(repeatUntilDismissed, Key.repeatUntilDismissed) } }
    var showInMenuBar: Bool { didSet { write(showInMenuBar, Key.showInMenuBar) } }
    var keepAwake: Bool { didSet { write(keepAwake, Key.keepAwake) } }
    var showSeconds: Bool { didSet { write(showSeconds, Key.showSeconds) } }
    var notificationsEnabled: Bool { didSet { write(notificationsEnabled, Key.notificationsEnabled) } }

    /// 2026-08-21 (#52): every setter writes through here rather than touching
    /// `defaults` directly, so persistence has one place to be switched off.
    /// Uninstalling wants that: it deletes the preferences file, and a write that
    /// lands afterwards puts it back — which really happened, a file holding a
    /// single `pl.showInMenuBar` that SwiftUI wrote while tearing the menu-bar
    /// scene down, half a second after the domain had been removed.
    ///
    /// This switch is not what fixed it (that was the order the uninstaller stops
    /// cfprefsd in — see `Uninstaller`). It is here because a store that keeps
    /// writing after its file has been deleted is the wrong shape regardless, and
    /// because it is one line.
    private var persists = true

    private func write(_ value: Any, _ key: String) {
        guard persists else { return }
        defaults.set(value, forKey: key)
    }

    /// Stop writing. There is no way back on purpose — the only caller is the
    /// uninstaller, and the process is about to end.
    func stopPersisting() { persists = false }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.lastDurationMinutes: 30.0,
            Key.selectedThemeID: "coral",
            Key.alarmSound: AlarmSound.marimba.rawValue,
            Key.alarmVolume: 0.7,
            Key.repeatUntilDismissed: false,
            Key.showInMenuBar: true,
            Key.keepAwake: false,
            Key.showSeconds: false,
            Key.notificationsEnabled: true,
        ])
        self.lastDurationMinutes = defaults.double(forKey: Key.lastDurationMinutes)
        self.selectedThemeID = defaults.string(forKey: Key.selectedThemeID) ?? "coral"
        self.alarmSound = AlarmSound(rawValue: defaults.string(forKey: Key.alarmSound) ?? "") ?? .marimba
        self.alarmVolume = defaults.double(forKey: Key.alarmVolume)
        self.repeatUntilDismissed = defaults.bool(forKey: Key.repeatUntilDismissed)
        self.showInMenuBar = defaults.bool(forKey: Key.showInMenuBar)
        self.keepAwake = defaults.bool(forKey: Key.keepAwake)
        self.showSeconds = defaults.bool(forKey: Key.showSeconds)
        self.notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
    }
}
