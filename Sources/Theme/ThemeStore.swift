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
        if settings.selectedThemeID == "custom", !settings.customAccentHex.isEmpty {
            return Theme.custom(accent: RGB(hex: settings.customAccentHex))
        }
        return Theme.preset(id: settings.selectedThemeID) ?? .default
    }

    var presets: [Theme] { Theme.presets }

    var hasCustomAccent: Bool { !settings.customAccentHex.isEmpty }

    var customAccentColor: Color {
        settings.customAccentHex.isEmpty ? Theme.default.swatch : RGB(hex: settings.customAccentHex).color
    }

    func selectPreset(id: String) {
        settings.selectedThemeID = id
        current = Theme.preset(id: id) ?? .default
    }

    func setCustomAccent(_ color: Color) {
        let rgb = color.resolvedRGB()
        settings.customAccentHex = rgb.hexString
        settings.selectedThemeID = "custom"
        current = Theme.custom(accent: rgb)
    }

    /// The contrast-guaranteed palette for the current appearance.
    func palette(for scheme: ColorScheme) -> Palette {
        Palette(current.colors(for: scheme))
    }
}

extension Color {
    /// Best-effort extraction of sRGB components from a SwiftUI Color (for the
    /// custom color picker). Falls back to the default accent on failure.
    func resolvedRGB() -> RGB {
        #if canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return RGB(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
        #else
        return RGB(hex: "#F0A07A")
        #endif
    }
}
