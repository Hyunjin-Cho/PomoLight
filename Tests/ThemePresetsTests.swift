import XCTest
import SwiftUI

/// A record of what the 15 shipped themes ARE — written 2026-11-03, before
/// `Sources/Theme/Theme.swift` was refactored (#58).
///
/// `ContrastTests` judges the palette; this file does not. It pins the output of
/// the private `Theme.pastel(_:_:hue:)` recipe glyph for glyph — the order, every
/// id, name, mood and custom flag, and all 240 hex strings (15 themes x light/dark
/// x 8 tokens) — so a rewrite of the recipe cannot move a single colour unnoticed.
/// `pastel` is private, so these 15 calls are the whole of its input.
///
/// Every expected value was produced by the code at dcd706d and is written out as
/// a literal. Nothing here re-derives a colour: a copy of the recipe would move
/// together with the recipe and prove nothing.
///
/// The ids matter outside this file. `SettingsStore` keeps the chosen one under
/// `pl.selectedThemeID`, and `ThemeStore` turns it back into a theme through
/// `Theme.preset(id:)` — an id that stops matching silently resets that user to
/// the default theme.
final class ThemePresetsTests: XCTestCase {

    /// One shipped theme as recorded at dcd706d. `light` and `dark` follow `tokens`.
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
                 light: ["#FDE7F1", "#FEF7FA", "#F882B5", "#FBC1DA", "#5C233C", "#9C5473", "#F8CEE0", "#EF4D93"],
                 dark:  ["#2D111D", "#3D1A29", "#F471AA", "#742547", "#EFE6EA", "#C2A8B3", "#5B243C", "#F066A2"]),
        Recorded("rose", "Rose",
                 light: ["#FDE7EB", "#FEF7F8", "#F88295", "#FBC1CA", "#5C232D", "#9C5460", "#F8CED5", "#EF4D68"],
                 dark:  ["#2D1115", "#3D1A20", "#F47187", "#742532", "#EFE6E8", "#C2A8AD", "#5B242D", "#F0667D"]),
        Recorded("red", "Red",
                 light: ["#FDEAE7", "#FEF8F7", "#F89182", "#FBC8C1", "#5C2B23", "#9C5D54", "#F8D4CE", "#EF624D"],
                 dark:  ["#2D1411", "#3D1F1A", "#F48271", "#742F25", "#EFE7E6", "#C2ACA8", "#5B2C24", "#F07866"]),
        Recorded("coral", "Coral",
                 light: ["#FDEFE7", "#FEFAF7", "#F8AD82", "#FBD6C1", "#5C3823", "#9C6E54", "#F8DDCE", "#EF884D"],
                 dark:  ["#2D1B11", "#3D271A", "#F4A171", "#744225", "#EFE9E6", "#C2B2A8", "#5B3824", "#F09866"]),
        Recorded("orange", "Orange",
                 light: ["#FDF4E7", "#FEFBF7", "#F8C982", "#FBE4C1", "#5C4523", "#9C7F54", "#F8E7CE", "#EFAE4D"],
                 dark:  ["#2D2111", "#3D2F1A", "#F4C071", "#745425", "#EFEBE6", "#C2B8A8", "#5B4524", "#F0B966"]),
        Recorded("yellow", "Yellow",
                 light: ["#FCF7D9", "#FEFDF7", "#F8E882", "#FBF3C1", "#5C5523", "#9C9254", "#F8F2CE", "#EFDA4D"],
                 dark:  ["#2D2911", "#3D381A", "#F4E371", "#746A25", "#EFEEE6", "#C2BEA8", "#5B5424", "#F0DD66"]),
        Recorded("lime", "Lime",
                 light: ["#EEFCD9", "#FBFEF7", "#C9F882", "#E4FBC1", "#455C23", "#7F9C54", "#E7F8CE", "#AEEF4D"],
                 dark:  ["#212D11", "#2F3D1A", "#C0F471", "#547425", "#EBEFE6", "#B8C2A8", "#455B24", "#B9F066"]),
        Recorded("green", "Green",
                 light: ["#E7FDEA", "#F7FEF8", "#82F891", "#C1FBC8", "#235C2B", "#549C5D", "#CEF8D4", "#4DEF62"],
                 dark:  ["#112D14", "#1A3D1F", "#71F482", "#25742F", "#E6EFE7", "#A8C2AC", "#245B2C", "#66F078"]),
        Recorded("mint", "Mint",
                 light: ["#E7FDF5", "#F7FEFB", "#82F8CC", "#C1FBE6", "#235C47", "#549C81", "#CEF8E8", "#4DEFB4"],
                 dark:  ["#112D22", "#1A3D30", "#71F4C4", "#257457", "#E6EFEC", "#A8C2B8", "#245B47", "#66F0BD"]),
        Recorded("teal", "Teal",
                 light: ["#E7FCFD", "#F7FDFE", "#7EF7FC", "#C1F9FB", "#235B5C", "#54999C", "#CEF6F8", "#47EFF5"],
                 dark:  ["#112C2D", "#1A3C3D", "#6CF4F9", "#257274", "#E6EFEF", "#A8C1C2", "#24595B", "#61F0F5"]),
        Recorded("sky", "Sky",
                 light: ["#E7F5FD", "#F7FBFE", "#7ECDFC", "#C1E6FB", "#23475C", "#54819C", "#CEE8F8", "#47B5F5"],
                 dark:  ["#11222D", "#1A303D", "#6CC5F9", "#255774", "#E6ECEF", "#A8B8C2", "#24475B", "#61BFF5"]),
        Recorded("blue", "Blue",
                 light: ["#E7EDFD", "#F7F9FE", "#7E9FFC", "#C1D0FB", "#23325C", "#54679C", "#CED9F8", "#4775F5"],
                 dark:  ["#11182D", "#1A233D", "#6C92F9", "#253A74", "#E6E9EF", "#A8AFC2", "#24335B", "#6188F5"]),
        Recorded("indigo", "Indigo",
                 light: ["#ECE7FD", "#F8F7FE", "#977EFC", "#CCC1FB", "#2F235C", "#62549C", "#D6CEF8", "#6A47F5"],
                 dark:  ["#16112D", "#211A3D", "#886CF9", "#352574", "#E8E6EF", "#AEA8C2", "#2F245B", "#7E61F5"]),
        Recorded("violet", "Violet",
                 light: ["#F7E7FD", "#FCF7FE", "#D482F8", "#EAC1FB", "#4B235C", "#86549C", "#EBCEF8", "#BF4DEF"],
                 dark:  ["#24112D", "#321A3D", "#CD71F4", "#5C2574", "#ECE6EF", "#BAA8C2", "#4B245B", "#C666F0"]),
        Recorded("magenta", "Magenta",
                 light: ["#FDE7F9", "#FEF7FC", "#F882E0", "#FBC1EF", "#5C2351", "#9C548D", "#F8CEEF", "#EF4DCF"],
                 dark:  ["#2D1127", "#3D1A36", "#F471DA", "#742564", "#EFE6ED", "#C2A8BD", "#5B2450", "#F066D4"]),
    ]

    /// The picker dot (`Theme.swatch`) as SwiftUI resolves it: the bit patterns of
    /// the resolved Float red, green, blue and opacity.
    private static let swatches: [String: [UInt32]] = [
        "pink":    [0x3F78F8F9, 0x3F028283, 0x3F35B5B6, 0x3F800000],
        "rose":    [0x3F78F8F9, 0x3F028283, 0x3F159596, 0x3F800000],
        "red":     [0x3F78F8F9, 0x3F119192, 0x3F028283, 0x3F800000],
        "coral":   [0x3F78F8F9, 0x3F2DADAE, 0x3F028283, 0x3F800000],
        "orange":  [0x3F78F8F9, 0x3F49C9CA, 0x3F028283, 0x3F800000],
        "yellow":  [0x3F78F8F9, 0x3F68E8E9, 0x3F028283, 0x3F800000],
        "lime":    [0x3F49C9CA, 0x3F78F8F9, 0x3F028283, 0x3F800000],
        "green":   [0x3F028283, 0x3F78F8F9, 0x3F119192, 0x3F800000],
        "mint":    [0x3F028283, 0x3F78F8F9, 0x3F4CCCCD, 0x3F800000],
        "teal":    [0x3EFCFCFE, 0x3F77F7F9, 0x3F7CFCFD, 0x3F800000],
        "sky":     [0x3EFCFCFE, 0x3F4DCDCE, 0x3F7CFCFD, 0x3F800000],
        "blue":    [0x3EFCFCFE, 0x3F1F9FA1, 0x3F7CFCFD, 0x3F800000],
        "indigo":  [0x3F179798, 0x3EFCFCFE, 0x3F7CFCFD, 0x3F800000],
        "violet":  [0x3F54D4D5, 0x3F028283, 0x3F78F8F9, 0x3F800000],
        "magenta": [0x3F78F8F9, 0x3F028283, 0x3F60E0E1, 0x3F800000],
    ]

    // MARK: - The list itself

    func testThereAreExactlyFifteenPresetsInThisOrder() {
        XCTAssertEqual(Theme.presets.map(\.id),
                       ["pink", "rose", "red", "coral", "orange", "yellow", "lime", "green",
                        "mint", "teal", "sky", "blue", "indigo", "violet", "magenta"])
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
