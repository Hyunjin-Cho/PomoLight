import Foundation
import Observation
import SwiftUI

/// The gentle alarm sounds the user can choose from. The default is our own
/// synthesized soft bell; the rest map to the calm entries in
/// /System/Library/Sounds (jarring ones like Basso/Funk are deliberately omitted).
enum AlarmSound: String, CaseIterable, Identifiable {
    case synthBell
    case glass
    case submarine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .synthBell: return "Soft Chime"
        case .glass:     return "Glass"
        case .submarine: return "Submarine"
        }
    }

    /// Localized label for the UI (the system-sound names stay as proper nouns).
    var displayNameKey: LocalizedStringKey {
        switch self {
        case .synthBell: return "Soft Chime"
        case .glass:     return "Glass"
        case .submarine: return "Submarine"
        }
    }

    /// The matching NSSound name for system sounds (nil for the synthesized chime).
    var systemSoundName: String? {
        switch self {
        case .synthBell: return nil
        case .glass:     return "Glass"
        case .submarine: return "Submarine"
        }
    }
}

/// Centralized, typed access to all persisted preferences. `@Observable` so views
/// update live; each setter writes through to UserDefaults immediately.
@MainActor
@Observable
final class SettingsStore {
    /// The Donate link. Replace with your real Gumroad / Ko-fi / Buy-Me-a-Coffee URL.
    static let donateURLString = "https://www.buymeacoffee.com/pomolight"

    private let defaults: UserDefaults

    private enum Key {
        static let lastDurationMinutes = "pl.lastDurationMinutes"
        static let selectedThemeID = "pl.selectedThemeID"
        static let customAccentHex = "pl.customAccentHex"
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
    var customAccentHex: String { didSet { defaults.set(customAccentHex, forKey: Key.customAccentHex) } }
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
            Key.customAccentHex: "",
            Key.alarmSound: AlarmSound.synthBell.rawValue,
            Key.alarmVolume: 0.7,
            Key.repeatUntilDismissed: false,
            Key.showInMenuBar: true,
            Key.keepAwake: false,
            Key.showSeconds: false,
            Key.notificationsEnabled: true,
        ])
        self.lastDurationMinutes = defaults.double(forKey: Key.lastDurationMinutes)
        self.selectedThemeID = defaults.string(forKey: Key.selectedThemeID) ?? "peach"
        self.customAccentHex = defaults.string(forKey: Key.customAccentHex) ?? ""
        self.alarmSound = AlarmSound(rawValue: defaults.string(forKey: Key.alarmSound) ?? "") ?? .synthBell
        self.alarmVolume = defaults.double(forKey: Key.alarmVolume)
        self.repeatUntilDismissed = defaults.bool(forKey: Key.repeatUntilDismissed)
        self.showInMenuBar = defaults.bool(forKey: Key.showInMenuBar)
        self.keepAwake = defaults.bool(forKey: Key.keepAwake)
        self.showSeconds = defaults.bool(forKey: Key.showSeconds)
        self.notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
    }
}
