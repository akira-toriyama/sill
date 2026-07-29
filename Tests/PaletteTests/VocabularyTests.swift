// Vocabulary drift guards — the 0.6.0 promise that name lists and the
// catalog can't fall out of sync (the enum-driven `canonicalThemeNames` /
// `paletteFor`, and the effect / pet name lists that moved here from
// Effects so a no-AppKit Core can validate).
//
// Division of labour since the catalog became a type: CI's api-guard owns
// the DECLARATION channel (a cut case is a reported API breakage), these
// tests own the STRING channel (rawValues, which an API diff cannot see).
import XCTest
import Palette

final class VocabularyTests: XCTestCase {

    /// Every canonical name (minus the `random` meta-name) resolves to a
    /// spec, and distinct names resolve to distinct specs — i.e. the
    /// table has no duplicate / shadowed entries.
    func testCanonicalThemeNamesResolveDistinctly() {
        let names = canonicalThemeNames.filter { $0 != "random" }
        XCTAssertFalse(names.isEmpty)
        var seen: [ThemeSpec] = []
        for name in names {
            guard let spec = paletteFor(name) else {
                XCTFail("canonical name '\(name)' failed to resolve"); continue
            }
            XCTAssertFalse(
                seen.contains(spec),
                "duplicate spec for theme name '\(name)' — catalog drift")
            seen.append(spec)
        }
    }

    /// Pins the catalog's rawValue STRINGS — the channel an API diff
    /// cannot see, and the only reason this fixture still earns its keep.
    ///
    /// `Theme` is an enum, so `swift package diagnose-api-breaking-changes`
    /// now reports a cut case as `enumelement Theme.x has been removed` —
    /// this test is no longer the guard against a member disappearing.
    /// What that diff is blind to is the rawValue: renaming
    /// `case catppuccinMocha = "…-RENAMED"` keeps the declaration and
    /// reports NO breakage (measured), while breaking every user config and
    /// every app that passes the string. This test is that channel's only
    /// guard, which is why it stays.
    ///
    /// Editing this Set green is correct for an ADDITION. For a rename or a
    /// cut it is correct only alongside `:boom:`/major — silencing it was
    /// how `catppuccin-latte` shipped minor in v1.36.0 (0a16df9 deleted the
    /// name from this very Set) and broke wand at its next pin bump.
    func testCanonicalThemeNamesMembership() {
        let expected: Set<String> = [
            "terminal", "chomp", "rainbow",
            "aurora-flux", "acidwave", "neon-noir", "outrun", "blacklight",
            "synthwave", "ghostwire", "cyberpunk", "tron",
            "biolume", "midas", "spectre",
            "voltage", "toxic", "ember",
            "solar-veil", "molten-vein", "coin-op", "arcane",
            "dusk", "clay", "gemstone", "graphite",
            "cobalt2", "shades-of-purple", "tokyo-hack",
            "github-dark", "dracula", "catppuccin-mocha", "gruvbox",
            "github-light",
            "system", "random",
        ]
        XCTAssertEqual(Set(canonicalThemeNames), expected)
        XCTAssertEqual(canonicalThemeNames.count, expected.count, "no duplicates")
    }

    /// Spot-check that table lookup matches the statics (the old switch's
    /// behavior), unknown is nil (v2 removed the silent terminal fallback),
    /// and lookups are case-insensitive.
    func testPaletteForLookup() {
        XCTAssertEqual(paletteFor("chomp"), .chomp)
        XCTAssertEqual(paletteFor("CATPPUCCIN-MOCHA"), .catppuccinMocha)
        XCTAssertNil(paletteFor("definitely-not-a-theme"))
    }

    /// `random` resolves to a concrete non-system catalog member.
    func testRandomPicksConcreteNonSystemTheme() {
        for _ in 0..<20 {
            let spec = paletteFor("random")
            XCTAssertNotNil(spec)
            XCTAssertNotEqual(spec, .system)
        }
    }

    // MARK: Retired names (tombstones)

    /// A tombstone must never shadow a live name — a member that returns
    /// to the catalog must be removed from `retiredThemeNames`.
    func testRetiredNamesNeverShadowCanonical() {
        for tomb in retiredThemeNames {
            XCTAssertFalse(canonicalThemeNames.contains(tomb.name),
                           "'\(tomb.name)' is both canonical and retired")
        }
    }

    /// `tryInstead` is a hint into the LIVE catalog — a dead hint would
    /// re-create the drift the tombstone exists to end.
    func testRetiredTryInsteadIsCanonical() {
        for tomb in retiredThemeNames {
            guard let hint = tomb.tryInstead else { continue }
            XCTAssertTrue(canonicalThemeNames.contains(hint),
                          "'\(tomb.name)'.tryInstead '\(hint)' is not canonical")
        }
    }

    /// The latte cut (v1.36.0, the WCAG sweep) is the backfilled tombstone;
    /// lookup normalizes like `canonical` and never resolves to a palette.
    func testCatppuccinLatteTombstone() {
        let tomb = retiredTheme("  Catppuccin-Latte ")
        XCTAssertEqual(tomb?.name, "catppuccin-latte")
        XCTAssertEqual(tomb?.retiredIn, "v1.36.0")
        XCTAssertEqual(tomb?.tryInstead, "github-light")
        XCTAssertNil(retiredTheme("dracula"))
        XCTAssertNil(paletteFor("catppuccin-latte"), "a tombstone must not resolve")
    }

    /// A retired name short-circuits `suggest` to the tombstone's hint —
    /// not to a Levenshtein neighbour like `catppuccin-mocha`.
    func testSuggestUsesTombstoneHint() {
        XCTAssertEqual(suggest("catppuccin-latte"), "github-light")
    }

    // MARK: Effect / pet vocabulary (moved from Effects in 0.6.0)

    func testCanonicalEffectNamesMembership() {
        XCTAssertEqual(
            Set(canonicalEffectNames),
            ["neon", "cyber", "vapor", "kawaii", "rainbow", "chomp",
             "voltage", "toxic", "ember", "solar-veil", "molten-vein",
             "coin-op", "arcane",
             "biolume", "midas", "spectre",
             "random", "off"])
    }

    func testCanonicalLinePetNamesMatchEnum() {
        XCTAssertEqual(canonicalLinePetNames, LinePet.allCases.map(\.rawValue))
        XCTAssertEqual(Set(canonicalLinePetNames), ["chomp", "ghost"])
    }
}
