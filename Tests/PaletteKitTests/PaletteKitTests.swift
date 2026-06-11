// PaletteKit tests — the derive recipe must reproduce the lean trio
// (border = neutral@0.10, hover = neutral@0.05, selection = primary@0.18),
// so dark presets stay pixel-correct while omitting the trio. Also:
// overrides win, the system preset resolves to dynamic colors, bg
// override, complement.

import XCTest
import AppKit
@testable import Palette
@testable import PaletteKit

@MainActor
final class PaletteKitTests: XCTestCase {

    private func comps(_ c: NSColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let s = c.usingColorSpace(.sRGB) ?? c
        return (s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent)
    }

    /// The dark-editor recipe: border = white@0.10, hover = white@0.05,
    /// selection = primary@0.18 — DERIVED, not stored.
    func testDarkRecipeDerivesTrio() {
        let p = resolve(.terminal)            // primary 0x33FF66, dark bg
        let d = comps(p.border)
        XCTAssertEqual(d.r, 1, accuracy: 0.01); XCTAssertEqual(d.a, 0.10, accuracy: 0.001)
        let h = comps(p.hover)
        XCTAssertEqual(h.r, 1, accuracy: 0.01); XCTAssertEqual(h.a, 0.05, accuracy: 0.001)
        let s = comps(p.selection)            // primary @ 0.18
        XCTAssertEqual(s.r, CGFloat(0x33) / 255, accuracy: 0.01)
        XCTAssertEqual(s.g, CGFloat(0xFF) / 255, accuracy: 0.01)
        XCTAssertEqual(s.b, CGFloat(0x66) / 255, accuracy: 0.01)
        XCTAssertEqual(s.a, 0.18, accuracy: 0.001)
    }

    /// Light themes derive BLACK neutral ink (not white).
    func testLightRecipeUsesBlackInk() {
        // A synthetic light spec with no overrides exercises the derive
        // branch (the catalog's light presets store the trio explicitly).
        let lightNoTrio = ThemeSpec(
            background: HexColor(0xFAFAF8), foreground: HexColor(0x1C1C1E),
            muted: HexColor(0x8A8A8E), primary: HexColor(0x3B82F6), font: .system)
        let p = resolve(lightNoTrio)
        let d = comps(p.border)
        XCTAssertEqual(d.r, 0, accuracy: 0.01)   // black ink
        XCTAssertEqual(d.a, 0.10, accuracy: 0.001)
    }

    /// An explicit override must win over the derived value.
    func testOverrideWins() {
        let p = resolve(.chomp)   // border = wall-blue #2121FF @ 0.55 (explicit)
        let d = comps(p.border)
        XCTAssertEqual(d.r, CGFloat(0x21) / 255, accuracy: 0.01)
        XCTAssertEqual(d.b, CGFloat(0xFF) / 255, accuracy: 0.01)
        XCTAssertEqual(d.a, 0.55, accuracy: 0.001)
    }

    func testSystemPresetResolvesDynamicColors() {
        let p = resolve(.system)
        XCTAssertNil(p.background)                   // vibrancy
        XCTAssertEqual(p.foreground, NSColor.labelColor)
        XCTAssertEqual(p.primary, NSColor.controlAccentColor)
        XCTAssertNotNil(p.vibrancyMaterial)         // hint emitted
    }

    func testSystemPresetMaterialOverride() {
        let p = resolve(.system, material: .menu, forceDark: true)
        XCTAssertEqual(p.vibrancyMaterial, .menu)
        XCTAssertTrue(p.forceDarkAqua)
    }

    /// bg override (shared primary/foreground, app-chosen background).
    func testBgOverride() {
        let p = resolve(.terminal, bgOverride: HexColor(0x111111))
        let b = comps(p.background!)
        XCTAssertEqual(b.r, CGFloat(0x11) / 255, accuracy: 0.01)
        // primary stays canonical (0x33FF66 → green channel saturated)
        XCTAssertEqual(comps(p.primary).g, 1, accuracy: 0.01)
    }

    /// secondary omitted ⇒ derived complement (not nil).
    func testSecondaryDerived() {
        let noSecondary = ThemeSpec(
            background: HexColor(0x101010), foreground: HexColor(0xEEEEEE),
            muted: HexColor(0x888888), primary: HexColor(0x3B82F6), font: .mono)
        let p = resolve(noSecondary)
        // complement of blue is in the orange/amber range — at minimum,
        // it must differ from the primary.
        XCTAssertNotEqual(comps(p.secondary).r, comps(p.primary).r, accuracy: 0.001)
    }

