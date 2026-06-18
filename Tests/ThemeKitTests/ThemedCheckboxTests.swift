// ThemeKit / ThemedCheckbox tests — DETERMINISTIC in headless CI (no Xcode
// locally → these first compile + run in CI). State is driven via the preview…
// overrides and asserted through the DEBUG checkboxProbe — no synthetic events.
// The live check-draw-in + hover circle 演出 is proven in prism, not here.

import XCTest
import AppKit
import Palette
import PaletteKit
@testable import ThemeKit

@MainActor
final class ThemedCheckboxTests: XCTestCase {

    private func palette() -> ResolvedPalette { resolve(.terminal) }

    private func sameColor(_ a: CGColor?, _ b: NSColor, accuracy: CGFloat = 0.01,
                           _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
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
                                      g: Double(s.greenComponent), b: Double(s.blueComponent))
        return prefersBlackForeground(fillRelLuminance: l) ? .black : .white
    }
    private func box(_ configure: (ThemedCheckbox) -> Void) -> ThemedCheckbox {
        let c = ThemedCheckbox(palette: palette())
        configure(c)
        c.frame = NSRect(x: 0, y: 0, width: 200, height: 42)
        c.layoutSubtreeIfNeeded()
        return c
    }

    // MARK: - Glyph + fill per state

    func testUncheckedIsOutlineNoFill() {
        let p = palette()
        let c = box { $0.previewChecked = false }.checkboxProbe
        XCTAssertEqual(alpha(c.boxFill), 0, accuracy: 0.001, "unchecked has no fill")
        XCTAssertTrue(c.strokeVisible, "unchecked shows the outline ring")
        sameColor(c.boxStroke, p.ink(.strong, of: .foreground), "outline = foreground @ strong")
        XCTAssertEqual(c.glyphStrokeEnd, 0, "no glyph drawn when unchecked")
    }

    func testCheckedFillsPrimaryWithContrastTick() {
        let p = palette()
        let c = box { $0.previewChecked = true }.checkboxProbe
        sameColor(c.boxFill, p.primary, "checked fill = primary")
        XCTAssertFalse(c.strokeVisible, "the outline ring fades out when filled")
        XCTAssertEqual(c.glyphStrokeEnd, 1, "the check is fully drawn")
        XCTAssertFalse(c.glyphIsDash, "checked draws the tick, not the dash")
        sameColor(c.glyphColor, contrastInk(on: p.primary), "tick = best-contrast on primary (onPrimary)")
    }

    func testIndeterminateFillsPrimaryWithDash() {
        let p = palette()
        let c = box { $0.previewIndeterminate = true }.checkboxProbe
        sameColor(c.boxFill, p.primary)
        XCTAssertTrue(c.glyphIsDash, "indeterminate draws the dash")
        XCTAssertEqual(c.glyphStrokeEnd, 1)
        sameColor(c.glyphColor, contrastInk(on: p.primary))
    }

    func testDisabledCheckedRecolorsWholeGlyphToMuted() {
        let p = palette()
        let c = box { $0.previewChecked = true; $0.isEnabled = false }.checkboxProbe
        sameColor(c.boxFill, p.muted, "disabled fill = muted (not primary)")
        sameColor(c.glyphColor, contrastInk(on: p.muted), "tick contrast computed on the muted fill")
    }

    // MARK: - State layer (hover circle) + focus ring

    func testHoverCircleRootIsForegroundUncheckedPrimaryChecked() {
        let p = palette()
        let unchecked = box { $0.previewChecked = false; $0.previewHovered = true }.checkboxProbe
        sameColor(unchecked.hoverCircleColor, p.ink(.faint, of: .foreground),
                  "unchecked hover circle roots on foreground")
        let checked = box { $0.previewChecked = true; $0.previewHovered = true }.checkboxProbe
        sameColor(checked.hoverCircleColor, p.ink(.faint, of: .primary),
                  "checked hover circle roots on primary")
    }
    func testPressedCircleDeeperThanHover() {
        let hover = box { $0.previewChecked = true; $0.previewHovered = true }.checkboxProbe
        let press = box { $0.previewChecked = true; $0.previewPressed = true }.checkboxProbe
        XCTAssertGreaterThan(alpha(press.hoverCircleColor), alpha(hover.hoverCircleColor))
    }
    func testRestingHasNoCircle() {
        XCTAssertEqual(alpha(box { $0.previewChecked = false }.checkboxProbe.hoverCircleColor), 0, accuracy: 0.001)
    }
    func testFocusRingShownAndPrimary() {
        let p = palette()
        let c = box { $0.previewFocused = true }.checkboxProbe
        XCTAssertEqual(c.focusRingOpacity, 1)
        sameColor(c.focusRingStroke, p.primary, "focus ring strokes primary")
        let c2 = box { _ in }.checkboxProbe
        XCTAssertEqual(c2.focusRingOpacity, 0, "ring hidden when not focused")
    }
    func testDisabledSuppressesForcedHoverAndFocus() {
        let c = box { $0.isEnabled = false; $0.previewHovered = true; $0.previewFocused = true }.checkboxProbe
        XCTAssertEqual(alpha(c.hoverCircleColor), 0, accuracy: 0.001, "disabled = no hover circle")
        XCTAssertEqual(c.focusRingOpacity, 0, "disabled = no focus ring")
    }

    // MARK: - Label + metrics

    func testTargetSizePerSize() {
        XCTAssertEqual(box { $0.size = .small }.checkboxProbe.target, 38)
        XCTAssertEqual(box { $0.size = .medium }.checkboxProbe.target, 42)
    }
    func testBareBoxIsSquareLabelWidensIntrinsic() {
        let bare = box { _ in }
        XCTAssertEqual(bare.intrinsicContentSize.width, 42, "bare box = the target square")
        let labeled = box { $0.label = "Remember me" }
        XCTAssertGreaterThan(labeled.intrinsicContentSize.width, 42, "a label widens the intrinsic content")
        XCTAssertEqual(labeled.intrinsicContentSize.height, 42, "height stays the square")
    }
    func testLabelColorEnabledVsDisabled() {
        let p = palette()
        sameColor(box { $0.label = "x" }.checkboxProbe.labelColor, p.foreground)
        sameColor(box { $0.label = "x"; $0.isEnabled = false }.checkboxProbe.labelColor, p.muted)
    }

    // MARK: - Toggle / onChange contract

    func testUserToggleCyclesAndFiresOnChange() {
        let c = box { _ in }
        var changes: [Bool] = []
        c.onChange = { changes.append($0) }
        c.toggleForTesting()          // off → on
        XCTAssertTrue(c.isChecked)
        c.toggleForTesting()          // on → off
        XCTAssertFalse(c.isChecked)
        XCTAssertEqual(changes, [true, false], "onChange carries the new value each toggle")
    }
    func testIndeterminateTogglesToCheckedAndClears() {
        let c = box { $0.isIndeterminate = true }
        var last: Bool?
        c.onChange = { last = $0 }
        c.toggleForTesting()
        XCTAssertTrue(c.isChecked, "indeterminate resolves to checked")
        XCTAssertFalse(c.isIndeterminate, "indeterminate is cleared")
        XCTAssertEqual(last, true)
    }
    func testProgrammaticIsCheckedDoesNotFireOnChange() {
        let c = box { _ in }
        var fired = false
        c.onChange = { _ in fired = true }
        c.isChecked = true            // programmatic — must not call back
        XCTAssertFalse(fired, "a programmatic isChecked = never fires onChange")
    }

    // MARK: - Accessibility

    func testAccessibilityRoleAndValue() {
        let c = box { $0.label = "Agree" }
        XCTAssertEqual(c.accessibilityRole(), .checkBox)
        XCTAssertEqual(c.accessibilityLabel(), "Agree")
        // Tri-state AX value, driven by the REAL bound props (preview overrides
        // don't re-run syncAccessibility): 1 = on, 0 = off, -1 = mixed.
        XCTAssertEqual((box { $0.isChecked = true }.accessibilityValue() as? NSNumber)?.intValue, 1)
        XCTAssertEqual((box { _ in }.accessibilityValue() as? NSNumber)?.intValue, 0)
        XCTAssertEqual((box { $0.isIndeterminate = true }.accessibilityValue() as? NSNumber)?.intValue, -1)
    }

    /// The real Space-key plumbing: one flash → one toggle, and a second Space
    /// while the flash is in flight is dropped (the isFlashing re-entrancy guard).
    func testSpaceKeyTogglesOnceAndGuardsReentry() {
        let c = box { _ in }
        var changes = 0
        c.onChange = { _ in changes += 1 }
        c.spaceKeyForTesting()                       // starts the flash
        XCTAssertTrue(c.isFlashingForTesting, "a flash is in flight")
        c.spaceKeyForTesting()                       // re-entry while flashing → dropped
        let e = expectation(description: "flash settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { e.fulfill() }
        wait(for: [e], timeout: 1.0)
        XCTAssertEqual(changes, 1, "exactly one toggle per press; the re-entry was dropped")
        XCTAssertTrue(c.isChecked)
    }
}
