// ThemeKit / ThemedComboBox tests — DETERMINISTIC in headless CI (no Xcode
// locally → these first compile + run in CI). The popup is driven via
// `previewOpen` / `previewHighlight` + the public field seams the combo wires
// (`onChange` / `onMoveDown` / `onReturn` / `onEscape` / `onFocusChange`), and
// read through the DEBUG `comboProbe`; no synthetic mouse events. The live
// click-keeps-focus / IME / placement-flip 演出 is proven in prism, not here.
// Window-server-dependent asserts (panel ordered in, screen placement) are
// guarded so a truly headless box doesn't hard-fail.

import XCTest
import AppKit
import Palette
import PaletteKit
import TestSupport
@testable import ThemeKitUI   // ThemedComboBox moved here (#17b M3); for the DEBUG `comboProbe`

@MainActor
final class ThemedComboBoxTests: XCTestCase {

    private func theme(_ name: String = "terminal") -> ResolvedPalette {
        resolve(paletteFor(name))
    }

    private func items(_ s: [String]) -> [ThemedComboBox.Item] {
        s.map { ThemedComboBox.Item($0) }
    }

    /// A borderless host window whose contentView holds the combo's field, so the
    /// field has a window (popup placement needs one). Returns the strong refs the
    /// caller must keep alive (the combo holds nothing of the window strongly).
    private func hosted(_ options: [String], _ p: ResolvedPalette? = nil,
                        frame: NSRect = NSRect(x: 200, y: 400, width: 240, height: 46))
        -> (NSWindow, ThemedComboBox) {
        let win = NSWindow(contentRect: frame, styleMask: [.borderless],
                           backing: .buffered, defer: true)
        let host = NSView(frame: NSRect(origin: .zero, size: frame.size))
        win.contentView = host
        let combo = ThemedComboBox(palette: p ?? theme())
        combo.options = items(options)
        host.addSubview(combo.field)
        combo.field.frame = host.bounds
        return (win, combo)
    }

    /// Simulate a keystroke: set the value then fire the change the field would.
    private func type(_ combo: ThemedComboBox, _ q: String) {
        combo.field.stringValue = q
        combo.field.onChange?(q)
    }

    // MARK: - Filtering (pure)

    func testDefaultFilterIsSubstringCaseAndDiacriticInsensitive() {
        let opts = items(["Apple", "Apricot", "Banana", "Grape", "café"])
        XCTAssertEqual(ThemedComboBox.defaultFilter(opts, "ap").map(\.label),
                       ["Apple", "Apricot", "Grape"], "case-insensitive substring (matchFrom any)")
        XCTAssertEqual(ThemedComboBox.defaultFilter(opts, "cafe").map(\.label),
                       ["café"], "diacritic-insensitive")
        XCTAssertEqual(ThemedComboBox.defaultFilter(opts, "").count, opts.count,
                       "empty query returns all")
    }

    func testTypingNarrowsFilteredCount() {
        let (w, c) = hosted(["Apple", "Apricot", "Banana", "Grape", "Mango"])
        XCTAssertEqual(c.comboProbe.filteredCount, 5, "all options before typing")
        type(c, "ap")
        XCTAssertEqual(c.comboProbe.filteredCount, 3, "Apple / Apricot / Grape match 'ap'")
        _ = w
    }

    // MARK: - Keyboard

    func testArrowDownAdvancesWrapsAndSkipsDisabled() {
        let (w, c) = hosted(["Apple", "Apricot", "Banana", "Grape", "Mango"])
        c.isOptionDisabled = { $0.label == "Banana" }   // index 2 disabled
        c.previewOpen = true
        XCTAssertNil(c.comboProbe.highlightedIndex, "no highlight until the first arrow")
        _ = c.field.onMoveDown?(); XCTAssertEqual(c.comboProbe.highlightedIndex, 0)
        _ = c.field.onMoveDown?(); XCTAssertEqual(c.comboProbe.highlightedIndex, 1)
        _ = c.field.onMoveDown?(); XCTAssertEqual(c.comboProbe.highlightedIndex, 3, "skips disabled index 2")
        _ = c.field.onMoveDown?(); XCTAssertEqual(c.comboProbe.highlightedIndex, 4)
        _ = c.field.onMoveDown?(); XCTAssertEqual(c.comboProbe.highlightedIndex, 0, "wraps to the top")
        _ = c.field.onMoveUp?();   XCTAssertEqual(c.comboProbe.highlightedIndex, 4, "up wraps to the bottom")
        _ = w
    }

