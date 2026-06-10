import SwiftUI
import Observation

/// Owns the active theme and resolves contrast-guaranteed `Palette`s for views.
/// Switching is live: changing `current` updates every view that reads it.
@MainActor
@Observable
final class ThemeStore {
    private let settings: SettingsStore
    private(set) var current: Theme

    init(settings: SettingsStore) {
        self.settings = settings
        self.current = ThemeStore.resolve(settings: settings)
    }

    static func resolve(settings: SettingsStore) -> Theme {
        Theme.preset(id: settings.selectedThemeID) ?? .default
    }

    var presets: [Theme] { Theme.presets }

    func selectPreset(id: String) {
        settings.selectedThemeID = id
        current = Theme.preset(id: id) ?? .default
    }

    /// The contrast-guaranteed palette for the current appearance.
    func palette(for scheme: ColorScheme) -> Palette {
        Palette(current.colors(for: scheme))
    }
}
