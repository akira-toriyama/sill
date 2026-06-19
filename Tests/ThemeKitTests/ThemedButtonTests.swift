// ThemeKit / ThemedButton tests — DETERMINISTIC in headless CI (no Xcode
// locally → these first run in CI). Real hover / press / keyboard focus need a
// key window + synthetic events (flaky headless — see the Phase 0 learning), so
// these tests drive each state through the `preview…` overrides and read the
// rendered result via the DEBUG `buttonProbe`, which IS deterministic. The live
// 演出 (the animated hover / press / elevation) is proven in prism, not here.

import XCTest
import AppKit
import Palette
import PaletteKit
@testable import ThemeKit   // for the DEBUG `buttonProbe`

@MainActor
final class ThemedButtonTests: XCTestCase {

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

    private func laidOut(_ configure: (ThemedButton) -> Void = { _ in },
                         width: CGFloat = 120, height: CGFloat = 36) -> ThemedButton {
        let b = ThemedButton(palette: palette())
        b.title = "Button"
        configure(b)
        b.frame = NSRect(x: 0, y: 0, width: width, height: height)
        b.layoutSubtreeIfNeeded()
        return b
    }

    // MARK: - Metrics

    func testHeightPerSize() {
        XCTAssertEqual(laidOut { $0.size = .small }.buttonProbe.height, 30)
        XCTAssertEqual(laidOut { $0.size = .medium }.buttonProbe.height, 36)
        XCTAssertEqual(laidOut { $0.size = .large }.buttonProbe.height, 42)
    }

    func testMinWidthRespected() {
        let b = laidOut { $0.title = "OK" }   // short label
        XCTAssertGreaterThanOrEqual(b.intrinsicContentSize.width, 64, "min width 64")
    }

    func testFullWidthDropsIntrinsicWidth() {
        let b = laidOut { $0.fullWidth = true }
        XCTAssertEqual(b.intrinsicContentSize.width, NSView.noIntrinsicMetric,
                       "fullWidth opts out of intrinsic width so the host stretches it")
        XCTAssertEqual(b.intrinsicContentSize.height, 36, "height is still fixed")
    }

    func testLeadingIconReflectedAndWidens() {
        let plain = laidOut { $0.title = "Save" }
        let withIcon = laidOut { $0.title = "Save"; $0.leadingSymbol = "tray-arrow-down" }
        XCTAssertTrue(withIcon.buttonProbe.hasLeadingIcon)
        XCTAssertFalse(plain.buttonProbe.hasLeadingIcon)
        XCTAssertGreaterThan(withIcon.intrinsicContentSize.width, plain.intrinsicContentSize.width,
                             "a leading icon widens the intrinsic content")
    }

    // MARK: - Fill / ink per variant

    func testContainedFillIsRole() {
        let p = palette()
        let b = laidOut { $0.variant = .contained }
        sameColor(b.buttonProbe.fillColor, p.primary, "contained fill = role (primary)")
    }

    func testTextAndOutlinedHaveClearFill() {
        XCTAssertEqual(alpha(laidOut { $0.variant = .text }.buttonProbe.fillColor), 0,
                       accuracy: 0.001, "text fill is clear")
        XCTAssertEqual(alpha(laidOut { $0.variant = .outlined }.buttonProbe.fillColor), 0,
                       accuracy: 0.001, "outlined fill is clear")
    }

    func testContainedInkIsBestContrastOnFill() {
        let p = palette()
        let b = laidOut { $0.variant = .contained; $0.role = .primary }
        sameColor(b.buttonProbe.titleColor, contrastInk(on: p.primary),
                  "contained ink = best-contrast on the role fill")
    }

    func testTextInkIsRoleColor() {
        let p = palette()
        sameColor(laidOut { $0.variant = .text }.buttonProbe.titleColor, p.primary,
                  "text ink = role colour")
    }

    func testRoleMapsToSecondaryAndError() {
        let p = palette()
        sameColor(laidOut { $0.variant = .contained; $0.role = .secondary }.buttonProbe.fillColor,
                  p.secondary, "secondary role fill")
        sameColor(laidOut { $0.variant = .contained; $0.role = .error }.buttonProbe.fillColor,
                  p.error, "error role fill")
    }

    // MARK: - State layer (overlay)

    func testRestingHasNoOverlay() {
        XCTAssertEqual(alpha(laidOut { $0.variant = .text }.buttonProbe.overlayColor), 0,
                       accuracy: 0.001, "resting = no state layer")
    }

