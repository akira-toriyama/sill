// ThemeKit / ThemedButtonGroup tests — DETERMINISTIC in headless CI (no Xcode
// locally → these first compile + run in CI). They drive the joined geometry via
// the DEBUG `groupProbe` (per-member corners / edges / grouped-shadow, divider,
// selection) — no synthetic events. The live seams / hover / selection 演出 is
// proven in prism, not here.

import XCTest
import AppKit
import Palette
import PaletteKit
@testable import ThemeKit   // for the DEBUG groupProbe / buttonProbe

@MainActor
final class ThemedButtonGroupTests: XCTestCase {

    private func palette() -> ResolvedPalette { resolve(.terminal) }

    private func sameColor(_ a: CGColor?, _ b: NSColor, accuracy: CGFloat = 0.01,
                           _ msg: String = "", file: StaticString = #filePath,
                           line: UInt = #line) {
        guard let a, let an = NSColor(cgColor: a)?.usingColorSpace(.sRGB),
              let bn = b.usingColorSpace(.sRGB) else {
            return XCTFail("colour unconvertible: \(msg)", file: file, line: line)
        }
        XCTAssertEqual(an.redComponent,   bn.redComponent,   accuracy: accuracy, msg, file: file, line: line)
        XCTAssertEqual(an.greenComponent, bn.greenComponent, accuracy: accuracy, msg, file: file, line: line)
        XCTAssertEqual(an.blueComponent,  bn.blueComponent,  accuracy: accuracy, msg, file: file, line: line)
        XCTAssertEqual(an.alphaComponent, bn.alphaComponent, accuracy: accuracy, msg, file: file, line: line)
    }

    private func alpha(_ c: CGColor?) -> CGFloat {
        guard let c, let n = NSColor(cgColor: c)?.usingColorSpace(.sRGB) else { return -1 }
        return n.alphaComponent
    }

    private func contrastInk(on c: NSColor) -> NSColor {
        let s = c.usingColorSpace(.sRGB) ?? c
        let l = wcagRelativeLuminance(r: Double(s.redComponent),
                                      g: Double(s.greenComponent),
                                      b: Double(s.blueComponent))
        return prefersBlackForeground(fillRelLuminance: l) ? .black : .white
    }

    private func group(_ titles: [String] = ["One", "Two", "Three"],
                       _ configure: (ThemedButtonGroup) -> Void = { _ in }) -> ThemedButtonGroup {
        let g = ThemedButtonGroup(palette: palette())
        g.segments = titles.map { ThemedButtonGroup.Segment($0) }
        configure(g)
        g.frame = NSRect(x: 0, y: 0, width: 400, height: 120)
        g.layoutSubtreeIfNeeded()
        return g
    }

    private let leftPair:   CACornerMask = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
    private let rightPair:  CACornerMask = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
    private let topPair:    CACornerMask = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    private let bottomPair: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    private let allCorners: CACornerMask =
        [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner, .layerMinXMaxYCorner]

    // MARK: - Corner merging

    func testHorizontalCornersRoundOnlyOuter() {
        let c = group { $0.orientation = .horizontal; $0.variant = .outlined }.groupProbe.perMemberCorners
        XCTAssertEqual(c[0], leftPair, "first rounds left, squares the seam")
        XCTAssertEqual(c[1], [], "middle is fully square")
        XCTAssertEqual(c[2], rightPair, "last rounds right")
    }

    func testVerticalCornersRoundOnlyOuter() {
        let c = group { $0.orientation = .vertical; $0.variant = .outlined }.groupProbe.perMemberCorners
        XCTAssertEqual(c[0], topPair, "first (top) rounds the top corners")
        XCTAssertEqual(c[1], [])
        XCTAssertEqual(c[2], bottomPair, "last (bottom) rounds the bottom corners")
    }

