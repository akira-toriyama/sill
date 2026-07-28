// `secondaryInk(on:)` — the catalog-wide sweep that turns "the selected row's
// second line is hard to read on some themes" into a gate.
//
// The defect was invisible for a structural reason, not an oversight: a
// selected row paints `selection` (primary@0.18) and draws its second line in
// `muted` ON that wash, and `contrastRatio` ignores alpha — so no sweep could
// see the pair until `composite`/`flatten` existed. Measured across the
// catalog, 16 of the 34 fixed presets were UNDER the 3:1 supplementary-text
// floor, dracula worst at 2.18.
//
// NOTE the flatten-before-measuring in every assertion below. The fallback ink
// carries 0.55 alpha, and `contrast` ignores alpha — measuring it unflattened
// would report a number ~2x better than what is actually on screen and the gate
// would pass while the text stayed illegible. (That mistake is not theoretical:
// it was made again while investigating this file, and the unflattened numbers
// looked like the hierarchy had INVERTED — the opposite of the truth.)
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import AppKit
@testable import Palette
@testable import PaletteKit

@MainActor
final class SecondaryInkTests: XCTestCase {

    /// WCAG's floor for supplementary / large text. Deliberately not 4.5 — this
    /// is a second line, not body copy.
    private let floor = 3.0

    private var fixedThemes: [Theme] {
        Theme.allCases.filter { $0.spec.backgroundMode == .fixed }
    }

    /// The colour a selected row's second line is REALLY drawn on.
    private func flattenedSelection(_ p: ResolvedPalette) -> NSColor? {
        guard let bg = p.background else { return nil }
        return p.flatten(p.selection, over: bg)
    }

    /// THE contract: after the accessor, no fixed preset leaves its selected
    /// row's secondary line under the floor. Zero exceptions — guaranteeing
    /// this is the accessor's entire job.
    func testEveryFixedPresetClearsTheFloorOnASelectedRow() {
        for theme in fixedThemes {
            let p = resolve(theme.spec)
            guard let wash = flattenedSelection(p) else { continue }
            let ink = p.secondaryInk(on: wash)
            // Flatten the ink too — it may carry alpha.
            let real = p.contrast(p.flatten(ink, over: wash), on: wash)
            XCTAssertGreaterThanOrEqual(
                real, floor,
                "\(theme.rawValue): secondary line on the selection wash is \(real), under \(floor)")
        }
    }

    /// The accessor must not OVER-correct. Wherever `muted` was already legible
    /// the theme's authored look is preserved exactly — this is what keeps the
    /// change a repair rather than a restyle. Measured: 18 of 34 presets take
    /// this path untouched.
    func testThemesWhereMutedAlreadyWorksAreLeftAlone() {
        var untouched = 0
        for theme in fixedThemes {
            let p = resolve(theme.spec)
            guard let wash = flattenedSelection(p) else { continue }
            guard p.contrast(p.muted, on: wash) >= floor else { continue }
            XCTAssertEqual(p.secondaryInk(on: wash), p.muted,
                           "\(theme.rawValue): muted already clears the floor, must be returned as-is")
            untouched += 1
        }
        XCTAssertGreaterThan(untouched, 0, "if nothing takes this path the guard is vacuous")
    }

    /// The defect this fixes was real and specific. dracula's selection
    /// flattens to #433D59 and scores 2.1796 against `muted` — pinned here so a
    /// future catalog edit that silently "fixes" it by recolouring the theme
    /// makes this test speak up rather than passing quietly.
    func testDraculaWasTheWorstCaseAndIsNowRepaired() {
        let p = resolve(Theme.dracula.spec)
        guard let wash = flattenedSelection(p) else { return XCTFail("dracula has a fixed background") }

        XCTAssertEqual(p.contrast(p.muted, on: wash), 2.1796, accuracy: 0.001,
                       "the untreated pair — if this moves, the catalog changed")
        let ink = p.secondaryInk(on: wash)
        XCTAssertNotEqual(ink, p.muted, "dracula must take the corrected path")
        XCTAssertGreaterThanOrEqual(p.contrast(p.flatten(ink, over: wash), on: wash), floor)
    }

    /// The floor's twin, and the half this accessor originally shipped without:
    /// a second line must stay BELOW the first. Legibility and hierarchy are
    /// different properties, and only one of them had a guard — so the repair
    /// was free to overshoot, and it did.
    ///
    /// The bar is calibrated on the catalog itself rather than invented. Every
    /// preset where `muted` already clears the floor is a preset the author was
    /// happy with, and those sit at 0.19…0.45 of the foreground's contrast. A
    /// repaired preset is allowed to run brighter than that band (it is a
    /// SELECTED row, and some extra presence is wanted) but not to approach the
    /// primary line.
    ///
    /// 0.65 is that ceiling: the shipping α 0.55 tops out at 0.60, and the
    /// previous α 0.70 topped out at 0.83 — so this test FAILS on the value it
    /// was written to retire, which is the only reason to trust it.
    func testSecondaryLineStaysBelowPrimary() {
        let ceiling = 0.65
        var worst = (theme: "", ratio: 0.0)
        for theme in fixedThemes {
            let p = resolve(theme.spec)
            guard let wash = flattenedSelection(p) else { continue }
            let ink = p.secondaryInk(on: wash)
            let secondary = p.contrast(p.flatten(ink, over: wash), on: wash)
            let primary = p.contrast(p.flatten(p.foreground, over: wash), on: wash)
            let ratio = secondary / primary
            if ratio > worst.ratio { worst = (theme.rawValue, ratio) }
            XCTAssertLessThanOrEqual(
                ratio, ceiling,
                "\(theme.rawValue): the second line is \(ratio) of the first line's contrast — "
                + "legible, but no longer reading as secondary")
        }
        // A vacuous pass would be worse than a failure: if the sweep stopped
        // seeing the repaired presets this would still be green.
        XCTAssertGreaterThan(worst.ratio, 0.45,
                             "no preset came close to the ceiling — is the sweep still reaching "
                             + "the corrected path? (worst was \(worst.theme))")
    }

    /// Guards the flatten-before-measuring discipline itself. A translucent ink
    /// scores far better unflattened than it does on screen; if someone
    /// "simplifies" the assertions above by dropping the flatten, this fails.
    func testMeasuringWithoutFlatteningOverstatesContrast() {
        let p = resolve(Theme.dracula.spec)
        guard let wash = flattenedSelection(p) else { return XCTFail("dracula has a fixed background") }
        let ink = p.secondaryInk(on: wash)
        XCTAssertGreaterThan(ink.alphaComponent, 0, "precondition: the fallback ink is translucent")
        XCTAssertLessThan(ink.alphaComponent, 1)

        let naive = p.contrast(ink, on: wash)                       // alpha ignored
        let real  = p.contrast(p.flatten(ink, over: wash), on: wash) // what is drawn
        XCTAssertGreaterThan(naive, real,
                             "ignoring alpha must overstate — that is why every check flattens first")
    }
}
