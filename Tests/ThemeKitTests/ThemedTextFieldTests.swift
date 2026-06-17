// ThemeKit / ThemedTextField tests — the behaviours the review surfaced,
// written to be DETERMINISTIC in headless CI (no Xcode locally → these first
// ran in CI):
//  • focused APPEARANCE via previewFocused — no window / first responder needed;
//  • real focus engage+clear via the reliable focus() seam, with the async
//    focus reconcile pumped deterministically (an expectation enqueued AFTER it
//    on the FIFO main queue, so the reconcile has provably run);
//  • clear-button parity, the silent setter, accessibility forwarding.
//
// We do NOT test `window.makeFirstResponder(theContainer)` here: a real click
// and the host both route focus through `makeFirstResponder(theInnerField)` /
// `focus()`, and the container's becomeFirstResponder-forwarding is an AppKit
// edge that doesn't reliably leave the field first responder headless.

import XCTest
import AppKit
import Palette
import PaletteKit
@testable import ThemeKit   // for the DEBUG `focusProbe`

@MainActor
final class ThemedTextFieldTests: XCTestCase {

    private func palette() -> ResolvedPalette { resolve(.terminal) }   // dark, primary 0x33FF66

    /// Focus reconciles from the settled first-responder state on the NEXT
    /// runloop tick (`DispatchQueue.main.async`). The main queue is FIFO, so
    /// enqueuing a fulfilment AFTER the reconcile and waiting guarantees the
    /// reconcile has run — deterministic, no sleep/timing race.
    private func pump() {
        let e = expectation(description: "focus reconcile")
        DispatchQueue.main.async { e.fulfill() }
        wait(for: [e], timeout: 2.0)
    }

    private func fieldInKeyWindow(label: String? = "Filter")
        -> (field: ThemedTextField, window: NSWindow) {
        _ = NSApplication.shared
        let f = ThemedTextField(palette: palette())
        f.label = label
        f.frame = NSRect(x: 20, y: 20, width: 260, height: 40)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
                           styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView?.addSubview(f)
        win.makeKeyAndOrderFront(nil)
        f.layoutSubtreeIfNeeded()
        return (f, win)
    }

    /// The focused APPEARANCE is deterministic via previewFocused (no real
    /// responder) — rock-solid in headless CI: the label floats and the border
    /// thickens to 2pt when focused, and reverts when not.
    func testPreviewFocusedAppearance() {
        let f = ThemedTextField(palette: palette())
        f.label = "Filter"
        f.frame = NSRect(x: 0, y: 0, width: 260, height: 40)
        f.layoutSubtreeIfNeeded()

        XCTAssertFalse(f.focusProbe.floated, "resting (empty, unfocused): label rests")
        XCTAssertEqual(f.focusProbe.borderWidth, 1, "resting border is 1pt")

        f.previewFocused = true
        f.layoutSubtreeIfNeeded()
        XCTAssertTrue(f.focusProbe.floated, "focused: label floats even with no text")
        XCTAssertEqual(f.focusProbe.borderWidth, 2, "focused border thickens to 2pt")

        f.previewFocused = false
        f.layoutSubtreeIfNeeded()
        XCTAssertFalse(f.focusProbe.floated)
        XCTAssertEqual(f.focusProbe.borderWidth, 1)
    }

    /// Real focus: programmatic `focus()` engages the focused look, and
    /// resigning first responder clears it — exercising the async reconcile,
    /// pumped deterministically.
    func testProgrammaticFocusEngagesAndClears() {
        let (f, win) = fieldInKeyWindow()
        win.makeFirstResponder(nil); pump()        // neutralise order-front auto-focus

        XCTAssertTrue(f.focus(), "focus() moves first responder")
        pump()
        XCTAssertTrue(f.focusProbe.focused, "focus() engages the focused appearance")
        XCTAssertTrue(f.focusProbe.floated, "label floats on focus, no text needed")
        XCTAssertEqual(f.focusProbe.borderWidth, 2, "focused border is 2pt")

        win.makeFirstResponder(nil); pump()        // resign
        XCTAssertFalse(f.focusProbe.focused, "resigning clears the focus look")
        XCTAssertEqual(f.focusProbe.borderWidth, 1)
    }

    /// `focus(selectingAll:)` is the host's programmatic begin-editing seam,
    /// and `onFocusChange` settles to true.
    func testFocusSelectingAllNotifies() {
        let (f, win) = fieldInKeyWindow()
        var lastFocus: Bool?
        f.onFocusChange = { lastFocus = $0 }
        win.makeFirstResponder(nil); pump()
        lastFocus = nil

        XCTAssertTrue(f.focus(selectingAll: true))
        pump()
        XCTAssertTrue(f.focusProbe.focused)
        XCTAssertEqual(lastFocus, true, "onFocusChange settles to true")
    }