    func testLoneSegmentRoundsAllCorners() {
        let c = group(["Only"]).groupProbe.perMemberCorners
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0], allCorners, "a lone member is a plain rounded button")
    }

    // MARK: - Border-edge seams (outlined)

    func testOutlinedHorizontalDropsTrailingEdgeExceptLast() {
        let e = group { $0.variant = .outlined; $0.orientation = .horizontal }.groupProbe.perMemberEdges
        let minusRight = ThemedButton.BorderEdges.all.subtracting(.right)
        XCTAssertEqual(e[0], minusRight, "first drops its right (shared) edge")
        XCTAssertEqual(e[1], minusRight, "middle drops its right edge")
        XCTAssertEqual(e[2], .all, "last keeps a closed perimeter")
    }

    func testOutlinedVerticalDropsBottomEdgeExceptLast() {
        let e = group { $0.variant = .outlined; $0.orientation = .vertical }.groupProbe.perMemberEdges
        let minusBottom = ThemedButton.BorderEdges.all.subtracting(.bottom)
        XCTAssertEqual(e[0], minusBottom)
        XCTAssertEqual(e[1], minusBottom)
        XCTAssertEqual(e[2], .all)
    }

    // MARK: - Elevation / dividers per variant

    func testContainedUsesOneGroupShadowMembersShadowless() {
        let g = group { $0.variant = .contained }.groupProbe
        XCTAssertTrue(g.perMemberGroupedShadow.allSatisfy { $0 }, "members forgo their own shadow")
        XCTAssertTrue(g.groupShadowVisible, "the group owns one shadow")
    }

    func testTextAndOutlinedHaveNoGroupShadow() {
        XCTAssertFalse(group { $0.variant = .text }.groupProbe.groupShadowVisible)
        XCTAssertFalse(group { $0.variant = .outlined }.groupProbe.groupShadowVisible)
        XCTAssertTrue(group { $0.variant = .text }.groupProbe.perMemberGroupedShadow.allSatisfy { !$0 })
    }

    func testDisableElevationHidesGroupShadow() {
        XCTAssertFalse(group { $0.variant = .contained; $0.disableElevation = true }
                        .groupProbe.groupShadowVisible)
    }

    func testDividerCountAndVisibilityPerVariant() {
        XCTAssertEqual(group { $0.variant = .text }.groupProbe.dividerCount, 2, "n-1 seams")
        XCTAssertTrue(group { $0.variant = .text }.groupProbe.dividerVisible)
        XCTAssertTrue(group { $0.variant = .contained }.groupProbe.dividerVisible)
        XCTAssertFalse(group { $0.variant = .outlined }.groupProbe.dividerVisible,
                       "outlined seams ARE the overlapped border, no divider layer")
    }

    func testDividerColorPerVariant() {
        let p = palette()
        sameColor(group { $0.variant = .text }.groupProbe.dividerColor,
                  p.primary.withAlphaComponent(0.5), "text divider = role @ 0.5")
        sameColor(group { $0.variant = .contained }.groupProbe.dividerColor,
                  contrastInk(on: p.primary).withAlphaComponent(0.25), "contained divider = contrast ink @ 0.25")
        sameColor(group { $0.variant = .text; $0.isEnabled = false }.groupProbe.dividerColor,
                  p.muted, "disabled divider = muted")
    }

    // MARK: - Fan-out

    func testSizeFansToEveryMember() {
        let h = group { $0.size = .large }.groupProbe.perMemberHeight
        XCTAssertTrue(h.allSatisfy { $0 == 42 }, "every member adopts the group size (large = 42)")
    }

    func testEnabledFansAndPerSegmentDisableAnds() {
        XCTAssertTrue(group { $0.isEnabled = false }.groupProbe.perMemberEnabled.allSatisfy { !$0 },
                      "group disable fans to all members")
        let g = ThemedButtonGroup(palette: palette())
        g.segments = [ThemedButtonGroup.Segment("A"),
                      ThemedButtonGroup.Segment("B", isEnabled: false),
                      ThemedButtonGroup.Segment("C")]
        XCTAssertEqual(g.groupProbe.perMemberEnabled, [true, false, true],
                       "a per-segment disable ANDs with the group")
    }

    // MARK: - Selection

    func testActionsModeNeverMarksASegmentActive() {
        let g = group { $0.mode = .actions; $0.variant = .outlined; $0.selectedIndex = 1 }
        XCTAssertNil(g.groupProbe.selectedMember, "actions mode ignores selection")
        XCTAssertTrue(g.groupProbe.perMemberOverlay.allSatisfy { alpha($0) == 0 },
                      "no member is rendered active in actions mode")
    }

    /// The active member is actually RENDERED in the pressed tier (read the
    /// member's overlay), and selecting another clears the prior — not just the
    /// group's bookkeeping.
    func testSegmentedSelectionRendersActiveAndIsExclusive() {
        let g = group { $0.mode = .segmented; $0.variant = .outlined; $0.selectedIndex = 1 }
        var ov = g.groupProbe.perMemberOverlay
        XCTAssertEqual(alpha(ov[0]), 0, accuracy: 0.001)
        XCTAssertEqual(alpha(ov[1]), 0.16, accuracy: 0.001, "selected member held at the pressed tier")
        XCTAssertEqual(alpha(ov[2]), 0, accuracy: 0.001)
        g.selectedIndex = 2
        ov = g.groupProbe.perMemberOverlay
        XCTAssertEqual(alpha(ov[1]), 0, accuracy: 0.001, "the prior selection cleared")
        XCTAssertEqual(alpha(ov[2]), 0.16, accuracy: 0.001, "the new selection rendered")
    }

    func testPreviewSelectedIndexRendersForCapture() {
        let g = group { $0.mode = .segmented; $0.variant = .outlined; $0.previewSelectedIndex = 0 }
        XCTAssertEqual(g.groupProbe.selectedMember, 0)
        XCTAssertEqual(alpha(g.groupProbe.perMemberOverlay[0]), 0.16, accuracy: 0.001)
    }

    /// The dispatch contract: actions fires `onTap` only; segmented updates
    /// `selectedIndex` + fires `onSelect` only.
    func testTapDispatchActionsVsSegmented() {
        let a = group { $0.mode = .actions }
        var tapped: Int?; var selectedFired: Int?
        a.onTap = { tapped = $0 }; a.onSelect = { selectedFired = $0 }
        a.simulateTapForTesting(1)
        XCTAssertEqual(tapped, 1, "actions fires onTap")
        XCTAssertNil(a.selectedIndex, "actions never sets selection")
        XCTAssertNil(selectedFired, "actions never fires onSelect")

        let s = group { $0.mode = .segmented }
        var tapped2: Int?; var selected2: Int?
        s.onTap = { tapped2 = $0 }; s.onSelect = { selected2 = $0 }
        s.simulateTapForTesting(2)
        XCTAssertEqual(selected2, 2, "segmented fires onSelect")
        XCTAssertEqual(s.selectedIndex, 2, "segmented updates selectedIndex")
        XCTAssertNil(tapped2, "segmented never fires onTap")
    }

    // MARK: - Roving focus (pure index math)

    func testRovingFocusSkipsDisabledAndClampsAtEnds() {
        let g = ThemedButtonGroup(palette: palette())
        g.segments = [ThemedButtonGroup.Segment("A"),
                      ThemedButtonGroup.Segment("B", isEnabled: false),
                      ThemedButtonGroup.Segment("C")]
        XCTAssertEqual(g.nextEnabledIndexForTesting(from: 0, forward: true), 2, "skips the disabled middle")
        XCTAssertEqual(g.nextEnabledIndexForTesting(from: 2, forward: false), 0, "skips it backward too")
        XCTAssertNil(g.nextEnabledIndexForTesting(from: 2, forward: true), "no wrap off the end")
        XCTAssertNil(g.nextEnabledIndexForTesting(from: 0, forward: false), "no wrap off the start")
    }

    // MARK: - Vertical intrinsic height (the overlap arithmetic)

    func testVerticalIntrinsicHeight() {
        // 3 × medium (h=36); outlined overlaps 1pt per seam, text/contained don't.
        XCTAssertEqual(group { $0.orientation = .vertical; $0.variant = .outlined }
                        .intrinsicContentSize.height, 3 * 36 - 2 * 1, "outlined overlaps 1pt per seam")
        XCTAssertEqual(group { $0.orientation = .vertical; $0.variant = .text }
                        .intrinsicContentSize.height, 3 * 36, "text members butt with no overlap")
    }

    // MARK: - Intrinsic size

    func testHorizontalIntrinsicAndFullWidth() {
        let g = group { $0.variant = .outlined }
        XCTAssertEqual(g.intrinsicContentSize.height, 36, "uniform member height")
        XCTAssertGreaterThan(g.intrinsicContentSize.width, 0)
        let fw = group { $0.fullWidth = true }
        XCTAssertEqual(fw.intrinsicContentSize.width, NSView.noIntrinsicMetric,
                       "fullWidth drops the intrinsic width")
    }

    // MARK: - Standalone ThemedButton regression (the additive knobs default to today)

    func testStandaloneButtonGroupingKnobsAreNoOp() {
        let b = ThemedButton(palette: palette())
        b.variant = .outlined
        b.frame = NSRect(x: 0, y: 0, width: 120, height: 36)
        b.layoutSubtreeIfNeeded()
        XCTAssertEqual(b.buttonProbe.maskedCorners, allCorners, "all corners rounded by default")
        XCTAssertEqual(b.buttonProbe.drawnBorderEdges, .all, "closed perimeter by default")
        XCTAssertFalse(b.buttonProbe.groupedShadow, "keeps its own shadow by default")
        // the standalone border path still spans the inset button rect
        let bounds = b.buttonProbe.borderPathBounds
        XCTAssertEqual(bounds.width, 119, accuracy: 1.0, "border path ≈ the inset button rect")
    }
}
