// The guard on a DESIGN habit, not on six separate bugs: a state field that also
// decides whether an unrelated capability exists. A consumer picks the value for
// one reason and loses the other silently — no compile error, no warning, and a
// green logic suite, because the capability is still coded, just unreachable.
//
// Six of these shipped in `ThemedListStyle` (audit 2026-08-03, t-fyvs) plus one
// in `ThemedGridView`. Two of them are what made facet's hover thumbnails and
// its header clicks structurally impossible. `style.hosted` (rects) was booked
// out first in #175 and keeps its own suite, `ThemedListRowRectTests`.
//
// Each case here asserts the INDEPENDENCE, not the current default: flip the
// field that used to be the gate and assert the gated capability is unmoved.
// Re-introducing any gate makes exactly one case fail.
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
@testable import Palette
@testable import PaletteKit
@testable import ThemeKitUI

@MainActor
final class ListStyleGateTests: XCTestCase {

    private typealias Item = ListItem<String>

    // MARK: - #2 header tappability vs collapsibility

    /// A header that cannot collapse still ACTIVATES. This is the facet
    /// regression: `handleTap` guarded the whole case on `collapsed != nil`, so a
    /// plain `[[desktop.N.section]]` header swallowed every click while Enter on
    /// the same row still worked.
    func testPlainHeaderStillActivates() {
        let plain = Item.tapOutcome(kind: .sectionHeader(subtitle: nil, collapsed: nil),
                                    isDisabled: false, selectionMode: .single)
        XCTAssertTrue(plain.activates, "a non-collapsible header must still report activation")
        XCTAssertFalse(plain.togglesSection, "a non-collapsible header must not toggle")
    }

    func testCollapsibleHeaderBothTogglesAndActivates() {
        for collapsed in [false, true] {
            let o = Item.tapOutcome(kind: .sectionHeader(subtitle: nil, collapsed: collapsed),
                                    isDisabled: false, selectionMode: .single)
            XCTAssertTrue(o.togglesSection, "collapsed: \(collapsed)")
            XCTAssertTrue(o.activates, "collapsed: \(collapsed)")
        }
    }

    /// Collapsibility governs COLLAPSING only — it must not move activation.
    func testCollapsibilityDoesNotGateActivation() {
        let kinds: [Item.Kind] = [.sectionHeader(subtitle: nil, collapsed: nil),
                                  .sectionHeader(subtitle: nil, collapsed: false),
                                  .sectionHeader(subtitle: nil, collapsed: true),
                                  .sectionHeader(subtitle: "sub", collapsed: nil)]
        let activations = Set(kinds.map {
            Item.tapOutcome(kind: $0, isDisabled: false, selectionMode: .single).activates
        })
        XCTAssertEqual(activations, [true], "activation varied with collapsibility — the gate is back")
    }

    /// Disabled is a genuine gate on ALL outcomes (not a ride-along).
    func testDisabledStopsEverything() {
        for kind: Item.Kind in [.row, .sectionHeader(subtitle: nil, collapsed: true), .separator] {
            XCTAssertEqual(Item.tapOutcome(kind: kind, isDisabled: true, selectionMode: .single),
                           RowTapOutcome(), "disabled must produce no outcome")
        }
    }

    // MARK: - #3 keyboard focus vs selectionMode

    /// `.focusable` used to read `selectionMode != .none`, so a list that
    /// deliberately selects nothing (menus, activate-only lists) lost every key
    /// with no diagnostic. Focus is now its own field and does not move.
    func testKeyboardFocusIsIndependentOfSelectionMode() {
        let focusValues = Set([SelectionMode.none, .single, .multiple].map { mode -> Bool in
            var s = ThemedListStyle()
            s.selectionMode = mode
            return s.takesKeyboardFocus
        })
        XCTAssertEqual(focusValues, [true], "selectionMode moved takesKeyboardFocus — the gate is back")
    }

    /// Selection semantics still govern SELECTING, which is the field's real job.
    func testSelectionModeStillGatesSelectingOnly() {
        XCTAssertFalse(Item.tapOutcome(kind: .row, isDisabled: false, selectionMode: .none).selects)
        XCTAssertTrue(Item.tapOutcome(kind: .row, isDisabled: false, selectionMode: .single).selects)
        // ...and never activation: a `.none` list is activate-ONLY, so losing this
        // would silence the one callback it has.
        for mode: SelectionMode in [.none, .single, .multiple] {
            XCTAssertTrue(Item.tapOutcome(kind: .row, isDisabled: false, selectionMode: mode).activates,
                          "mode: \(mode)")
        }
    }