    func testArrowConsumesAndOpensWhenClosed() {
        let (w, c) = hosted(["Apple", "Banana"])
        XCTAssertFalse(c.comboProbe.isOpen, "starts closed")
        let consumed = c.field.onMoveDown?()
        XCTAssertEqual(consumed, true, "ArrowDown is consumed (suppresses caret movement)")
        XCTAssertTrue(c.comboProbe.isOpen, "ArrowDown opens the popup when closed")
        XCTAssertEqual(c.comboProbe.highlightedIndex, 0, "and lands on the first enabled row")
        _ = w
    }

    func testEnterCommitsHighlightFiresOnSelect() {
        let (w, c) = hosted(["Apple", "Apricot", "Banana"])
        var picked: ThemedComboBox.Item?
        c.onSelect = { picked = $0 }
        c.previewOpen = true
        _ = c.field.onMoveDown?()            // highlight 0 (Apple)
        _ = c.field.onMoveDown?()            // highlight 1 (Apricot)
        let consumed = c.field.onReturn?()
        XCTAssertEqual(consumed, true, "Return is consumed while open")
        XCTAssertEqual(picked?.label, "Apricot", "Enter commits the highlighted row")
        XCTAssertEqual(c.comboProbe.committedValue, "Apricot")
        XCTAssertEqual(c.field.stringValue, "Apricot", "the field shows the committed label")
        XCTAssertFalse(c.comboProbe.isOpen, "the popup closes on commit")
        _ = w
    }

    func testReturnFallsThroughWhenClosed() {
        let (w, c) = hosted(["Apple"])
        XCTAssertEqual(c.field.onReturn?(), false, "a closed combo lets the host's Return fire")
        _ = w
    }

    func testEscClosesThenIsNoOpByDefault() {
        let (w, c) = hosted(["Apple", "Banana"])
        c.previewOpen = true
        XCTAssertEqual(c.field.onEscape?(), true, "Esc consumes + closes while open")
        XCTAssertFalse(c.comboProbe.isOpen)
        XCTAssertEqual(c.field.onEscape?(), false, "closed: Esc falls through (clearsOnEscape=false)")
        _ = w
    }

    func testEscClearsWhenClearsOnEscapeAndClosed() {
        let (w, c) = hosted(["Apple", "Banana"])
        c.clearsOnEscape = true
        c.selectedIndex = 0
        XCTAssertEqual(c.field.stringValue, "Apple")
        XCTAssertEqual(c.field.onEscape?(), true, "closed + clearsOnEscape: Esc consumes")
        XCTAssertEqual(c.field.stringValue, "", "and clears the field")
        XCTAssertNil(c.selectedItem, "and the selection")
        _ = w
    }

    // MARK: - Selection / blur

    func testProgrammaticSelectionDoesNotFireOnSelect() {
        let (w, c) = hosted(["Apple", "Apricot", "Banana"])
        var fired = false
        c.onSelect = { _ in fired = true }
        c.selectedIndex = 2
        XCTAssertFalse(fired, "a programmatic selectedIndex is not a user choice")
        XCTAssertEqual(c.selectedItem?.label, "Banana")
        XCTAssertEqual(c.field.stringValue, "Banana", "the label is pushed into the field")
        XCTAssertEqual(c.comboProbe.committedValue, "Banana", "and becomes the blur-revert target")
        _ = w
    }

    func testClearOnBlurRevertsSelectOnly() {
        let (w, c) = hosted(["Apple", "Apricot", "Banana"])
        c.selectedIndex = 0                              // commit Apple
        type(c, "Xyz")                                   // type a non-match
        c.field.onFocusChange?(false)                    // blur (not a row click)
        XCTAssertEqual(c.field.stringValue, "Apple", "select-only reverts the unmatched text on blur")
        _ = w
    }

