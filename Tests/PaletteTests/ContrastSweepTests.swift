// WCAG contrast sweep over the built-in theme catalog.
//
// The idea is borrowed from Google's DESIGN.md `contrast-ratio` lint rule
// (warn when a text/background pair falls below WCAG AA). sill's tokens are
// typed Swift, so the compiler already enforces the *structural* rules
// DESIGN.md lints (missing/duplicate/unknown keys, broken refs); the one
// thing the type system CANNOT see is the *semantic legibility* of an
// authored color pair. This sweep adds exactly that check on top of the
// existing pure `wcagRelativeLuminance` / `contrastRatio` primitives — a
// READ over the catalog, not a second token source.
//
// WCAG levels used:
//   • SC 1.4.3 (Contrast Minimum, AA) — normal text 4.5:1   → HARD pairs
//   • SC 1.4.11 (Non-text Contrast, AA) / large-text floor 3:1 → WARN pairs
//
// `swift test` (CI, full Xcode) runs this; the pure `contrastRatio` it
// exercises compiles under the maintainer's CommandLineTools `swift build`.
import XCTest
import Palette

final class ContrastSweepTests: XCTestCase {

    // MARK: - contrastRatio primitive

    /// Bounds: black-on-white is the WCAG max (21:1); a color against
    /// itself is 1:1.
    func testContrastRatioBounds() {
        XCTAssertEqual(contrastRatio(HexColor(0x000000), HexColor(0xFFFFFF)), 21, accuracy: 0.001)
        XCTAssertEqual(contrastRatio(HexColor(0x808080), HexColor(0x808080)), 1, accuracy: 0.0001)
    }

    /// Order-independent: contrast is a property of the pair, not which is
    /// ink vs fill.
    func testContrastRatioIsSymmetric() {
        let a = HexColor(0x123456), b = HexColor(0xABCDEF)
        XCTAssertEqual(contrastRatio(a, b), contrastRatio(b, a), accuracy: 1e-12)
    }

    // MARK: - Catalog sweep

    private static let aa = 4.5      // SC 1.4.3 normal text
    private static let floor3 = 3.0  // SC 1.4.11 / large-text floor

    /// (preset, pair) keys that INTENTIONALLY sit below their floor. Each is
    /// a documented, reviewed exception — NOT a way to lower the global bar.
    /// The sweep still PRINTS each accepted exception (so it stays visible in
    /// CI logs, mirroring DESIGN.md's "surface findings, don't silently
    /// pass"), and removing the underlying issue should remove the entry.
    /// Key: "<preset>/<pair>".
    let contrastExceptions: [String: String] = [
        // --- error × background below AA 4.5 (HARD): third-party brand reds
        //     kept faithful to the source theme (sill-owned gemstone &
        //     default-using gruvbox were instead lifted over AA) -----------
        "shades-of-purple/error": "brand red #EC3A37 on #2D2B55 ≈ 3.29:1 — third-party theme fidelity (ahmadawais)",
        "cobalt2/error":          "Wes Bos red #FF5C57 on #193549 ≈ 4.20:1 — third-party theme fidelity",
        // --- muted × background below the 3:1 floor (WARN) ---------------
        "gemstone/muted":         "velvet low-value muted #5E5870 ≈ 2.97:1 — supplementary text, by design",
    ]

    /// Every `.fixed` preset's legibility-critical pairs clear their WCAG
    /// floor, unless explicitly exception-listed above. `.vibrancy` /
    /// `.systemDynamic` presets resolve OS NSColors in PaletteKit and cannot
    /// be checked from the pure ThemeSpec, so they are skipped — and the skip
    /// set is asserted, so a preset that *accidentally* goes dynamic is caught
    /// rather than silently dropped.
    func testPresetCatalogMeetsContrast() {
        var skipped: [String] = []
        var unexpected: [String] = []

        for name in canonicalThemeNames where name != "random" {
            let spec = paletteFor(name)
            // `.fixed` is the only mode whose hexes are concrete & complete.
            guard spec.backgroundMode == .fixed, let bg = spec.background else {
                skipped.append(name)
                continue
            }

            func check(_ pair: String, _ ink: HexColor, _ fill: HexColor, min floor: Double) {
                let ratio = contrastRatio(ink, fill)
                guard ratio < floor else { return }
                let key = "\(name)/\(pair)"
                let measured = String(format: "%.2f", ratio)
                if let reason = contrastExceptions[key] {
                    print("contrast: accepted exception \(key) = \(measured):1 — \(reason)")
                } else {
                    unexpected.append(
                        "\(key) = \(measured):1 < \(floor):1 — fix the hex, "
                        + "or add \"\(key)\" to contrastExceptions with a reason")
                }
            }

            // HARD — essential text on the background (SC 1.4.3, 4.5:1).
            check("foreground", spec.foreground, bg, min: Self.aa)
            check("error", spec.error, bg, min: Self.aa)

            // The OS-accent sentinel isn't a real color — skip the two
            // primary-derived pairs for it (no `.fixed` preset uses it today).
            if !spec.usesSystemPrimary {
                // HARD — the auto-picked button-label ink on the primary fill.
                check("onPrimary", spec.primary.bestForeground, spec.primary, min: Self.aa)
                // WARN — primary as a graphical affordance (SC 1.4.11, 3:1).
                check("primary", spec.primary, bg, min: Self.floor3)
            }

            // WARN — supplementary text, relaxed to the 3:1 floor.
            check("muted", spec.muted, bg, min: Self.floor3)
        }

        XCTAssertEqual(
            skipped, ["system"],
            "unexpected statically-unanalyzable preset(s) — a preset silently "
            + "went .vibrancy/.systemDynamic; the sweep can no longer cover it")
        XCTAssertTrue(
            unexpected.isEmpty,
            "sub-threshold contrast not in the documented exception list:\n  "
            + unexpected.joined(separator: "\n  "))
    }
}
