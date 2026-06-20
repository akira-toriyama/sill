// ThemeKit / ThemedChip tests — DETERMINISTIC in headless CI (no Xcode locally →
// these first run in CI). Real hover / press / keyboard focus need a key window +
// synthetic events (flaky headless), so these drive each state through the
// `preview…` overrides and read the rendered result via the DEBUG `chipProbe`,
// which IS deterministic. The live 演出 is proven in prism, not here.

import XCTest
import AppKit
import Palette
import PaletteKit
@testable import ThemeKit   // for the DEBUG `chipProbe`

@MainActor
final class ThemedChipTests: XCTestCase {

    private func palette() -> ResolvedPalette { resolve(.terminal) }

    /// CGColor identity is fragile across resolve()/colour-space conversions —
    /// compare resolved sRGB components (incl. alpha) within tolerance.
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

    /// Best-contrast ink on a fill — mirrors PaletteKit's onPrimary path via the
    /// SAME pure Palette helpers, so the expected value can't drift.
    private func contrastInk(on c: NSColor) -> NSColor {
        let s = c.usingColorSpace(.sRGB) ?? c
        let l = wcagRelativeLuminance(r: Double(s.redComponent),
                                      g: Double(s.greenComponent),
                                      b: Double(s.blueComponent))
        return prefersBlackForeground(fillRelLuminance: l) ? .black : .white
    }

    private func laidOut(_ configure: (ThemedChip) -> Void = { _ in },
                         title: String = "Chip", width: CGFloat = 120,
                         height: CGFloat = 32) -> ThemedChip {
        let c = ThemedChip(palette: palette())
        c.title = title
        configure(c)
        c.frame = NSRect(x: 0, y: 0, width: width, height: height)
        c.layoutSubtreeIfNeeded()
        return c
    }

    // MARK: - Metrics

    func testHeightPerSize() {
        XCTAssertEqual(laidOut { $0.size = .small }.chipProbe.height, 24)
        XCTAssertEqual(laidOut { $0.size = .medium }.chipProbe.height, 32)
    }

    /// A chip hugs its label — NO 64 pt min-width floor (unlike ThemedButton).
    func testChipHasNoMinWidthFloor() {
        let c = laidOut(title: "x") { $0.variant = .filled }
        XCTAssertLessThan(c.chipProbe.intrinsicWidth, 64,
                          "a 1-char chip is far narrower than a button's 64 floor")
    }

    /// Pill corner = height/2 for filled/outlined; the keycap is a 5 pt key.
    func testCornerRadiusPillVsKeycap() {
        XCTAssertEqual(laidOut { $0.variant = .filled; $0.size = .medium }.chipProbe.cornerRadius, 16)
        XCTAssertEqual(laidOut { $0.variant = .filled; $0.size = .small }.chipProbe.cornerRadius, 12)
        XCTAssertEqual(laidOut { $0.variant = .outlined; $0.size = .medium }.chipProbe.cornerRadius, 16)
        XCTAssertEqual(laidOut { $0.variant = .keycap }.chipProbe.cornerRadius, 5)
    }

    /// A single-glyph keycap is at least square (minWidth = height).
    func testKeycapSingleGlyphIsSquare() {
        let k = laidOut(title: "⌘") { $0.variant = .keycap; $0.size = .small }
        XCTAssertGreaterThanOrEqual(k.chipProbe.intrinsicWidth, 24,
                                    "a 1-glyph keycap is square (>= height)")
    }

    func testLeadingIconReflectedAndWidens() {
        let plain = laidOut(title: "Tag")
        let withIcon = laidOut(title: "Tag") { $0.leadingSymbol = "tag" }
        XCTAssertTrue(withIcon.chipProbe.hasLeadingIcon)
        XCTAssertFalse(plain.chipProbe.hasLeadingIcon)
        XCTAssertGreaterThan(withIcon.chipProbe.intrinsicWidth, plain.chipProbe.intrinsicWidth,
                             "a leading icon widens the intrinsic content")
    }

    func testDeleteReflectedAndWidens() {
        let plain = laidOut(title: "Tag")
        let withX = laidOut(title: "Tag") { $0.onDelete = {} }
        XCTAssertTrue(withX.chipProbe.hasDelete)
        XCTAssertFalse(plain.chipProbe.hasDelete)
        XCTAssertGreaterThan(withX.chipProbe.intrinsicWidth, plain.chipProbe.intrinsicWidth,
                             "the × widens the intrinsic content")
    }

    // MARK: - Fill / ink per variant + role

