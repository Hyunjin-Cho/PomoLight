import XCTest
import SwiftUI

/// A record of what the shipped themes ARE — written 2026-11-03, before
/// `Sources/Theme/Theme.swift` was refactored (#58).
///
/// 2026-11-19 (#66): re-recorded for the eight OKLCH pastels that replaced the 15
/// candy themes. The literals below were printed by the #66 code, and that code's
/// output was first checked byte for byte (128 of 128 hex strings) against the
/// candidate renderer the owner chose the themes from.
///
/// `ContrastTests` judges the palette; this file does not. It pins the output of
/// the private `Theme.pastel(_:_:hue:)` recipe glyph for glyph — the order, every
/// id, name, mood and custom flag, and every hex string (themes x light/dark x 8
/// tokens) — so a rewrite of the recipe cannot move a single colour unnoticed.
/// `pastel` is private, so the calls in `Theme.presets` are the whole of its input.
///
/// Every expected value was produced by the code (dcd706d, then #66 — above) and is
/// written out as a literal. Nothing here re-derives a colour: a copy of the recipe would move
/// together with the recipe and prove nothing.
///
/// The ids matter outside this file. `SettingsStore` keeps the chosen one under
/// `pl.selectedThemeID`, and `ThemeStore` turns it back into a theme through
/// `Theme.preset(id:)` — an id that stops matching silently resets that user to
/// the default theme.
final class ThemePresetsTests: XCTestCase {

    /// One shipped theme as recorded. `light` and `dark` follow `tokens`.
    private struct Recorded {
        let id: String
        let name: String
        let light: [String]
        let dark: [String]

        init(_ id: String, _ name: String, light: [String], dark: [String]) {
            self.id = id
            self.name = name
            self.light = light
            self.dark = dark
        }
    }

    /// The order of the eight hex strings in every `light` / `dark` row below.
    private static let tokens: [(name: String, value: KeyPath<ThemeColors, String>)] = [
        ("bg", \.bg), ("surface", \.surface), ("accent", \.accent), ("accentSoft", \.accentSoft),
        ("text", \.text), ("textSecondary", \.textSecondary),
        ("ringTrack", \.ringTrack), ("ringFill", \.ringFill),
    ]

    private static let recorded: [Recorded] = [
        Recorded("pink", "Pink",
                 light: ["#FFEFF3", "#FFFAFC", "#FFBBCF", "#FFDBE5", "#462932", "#775A62", "#FFD9E3", "#BD5B7D"],
                 dark:  ["#201418", "#2C1E22", "#F5ACC2", "#4F343C", "#F3E8EB", "#BCADB0", "#402D32", "#EFA6BB"]),
        Recorded("coral", "Coral",
                 light: ["#FFF0EA", "#FFFBF9", "#FFC0A8", "#FFDED2", "#462B20", "#785C51", "#FFDCCF", "#BF623D"],
                 dark:  ["#201511", "#2C1F1B", "#F7B196", "#4F362C", "#F3E9E5", "#BCAEA8", "#402E27", "#F0AB90"]),
        Recorded("yellow", "Yellow",
                 light: ["#F8F4E3", "#FDFCF6", "#FAE8A2", "#FAF0CB", "#3A3316", "#6A6349", "#EEE5C3", "#977E00"],
                 dark:  ["#1B180E", "#262317", "#EDDB96", "#443D24", "#EDEBE2", "#B4B1A5", "#383321", "#E7D48F"]),
        Recorded("green", "Green",
                 light: ["#ECF7E9", "#F9FDF8", "#B4E0A6", "#D7EFCF", "#273822", "#586953", "#D6ECCF", "#579241"],
                 dark:  ["#141B12", "#1E251B", "#A8D299", "#33422E", "#E7EDE5", "#ACB4A9", "#2B3728", "#A1CC93"]),
        Recorded("mint", "Mint",
                 light: ["#E6F9F2", "#F7FEFB", "#91E5CA", "#C6F2E2", "#173A30", "#4C6B61", "#C7EFE1", "#009678"],
                 dark:  ["#0F1B17", "#182622", "#84D7BD", "#26443B", "#E4EEEA", "#A6B5B0", "#233831", "#7ED1B7"]),
        Recorded("sky", "Sky",
                 light: ["#E7F6FF", "#F8FDFF", "#98DBFF", "#CAECFF", "#183746", "#4C6876", "#C8EBFE", "#008CBC"],
                 dark:  ["#0F1A20", "#18252C", "#86CFF5", "#27414F", "#E4EDF2", "#A6B3BB", "#233640", "#80C8EE"]),
        Recorded("blue", "Blue",
                 light: ["#EFF3FF", "#FBFCFF", "#C1CFFF", "#DEE5FF", "#2B314A", "#5B627B", "#DBE4FF", "#6679CD"],
                 dark:  ["#151822", "#1F222E", "#AFC1FF", "#363C52", "#E8EBF3", "#ADB1BD", "#2D3242", "#A9BBF8"]),
        Recorded("violet", "Violet",
                 light: ["#F7F0FF", "#FDFBFF", "#DFC3FF", "#EEDFFF", "#382D45", "#695E76", "#ECDDFD", "#946ABD"],
                 dark:  ["#1B1620", "#25202B", "#D2B5F3", "#42384E", "#EDE9F2", "#B4AEBA", "#372F3F", "#CCAFEC"]),
    ]