    func testHoverThenPressDeepensOverlay() {
        let hover = laidOut { $0.variant = .text; $0.previewHovered = true }
        let press = laidOut { $0.variant = .text; $0.previewPressed = true }
        let ah = alpha(hover.buttonProbe.overlayColor)
        let ap = alpha(press.buttonProbe.overlayColor)
        XCTAssertGreaterThan(ah, 0, "hover shows a state layer")
        XCTAssertGreaterThan(ap, ah, "pressed state layer is stronger than hover")
    }

    func testFocusShowsOverlayAndRingForText() {
        let b = laidOut { $0.variant = .text; $0.previewFocused = true }
        XCTAssertGreaterThan(alpha(b.buttonProbe.overlayColor), 0, "focus shows a faint state layer")
        XCTAssertEqual(b.buttonProbe.focusRingOpacity, 1, "focus ring visible when focused")
    }

    func testFocusRingHiddenWhenNotFocused() {
        XCTAssertEqual(laidOut().buttonProbe.focusRingOpacity, 0)
    }

    /// Contained focus is signalled by the ring + a raised elevation, with NO
    /// state-layer wash (the wash is hover/pressed only) — pins the deliberate
    /// contained-vs-text focus asymmetry.
    func testContainedFocusIsRingAndElevationNoOverlay() {
        let b = laidOut { $0.variant = .contained; $0.previewFocused = true }
        XCTAssertEqual(b.buttonProbe.focusRingOpacity, 1, "focus ring visible")
        XCTAssertEqual(alpha(b.buttonProbe.overlayColor), 0, accuracy: 0.001,
                       "contained focus draws no state-layer wash")
        let rest = laidOut { $0.variant = .contained }.buttonProbe.shadowOpacity
        XCTAssertGreaterThan(b.buttonProbe.shadowOpacity, rest, "focus raises elevation above rest")
    }

    // MARK: - Outlined border

    func testOutlinedBorderRestingHalfAlphaThenFull() {
        let p = palette()
        let resting = laidOut { $0.variant = .outlined }
        XCTAssertTrue(resting.buttonProbe.borderVisible)
        sameColor(resting.buttonProbe.borderColor, p.primary.withAlphaComponent(0.5),
                  "outlined resting border = role @ 0.5")
        let hover = laidOut { $0.variant = .outlined; $0.previewHovered = true }
        sameColor(hover.buttonProbe.borderColor, p.primary,
                  "outlined hover border = full role")
    }

    func testNonOutlinedHasNoBorder() {
        XCTAssertFalse(laidOut { $0.variant = .text }.buttonProbe.borderVisible)
        XCTAssertFalse(laidOut { $0.variant = .contained }.buttonProbe.borderVisible)
    }

    // MARK: - Elevation

    func testContainedElevatesWhenEnabled() {
        XCTAssertGreaterThan(laidOut { $0.variant = .contained }.buttonProbe.shadowOpacity, 0,
                             "contained rests with an elevation shadow")
        XCTAssertEqual(laidOut { $0.variant = .text }.buttonProbe.shadowOpacity, 0,
                       "text variant has no shadow")
    }

    func testContainedPressDeepensElevation() {
        let rest = laidOut { $0.variant = .contained }.buttonProbe.shadowOpacity
        let press = laidOut { $0.variant = .contained; $0.previewPressed = true }.buttonProbe.shadowOpacity
        XCTAssertGreaterThan(press, rest, "pressed elevation > resting")
    }

    // MARK: - Disabled

    func testDisabledInkMutedNoOverlayNoShadow() {
        let p = palette()
        let b = laidOut { $0.variant = .contained; $0.isEnabled = false }
        sameColor(b.buttonProbe.titleColor, p.muted, "disabled ink = muted")
        XCTAssertEqual(b.buttonProbe.shadowOpacity, 0, "disabled is flat (no elevation)")
    }

    /// The isEnabled gate must beat the preview overrides — a disabled button
    /// shows no hover state layer even when `previewHovered` is forced.
    func testDisabledSuppressesForcedHover() {
        let b = laidOut { $0.variant = .text; $0.isEnabled = false; $0.previewHovered = true }
        XCTAssertEqual(alpha(b.buttonProbe.overlayColor), 0, accuracy: 0.001,
                       "disabled suppresses the forced hover overlay")
    }

    // MARK: - Activation + accessibility

