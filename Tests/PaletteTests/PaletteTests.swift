// Pure-spec tests — no AppKit. Validate HexColor math, the lean
// store/derive split (dark presets omit the trio; light/special store
// it), sentinels, and name resolution.

import XCTest
@testable import Palette

final class PaletteTests: XCTestCase {

    func testHexColorChannels() {
        let c = HexColor(0x9ECE6A)
        XCTAssertEqual(c.rgb, 0x9ECE6A)
        XCTAssertEqual(c.alpha, 1.0, accuracy: 0.0001)
        XCTAssertEqual(c.r, Double(0x9E) / 255, accuracy: 0.0001)
        XCTAssertEqual(c.g, Double(0xCE) / 255, accuracy: 0.0001)
        XCTAssertEqual(c.b, Double(0x6A) / 255, accuracy: 0.0001)
    }

    func testHexHighByteIgnored() {
        XCTAssertEqual(HexColor(0xFF_9ECE6A).rgb, 0x9ECE6A)
    }

    func testWithAlpha() {
        let c = HexColor(0x123456).withAlpha(0.3)
        XCTAssertEqual(c.rgb, 0x123456)
        XCTAssertEqual(c.alpha, 0.3, accuracy: 0.0001)
    }

    func testLuminanceDarkVsLight() {
        XCTAssertLessThan(HexColor(0x0E0F14).luminance, 0.5)    // terminal bg
        XCTAssertGreaterThan(HexColor(0xFFF1F6).luminance, 0.5) // cute bg
    }

    func testIsLight() {
        XCTAssertFalse(ThemeSpec.terminal.isLight)
        XCTAssertTrue(ThemeSpec.cute.isLight)
        XCTAssertTrue(ThemeSpec.paper.isLight)
        XCTAssertFalse(ThemeSpec.system.isLight)   // nil bg → treated dark
    }

    /// Lean core: the 15 dark editor presets store NONE of the trio —
    /// PaletteKit derives them. (Regression guard: if someone "fills
    /// them in", the lean contract silently breaks.)
    func testDarkPresetsOmitTrio() {
        let dark: [ThemeSpec] = [
            .terminal, .nord, .dracula, .gruvbox, .catppuccin, .rosepine,
            .everforest, .solarized, .onedark, .monokai, .hacker, .monotone,
            .neon, .cyber, .vapor,
        ]
        for s in dark {
            XCTAssertNil(s.divider)
            XCTAssertNil(s.hoverFill)
            XCTAssertNil(s.selFill)
        }
    }

    /// Light / monochrome / special presets DO store the trio (they
    /// deviate from the dark-ink recipe).
    func testSpecialPresetsStoreTrio() {
        for s in [ThemeSpec.cute, .paper, .kawaii, .monoLight, .monoDark, .rainbow] {
            XCTAssertNotNil(s.divider)
            XCTAssertNotNil(s.hoverFill)
            XCTAssertNotNil(s.selFill)
        }
    }

    func testSystemSentinel() {
        XCTAssertTrue(ThemeSpec.system.usesSystemAccent)
        XCTAssertNil(ThemeSpec.system.bg)
        XCTAssertFalse(ThemeSpec.terminal.usesSystemAccent)
    }

    func testErrorDefaultsToCanonicalRed() {
        XCTAssertEqual(ThemeSpec.terminal.error.rgb, defaultErrorHex)
        XCTAssertEqual(defaultErrorHex, 0xEF4444)
    }

    func testFacetAuthoritativeHex() {
        // Q1: facet's hex is canonical for the drifted house themes.
        XCTAssertEqual(ThemeSpec.terminal.accent.rgb, 0x9ECE6A)
        XCTAssertEqual(ThemeSpec.terminal.text.rgb,   0xC0CAF5)
        XCTAssertEqual(ThemeSpec.hacker.accent.rgb,   0x33FF66)  // not perch's 0x00FF41
        XCTAssertEqual(ThemeSpec.hacker.bg?.rgb,      0x0A0F0A)  // not perch's 0x000000
    }

    func testPaletteForCaseInsensitiveAndFallback() {
        XCTAssertEqual(paletteFor("nord").accent.rgb, 0x88C0D0)
        XCTAssertEqual(paletteFor("NORD").accent.rgb, 0x88C0D0)
        XCTAssertEqual(paletteFor("no-such-theme").accent.rgb,
                       ThemeSpec.terminal.accent.rgb)
    }

    func testEveryCanonicalNameResolves() {
        for n in canonicalThemeNames where n != "random" {
            // Must map to a concrete spec (no trap / no crash).
            _ = paletteFor(n)
        }
    }

    func testChompIsCanonicalCrossAppTheme() {
        XCTAssertTrue(canonicalThemeNames.contains("chomp"))
        XCTAssertEqual(paletteFor("chomp").bg?.rgb, 0x000000)
        XCTAssertEqual(paletteFor("chomp").accent.rgb, 0xFFEA00)
        XCTAssertEqual(paletteFor("chomp").error.rgb, 0xFF0000)
    }
}
