// ThemeKit / ThemedDivider tests — DETERMINISTIC in headless CI (no Xcode
// locally → these first run in CI). A divider is static (no focus / hover /
// animation), so every assertion reads the rendered rule off the DEBUG
// `dividerProbe` after a synchronous `layoutSubtreeIfNeeded()` — no window,
// no synthetic events, no timing. Colours are compared by sRGB components
// (CGColor identity is colour-space-fragile across two `resolve()` calls).

import XCTest
import AppKit
import Palette
import PaletteKit
@testable import ThemeKit   // for the DEBUG `dividerProbe`
import TestSupport

@MainActor
final class ThemedDividerTests: XCTestCase {

    private func palette() -> ResolvedPalette { resolve(.terminal) }

    private func laidOut(width: CGFloat = 200, height: CGFloat = 14) -> ThemedDivider {
        let d = ThemedDivider(palette: palette())
        d.frame = NSRect(x: 0, y: 0, width: width, height: height)
        d.layoutSubtreeIfNeeded()
        return d
    }

    /// A horizontal divider tints its rule with the canonical `border` role.
    func testHorizontalDefaultUsesBorderRole() {
        let p = palette()
        let d = ThemedDivider(palette: p)
        d.frame = NSRect(x: 0, y: 0, width: 200, height: 14)
        d.layoutSubtreeIfNeeded()
        sameColor(d.dividerProbe.strokeColor, p.border, accuracy: 0.002, "rule uses palette.border")
        XCTAssertFalse(d.dividerProbe.isVertical)
    }

    /// Orientation owns the thickness axis and stretches the other (the
    /// `flexItem` equivalent): horizontal owns height, vertical owns width.
    func testOrientationFlipsIntrinsicAxis() {
        let d = ThemedDivider(palette: palette())

        XCTAssertEqual(d.intrinsicContentSize.width, NSView.noIntrinsicMetric,
                       "horizontal spans its width")
        XCTAssertGreaterThan(d.intrinsicContentSize.height, 0,
                             "horizontal owns a thin height")

        d.orientation = .vertical
        XCTAssertEqual(d.intrinsicContentSize.height, NSView.noIntrinsicMetric,
                       "vertical spans its height")
        XCTAssertGreaterThan(d.intrinsicContentSize.width, 0,
                             "vertical owns a thin width")
    }

    /// A theme switch RE-TINTS the rule immediately (snap, no cross-fade) —
    /// the regression the `applyTheme` layerTxn(animated:false) guards.
    func testThemeSwitchRetintsBorder() {
        let d = laidOut()
        let dracula = resolve(.dracula)
        d.palette = dracula
        sameColor(d.dividerProbe.strokeColor, dracula.border, accuracy: 0.002,
                  "rule re-tints to the new theme's border on palette assign")
    }

    /// The variant shifts the rule's leading origin: fullWidth flush, inset by
    /// `inset` (72), middle by 16.
    func testVariantShiftsRuleOrigin() {
        let full = laidOut(); full.variant = .fullWidth; full.layoutSubtreeIfNeeded()
        XCTAssertEqual(full.dividerProbe.ruleFrame.minX, 0, accuracy: 0.5)

        let inset = laidOut(); inset.variant = .inset; inset.layoutSubtreeIfNeeded()
        XCTAssertEqual(inset.dividerProbe.ruleFrame.minX, 72, accuracy: 0.5)

        let middle = laidOut(); middle.variant = .middle; middle.layoutSubtreeIfNeeded()
        XCTAssertEqual(middle.dividerProbe.ruleFrame.minX, 16, accuracy: 0.5)
        // …and trims the trailing edge symmetrically (16 each side of 200).
        XCTAssertEqual(middle.dividerProbe.ruleFrame.maxX, 200 - 16, accuracy: 0.5)
    }

    /// The default rule is a hairline — one device pixel (≤ 1 pt at any scale),
    /// and strictly positive (it must actually render).
    func testHairlineThicknessIsThin() {
        let t = laidOut().dividerProbe.thickness
        XCTAssertGreaterThan(t, 0, "the rule has a positive thickness")
        XCTAssertLessThanOrEqual(t, 1.0 + .ulpOfOne, "default rule is ≤ 1 pt (a device hairline)")
    }

    /// `deviceHairline = false` honours `thickness` literally in points.
    func testNonHairlineHonoursThicknessInPoints() {
        let d = laidOut()
        d.deviceHairline = false
        d.thickness = 2
        d.layoutSubtreeIfNeeded()
        XCTAssertEqual(d.dividerProbe.thickness, 2, accuracy: 0.01)
    }

    /// A degenerate `thickness` (0 / negative) still draws at least a device
    /// hairline rather than vanishing — the `ruleThickness` floor.
    func testDegenerateThicknessStillRenders() {
        let d = laidOut()
        d.deviceHairline = false
        d.thickness = 0
        d.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(d.dividerProbe.thickness, 0,
                             "thickness 0 floors to a device hairline, not invisible")
    }

    /// `.inset` is a horizontal-list affordance — a VERTICAL `.inset` rule falls
    /// back to fullWidth, so a short column separator never silently vanishes
    /// (the 72 pt inset would otherwise clamp a sub-72 pt rule to zero height).
    func testVerticalInsetFallsBackToFullWidth() {
        let d = ThemedDivider(palette: palette())
        d.orientation = .vertical
        d.variant = .inset
        d.frame = NSRect(x: 0, y: 0, width: 14, height: 30)   // shorter than `inset` (72)
        d.layoutSubtreeIfNeeded()
        XCTAssertEqual(d.dividerProbe.ruleFrame.height, 30, accuracy: 0.5,
                       "vertical .inset spans the full height (inset ignored)")
    }

    /// The divider is decorative — clicks fall THROUGH to whatever is behind it,
    /// at ANY point (the override is point-insensitive by design).
    func testHitTestPassesThrough() {
        let d = laidOut()
        XCTAssertNil(d.hitTest(NSPoint(x: 5, y: 1)), "a divider never swallows a click")
        XCTAssertNil(d.hitTest(NSPoint(x: 999, y: 999)), "…anywhere, in or out of bounds")
    }

    /// Decorative ⇒ AX-ignored (VoiceOver skips it; the host announces structure).
    func testAccessibilityIgnored() {
        XCTAssertFalse(ThemedDivider(palette: palette()).isAccessibilityElement())
    }

    /// `label` toggles the text-in-divider — but only for a HORIZONTAL rule
    /// (vertical + alignment are out of scope; the probe reflects that).
    func testLabelPresenceIsHorizontalOnly() {
        let d = laidOut()
        XCTAssertFalse(d.dividerProbe.hasLabel, "no label by default")

        d.label = "OR"
        XCTAssertTrue(d.dividerProbe.hasLabel, "a horizontal label shows")

        d.orientation = .vertical
        XCTAssertFalse(d.dividerProbe.hasLabel, "a vertical rule ignores the label")

        d.orientation = .horizontal
        d.label = nil
        XCTAssertFalse(d.dividerProbe.hasLabel, "clearing the label removes it")
    }
}
