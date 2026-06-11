// Pure-spec tests — no AppKit. Validate HexColor math, the lean
// store/derive split (dark presets omit the trio; light/special store
// it), sentinels, and name resolution against the Phase V catalog.

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
        XCTAssertLessThan(HexColor(0x050805).luminance, 0.5)    // terminal bg
        XCTAssertGreaterThan(HexColor(0xFFFFFF).luminance, 0.5) // github-light bg
    }

    func testIsLight() {
        XCTAssertFalse(ThemeSpec.terminal.isLight)
        XCTAssertTrue(ThemeSpec.githubLight.isLight)
        XCTAssertTrue(ThemeSpec.catppuccinLatte.isLight)
        XCTAssertFalse(ThemeSpec.system.isLight)   // nil bg → treated dark
    }

    /// Lean core: the dark editor presets store NONE of the trio —
    /// PaletteKit derives them. (Regression guard: if someone "fills
    /// them in", the lean contract silently breaks.)
    func testDarkPresetsOmitTrio() {
        let dark: [ThemeSpec] = [
            .terminal, .cobalt2, .shadesOfPurple, .tokyoHack,
            .githubDark, .dracula, .catppuccinMocha, .gruvbox,
        ]
        for s in dark {
            XCTAssertNil(s.border)
            XCTAssertNil(s.hover)
            XCTAssertNil(s.selection)
        }
    }

    /// Light / special presets DO store the trio (they deviate from the
    /// dark-ink recipe).
    func testSpecialPresetsStoreTrio() {
        for s in [ThemeSpec.githubLight, .catppuccinLatte, .rainbow] {
            XCTAssertNotNil(s.border)
            XCTAssertNotNil(s.hover)
            XCTAssertNotNil(s.selection)
        }
    }

    func testSystemSentinel() {
        XCTAssertTrue(ThemeSpec.system.usesSystemPrimary)
        XCTAssertNil(ThemeSpec.system.background)
        XCTAssertFalse(ThemeSpec.terminal.usesSystemPrimary)
    }

    /// A preset without an error override falls back to the canonical red.
    func testErrorDefaultsToCanonicalRed() {
        XCTAssertEqual(ThemeSpec.gruvbox.error.rgb, defaultErrorHex)
        XCTAssertEqual(defaultErrorHex, 0xEF4444)
    }

    /// The blessed Phase V catalog hex (regression guard against drift).
    func testCatalogAuthoritativeHex() {
        XCTAssertEqual(ThemeSpec.terminal.primary.rgb,     0x33FF66)  // green-on-black
        XCTAssertEqual(ThemeSpec.terminal.foreground.rgb,  0x9BFEDA)
        XCTAssertEqual(ThemeSpec.terminal.background?.rgb,  0x050805)
        XCTAssertEqual(ThemeSpec.dracula.background?.rgb,   0x282A36) // carry-forward
        XCTAssertEqual(ThemeSpec.dracula.primary.rgb,       0xBD93F9)
        XCTAssertEqual(ThemeSpec.dracula.secondary?.rgb,    0xFF79C6) // brand pink
    }

    func testPaletteForCaseInsensitiveAndFallback() {
        XCTAssertEqual(paletteFor("dracula").primary.rgb, 0xBD93F9)
        XCTAssertEqual(paletteFor("DRACULA").primary.rgb, 0xBD93F9)
        XCTAssertEqual(paletteFor("no-such-theme").primary.rgb,
                       ThemeSpec.terminal.primary.rgb)
    }

    /// Hyphenated canonical names map to their concrete spec.
    func testHyphenatedNamesResolve() {
        XCTAssertEqual(paletteFor("shades-of-purple").primary.rgb, 0xFAD000)
        XCTAssertEqual(paletteFor("tokyo-hack").primary.rgb,       0xE84B3C)
        XCTAssertEqual(paletteFor("github-dark").primary.rgb,      0x2F81F7)
        XCTAssertEqual(paletteFor("catppuccin-latte").primary.rgb, 0x8839EF)
    }

    func testEveryCanonicalNameResolves() {
        for n in canonicalThemeNames where n != "random" {
            // Must map to a concrete spec (no trap / no crash).
            _ = paletteFor(n)
        }
    }

    func testChompIsCanonicalCrossAppTheme() {
        XCTAssertTrue(canonicalThemeNames.contains("chomp"))
        XCTAssertEqual(paletteFor("chomp").background?.rgb, 0x000000)
        XCTAssertEqual(paletteFor("chomp").primary.rgb, 0xFFEA00)
        XCTAssertEqual(paletteFor("chomp").error.rgb, 0xFF0000)
    }

    // MARK: - backgroundMode

    /// backgroundMode defaults from background: nil → vibrancy, concrete → fixed.
    func testBackgroundModeDefaultsFromBackground() {
        XCTAssertEqual(ThemeSpec.system.backgroundMode, .vibrancy)     // bg nil
        XCTAssertEqual(ThemeSpec.terminal.backgroundMode, .fixed)      // concrete bg
        XCTAssertEqual(ThemeSpec.githubLight.backgroundMode, .fixed)
    }

    /// usesSystemColors is true for vibrancy + systemDynamic, false for fixed.
    func testUsesSystemColors() {
        XCTAssertTrue(ThemeSpec.system.usesSystemColors)       // vibrancy
        XCTAssertFalse(ThemeSpec.terminal.usesSystemColors)    // fixed
        let sysDyn = ThemeSpec(
            background: HexColor(0x000000), foreground: HexColor(0x111111),
            muted: HexColor(0x222222), primary: HexColor(systemPrimarySentinel),
            font: .menu, backgroundMode: .systemDynamic)
        XCTAssertTrue(sysDyn.usesSystemColors)
    }

    /// tertiary is nil on every catalog preset (derive is the default).
    func testTertiaryUnsetOnPresets() {
        for n in canonicalThemeNames where n != "random" {
            XCTAssertNil(paletteFor(n).tertiary, "\(n) should not author tertiary")
        }
    }

    // MARK: - parseColorToken (pure, opt-in)

    func testParseColorTokenNamed() {
        XCTAssertEqual(parseColorToken("red")?.rgb, 0xFF0000)
        XCTAssertEqual(parseColorToken("  BLUE ")?.rgb, 0x0000FF)
        XCTAssertEqual(parseColorToken("grey")?.rgb, 0x808080)
        XCTAssertEqual(parseColorToken("gray")?.rgb, 0x808080)
    }

    func testParseColorTokenHexForms() {
        XCTAssertEqual(parseColorToken("#9ECE6A")?.rgb, 0x9ECE6A)
        XCTAssertEqual(parseColorToken("9ECE6A")?.rgb, 0x9ECE6A)   // # optional
        XCTAssertEqual(parseColorToken("#abc")?.rgb, 0xAABBCC)     // 3-digit expand
        let withA = parseColorToken("#11223344")                  // 8-digit
        XCTAssertEqual(withA?.rgb, 0x112233)
        XCTAssertEqual(withA?.alpha ?? -1, Double(0x44) / 255, accuracy: 0.001)
    }

    func testParseColorTokenRejectsGarbage() {
        XCTAssertNil(parseColorToken(""))
        XCTAssertNil(parseColorToken("notacolor"))
        XCTAssertNil(parseColorToken("#12"))       // wrong length
        XCTAssertNil(parseColorToken("#xyzxyz"))   // non-hex
        XCTAssertNil(parseColorToken("primary"))   // semantic, not a literal
    }

    // MARK: - contrast + pill alpha (pure)

    func testBestForeground() {
        XCTAssertEqual(HexColor(0xFFE000).bestForeground.rgb, 0x000000)  // bright yellow → black
        XCTAssertEqual(HexColor(0x202060).bestForeground.rgb, 0xFFFFFF)  // deep navy → white
        // Mid-luminance fills: WCAG max-contrast picks BLACK where the old
        // binary 0.6 cut returned low-contrast (~3.5:1) white.
        XCTAssertEqual(HexColor(0xFF2D95).bestForeground.rgb, 0x000000)  // hot pink (rainbow primary)
        XCTAssertEqual(HexColor(0xE84B3C).bestForeground.rgb, 0x000000)  // red-orange (tokyo-hack)
        XCTAssertEqual(HexColor(0x2F81F7).bestForeground.rgb, 0x000000)  // medium blue (github-dark)
    }

    func testSuggestedPillAlphaMonotoneAndClamped() {
        let darkA = suggestedPillAlpha(luminance: 0.05)
        let lightA = suggestedPillAlpha(luminance: 0.95)
        XCTAssertGreaterThan(darkA, lightA)            // darker → more opaque
        XCTAssertGreaterThanOrEqual(lightA, 0.30)      // clamped floor
        XCTAssertLessThanOrEqual(darkA, 0.92)          // clamped ceil
    }

    // MARK: - validation (canonical / suggest)

    func testCanonicalResolvesAndRejects() {
        XCTAssertEqual(canonical("DRACULA"), "dracula")        // case-insensitive
        XCTAssertEqual(canonical("  github-light "), "github-light")  // trimmed
        XCTAssertEqual(canonical("random"), "random")          // meta-name kept
        XCTAssertNil(canonical("nord"))                        // cut in Phase V
        XCTAssertNil(canonical("nonsense"))
    }

    func testSuggestNearestOrNil() {
        XCTAssertEqual(suggest("dracua"), "dracula")           // 1 edit
        XCTAssertEqual(suggest("terminl"), "terminal")
        XCTAssertNil(suggest(""))
        XCTAssertNil(suggest("zzzzzzzzzz"))                    // nothing close
    }

    // MARK: - EffectIntensity (pure, shared knob)

    func testEffectIntensityMultipliers() {
        XCTAssertEqual(EffectIntensity.subtle.multiplier, 0.6, accuracy: 0.0001)
        XCTAssertEqual(EffectIntensity.normal.multiplier, 1.0, accuracy: 0.0001)
        XCTAssertEqual(EffectIntensity.bold.multiplier, 1.6, accuracy: 0.0001)
        XCTAssertEqual(EffectIntensity.wild.multiplier, 2.5, accuracy: 0.0001)
    }

    func testEffectIntensityParse() {
        XCTAssertEqual(EffectIntensity.parse("BOLD"), .bold)      // case-insensitive
        XCTAssertEqual(EffectIntensity.parse("  wild "), .wild)   // trimmed
        XCTAssertNil(EffectIntensity.parse("loud"))               // unknown → nil
        XCTAssertEqual(EffectIntensity.allCases.count, 4)
    }
}