    /// The picker dot (`Theme.swatch`) as SwiftUI resolves it: the bit patterns of
    /// the resolved Float red, green, blue and opacity.
    private static let swatches: [String: [UInt32]] = [
        "pink":   [0x3F800000, 0x3F3BBBBD, 0x3F4FCFD0, 0x3F800000],
        "coral":  [0x3F800000, 0x3F40C0C1, 0x3F28A8A9, 0x3F800000],
        "yellow": [0x3F7AFAFB, 0x3F68E8E9, 0x3F22A2A3, 0x3F800000],
        "green":  [0x3F34B4B5, 0x3F60E0E1, 0x3F26A6A7, 0x3F800000],
        "mint":   [0x3F119192, 0x3F65E5E6, 0x3F4ACACB, 0x3F800000],
        "sky":    [0x3F189899, 0x3F5BDBDC, 0x3F800000, 0x3F800000],
        "blue":   [0x3F41C1C2, 0x3F4FCFD0, 0x3F800000, 0x3F800000],
        "violet": [0x3F5FDFE0, 0x3F43C3C4, 0x3F800000, 0x3F800000],
    ]

    // MARK: - The list itself

    func testThereAreExactlyEightPresetsInThisOrder() {
        XCTAssertEqual(Theme.presets.map(\.id),
                       ["pink", "coral", "yellow", "green", "mint", "sky", "blue", "violet"])
    }

