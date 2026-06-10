// PaletteKit tests — the derive recipe must reproduce facet's exact
// divider / hoverFill / selFill values, so the lean+derive migration is
// pixel-identical for the 15 dark presets. Also: overrides win, the
// system preset resolves to dynamic colors, bg override, complement.

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

    /// The dark-editor recipe: divider = white@0.10, hover = white@0.05,
    /// sel = accent@0.18 — facet's exact values, now DERIVED.
    func testDarkRecipeReproducesFacet() {
        let p = resolve(.terminal)            // accent 0x9ECE6A, dark bg
        let d = comps(p.divider)
        XCTAssertEqual(d.r, 1, accuracy: 0.01); XCTAssertEqual(d.a, 0.10, accuracy: 0.001)
        let h = comps(p.hoverFill)
        XCTAssertEqual(h.r, 1, accuracy: 0.01); XCTAssertEqual(h.a, 0.05, accuracy: 0.001)
        let s = comps(p.selFill)              // accent @ 0.18
        XCTAssertEqual(s.r, CGFloat(0x9E) / 255, accuracy: 0.01)
        XCTAssertEqual(s.g, CGFloat(0xCE) / 255, accuracy: 0.01)
        XCTAssertEqual(s.b, CGFloat(0x6A) / 255, accuracy: 0.01)
        XCTAssertEqual(s.a, 0.18, accuracy: 0.001)
    }

    /// Light themes derive BLACK neutral ink (not white).
    func testLightRecipeUsesBlackInk() {
        // paper stores its trio explicitly, so use a synthetic light spec
        // with no overrides to exercise the derive branch.
        let lightNoTrio = ThemeSpec(
            bg: HexColor(0xFAFAF8), text: HexColor(0x1C1C1E),
            dim: HexColor(0x8A8A8E), accent: HexColor(0x3B82F6), font: .system)
        let p = resolve(lightNoTrio)
        let d = comps(p.divider)
        XCTAssertEqual(d.r, 0, accuracy: 0.01)   // black ink
        XCTAssertEqual(d.a, 0.10, accuracy: 0.001)
    }

    /// An explicit override must win over the derived value.
    func testOverrideWins() {
        let p = resolve(.cute)   // divider = accent #F2789F @ 0.22 (explicit)
        let d = comps(p.divider)
        XCTAssertEqual(d.r, CGFloat(0xF2) / 255, accuracy: 0.01)
        XCTAssertEqual(d.a, 0.22, accuracy: 0.001)
    }

    func testSystemPresetResolvesDynamicColors() {
        let p = resolve(.system)
        XCTAssertNil(p.bg)                          // vibrancy
        XCTAssertEqual(p.text, NSColor.labelColor)
        XCTAssertEqual(p.accent, NSColor.controlAccentColor)
        XCTAssertNotNil(p.vibrancyMaterial)         // hint emitted
    }

    func testSystemPresetMaterialOverride() {
        let p = resolve(.system, material: .menu, forceDark: true)
        XCTAssertEqual(p.vibrancyMaterial, .menu)
        XCTAssertTrue(p.forceDarkAqua)
    }

    /// bg override (Q1: shared accent/text, app-chosen bg).
    func testBgOverride() {
        let p = resolve(.terminal, bgOverride: HexColor(0x111111))
        let b = comps(p.bg!)
        XCTAssertEqual(b.r, CGFloat(0x11) / 255, accuracy: 0.01)
        // accent stays canonical
        XCTAssertEqual(comps(p.accent).r, CGFloat(0x9E) / 255, accuracy: 0.01)
    }

    /// accent2 omitted ⇒ derived complement (not nil).
    func testAccent2Derived() {
        let noAccent2 = ThemeSpec(
            bg: HexColor(0x101010), text: HexColor(0xEEEEEE),
            dim: HexColor(0x888888), accent: HexColor(0x3B82F6), font: .mono)
        let p = resolve(noAccent2)
        // complement of blue is in the orange/amber range — at minimum,
        // it must differ from the accent.
        XCTAssertNotEqual(comps(p.accent2).r, comps(p.accent).r, accuracy: 0.001)
    }

    func testTertiaryIsFadedText() {
        let p = resolve(.terminal)
        XCTAssertEqual(comps(p.tertiary()).a, 0.55, accuracy: 0.001)
        XCTAssertEqual(comps(p.tertiary(0.4)).a, 0.40, accuracy: 0.001)
    }

    func testPalInstallAndRead() {
        setPalette(named: "nord")
        XCTAssertEqual(comps(pal.accent).r, CGFloat(0x88) / 255, accuracy: 0.01)
        setPalette(resolve(.terminal))
        XCTAssertEqual(comps(pal.accent).g, CGFloat(0xCE) / 255, accuracy: 0.01)
    }

    func testNSColorHexInit() {
        let c = comps(NSColor(hex: 0x9ECE6A))
        XCTAssertEqual(c.r, CGFloat(0x9E) / 255, accuracy: 0.01)
        XCTAssertEqual(c.a, 1, accuracy: 0.001)
    }
}
