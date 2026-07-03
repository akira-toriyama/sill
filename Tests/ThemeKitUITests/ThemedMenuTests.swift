// ThemeKitUI / ThemedMenu tests — DETERMINISTIC in headless CI (no Xcode locally →
// these first compile + run in CI). The menu is driven via its public API + the
// DEBUG `menuProbe` / `_controller` / `_activate` seams; the hosted SwiftUI list's
// nav / AX are exercised through the `ListController` the menu configures. Open /
// monitor-lifecycle uses a real (un-ordered) NSWindow + anchor. The Grow appearance
// + live VoiceOver traversal are proven LIVE in prism, not asserted here.
//
// #17b M4: the menu moved ThemeKit → ThemeKitUI (its rows are now the SwiftUI
// `ThemedListView`); `@testable import ThemeKit` stays for the composed
// `ThemedToolBar`'s probe/tap seams (the horizontal presentation) + `PopupCorner`.

import XCTest
import AppKit
import Palette
import PaletteKit
@testable import ThemeKit
@testable import ThemeKitUI

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
        XCTAssertEqual(m._controller.items.count, 4)
        let rows = m._controller.items
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
        let rows = m._controller.items
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
        let labels = m.menuProbe.axMenuItemLabels
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
        // The controller's onActivate (a row click's synchronous mouseUp commit) is
        // wired to the item's action.
        m._controller.fireActivate("x")
        XCTAssertEqual(fired, ["x"])
    }

    // MARK: - Keyboard nav shares the list highlight (wrap + skip)

    func testKeyboardNavWrapsAndSkipsSeparatorsAndDisabled() {
        let m = ThemedMenu(palette: theme())
        m.items = [.init("A"), .separator(),
                   .init("B"), .init(id: "c", title: "C", isEnabled: false), .init("D")]
        m._controller.moveHighlight(1); XCTAssertEqual(m.menuProbe.highlightedID, "A")
        m._controller.moveHighlight(1); XCTAssertEqual(m.menuProbe.highlightedID, "B", "skips the separator")
        m._controller.moveHighlight(1); XCTAssertEqual(m.menuProbe.highlightedID, "D", "skips the disabled C")
        m._controller.moveHighlight(1); XCTAssertEqual(m.menuProbe.highlightedID, "A", "wraps to the first (MUI)")
        m._controller.moveHighlight(-1); XCTAssertEqual(m.menuProbe.highlightedID, "D", "wraps back to the last")
    }

    // MARK: - Per-row AX (only actionable rows are exposed; activating runs the action)

    func testAXVendsMenuItemsAndPressActivates() {
        var fired: [String] = []
        let m = ThemedMenu(palette: theme())
        m.items = [.init(id: "a", title: "Apple", action: { fired.append("a") }),
                   .separator(),
                   .init(id: "b", title: "Banana", isEnabled: false)]
        // Only the one actionable row is exposed as a menu item (separator + disabled
        // excluded). The SwiftUI rows carry the real per-row `.isButton` AX
        // (`vendsRowAXElements`); the live VoiceOver press is proven in prism, and the
        // AXPress-equivalent (a row activation) runs the item's action here.
        XCTAssertEqual(m.menuProbe.axMenuItemLabels, ["Apple"], "only the actionable row is a menu item")
        m._controller.fireActivate("a")
        XCTAssertEqual(fired, ["a"], "activating the actionable row runs its action")
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

    // MARK: - Preview seam (deterministic capture — the hosted list's `highlight` is
    // the vertical preview override now, so a caller-set highlight must survive open)

    func testVerticalPreviewOpenKeepsCallerHighlight() {
        let (m, anchor) = anchoredMenu([.init("A"), .init("B"), .init("C")])
        m.previewAnchor = anchor
        m.previewHighlight = "B"
        m.previewOpen = true
        XCTAssertTrue(m.menuProbe.isOpen, "previewOpen presents the menu (no dismiss monitors)")
        XCTAssertEqual(m.menuProbe.highlightedID, "B",
                       "a caller-set previewHighlight survives the preview open (not cleared)")
        m.previewOpen = false
    }

    // MARK: - Activation closes the menu

    func testActivatingHighlightClosesAndRuns() {
        var fired = false
        let (m, anchor) = anchoredMenu([.init(id: "a", title: "A", action: { fired = true })]) { $0.highlightsFirstOnOpen = true }
        m.present(from: anchor)
        XCTAssertTrue(m.menuProbe.isOpen)
        m._controller.activateHighlight()       // ⏎ on the highlight
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

    // MARK: - Submenu cascade

    /// A menu with one submenu row ("More" → Sub 1/2/3) between two leaf rows.
    private func cascadeItems() -> [ThemedMenu.MenuItem] {
        [.init("A"),
         .init(id: "more", title: "More", submenu: [
            .init(id: "s1", title: "Sub 1"),
            .init(id: "s2", title: "Sub 2"),
            .init(id: "s3", title: "Sub 3"),
         ]),
         .init("B")]
    }

    func testSubmenuChildrenAutoSetChevron() {
        let m = ThemedMenu(palette: theme())
        m.items = cascadeItems()
        XCTAssertTrue(m.items[1].hasSubmenu, "non-empty submenu auto-sets hasSubmenu")
        XCTAssertEqual(m._controller.items[1].trailing, .chevron, "a submenu row → trailing chevron")
    }

    func testOpenSubmenuShowsChildRows() {
        let (m, anchor) = anchoredMenu(cascadeItems())
        m.present(from: anchor)
        XCTAssertFalse(m.menuProbe.childOpen, "no child until opened")
        m._openSubmenu("more")
        let p = m.menuProbe
        XCTAssertTrue(p.childOpen, "opening a submenu row shows the child")
        XCTAssertEqual(p.childRowID, "more")
        XCTAssertEqual(p.childRowCount, 3, "the child hosts the submenu's rows")
        XCTAssertTrue(p.leafIsChild, "the active leaf is now the child (keys route there)")
        m.dismiss(animated: false)
    }

    func testRightArrowOpensAndLeftClosesSubmenu() {
        let (m, anchor) = anchoredMenu(cascadeItems())
        m.present(from: anchor)
        m._controller.moveHighlight(1)                 // A
        m._controller.moveHighlight(1)                 // More (the submenu row)
        XCTAssertEqual(m.menuProbe.highlightedID, "more")
        XCTAssertNil(m._handleKey(keyDown(124)), "→ is swallowed")
        XCTAssertTrue(m.menuProbe.childOpen, "→ on a submenu row opens the child")
        XCTAssertNil(m._handleKey(keyDown(123)), "← is swallowed")
        XCTAssertFalse(m.menuProbe.childOpen, "← closes the child (back to the parent level)")
        XCTAssertEqual(m.menuProbe.highlightedID, "more", "the parent row stays highlighted")
        m.dismiss(animated: false)
    }

    func testArrowsRouteToTheOpenChild() {
        let (m, anchor) = anchoredMenu(cascadeItems())
        m.present(from: anchor)
        m._openSubmenu("more")
        XCTAssertEqual(m.menuProbe.childHighlightedID, "s1", "openSubmenu lit the child's first row")
        XCTAssertNil(m._handleKey(keyDown(125)), "↓ swallowed")
        XCTAssertEqual(m.menuProbe.childHighlightedID, "s2", "↓ moves the CHILD highlight (keys route to the leaf)")
        m.dismiss(animated: false)
    }

    func testActivatingChildLeafBubblesDismissAndRunsAction() {
        var fired: [String] = []
        let items: [ThemedMenu.MenuItem] = [
            .init(id: "more", title: "More", submenu: [
                .init(id: "s1", title: "Sub 1", action: { fired.append("s1") }),
            ]),
        ]
        let (m, anchor) = anchoredMenu(items)
        m.present(from: anchor)
        m._openSubmenu("more")
        XCTAssertTrue(m.menuProbe.childOpen)
        m._child?._activate("s1")                // click a child leaf row
        XCTAssertEqual(fired, ["s1"], "the child leaf's action runs")
        XCTAssertFalse(m.menuProbe.isOpen, "and the WHOLE chain dismisses (bubbles to the root)")
        XCTAssertFalse(m.menuProbe.childOpen)
    }

    func testSubmenuRowActivationOpensChildNotItsAction() {
        var fired = false
        let items: [ThemedMenu.MenuItem] = [
            .init(id: "more", title: "More", submenu: [.init(id: "s1", title: "Sub 1")], action: { fired = true }),
        ]
        let (m, anchor) = anchoredMenu(items)
        m.present(from: anchor)
        m._activate("more")                      // ⏎ / click on the submenu row
        XCTAssertFalse(fired, "a submenu row's own action is ignored — opening the child IS its activation")
        XCTAssertTrue(m.menuProbe.childOpen, "activating a submenu row opens the child")
        m.dismiss(animated: false)
    }

    func testEscClosesOneLevelThenDismisses() {
        let (m, anchor) = anchoredMenu(cascadeItems())
        m.present(from: anchor)
        m._openSubmenu("more")
        XCTAssertTrue(m.menuProbe.childOpen)
        XCTAssertNil(m._handleKey(keyDown(53)), "Esc swallowed")
        XCTAssertFalse(m.menuProbe.childOpen, "Esc closes the submenu level first")
        XCTAssertTrue(m.menuProbe.isOpen, "the root stays open")
        XCTAssertNil(m._handleKey(keyDown(53)))
        XCTAssertFalse(m.menuProbe.isOpen, "a second Esc dismisses the root")
    }

    func testDismissClosesTheChild() {
        let (m, anchor) = anchoredMenu(cascadeItems())
        m.present(from: anchor)
        m._openSubmenu("more")
        XCTAssertTrue(m.menuProbe.childOpen)
        m.dismiss(animated: false)
        XCTAssertFalse(m.menuProbe.childOpen, "dismiss closes the child too")
        XCTAssertFalse(m.menuProbe.isOpen)
    }

    // MARK: - Submenu cascade (N-level)

    /// A two-level cascade: More → Deep → G1/G2.
    private func deepCascadeItems() -> [ThemedMenu.MenuItem] {
        [.init(id: "more", title: "More", submenu: [
            .init(id: "deep", title: "Deep", submenu: [
                .init(id: "g1", title: "G1"),
                .init(id: "g2", title: "G2"),
            ]),
        ])]
    }

    func testChildOpensGrandchild() {
        let (m, anchor) = anchoredMenu(deepCascadeItems())
        m.present(from: anchor)
        m._openSubmenu("more")
        XCTAssertTrue(m.menuProbe.childOpen, "the level-1 child opens")
        m._child?._openSubmenu("deep")           // open a grandchild from the child
        XCTAssertTrue(m._child?.menuProbe.childOpen ?? false, "a child now opens its grandchild (N-level)")
        // menuProbe.childRowCount = THIS menu's child's row count, so the level-1
        // child's childRowCount is the grandchild's own row count.
        XCTAssertEqual(m._child?.menuProbe.childRowCount, 2, "the grandchild hosts Deep's rows")
        m.dismiss(animated: false)
    }

    func testDismissTearsDownWholeDeepChain() {
        let (m, anchor) = anchoredMenu(deepCascadeItems())
        m.present(from: anchor)
        m._openSubmenu("more")
        m._child?._openSubmenu("deep")
        XCTAssertTrue(m._child?.menuProbe.childOpen ?? false, "grandchild open before dismiss")
        m.dismiss(animated: false)
        XCTAssertFalse(m.menuProbe.isOpen, "root closed")
        XCTAssertFalse(m.menuProbe.childOpen, "child closed (children-first teardown)")
    }

    func testEscClosesDeepChainOneLevelAtATime() {
        let (m, anchor) = anchoredMenu(deepCascadeItems())
        m.present(from: anchor)
        m._openSubmenu("more")
        m._child?._openSubmenu("deep")
        XCTAssertTrue(m._child?.menuProbe.childOpen ?? false, "grandchild open")
        XCTAssertNil(m._handleKey(keyDown(53)), "Esc swallowed")
        XCTAssertFalse(m._child?.menuProbe.childOpen ?? true, "first Esc closes the deepest (grandchild) level")
        XCTAssertTrue(m.menuProbe.childOpen, "the level-1 child stays open")
        XCTAssertNil(m._handleKey(keyDown(53)))
        XCTAssertFalse(m.menuProbe.childOpen, "second Esc closes the child level")
        XCTAssertTrue(m.menuProbe.isOpen, "the root stays open")
        XCTAssertNil(m._handleKey(keyDown(53)))
        XCTAssertFalse(m.menuProbe.isOpen, "third Esc dismisses the root")
    }

    func testCloseChildTearsDownDeeperLevels() {
        // The mechanism a hover-onto-a-non-submenu-row uses: closeChild() must
        // recursively collapse EVERY deeper level, not just the direct child.
        let (m, anchor) = anchoredMenu(deepCascadeItems())
        m.present(from: anchor)
        m._openSubmenu("more")
        m._child?._openSubmenu("deep")
        XCTAssertTrue(m._child?.menuProbe.childOpen ?? false, "grandchild open")
        m._closeChild()                          // collapse from the root
        XCTAssertFalse(m.menuProbe.childOpen, "the whole open chain collapses (child + grandchild)")
        m.dismiss(animated: false)
    }

    func testRightArrowOnNonSubmenuRowPassesThrough() {
        let (m, anchor) = anchoredMenu(cascadeItems())
        m.present(from: anchor)
        m._controller.moveHighlight(1)                 // A — a leaf row with no submenu
        XCTAssertEqual(m.menuProbe.highlightedID, "A")
        let right = keyDown(124)
        XCTAssertTrue(m._handleKey(right) === right, "→ on a non-submenu row passes through UNCHANGED (host IME safe)")
        XCTAssertFalse(m.menuProbe.childOpen, "and opens nothing")
        m.dismiss(animated: false)
    }

    func testLeftArrowAtRootPassesThrough() {
        let (m, anchor) = anchoredMenu(cascadeItems())
        m.present(from: anchor)
        let left = keyDown(123)
        XCTAssertTrue(m._handleKey(left) === left, "← at the root with no open child passes through UNCHANGED (host IME safe)")
        m.dismiss(animated: false)
    }

    // MARK: - Horizontal presentation (.toolbar / .labeledToolbar — the menu bar)

    /// A/Folder(→S1,S2)/B, laid out as a horizontal bar. Folder is the one submenu item.
    private func horizontalItems() -> [ThemedMenu.MenuItem] {
        [.init("A"),
         .init(id: "folder", title: "Folder", submenu: [.init(id: "s1", title: "S1"),
                                                         .init(id: "s2", title: "S2")]),
         .init("B")]
    }

    func testToolbarPresentationMapsItemsToBar() {
        let m = ThemedMenu(palette: theme())
        m.presentation = .toolbar
        m.items = horizontalItems()
        XCTAssertEqual(m.menuProbe.presentation, .toolbar, "the root reports its horizontal presentation")
        XCTAssertEqual(m._toolbar?.toolBarProbe.itemCount, 3, "3 menu items → 3 toolbar items (composed ThemedToolBar)")
        XCTAssertEqual(m.menuProbe.rowCount, 3, "the probe row count reads the bar's item count when horizontal")
    }

    func testHorizontalArrowsMoveAlongTheBar() {
        let (m, anchor) = anchoredMenu(horizontalItems()) { $0.presentation = .toolbar }
        m.present(from: anchor)
        XCTAssertNil(m._handleKey(keyDown(124)), "→ swallowed")
        XCTAssertEqual(m.menuProbe.highlightedID, "A", "→ lights the first bar item")
        XCTAssertNil(m._handleKey(keyDown(124)))
        XCTAssertEqual(m.menuProbe.highlightedID, "folder", "→ moves to the NEXT item along the bar")
        XCTAssertNil(m._handleKey(keyDown(123)), "← swallowed")
        XCTAssertEqual(m.menuProbe.highlightedID, "A", "← moves to the PREVIOUS item")
        XCTAssertNil(m._handleKey(keyDown(123)))
        XCTAssertEqual(m.menuProbe.highlightedID, "B", "← wraps to the last (MUI wrap, horizontal)")
        m.dismiss(animated: false)
    }

    func testHorizontalUpArrowIsInert() {
        let (m, anchor) = anchoredMenu(horizontalItems()) { $0.presentation = .toolbar }
        m.present(from: anchor)
        let up = keyDown(126)
        XCTAssertTrue(m._handleKey(up) === up, "↑ on a top bar has no meaning → passes through (host/IME safe)")
        m.dismiss(animated: false)
    }

    func testHorizontalDownOpensChildBelowAndChildIsVertical() {
        let (m, anchor) = anchoredMenu(horizontalItems()) { $0.presentation = .toolbar }
        m.present(from: anchor)
        _ = m._handleKey(keyDown(124))                  // A
        _ = m._handleKey(keyDown(124))                  // Folder
        XCTAssertEqual(m.menuProbe.highlightedID, "folder")
        XCTAssertNil(m._handleKey(keyDown(125)), "↓ swallowed")
        XCTAssertTrue(m.menuProbe.childOpen, "↓ on a folder bar-item opens its child (below)")
        XCTAssertEqual(m.menuProbe.childRowID, "folder")
        XCTAssertEqual(m._child?.menuProbe.presentation, .vertical, "a horizontal root's child is a VERTICAL dropdown")
        XCTAssertEqual(m._child?.menuProbe.rowCount, 2, "the child hosts the submenu's rows")
        XCTAssertTrue(m.menuProbe.leafIsChild, "keys now route to the open child")
        m.dismiss(animated: false)
    }

    func testHorizontalDownOnLeafOpensNothing() {
        let (m, anchor) = anchoredMenu(horizontalItems()) { $0.presentation = .toolbar }
        m.present(from: anchor)
        _ = m._handleKey(keyDown(124))                  // A (a leaf)
        let down = keyDown(125)
        XCTAssertTrue(m._handleKey(down) === down, "↓ on a non-folder bar item passes through (nothing to open)")
        XCTAssertFalse(m.menuProbe.childOpen)
        m.dismiss(animated: false)
    }

    func testHorizontalEnterActivatesLeafAndDismisses() {
        var fired = false
        let items: [ThemedMenu.MenuItem] = [
            .init(id: "a", title: "A", action: { fired = true }),
            .init(id: "folder", title: "Folder", submenu: [.init(id: "s1", title: "S1")]),
        ]
        let (m, anchor) = anchoredMenu(items) { $0.presentation = .toolbar }
        m.present(from: anchor)
        _ = m._handleKey(keyDown(124))                  // highlight A
        XCTAssertEqual(m.menuProbe.highlightedID, "a")
        XCTAssertNil(m._handleKey(keyDown(36)), "⏎ swallowed")
        XCTAssertTrue(fired, "⏎ on a highlighted leaf runs its action")
        XCTAssertFalse(m.menuProbe.isOpen, "and dismisses the bar")
    }

    func testHorizontalClickOpensFolderChild() {
        let (m, anchor) = anchoredMenu(horizontalItems()) { $0.presentation = .toolbar }
        m.present(from: anchor)
        m._toolbar?.simulateItemTapForTesting(1)        // item 1 == "folder" (bar items are 1:1 with menu items)
        XCTAssertTrue(m.menuProbe.childOpen, "clicking a folder bar-item opens its child")
        XCTAssertEqual(m.menuProbe.childRowID, "folder")
        m.dismiss(animated: false)
    }

    func testHorizontalPreviewHighlightLightsMatchingBarItem() throws {
        let m = ThemedMenu(palette: theme())
        m.presentation = .toolbar
        m.items = horizontalItems()
        let tb = try XCTUnwrap(m._toolbar, "a .toolbar root builds its composed ThemedToolBar")
        m.previewHighlight = "folder"
        XCTAssertEqual(tb.toolBarProbe.forcedItem, 1, "previewHighlight forces the matching bar item (index 1) lit")
        XCTAssertEqual(m.previewHighlight, "folder", "the getter round-trips the horizontal preview id")
        m.previewHighlight = nil
        XCTAssertNil(tb.toolBarProbe.forcedItem, "clearing it unlights the bar")
    }

    func testEscDismissesHorizontalRoot() {
        let (m, anchor) = anchoredMenu(horizontalItems()) { $0.presentation = .toolbar }
        m.present(from: anchor)
        XCTAssertNil(m._handleKey(keyDown(53)), "Esc swallowed")
        XCTAssertFalse(m.menuProbe.isOpen, "Esc on a horizontal root with no open child dismisses it")
    }
}
