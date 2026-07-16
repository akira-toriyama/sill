// ThemeKit / ThemedToolBar tests — DETERMINISTIC in headless CI (no Xcode locally
// → these first compile + run in CI). They drive the bar's chrome + flex-section
// geometry + composed-item state via the DEBUG `toolBarProbe` + the `simulate…`
// seams — no synthetic events / screenshots. The live surface / hover / press 演出
// is proven in prism, not here.

import XCTest
import AppKit
import Palette
import PaletteKit
import TestSupport
@testable import ThemeKit   // for the DEBUG toolBarProbe / simulate seams

@MainActor
final class ThemedToolBarTests: XCTestCase {

    private func palette() -> ResolvedPalette { resolve(.terminal) }

    private func bar(_ items: [ThemedToolBar.Item], width: CGFloat = 400,
                     _ configure: (ThemedToolBar) -> Void = { _ in }) -> ThemedToolBar {
        let t = ThemedToolBar(palette: palette())
        configure(t)
        t.items = items
        t.frame = NSRect(x: 0, y: 0, width: width, height: t.intrinsicContentSize.height)
        t.layoutSubtreeIfNeeded()
        return t
    }

    private func icons(_ names: String...) -> [ThemedToolBar.Item] {
        names.map { .button(.init(symbol: $0)) }
    }

    private func alpha(_ c: CGColor?) -> CGFloat {
        guard let c, let n = NSColor(cgColor: c)?.usingColorSpace(.sRGB) else { return -1 }
        return n.alphaComponent
    }
    /// Flatten the probe's `[Int: CGColor?]` double-optional lookup.
    private func overlayAlpha(_ t: ThemedToolBar, _ i: Int) -> CGFloat {
        alpha(t.toolBarProbe.buttonOverlay[i] ?? nil)
    }

    // MARK: - Density variant → minHeight / intrinsic height

    func testVariantMinHeight() {
        XCTAssertEqual(bar([]) { $0.variant = .regular }.toolBarProbe.minHeight, 64)
        XCTAssertEqual(bar([]) { $0.variant = .dense }.toolBarProbe.minHeight, 48)
        XCTAssertEqual(bar([]) { $0.variant = .compact }.toolBarProbe.minHeight, 40)
    }

    func testIntrinsicHeightIsVariantMinHeight() {
        XCTAssertEqual(bar(icons("a")) { $0.variant = .dense }.intrinsicContentSize.height, 48)
    }

    // MARK: - Surface (MUI AppBar color)

    func testSurfaceFillPerCase() {
        let p = palette()
        sameColor(bar([]) { $0.surface = .primary }.toolBarProbe.surfaceFill, p.primary,
                  "primary bar fills with the primary role")
        sameColor(bar([]) { $0.surface = .secondary }.toolBarProbe.surfaceFill, p.secondary,
                  "secondary bar fills with the secondary role")
        XCTAssertGreaterThan(alpha(bar([]) { $0.surface = .surface }.toolBarProbe.surfaceFill), 0,
                             "a surface bar has a neutral fill")
        XCTAssertEqual(alpha(bar([]) { $0.surface = .transparent }.toolBarProbe.surfaceFill), 0,
                       accuracy: 0.001, "a transparent bar paints nothing")
    }

    // MARK: - Elevation ↔ hairline (flat vs lifted)

    func testFlatSquareBarShowsHairlineNotShadow() {
        let p = palette()
        let t = bar([]) { $0.elevation = 0; $0.surface = .surface; $0.corners = .square }
        XCTAssertEqual(t.toolBarProbe.shadowOpacity, 0, accuracy: 0.001, "flat = no shadow")
        XCTAssertTrue(t.toolBarProbe.hairlineVisible, "flat square bar gets a bottom hairline")
        sameColor(t.toolBarProbe.hairlineColor, p.border, "hairline = the border role")
    }

    func testElevatedBarShowsShadowNotHairline() {
        let t = bar([]) { $0.elevation = 6 }
        XCTAssertGreaterThan(t.toolBarProbe.shadowOpacity, 0, "elevation > 0 lifts a drop shadow")
        XCTAssertFalse(t.toolBarProbe.hairlineVisible, "an elevated bar drops the hairline")
    }

    func testRoundedAndTransparentSuppressHairline() {
        XCTAssertFalse(bar([]) { $0.corners = .rounded }.toolBarProbe.hairlineVisible,
                       "a rounded panel has no bottom hairline")
        XCTAssertFalse(bar([]) { $0.surface = .transparent }.toolBarProbe.hairlineVisible,
                       "a transparent bar has no hairline")
    }

    func testCornerRadiusPerCorners() {
        XCTAssertEqual(bar([]) { $0.corners = .square }.toolBarProbe.cornerRadius, 0)
        XCTAssertEqual(bar([]) { $0.corners = .rounded }.toolBarProbe.cornerRadius, 8)
    }

    // MARK: - Item geometry (icon-only square vs labelled pill)

    func testIconOnlyButtonIsSquareAtControlHeight() {
        let f = bar(icons("plus")) { $0.variant = .regular }.frame(ofItem: 0)!
        XCTAssertEqual(f.width, f.height, accuracy: 0.5, "icon-only ⇒ a square")
        XCTAssertEqual(f.height, 36, accuracy: 0.5, "regular control height = medium (36)")
    }

    func testLabelledButtonIsWiderThanTall() {
        let f = bar([.button(.init(title: "Compose", symbol: "note-pencil"))]).frame(ofItem: 0)!
        XCTAssertGreaterThan(f.width, f.height, "a labelled button is a pill, not a square")
    }

