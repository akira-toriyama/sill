// ThemeKitUI / ThemedTextFieldView bridge tests — the T1 controlled surface
// (sill deferred #17 completed): a controlled `Binding<String>`, the key-callback
// pass-through (onReturn/onEscape/onMoveUp/onMoveDown), and programmatic focus
// via a `Binding<Bool>`. The bridge is exercised through its Context-free seams
// (`makeField()` / `apply(to:)`) so no NSViewRepresentable.Context is needed;
// real-focus tests reuse the deterministic key-window + pump() recipe from
// ThemedTextFieldTests (main queue is FIFO — an expectation enqueued after the
// async focus reconcile proves it ran).

import XCTest
import AppKit
import SwiftUI
import Palette
import PaletteKit
import ThemeKit
@testable import ThemeKitUI

@MainActor
final class ThemedTextFieldViewTests: XCTestCase {

    private func palette() -> ResolvedPalette { resolve(.terminal) }

    private func pump() {
        let e = expectation(description: "focus reconcile")
        DispatchQueue.main.async { e.fulfill() }
        wait(for: [e], timeout: 2.0)
    }

    private func hostInKeyWindow(_ f: ThemedTextField) -> NSWindow {
        _ = NSApplication.shared
        f.frame = NSRect(x: 20, y: 20, width: 260, height: 40)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
                           styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView?.addSubview(f)
        win.makeKeyAndOrderFront(nil)
        f.layoutSubtreeIfNeeded()
        return win
    }

    // MARK: - Controlled Binding<String>

    /// Field-side edits flow INTO the binding: a user keystroke (simulated via
    /// the notifying setText, the same path controlTextDidChange drives) lands
    /// in the bound model, and the optional onChange observer sees it too.
    func testControlledTypingUpdatesBinding() {
        var model = "ker"
        var observed: [String] = []
        let v = ThemedTextFieldView(palette: palette(),
                                    text: Binding(get: { model }, set: { model = $0 }),
                                    onChange: { observed.append($0) })
        let f = v.makeField()

        XCTAssertEqual(f.stringValue, "ker", "binding seeds the field")
        f.setText("kern", notifying: true)      // = a keystroke's onChange path
        XCTAssertEqual(model, "kern", "typing pushes field → binding")
        XCTAssertEqual(observed, ["kern"], "onChange observer sees the edit")
    }

    /// Model-side changes flow INTO the field while it is NOT focused —
    /// silently (no onChange echo, no binding re-entry).
    func testControlledModelPushWhenUnfocused() {
        var model = "a"
        var echoed = false
        let v = ThemedTextFieldView(palette: palette(),
                                    text: Binding(get: { model }, set: { model = $0 }),
                                    onChange: { _ in echoed = true })
        let f = v.makeField()

        model = "reset"
        v.apply(to: f)
        XCTAssertEqual(f.stringValue, "reset", "unfocused: model pushes into the field")
        XCTAssertFalse(echoed, "the model push must not echo onChange")
    }

    /// The seed-once protection SURVIVES in controlled mode: while the field is
    /// first responder (live typing), apply() must NOT clobber the field text
    /// with a stale model value.
    func testControlledModelPushSkippedWhileFocused() {
        var model = "typing"
        let v = ThemedTextFieldView(palette: palette(),
                                    text: Binding(get: { model }, set: { model = $0 }))
        let f = v.makeField()
        let win = hostInKeyWindow(f)
        win.makeFirstResponder(nil); pump()

        XCTAssertTrue(f.focus()); pump()
        XCTAssertTrue(f.isFirstResponderNow)

        model = "stale-model"
        v.apply(to: f)
        XCTAssertEqual(f.stringValue, "typing",
                       "focused: live typing must not be clobbered by the model")
    }

    /// The pre-existing uncontrolled init keeps its seed-once contract:
    /// apply() with a different `text` does NOT re-push it.
    func testUncontrolledStaysSeedOnce() {
        var v = ThemedTextFieldView(palette: palette(), text: "seed")
        let f = v.makeField()
        XCTAssertEqual(f.stringValue, "seed")

        v.text = "later"
        v.apply(to: f)
        XCTAssertEqual(f.stringValue, "seed", "uncontrolled text is seeded once, never re-pushed")
    }