    func testFilledNeutralFillIsMutedWash() {
        let p = palette()
        let c = laidOut { $0.variant = .filled; $0.role = .neutral }
        sameColor(c.chipProbe.fillColor, p.ink(.wash, of: .muted), "filled neutral = muted wash")
        sameColor(c.chipProbe.titleColor, p.foreground, "filled neutral ink = foreground")
    }

    func testFilledPrimaryFillIsRoleAndInkIsContrast() {
        let p = palette()
        let c = laidOut { $0.variant = .filled; $0.role = .primary }
        sameColor(c.chipProbe.fillColor, p.primary, "filled primary fill = opaque role")
        sameColor(c.chipProbe.titleColor, contrastInk(on: p.primary),
                  "filled primary ink = best-contrast on the role fill")
    }

    func testFilledRoleMapsSecondaryAndError() {
        let p = palette()
        sameColor(laidOut { $0.variant = .filled; $0.role = .secondary }.chipProbe.fillColor,
                  p.secondary, "secondary role fill")
        sameColor(laidOut { $0.variant = .filled; $0.role = .error }.chipProbe.fillColor,
                  p.error, "error role fill")
    }

    func testOutlinedHasClearFill() {
        XCTAssertEqual(alpha(laidOut { $0.variant = .outlined }.chipProbe.fillColor), 0,
                       accuracy: 0.001, "outlined resting fill is clear")
    }

    func testOutlinedNeutralBorderIsBorderRole() {
        let p = palette()
        let c = laidOut { $0.variant = .outlined; $0.role = .neutral }
        sameColor(c.chipProbe.borderColor, p.border, "outlined neutral border = border role")
        XCTAssertEqual(c.chipProbe.borderWidth, 1, "outlined has a 1pt border")
    }

    func testOutlinedRoleBorderRestingHalfThenFullOnHover() {
        let p = palette()
        let resting = laidOut { $0.variant = .outlined; $0.role = .primary }
        sameColor(resting.chipProbe.borderColor, p.primary.withAlphaComponent(0.5),
                  "outlined role resting border = role @ 0.5")
        let hover = laidOut { $0.variant = .outlined; $0.role = .primary
                              $0.onTap = {}; $0.previewHovered = true }
        sameColor(hover.chipProbe.borderColor, p.primary, "outlined role hover border = full role")
    }

    func testFilledHasNoBorder() {
        XCTAssertEqual(laidOut { $0.variant = .filled }.chipProbe.borderWidth, 0,
                       "filled chip draws no border")
    }

    func testKeycapFillBorderInk() {
        let p = palette()
        let k = laidOut(title: "⌘") { $0.variant = .keycap }
        sameColor(k.chipProbe.fillColor, p.ink(.faint, of: .foreground), "keycap face = faint fg wash")
        sameColor(k.chipProbe.borderColor, p.border, "keycap border = border role")
        sameColor(k.chipProbe.titleColor, p.foreground, "keycap ink = foreground")
        XCTAssertEqual(k.chipProbe.borderWidth, 1, "keycap has a 1pt border")
    }

    /// keycap ignores role (a key is never tinted primary/error).
    func testKeycapIgnoresRole() {
        let p = palette()
        let k = laidOut(title: "⌘") { $0.variant = .keycap; $0.role = .error }
        sameColor(k.chipProbe.titleColor, p.foreground, "keycap ink stays foreground regardless of role")
        sameColor(k.chipProbe.fillColor, p.ink(.faint, of: .foreground), "keycap fill unchanged by role")
    }

    // MARK: - Selection

    func testSelectedNeutralUsesSelectionWash() {
        let p = palette()
        sameColor(laidOut { $0.variant = .filled; $0.isSelected = true }.chipProbe.fillColor,
                  p.selection, "selected filled neutral = canonical selection wash")
        sameColor(laidOut { $0.variant = .outlined; $0.isSelected = true }.chipProbe.fillColor,
                  p.selection, "selected outlined neutral gains the selection fill")
    }

    func testUnselectedOutlinedStaysClear() {
        XCTAssertEqual(alpha(laidOut { $0.variant = .outlined; $0.isSelected = false }.chipProbe.fillColor),
                       0, accuracy: 0.001, "an unselected outlined chip has a clear fill")
    }

    // MARK: - State layer (clickable only)

    func testStaticChipHasNoOverlayEvenWhenForcedHover() {
        // No onTap ⇒ static ⇒ the body never lights, even with previewHovered.
        let c = laidOut { $0.variant = .filled; $0.previewHovered = true }
        XCTAssertEqual(alpha(c.chipProbe.overlayColor), 0, accuracy: 0.001,
                       "a non-clickable chip ignores a forced hover")
    }