    /// Clear-button parity: clearText empties the field AND notifies onChange,
    /// unlike the silent `stringValue` setter — so a bound search list refreshes.
    func testClearTextFiresOnChange() {
        let f = ThemedTextField(palette: palette())
        f.stringValue = "kernel"
        var seen: [String] = []
        f.onChange = { seen.append($0) }

        f.clearText()
        XCTAssertEqual(f.stringValue, "")
        XCTAssertEqual(seen, [""], #"clear must fire onChange("")"#)
    }

    /// The plain `stringValue` setter stays SILENT (no onChange) to avoid
    /// re-entrant host binding loops.
    func testStringValueSetterIsSilent() {
        let f = ThemedTextField(palette: palette())
        var fired = false
        f.onChange = { _ in fired = true }
        f.stringValue = "hello"
        XCTAssertFalse(fired, "assigning stringValue must not fire onChange")
    }

    /// Accessibility: the floating label is a CATextLayer (invisible to AX), so
    /// it must be forwarded to the inner field as its accessible name; it falls
    /// back to the placeholder when there is no label.
    func testAccessibilityNameForwarded() {
        let f = ThemedTextField(palette: palette())
        let inner = f.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertNotNil(inner, "inner NSTextField present")

        f.label = "Filter"
        XCTAssertEqual(inner?.accessibilityLabel(), "Filter")

        f.label = nil
        f.placeholder = "type to filter…"
        XCTAssertEqual(inner?.accessibilityLabel(), "type to filter…",
                       "falls back to placeholder when label is nil")
    }

    // MARK: - Additive combo-box seams (default = byte-identical)

    /// The arrow-key seams default to nil so a bare field's arrows fall through
    /// to the field editor exactly as before (the `?? false` path in doCommandBy).
    func testArrowSeamsDefaultNil() {
        let f = ThemedTextField(palette: palette())
        XCTAssertNil(f.onMoveDown, "no arrow seam by default")
        XCTAssertNil(f.onMoveUp, "no arrow seam by default")
    }

    /// With `secondTrailingSymbol` nil (the default), the laid-out geometry is
    /// IDENTICAL to a field that has only the single `trailingSymbol` — the new
    /// inner-slot code path is dormant.
    func testSecondTrailingNilIsGeometryIdentical() {
        let frame = NSRect(x: 0, y: 0, width: 240, height: 46)
        let a = ThemedTextField(palette: palette()); a.label = "Fruit"
        a.trailingSymbol = "chevron.down"; a.frame = frame; a.layoutSubtreeIfNeeded()
        let b = ThemedTextField(palette: palette()); b.label = "Fruit"
        b.trailingSymbol = "chevron.down"; b.secondTrailingSymbol = nil
        b.frame = frame; b.layoutSubtreeIfNeeded()

        let ga = a.geometryProbe, gb = b.geometryProbe
        XCTAssertNil(gb.secondTrailingIcon, "the inner slot is absent when unset")
        XCTAssertEqual(ga.textRect, gb.textRect, "text rect unchanged by a nil second slot")
        XCTAssertEqual(ga.trailingIcon, gb.trailingIcon, "trailing icon unchanged")
    }

    /// Adding the inner second trailing icon shrinks the text rect by exactly one
    /// icon + one gap (8) — NOT two gaps — and the inner icon sits left of the
    /// outer one.
    func testSecondTrailingShrinksTextRectByOneIconPlusGap() {
        let frame = NSRect(x: 0, y: 0, width: 240, height: 46)
        let one = ThemedTextField(palette: palette()); one.label = "Fruit"
        one.trailingSymbol = "chevron.down"; one.frame = frame; one.layoutSubtreeIfNeeded()
        let two = ThemedTextField(palette: palette()); two.label = "Fruit"
        two.trailingSymbol = "chevron.down"; two.secondTrailingSymbol = "xmark.circle.fill"
        two.frame = frame; two.layoutSubtreeIfNeeded()

        let g1 = one.geometryProbe, g2 = two.geometryProbe
        let iconW = g1.trailingIcon!.width
        XCTAssertEqual(g1.textRect.maxX - g2.textRect.maxX, iconW + 8, accuracy: 0.5,
                       "second icon eats exactly one icon width + one 8pt gap")
        XCTAssertNotNil(g2.secondTrailingIcon)
        XCTAssertLessThanOrEqual(g2.secondTrailingIcon!.maxX, g2.trailingIcon!.minX,
                                 "the inner icon sits left of the outer chevron")
    }
}
