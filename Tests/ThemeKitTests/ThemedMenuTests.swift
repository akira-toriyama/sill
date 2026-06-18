// ThemeKit / ThemedMenu tests — DETERMINISTIC in headless CI (no Xcode locally →
// these first compile + run in CI). The menu is driven via its public API + the
// DEBUG `menuProbe` / `_list` / `_activate` seams; the hosted list's nav / AX are
// exercised through the same list the controller configures. Open / monitor-
// lifecycle uses a real (un-ordered) NSWindow + anchor. The Grow appearance + live
// VoiceOver traversal are proven LIVE in still, not asserted here.

import XCTest
import AppKit
import Palette
import PaletteKit
@testable import ThemeKit

@MainActor
final class ThemedMenuTests: XCTestCase {

    private func theme(_ name: String = "terminal") -> ResolvedPalette { resolve(paletteFor(name)) }

    /// Host windows kept alive for the duration of a test method (an anchor needs a
    /// live `.window` to present against; without this they'd deallocate).
    private var hostWindows: [NSWindow] = []

    /// A host window with an anchor view in it (gives the anchor a `.window` so the
    /// menu can present). The window is never ordered on screen.
    private func anchoredMenu(_ items: [ThemedMenu.MenuItem],
                              _ configure: (ThemedMenu) -> Void = { _ in }) -> (ThemedMenu, NSView) {
        let frame = NSRect(x: 0, y: 0, width: 320, height: 220)
        let win = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
        let host = NSView(frame: frame)
        win.contentView = host
        hostWindows.append(win)
        let anchor = NSView(frame: NSRect(x: 20, y: 20, width: 90, height: 24))
        host.addSubview(anchor)
        let m = ThemedMenu(palette: theme())
        m.items = items
        configure(m)
        return (m, anchor)
    }

    /// An anchored menu whose host window sits at a real SCREEN position (for the
    /// placement-corner tests, which need the anchor's on-screen rect resolved).
    private func anchoredMenuAt(_ winOrigin: CGPoint, _ items: [ThemedMenu.MenuItem]) -> (ThemedMenu, NSView) {
        let frame = NSRect(origin: winOrigin, size: CGSize(width: 260, height: 64))
        let win = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
        let host = NSView(frame: NSRect(origin: .zero, size: frame.size))
        win.contentView = host
        hostWindows.append(win)
        let anchor = NSView(frame: NSRect(x: 12, y: 20, width: 120, height: 24))
        host.addSubview(anchor)
        let m = ThemedMenu(palette: theme())
        m.items = items
        return (m, anchor)
    }