    func testClickableHoverThenPressDeepensOverlay() {
        let hover = laidOut { $0.variant = .filled; $0.role = .neutral; $0.onTap = {}; $0.previewHovered = true }
        let press = laidOut { $0.variant = .filled; $0.role = .neutral; $0.onTap = {}; $0.previewPressed = true }
        let ah = alpha(hover.chipProbe.overlayColor)
        let ap = alpha(press.chipProbe.overlayColor)
        XCTAssertGreaterThan(ah, 0, "clickable hover shows a state layer")
        XCTAssertGreaterThan(ap, ah, "pressed state layer is stronger than hover")
    }

    // MARK: - Focus ring

    func testFocusRingHiddenWhenNotFocused() {
        XCTAssertEqual(laidOut { $0.onTap = {} }.chipProbe.focusRingOpacity, 0)
    }

    func testClickableFocusShowsRing() {
        let c = laidOut { $0.onTap = {}; $0.previewFocused = true }
        XCTAssertEqual(c.chipProbe.focusRingOpacity, 1, "a clickable focused chip shows the ring")
    }

    /// A delete-only chip is focusable (so Backspace/Delete reaches it) and shows
    /// the focus ring — even though its body is not a click target.
    func testDeleteOnlyChipIsFocusableAndRings() {
        let c = laidOut { $0.onDelete = {}; $0.previewFocused = true }
        XCTAssertTrue(c.acceptsFirstResponder, "a deletable chip is focusable")
        XCTAssertEqual(c.chipProbe.focusRingOpacity, 1, "and shows the focus ring")
    }

    func testStaticChipNotFocusable() {
        XCTAssertFalse(laidOut().acceptsFirstResponder,
                       "a static (display) chip is not focusable")
        XCTAssertEqual(laidOut { $0.previewFocused = true }.chipProbe.focusRingOpacity, 0,
                       "and shows no ring even when forced")
    }

    // MARK: - Disabled

    func testDisabledInkMutedAndSuppressesForcedHover() {
        let p = palette()
        let c = laidOut { $0.variant = .filled; $0.onTap = {}; $0.isEnabled = false; $0.previewHovered = true }
        sameColor(c.chipProbe.titleColor, p.muted, "disabled ink = muted")
        XCTAssertEqual(alpha(c.chipProbe.overlayColor), 0, accuracy: 0.001,
                       "disabled suppresses the forced hover overlay")
        XCTAssertFalse(c.acceptsFirstResponder, "disabled chip is not focusable")
    }

    // MARK: - Activation + keyboard

    /// Space activates a clickable chip's onTap (no flash — chips fire immediately).
    func testSpaceActivatesClickable() {
        let c = laidOut { $0.onTap = {} }
        var count = 0
        c.onTap = { count += 1 }
        c.keyDown(with: spaceDown())
        c.keyDown(with: spaceDown(isARepeat: true))   // auto-repeat — ignored
        XCTAssertEqual(count, 1, "Space fires once; auto-repeat is swallowed")
    }

    /// Backspace fires onDelete on a deletable chip; forward-Delete too.
    func testBackspaceAndDeleteFireOnDelete() {
        for code in [UInt16(51), UInt16(117)] {
            let c = laidOut()
            var count = 0
            c.onDelete = { count += 1 }
            c.keyDown(with: key(code))
            XCTAssertEqual(count, 1, "key \(code) fires onDelete once")
        }
    }

    func testDisabledIgnoresDeleteKey() {
        let c = laidOut { $0.isEnabled = false }
        var fired = false
        c.onDelete = { fired = true }
        c.keyDown(with: key(51))
        XCTAssertFalse(fired, "a disabled chip ignores Backspace")
    }

    /// The cell-less NSControl stores target / action through its accessors.
    func testTargetActionStorage() {
        final class Sink: NSObject { @objc func tap() {} }
        let c = laidOut { $0.onTap = {} }
        let sink = Sink()
        c.target = sink
        c.action = #selector(Sink.tap)
        XCTAssertTrue(c.target === sink)
        XCTAssertEqual(c.action, #selector(Sink.tap))
    }

    // MARK: - Accessibility

    func testAccessibilityRoleClickableVsStatic() {
        XCTAssertEqual(laidOut { $0.onTap = {} }.accessibilityRole(), .button,
                       "a clickable chip is a button")
        XCTAssertEqual(laidOut().accessibilityRole(), .staticText,
                       "a static chip is static text")
        XCTAssertEqual(laidOut(title: "design").accessibilityLabel(), "design")
    }

    // MARK: - Event helpers

    private func spaceDown(isARepeat: Bool = false) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: " ",
            charactersIgnoringModifiers: " ", isARepeat: isARepeat, keyCode: 49)!
    }
    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{8}",
            charactersIgnoringModifiers: "\u{8}", isARepeat: false, keyCode: code)!
    }
}