    func testFreeTextKeepsTextOnBlurAndCommits() {
        let (w, c) = hosted(["Apple", "Apricot"])
        c.allowsFreeText = true
        var picked: ThemedComboBox.Item?
        c.onSelect = { picked = $0 }
        type(c, "Xyz")
        c.field.onFocusChange?(false)
        XCTAssertEqual(c.field.stringValue, "Xyz", "freeSolo keeps the typed text on blur")
        XCTAssertEqual(picked?.label, "Xyz", "and commits it as a free item")
        _ = w
    }

    func testClearButtonClearsAndFires() {
        let (w, c) = hosted(["Apple", "Apricot"])
        c.selectedIndex = 0
        // `picked` starts at the OUTER nil so an actual onSelect(nil) fire (→ .some(nil))
        // is observable — the assertion below would fail if clear() stopped firing.
        var change: String?; var picked: ThemedComboBox.Item?? = nil
        c.onChange = { change = $0 }
        c.onSelect = { picked = .some($0) }
        c.field.onSecondTrailingTap?()                   // the clear-× slot
        XCTAssertEqual(c.field.stringValue, "")
        XCTAssertNil(c.selectedItem)
        XCTAssertEqual(change, "", "clear fires onChange(\"\") so a bound list refreshes")
        XCTAssertEqual(picked, .some(nil), "clear fires onSelect(nil)")
        _ = w
    }

    // MARK: - Theming (canonical roles)

    func testColoursMatchCanonicalRoles() {
        for name in ["github-light", "dracula", "cyberpunk"] {
            let p = theme(name)
            let (w, c) = hosted(["Apple", "Banana"], p)
            c.previewOpen = true
            let pr = c.comboProbe
            // The container surface + border are read back from the layer (real
            // rendered state). The row highlight (selection wash + primary accent
            // bar) is proven LIVE in prism — drawRows reads the roles directly, so
            // a probe assertion would only echo the input palette.
            sameColor(pr.surfaceColor, p.background ?? .textBackgroundColor,
                      "popup surface = background (\(name))")
            sameColor(pr.borderColor, p.border, "popup edge = border (\(name))")
            _ = w
        }
    }

    // MARK: - Empty state / lifecycle / placement

    func testNoOptionsRowOnEmptyFilter() {
        let (w, c) = hosted(["Apple", "Banana"])
        c.previewOpen = true
        type(c, "zzz")
        let pr = c.comboProbe
        XCTAssertEqual(pr.filteredCount, 0)
        XCTAssertTrue(pr.noOptions, "an unmatched filter shows the No-options row")
        XCTAssertTrue(pr.isOpen, "the popup stays open (one-row height), not zero-height")
        _ = w
    }

    func testPreviewOpenSnapsWithoutAnimation() {
        let (w, c) = hosted(["Apple", "Banana"])
        c.previewOpen = true
        let pr = c.comboProbe
        XCTAssertFalse(pr.hasOpacityAnimation, "previewOpen snaps — no fade")
        XCTAssertTrue(pr.reduceMotionRespected, "and can never violate reduce-motion")
        _ = w
    }

    func testInvalidateTearsDown() {
        let (w, c) = hosted(["Apple", "Banana"])
        c.previewOpen = true
        XCTAssertTrue(c.comboProbe.isOpen, "open")
        c.invalidate()
        XCTAssertFalse(c.comboProbe.isOpen, "closed after invalidate()")
        XCTAssertFalse(c.comboProbe.panelOrderedIn, "panel ordered out")
        c.invalidate()  // idempotent
        XCTAssertFalse(c.comboProbe.isOpen, "invalidate() is idempotent")
        _ = w
    }

    func testPopupWidthEqualsFieldWidth() throws {
        guard NSScreen.main != nil else { throw XCTSkip("no screen") }
        let (w, c) = hosted(["Apple", "Banana"],
                            frame: NSRect(x: 300, y: 400, width: 220, height: 46))
        c.previewOpen = true
        guard c.comboProbe.panelOrderedIn else { throw XCTSkip("headless: panel not ordered") }
        XCTAssertEqual(c.comboProbe.popupFrame.width, 220, accuracy: 0.5,
                       "popup width tracks the field width")
        _ = w
    }

