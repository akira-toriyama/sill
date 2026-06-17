// Vocabulary drift guards — the 0.6.0 promise that name lists and the
// catalog can't fall out of sync (the table-driven rewrite of
// `canonicalThemeNames` / `paletteFor`, and the effect / pet name lists
// that moved here from Effects so a no-AppKit Core can validate).
import XCTest
import Palette

final class VocabularyTests: XCTestCase {

    // MARK: Theme catalog

    /// Every canonical name (minus the `random` meta-name) resolves to a
    /// spec, and distinct names resolve to distinct specs — i.e. the
    /// table has no duplicate / shadowed entries.
    func testCanonicalThemeNamesResolveDistinctly() {
        let names = canonicalThemeNames.filter { $0 != "random" }
        XCTAssertFalse(names.isEmpty)
        var seen: [ThemeSpec] = []
        for name in names {
            let spec = paletteFor(name)
            XCTAssertFalse(
                seen.contains(spec),
                "duplicate spec for theme name '\(name)' — catalog drift")
            seen.append(spec)
        }
    }

    /// The catalog members the family ships against. An addition extends
    /// this list deliberately; a silent disappearance is drift.
    func testCanonicalThemeNamesMembership() {
        let expected: Set<String> = [
            "terminal", "chomp", "rainbow",
            "aurora-flux", "acidwave", "neon-noir", "outrun", "blacklight",
            "synthwave", "ghostwire", "cyberpunk", "tron",
            "cobalt2", "shades-of-purple", "tokyo-hack",
            "github-dark", "dracula", "catppuccin-mocha", "gruvbox",
            "github-light", "catppuccin-latte",
            "system", "random",
        ]
        XCTAssertEqual(Set(canonicalThemeNames), expected)
        XCTAssertEqual(canonicalThemeNames.count, expected.count, "no duplicates")
    }

    /// Spot-check that table lookup matches the statics (the old switch's
    /// behavior), unknown falls back to terminal, and lookups are
    /// case-insensitive.
    func testPaletteForLookup() {
        XCTAssertEqual(paletteFor("chomp"), .chomp)
        XCTAssertEqual(paletteFor("CATPPUCCIN-MOCHA"), .catppuccinMocha)
        XCTAssertEqual(paletteFor("definitely-not-a-theme"), .terminal)
    }

    /// `random` resolves to a concrete non-system catalog member.
    func testRandomPicksConcreteNonSystemTheme() {
        for _ in 0..<20 {
            let spec = paletteFor("random")
            XCTAssertNotEqual(spec, .system)
        }
    }

    // MARK: Effect / pet vocabulary (moved from Effects in 0.6.0)

    func testCanonicalEffectNamesMembership() {
        XCTAssertEqual(
            Set(canonicalEffectNames),
            ["neon", "cyber", "vapor", "kawaii", "rainbow", "chomp",
             "random", "off"])
    }

    func testCanonicalLinePetNamesMatchEnum() {
        XCTAssertEqual(canonicalLinePetNames, LinePet.allCases.map(\.rawValue))
        XCTAssertEqual(Set(canonicalLinePetNames), ["chomp", "ghost"])
    }
}