    /// A synthetic keyDown for routing through the menu's `_handleKey` seam
    /// (`handleKeyDown` reads only `keyCode`; `chars` is non-empty so `keyEvent` is
    /// never nil).
    private func keyDown(_ keyCode: UInt16, chars: String = " ") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: 0, context: nil, characters: chars,
                         charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode)!
    }

    /// FIFO main-queue pump — enqueue a fulfilment AFTER a deferred async so it has
    /// run by the time we assert (deterministic, no sleep). Mirrors ThemedTextFieldTests.
    private func pump() {
        let e = expectation(description: "runloop turn")
        DispatchQueue.main.async { e.fulfill() }
        wait(for: [e], timeout: 2.0)
    }

    // MARK: - MenuItem → ListItem mapping

    func testItemKindsMapToRows() {
        let m = ThemedMenu(palette: theme())
        m.items = [.init("A"), .separator(), .init("B", isEnabled: false), .header("Group")]
        XCTAssertEqual(m._list.listProbe.rowCount, 4)
        let rows = m._list.items
        XCTAssertEqual(rows[1].kind, .separator)
        XCTAssertTrue(rows[2].isDisabled, "a disabled item maps to a disabled row")
        XCTAssertEqual(rows[3].kind, .sectionHeader(subtitle: nil), "a header maps to a section header")
    }

    func testMappingDetails() {
        let suppliedIcon = NSImage(size: NSSize(width: 8, height: 8))
        let m = ThemedMenu(palette: theme())
        m.items = [
            .init(id: "chk", title: "Checked", isChecked: true),
            .init(id: "del", title: "Delete", isDestructive: true),
            .init(id: "sub", title: "More", hasSubmenu: true),
            .init(id: "sc",  title: "Save", shortcut: "⌘S"),
            .init(id: "both", title: "Checked over icon", icon: suppliedIcon, isChecked: true),
        ]
        let rows = m._list.items
        XCTAssertNotNil(rows[0].image, "a checked item gets a leading checkmark glyph")
        XCTAssertTrue(rows[0].axChecked, "a checked item carries the AX checked flag")
        XCTAssertEqual(rows[1].tint, .error, "a destructive item → error tint")
        XCTAssertEqual(rows[2].trailing, .chevron, "a submenu item → trailing chevron")
        XCTAssertEqual(rows[3].trailing, .shortcut("⌘S"), "a shortcut → trailing lozenge")
        XCTAssertFalse(rows[4].image === suppliedIcon, "isChecked suppresses the supplied icon")
        XCTAssertTrue(rows[4].image === rows[0].image, "the checkmark wins — both checked rows share the same glyph")
    }

    func testCheckedRowAXLabelCarriesMarker() {
        let m = ThemedMenu(palette: theme())
        m.items = [.init(id: "on", title: "Show Sidebar", isChecked: true),
                   .init(id: "off", title: "Show Toolbar")]
        let labels = m._list._axChildren().compactMap { $0.accessibilityLabel() }
        XCTAssertTrue(labels.contains("Show Sidebar, checked"), "a checked item's AX label carries the marker")
        XCTAssertTrue(labels.contains("Show Toolbar"), "an unchecked item's label is unmarked")
    }

    // MARK: - Activation routes to the item's action

    func testActivateRunsActionAndIgnoresNonItems() {
        var fired: [String] = []
        let m = ThemedMenu(palette: theme())
        m.items = [
            .init(id: "a", title: "A", action: { fired.append("a") }),
            .separator(id: "s"),
            .init(id: "b", title: "B", isEnabled: false, action: { fired.append("b") }),
            .header("H", id: "h"),
        ]
        m._activate("a")
        XCTAssertEqual(fired, ["a"], "an enabled item runs its action")
        m._activate("s"); m._activate("b"); m._activate("h"); m._activate("nope")
        XCTAssertEqual(fired, ["a"], "separator / disabled / header / unknown ids never fire")
    }

    func testListActivateCallbackReachesTheItemAction() {
        var fired: [String] = []
        let m = ThemedMenu(palette: theme())
        m.items = [.init(id: "x", title: "X", action: { fired.append("x") })]
        // The list's onActivate (a row click / Enter) is wired to the controller.
        m._list.activateRow("x")
        XCTAssertEqual(fired, ["x"])
    }

    // MARK: - Keyboard nav shares the list highlight (wrap + skip)

    func testKeyboardNavWrapsAndSkipsSeparatorsAndDisabled() {
        let m = ThemedMenu(palette: theme())
        m.items = [.init("A"), .separator(),
                   .init("B"), .init(id: "c", title: "C", isEnabled: false), .init("D")]
        m._list.moveHighlight(1); XCTAssertEqual(m.menuProbe.highlightedID, "A")
        m._list.moveHighlight(1); XCTAssertEqual(m.menuProbe.highlightedID, "B", "skips the separator")
        m._list.moveHighlight(1); XCTAssertEqual(m.menuProbe.highlightedID, "D", "skips the disabled C")
        m._list.moveHighlight(1); XCTAssertEqual(m.menuProbe.highlightedID, "A", "wraps to the first (MUI)")
        m._list.moveHighlight(-1); XCTAssertEqual(m.menuProbe.highlightedID, "D", "wraps back to the last")
    }

    // MARK: - Synthetic AX (only actionable rows are .menuItem; AXPress activates)

    func testAXVendsMenuItemsAndPressActivates() {
        var fired: [String] = []
        let m = ThemedMenu(palette: theme())
        m.items = [.init(id: "a", title: "Apple", action: { fired.append("a") }),
                   .separator(),
                   .init(id: "b", title: "Banana", isEnabled: false)]
        let kids = m._list._axChildren()
        XCTAssertEqual(kids.count, 1, "only the one actionable row vends an AX element")
        XCTAssertEqual(kids.first?.accessibilityRole(), .menuItem)
        XCTAssertEqual(kids.first?.accessibilityLabel(), "Apple")
        XCTAssertEqual(m.menuProbe.axMenuItemLabels, ["Apple"])
        _ = kids.first?.accessibilityPerformPress()
        XCTAssertEqual(fired, ["a"], "AXPress activates the row → runs the item action")
    }

    // MARK: - Open / dismiss + monitor lifecycle (the load-bearing risk)

    func testOpenInstallsMonitorsAndDismissRemovesThem() {
        let (m, anchor) = anchoredMenu([.init("A"), .init("B")])
        XCTAssertFalse(m.menuProbe.hasKeyMonitor, "no monitor before open")
        m.present(from: anchor)
        let open = m.menuProbe
        XCTAssertTrue(open.isOpen)
        XCTAssertTrue(open.hasKeyMonitor, "open installs the local keyDown monitor")
        XCTAssertTrue(open.hasMouseMonitor, "and the outside-click monitor")
        m.dismiss(animated: false)
        let closed = m.menuProbe
        XCTAssertFalse(closed.isOpen)
        XCTAssertFalse(closed.hasKeyMonitor, "dismiss removes the keyDown monitor (else it swallows the host's keys globally)")
        XCTAssertFalse(closed.hasMouseMonitor, "and the outside-click monitor")
    }

    func testInvalidateTearsDownMonitors() {
        let (m, anchor) = anchoredMenu([.init("A")])
        m.present(from: anchor)
        m.invalidate()
        XCTAssertFalse(m.menuProbe.hasKeyMonitor)
        XCTAssertFalse(m.menuProbe.hasMouseMonitor)
        XCTAssertFalse(m.menuProbe.isOpen)
    }

    func testDismissIsIdempotent() {
        let (m, anchor) = anchoredMenu([.init("A")])
        m.present(from: anchor)
        m.dismiss(animated: false)
        m.dismiss(animated: false)          // must not crash / double-fire
        XCTAssertFalse(m.menuProbe.isOpen)
    }

    // MARK: - Initial highlight on open

    func testNoPreHighlightByDefault() {
        let (m, anchor) = anchoredMenu([.init("A"), .init("B")])
        m.present(from: anchor)
        XCTAssertNil(m.menuProbe.highlightedID, "an action menu opens with nothing lit (native NSMenu)")
        m.dismiss(animated: false)
    }

    func testHighlightsFirstOnOpenSkipsLeadingSeparator() {
        let (m, anchor) = anchoredMenu([.separator(), .init("A"), .init("B")]) { $0.highlightsFirstOnOpen = true }
        m.present(from: anchor)
        XCTAssertEqual(m.menuProbe.highlightedID, "A", "opt-in pre-highlights the first ENABLED row")
        m.dismiss(animated: false)
    }

    // MARK: - Activation closes the menu

    func testActivatingHighlightClosesAndRuns() {
        var fired = false
        let (m, anchor) = anchoredMenu([.init(id: "a", title: "A", action: { fired = true })]) { $0.highlightsFirstOnOpen = true }
        m.present(from: anchor)
        XCTAssertTrue(m.menuProbe.isOpen)
        m._list.activateHighlight()             // ⏎ on the highlight
        XCTAssertTrue(fired, "Enter on the highlight runs the action")
        XCTAssertFalse(m.menuProbe.isOpen, "and closes the menu")
        XCTAssertFalse(m.menuProbe.hasKeyMonitor, "activation tears down the keyDown monitor (no global key swallow)")
        XCTAssertFalse(m.menuProbe.hasMouseMonitor, "and the outside-click monitor")
    }

    // MARK: - keyDown monitor routing (swallow owned keys, pass the rest through)

    func testKeyDownSwallowsOwnedKeysAndPassesOthers() {
        let (m, anchor) = anchoredMenu([.init("A"), .init("B")])
        m.present(from: anchor)
        XCTAssertNil(m._handleKey(keyDown(125)), "↓ is swallowed")
        XCTAssertEqual(m.menuProbe.highlightedID, "A", "and moves the highlight")
        XCTAssertNil(m._handleKey(keyDown(125)))
        XCTAssertEqual(m.menuProbe.highlightedID, "B")
        let letter = keyDown(0, chars: "a")
        XCTAssertTrue(m._handleKey(letter) === letter, "an unowned key passes through UNCHANGED (host IME safe)")
        XCTAssertEqual(m.menuProbe.highlightedID, "B", "and does not move the highlight")
        XCTAssertNil(m._handleKey(keyDown(53)), "Esc is swallowed")
        XCTAssertFalse(m.menuProbe.isOpen, "and dismisses the menu")
        let afterClose = keyDown(125)
        XCTAssertTrue(m._handleKey(afterClose) === afterClose, "once closed the monitor passes every key through (guard isOpen)")
    }

    func testTabDismissesButPassesThrough() {
        let (m, anchor) = anchoredMenu([.init("A")])
        m.present(from: anchor)
        let tab = keyDown(48)
        XCTAssertTrue(m._handleKey(tab) === tab, "Tab is NOT swallowed (no focus trap)")
        XCTAssertFalse(m.menuProbe.isOpen, "but it dismisses the menu")
    }

    func testEnterKeyActivatesHighlightAndCloses() {
        var fired = false
        let (m, anchor) = anchoredMenu([.init(id: "a", title: "A", action: { fired = true })]) { $0.highlightsFirstOnOpen = true }
        m.present(from: anchor)
        XCTAssertNil(m._handleKey(keyDown(36)), "⏎ is swallowed")
        XCTAssertTrue(fired, "⏎ activates the highlight")
        XCTAssertFalse(m.menuProbe.isOpen, "and closes the menu")
    }

    // MARK: - Context menu (present at a point) + deferred mouse monitor

    func testContextMenuDefersMouseMonitor() {
        let (m, anchor) = anchoredMenu([.init("A"), .init("B")])
        guard let win = anchor.window else { return XCTFail("no host window") }
        m.present(at: CGPoint(x: 40, y: 40), in: win)
        XCTAssertTrue(m.menuProbe.hasKeyMonitor, "the keyDown monitor arms synchronously")
        XCTAssertFalse(m.menuProbe.hasMouseMonitor, "the outside-click monitor is DEFERRED (the opening click must pass first)")
        pump()
        XCTAssertTrue(m.menuProbe.hasMouseMonitor, "and arms on the next runloop turn")
        m.dismiss(animated: false)
    }

    func testContextMenuDismissedBeforeDeferredArmDoesNotLeak() {
        let (m, anchor) = anchoredMenu([.init("A")])
        guard let win = anchor.window else { return XCTFail("no host window") }
        m.present(at: CGPoint(x: 40, y: 40), in: win)
        m.dismiss(animated: false)              // close BEFORE the deferred arm fires
        pump()
        XCTAssertFalse(m.menuProbe.hasMouseMonitor, "a menu closed before the deferred arm installs no monitor (no leak)")
        XCTAssertFalse(m.menuProbe.isOpen)
    }

    // MARK: - Placement → Grow-origin corner

    func testDropDownResolvesTopLeadingWithRoomBelow() throws {
        guard let vf = NSScreen.main?.visibleFrame else { throw XCTSkip("no screen") }
        let (m, anchor) = anchoredMenuAt(CGPoint(x: vf.midX, y: vf.midY), [.init("A"), .init("B"), .init("C")])
        m.present(from: anchor)
        XCTAssertEqual(m.menuProbe.resolvedCorner, .topLeading, "room below ⇒ drop down, Grow from the top-leading corner")
        XCTAssertTrue(m.menuProbe.reduceMotionRespected, "no live fade is left running under reduce-motion")
        m.dismiss(animated: false)
    }

    func testDropDownFlipsAboveAtBottomEdge() throws {
        guard let vf = NSScreen.main?.visibleFrame else { throw XCTSkip("no screen") }
        let (m, anchor) = anchoredMenuAt(CGPoint(x: vf.midX, y: vf.minY + 2), [.init("A"), .init("B"), .init("C")])
        m.present(from: anchor)
        XCTAssertEqual(m.menuProbe.resolvedCorner, .bottomLeading, "no room below ⇒ flip above, Grow from the bottom-leading corner")
        m.dismiss(animated: false)
    }
}
