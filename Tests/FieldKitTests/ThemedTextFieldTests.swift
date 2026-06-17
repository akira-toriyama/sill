// FieldKit tests — pin the behaviours the adversarial review surfaced:
//  • the BARE-focus highlight (the long-open question) — proven by driving
//    the real first-responder edge, NOT flaky synthetic clicks;
//  • the symmetric focus-OFF edge;
//  • clear-button parity with a user deletion (fires onChange);
//  • the floating label reaching the accessibility tree.

import XCTest
import AppKit
import Palette
import PaletteKit
@testable import FieldKit   // for the DEBUG `focusProbe`

@MainActor
final class ThemedTextFieldTests: XCTestCase {

    private func palette() -> ResolvedPalette { resolve(.terminal) }   // dark, primary 0x33FF66

    /// Focus is reconciled from the SETTLED first-responder state on the next
    /// runloop tick (so a bare click's become→spurious-end thrash collapses to
    /// the real result). Pump the runloop so that deferred reconcile runs.
    private func pump(_ s: TimeInterval = 0.2) {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(s))
    }

    /// A field installed in a key window, laid out, ready to focus.
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

    /// THE open question: does a BARE focus (click, no typing) light the field?
    /// Drive the real responder edge (makeFirstResponder) and read the model +
    /// live layer state — deterministic, no NSEvents.
    func testBareFocusEngagesHighlightWithoutTyping() {
        let (f, win) = fieldInKeyWindow()

        let before = f.focusProbe
        XCTAssertFalse(before.focused, "starts unfocused")
        XCTAssertFalse(before.floated, "empty + unfocused → label rests")
        XCTAssertEqual(before.borderWidth, 1, "resting border is 1pt")

        _ = win.makeFirstResponder(f)        // bare focus — NO text typed
        pump()                               // let the deferred reconcile settle
        f.layoutSubtreeIfNeeded()

        let after = f.focusProbe
        XCTAssertTrue(after.focused, "bare focus must engage the focused appearance")
        XCTAssertTrue(after.floated, "label floats on focus even with no text")
        XCTAssertEqual(after.borderWidth, 2, "focused border thickens to 2pt")
        XCTAssertNotNil(after.borderColor)
    }

    /// The symmetric OFF edge: losing first responder clears the focus look
    /// (whether via controlTextDidEndEditing or the resignFirstResponder edge).
    func testLosingFirstResponderClearsFocus() {
        let (f, win) = fieldInKeyWindow()
        _ = win.makeFirstResponder(f); pump()
        XCTAssertTrue(f.focusProbe.focused)

        _ = win.makeFirstResponder(nil); pump()   // drop first responder
        f.layoutSubtreeIfNeeded()
        XCTAssertFalse(f.focusProbe.focused, "focus look must clear on resign")
        XCTAssertEqual(f.focusProbe.borderWidth, 1)
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

    /// Programmatic `focus()` makes the field first responder and engages the
    /// focus look — the host's seam instead of reaching for the inner field.
    func testProgrammaticFocusEngages() {
        let (f, _) = fieldInKeyWindow()
        var lastFocus: Bool?
        f.onFocusChange = { lastFocus = $0 }

        f.window?.makeFirstResponder(nil); pump()   // neutralise order-front auto-focus
        lastFocus = nil

        XCTAssertTrue(f.focus(selectingAll: true), "focus() should move first responder")
        pump()
        XCTAssertTrue(f.focusProbe.focused, "focus() engages the focused appearance")
        XCTAssertEqual(lastFocus, true, "onFocusChange settles to true")
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
}