    /// The full keyboard path: Space on a focused button flashes pressed then
    /// fires `onTap` (after the 0.12 s flash) — pump the main queue to await it.
    func testSpaceKeyActivatesOnTap() {
        let b = laidOut()
        let exp = expectation(description: "onTap fires from Space")
        b.onTap = { exp.fulfill() }
        let ev = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: " ",
            charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
        b.keyDown(with: ev)
        wait(for: [exp], timeout: 1.0)
    }

    /// A disabled button ignores Space (no activation).
    func testDisabledIgnoresSpace() {
        let b = laidOut { $0.isEnabled = false }
        var fired = false
        b.onTap = { fired = true }
        let ev = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: " ",
            charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
        b.keyDown(with: ev)
        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settle.fulfill() }
        wait(for: [settle], timeout: 1.0)
        XCTAssertFalse(fired, "disabled button does not activate on Space")
    }

    /// The cell-less NSControl stores target / action through its overridden
    /// accessors (not a now-absent cell).
    func testTargetActionStorage() {
        final class Sink: NSObject { @objc func tap() {} }
        let b = laidOut()
        let sink = Sink()
        b.target = sink
        b.action = #selector(Sink.tap)
        XCTAssertTrue(b.target === sink, "target stored on the control")
        XCTAssertEqual(b.action, #selector(Sink.tap), "action stored on the control")
    }

    private func spaceDown(isARepeat: Bool = false) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: " ",
            charactersIgnoringModifiers: " ", isARepeat: isARepeat, keyCode: 49)!
    }
    private func returnEvent(_ mods: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0,
            windowNumber: 0, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
    }
    /// Pump the main queue past the 0.12 s activation flash.
    private func settle(_ seconds: TimeInterval = 0.25) {
        let e = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { e.fulfill() }
        wait(for: [e], timeout: 1.0)
    }

    /// A held Space (auto-repeat) and a rapid second press inside the flash
    /// window both collapse to ONE activation — no auto-repeat / double fire.
    func testSpaceActivatesExactlyOncePerPress() {
        let b = laidOut()
        var count = 0
        b.onTap = { count += 1 }
        b.keyDown(with: spaceDown())                 // press
        b.keyDown(with: spaceDown(isARepeat: true))  // auto-repeat — ignored
        b.keyDown(with: spaceDown())                 // 2nd press inside flash — dropped
        settle()
        XCTAssertEqual(count, 1, "one activation per press, repeats/overlaps suppressed")
    }

    /// Disabling the button during the 0.12 s flash cancels the pending
    /// activation (activate() re-checks isEnabled).
    func testDisableDuringFlashCancelsActivation() {
        let b = laidOut()
        var fired = false
        b.onTap = { fired = true }
        b.keyDown(with: spaceDown())   // schedules the flash
        b.isEnabled = false            // disable inside the window
        settle()
        XCTAssertFalse(fired, "an async disable mid-flash cancels the activation")
    }

    /// Return only activates a button that opted in as the default
    /// (keyEquivalent "\r"); an unset button must NOT swallow Return.
    func testReturnDefaultButtonGatedOnKeyEquivalent() {
        let plain = laidOut()
        var plainFired = false
        plain.onTap = { plainFired = true }
        XCTAssertFalse(plain.performKeyEquivalent(with: returnEvent()),
                       "an unset button does not claim Return")
        settle()
        XCTAssertFalse(plainFired, "and never activates from it")

        let def = laidOut { $0.keyEquivalent = "\r" }
        let exp = expectation(description: "default button fires on Return")
        def.onTap = { exp.fulfill() }
        XCTAssertTrue(def.performKeyEquivalent(with: returnEvent()),
                      "the default button claims Return")
        wait(for: [exp], timeout: 1.0)
    }

    /// A modifier mismatch (⌘Return) does not trigger a plain-Return default.
    func testReturnKeyEquivalentRespectsModifierMask() {
        let def = laidOut { $0.keyEquivalent = "\r" }
        var fired = false
        def.onTap = { fired = true }
        XCTAssertFalse(def.performKeyEquivalent(with: returnEvent(.command)),
                       "⌘Return does not match a no-modifier key equivalent")
        settle()
        XCTAssertFalse(fired)
    }

    func testAccessibilityRoleAndLabel() {
        let b = laidOut { $0.title = "Save" }
        XCTAssertEqual(b.accessibilityRole(), .button)
        XCTAssertEqual(b.accessibilityLabel(), "Save", "AX label keeps the original case")
    }
}
