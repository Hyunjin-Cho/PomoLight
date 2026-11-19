import XCTest
import SwiftUI

/// A record of what `ResolvedPalette.init(_:)` returns — written 2026-11-03, before
/// `Sources/Theme/Theme.swift` was refactored (#58).
///
/// `ContrastTests` checks that each role clears its tier; that leaves plenty of
/// room for a refactor to hand back a DIFFERENT colour that also clears it. This
/// file closes that room: every one of the 14 RGB roles is pinned to the exact
/// Double it holds today (`bitPattern`, three channels each), for
///
///   - the shipped palettes (`Theme.presets` x light/dark — 16 since #66), and
///   - hand-made `ThemeColors` the shipped themes never produce — `init` is
///     internal and takes any eight strings.
///
/// Every expected value was produced by the code at dcd706d and is written out as
/// a literal. Nothing here re-runs the contrast math: a copy of the derivation
/// would move together with the derivation and prove nothing.
///
/// Why the synthetic cases are not optional (measured 2026-11-03 at dcd706d):
/// the AAA ink is corrected against `bg` first and `surface` second. Reversing
/// that order changes timerText/primaryText on 0 of the 30 shipped palettes — the
/// shipped themes cannot see that mistake at all. It changes them on 7 of the 23
/// hand-picked cases below and on 110 of the 121 grid cells (every off-diagonal
/// pair). The 4.5:1 chain behind secondaryText/controlIcon is order-sensitive on
/// 8 of the 30 shipped palettes, 9 of the 23 hand-picked cases and 94 grid cells.
/// (Those shipped counts are for the 15 candy themes; the 2026-11-19 pastels (#66)
/// were not re-measured for order sensitivity — the synthetic cases still are.)
///
/// 2026-11-19 (#66): the two shipped tables were re-recorded from the #66 code when
/// the 15 themes became eight OKLCH pastels. The synthetic tables are untouched.
final class ResolvedPaletteTests: XCTestCase {

    /// Every role, in declaration order. Each table below must name all of them.
    private static let roles: [(name: String, value: KeyPath<ResolvedPalette, RGB>)] = [
        ("bg", \.bg), ("bgDeep", \.bgDeep), ("surface", \.surface), ("accent", \.accent),
        ("accentSoft", \.accentSoft), ("ringTrack", \.ringTrack), ("buttonFill", \.buttonFill),
        ("ringFill", \.ringFill), ("timerText", \.timerText), ("primaryText", \.primaryText),
        ("secondaryText", \.secondaryText), ("controlIcon", \.controlIcon),
        ("buttonLabel", \.buttonLabel), ("onAccentSoft", \.onAccentSoft),
    ]

    /// role -> [r, g, b] bit patterns
    private typealias Record = [String: [UInt64]]

    private struct Shipped {
        let id: String
        let roles: Record
        init(_ id: String, _ roles: Record) {
            self.id = id
            self.roles = roles
        }
    }

    private struct Synthetic {
        let label: String
        let colors: ThemeColors
        let roles: Record
        init(_ label: String, _ colors: ThemeColors, _ roles: Record) {
            self.label = label
            self.colors = colors
            self.roles = roles
        }
    }

    // MARK: - Shipped palettes

    func testShippedLightPalettesAreRecordedBitForBit() {
        assertShipped(Self.shippedLight, \.light, appearance: "light")
    }

    func testShippedDarkPalettesAreRecordedBitForBit() {
        assertShipped(Self.shippedDark, \.dark, appearance: "dark")
    }

    // MARK: - Synthetic palettes

    /// A light `bg` under a dark `surface` and the reverse — no single ink can clear
    /// 7:1 against both, so the order of the two corrections decides the result.
    ///
    /// 2026-11-03, recorded as found: the struct promises ">= 7:1 vs bg AND surface",
    /// but on these inputs the ink only clears it against `surface`, the backdrop
    /// corrected last ("light bg, dark surface": 1.86:1 vs bg, 7.19:1 vs surface).
    /// No shipped theme has a mixed pair, so nothing on screen shows it today.
    func testMixedBackdropsAreRecordedBitForBit() {
        assertSynthetic(Self.mixed)
    }

    /// Mid-luminance backdrops where 7:1 cannot be reached at all, including the
    /// two greys either side of the black/white tie (L ≈ 0.1791): #757575 is
    /// pushed toward white, #767676 toward black.
    ///
    /// 2026-11-03, recorded as found: when `bg` and `surface` both make 7:1
    /// unreachable, the 98% fallback runs twice — the ink ends ~99.96% of the way
    /// to the extreme (#808080: 0.000200784…), not ~98% as `enforcingContrast`'s
    /// comment describes for a single call.
    func testUnreachableTargetsAreRecordedBitForBit() {
        assertSynthetic(Self.unreachable)
    }

    /// Inks that already clear their tier come back untouched, and inks a hair
    /// under it are moved. #595959 on white is 7.005:1 (kept), #5A5A5A 6.897:1
    /// (moved); #767676 is 4.54:1 (kept), #777777 4.48:1 (moved).
    func testInkThatAlreadyPassesIsRecordedBitForBit() {
        assertSynthetic(Self.passing)
    }

    /// How the eight strings are read: junk and empty strings fall back to grey
    /// 0.5, 3-digit hex expands, "#" is optional, case and surrounding whitespace
    /// do not matter.
    ///
    /// 2026-11-03, recorded as found (the parser is `RGB(hex:)`): a 6-character
    /// string with a sign is accepted — "+8C746" reads as #08C746 and "-00000" as
    /// black — while "#+F6" expands to "++FF66" first and falls back to grey.
    func testHexSpellingsAreRecordedBitForBit() {
        assertSynthetic(Self.spelling)
    }

    /// Every pair of 11 grey levels as bg x surface, with the other six tokens
    /// fixed. Each cell pins all 14 roles: the ink and secondary per cell, the grey
    /// fills per level, and the six roles the backdrops do not touch.
    func testGreyBackdropGridIsRecordedCellByCell() {
        XCTAssertEqual(Self.gridCells.count, 121)
        XCTAssertEqual(Set(Self.gridCells.map { "\($0.bg)/\($0.surface)" }).count, 121,
                       "every bg x surface pair exactly once")
        for cell in Self.gridCells {
            let label = "grid bg \(cell.bg) / surface \(cell.surface)"
            guard let bg = Self.gridLevels[cell.bg], let surface = Self.gridLevels[cell.surface] else {
                XCTFail("\(label): level missing from gridLevels")
                continue
            }
            var expected = Self.gridFixedRoles
            expected["bg"] = [bg[0], bg[0], bg[0]]
            expected["bgDeep"] = [bg[1], bg[1], bg[1]]
            expected["surface"] = [surface[0], surface[0], surface[0]]
            expected["timerText"] = cell.ink
            expected["primaryText"] = cell.ink
            expected["secondaryText"] = cell.secondary
            expected["controlIcon"] = cell.secondary
            let colors = ThemeColors(bg: cell.bg, surface: cell.surface,
                                     accent: "#F5A97F", accentSoft: "#FBD3BE",
                                     text: "#7A5C9E", textSecondary: "#9E8A5C",
                                     ringTrack: "#F9DCCB", ringFill: "#F08A5D")
            assertRecorded(ResolvedPalette(colors), expected, label)
        }
    }

    // MARK: - Palette

    /// `Palette` is the same 14 roles as SwiftUI colours. Pinned as a mapping onto
    /// the records above: each `Palette` role must resolve to exactly the colour of
    /// the same-named `ResolvedPalette` role, on every shipped and synthetic input.
    func testPaletteCarriesEveryRoleUnderTheSameName() {
        let environment = EnvironmentValues()
        let pairs: [(String, KeyPath<Palette, Color>, KeyPath<ResolvedPalette, RGB>)] = [
            ("bg", \.bg, \.bg), ("bgDeep", \.bgDeep, \.bgDeep), ("surface", \.surface, \.surface),
            ("accent", \.accent, \.accent), ("accentSoft", \.accentSoft, \.accentSoft),
            ("ringTrack", \.ringTrack, \.ringTrack), ("ringFill", \.ringFill, \.ringFill),
            ("timerText", \.timerText, \.timerText), ("primaryText", \.primaryText, \.primaryText),
            ("secondaryText", \.secondaryText, \.secondaryText),
            ("controlIcon", \.controlIcon, \.controlIcon), ("buttonFill", \.buttonFill, \.buttonFill),
            ("buttonLabel", \.buttonLabel, \.buttonLabel), ("onAccentSoft", \.onAccentSoft, \.onAccentSoft),
        ]
        XCTAssertEqual(pairs.count, Self.roles.count)
        let inputs: [(String, ThemeColors)] =
            Theme.presets.flatMap { [("\($0.id) light", $0.light), ("\($0.id) dark", $0.dark)] }
            + (Self.mixed + Self.unreachable + Self.passing + Self.spelling).map { ($0.label, $0.colors) }
        XCTAssertEqual(inputs.count, 39)   // 8 themes x 2 + 23 synthetic (53 before #66)
        for (label, colors) in inputs {
            let palette = Palette(colors)
            let resolved = ResolvedPalette(colors)
            for (name, color, rgb) in pairs {
                XCTAssertEqual(palette[keyPath: color].resolve(in: environment),
                               resolved[keyPath: rgb].color.resolve(in: environment),
                               "\(label) · Palette.\(name)")
            }
        }
    }

    // MARK: - Helpers

    private func assertShipped(_ table: [Shipped], _ appearance: KeyPath<Theme, ThemeColors>,
                               appearance name: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(table.map(\.id), Theme.presets.map(\.id), "\(name) table order", file: file, line: line)
        for (theme, want) in zip(Theme.presets, table) {
            assertRecorded(ResolvedPalette(theme[keyPath: appearance]), want.roles,
                           "\(theme.id) \(name)", file: file, line: line)
        }
    }

    private func assertSynthetic(_ table: [Synthetic],
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(table.isEmpty, file: file, line: line)
        for want in table {
            assertRecorded(ResolvedPalette(want.colors), want.roles, want.label, file: file, line: line)
        }
    }