    func testDividerItemIsAnInsetHairlineRule() {
        let d = bar([.button(.init(symbol: "a")), .divider, .button(.init(symbol: "b"))]) {
            $0.variant = .regular
        }.frame(ofItem: 1)!
        XCTAssertEqual(d.height, 32, accuracy: 0.5, "divider = half the regular bar height (64 × 0.5)")
        XCTAssertLessThan(d.width, 4, "a hairline-thin vertical rule")
    }

    // MARK: - Flex sections (MUI flexGrow spacers)

    func testFlexibleSpacePushesTrailingItemToRightGutter() {
        let t = bar([.button(.init(symbol: "a")), .flexibleSpace, .button(.init(symbol: "b"))], width: 400)
        XCTAssertEqual(t.frame(ofItem: 2)!.maxX, 400 - t.toolBarProbe.gutter, accuracy: 1,
                       "a flexible space hugs the trailing item to the right gutter")
    }

    func testNoFlexKeepsContentLeftAligned() {
        let t = bar(icons("a", "b"), width: 400)
        XCTAssertEqual(t.frame(ofItem: 0)!.minX, t.toolBarProbe.gutter, accuracy: 0.5,
                       "the first item starts at the leading gutter")
        XCTAssertLessThan(t.frame(ofItem: 1)!.maxX, 200, "no flex ⇒ content stays left, not pushed right")
    }

    func testIntrinsicWidthFiniteWithoutFlexNoneWithFlex() {
        XCTAssertNotEqual(bar(icons("a", "b")).intrinsicContentSize.width, NSView.noIntrinsicMetric)
        XCTAssertGreaterThan(bar(icons("a", "b")).intrinsicContentSize.width, 0)
        XCTAssertEqual(bar([.button(.init(symbol: "a")), .flexibleSpace, .button(.init(symbol: "b"))])
                        .intrinsicContentSize.width, NSView.noIntrinsicMetric,
                       "a flexible space drops the intrinsic width so the host stretches the bar")
    }

    // MARK: - Spacing / gutters

    func testItemSpacingBetweenAdjacentButtons() {
        let t = bar(icons("a", "b"), width: 400) { $0.gutter = 0; $0.itemSpacing = 20; $0.variant = .regular }
        XCTAssertEqual(t.frame(ofItem: 1)!.minX - t.frame(ofItem: 0)!.maxX, 20, accuracy: 0.5,
                       "itemSpacing sits between adjacent content items")
    }

    func testFixedSpaceAddsAGap() {
        let t = bar([.button(.init(symbol: "a")), .fixedSpace(50), .button(.init(symbol: "b"))],
                    width: 400) { $0.gutter = 0; $0.itemSpacing = 0 }
        XCTAssertEqual(t.frame(ofItem: 2)!.minX - t.frame(ofItem: 0)!.maxX, 50, accuracy: 0.5)
    }

    func testDisableGuttersStartsAtEdge() {
        let t = bar(icons("a"), width: 400) { $0.gutter = 0 }
        XCTAssertEqual(t.frame(ofItem: 0)!.minX, 0, accuracy: 0.5, "gutter 0 = an edge-to-edge bar")
    }

    // MARK: - Activation dispatch

    func testItemTapFiresOnItemClickWithIndex() {
        let t = bar(icons("a", "b", "c"))
        var clicked: Int?
        t.onItemClick = { clicked = $0 }
        t.simulateItemTapForTesting(2)
        XCTAssertEqual(clicked, 2, "a button item's tap fires onItemClick with its index")
    }

    // MARK: - Hover (bar-driven in a non-key panel; reported in both modes)

    func testNonActivatingPanelDrivesItemHoverAppearance() {
        let t = bar(icons("a", "b", "c")) { $0.trackingMode = .nonActivatingPanel }
        var arg: Int?; var fired = false
        t.onItemHover = { fired = true; arg = $0 }
        t.simulateHoverForTesting(1)
        XCTAssertTrue(fired); XCTAssertEqual(arg, 1)
        XCTAssertGreaterThan(overlayAlpha(t, 1), 0, "panel mode forces the hovered item's wash")
        XCTAssertEqual(overlayAlpha(t, 0), 0, accuracy: 0.001, "other items stay at rest")
        XCTAssertEqual(overlayAlpha(t, 2), 0, accuracy: 0.001)
    }

    func testStandardModeReportsHoverButLeavesAppearanceToTheButton() {
        let t = bar(icons("a", "b", "c")) { $0.trackingMode = .standard }
        var arg: Int?; var fired = false
        t.onItemHover = { fired = true; arg = $0 }
        t.simulateHoverForTesting(1)
        XCTAssertTrue(fired); XCTAssertEqual(arg, 1, "standard mode still reports the hovered item")
        XCTAssertEqual(overlayAlpha(t, 1), 0, accuracy: 0.001,
                       "standard mode leaves item visuals to the buttons' own tracking")
    }

    func testPreviewHoveredItemForcesAppearanceForCapture() {
        let t = bar(icons("a", "b", "c")) { $0.previewHoveredItem = 1 }   // standard tracking
        XCTAssertGreaterThan(overlayAlpha(t, 1), 0, "previewHoveredItem forces the wash regardless of mode")
        XCTAssertEqual(overlayAlpha(t, 0), 0, accuracy: 0.001)
    }

    func testHoverChangeIsExclusive() {
        let t = bar(icons("a", "b", "c")) { $0.trackingMode = .nonActivatingPanel }
        t.simulateHoverForTesting(0)
        XCTAssertGreaterThan(overlayAlpha(t, 0), 0)
        t.simulateHoverForTesting(2)
        XCTAssertEqual(overlayAlpha(t, 0), 0, accuracy: 0.001, "the prior hover cleared")
        XCTAssertGreaterThan(overlayAlpha(t, 2), 0, "the new hover rendered")
    }
}
