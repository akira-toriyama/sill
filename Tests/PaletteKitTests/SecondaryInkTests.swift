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
// carries 0.70 alpha, and `contrast` ignores alpha — measuring it unflattened
// would report a number ~2x better than what is actually on screen and the gate
// would pass while the text stayed illegible.
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