    func testFlipsAboveAtBottomEdge() throws {
        guard let vf = NSScreen.main?.visibleFrame else { throw XCTSkip("no screen") }
        let (w, c) = hosted(["Apple", "Banana", "Grape"],
                            frame: NSRect(x: vf.midX, y: vf.minY + 2, width: 200, height: 46))
        c.previewOpen = true
        guard c.comboProbe.panelOrderedIn else { throw XCTSkip("headless: panel not ordered") }
        XCTAssertTrue(c.comboProbe.flippedAbove, "a bottom-edge combo flips its popup above")
        XCTAssertTrue(vf.contains(c.comboProbe.popupFrame), "the flipped popup stays on screen")
        _ = w
    }

    // MARK: - Actionable empty state (emptyActionRow / onEmptyAction)

    func testEmptyStateInertByDefault() {
        let (w, c) = hosted(["Apple", "Banana"])
        type(c, "zzz")
        let pr = c.comboProbe
        XCTAssertTrue(pr.noOptions, "0 matches")
        XCTAssertFalse(pr.emptyActionActive, "no emptyActionRow ⇒ inert No options")
        XCTAssertNil(pr.emptyActionLabel)
        _ = w
    }

    func testEmptyActionRowOffersActionableRow() {
        let (w, c) = hosted(["Apple", "Banana"])
        c.emptyActionRow = { $0.isEmpty ? nil : "Create “\($0)”" }
        type(c, "kiwi")
        let pr = c.comboProbe
        XCTAssertTrue(pr.emptyActionActive, "0 matches + emptyActionRow ⇒ actionable row")
        XCTAssertEqual(pr.emptyActionLabel, "Create “kiwi”")
        // With matches present the hook is NOT consulted.
        type(c, "ap")
        XCTAssertFalse(c.comboProbe.emptyActionActive, "matches present ⇒ no action row")
        _ = w
    }

    func testEmptyActionRowReturningNilStaysInert() {
        let (w, c) = hosted(["Apple", "Banana"])
        c.emptyActionRow = { _ in nil }      // e.g. an invalid/empty normalized name
        type(c, "zzz")
        XCTAssertFalse(c.comboProbe.emptyActionActive, "nil from the hook ⇒ inert")
        XCTAssertTrue(c.comboProbe.noOptions)
        _ = w
    }

    func testArrowHighlightsActionRow() {
        let (w, c) = hosted(["Apple", "Banana"])
        c.emptyActionRow = { "Create \($0)" }
        type(c, "kiwi")                       // opens; action row present, not yet highlighted
        XCTAssertNil(c.comboProbe.highlightedIndex)
        _ = c.field.onMoveDown?()
        XCTAssertEqual(c.comboProbe.highlightedIndex, 0, "arrow highlights the single action row")
        _ = w
    }

    func testEnterCommitsEmptyActionWithQuery() {
        let (w, c) = hosted(["Apple", "Banana"])
        c.emptyActionRow = { "Create \($0)" }
        var created: String?
        c.onEmptyAction = { created = $0 }
        var picked: Bool = false
        c.onSelect = { _ in picked = true }
        type(c, "kiwi")                       // opens with the action row
        let consumed = c.field.onReturn?()
        XCTAssertEqual(consumed, true, "Return is consumed by the action row")
        XCTAssertEqual(created, "kiwi", "Enter fires onEmptyAction with the live query")
        XCTAssertFalse(picked, "the empty action is NOT a normal onSelect")
        XCTAssertFalse(c.comboProbe.isOpen, "the popup closes after the action")
        _ = w
    }

    func testEmptyActionDoesNotFireWhenInert() {
        let (w, c) = hosted(["Apple", "Banana"])
        var fired = false
        c.onEmptyAction = { _ in fired = true }   // no emptyActionRow ⇒ inert
        type(c, "zzz")
        _ = c.field.onReturn?()
        XCTAssertFalse(fired, "Enter on an inert No-options row never fires onEmptyAction")
        XCTAssertFalse(c.comboProbe.isOpen, "Enter still closes the popup")
        _ = w
    }
}