    /// 2026-11-19 (#66): seven themes went. Anyone who had picked one still has its
    /// id under `pl.selectedThemeID`; `ThemeStore` has to land them on the default
    /// theme. The eight that stayed kept their ids, so those choices survive as-is.
    @MainActor
    func testAStoredIdOfARemovedThemeFallsBackToTheDefault() {
        let suite = "pl.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for gone in ["rose", "red", "orange", "lime", "teal", "indigo", "magenta"] {
            XCTAssertNil(Theme.preset(id: gone), "\(gone) is still a preset")
            defaults.set(gone, forKey: "pl.selectedThemeID")
            XCTAssertEqual(ThemeStore.resolve(settings: SettingsStore(defaults: defaults)).id, "coral", gone)
        }
        for kept in Theme.presets.map(\.id) {
            defaults.set(kept, forKey: "pl.selectedThemeID")
            XCTAssertEqual(ThemeStore.resolve(settings: SettingsStore(defaults: defaults)).id, kept)
        }
    }

    /// 2026-11-03: `mood` is "" and `isCustom` is false on every shipped theme —
    /// nothing in the app sets either. Recorded as found.
    func testNamesMoodsAndCustomFlagsAreRecorded() {
        XCTAssertEqual(Theme.presets.count, Self.recorded.count)
        for (theme, want) in zip(Theme.presets, Self.recorded) {
            XCTAssertEqual(theme.id, want.id)
            XCTAssertEqual(theme.name, want.name, "\(want.id) name")
            XCTAssertEqual(theme.mood, "", "\(want.id) mood")
            XCTAssertFalse(theme.isCustom, "\(want.id) isCustom")
        }
    }

    // MARK: - Every colour, hex for hex

    func testLightColorsOfEveryPresetAreRecordedHexForHex() {
        assertColors(\.light, \.light, appearance: "light")
    }

    func testDarkColorsOfEveryPresetAreRecordedHexForHex() {
        assertColors(\.dark, \.dark, appearance: "dark")
    }

    // MARK: - The rest of Theme's surface

    /// `ThemeStore` resolves the stored `pl.selectedThemeID` through this lookup.
    /// It is an exact, case-sensitive match — no trimming, no case folding.
    func testPresetLookupFindsEveryRecordedIDAndNothingElse() {
        for want in Self.recorded {
            let found = Theme.preset(id: want.id)
            XCTAssertEqual(found?.id, want.id, "preset(id: \(want.id.debugDescription))")
            XCTAssertEqual(found?.name, want.name, "preset(id: \(want.id.debugDescription))")
        }
        for miss in ["", "Coral", "CORAL", " coral", "coral ", "grey", "custom", "pastel"] {
            XCTAssertNil(Theme.preset(id: miss), "\(miss.debugDescription) should match nothing")
        }
    }

    func testTheDefaultThemeIsCoral() {
        XCTAssertEqual(Theme.default.id, "coral")
        XCTAssertEqual(Theme.default.name, "Coral")
        XCTAssertEqual(Theme.default, Theme.preset(id: "coral"))
    }

    func testColorsForSchemePicksTheMatchingSet() {
        for theme in Theme.presets {
            XCTAssertNotEqual(theme.light, theme.dark, "\(theme.id): the two sets must differ for this to mean anything")
            XCTAssertEqual(theme.colors(for: .light), theme.light, "\(theme.id) light")
            XCTAssertEqual(theme.colors(for: .dark), theme.dark, "\(theme.id) dark")
        }
    }

    func testSwatchOfEveryPresetIsRecorded() {
        let environment = EnvironmentValues()
        XCTAssertEqual(Set(Self.swatches.keys), Set(Theme.presets.map(\.id)))
        for theme in Theme.presets {
            guard let want = Self.swatches[theme.id] else {
                XCTFail("\(theme.id): no recorded swatch")
                continue
            }
            let got = theme.swatch.resolve(in: environment)
            let gotBits = [got.red, got.green, got.blue, got.opacity].map(\.bitPattern)
            XCTAssertEqual(gotBits, want, "\(theme.id) swatch resolved to \(got)")
        }
    }

    // MARK: - Helper

    private func assertColors(_ actual: KeyPath<Theme, ThemeColors>,
                              _ expected: KeyPath<Recorded, [String]>,
                              appearance: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Theme.presets.count, Self.recorded.count, file: file, line: line)
        for (theme, want) in zip(Theme.presets, Self.recorded) {
            XCTAssertEqual(theme.id, want.id, file: file, line: line)
            let colors = theme[keyPath: actual]
            let hexes = want[keyPath: expected]
            XCTAssertEqual(hexes.count, Self.tokens.count, "\(want.id) \(appearance): table row", file: file, line: line)
            for (token, hex) in zip(Self.tokens, hexes) {
                XCTAssertEqual(colors[keyPath: token.value], hex,
                               "\(want.id) \(appearance) \(token.name)", file: file, line: line)
            }
        }
    }
}