    private func assertRecorded(_ palette: ResolvedPalette, _ expected: Record, _ label: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(expected.keys), Set(Self.roles.map(\.name)),
                       "\(label): the record must name every role", file: file, line: line)
        for role in Self.roles {
            guard let want = expected[role.name], want.count == 3 else {
                XCTFail("\(label) · \(role.name): no [r, g, b] record", file: file, line: line)
                continue
            }
            let got = palette[keyPath: role.value]
            for (channel, value, bits) in [("r", got.r, want[0]), ("g", got.g, want[1]), ("b", got.b, want[2])] {
                XCTAssertEqual(value.bitPattern, bits,
                               "\(label) · \(role.name).\(channel): got \(value) " +
                               "(\(Self.hex(value.bitPattern))), recorded \(Double(bitPattern: bits)) " +
                               "(\(Self.hex(bits)))",
                               file: file, line: line)
            }
        }
    }

    private static func hex(_ bits: UInt64) -> String {
        let digits = String(bits, radix: 16, uppercase: true)
        return "0x" + String(repeating: "0", count: 16 - digits.count) + digits
    }

    // MARK: - Records (shipped: #66, 2026-11-19 · synthetic: dcd706d)

    private static let shippedLight: [Shipped] = [
        Shipped("pink", [
            "bg":            [0x3FF0000000000000, 0x3FEDFDFDFDFDFDFE, 0x3FEE7E7E7E7E7E7E],
            "bgDeep":        [0x3FEEE147AE147AE1, 0x3FECF1432EB3D28B, 0x3FED6D444E8BFCA0],
            "surface":       [0x3FF0000000000000, 0x3FEF5F5F5F5F5F5F, 0x3FEF9F9F9F9F9FA0],
            "accent":        [0x3FF0000000000000, 0x3FE7777777777777, 0x3FE9F9F9F9F9F9FA],
            "accentSoft":    [0x3FF0000000000000, 0x3FEB7B7B7B7B7B7B, 0x3FECBCBCBCBCBCBD],
            "ringTrack":     [0x3FF0000000000000, 0x3FEB3B3B3B3B3B3B, 0x3FEC7C7C7C7C7C7C],
            "buttonFill":    [0x3FF0000000000000, 0x3FE7777777777777, 0x3FE9F9F9F9F9F9FA],
            "ringFill":      [0x3FE7B7B7B7B7B7B8, 0x3FD6D6D6D6D6D6D7, 0x3FDF5F5F5F5F5F5F],
            "timerText":     [0x3FD1919191919192, 0x3FC4949494949495, 0x3FC9191919191919],
            "primaryText":   [0x3FD1919191919192, 0x3FC4949494949495, 0x3FC9191919191919],
            "secondaryText": [0x3FDDDDDDDDDDDDDE, 0x3FD6969696969697, 0x3FD8989898989899],
            "controlIcon":   [0x3FDDDDDDDDDDDDDE, 0x3FD6969696969697, 0x3FD8989898989899],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FD1919191919192, 0x3FC4949494949495, 0x3FC9191919191919],
        ]),
        Shipped("coral", [
            "bg":            [0x3FF0000000000000, 0x3FEE1E1E1E1E1E1E, 0x3FED5D5D5D5D5D5D],
            "bgDeep":        [0x3FEEE147AE147AE1, 0x3FED104376A9DD10, 0x3FEC5641C6E59DEF],
            "surface":       [0x3FF0000000000000, 0x3FEF7F7F7F7F7F7F, 0x3FEF3F3F3F3F3F3F],
            "accent":        [0x3FF0000000000000, 0x3FE8181818181818, 0x3FE5151515151515],
            "accentSoft":    [0x3FF0000000000000, 0x3FEBDBDBDBDBDBDC, 0x3FEA5A5A5A5A5A5A],
            "ringTrack":     [0x3FF0000000000000, 0x3FEB9B9B9B9B9B9C, 0x3FE9F9F9F9F9F9FA],
            "buttonFill":    [0x3FF0000000000000, 0x3FE8181818181818, 0x3FE5151515151515],
            "ringFill":      [0x3FE7F7F7F7F7F7F8, 0x3FD8989898989899, 0x3FCE9E9E9E9E9E9F],
            "timerText":     [0x3FD1919191919192, 0x3FC5959595959596, 0x3FC0101010101010],
            "primaryText":   [0x3FD1919191919192, 0x3FC5959595959596, 0x3FC0101010101010],
            "secondaryText": [0x3FDE1E1E1E1E1E1E, 0x3FD7171717171717, 0x3FD4545454545454],
            "controlIcon":   [0x3FDE1E1E1E1E1E1E, 0x3FD7171717171717, 0x3FD4545454545454],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FD1919191919192, 0x3FC5959595959596, 0x3FC0101010101010],
        ]),
        Shipped("yellow", [
            "bg":            [0x3FEF1F1F1F1F1F1F, 0x3FEE9E9E9E9E9E9F, 0x3FEC7C7C7C7C7C7C],
            "bgDeep":        [0x3FEE0845B65A313B, 0x3FED8C4496820726, 0x3FEB7D3FCF2B5449],
            "surface":       [0x3FEFBFBFBFBFBFC0, 0x3FEF9F9F9F9F9FA0, 0x3FEEDEDEDEDEDEDF],
            "accent":        [0x3FEF5F5F5F5F5F5F, 0x3FED1D1D1D1D1D1D, 0x3FE4545454545454],
            "accentSoft":    [0x3FEF5F5F5F5F5F5F, 0x3FEE1E1E1E1E1E1E, 0x3FE9797979797979],
            "ringTrack":     [0x3FEDDDDDDDDDDDDE, 0x3FECBCBCBCBCBCBD, 0x3FE8787878787878],
            "buttonFill":    [0x3FEF5F5F5F5F5F5F, 0x3FED1D1D1D1D1D1D, 0x3FE4545454545454],
            "ringFill":      [0x3FE2F2F2F2F2F2F3, 0x3FDF9F9F9F9F9FA0, 0x0000000000000000],
            "timerText":     [0x3FCD1D1D1D1D1D1D, 0x3FC999999999999A, 0x3FB6161616161616],
            "primaryText":   [0x3FCD1D1D1D1D1D1D, 0x3FC999999999999A, 0x3FB6161616161616],
            "secondaryText": [0x3FDA9A9A9A9A9A9B, 0x3FD8D8D8D8D8D8D9, 0x3FD2525252525252],
            "controlIcon":   [0x3FDA9A9A9A9A9A9B, 0x3FD8D8D8D8D8D8D9, 0x3FD2525252525252],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FCD1D1D1D1D1D1D, 0x3FC999999999999A, 0x3FB6161616161616],
        ]),
        Shipped("green", [
            "bg":            [0x3FED9D9D9D9D9D9E, 0x3FEEFEFEFEFEFEFF, 0x3FED3D3D3D3D3D3D],
            "bgDeep":        [0x3FEC944256D1B2FB, 0x3FEDE9456E6426B6, 0x3FEC37417EEF936A],
            "surface":       [0x3FEF3F3F3F3F3F3F, 0x3FEFBFBFBFBFBFC0, 0x3FEF1F1F1F1F1F1F],
            "accent":        [0x3FE6969696969697, 0x3FEC1C1C1C1C1C1C, 0x3FE4D4D4D4D4D4D5],
            "accentSoft":    [0x3FEAFAFAFAFAFAFB, 0x3FEDFDFDFDFDFDFE, 0x3FE9F9F9F9F9F9FA],
            "ringTrack":     [0x3FEADADADADADADB, 0x3FED9D9D9D9D9D9E, 0x3FE9F9F9F9F9F9FA],
            "buttonFill":    [0x3FE6969696969697, 0x3FEC1C1C1C1C1C1C, 0x3FE4D4D4D4D4D4D5],
            "ringFill":      [0x3FD56609E0EB2899, 0x3FE1F483E008FEC1, 0x3FCFF9932CC65FF9],
            "timerText":     [0x3FC3939393939394, 0x3FCC1C1C1C1C1C1C, 0x3FC1111111111111],
            "primaryText":   [0x3FC3939393939394, 0x3FCC1C1C1C1C1C1C, 0x3FC1111111111111],
            "secondaryText": [0x3FD6161616161616, 0x3FDA5A5A5A5A5A5A, 0x3FD4D4D4D4D4D4D5],
            "controlIcon":   [0x3FD6161616161616, 0x3FDA5A5A5A5A5A5A, 0x3FD4D4D4D4D4D4D5],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FC3939393939394, 0x3FCC1C1C1C1C1C1C, 0x3FC1111111111111],
        ]),
        Shipped("mint", [
            "bg":            [0x3FECDCDCDCDCDCDD, 0x3FEF3F3F3F3F3F3F, 0x3FEE5E5E5E5E5E5E],
            "bgDeep":        [0x3FEBDA40A70D73DA, 0x3FEE2745FE503BC0, 0x3FED4E440695F21A],
            "surface":       [0x3FEEFEFEFEFEFEFF, 0x3FEFDFDFDFDFDFE0, 0x3FEF7F7F7F7F7F7F],
            "accent":        [0x3FE2323232323232, 0x3FECBCBCBCBCBCBD, 0x3FE9595959595959],
            "accentSoft":    [0x3FE8D8D8D8D8D8D9, 0x3FEE5E5E5E5E5E5E, 0x3FEC5C5C5C5C5C5C],
            "ringTrack":     [0x3FE8F8F8F8F8F8F9, 0x3FEDFDFDFDFDFDFE, 0x3FEC3C3C3C3C3C3C],
            "buttonFill":    [0x3FE2323232323232, 0x3FECBCBCBCBCBCBD, 0x3FE9595959595959],
            "ringFill":      [0x0000000000000000, 0x3FE2727272727273, 0x3FDD83EA50B71D84],
            "timerText":     [0x3FB7171717171717, 0x3FCD1D1D1D1D1D1D, 0x3FC8181818181818],
            "primaryText":   [0x3FB7171717171717, 0x3FCD1D1D1D1D1D1D, 0x3FC8181818181818],
            "secondaryText": [0x3FD3131313131313, 0x3FDADADADADADADB, 0x3FD8585858585858],
            "controlIcon":   [0x3FD3131313131313, 0x3FDADADADADADADB, 0x3FD8585858585858],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FB7171717171717, 0x3FCD1D1D1D1D1D1D, 0x3FC8181818181818],
        ]),
        Shipped("sky", [
            "bg":            [0x3FECFCFCFCFCFCFD, 0x3FEEDEDEDEDEDEDF, 0x3FF0000000000000],
            "bgDeep":        [0x3FEBF940EF037E5F, 0x3FEDCA45266E1C31, 0x3FEEE147AE147AE1],
            "surface":       [0x3FEF1F1F1F1F1F1F, 0x3FEFBFBFBFBFBFC0, 0x3FF0000000000000],
            "accent":        [0x3FE3131313131313, 0x3FEB7B7B7B7B7B7B, 0x3FF0000000000000],
            "accentSoft":    [0x3FE9595959595959, 0x3FED9D9D9D9D9D9E, 0x3FF0000000000000],
            "ringTrack":     [0x3FE9191919191919, 0x3FED7D7D7D7D7D7D, 0x3FEFDFDFDFDFDFE0],
            "buttonFill":    [0x3FE3131313131313, 0x3FEB7B7B7B7B7B7B, 0x3FF0000000000000],
            "ringFill":      [0x0000000000000000, 0x3FE1919191919192, 0x3FE7979797979798],
            "timerText":     [0x3FB8181818181818, 0x3FCB9B9B9B9B9B9C, 0x3FD1919191919192],
            "primaryText":   [0x3FB8181818181818, 0x3FCB9B9B9B9B9B9C, 0x3FD1919191919192],
            "secondaryText": [0x3FD3131313131313, 0x3FDA1A1A1A1A1A1A, 0x3FDD9D9D9D9D9D9E],
            "controlIcon":   [0x3FD3131313131313, 0x3FDA1A1A1A1A1A1A, 0x3FDD9D9D9D9D9D9E],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FB8181818181818, 0x3FCB9B9B9B9B9B9C, 0x3FD1919191919192],
        ]),
        Shipped("blue", [
            "bg":            [0x3FEDFDFDFDFDFDFE, 0x3FEE7E7E7E7E7E7E, 0x3FF0000000000000],
            "bgDeep":        [0x3FECF1432EB3D28B, 0x3FED6D444E8BFCA0, 0x3FEEE147AE147AE1],
            "surface":       [0x3FEF7F7F7F7F7F7F, 0x3FEF9F9F9F9F9FA0, 0x3FF0000000000000],
            "accent":        [0x3FE8383838383838, 0x3FE9F9F9F9F9F9FA, 0x3FF0000000000000],
            "accentSoft":    [0x3FEBDBDBDBDBDBDC, 0x3FECBCBCBCBCBCBD, 0x3FF0000000000000],
            "ringTrack":     [0x3FEB7B7B7B7B7B7B, 0x3FEC9C9C9C9C9C9D, 0x3FF0000000000000],
            "buttonFill":    [0x3FE8383838383838, 0x3FE9F9F9F9F9F9FA, 0x3FF0000000000000],
            "ringFill":      [0x3FD999999999999A, 0x3FDE5E5E5E5E5E5E, 0x3FE9B9B9B9B9B9BA],
            "timerText":     [0x3FC5959595959596, 0x3FC8989898989899, 0x3FD2929292929293],
            "primaryText":   [0x3FC5959595959596, 0x3FC8989898989899, 0x3FD2929292929293],
            "secondaryText": [0x3FD6D6D6D6D6D6D7, 0x3FD8989898989899, 0x3FDEDEDEDEDEDEDF],
            "controlIcon":   [0x3FD6D6D6D6D6D6D7, 0x3FD8989898989899, 0x3FDEDEDEDEDEDEDF],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FC5959595959596, 0x3FC8989898989899, 0x3FD2929292929293],
        ]),
        Shipped("violet", [
            "bg":            [0x3FEEFEFEFEFEFEFF, 0x3FEE1E1E1E1E1E1E, 0x3FF0000000000000],
            "bgDeep":        [0x3FEDE9456E6426B6, 0x3FED104376A9DD10, 0x3FEEE147AE147AE1],
            "surface":       [0x3FEFBFBFBFBFBFC0, 0x3FEF7F7F7F7F7F7F, 0x3FF0000000000000],
            "accent":        [0x3FEBFBFBFBFBFBFC, 0x3FE8787878787878, 0x3FF0000000000000],
            "accentSoft":    [0x3FEDDDDDDDDDDDDE, 0x3FEBFBFBFBFBFBFC, 0x3FF0000000000000],
            "ringTrack":     [0x3FED9D9D9D9D9D9E, 0x3FEBBBBBBBBBBBBC, 0x3FEFBFBFBFBFBFC0],
            "buttonFill":    [0x3FEBFBFBFBFBFBFC, 0x3FE8787878787878, 0x3FF0000000000000],
            "ringFill":      [0x3FE2929292929293, 0x3FDA9A9A9A9A9A9B, 0x3FE7B7B7B7B7B7B8],
            "timerText":     [0x3FCC1C1C1C1C1C1C, 0x3FC6969696969697, 0x3FD1515151515151],
            "primaryText":   [0x3FCC1C1C1C1C1C1C, 0x3FC6969696969697, 0x3FD1515151515151],
            "secondaryText": [0x3FDA5A5A5A5A5A5A, 0x3FD7979797979798, 0x3FDD9D9D9D9D9D9E],
            "controlIcon":   [0x3FDA5A5A5A5A5A5A, 0x3FD7979797979798, 0x3FDD9D9D9D9D9D9E],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FCC1C1C1C1C1C1C, 0x3FC6969696969697, 0x3FD1515151515151],
        ]),
    ]

    private static let shippedDark: [Shipped] = [
        Shipped("pink", [
            "bg":            [0x3FC0101010101010, 0x3FB4141414141414, 0x3FB8181818181818],
            "bgDeep":        [0x3FBF0047F60A8566, 0x3FB3602CF9C69360, 0x3FB74035F887E40D],
            "surface":       [0x3FC6161616161616, 0x3FBE1E1E1E1E1E1E, 0x3FC1111111111111],
            "accent":        [0x3FEEBEBEBEBEBEBF, 0x3FE5959595959596, 0x3FE8585858585858],
            "accentSoft":    [0x3FD3D3D3D3D3D3D4, 0x3FCA1A1A1A1A1A1A, 0x3FCE1E1E1E1E1E1E],
            "ringTrack":     [0x3FD0101010101010, 0x3FC6969696969697, 0x3FC9191919191919],
            "buttonFill":    [0x3FEEBEBEBEBEBEBF, 0x3FE5959595959596, 0x3FE8585858585858],
            "ringFill":      [0x3FEDFDFDFDFDFDFE, 0x3FE4D4D4D4D4D4D5, 0x3FE7777777777777],
            "timerText":     [0x3FEE7E7E7E7E7E7E, 0x3FED1D1D1D1D1D1D, 0x3FED7D7D7D7D7D7D],
            "primaryText":   [0x3FEE7E7E7E7E7E7E, 0x3FED1D1D1D1D1D1D, 0x3FED7D7D7D7D7D7D],
            "secondaryText": [0x3FE7979797979798, 0x3FE5B5B5B5B5B5B6, 0x3FE6161616161616],
            "controlIcon":   [0x3FE7979797979798, 0x3FE5B5B5B5B5B5B6, 0x3FE6161616161616],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FEE7E7E7E7E7E7E, 0x3FED1D1D1D1D1D1D, 0x3FED7D7D7D7D7D7D],
        ]),
        Shipped("coral", [
            "bg":            [0x3FC0101010101010, 0x3FB5151515151515, 0x3FB1111111111111],
            "bgDeep":        [0x3FBF0047F60A8566, 0x3FB4582F3976E78B, 0x3FB078263AB596DE],
            "surface":       [0x3FC6161616161616, 0x3FBF1F1F1F1F1F1F, 0x3FBB1B1B1B1B1B1B],
            "accent":        [0x3FEEFEFEFEFEFEFF, 0x3FE6363636363636, 0x3FE2D2D2D2D2D2D3],
            "accentSoft":    [0x3FD3D3D3D3D3D3D4, 0x3FCB1B1B1B1B1B1B, 0x3FC6161616161616],
            "ringTrack":     [0x3FD0101010101010, 0x3FC7171717171717, 0x3FC3939393939394],
            "buttonFill":    [0x3FEEFEFEFEFEFEFF, 0x3FE6363636363636, 0x3FE2D2D2D2D2D2D3],
            "ringFill":      [0x3FEE1E1E1E1E1E1E, 0x3FE5757575757575, 0x3FE2121212121212],
            "timerText":     [0x3FEE7E7E7E7E7E7E, 0x3FED3D3D3D3D3D3D, 0x3FECBCBCBCBCBCBD],
            "primaryText":   [0x3FEE7E7E7E7E7E7E, 0x3FED3D3D3D3D3D3D, 0x3FECBCBCBCBCBCBD],
            "secondaryText": [0x3FE7979797979798, 0x3FE5D5D5D5D5D5D6, 0x3FE5151515151515],
            "controlIcon":   [0x3FE7979797979798, 0x3FE5D5D5D5D5D5D6, 0x3FE5151515151515],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FEE7E7E7E7E7E7E, 0x3FED3D3D3D3D3D3D, 0x3FECBCBCBCBCBCBD],
        ]),
        Shipped("yellow", [
            "bg":            [0x3FBB1B1B1B1B1B1B, 0x3FB8181818181818, 0x3FAC1C1C1C1C1C1C],
            "bgDeep":        [0x3FBA283CB798E08E, 0x3FB74035F887E40D, 0x3FAB203EF74934B9],
            "surface":       [0x3FC3131313131313, 0x3FC1919191919192, 0x3FB7171717171717],
            "accent":        [0x3FEDBDBDBDBDBDBE, 0x3FEB7B7B7B7B7B7B, 0x3FE2D2D2D2D2D2D3],
            "accentSoft":    [0x3FD1111111111111, 0x3FCE9E9E9E9E9E9F, 0x3FC2121212121212],
            "ringTrack":     [0x3FCC1C1C1C1C1C1C, 0x3FC999999999999A, 0x3FC0909090909091],
            "buttonFill":    [0x3FEDBDBDBDBDBDBE, 0x3FEB7B7B7B7B7B7B, 0x3FE2D2D2D2D2D2D3],
            "ringFill":      [0x3FECFCFCFCFCFCFD, 0x3FEA9A9A9A9A9A9B, 0x3FE1F1F1F1F1F1F2],
            "timerText":     [0x3FEDBDBDBDBDBDBE, 0x3FED7D7D7D7D7D7D, 0x3FEC5C5C5C5C5C5C],
            "primaryText":   [0x3FEDBDBDBDBDBDBE, 0x3FED7D7D7D7D7D7D, 0x3FEC5C5C5C5C5C5C],
            "secondaryText": [0x3FE6969696969697, 0x3FE6363636363636, 0x3FE4B4B4B4B4B4B5],
            "controlIcon":   [0x3FE6969696969697, 0x3FE6363636363636, 0x3FE4B4B4B4B4B4B5],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FEDBDBDBDBDBDBE, 0x3FED7D7D7D7D7D7D, 0x3FEC5C5C5C5C5C5C],
        ]),
        Shipped("green", [
            "bg":            [0x3FB4141414141414, 0x3FBB1B1B1B1B1B1B, 0x3FB2121212121212],
            "bgDeep":        [0x3FB3602CF9C69360, 0x3FBA283CB798E08E, 0x3FB170287A65EB0A],
            "surface":       [0x3FBE1E1E1E1E1E1E, 0x3FC2929292929293, 0x3FBB1B1B1B1B1B1B],
            "accent":        [0x3FE5151515151515, 0x3FEA5A5A5A5A5A5A, 0x3FE3333333333333],
            "accentSoft":    [0x3FC999999999999A, 0x3FD0909090909091, 0x3FC7171717171717],
            "ringTrack":     [0x3FC5959595959596, 0x3FCB9B9B9B9B9B9C, 0x3FC4141414141414],
            "buttonFill":    [0x3FE5151515151515, 0x3FEA5A5A5A5A5A5A, 0x3FE3333333333333],
            "ringFill":      [0x3FE4343434343434, 0x3FE999999999999A, 0x3FE2727272727272],
            "timerText":     [0x3FECFCFCFCFCFCFD, 0x3FEDBDBDBDBDBDBE, 0x3FECBCBCBCBCBCBD],
            "primaryText":   [0x3FECFCFCFCFCFCFD, 0x3FEDBDBDBDBDBDBE, 0x3FECBCBCBCBCBCBD],
            "secondaryText": [0x3FE5959595959596, 0x3FE6969696969697, 0x3FE5353535353535],
            "controlIcon":   [0x3FE5959595959596, 0x3FE6969696969697, 0x3FE5353535353535],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FECFCFCFCFCFCFD, 0x3FEDBDBDBDBDBDBE, 0x3FECBCBCBCBCBCBD],
        ]),
        Shipped("mint", [
            "bg":            [0x3FAE1E1E1E1E1E1E, 0x3FBB1B1B1B1B1B1B, 0x3FB7171717171717],
            "bgDeep":        [0x3FAD104376A9DD10, 0x3FBA283CB798E08E, 0x3FB64833B8D78FE2],
            "surface":       [0x3FB8181818181818, 0x3FC3131313131313, 0x3FC1111111111111],
            "accent":        [0x3FE0909090909091, 0x3FEAFAFAFAFAFAFB, 0x3FE7B7B7B7B7B7B8],
            "accentSoft":    [0x3FC3131313131313, 0x3FD1111111111111, 0x3FCD9D9D9D9D9D9E],
            "ringTrack":     [0x3FC1919191919192, 0x3FCC1C1C1C1C1C1C, 0x3FC8989898989899],
            "buttonFill":    [0x3FE0909090909091, 0x3FEAFAFAFAFAFAFB, 0x3FE7B7B7B7B7B7B8],
            "ringFill":      [0x3FDF9F9F9F9F9FA0, 0x3FEA3A3A3A3A3A3A, 0x3FE6F6F6F6F6F6F7],
            "timerText":     [0x3FEC9C9C9C9C9C9D, 0x3FEDDDDDDDDDDDDE, 0x3FED5D5D5D5D5D5D],
            "primaryText":   [0x3FEC9C9C9C9C9C9D, 0x3FEDDDDDDDDDDDDE, 0x3FED5D5D5D5D5D5D],
            "secondaryText": [0x3FE4D4D4D4D4D4D5, 0x3FE6B6B6B6B6B6B7, 0x3FE6161616161616],
            "controlIcon":   [0x3FE4D4D4D4D4D4D5, 0x3FE6B6B6B6B6B6B7, 0x3FE6161616161616],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FEC9C9C9C9C9C9D, 0x3FEDDDDDDDDDDDDE, 0x3FED5D5D5D5D5D5D],
        ]),
        Shipped("sky", [
            "bg":            [0x3FAE1E1E1E1E1E1E, 0x3FBA1A1A1A1A1A1A, 0x3FC0101010101010],
            "bgDeep":        [0x3FAD104376A9DD10, 0x3FB9303A77E88C63, 0x3FBF0047F60A8566],
            "surface":       [0x3FB8181818181818, 0x3FC2929292929293, 0x3FC6161616161616],
            "accent":        [0x3FE0D0D0D0D0D0D1, 0x3FE9F9F9F9F9F9FA, 0x3FEEBEBEBEBEBEBF],
            "accentSoft":    [0x3FC3939393939394, 0x3FD0505050505050, 0x3FD3D3D3D3D3D3D4],
            "ringTrack":     [0x3FC1919191919192, 0x3FCB1B1B1B1B1B1B, 0x3FD0101010101010],
            "buttonFill":    [0x3FE0D0D0D0D0D0D1, 0x3FE9F9F9F9F9F9FA, 0x3FEEBEBEBEBEBEBF],
            "ringFill":      [0x3FE0101010101010, 0x3FE9191919191919, 0x3FEDDDDDDDDDDDDE],
            "timerText":     [0x3FEC9C9C9C9C9C9D, 0x3FEDBDBDBDBDBDBE, 0x3FEE5E5E5E5E5E5E],
            "primaryText":   [0x3FEC9C9C9C9C9C9D, 0x3FEDBDBDBDBDBDBE, 0x3FEE5E5E5E5E5E5E],
            "secondaryText": [0x3FE4D4D4D4D4D4D5, 0x3FE6767676767676, 0x3FE7777777777777],
            "controlIcon":   [0x3FE4D4D4D4D4D4D5, 0x3FE6767676767676, 0x3FE7777777777777],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FEC9C9C9C9C9C9D, 0x3FEDBDBDBDBDBDBE, 0x3FEE5E5E5E5E5E5E],
        ]),
        Shipped("blue", [
            "bg":            [0x3FB5151515151515, 0x3FB8181818181818, 0x3FC1111111111111],
            "bgDeep":        [0x3FB4582F3976E78B, 0x3FB74035F887E40D, 0x3FC078263AB596DE],
            "surface":       [0x3FBF1F1F1F1F1F1F, 0x3FC1111111111111, 0x3FC7171717171717],
            "accent":        [0x3FE5F5F5F5F5F5F6, 0x3FE8383838383838, 0x3FF0000000000000],
            "accentSoft":    [0x3FCB1B1B1B1B1B1B, 0x3FCE1E1E1E1E1E1E, 0x3FD4949494949495],
            "ringTrack":     [0x3FC6969696969697, 0x3FC9191919191919, 0x3FD0909090909091],
            "buttonFill":    [0x3FE5F5F5F5F5F5F6, 0x3FE8383838383838, 0x3FF0000000000000],
            "ringFill":      [0x3FE5353535353535, 0x3FE7777777777777, 0x3FEF1F1F1F1F1F1F],
            "timerText":     [0x3FED1D1D1D1D1D1D, 0x3FED7D7D7D7D7D7D, 0x3FEE7E7E7E7E7E7E],
            "primaryText":   [0x3FED1D1D1D1D1D1D, 0x3FED7D7D7D7D7D7D, 0x3FEE7E7E7E7E7E7E],
            "secondaryText": [0x3FE5B5B5B5B5B5B6, 0x3FE6363636363636, 0x3FE7B7B7B7B7B7B8],
            "controlIcon":   [0x3FE5B5B5B5B5B5B6, 0x3FE6363636363636, 0x3FE7B7B7B7B7B7B8],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FED1D1D1D1D1D1D, 0x3FED7D7D7D7D7D7D, 0x3FEE7E7E7E7E7E7E],
        ]),
        Shipped("violet", [
            "bg":            [0x3FBB1B1B1B1B1B1B, 0x3FB6161616161616, 0x3FC0101010101010],
            "bgDeep":        [0x3FBA283CB798E08E, 0x3FB5503179273BB6, 0x3FBF0047F60A8566],
            "surface":       [0x3FC2929292929293, 0x3FC0101010101010, 0x3FC5959595959596],
            "accent":        [0x3FEA5A5A5A5A5A5A, 0x3FE6B6B6B6B6B6B7, 0x3FEE7E7E7E7E7E7E],
            "accentSoft":    [0x3FD0909090909091, 0x3FCC1C1C1C1C1C1C, 0x3FD3939393939394],
            "ringTrack":     [0x3FCB9B9B9B9B9B9C, 0x3FC7979797979798, 0x3FCF9F9F9F9F9FA0],
            "buttonFill":    [0x3FEA5A5A5A5A5A5A, 0x3FE6B6B6B6B6B6B7, 0x3FEE7E7E7E7E7E7E],
            "ringFill":      [0x3FE999999999999A, 0x3FE5F5F5F5F5F5F6, 0x3FED9D9D9D9D9D9E],
            "timerText":     [0x3FEDBDBDBDBDBDBE, 0x3FED3D3D3D3D3D3D, 0x3FEE5E5E5E5E5E5E],
            "primaryText":   [0x3FEDBDBDBDBDBDBE, 0x3FED3D3D3D3D3D3D, 0x3FEE5E5E5E5E5E5E],
            "secondaryText": [0x3FE6969696969697, 0x3FE5D5D5D5D5D5D6, 0x3FE7575757575757],
            "controlIcon":   [0x3FE6969696969697, 0x3FE5D5D5D5D5D5D6, 0x3FE7575757575757],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FEDBDBDBDBDBDBE, 0x3FED3D3D3D3D3D3D, 0x3FEE5E5E5E5E5E5E],
        ]),
    ]

    private static let mixed: [Synthetic] = [
        Synthetic("light bg, dark surface",
                  ThemeColors(bg: "#FFF4E8", surface: "#1E2A3A",
                              accent: "#F5A97F", accentSoft: "#FBD3BE",
                              text: "#5A3A2E", textSecondary: "#8C7468",
                              ringTrack: "#F9DCCB", ringFill: "#F08A5D"), [
            "bg":            [0x3FF0000000000000, 0x3FEE9E9E9E9E9E9F, 0x3FED1D1D1D1D1D1D],
            "bgDeep":        [0x3FEEE147AE147AE1, 0x3FED8C4496820726, 0x3FEC184136F988E5],
            "surface":       [0x3FBE1E1E1E1E1E1E, 0x3FC5151515151515, 0x3FCD1D1D1D1D1D1D],
            "accent":        [0x3FEEBEBEBEBEBEBF, 0x3FE5353535353535, 0x3FDFDFDFDFDFDFE0],
            "accentSoft":    [0x3FEF7F7F7F7F7F7F, 0x3FEA7A7A7A7A7A7A, 0x3FE7D7D7D7D7D7D8],
            "ringTrack":     [0x3FEF3F3F3F3F3F3F, 0x3FEB9B9B9B9B9B9C, 0x3FE9797979797979],
            "buttonFill":    [0x3FEEBEBEBEBEBEBF, 0x3FE5353535353535, 0x3FDFDFDFDFDFDFE0],
            "ringFill":      [0x3FE77DE44AB1177E, 0x3FDB03F9BC4BA7D0, 0x3FD234C420493F02],
            "timerText":     [0x3FE821BB54EE8823, 0x3FE69B15F73EED03, 0x3FE60897F41D12D7],
            "primaryText":   [0x3FE821BB54EE8823, 0x3FE69B15F73EED03, 0x3FE60897F41D12D7],
            "secondaryText": [0x3FE3F6C7AD0D4ED8, 0x3FE1DBB0455D8821, 0x3FE0CE249185A4C6],
            "controlIcon":   [0x3FE3F6C7AD0D4ED8, 0x3FE1DBB0455D8821, 0x3FE0CE249185A4C6],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FD6969696969697, 0x3FCD1D1D1D1D1D1D, 0x3FC7171717171717],
        ]),
        Synthetic("dark bg, light surface",
                  ThemeColors(bg: "#1E2A3A", surface: "#FFF4E8",
                              accent: "#F5A97F", accentSoft: "#FBD3BE",
                              text: "#5A3A2E", textSecondary: "#8C7468",
                              ringTrack: "#F9DCCB", ringFill: "#F08A5D"), [
            "bg":            [0x3FBE1E1E1E1E1E1E, 0x3FC5151515151515, 0x3FCD1D1D1D1D1D1D],
            "bgDeep":        [0x3FBD104376A9DD10, 0x3FC4582F3976E78B, 0x3FCC184136F988E5],
            "surface":       [0x3FF0000000000000, 0x3FEE9E9E9E9E9E9F, 0x3FED1D1D1D1D1D1D],
            "accent":        [0x3FEEBEBEBEBEBEBF, 0x3FE5353535353535, 0x3FDFDFDFDFDFDFE0],
            "accentSoft":    [0x3FEF7F7F7F7F7F7F, 0x3FEA7A7A7A7A7A7A, 0x3FE7D7D7D7D7D7D8],
            "ringTrack":     [0x3FEF3F3F3F3F3F3F, 0x3FEB9B9B9B9B9B9C, 0x3FE9797979797979],
            "buttonFill":    [0x3FEEBEBEBEBEBEBF, 0x3FE5353535353535, 0x3FDFDFDFDFDFDFE0],
            "ringFill":      [0x3FE77DE44AB1177E, 0x3FDB03F9BC4BA7D0, 0x3FD234C420493F02],
            "timerText":     [0x3FD53C676975BF79, 0x3FD3E4A2B09DC652, 0x3FD363B8EB4CC8E4],
            "primaryText":   [0x3FD53C676975BF79, 0x3FD3E4A2B09DC652, 0x3FD363B8EB4CC8E4],
            "secondaryText": [0x3FDF759A77A6C162, 0x3FDB9B533C4C45B9, 0x3FD9AE2F9E9F07E4],
            "controlIcon":   [0x3FDF759A77A6C162, 0x3FDB9B533C4C45B9, 0x3FD9AE2F9E9F07E4],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FD6969696969697, 0x3FCD1D1D1D1D1D1D, 0x3FC7171717171717],
        ]),
        Synthetic("white bg, black surface",
                  ThemeColors(bg: "#FFFFFF", surface: "#000000",
                              accent: "#3FA7D6", accentSoft: "#CFE8F5",
                              text: "#7A5C9E", textSecondary: "#9E8A5C",
                              ringTrack: "#DDDDDD", ringFill: "#EEEEEE"), [
            "bg":            [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "bgDeep":        [0x3FEEE147AE147AE1, 0x3FEEE147AE147AE1, 0x3FEEE147AE147AE1],
            "surface":       [0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
            "accent":        [0x3FCF9F9F9F9F9FA0, 0x3FE4F4F4F4F4F4F5, 0x3FEADADADADADADB],
            "accentSoft":    [0x3FE9F9F9F9F9F9FA, 0x3FED1D1D1D1D1D1D, 0x3FEEBEBEBEBEBEBF],
            "ringTrack":     [0x3FEBBBBBBBBBBBBC, 0x3FEBBBBBBBBBBBBC, 0x3FEBBBBBBBBBBBBC],
            "buttonFill":    [0x3FCF9F9F9F9F9FA0, 0x3FE4F4F4F4F4F4F5, 0x3FEADADADADADADB],
            "ringFill":      [0x3FDF0FB38A94D241, 0x3FDF0FB38A94D241, 0x3FDF0FB38A94D241],
            "timerText":     [0x3FE42222F4ABC31C, 0x3FE22C35381616E9, 0x3FE67C73709291C0],
            "primaryText":   [0x3FE42222F4ABC31C, 0x3FE22C35381616E9, 0x3FE67C73709291C0],
            "secondaryText": [0x3FE0A7B1EF6003DB, 0x3FDD17F940EF037E, 0x3FD36550D5F4ACFF],
            "controlIcon":   [0x3FE0A7B1EF6003DB, 0x3FDD17F940EF037E, 0x3FD36550D5F4ACFF],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FDD651327A283CC, 0x3FD62AA586CE7C91, 0x3FE308CB5AB6DFD6],
        ]),
        Synthetic("black bg, white surface",
                  ThemeColors(bg: "#000000", surface: "#FFFFFF",
                              accent: "#3FA7D6", accentSoft: "#CFE8F5",
                              text: "#7A5C9E", textSecondary: "#9E8A5C",
                              ringTrack: "#DDDDDD", ringFill: "#EEEEEE"), [
            "bg":            [0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
            "bgDeep":        [0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
            "surface":       [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "accent":        [0x3FCF9F9F9F9F9FA0, 0x3FE4F4F4F4F4F4F5, 0x3FEADADADADADADB],
            "accentSoft":    [0x3FE9F9F9F9F9F9FA, 0x3FED1D1D1D1D1D1D, 0x3FEEBEBEBEBEBEBF],
            "ringTrack":     [0x3FEBBBBBBBBBBBBC, 0x3FEBBBBBBBBBBBBC, 0x3FEBBBBBBBBBBBBC],
            "buttonFill":    [0x3FCF9F9F9F9F9FA0, 0x3FE4F4F4F4F4F4F5, 0x3FEADADADADADADB],
            "ringFill":      [0x3FDF0FB38A94D241, 0x3FDF0FB38A94D241, 0x3FDF0FB38A94D241],
            "timerText":     [0x3FD7914BA9DF1E9A, 0x3FD482B7F77461F2, 0x3FDB3C634CC59A98],
            "primaryText":   [0x3FD7914BA9DF1E9A, 0x3FD482B7F77461F2, 0x3FDB3C634CC59A98],
            "secondaryText": [0x3FE0A7B1EF6003DB, 0x3FDD17F940EF037E, 0x3FD36550D5F4ACFF],
            "controlIcon":   [0x3FE0A7B1EF6003DB, 0x3FDD17F940EF037E, 0x3FD36550D5F4ACFF],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FDD651327A283CC, 0x3FD62AA586CE7C91, 0x3FE308CB5AB6DFD6],
        ]),
        Synthetic("pale bg, mid-dark surface",
                  ThemeColors(bg: "#F2F7FF", surface: "#4D4D4D",
                              accent: "#3FA7D6", accentSoft: "#CFE8F5",
                              text: "#2E5A3A", textSecondary: "#6B8E73",
                              ringTrack: "#C8D8F0", ringFill: "#7FA8E0"), [
            "bg":            [0x3FEE5E5E5E5E5E5E, 0x3FEEFEFEFEFEFEFF, 0x3FF0000000000000],
            "bgDeep":        [0x3FED4E440695F21A, 0x3FEDE9456E6426B6, 0x3FEEE147AE147AE1],
            "surface":       [0x3FD3535353535353, 0x3FD3535353535353, 0x3FD3535353535353],
            "accent":        [0x3FCF9F9F9F9F9FA0, 0x3FE4F4F4F4F4F4F5, 0x3FEADADADADADADB],
            "accentSoft":    [0x3FE9F9F9F9F9F9FA, 0x3FED1D1D1D1D1D1D, 0x3FEEBEBEBEBEBEBF],
            "ringTrack":     [0x3FE9191919191919, 0x3FEB1B1B1B1B1B1B, 0x3FEE1E1E1E1E1E1E],
            "buttonFill":    [0x3FCF9F9F9F9F9FA0, 0x3FE4F4F4F4F4F4F5, 0x3FEADADADADADADB],
            "ringFill":      [0x3FD6F31C11D463C0, 0x3FDE5BCC7047518F, 0x3FE43D32F584E10A],
            "timerText":     [0x3FECDA4AEEC5D011, 0x3FED83EA50B71D86, 0x3FED088DAC64B6A5],
            "primaryText":   [0x3FECDA4AEEC5D011, 0x3FED83EA50B71D86, 0x3FED088DAC64B6A5],
            "secondaryText": [0x3FE677E6E7502BB8, 0x3FE82A5DFA08C7A8, 0x3FE6DB3551FE0638],
            "controlIcon":   [0x3FE677E6E7502BB8, 0x3FE82A5DFA08C7A8, 0x3FE6DB3551FE0638],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FC7171717171717, 0x3FD6969696969697, 0x3FCD1D1D1D1D1D1D],
        ]),
    ]

    private static let unreachable: [Synthetic] = [
        Synthetic("everything mid grey",
                  ThemeColors(bg: "#808080", surface: "#808080",
                              accent: "#808080", accentSoft: "#808080",
                              text: "#808080", textSecondary: "#808080",
                              ringTrack: "#808080", ringFill: "#808080"), [
            "bg":            [0x3FE0101010101010, 0x3FE0101010101010, 0x3FE0101010101010],
            "bgDeep":        [0x3FDF0047F60A8566, 0x3FDF0047F60A8566, 0x3FDF0047F60A8566],
            "surface":       [0x3FE0101010101010, 0x3FE0101010101010, 0x3FE0101010101010],
            "accent":        [0x3FE0101010101010, 0x3FE0101010101010, 0x3FE0101010101010],
            "accentSoft":    [0x3FE0101010101010, 0x3FE0101010101010, 0x3FE0101010101010],
            "ringTrack":     [0x3FE0101010101010, 0x3FE0101010101010, 0x3FE0101010101010],
            "buttonFill":    [0x3FDD8E32091350C2, 0x3FDD8E32091350C2, 0x3FDD8E32091350C2],
            "ringFill":      [0x3FCAFC43F2068160, 0x3FCAFC43F2068160, 0x3FCAFC43F2068160],
            "timerText":     [0x3F2A51341F3B7D40, 0x3F2A51341F3B7D40, 0x3F2A51341F3B7D40],
            "primaryText":   [0x3F2A51341F3B7D40, 0x3F2A51341F3B7D40, 0x3F2A51341F3B7D40],
            "secondaryText": [0x3FB7215ECF734A48, 0x3FB7215ECF734A48, 0x3FB7215ECF734A48],
            "controlIcon":   [0x3FB7215ECF734A48, 0x3FB7215ECF734A48, 0x3FB7215ECF734A48],
            "buttonLabel":   [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "onAccentSoft":  [0x3FB7215ECF734A48, 0x3FB7215ECF734A48, 0x3FB7215ECF734A48],
        ]),
        Synthetic("two mid greys, blue ink",
                  ThemeColors(bg: "#767676", surface: "#959595",
                              accent: "#3FA7D6", accentSoft: "#8FA0B0",
                              text: "#4A6FA5", textSecondary: "#7A8A9A",
                              ringTrack: "#888888", ringFill: "#999999"), [
            "bg":            [0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E],
            "bgDeep":        [0x3FDC944256D1B2FB, 0x3FDC944256D1B2FB, 0x3FDC944256D1B2FB],
            "surface":       [0x3FE2B2B2B2B2B2B3, 0x3FE2B2B2B2B2B2B3, 0x3FE2B2B2B2B2B2B3],
            "accent":        [0x3FCF9F9F9F9F9FA0, 0x3FE4F4F4F4F4F4F5, 0x3FEADADADADADADB],
            "accentSoft":    [0x3FE1F1F1F1F1F1F2, 0x3FE4141414141414, 0x3FE6161616161616],
            "ringTrack":     [0x3FE1111111111111, 0x3FE1111111111111, 0x3FE1111111111111],
            "buttonFill":    [0x3FCF9F9F9F9F9FA0, 0x3FE4F4F4F4F4F4F5, 0x3FEADADADADADADB],
            "ringFill":      [0x3FCEB851EB851EB4, 0x3FCEB851EB851EB4, 0x3FCEB851EB851EB4],
            "timerText":     [0x3F4304AEAA91FDE8, 0x3F4C8705FFDAFCE0, 0x3F5533EC3E29AE18],
            "primaryText":   [0x3F4304AEAA91FDE8, 0x3F4C8705FFDAFCE0, 0x3F5533EC3E29AE18],
            "secondaryText": [0x3F8398B76FC1ACA0, 0x3F862AA586CE7C00, 0x3F88BC939DDB4B40],
            "controlIcon":   [0x3F8398B76FC1ACA0, 0x3F862AA586CE7C00, 0x3F88BC939DDB4B40],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FC1D463BFE8DEA0, 0x3FCABE959FDD4DF0, 0x3FD3E0AD7A4713DF],
        ]),
        Synthetic("olive bg, grey surface, ink = bg",
                  ThemeColors(bg: "#6B8E23", surface: "#B0B0B0",
                              accent: "#6B8E23", accentSoft: "#9CB86A",
                              text: "#6B8E23", textSecondary: "#6B8E23",
                              ringTrack: "#808080", ringFill: "#8A8A8A"), [
            "bg":            [0x3FDADADADADADADB, 0x3FE1D1D1D1D1D1D2, 0x3FC1919191919192],
            "bgDeep":        [0x3FD9EA3C27ACCB84, 0x3FE13227EA79D5FF, 0x3FC0F4275A8DC0F4],
            "surface":       [0x3FE6161616161616, 0x3FE6161616161616, 0x3FE6161616161616],
            "accent":        [0x3FDADADADADADADB, 0x3FE1D1D1D1D1D1D2, 0x3FC1919191919192],
            "accentSoft":    [0x3FE3939393939394, 0x3FE7171717171717, 0x3FDA9A9A9A9A9A9B],
            "ringTrack":     [0x3FE0101010101010, 0x3FE0101010101010, 0x3FE0101010101010],
            "buttonFill":    [0x3FD7A1DF4FF3CAD5, 0x3FDF5CCD71485290, 0x3FBEEBB885521EED],
            "ringFill":      [0x3FCBB54EE8821BB0, 0x3FCBB54EE8821BB0, 0x3FCBB54EE8821BB0],
            "timerText":     [0x3F812FE83A25AA40, 0x3F86CF210C91AFC0, 0x3F667CE349B015C0],
            "primaryText":   [0x3F812FE83A25AA40, 0x3F86CF210C91AFC0, 0x3F667CE349B015C0],
            "secondaryText": [0x3FB57BE248AF1570, 0x3FBC82E94FB61C74, 0x3F9C1C1C1C1C1C0C],
            "controlIcon":   [0x3FB57BE248AF1570, 0x3FBC82E94FB61C74, 0x3F9C1C1C1C1C1C0C],
            "buttonLabel":   [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "onAccentSoft":  [0x3FCADADADADADAD9, 0x3FD1D1D1D1D1D1D1, 0x3FB1919191919191],
        ]),
        Synthetic("grey #757575 just below the black/white tie",
                  ThemeColors(bg: "#757575", surface: "#757575",
                              accent: "#757575", accentSoft: "#757575",
                              text: "#757575", textSecondary: "#757575",
                              ringTrack: "#757575", ringFill: "#757575"), [
            "bg":            [0x3FDD5D5D5D5D5D5D, 0x3FDD5D5D5D5D5D5D, 0x3FDD5D5D5D5D5D5D],
            "bgDeep":        [0x3FDC5641C6E59DEF, 0x3FDC5641C6E59DEF, 0x3FDC5641C6E59DEF],
            "surface":       [0x3FDD5D5D5D5D5D5D, 0x3FDD5D5D5D5D5D5D, 0x3FDD5D5D5D5D5D5D],
            "accent":        [0x3FDD5D5D5D5D5D5D, 0x3FDD5D5D5D5D5D5D, 0x3FDD5D5D5D5D5D5D],
            "accentSoft":    [0x3FDD5D5D5D5D5D5D, 0x3FDD5D5D5D5D5D5D, 0x3FDD5D5D5D5D5D5D],
            "ringTrack":     [0x3FDD5D5D5D5D5D5D, 0x3FDD5D5D5D5D5D5D, 0x3FDD5D5D5D5D5D5D],
            "buttonFill":    [0x3FDD5D5D5D5D5D5D, 0x3FDD5D5D5D5D5D5D, 0x3FDD5D5D5D5D5D5D],
            "ringFill":      [0x3FEA75569E4C60DE, 0x3FEA75569E4C60DE, 0x3FEA75569E4C60DE],
            "timerText":     [0x3FEFFE3A073CE53E, 0x3FEFFE3A073CE53E, 0x3FEFFE3A073CE53E],
            "primaryText":   [0x3FEFFE3A073CE53E, 0x3FEFFE3A073CE53E, 0x3FEFFE3A073CE53E],
            "secondaryText": [0x3FEFA75569E4C610, 0x3FEFA75569E4C610, 0x3FEFA75569E4C610],
            "controlIcon":   [0x3FEFA75569E4C610, 0x3FEFA75569E4C610, 0x3FEFA75569E4C610],
            "buttonLabel":   [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "onAccentSoft":  [0x3FEFA75569E4C610, 0x3FEFA75569E4C610, 0x3FEFA75569E4C610],
        ]),
        Synthetic("grey #767676 just above the black/white tie",
                  ThemeColors(bg: "#767676", surface: "#767676",
                              accent: "#767676", accentSoft: "#767676",
                              text: "#767676", textSecondary: "#767676",
                              ringTrack: "#767676", ringFill: "#767676"), [
            "bg":            [0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E],
            "bgDeep":        [0x3FDC944256D1B2FB, 0x3FDC944256D1B2FB, 0x3FDC944256D1B2FB],
            "surface":       [0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E],
            "accent":        [0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E],
            "accentSoft":    [0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E],
            "ringTrack":     [0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E],
            "buttonFill":    [0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E],
            "ringFill":      [0x3FC6820725DE3018, 0x3FC6820725DE3018, 0x3FC6820725DE3018],
            "timerText":     [0x3F2842DC0CCAD740, 0x3F2842DC0CCAD740, 0x3F2842DC0CCAD740],
            "primaryText":   [0x3F2842DC0CCAD740, 0x3F2842DC0CCAD740, 0x3F2842DC0CCAD740],
            "secondaryText": [0x3F82F43BE9FE78C0, 0x3F82F43BE9FE78C0, 0x3F82F43BE9FE78C0],
            "controlIcon":   [0x3F82F43BE9FE78C0, 0x3F82F43BE9FE78C0, 0x3F82F43BE9FE78C0],
            "buttonLabel":   [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "onAccentSoft":  [0x3F82F43BE9FE78C0, 0x3F82F43BE9FE78C0, 0x3F82F43BE9FE78C0],
        ]),
    ]

    private static let passing: [Synthetic] = [
        Synthetic("black ink on white",
                  ThemeColors(bg: "#FFFFFF", surface: "#FAFAFA",
                              accent: "#000000", accentSoft: "#F0F0F0",
                              text: "#000000", textSecondary: "#333333",
                              ringTrack: "#EEEEEE", ringFill: "#000000"), [
            "bg":            [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "bgDeep":        [0x3FEEE147AE147AE1, 0x3FEEE147AE147AE1, 0x3FEEE147AE147AE1],
            "surface":       [0x3FEF5F5F5F5F5F5F, 0x3FEF5F5F5F5F5F5F, 0x3FEF5F5F5F5F5F5F],
            "accent":        [0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
            "accentSoft":    [0x3FEE1E1E1E1E1E1E, 0x3FEE1E1E1E1E1E1E, 0x3FEE1E1E1E1E1E1E],
            "ringTrack":     [0x3FEDDDDDDDDDDDDE, 0x3FEDDDDDDDDDDDDE, 0x3FEDDDDDDDDDDDDE],
            "buttonFill":    [0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
            "ringFill":      [0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
            "timerText":     [0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
            "primaryText":   [0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
            "secondaryText": [0x3FC999999999999A, 0x3FC999999999999A, 0x3FC999999999999A],
            "controlIcon":   [0x3FC999999999999A, 0x3FC999999999999A, 0x3FC999999999999A],
            "buttonLabel":   [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "onAccentSoft":  [0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
        ]),
        Synthetic("white ink on black",
                  ThemeColors(bg: "#000000", surface: "#111111",
                              accent: "#FFFFFF", accentSoft: "#222222",
                              text: "#FFFFFF", textSecondary: "#CCCCCC",
                              ringTrack: "#333333", ringFill: "#FFFFFF"), [
            "bg":            [0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
            "bgDeep":        [0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
            "surface":       [0x3FB1111111111111, 0x3FB1111111111111, 0x3FB1111111111111],
            "accent":        [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "accentSoft":    [0x3FC1111111111111, 0x3FC1111111111111, 0x3FC1111111111111],
            "ringTrack":     [0x3FC999999999999A, 0x3FC999999999999A, 0x3FC999999999999A],
            "buttonFill":    [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "ringFill":      [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "timerText":     [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "primaryText":   [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "secondaryText": [0x3FE999999999999A, 0x3FE999999999999A, 0x3FE999999999999A],
            "controlIcon":   [0x3FE999999999999A, 0x3FE999999999999A, 0x3FE999999999999A],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
        ]),
        Synthetic("ink just over 7:1 and 4.5:1 on white",
                  ThemeColors(bg: "#FFFFFF", surface: "#FFFFFF",
                              accent: "#595959", accentSoft: "#FFFFFF",
                              text: "#595959", textSecondary: "#767676",
                              ringTrack: "#FFFFFF", ringFill: "#949494"), [
            "bg":            [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "bgDeep":        [0x3FEEE147AE147AE1, 0x3FEEE147AE147AE1, 0x3FEEE147AE147AE1],
            "surface":       [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "accent":        [0x3FD6565656565656, 0x3FD6565656565656, 0x3FD6565656565656],
            "accentSoft":    [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "ringTrack":     [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "buttonFill":    [0x3FD6565656565656, 0x3FD6565656565656, 0x3FD6565656565656],
            "ringFill":      [0x3FE2929292929293, 0x3FE2929292929293, 0x3FE2929292929293],
            "timerText":     [0x3FD6565656565656, 0x3FD6565656565656, 0x3FD6565656565656],
            "primaryText":   [0x3FD6565656565656, 0x3FD6565656565656, 0x3FD6565656565656],
            "secondaryText": [0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E],
            "controlIcon":   [0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E, 0x3FDD9D9D9D9D9D9E],
            "buttonLabel":   [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "onAccentSoft":  [0x3FD6565656565656, 0x3FD6565656565656, 0x3FD6565656565656],
        ]),
        Synthetic("ink just under 7:1 and 4.5:1 on white",
                  ThemeColors(bg: "#FFFFFF", surface: "#FFFFFF",
                              accent: "#5A5A5A", accentSoft: "#FFFFFF",
                              text: "#5A5A5A", textSecondary: "#777777",
                              ringTrack: "#FFFFFF", ringFill: "#959595"), [
            "bg":            [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "bgDeep":        [0x3FEEE147AE147AE1, 0x3FEEE147AE147AE1, 0x3FEEE147AE147AE1],
            "surface":       [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "accent":        [0x3FD6969696969697, 0x3FD6969696969697, 0x3FD6969696969697],
            "accentSoft":    [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "ringTrack":     [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "buttonFill":    [0x3FD6969696969697, 0x3FD6969696969697, 0x3FD6969696969697],
            "ringFill":      [0x3FE252F6CDD81586, 0x3FE252F6CDD81586, 0x3FE252F6CDD81586],
            "timerText":     [0x3FD622EFBC895623, 0x3FD622EFBC895623, 0x3FD622EFBC895623],
            "primaryText":   [0x3FD622EFBC895623, 0x3FD622EFBC895623, 0x3FD622EFBC895623],
            "secondaryText": [0x3FDD44F3078263AB, 0x3FDD44F3078263AB, 0x3FDD44F3078263AB],
            "controlIcon":   [0x3FDD44F3078263AB, 0x3FDD44F3078263AB, 0x3FDD44F3078263AB],
            "buttonLabel":   [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "onAccentSoft":  [0x3FD6969696969697, 0x3FD6969696969697, 0x3FD6969696969697],
        ]),
    ]

    private static let spelling: [Synthetic] = [
        Synthetic("junk everywhere",
                  ThemeColors(bg: "not a color", surface: "not a color",
                              accent: "not a color", accentSoft: "not a color",
                              text: "not a color", textSecondary: "not a color",
                              ringTrack: "not a color", ringFill: "not a color"), [
            "bg":            [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE0000000000000],
            "bgDeep":        [0x3FDEE147AE147AE1, 0x3FDEE147AE147AE1, 0x3FDEE147AE147AE1],
            "surface":       [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE0000000000000],
            "accent":        [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE0000000000000],
            "accentSoft":    [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE0000000000000],
            "ringTrack":     [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE0000000000000],
            "buttonFill":    [0x3FDD70A3D70A3D71, 0x3FDD70A3D70A3D71, 0x3FDD70A3D70A3D71],
            "ringFill":      [0x3FCAE147AE147ADE, 0x3FCAE147AE147ADE, 0x3FCAE147AE147ADE],
            "timerText":     [0x3F2A36E2EB1C41C0, 0x3F2A36E2EB1C41C0, 0x3F2A36E2EB1C41C0],
            "primaryText":   [0x3F2A36E2EB1C41C0, 0x3F2A36E2EB1C41C0, 0x3F2A36E2EB1C41C0],
            "secondaryText": [0x3FB70A3D70A3D6FC, 0x3FB70A3D70A3D6FC, 0x3FB70A3D70A3D6FC],
            "controlIcon":   [0x3FB70A3D70A3D6FC, 0x3FB70A3D70A3D6FC, 0x3FB70A3D70A3D6FC],
            "buttonLabel":   [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "onAccentSoft":  [0x3FB70A3D70A3D6FC, 0x3FB70A3D70A3D6FC, 0x3FB70A3D70A3D6FC],
        ]),
        Synthetic("empty everywhere",
                  ThemeColors(bg: "", surface: "",
                              accent: "", accentSoft: "",
                              text: "", textSecondary: "",
                              ringTrack: "", ringFill: ""), [
            "bg":            [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE0000000000000],
            "bgDeep":        [0x3FDEE147AE147AE1, 0x3FDEE147AE147AE1, 0x3FDEE147AE147AE1],
            "surface":       [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE0000000000000],
            "accent":        [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE0000000000000],
            "accentSoft":    [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE0000000000000],
            "ringTrack":     [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE0000000000000],
            "buttonFill":    [0x3FDD70A3D70A3D71, 0x3FDD70A3D70A3D71, 0x3FDD70A3D70A3D71],
            "ringFill":      [0x3FCAE147AE147ADE, 0x3FCAE147AE147ADE, 0x3FCAE147AE147ADE],
            "timerText":     [0x3F2A36E2EB1C41C0, 0x3F2A36E2EB1C41C0, 0x3F2A36E2EB1C41C0],
            "primaryText":   [0x3F2A36E2EB1C41C0, 0x3F2A36E2EB1C41C0, 0x3F2A36E2EB1C41C0],
            "secondaryText": [0x3FB70A3D70A3D6FC, 0x3FB70A3D70A3D6FC, 0x3FB70A3D70A3D6FC],
            "controlIcon":   [0x3FB70A3D70A3D6FC, 0x3FB70A3D70A3D6FC, 0x3FB70A3D70A3D6FC],
            "buttonLabel":   [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "onAccentSoft":  [0x3FB70A3D70A3D6FC, 0x3FB70A3D70A3D6FC, 0x3FB70A3D70A3D6FC],
        ]),
        Synthetic("3-digit with #",
                  ThemeColors(bg: "#fff", surface: "#eee",
                              accent: "#f80", accentSoft: "#fdb",
                              text: "#222", textSecondary: "#666",
                              ringTrack: "#ddd", ringFill: "#f60"), [
            "bg":            [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "bgDeep":        [0x3FEEE147AE147AE1, 0x3FEEE147AE147AE1, 0x3FEEE147AE147AE1],
            "surface":       [0x3FEDDDDDDDDDDDDE, 0x3FEDDDDDDDDDDDDE, 0x3FEDDDDDDDDDDDDE],
            "accent":        [0x3FF0000000000000, 0x3FE1111111111111, 0x0000000000000000],
            "accentSoft":    [0x3FF0000000000000, 0x3FEBBBBBBBBBBBBC, 0x3FE7777777777777],
            "ringTrack":     [0x3FEBBBBBBBBBBBBC, 0x3FEBBBBBBBBBBBBC, 0x3FEBBBBBBBBBBBBC],
            "buttonFill":    [0x3FF0000000000000, 0x3FE1111111111111, 0x0000000000000000],
            "ringFill":      [0x3FEA3D70A3D70A3E, 0x3FD4FDF3B645A1CB, 0x0000000000000000],
            "timerText":     [0x3FC1111111111111, 0x3FC1111111111111, 0x3FC1111111111111],
            "primaryText":   [0x3FC1111111111111, 0x3FC1111111111111, 0x3FC1111111111111],
            "secondaryText": [0x3FD999999999999A, 0x3FD999999999999A, 0x3FD999999999999A],
            "controlIcon":   [0x3FD999999999999A, 0x3FD999999999999A, 0x3FD999999999999A],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FC1111111111111, 0x3FC1111111111111, 0x3FC1111111111111],
        ]),
        Synthetic("3-digit without #",
                  ThemeColors(bg: "fff", surface: "eee",
                              accent: "f80", accentSoft: "fdb",
                              text: "222", textSecondary: "666",
                              ringTrack: "ddd", ringFill: "f60"), [
            "bg":            [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "bgDeep":        [0x3FEEE147AE147AE1, 0x3FEEE147AE147AE1, 0x3FEEE147AE147AE1],
            "surface":       [0x3FEDDDDDDDDDDDDE, 0x3FEDDDDDDDDDDDDE, 0x3FEDDDDDDDDDDDDE],
            "accent":        [0x3FF0000000000000, 0x3FE1111111111111, 0x0000000000000000],
            "accentSoft":    [0x3FF0000000000000, 0x3FEBBBBBBBBBBBBC, 0x3FE7777777777777],
            "ringTrack":     [0x3FEBBBBBBBBBBBBC, 0x3FEBBBBBBBBBBBBC, 0x3FEBBBBBBBBBBBBC],
            "buttonFill":    [0x3FF0000000000000, 0x3FE1111111111111, 0x0000000000000000],
            "ringFill":      [0x3FEA3D70A3D70A3E, 0x3FD4FDF3B645A1CB, 0x0000000000000000],
            "timerText":     [0x3FC1111111111111, 0x3FC1111111111111, 0x3FC1111111111111],
            "primaryText":   [0x3FC1111111111111, 0x3FC1111111111111, 0x3FC1111111111111],
            "secondaryText": [0x3FD999999999999A, 0x3FD999999999999A, 0x3FD999999999999A],
            "controlIcon":   [0x3FD999999999999A, 0x3FD999999999999A, 0x3FD999999999999A],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FC1111111111111, 0x3FC1111111111111, 0x3FC1111111111111],
        ]),
        Synthetic("6-digit without #",
                  ThemeColors(bg: "FFF4E8", surface: "FFFFFF",
                              accent: "F5A97F", accentSoft: "FBD3BE",
                              text: "5A3A2E", textSecondary: "8C7468",
                              ringTrack: "F9DCCB", ringFill: "F08A5D"), [
            "bg":            [0x3FF0000000000000, 0x3FEE9E9E9E9E9E9F, 0x3FED1D1D1D1D1D1D],
            "bgDeep":        [0x3FEEE147AE147AE1, 0x3FED8C4496820726, 0x3FEC184136F988E5],
            "surface":       [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "accent":        [0x3FEEBEBEBEBEBEBF, 0x3FE5353535353535, 0x3FDFDFDFDFDFDFE0],
            "accentSoft":    [0x3FEF7F7F7F7F7F7F, 0x3FEA7A7A7A7A7A7A, 0x3FE7D7D7D7D7D7D8],
            "ringTrack":     [0x3FEF3F3F3F3F3F3F, 0x3FEB9B9B9B9B9B9C, 0x3FE9797979797979],
            "buttonFill":    [0x3FEEBEBEBEBEBEBF, 0x3FE5353535353535, 0x3FDFDFDFDFDFDFE0],
            "ringFill":      [0x3FE77DE44AB1177E, 0x3FDB03F9BC4BA7D0, 0x3FD234C420493F02],
            "timerText":     [0x3FD6969696969697, 0x3FCD1D1D1D1D1D1D, 0x3FC7171717171717],
            "primaryText":   [0x3FD6969696969697, 0x3FCD1D1D1D1D1D1D, 0x3FC7171717171717],
            "secondaryText": [0x3FE029C35CF6902A, 0x3FDAC8DD5839812F, 0x3FD80388A75FB19D],
            "controlIcon":   [0x3FE029C35CF6902A, 0x3FDAC8DD5839812F, 0x3FD80388A75FB19D],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FD6969696969697, 0x3FCD1D1D1D1D1D1D, 0x3FC7171717171717],
        ]),
        Synthetic("6-digit with #",
                  ThemeColors(bg: "#FFF4E8", surface: "#FFFFFF",
                              accent: "#F5A97F", accentSoft: "#FBD3BE",
                              text: "#5A3A2E", textSecondary: "#8C7468",
                              ringTrack: "#F9DCCB", ringFill: "#F08A5D"), [
            "bg":            [0x3FF0000000000000, 0x3FEE9E9E9E9E9E9F, 0x3FED1D1D1D1D1D1D],
            "bgDeep":        [0x3FEEE147AE147AE1, 0x3FED8C4496820726, 0x3FEC184136F988E5],
            "surface":       [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "accent":        [0x3FEEBEBEBEBEBEBF, 0x3FE5353535353535, 0x3FDFDFDFDFDFDFE0],
            "accentSoft":    [0x3FEF7F7F7F7F7F7F, 0x3FEA7A7A7A7A7A7A, 0x3FE7D7D7D7D7D7D8],
            "ringTrack":     [0x3FEF3F3F3F3F3F3F, 0x3FEB9B9B9B9B9B9C, 0x3FE9797979797979],
            "buttonFill":    [0x3FEEBEBEBEBEBEBF, 0x3FE5353535353535, 0x3FDFDFDFDFDFDFE0],
            "ringFill":      [0x3FE77DE44AB1177E, 0x3FDB03F9BC4BA7D0, 0x3FD234C420493F02],
            "timerText":     [0x3FD6969696969697, 0x3FCD1D1D1D1D1D1D, 0x3FC7171717171717],
            "primaryText":   [0x3FD6969696969697, 0x3FCD1D1D1D1D1D1D, 0x3FC7171717171717],
            "secondaryText": [0x3FE029C35CF6902A, 0x3FDAC8DD5839812F, 0x3FD80388A75FB19D],
            "controlIcon":   [0x3FE029C35CF6902A, 0x3FDAC8DD5839812F, 0x3FD80388A75FB19D],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FD6969696969697, 0x3FCD1D1D1D1D1D1D, 0x3FC7171717171717],
        ]),
        Synthetic("lowercase",
                  ThemeColors(bg: "#fff4e8", surface: "#ffffff",
                              accent: "#f5a97f", accentSoft: "#fbd3be",
                              text: "#5a3a2e", textSecondary: "#8c7468",
                              ringTrack: "#f9dccb", ringFill: "#f08a5d"), [
            "bg":            [0x3FF0000000000000, 0x3FEE9E9E9E9E9E9F, 0x3FED1D1D1D1D1D1D],
            "bgDeep":        [0x3FEEE147AE147AE1, 0x3FED8C4496820726, 0x3FEC184136F988E5],
            "surface":       [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "accent":        [0x3FEEBEBEBEBEBEBF, 0x3FE5353535353535, 0x3FDFDFDFDFDFDFE0],
            "accentSoft":    [0x3FEF7F7F7F7F7F7F, 0x3FEA7A7A7A7A7A7A, 0x3FE7D7D7D7D7D7D8],
            "ringTrack":     [0x3FEF3F3F3F3F3F3F, 0x3FEB9B9B9B9B9B9C, 0x3FE9797979797979],
            "buttonFill":    [0x3FEEBEBEBEBEBEBF, 0x3FE5353535353535, 0x3FDFDFDFDFDFDFE0],
            "ringFill":      [0x3FE77DE44AB1177E, 0x3FDB03F9BC4BA7D0, 0x3FD234C420493F02],
            "timerText":     [0x3FD6969696969697, 0x3FCD1D1D1D1D1D1D, 0x3FC7171717171717],
            "primaryText":   [0x3FD6969696969697, 0x3FCD1D1D1D1D1D1D, 0x3FC7171717171717],
            "secondaryText": [0x3FE029C35CF6902A, 0x3FDAC8DD5839812F, 0x3FD80388A75FB19D],
            "controlIcon":   [0x3FE029C35CF6902A, 0x3FDAC8DD5839812F, 0x3FD80388A75FB19D],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FD6969696969697, 0x3FCD1D1D1D1D1D1D, 0x3FC7171717171717],
        ]),
        Synthetic("padded with whitespace",
                  ThemeColors(bg: "  #FFF4E8  ", surface: "\t#FFFFFF\n",
                              accent: " F5A97F", accentSoft: "#FBD3BE ",
                              text: "\n#5A3A2E", textSecondary: "  #8c7468",
                              ringTrack: "#F9DCCB\t", ringFill: " #fff "), [
            "bg":            [0x3FF0000000000000, 0x3FEE9E9E9E9E9E9F, 0x3FED1D1D1D1D1D1D],
            "bgDeep":        [0x3FEEE147AE147AE1, 0x3FED8C4496820726, 0x3FEC184136F988E5],
            "surface":       [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "accent":        [0x3FEEBEBEBEBEBEBF, 0x3FE5353535353535, 0x3FDFDFDFDFDFDFE0],
            "accentSoft":    [0x3FEF7F7F7F7F7F7F, 0x3FEA7A7A7A7A7A7A, 0x3FE7D7D7D7D7D7D8],
            "ringTrack":     [0x3FEF3F3F3F3F3F3F, 0x3FEB9B9B9B9B9B9C, 0x3FE9797979797979],
            "buttonFill":    [0x3FEEBEBEBEBEBEBF, 0x3FE5353535353535, 0x3FDFDFDFDFDFDFE0],
            "ringFill":      [0x3FDFFFFFFFFFFFFE, 0x3FDFFFFFFFFFFFFE, 0x3FDFFFFFFFFFFFFE],
            "timerText":     [0x3FD6969696969697, 0x3FCD1D1D1D1D1D1D, 0x3FC7171717171717],
            "primaryText":   [0x3FD6969696969697, 0x3FCD1D1D1D1D1D1D, 0x3FC7171717171717],
            "secondaryText": [0x3FE029C35CF6902A, 0x3FDAC8DD5839812F, 0x3FD80388A75FB19D],
            "controlIcon":   [0x3FE029C35CF6902A, 0x3FDAC8DD5839812F, 0x3FD80388A75FB19D],
            "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
            "onAccentSoft":  [0x3FD6969696969697, 0x3FCD1D1D1D1D1D1D, 0x3FC7171717171717],
        ]),
        Synthetic("malformed lengths and characters",
                  ThemeColors(bg: "#FFF4E8FF", surface: "#FFF4E",
                              accent: "##F5A97F", accentSoft: "0xFBD3",
                              text: "#GGGGGG", textSecondary: "+8C746",
                              ringTrack: "-00000", ringFill: "#+F6"), [
            "bg":            [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE0000000000000],
            "bgDeep":        [0x3FDEE147AE147AE1, 0x3FDEE147AE147AE1, 0x3FDEE147AE147AE1],
            "surface":       [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE0000000000000],
            "accent":        [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE0000000000000],
            "accentSoft":    [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE0000000000000],
            "ringTrack":     [0x0000000000000000, 0x0000000000000000, 0x0000000000000000],
            "buttonFill":    [0x3FDD70A3D70A3D71, 0x3FDD70A3D70A3D71, 0x3FDD70A3D70A3D71],
            "ringFill":      [0x3FE0000000000000, 0x3FE0000000000000, 0x3FE0000000000000],
            "timerText":     [0x3F2A36E2EB1C41C0, 0x3F2A36E2EB1C41C0, 0x3F2A36E2EB1C41C0],
            "primaryText":   [0x3F2A36E2EB1C41C0, 0x3F2A36E2EB1C41C0, 0x3F2A36E2EB1C41C0],
            "secondaryText": [0x3F71FD82A159AB88, 0x3FBBF82116D968B0, 0x3FA3AD46E07A139C],
            "controlIcon":   [0x3F71FD82A159AB88, 0x3FBBF82116D968B0, 0x3FA3AD46E07A139C],
            "buttonLabel":   [0x3FF0000000000000, 0x3FF0000000000000, 0x3FF0000000000000],
            "onAccentSoft":  [0x3FB70A3D70A3D6FC, 0x3FB70A3D70A3D6FC, 0x3FB70A3D70A3D6FC],
        ]),
    ]

    // MARK: Grid

    /// grey level -> [bg/surface channel, bgDeep channel] bit patterns (all three
    /// channels of a grey are equal).
    private static let gridLevels: [String: [UInt64]] = [
        "#000000": [0x0000000000000000, 0x0000000000000000],
        "#1A1A1A": [0x3FBA1A1A1A1A1A1A, 0x3FB9303A77E88C63],
        "#333333": [0x3FC999999999999A, 0x3FC8B4395810624E],
        "#4D4D4D": [0x3FD3535353535353, 0x3FD2A62B4A02543F],
        "#666666": [0x3FD999999999999A, 0x3FD8B4395810624E],
        "#808080": [0x3FE0101010101010, 0x3FDF0047F60A8566],
        "#999999": [0x3FE3333333333333, 0x3FE2872B020C49BA],
        "#B3B3B3": [0x3FE6767676767676, 0x3FE5AD3251095B46],
        "#CCCCCC": [0x3FE999999999999A, 0x3FE8B4395810624E],
        "#E6E6E6": [0x3FECDCDCDCDCDCDD, 0x3FEBDA40A70D73DA],
        "#FFFFFF": [0x3FF0000000000000, 0x3FEEE147AE147AE1],
    ]

    /// The six tokens the grid holds fixed give these seven roles in every cell.
    private static let gridFixedRoles: Record = [
        "accent":        [0x3FEEBEBEBEBEBEBF, 0x3FE5353535353535, 0x3FDFDFDFDFDFDFE0],
        "accentSoft":    [0x3FEF7F7F7F7F7F7F, 0x3FEA7A7A7A7A7A7A, 0x3FE7D7D7D7D7D7D8],
        "ringTrack":     [0x3FEF3F3F3F3F3F3F, 0x3FEB9B9B9B9B9B9C, 0x3FE9797979797979],
        "ringFill":      [0x3FE77DE44AB1177E, 0x3FDB03F9BC4BA7D0, 0x3FD234C420493F02],
        "buttonFill":    [0x3FEEBEBEBEBEBEBF, 0x3FE5353535353535, 0x3FDFDFDFDFDFDFE0],
        "buttonLabel":   [0x3FC0A3D70A3D70A4, 0x3FBEB851EB851EB8, 0x3FC3333333333333],
        "onAccentSoft":  [0x3FDB8EC1F5285B8F, 0x3FD4C7FB2E6194C8, 0x3FE1D83EA50B71D8],
    ]

    private struct Cell {
        let bg: String
        let surface: String
        let ink: [UInt64]          // timerText and primaryText
        let secondary: [UInt64]    // secondaryText and controlIcon
        init(_ bg: String, _ surface: String, ink: [UInt64], secondary: [UInt64]) {
            self.bg = bg
            self.surface = surface
            self.ink = ink
            self.secondary = secondary
        }
    }

    private static let gridCells: [Cell] = [
        Cell("#000000", "#000000", ink: [0x3FE4511DEAB78451, 0x3FE1AE7B4814E1AE, 0x3FE77AADE114477B], secondary: [0x3FE3D3D3D3D3D3D4, 0x3FE1515151515151, 0x3FD7171717171717]),
        Cell("#000000", "#1A1A1A", ink: [0x3FE62FA87D7B6F25, 0x3FE3F8F6EAA0E688, 0x3FE8D7B0C74E797C], secondary: [0x3FE3D3D3D3D3D3D4, 0x3FE1515151515151, 0x3FD7171717171717]),
        Cell("#000000", "#333333", ink: [0x3FE93949ABF9CCBF, 0x3FE7B1FFD2C46E6A, 0x3FEB0ED57D6D0ABD], secondary: [0x3FE58817739C9255, 0x3FE35F887E40D02C, 0x3FDCD14C2D752338]),
        Cell("#000000", "#4D4D4D", ink: [0x3FEDA9D2C88B1A78, 0x3FED22E574D0F9F1, 0x3FEE4BBC60374180], secondary: [0x3FE92EF180DD05FC, 0x3FE7C7234C420494, 0x3FE48B95D343E7BF]),
        Cell("#000000", "#666666", ink: [0x3FEFC42EADA782A7, 0x3FEFB6B08BAE7F67, 0x3FEFD45FA338B9C1], secondary: [0x3FED5271297B66EE, 0x3FECC5170287A660, 0x3FEB7FFADC23D1E8]),
        Cell("#000000", "#808080", ink: [0x3F8A016DF93CD180, 0x3F86A1E57AFC0180, 0x3F8E0DAB5D8A9800], secondary: [0x3FB9610F239E7FB8, 0x3FB62AA586CE7C80, 0x3FAD8E32091350A8]),
        Cell("#000000", "#999999", ink: [0x3F9A016DF93CD200, 0x3F96A1E57AFC01E0, 0x3F9E0DAB5D8A9880], secondary: [0x3FCAF72015D867BE, 0x3FC78D4FDF3B6454, 0x3FBF671529A485C6]),
        Cell("#000000", "#B3B3B3", ink: [0x3FC521295A816ADC, 0x3FC2638A73ECC1B8, 0x3FC86B1B3C009C38], secondary: [0x3FD3D3D3D3D3D3D3, 0x3FD1515151515150, 0x3FC7171717171716]),
        Cell("#000000", "#CCCCCC", ink: [0x3FCEE1B297F839BE, 0x3FCAE040820B428A, 0x3FD1D81DBF8A4ACB], secondary: [0x3FD89606AA818BC9, 0x3FD579505A9808AC, 0x3FCCA1C078CAB63A]),
        Cell("#000000", "#E6E6E6", ink: [0x3FD4511DEAB78450, 0x3FD1AE7B4814E1AD, 0x3FD77AADE114477A], secondary: [0x3FDC8D3108124FC1, 0x3FD8EFFA37A84C23, 0x3FD09FFC251ADD6D]),
        Cell("#000000", "#FFFFFF", ink: [0x3FD7914BA9DF1E9A, 0x3FD482B7F77461F2, 0x3FDB3C634CC59A98], secondary: [0x3FE0A7B1EF6003DB, 0x3FDD17F940EF037E, 0x3FD36550D5F4ACFF]),
        Cell("#1A1A1A", "#000000", ink: [0x3FE5FC62C92F95FD, 0x3FE3BA2086ED53BA, 0x3FE8B24BE57F18B3], secondary: [0x3FE3D3D3D3D3D3D4, 0x3FE1515151515151, 0x3FD7171717171717]),
        Cell("#1A1A1A", "#1A1A1A", ink: [0x3FE5FC62C92F95FD, 0x3FE3BA2086ED53BA, 0x3FE8B24BE57F18B3], secondary: [0x3FE3D3D3D3D3D3D4, 0x3FE1515151515151, 0x3FD7171717171717]),
        Cell("#1A1A1A", "#333333", ink: [0x3FE930BE0DED288D, 0x3FE7A786C226809D, 0x3FEB089A02752546], secondary: [0x3FE58817739C9255, 0x3FE35F887E40D02C, 0x3FDCD14C2D752338]),
        Cell("#1A1A1A", "#4D4D4D", ink: [0x3FEDCC0140BDAB3E, 0x3FED4CC9B748B125, 0x3FEE64AA4C16D75B], secondary: [0x3FE92EF180DD05FC, 0x3FE7C7234C420494, 0x3FE48B95D343E7BF]),
        Cell("#1A1A1A", "#666666", ink: [0x3FEFCCBA4BB426D8, 0x3FEFC1299C4C6D34, 0x3FEFDA9B1E309F38], secondary: [0x3FED5271297B66EE, 0x3FECC5170287A660, 0x3FEB7FFADC23D1E8]),
        Cell("#1A1A1A", "#808080", ink: [0x3F8C24557C65DDC0, 0x3F894029A27774C0, 0x3F8F9C8A1B83F5C0], secondary: [0x3FB9610F239E7FB8, 0x3FB62AA586CE7C80, 0x3FAD8E32091350A8]),
        Cell("#1A1A1A", "#999999", ink: [0x3F9C24557C65DE40, 0x3F994029A2777500, 0x3F9F9C8A1B83F640], secondary: [0x3FCAF72015D867BE, 0x3FC78D4FDF3B6454, 0x3FBF671529A485C6]),
        Cell("#1A1A1A", "#B3B3B3", ink: [0x3FC51B401D4C6700, 0x3FC2F01F39D99808, 0x3FC7B56794A2F8F4], secondary: [0x3FD3D3D3D3D3D3D3, 0x3FD1515151515150, 0x3FC7171717171716]),
        Cell("#1A1A1A", "#CCCCCC", ink: [0x3FCDE69AD42C3C9A, 0x3FCAD42C3C9EECBA, 0x3FD0CB295E9E1B06], secondary: [0x3FD89606AA818BC9, 0x3FD579505A9808AC, 0x3FCCA1C078CAB63A]),
        Cell("#1A1A1A", "#E6E6E6", ink: [0x3FD358FAC586091A, 0x3FD15C1C9FB220B6, 0x3FD5BB9EF2EAB991], secondary: [0x3FDC8D3108124FC1, 0x3FD8EFFA37A84C23, 0x3FD09FFC251ADD6D]),
        Cell("#1A1A1A", "#FFFFFF", ink: [0x3FD7BEA820F5F3E7, 0x3FD54E232114CB0F, 0x3FDAAC148737581C], secondary: [0x3FE0A7B1EF6003DB, 0x3FDD17F940EF037E, 0x3FD36550D5F4ACFF]),
        Cell("#333333", "#000000", ink: [0x3FE952EC861FB954, 0x3FE7D16B049E37D2, 0x3FEB2187EE54BB22], secondary: [0x3FE58817739C9255, 0x3FE35F887E40D02C, 0x3FDCD14C2D752338]),
        Cell("#333333", "#1A1A1A", ink: [0x3FE952EC861FB954, 0x3FE7D16B049E37D2, 0x3FEB2187EE54BB22], secondary: [0x3FE58817739C9255, 0x3FE35F887E40D02C, 0x3FDCD14C2D752338]),
        Cell("#333333", "#333333", ink: [0x3FE952EC861FB954, 0x3FE7D16B049E37D2, 0x3FEB2187EE54BB22], secondary: [0x3FE58817739C9255, 0x3FE35F887E40D02C, 0x3FDCD14C2D752338]),
        Cell("#333333", "#4D4D4D", ink: [0x3FEDBAEA04A462DA, 0x3FED37D7960CD58A, 0x3FEE583356270C6D], secondary: [0x3FE91742AD956AD2, 0x3FE7AA9267CE9DE0, 0x3FE463C9C7522CE7]),
        Cell("#333333", "#666666", ink: [0x3FEFDDD187CD6F3B, 0x3FEFD61BBD8848CD, 0x3FEFE71214206A25], secondary: [0x3FED47394C2396B1, 0x3FECB78F021B1769, 0x3FEB6D20F16DF2AA]),
        Cell("#333333", "#808080", ink: [0x3F903512415BFB40, 0x3F8E7CB1F16E5B00, 0x3F915D23CBBB5880], secondary: [0x3FB81D8AE7E28F58, 0x3FB5B2AD5A341C48, 0x3FB023496122E078]),
        Cell("#333333", "#999999", ink: [0x3FA03512415BFB80, 0x3F9E7CB1F16E5B80, 0x3FA15D23CBBB58D0], secondary: [0x3FCB8F7A2D953628, 0x3FC8CC33D4CDD73C, 0x3FC271786F0349BA]),
        Cell("#333333", "#B3B3B3", ink: [0x3FC44256D1B2FAA0, 0x3FC30DEF36E4F96C, 0x3FC5B46CBEAA2F44], secondary: [0x3FD2F2A3FF56953F, 0x3FD10C63A24D83FC, 0x3FC95C0598A48562]),
        Cell("#333333", "#CCCCCC", ink: [0x3FCE63823A8C77F8, 0x3FCC94E6D2577628, 0x3FD047518EFFA376], secondary: [0x3FD7410F1675E5B6, 0x3FD4EC4BBB8DAD9F, 0x3FCF1F7B3B558C6E]),
        Cell("#333333", "#E6E6E6", ink: [0x3FD33F05AD9D3AEB, 0x3FD21A09A7598692, 0x3FD49E9A81EE79BA], secondary: [0x3FDC6BF5FF01DFE0, 0x3FD99295737445FC, 0x3FD30504327B640B]),
        Cell("#333333", "#FFFFFF", ink: [0x3FD648F919DE7A1F, 0x3FD4F5BA55FBDF31, 0x3FD7E01138219A6D], secondary: [0x3FE05D308B10982C, 0x3FDD727D8CB46FA0, 0x3FD5E6BF03D3E791]),
        Cell("#4D4D4D", "#000000", ink: [0x3FEDA9D2C88B1A78, 0x3FED22E574D0F9F2, 0x3FEE4BBC60374180], secondary: [0x3FE92EF180DD05FC, 0x3FE7C7234C420494, 0x3FE48B95D343E7BF]),
        Cell("#4D4D4D", "#1A1A1A", ink: [0x3FEDA9D2C88B1A78, 0x3FED22E574D0F9F2, 0x3FEE4BBC60374180], secondary: [0x3FE92EF180DD05FC, 0x3FE7C7234C420494, 0x3FE48B95D343E7BF]),
        Cell("#4D4D4D", "#333333", ink: [0x3FEDA9D2C88B1A78, 0x3FED22E574D0F9F2, 0x3FEE4BBC60374180], secondary: [0x3FE92EF180DD05FC, 0x3FE7C7234C420494, 0x3FE48B95D343E7BF]),
        Cell("#4D4D4D", "#4D4D4D", ink: [0x3FEDA9D2C88B1A78, 0x3FED22E574D0F9F2, 0x3FEE4BBC60374180], secondary: [0x3FE92EF180DD05FC, 0x3FE7C7234C420494, 0x3FE48B95D343E7BF]),
        Cell("#4D4D4D", "#666666", ink: [0x3FEFF40955EE4D55, 0x3FEFF1568256197B, 0x3FEFF74653D82527], secondary: [0x3FED231382EC3098, 0x3FEC8BF539A0D8F7, 0x3FEB3062C4405C37]),
        Cell("#4D4D4D", "#808080", ink: [0x3F92FC0C0577BE80, 0x3F92A5B192714340, 0x3F9363ABC2B2B8C0], secondary: [0x3FB82D10CDA0FB68, 0x3FB6D3A701870E88, 0x3FB3B933AC183A90]),
        Cell("#4D4D4D", "#999999", ink: [0x3F92FC0C0577BE80, 0x3F92A5B192714340, 0x3F9363ABC2B2B8C0], secondary: [0x3FCA30D23419106C, 0x3FC8BA9F96FCFA7C, 0x3FC55DF7FA6F94D4]),
        Cell("#4D4D4D", "#B3B3B3", ink: [0x3FC2FC0C0577BEF8, 0x3FC2A5B1927143C0, 0x3FC363ABC2B2B938], secondary: [0x3FD221CC9A38BC9E, 0x3FD11EBD41254AF7, 0x3FCD95CD822457EE]),
        Cell("#4D4D4D", "#CCCCCC", ink: [0x3FCC7A1208339E7C, 0x3FCBF88A5BA9E5A8, 0x3FCD1581A40C15E0], secondary: [0x3FD6294F6728E68A, 0x3FD4ECAE6C1122BD, 0x3FD2146F5DC0E069]),
        Cell("#4D4D4D", "#E6E6E6", ink: [0x3FD2FC0C0577BF00, 0x3FD2A5B1927143CA, 0x3FD363ABC2B2B944], secondary: [0x3FDB32B2E7551AF0, 0x3FD9AE1BE1B7F075, 0x3FD6305A219B41F6]),
        Cell("#4D4D4D", "#FFFFFF", ink: [0x3FD68B4E467E32D2, 0x3FD624C2DDE68082, 0x3FD7065BF7343C02], secondary: [0x3FDF3A35B44544DB, 0x3FDD7C0D0CA3C83C, 0x3FD979E2BE49F667]),
        Cell("#666666", "#000000", ink: [0x3FEFAA8BD3819612, 0x3FEF974559D4B600, 0x3FEFC1AD3251095D], secondary: [0x3FED5271297B66EE, 0x3FECC5170287A660, 0x3FEB7FFADC23D1E8]),
        Cell("#666666", "#1A1A1A", ink: [0x3FEFAA8BD3819612, 0x3FEF974559D4B600, 0x3FEFC1AD3251095D], secondary: [0x3FED5271297B66EE, 0x3FECC5170287A660, 0x3FEB7FFADC23D1E8]),
        Cell("#666666", "#333333", ink: [0x3FEFAA8BD3819612, 0x3FEF974559D4B600, 0x3FEFC1AD3251095D], secondary: [0x3FED5271297B66EE, 0x3FECC5170287A660, 0x3FEB7FFADC23D1E8]),
        Cell("#666666", "#4D4D4D", ink: [0x3FEFAA8BD3819612, 0x3FEF974559D4B600, 0x3FEFC1AD3251095D], secondary: [0x3FED5271297B66EE, 0x3FECC5170287A660, 0x3FEB7FFADC23D1E8]),
        Cell("#666666", "#666666", ink: [0x3FEFFE4A79FD78C3, 0x3FEFFDE7C97A03A4, 0x3FEFFEC0E768054F], secondary: [0x3FED5271297B66EE, 0x3FECC5170287A660, 0x3FEB7FFADC23D1E8]),
        Cell("#666666", "#808080", ink: [0x3F944430875D2C40, 0x3F9437DA76EE8860, 0x3F9452FE34AEBDC0], secondary: [0x3FB775275462B8A0, 0x3FB70412686C84F8, 0x3FB5FFFBE34FDB00]),
        Cell("#666666", "#999999", ink: [0x3F944430875D2C40, 0x3F9437DA76EE8860, 0x3F9452FE34AEBDC0], secondary: [0x3FC775275462B8B0, 0x3FC70412686C850C, 0x3FC5FFFBE34FDB14]),
        Cell("#666666", "#B3B3B3", ink: [0x3FC44430875D2CC8, 0x3FC437DA76EE88E8, 0x3FC452FE34AEBE40], secondary: [0x3FD197DD7F4A0A8A, 0x3FD1430DCE5163CE, 0x3FD07FFCEA7BE454]),
        Cell("#666666", "#CCCCCC", ink: [0x3FCBDDC2BA201D9C, 0x3FCBCCCC6387FC44, 0x3FCBF21D887045A0], secondary: [0x3FD51CA3658C0CA8, 0x3FD4B6DD5DFB4494, 0x3FD3CCC919617866]),
        Cell("#666666", "#E6E6E6", ink: [0x3FD1BBAA76718738, 0x3FD1B0DF2810B7D2, 0x3FD1C89E6E18E680], secondary: [0x3FD9CDAB433964CE, 0x3FD9514772DDC59A, 0x3FD8332EAD3E3DD4]),
        Cell("#666666", "#FFFFFF", ink: [0x3FD588738FD2FFA2, 0x3FD57B581E5D7180, 0x3FD5982E17F9AA30], secondary: [0x3FDD5271297B66EC, 0x3FDCC5170287A65E, 0x3FDB7FFADC23D1E6]),
        Cell("#808080", "#000000", ink: [0x3FE3528DF24C6916, 0x3FE34AD8280742A8, 0x3FE35BCE7E9F6400], secondary: [0x3FDE8F5A83E2809B, 0x3FDE181A8FB4FB05, 0x3FDD05D4447F7AFA]),
        Cell("#808080", "#1A1A1A", ink: [0x3FE5395F0DF42620, 0x3FE532D155395F10, 0x3FE5413C52077B67], secondary: [0x3FE102780627BE11, 0x3FE0CD0314484D38, 0x3FE0520FB4C66344]),
        Cell("#808080", "#333333", ink: [0x3FE864BB91610BDC, 0x3FE8601B4B378E67, 0x3FE86A48B25FA268], secondary: [0x3FE3E474A2828FAC, 0x3FE3B94768FF5210, 0x3FE355F8FE517790]),
        Cell("#808080", "#4D4D4D", ink: [0x3FED76E93075AEA2, 0x3FED755E6E67DA26, 0x3FED78C2E61FE0D1], secondary: [0x3FE7EDA31701B51F, 0x3FE7D0DA45FF8C0C, 0x3FE78EA5FEE0FA62]),
        Cell("#808080", "#666666", ink: [0x3FEF5DBA4C1D6BAC, 0x3FEF5D579B99F68D, 0x3FEF5E30B987F838], secondary: [0x3FED1E0363A52E69, 0x3FED13BBAB48FB2C, 0x3FECFC16B674EBB8]),
        Cell("#808080", "#808080", ink: [0x3F291565ADC4B340, 0x3F22EA5D7672C200, 0x3F303E1E2B46B740], secondary: [0x3FB9610F239E7FB8, 0x3FB62AA586CE7C80, 0x3FAD8E32091350A8]),
        Cell("#808080", "#999999", ink: [0x3F8398B76FC1ACA0, 0x3F7D8E3209135000, 0x3F89610F239E7F00], secondary: [0x3FB9610F239E7FB8, 0x3FB62AA586CE7C80, 0x3FAD8E32091350A8]),
        Cell("#808080", "#B3B3B3", ink: [0x3F8398B76FC1ACA0, 0x3F7D8E3209135000, 0x3F89610F239E7F00], secondary: [0x3FB9610F239E7FB8, 0x3FB62AA586CE7C80, 0x3FAD8E32091350A8]),
        Cell("#808080", "#CCCCCC", ink: [0x3F8398B76FC1ACA0, 0x3F7D8E3209135000, 0x3F89610F239E7F00], secondary: [0x3FB9610F239E7FB8, 0x3FB62AA586CE7C80, 0x3FAD8E32091350A8]),
        Cell("#808080", "#E6E6E6", ink: [0x3F8398B76FC1ACA0, 0x3F7D8E3209135000, 0x3F89610F239E7F00], secondary: [0x3FB9610F239E7FB8, 0x3FB62AA586CE7C80, 0x3FAD8E32091350A8]),
        Cell("#808080", "#FFFFFF", ink: [0x3F8398B76FC1ACA0, 0x3F7D8E3209135000, 0x3F89610F239E7F00], secondary: [0x3FB9610F239E7FB8, 0x3FB62AA586CE7C80, 0x3FAD8E32091350A8]),
        Cell("#999999", "#000000", ink: [0x3FE3130C7EC60B45, 0x3FE2F2AA93A39D10, 0x3FE339E865BC291E], secondary: [0x3FDEA897635E7428, 0x3FDD883BA3443D45, 0x3FDAF102363B256E]),
        Cell("#999999", "#1A1A1A", ink: [0x3FE4EBC1913C09A9, 0x3FE4CFFFEC4318EA, 0x3FE50D10573390F6], secondary: [0x3FE0D844D013A92A, 0x3FE05532617C1BDA, 0x3FDE4F765FD8ADAC]),
        Cell("#999999", "#333333", ink: [0x3FE89D2BB6280673, 0x3FE88AAA9D82109E, 0x3FE8B3603A2260A5], secondary: [0x3FE3E0370CDC8755, 0x3FE3775B81301648, 0x3FE2862F5989DF12]),
        Cell("#999999", "#4D4D4D", ink: [0x3FED89B93CB80229, 0x3FED838E3480B038, 0x3FED91201360CAE5], secondary: [0x3FE86C226809D496, 0x3FE82A9930BE0DEF, 0x3FE793DD97F62B6D]),
        Cell("#999999", "#666666", ink: [0x3FEF626E4F2E008E, 0x3FEF60E38D202C12, 0x3FEF644804D832BD], secondary: [0x3FECF80DC33721D8, 0x3FECDDD6E04C0595, 0x3FECA18BD66277C8]),
        Cell("#999999", "#808080", ink: [0x3F491565ADC4B3C0, 0x3F42EA5D7672C260, 0x3F503E1E2B46B7A0], secondary: [0x3FBAF72015D867BC, 0x3FB78D4FDF3B6453, 0x3FAF671529A485C4]),
        Cell("#999999", "#999999", ink: [0x3FA398B76FC1AD10, 0x3F9D8E3209135090, 0x3FA9610F239E7FA0], secondary: [0x3FCAF72015D867BE, 0x3FC78D4FDF3B6454, 0x3FBF671529A485C6]),
        Cell("#999999", "#B3B3B3", ink: [0x3FA398B76FC1AD10, 0x3F9D8E3209135090, 0x3FA9610F239E7FA0], secondary: [0x3FCAF72015D867BE, 0x3FC78D4FDF3B6454, 0x3FBF671529A485C6]),
        Cell("#999999", "#CCCCCC", ink: [0x3FA398B76FC1AD10, 0x3F9D8E3209135090, 0x3FA9610F239E7FA0], secondary: [0x3FCAF72015D867BE, 0x3FC78D4FDF3B6454, 0x3FBF671529A485C6]),
        Cell("#999999", "#E6E6E6", ink: [0x3FA398B76FC1AD10, 0x3F9D8E3209135090, 0x3FA9610F239E7FA0], secondary: [0x3FCAF72015D867BE, 0x3FC78D4FDF3B6454, 0x3FBF671529A485C6]),
        Cell("#999999", "#FFFFFF", ink: [0x3FA398B76FC1AD10, 0x3F9D8E3209135090, 0x3FA9610F239E7FA0], secondary: [0x3FCAF72015D867BE, 0x3FC78D4FDF3B6454, 0x3FBF671529A485C6]),
        Cell("#B3B3B3", "#000000", ink: [0x3FE36EB8DC15D6C3, 0x3FE2BEEE71ED375B, 0x3FE441ABC1E02FA6], secondary: [0x3FDF4FF3CAD51282, 0x3FDD747EBC2CD0A6, 0x3FD92EF180DD05FA]),
        Cell("#B3B3B3", "#1A1A1A", ink: [0x3FE500E1C0931BEC, 0x3FE46710A3AF9070, 0x3FE5B97649A429B2], secondary: [0x3FE16C4D954357D2, 0x3FE098465AD5B6FE, 0x3FDD6138427FF094]),
        Cell("#B3B3B3", "#333333", ink: [0x3FE8AB412B0CBD49, 0x3FE844B5C2750AF7, 0x3FE9264EDBC2C678], secondary: [0x3FE412CB1D088DAD, 0x3FE36550D5F4AD00, 0x3FE1D651327A283E]),
        Cell("#B3B3B3", "#4D4D4D", ink: [0x3FEDE7C97A03A3CF, 0x3FEDCA7D12FCDE93, 0x3FEE0AF1F5A55D4A], secondary: [0x3FE87D9C54A69218, 0x3FE810624DD2F1AC, 0x3FE71529A485CD7E]),
        Cell("#B3B3B3", "#666666", ink: [0x3FEF79F25E80E8F7, 0x3FEF729F44BF37A8, 0x3FEF82BC7D695755], secondary: [0x3FECE86D8C449684, 0x3FECBB73C5B13658, 0x3FEC5402169172BE]),
        Cell("#B3B3B3", "#808080", ink: [0x3F6DC968BE5995C0, 0x3F66764EFCA84700, 0x3F7349C3D363FA20], secondary: [0x3FBAF72015D867BE, 0x3FB78D4FDF3B6454, 0x3FAF671529A485C6]),
        Cell("#B3B3B3", "#999999", ink: [0x3FA47A7802DD9780, 0x3F9EE2AC9B676264, 0x3FAA856D42A978AC], secondary: [0x3FCBC2288EF55BC1, 0x3FC83EA50B71D83D, 0x3FC029C35CF69029]),
        Cell("#B3B3B3", "#B3B3B3", ink: [0x3FC74559D4B5FDA8, 0x3FC18C6DB56377F0, 0x3FCE2341FA4C37B8], secondary: [0x3FD3D3D3D3D3D3D3, 0x3FD1515151515150, 0x3FC7171717171716]),
        Cell("#B3B3B3", "#CCCCCC", ink: [0x3FC74559D4B5FDA8, 0x3FC18C6DB56377F0, 0x3FCE2341FA4C37B8], secondary: [0x3FD3D3D3D3D3D3D3, 0x3FD1515151515150, 0x3FC7171717171716]),
        Cell("#B3B3B3", "#E6E6E6", ink: [0x3FC74559D4B5FDA8, 0x3FC18C6DB56377F0, 0x3FCE2341FA4C37B8], secondary: [0x3FD3D3D3D3D3D3D3, 0x3FD1515151515150, 0x3FC7171717171716]),
        Cell("#B3B3B3", "#FFFFFF", ink: [0x3FC74559D4B5FDA8, 0x3FC18C6DB56377F0, 0x3FCE2341FA4C37B8], secondary: [0x3FD3D3D3D3D3D3D3, 0x3FD1515151515150, 0x3FC7171717171716]),
        Cell("#CCCCCC", "#000000", ink: [0x3FE3A8B3C2EAA5D6, 0x3FE29A13BA6F7A8B, 0x3FE4ED73CD180CFE], secondary: [0x3FDFAE38AA88F2A0, 0x3FDD20EAD9A5A0B6, 0x3FD7425179346450]),
        Cell("#CCCCCC", "#1A1A1A", ink: [0x3FE58EBF7D8B78A2, 0x3FE4A9C1EC85B676, 0x3FE6A1895EC594D7], secondary: [0x3FE16AB5AA9B73B8, 0x3FE043ED17479CCF, 0x3FDB3BD92273F6A0]),
        Cell("#CCCCCC", "#333333", ink: [0x3FE8E1540424E987, 0x3FE84532C42C9F51, 0x3FE99CAF1DB54294], secondary: [0x3FE491E85549688A, 0x3FE3AADC6C3135B8, 0x3FE197743A798DA0]),
        Cell("#CCCCCC", "#4D4D4D", ink: [0x3FEDA07156B6F885, 0x3FED6C664164351E, 0x3FEDDEE509E71634], secondary: [0x3FE882E7AAA2DA90, 0x3FE7EB87965534DA, 0x3FE68F5DCE090485]),
        Cell("#CCCCCC", "#666666", ink: [0x3FEF867D1157CB51, 0x3FEF7C14737A7109, 0x3FEF92FA9B949E0C], secondary: [0x3FECD8CD55520B32, 0x3FEC9910AB16671A, 0x3FEC067856C06DB4]),
        Cell("#CCCCCC", "#808080", ink: [0x3F752A0DCA9DF7C0, 0x3F6FEB7DB7E1A840, 0x3F7B68D2E9075600], secondary: [0x3FB991C97E2053E8, 0x3FB65534D918FEC0, 0x3FADC6F12176A900]),
        Cell("#CCCCCC", "#999999", ink: [0x3FA284CC114A395C, 0x3F9BEE0E00E573E0, 0x3FA7FBB88BE66BE0], secondary: [0x3FCB894F255DE43C, 0x3FC80CFDD61AEAFD, 0x3FC008A939674753]),
        Cell("#CCCCCC", "#B3B3B3", ink: [0x3FC725FF159CC7CA, 0x3FC174C8C08F687E, 0x3FCDFAA6AEE006EE], secondary: [0x3FD3AB388867A307, 0x3FD12DD9E2133A23, 0x3FC6E7CD2D6EF82E]),
        Cell("#CCCCCC", "#CCCCCC", ink: [0x3FD088DAC64B6A22, 0x3FC8EFFA37A84C21, 0x3FD569E4C60DBBCF], secondary: [0x3FD89606AA818BC9, 0x3FD579505A9808AC, 0x3FCCA1C078CAB63A]),
        Cell("#CCCCCC", "#E6E6E6", ink: [0x3FD088DAC64B6A22, 0x3FC8EFFA37A84C21, 0x3FD569E4C60DBBCF], secondary: [0x3FD89606AA818BC9, 0x3FD579505A9808AC, 0x3FCCA1C078CAB63A]),
        Cell("#CCCCCC", "#FFFFFF", ink: [0x3FD088DAC64B6A22, 0x3FC8EFFA37A84C21, 0x3FD569E4C60DBBCF], secondary: [0x3FD89606AA818BC9, 0x3FD579505A9808AC, 0x3FCCA1C078CAB63A]),
        Cell("#E6E6E6", "#000000", ink: [0x3FE3A7E13949ABFA, 0x3FE2209760144DA6, 0x3FE57D6D0ABCE9F9], secondary: [0x3FE0671592E9564B, 0x3FDD9FFAE94C6BF6, 0x3FD64F58C47E0A89]),
        Cell("#E6E6E6", "#1A1A1A", ink: [0x3FE5C8BA646047B6, 0x3FE484E73507F9A4, 0x3FE74D5169FD722F], secondary: [0x3FE1D2139CD41FE7, 0x3FE05FFDAFDCEB41, 0x3FDA199684157DF1]),
        Cell("#E6E6E6", "#333333", ink: [0x3FE8C38407198822, 0x3FE7DE23C59050D6, 0x3FE9D6C455BE30E2], secondary: [0x3FE4A80FB0A9B320, 0x3FE37FFE264A55CE, 0x3FE0D70901A23261]),
        Cell("#E6E6E6", "#4D4D4D", ink: [0x3FEDDF26D4E96448, 0x3FED9BB02B0C5405, 0x3FEE301BA0BF77CC], secondary: [0x3FE88E4A4BEF5D8E, 0x3FE7CBFEC920C850, 0x3FE60D1DE9127110]),
        Cell("#E6E6E6", "#666666", ink: [0x3FEF9307C42EADAB, 0x3FEF8589A235AA6A, 0x3FEFA338B9BFE4C5], secondary: [0x3FED2A03EC2A6CCA, 0x3FECDFFF89929576, 0x3FEC35C240688C9C]),
        Cell("#E6E6E6", "#808080", ink: [0x3F7B6F67360F24C0, 0x3F74B056398D84C0, 0x3F81C3F0FF5558E0], secondary: [0x3FB92016AAF164DC, 0x3FB5F1E66E6B243C, 0x3FAD4288933985A8]),
        Cell("#E6E6E6", "#999999", ink: [0x3FA4938D688B5C30, 0x3F9F0881565447E0, 0x3FAAA5E97F000610], secondary: [0x3FCB68D2E90756CC, 0x3FC7F09E49E93ED8, 0x3FBFEB7DB7E1A920]),
        Cell("#E6E6E6", "#B3B3B3", ink: [0x3FC725FF159CC7C9, 0x3FC174C8C08F687E, 0x3FCDFAA6AEE006EE], secondary: [0x3FD36A400FBA8827, 0x3FD0F51AC9AFE1DA, 0x3FC69C23B7952D24]),
        Cell("#E6E6E6", "#CCCCCC", ink: [0x3FD0B7E2E4F13AF6, 0x3FC936E916247A7F, 0x3FD5A6CDB7300503], secondary: [0x3FD88DE79B6BE86E, 0x3FD57238778B9DA3, 0x3FCC984B4A0F7CDA]),
        Cell("#E6E6E6", "#E6E6E6", ink: [0x3FD56F08A23BD570, 0x3FD029C35CF6902A, 0x3FDBC2288EF55BC2], secondary: [0x3FDC8D3108124FC1, 0x3FD8EFFA37A84C23, 0x3FD09FFC251ADD6D]),
        Cell("#E6E6E6", "#FFFFFF", ink: [0x3FD56F08A23BD570, 0x3FD029C35CF6902A, 0x3FDBC2288EF55BC2], secondary: [0x3FDC8D3108124FC1, 0x3FD8EFFA37A84C23, 0x3FD09FFC251ADD6D]),
        Cell("#FFFFFF", "#000000", ink: [0x3FE42222F4ABC31C, 0x3FE22C35381616E9, 0x3FE67C73709291C0], secondary: [0x3FE0A7B1EF6003DB, 0x3FDD17F940EF037E, 0x3FD36550D5F4ACFF]),
        Cell("#FFFFFF", "#1A1A1A", ink: [0x3FE5AA1E7200F442, 0x3FE3F4F48BB02478, 0x3FE7B6B71FFB8734], secondary: [0x3FE230868AA336AC, 0x3FE04AC9C39EC192, 0x3FD7DB2F26F5CEE6]),
        Cell("#FFFFFF", "#333333", ink: [0x3FE91C144C00A2D8, 0x3FE7F8A307CAC2FC, 0x3FEA79CF6AA7AF79], secondary: [0x3FE4F39ED54F5EF0, 0x3FE36F07CFB23475, 0x3FDFE28C1F2B0BEA]),
        Cell("#FFFFFF", "#4D4D4D", ink: [0x3FEDB406C400364A, 0x3FED52E10298EBAC, 0x3FEE289A78E28FD4], secondary: [0x3FE8F0FACF647CA8, 0x3FE7F8B6C4B1DA68, 0x3FE5BDB3DF4A3208]),
        Cell("#FFFFFF", "#666666", ink: [0x3FEF9E0120AAB3B9, 0x3FEF8DD02B197CA0, 0x3FEFB16F1425C2A6], secondary: [0x3FED3CE7B553D7BE, 0x3FECDBC1F3EC8D1F, 0x3FEBFC5183E56180]),
        Cell("#FFFFFF", "#808080", ink: [0x3F80760ABA091620, 0x3F78D39AAB769F40, 0x3F85518798CCD100], secondary: [0x3FBAA5E97F00061C, 0x3FB7466100BF35F4, 0x3FAF0881565447EC]),
        Cell("#FFFFFF", "#999999", ink: [0x3FA4938D688B5C28, 0x3F9F0881565447D0, 0x3FAAA5E97F000608], secondary: [0x3FCBFB01F88CD344, 0x3FC8704C40C8C57C, 0x3FC04ADD8085D8FD]),
        Cell("#FFFFFF", "#B3B3B3", ink: [0x3FC6A24EBFCC7F13, 0x3FC1117A55E18DFD, 0x3FCD501A7219A060], secondary: [0x3FD351E2E2799E12, 0x3FD0DFD3208AA0BE, 0x3FC67FC42B6380FE]),
        Cell("#FFFFFF", "#CCCCCC", ink: [0x3FD0F9BB0FD95F50, 0x3FC99A3780D254FE, 0x3FD5FC13D593384A], secondary: [0x3FD8A644C8ACD282, 0x3FD5878020B0DEBF, 0x3FCCB4AAD64128FF]),
        Cell("#FFFFFF", "#E6E6E6", ink: [0x3FD59AEE142BEDAB, 0x3FD04ADD8085D8FF, 0x3FDBFB01F88CD347], secondary: [0x3FDD501A7219A063, 0x3FD99A3780D254FE, 0x3FD1117A55E18DFF]),
        Cell("#FFFFFF", "#FFFFFF", ink: [0x3FD9B870C2AE3352, 0x3FD36550D5F4ACFF, 0x3FE0A7B1EF6003DB], secondary: [0x3FE0A7B1EF6003DB, 0x3FDD17F940EF037E, 0x3FD36550D5F4ACFF]),
    ]
}