    // MARK: - #5 accent bar vs selection SHAPE (render)

    /// `roundedSelection` picks the fill's SHAPE; it used to also delete the 3pt
    /// `primary` bar, so a theme could not have both a pill and the affordance.
    /// Rasterised, because the bar is a drawn thing and a value assertion would
    /// not notice it silently vanishing.
    func testRoundedSelectionKeepsTheAccentBarWhenAsked() throws {
        let barred = try leadingEdgeIsPrimary(rounded: true, showsBar: true)
        let plain  = try leadingEdgeIsPrimary(rounded: true, showsBar: false)
        XCTAssertTrue(barred, "rounded + showsSelectionAccentBar drew no primary bar")
        XCTAssertFalse(plain, "showsSelectionAccentBar=false still drew a bar")
    }

    func testAccentBarSurvivesBothSelectionShapes() throws {
        for rounded in [false, true] {
            XCTAssertTrue(try leadingEdgeIsPrimary(rounded: rounded, showsBar: true),
                          "roundedSelection=\(rounded) lost the accent bar")
        }
    }

    /// Renders one selected row and reports whether the leading edge carries the
    /// palette's `primary`. The bar is `metrics.accentBar` (3pt) wide at the
    /// leading edge, inset by `roundedHInset` when the shape is a pill.
    private func leadingEdgeIsPrimary(rounded: Bool, showsBar: Bool) throws -> Bool {
        let palette = resolve(Theme.dracula.spec)
        var style = ThemedListStyle()
        style.selectionMode = .single
        style.selectionInk = .wash              // the bar only exists on a wash
        style.roundedSelection = rounded
        style.showsSelectionAccentBar = showsBar

        let list = ThemedListView<String>(
            items: [ListItem(id: "a", primary: "row a")],
            selection: .constant(["a"]),
            style: style,
            palette: palette)
            .frame(width: 240, height: 40)

        let host = NSHostingView(rootView: list)
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 40)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds),
                               "no bitmap rep")
        host.cacheDisplay(in: host.bounds, to: rep)

        let primary = palette.primary.usingColorSpace(.deviceRGB)
        // Sweep the leading gutter (past the pill inset) down the row's middle band.
        for x in 0..<8 {
            for y in stride(from: rep.pixelsHigh / 3, to: rep.pixelsHigh * 2 / 3, by: 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let p = primary else { continue }
                if abs(c.redComponent - p.redComponent) < 0.06,
                   abs(c.greenComponent - p.greenComponent) < 0.06,
                   abs(c.blueComponent - p.blueComponent) < 0.06,
                   c.alphaComponent > 0.9 {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - #6 AX vending vs swallowing the row's contents

    /// Vending a row as one AX element and DISCARDING its inner elements were
    /// the same switch, so turning on row AX for VoiceOver deleted the badges
    /// and secondary line. The two are separate fields now.
    func testAXVendingDoesNotForceFlattening() {
        var s = ThemedListStyle()
        s.vendsRowAXElements = true
        XCTAssertTrue(s.flattensRowAXChildren, "menu parity: flattening stays the default")
        s.flattensRowAXChildren = false
        XCTAssertTrue(s.vendsRowAXElements, "asking to keep children must not stop vending")
    }

    // MARK: - #4 the rename is the fix

    /// `hoverStyle` had exactly two uses and both were the selection fill, so the
    /// name pointed every reader at a hover knob that does not exist. Renaming it
    /// IS the de-gating; this pins the surviving semantics.
    func testSelectionInkGovernsTheFillNotHover() {
        var s = ThemedListStyle()
        XCTAssertEqual(s.selectionInk, .wash, "default ink is the wash")
        s.selectionInk = .solidAccent
        XCTAssertEqual(s.selectionInk, .solidAccent)
        // The ink is orthogonal to every other decoration field.
        XCTAssertFalse(s.roundedSelection)
        XCTAssertTrue(s.showsSelectionAccentBar)
        XCTAssertTrue(s.takesKeyboardFocus)
    }

    // MARK: - defaults are the contract

    /// A fresh style must arrive with every capability ON, so a consumer opts
    /// OUT of things rather than accidentally opting out by picking a state.
    func testFreshStyleGrantsEveryCapability() {
        let s = ThemedListStyle()
        XCTAssertTrue(s.takesKeyboardFocus)
        XCTAssertTrue(s.showsSelectionAccentBar)
        XCTAssertTrue(s.flattensRowAXChildren)   // only consulted when vending
        XCTAssertFalse(s.hosted)
        XCTAssertFalse(s.vendsRowAXElements)
    }
}