    /// tertiary (a first-class field) derives foreground@0.55 when the
    /// spec doesn't author it.
    func testTertiaryDerivesFadedForeground() {
        let p = resolve(.terminal)               // foreground 0x9BFEDA, no tertiary
        let t = comps(p.tertiary)
        XCTAssertEqual(t.a, 0.55, accuracy: 0.001)
        XCTAssertEqual(t.r, CGFloat(0x9B) / 255, accuracy: 0.01)
    }

    /// An authored tertiary wins over the derive.
    func testTertiaryOverrideWins() {
        let spec = ThemeSpec(
            background: HexColor(0x101010), foreground: HexColor(0xEEEEEE),
            muted: HexColor(0x888888), primary: HexColor(0x3B82F6), font: .mono,
            tertiary: HexColor(0x40C0FF, 0.7))
        let t = comps(resolve(spec).tertiary)
        XCTAssertEqual(t.r, CGFloat(0x40) / 255, accuracy: 0.01)
        XCTAssertEqual(t.a, 0.70, accuracy: 0.001)
    }

    /// The `system` preset's selection is the unified family default 0.18.
    func testSystemSelectionIsUnified018() {
        XCTAssertEqual(comps(resolve(.system).selection).a, 0.18, accuracy: 0.001)
    }

    /// `.systemDynamic` = a concrete bg with live OS inks — the case the
    /// old `background == nil` gate could not express.
    func testSystemDynamicKeepsConcreteBgWithOSInks() {
        let pill = ThemeSpec(
            background: HexColor(0x000000), foreground: HexColor(0x000000),
            muted: HexColor(0x000000), primary: HexColor(systemPrimarySentinel),
            font: .menu, backgroundMode: .systemDynamic)
        let p = resolve(pill)
        XCTAssertNotNil(p.background)                         // concrete fill kept
        XCTAssertEqual(comps(p.background!).r, 0, accuracy: 0.01)
        XCTAssertEqual(p.foreground, NSColor.labelColor)      // OS ink, not 0x000000
        XCTAssertEqual(p.primary, NSColor.controlAccentColor)
        XCTAssertNil(p.vibrancyMaterial)                      // no vibrancy for a fill
    }

    /// ink(tier, root) is an alpha-over tint of the named base.
    func testInkTiers() {
        let p = resolve(.terminal)                            // foreground 0x9BFEDA
        let subtle = comps(p.ink(.subtle, of: .foreground))
        XCTAssertEqual(subtle.r, CGFloat(0x9B) / 255, accuracy: 0.01)
        XCTAssertEqual(subtle.a, 0.16, accuracy: 0.001)
        XCTAssertEqual(comps(p.ink(.faint, of: .primary)).a, 0.06, accuracy: 0.001)
        XCTAssertEqual(comps(p.ink(.wash, of: .primary)).a, 0.30, accuracy: 0.001)
        XCTAssertEqual(comps(p.ink(.strong, of: .muted)).a, 0.55, accuracy: 0.001)
    }

    /// onPrimary picks the higher-contrast foreground off the OPAQUE
    /// primary; onPrimaryStroke is the same ink @0.4.
    func testOnPrimaryContrast() {
        // light primary → black foreground
        let light = ThemeSpec(background: HexColor(0x101010), foreground: HexColor(0xEEEEEE),
            muted: HexColor(0x888888), primary: HexColor(0xFFE000), font: .mono)
        XCTAssertEqual(resolve(light).onPrimary(), NSColor.black)
        // dark primary → white foreground, stroke @0.4
        let dark = ThemeSpec(background: HexColor(0xF0F0F0), foreground: HexColor(0x111111),
            muted: HexColor(0x888888), primary: HexColor(0x202060), font: .mono)
        let dp = resolve(dark)
        XCTAssertEqual(comps(dp.onPrimary()).r, 1, accuracy: 0.01)
        XCTAssertEqual(comps(dp.onPrimaryStroke).a, 0.40, accuracy: 0.001)
    }

    func testPalInstallAndRead() {
        setPalette(named: "dracula")
        XCTAssertEqual(comps(pal.primary).r, CGFloat(0xBD) / 255, accuracy: 0.01)
        setPalette(resolve(.terminal))
        XCTAssertEqual(comps(pal.primary).g, 1, accuracy: 0.01)   // 0x33FF66
    }

    func testNSColorHexInit() {
        let c = comps(NSColor(hex: 0x9ECE6A))
        XCTAssertEqual(c.r, CGFloat(0x9E) / 255, accuracy: 0.01)
        XCTAssertEqual(c.a, 1, accuracy: 0.001)
    }
}
