// ThemeKit / ThemedControl base-contract tests — the #14b value-preserving
// extraction's safety net. DETERMINISTIC in headless CI (no Xcode locally → these
// first run in CI). Each test drives a REAL subclass (Button/FAB/Checkbox/Chip)
// through the shared base machinery via the `preview…` overrides + `isEnabled` +
// keyDown, and reads the result through that widget's DEBUG probe or the base's
// `@testable` focusRingLayer. Proves the base owns ONE copy of: the fx-merge
// (real||preview AND gate), the concentric focusRingOutset math, the disable
// cleanup, and the keyboardActivate seam (toggle vs send). The live 演出 is proven
// in prism, not here.
//
// The four per-widget suites (ThemedButtonTests / ThemedFABTests /
// ThemedCheckboxTests / ThemedChipTests) are the byte-equivalence net —
// kept UNCHANGED; this file adds the cross-cutting base machinery on top of them.
import XCTest
import AppKit
import Palette
import PaletteKit
@testable import ThemeKit

@MainActor
final class ThemedControlTests: XCTestCase {
    private func palette() -> ResolvedPalette { resolve(.terminal) }
    private func alpha(_ c: CGColor?) -> CGFloat {
        guard let c, let n = NSColor(cgColor: c)?.usingColorSpace(.sRGB) else { return -1 }
        return n.alphaComponent
    }
    private func settle(_ seconds: TimeInterval = 0.25) {
        let e = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { e.fulfill() }
        wait(for: [e], timeout: 1.0)
    }
    private func spaceDown(isARepeat: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: " ",
            charactersIgnoringModifiers: " ", isARepeat: isARepeat, keyCode: 49)!
    }

    // MARK: - Step 2: fx-merge (real||preview AND appearanceGate) on Button + FAB

    // fx merge = (realState || preview) && appearanceGate. Default gate = isEnabled
    // (Button / FAB). The preview overrides feed the SAME computed the real events do.
    func testFxHoverShowsOverlayButDisabledSuppresses() {
        let b = ThemedButton(palette: palette()); b.title = "B"; b.variant = .text
        b.frame = NSRect(x: 0, y: 0, width: 120, height: 36); b.layoutSubtreeIfNeeded()
        b.previewHovered = true
        XCTAssertGreaterThan(alpha(b.buttonProbe.overlayColor), 0, "preview hover lights the base fx merge")
        b.isEnabled = false   // appearanceGate=false now ANDs the merge to false
        XCTAssertEqual(alpha(b.buttonProbe.overlayColor), 0, accuracy: 0.001,
                       "the base appearanceGate (=isEnabled) suppresses the forced hover")
    }
    func testFxFocusRingGatedByEnabled() {
        let f = ThemedFAB(palette: palette()); f.leadingSymbol = "plus"
        f.frame = NSRect(origin: .zero, size: f.intrinsicContentSize); f.layoutSubtreeIfNeeded()
        f.previewFocused = true
        XCTAssertEqual(f.fabProbe.focusRingOpacity, 1, "preview focus shows the base-owned ring (showFocusRing)")
        f.isEnabled = false
        XCTAssertEqual(f.fabProbe.focusRingOpacity, 0, "disabled gates the base ring off")
    }

    // MARK: - Step 3: Chip's appearanceGate/focusGate seams (gate ≠ isEnabled)

    func testChipAppearanceGateSeamSuppressesForcedHoverWhenStatic() {
        let c = ThemedChip(palette: palette()); c.title = "Tag"; c.variant = .filled
        c.frame = NSRect(x: 0, y: 0, width: 120, height: 32); c.layoutSubtreeIfNeeded()
        c.previewHovered = true   // appearanceGate = isClickable = false → merge AND-ed off
        XCTAssertEqual(alpha(c.chipProbe.overlayColor), 0, accuracy: 0.001,
                       "Chip overrides appearanceGate to isClickable; a static chip ignores forced hover")
        XCTAssertFalse(c.acceptsFirstResponder, "Chip overrides focusGate; a static chip is not focusable")
    }
    func testChipFocusGateSeamKeepsDeleteOnlyFocusable() {
        let c = ThemedChip(palette: palette()); c.title = "Tag"; c.onDelete = {}
        c.frame = NSRect(x: 0, y: 0, width: 120, height: 32); c.layoutSubtreeIfNeeded()
        c.previewFocused = true
        XCTAssertTrue(c.acceptsFirstResponder, "delete-only body is inert but focusGate=isInteractive keeps it focusable")
        XCTAssertEqual(c.chipProbe.focusRingOpacity, 1, "and the base ring shows")
    }

    // MARK: - Step 4: concentric focusRingOutset math (4 literal-2 → Space.xxs)

    func testFocusRingOutsetIsTwoOnEverySubclass() {
        // Button — selective-corner ring, still concentric-outset 2
        let b = ThemedButton(palette: palette()); b.title = "B"; b.previewFocused = true
        b.frame = NSRect(x: 0, y: 0, width: 120, height: 36); b.layoutSubtreeIfNeeded()
        let bb = b.focusRingLayer.path!.boundingBoxOfPath
        XCTAssertEqual(bb.width,  120 + 4, accuracy: 0.5, "Button ring grows by 2*outset wide")
        XCTAssertEqual(bb.height,  36 + 4, accuracy: 0.5, "Button ring grows by 2*outset tall")
        XCTAssertEqual(bb.minX, -2, accuracy: 0.5, "ring sits 2pt outside the box (focusRingOutset = Space.xxs)")
        XCTAssertEqual(bb.minY, -2, accuracy: 0.5)
        // FAB — circle ring
        let f = ThemedFAB(palette: palette()); f.variant = .circular; f.leadingSymbol = "plus"; f.previewFocused = true
        f.frame = NSRect(x: 0, y: 0, width: 48, height: 48); f.layoutSubtreeIfNeeded()
        let fb = f.focusRingLayer.path!.boundingBoxOfPath
        XCTAssertEqual(fb.width,  48 + 4, accuracy: 0.5, "FAB circle ring grows by 2*outset")
        XCTAssertEqual(fb.minX, -2, accuracy: 0.5)
        // Chip — pill ring
        let c = ThemedChip(palette: palette()); c.title = "Tag"; c.onTap = {}; c.previewFocused = true
        c.frame = NSRect(x: 0, y: 0, width: 120, height: 32); c.layoutSubtreeIfNeeded()
        let cb = c.focusRingLayer.path!.boundingBoxOfPath
        XCTAssertEqual(cb.width, 120 + 4, accuracy: 0.5, "Chip pill ring grows by 2*outset")
        XCTAssertEqual(cb.minY, -2, accuracy: 0.5)
    }

    // MARK: - Step 5: disable-cleanup (stuck-hover gotcha + didDisable seam)

    func testDisableClearsStrandedHoverOnce() {
        let b = ThemedButton(palette: palette()); b.title = "B"; b.variant = .text
        b.frame = NSRect(x: 0, y: 0, width: 120, height: 36); b.layoutSubtreeIfNeeded()
        b.previewHovered = true
        XCTAssertGreaterThan(alpha(b.buttonProbe.overlayColor), 0)
        b.isEnabled = false   // base clears isHovered/isPressed + resigns FR, then didDisable()
        XCTAssertEqual(alpha(b.buttonProbe.overlayColor), 0, accuracy: 0.001,
                       "base disable cleanup clears the stranded hover overlay")
        // NOTE: previewHovered remains true, so re-enabling would relight the overlay
        // (merge = previewHovered && isEnabled = true). Asserting re-enable is intentionally
        // omitted — the load-bearing gate is the disable-to-clear step above.
    }

    // MARK: - Step 6: keyboardActivate seam — toggle (Checkbox) vs send (Button/FAB)

    func testButtonKeyboardActivateSendsOnce() {
        let b = ThemedButton(palette: palette()); b.title = "B"
        b.frame = NSRect(x: 0, y: 0, width: 120, height: 36); b.layoutSubtreeIfNeeded()
        var count = 0; b.onTap = { count += 1 }
        b.keyDown(with: spaceDown())                  // flash → send
        b.keyDown(with: spaceDown())                  // inside the flash window → dropped (isFlashing)
        settle()
        XCTAssertEqual(count, 1, "base keyboardActivate = flash-then-send, atomic per press")
    }
    func testCheckboxKeyboardActivateTogglesViaSeam() {
        let c = ThemedCheckbox(palette: palette())
        c.frame = NSRect(x: 0, y: 0, width: 200, height: 42); c.layoutSubtreeIfNeeded()
        var changes = 0; c.onChange = { _ in changes += 1 }
        c.spaceKeyForTesting()                        // base flash helper → Checkbox's TOGGLE override
        XCTAssertTrue(c.isFlashingForTesting, "reuses the base flash (isFlashing in flight)")
        c.spaceKeyForTesting()                        // re-entry dropped by the shared isFlashing guard
        settle()
        XCTAssertEqual(changes, 1, "Checkbox overrides keyboardActivate to toggle (not send), once per press")
        XCTAssertTrue(c.isChecked, "the toggle landed")
    }
}