    /// The trailing clear affordance (default onTrailingTap = clearText) empties
    /// the bound model too — the Esc-clear / clear-× search path.
    func testTrailingClearEmptiesBinding() {
        var model = "kernel"
        let v = ThemedTextFieldView(palette: palette(),
                                    text: Binding(get: { model }, set: { model = $0 }))
        let f = v.makeField()

        f.onTrailingTap?()
        XCTAssertEqual(f.stringValue, "")
        XCTAssertEqual(model, "", #"clear-× must land "" in the binding"#)
    }

    // MARK: - Key callbacks (onReturn / onEscape / ↑↓)

    /// All four key callbacks pass through to the AppKit field's seams with
    /// their handled-Bool contract intact.
    func testKeyCallbacksPassThrough() {
        var model = ""
        var fired: [String] = []
        let v = ThemedTextFieldView(palette: palette(),
                                    text: Binding(get: { model }, set: { model = $0 }),
                                    onReturn: { fired.append("return"); return true },
                                    onEscape: { fired.append("escape"); return true },
                                    onMoveUp: { fired.append("up"); return false },
                                    onMoveDown: { fired.append("down"); return true })
        let f = v.makeField()

        XCTAssertEqual(f.onReturn?(), true)
        XCTAssertEqual(f.onEscape?(), true)
        XCTAssertEqual(f.onMoveUp?(), false, "the handled-Bool is forwarded verbatim")
        XCTAssertEqual(f.onMoveDown?(), true)
        XCTAssertEqual(fired, ["return", "escape", "up", "down"])
    }

    /// A bridge without key callbacks leaves the field's seams nil, so arrows
    /// fall through to the field editor exactly as before (byte-identical
    /// default — the `?? false` path in doCommandBy).
    func testKeyCallbacksDefaultNil() {
        var model = ""
        let v = ThemedTextFieldView(palette: palette(),
                                    text: Binding(get: { model }, set: { model = $0 }))
        let f = v.makeField()
        XCTAssertNil(f.onReturn)
        XCTAssertNil(f.onEscape)
        XCTAssertNil(f.onMoveUp)
        XCTAssertNil(f.onMoveDown)
    }

    // MARK: - Programmatic focus (Binding<Bool>)

    /// focused=true grabs first responder on apply; flipping it false releases.
    func testFocusBindingGrabsAndReleases() {
        var model = ""
        var focus = false
        let v = ThemedTextFieldView(palette: palette(),
                                    text: Binding(get: { model }, set: { model = $0 }),
                                    focused: Binding(get: { focus }, set: { focus = $0 }))
        let f = v.makeField()
        let win = hostInKeyWindow(f)
        win.makeFirstResponder(nil); pump()
        XCTAssertFalse(f.isFirstResponderNow)

        focus = true
        v.apply(to: f); pump()
        XCTAssertTrue(f.isFirstResponderNow, "focused=true grabs first responder")

        focus = false
        v.apply(to: f); pump()
        XCTAssertFalse(f.isFirstResponderNow, "focused=false releases first responder")
    }

    /// User-driven focus flows BACK into the binding (via onFocusChange), so a
    /// host reading `focused` stays truthful.
    func testFocusBindingReflectsUserFocus() {
        var model = ""
        var focus = false
        let v = ThemedTextFieldView(palette: palette(),
                                    text: Binding(get: { model }, set: { model = $0 }),
                                    focused: Binding(get: { focus }, set: { focus = $0 }))
        let f = v.makeField()
        let win = hostInKeyWindow(f)
        win.makeFirstResponder(nil); pump()

        XCTAssertTrue(f.focus()); pump()           // a "user" focus, not the binding
        XCTAssertTrue(focus, "field focus reflects back into the binding")

        win.makeFirstResponder(nil); pump()
        XCTAssertFalse(focus, "resigning reflects back too")
    }
}
