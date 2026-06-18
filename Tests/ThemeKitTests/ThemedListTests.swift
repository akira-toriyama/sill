// ThemeKit / ThemedList tests — DETERMINISTIC in headless CI (no Xcode locally →
// these first compile + run in CI). The list is driven via the public config +
// `previewHighlight`/`previewSelection` + the pure `stickyHeader`/`_moveHighlight`
// seams, and read through the DEBUG `listProbe`; no synthetic mouse events, no
// live window (the layout cache + role resolvers are pure of the rendered pixels).
// The selection / hover / solidAccent APPEARANCE is proven LIVE in prism, not
// asserted here (the combo-probe precedent).

import XCTest
import AppKit
import Palette
import PaletteKit
@testable import ThemeKit   // for the DEBUG `listProbe` + seams

@MainActor
final class ThemedListTests: XCTestCase {

    private func theme(_ name: String = "terminal") -> ResolvedPalette { resolve(paletteFor(name)) }

    private func makeList(_ items: [ListItem] = [], _ p: ResolvedPalette? = nil) -> ThemedList {
        let l = ThemedList(palette: p ?? theme())
        l.items = items
        return l
    }

    private func row(_ id: String, secondary: String? = nil) -> ListItem {
        ListItem(id: id, primary: id.capitalized, secondary: secondary)
    }
    private func header(_ id: String, subtitle: String? = nil) -> ListItem {
        ListItem(id: id, primary: id, kind: .sectionHeader(subtitle: subtitle))
    }

    private func sameColor(_ a: NSColor, _ b: NSColor, _ msg: String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
        guard let an = a.usingColorSpace(.sRGB), let bn = b.usingColorSpace(.sRGB) else {
            return XCTFail("colour unconvertible: \(msg)", file: file, line: line)
        }
        XCTAssertEqual(an.redComponent,   bn.redComponent,   accuracy: 0.01, msg, file: file, line: line)
        XCTAssertEqual(an.greenComponent, bn.greenComponent, accuracy: 0.01, msg, file: file, line: line)
        XCTAssertEqual(an.blueComponent,  bn.blueComponent,  accuracy: 0.01, msg, file: file, line: line)
        XCTAssertEqual(an.alphaComponent, bn.alphaComponent, accuracy: 0.01, msg, file: file, line: line)
    }

    // MARK: - Geometry / layout cache

    func testComfortableRowHeightsAndCumulativeOffsets() {
        let l = makeList([row("a"), row("b"), row("c")])
        let pr = l.listProbe
        XCTAssertEqual(pr.rowFrames["a"]?.height, 30, "comfortable single-line row = 30 (combo-compat)")
        XCTAssertEqual(pr.rowFrames["a"]?.minY, 0)
        XCTAssertEqual(pr.rowFrames["b"]?.minY, 30, "cumulative offset")
        XCTAssertEqual(pr.rowFrames["c"]?.minY, 60)
        XCTAssertEqual(pr.totalHeight, 90)
    }

    func testTwoLineRowIsTallerAndShiftsLaterOffsets() {
        let l = makeList([row("a"), row("b", secondary: "subtitle"), row("c")])
        let pr = l.listProbe
        XCTAssertEqual(pr.rowFrames["b"]?.height, 46, "a row with secondary text is the two-line height")
        XCTAssertEqual(pr.rowFrames["c"]?.minY, 30 + 46, "the taller row shifts everything below it")
        XCTAssertEqual(pr.totalHeight, 30 + 46 + 30)
    }

    func testHeaderHeightsAndCompactDensity() {
        let l = makeList([header("H1"), row("a"), header("H2", subtitle: "sub"), row("b")])
        let one = l.listProbe
        XCTAssertEqual(one.rowFrames["H1"]?.height, 28, "1-line header = 28")
        XCTAssertEqual(one.rowFrames["H2"]?.height, 40, "2-line header = 40")
        l.density = .compact
        let two = l.listProbe
        XCTAssertEqual(two.rowFrames["a"]?.height, 26, "compact single-line = 26")
        XCTAssertEqual(two.rowFrames["H1"]?.height, 24, "compact 1-line header = 24")
        XCTAssertEqual(two.rowFrames["H2"]?.height, 40, "compact 2-line header = 40 (content doesn't shrink, so it can't clip)")
    }

    // MARK: - Keyboard highlight (skips headers + disabled, clamps)

    func testMoveHighlightSkipsHeadersDisabledAndClamps() {
        let items = [header("H"), row("a"),
                     ListItem(id: "b", primary: "B", isDisabled: true),
                     row("c"), row("d")]
        let l = makeList(items)
        XCTAssertNil(l.listProbe.effectiveHighlightID, "no highlight until the first move")
        l._moveHighlight(1); XCTAssertEqual(l.listProbe.effectiveHighlightID, "a", "lands on the first selectable row (skips the header)")
        l._moveHighlight(1); XCTAssertEqual(l.listProbe.effectiveHighlightID, "c", "skips the disabled 'b'")
        l._moveHighlight(1); XCTAssertEqual(l.listProbe.effectiveHighlightID, "d")
        l._moveHighlight(1); XCTAssertEqual(l.listProbe.effectiveHighlightID, "d", "clamps at the bottom (no wrap)")
        l._moveHighlight(-1); XCTAssertEqual(l.listProbe.effectiveHighlightID, "c")
        l._moveHighlight(-1); XCTAssertEqual(l.listProbe.effectiveHighlightID, "a", "skips 'b' going up")
        l._moveHighlight(-1); XCTAssertEqual(l.listProbe.effectiveHighlightID, "a", "clamps at the top")
    }

    // MARK: - Sticky header pin + handoff (pure seam — no live window)

    func testStickyHeaderPinAndHandoff() {
        // A(2-line=40)@0 · r1(30)@40 · r2(30)@70 · B(1-line=28)@100 · r3(30)@128
        let l = makeList([header("A", subtitle: "s"), row("r1"), row("r2"), header("B"), row("r3")])
        XCTAssertEqual(l._stickyHeader(atScrollY: 0).id, "A", "first header pins at the top")
        let mid = l._stickyHeader(atScrollY: 50)
        XCTAssertEqual(mid.id, "A", "A stays pinned while its section is visible")
        XCTAssertEqual(mid.drawY, 50, "and rides the visible top")
        let handoff = l._stickyHeader(atScrollY: 75)
        XCTAssertEqual(handoff.id, "A", "A is still active just before B arrives")
        XCTAssertEqual(handoff.drawY, 60, "but B (top 100) pushes A up: 100 − 40")
        XCTAssertEqual(l._stickyHeader(atScrollY: 110).id, "B", "past B's top, B takes over")
    }

    func testNoStickyHeaderWhenNoneAbove() {
        let l = makeList([row("a"), header("H"), row("b")])
        XCTAssertNil(l._stickyHeader(atScrollY: 0).id, "no header at/above the top ⇒ nothing pinned")
    }

    // MARK: - Empty / actionable state

    func testEmptyInertByDefault() {
        let l = makeList([])
        let pr = l.listProbe
        XCTAssertTrue(pr.isNoOptions, "empty + no action hook ⇒ inert No options")
        XCTAssertFalse(pr.emptyActionActive)
        XCTAssertNil(pr.emptyActionLabel)
    }

    func testEmptyActionRowOffersAndCommits() {
        let l = makeList([])
        l.emptyActionRow = { $0.isEmpty ? nil : "Create “\($0)”" }
        l.query = "kiwi"
        var pr = l.listProbe
        XCTAssertTrue(pr.emptyActionActive, "0 items + hook ⇒ actionable row")
        XCTAssertEqual(pr.emptyActionLabel, "Create “kiwi”")
        XCTAssertFalse(pr.isNoOptions)
        // Arrow highlights the single synthetic row.
        l._moveHighlight(1)
        XCTAssertEqual(l.listProbe.effectiveHighlightID, ThemedList.emptyActionID)
        var created: String?
        l.onEmptyAction = { created = $0 }
        l.activateRow(ThemedList.emptyActionID)
        XCTAssertEqual(created, "kiwi", "activating the empty row fires onEmptyAction with the live query")
        // An empty query ⇒ the hook returns nil ⇒ inert again.
        l.query = ""
        pr = l.listProbe
        XCTAssertFalse(pr.emptyActionActive)
        XCTAssertTrue(pr.isNoOptions)
    }

    func testEmptyActionGoesInertWhenItemsPresent() {
        let l = makeList([row("a")])
        l.emptyActionRow = { _ in "Create" }
        XCTAssertFalse(l.listProbe.emptyActionActive, "items present ⇒ the hook is never consulted")
    }

    // MARK: - Selection model

    func testProgrammaticSelectedIDIsSilentSelectRowFires() {
        let l = makeList([row("a"), row("b")])
        var fired: [String?] = []
        l.onSelectionChange = { fired.append($0) }
        l.selectedID = "b"
        XCTAssertEqual(l.selectedItem?.id, "b", "programmatic selection lands")
        XCTAssertEqual(l.listProbe.effectiveSelectionID, "b")
        XCTAssertTrue(fired.isEmpty, "a programmatic selectedID is NOT a user choice — no callback")
        l.selectRow("a")
        XCTAssertEqual(fired, ["a"], "selectRow is the user-intent path — fires once")
    }

    func testNoneModeForcesNilAndIgnoresSelectRow() {
        let l = makeList([row("a"), row("b")])
        l.selectedID = "a"
        l.selectionMode = .none
        XCTAssertNil(l.selectedItem, "switching to .none drops the selection")
        XCTAssertNil(l.listProbe.effectiveSelectionID)
        var fired = false
        l.onSelectionChange = { _ in fired = true }
        l.selectRow("b")
        XCTAssertNil(l.selectedItem, ".none ignores selectRow")
        XCTAssertFalse(fired)
    }

    func testSelectionReconciledByIDOnReload() {
        let l = makeList([row("a"), row("b"), row("c")])
        l.selectedID = "b"
        l.items = [row("a"), row("c")]                 // 'b' vanished
        XCTAssertNil(l.selectedItem, "a selection whose id is gone is dropped on reload")
        l.selectedID = "c"
        l.items = [row("c"), row("a")]                 // 'c' still present (reordered)
        XCTAssertEqual(l.selectedItem?.id, "c", "a still-present selection survives a reload")
    }

    func testHeaderAndDisabledRowsAreNotSelectable() {
        let l = makeList([header("H"), ListItem(id: "off", primary: "Off", isDisabled: true), row("a")])
        l.selectedID = "H"
        XCTAssertNil(l.selectedItem, "a header can't be selected")
        l.selectedID = "off"
        XCTAssertNil(l.selectedItem, "a disabled row can't be selected")
        l.selectedID = "a"
        XCTAssertEqual(l.selectedItem?.id, "a")
    }

    // MARK: - Per-row invalidation (D1 — never the blunt full bounds)

    func testHighlightInvalidatesOnlyChangedRows() {
        let l = makeList([row("a"), row("b"), row("c")])   // no headers ⇒ no sticky band term
        l._moveHighlight(1)                                 // nil → a
        l._moveHighlight(1)                                 // a → b
        let rects = l.listProbe.lastInvalidatedRects
        XCTAssertEqual(rects.count, 2, "a highlight move invalidates exactly old + new, not the whole list")
        for r in rects {
            XCTAssertEqual(r.height, 30, "each invalidated rect is a single row, not the full bounds")
        }
        XCTAssertFalse(rects.contains { $0.height == l.listProbe.totalHeight },
                       "never invalidates the full-height bounds")
    }

    func testInvalidatingARowUnderTheStickyBandAlsoRepaintsTheHeader() {
        // header H (28pt) at y:0..28 — its own rect overlaps the [0, maxHeader) band.
        let l = makeList([header("H"), row("a"), row("b")])
        l.setLeadingImage(NSImage(size: NSSize(width: 8, height: 8)), forID: "H")
        let rects = l.listProbe.lastInvalidatedRects
        XCTAssertEqual(rects.count, 2, "a row touching the sticky band also invalidates the pinned-header strip (D1 band term)")
        XCTAssertTrue(rects.contains { $0.minY == 0 && $0.height == 28 },
                      "the appended band strip sits at the visible top, header-height tall")
        // A row clear of the band invalidates exactly itself (no band term).
        l.setLeadingImage(NSImage(), forID: "a")            // 'a' at y:28..58, outside [0,28)
        XCTAssertEqual(l.listProbe.lastInvalidatedRects.count, 1, "a row outside the band → no extra strip")
    }

    // MARK: - Public methods (setLeadingImage / rowFrame)

    func testSetLeadingImageInvalidatesOneRowWithoutRelayout() {
        let l = makeList([row("a"), row("b"), row("c")])
        l.selectedID = "b"
        let before = l.listProbe
        l.setLeadingImage(NSImage(size: NSSize(width: 8, height: 8)), forID: "a")
        let after = l.listProbe
        XCTAssertEqual(after.totalHeight, before.totalHeight, "a favicon swap must NOT relayout")
        XCTAssertEqual(after.rowFrames["a"]?.minY, before.rowFrames["a"]?.minY, "row geometry unchanged")
        XCTAssertEqual(after.effectiveSelectionID, "b", "no reload ⇒ the selection survives")
        XCTAssertEqual(after.lastInvalidatedRects.count, 1, "invalidates exactly one row, not the full bounds")
        l.setLeadingImage(nil, forID: "zzz")               // unknown id = no-op, must not crash
    }

    func testRowFrameForID() {
        let l = makeList([row("a"), row("b")])
        XCTAssertEqual(l.rowFrame(for: "b")?.minY, 30, "real row geometry")
        XCTAssertNil(l.rowFrame(for: "nope"), "unknown id ⇒ nil")
        XCTAssertNil(l.rowFrame(for: ThemedList.emptyActionID), "non-empty list ⇒ the synthetic id is nil")

        let e = makeList([])
        XCTAssertNil(e.rowFrame(for: ThemedList.emptyActionID), "empty but inert ⇒ no synthetic row")
        e.emptyActionRow = { _ in "Create" }; e.query = "x"
        XCTAssertEqual(e.rowFrame(for: ThemedList.emptyActionID)?.minY, 0, "an active empty-action row exposes its rect")
        XCTAssertNil(e.rowFrame(for: "a"), "a non-synthetic id on an empty list ⇒ nil")
    }

    // MARK: - Theming (role resolution — colour equality, not pixels)

    func testResolvedRoleColours() {
        for name in ["github-light", "dracula", "cyberpunk"] {
            let p = theme(name)
            let l = makeList([row("a")], p)
            sameColor(l._primaryTextColor(disabled: false, onAccent: false), p.foreground, "resting primary = foreground (\(name))")
            sameColor(l._primaryTextColor(disabled: true, onAccent: false), p.tertiary, "disabled primary = tertiary (\(name))")
            sameColor(l._primaryTextColor(disabled: false, onAccent: true), p.onPrimary(1), "solidAccent primary = onPrimary (\(name))")
            sameColor(l._badgeFill(.primary, onAccent: false), p.ink(.subtle, of: .primary), "primary badge fill (\(name))")
            sameColor(l._badgeFill(.error, onAccent: false), p.error.withAlphaComponent(0.16), "error badge fill (\(name))")
            // On a .solidAccent row EVERY badge role collapses to the onPrimary fill
            // (so a badge never vanishes into / clashes with the opaque primary).
            for role in [BadgeRole.neutral, .primary, .secondary, .error] {
                sameColor(l._badgeFill(role, onAccent: true), p.onPrimary(0.18),
                          "\(role) badge collapses to onPrimary fill on a solidAccent row (\(name))")
            }
        }
    }

    // MARK: - First-responder gate

    func testManagesFirstResponderGatesAcceptsFR() {
        let l = makeList([row("a")])
        XCTAssertFalse(l.listProbe.acceptsFirstResponder, "default: the list does NOT take first responder (combo keeps its field FR)")
        l.managesFirstResponder = true
        XCTAssertTrue(l.listProbe.acceptsFirstResponder, "opt-in: the list drives nav itself")
    }

    // MARK: - Separator (menu rule — non-interactive, skipped by nav)

    private func separator(_ id: String = "sep") -> ListItem { ListItem(id: id, primary: "", kind: .separator) }

    func testSeparatorBandHeightByDensity() {
        let l = makeList([row("a"), separator(), row("b")])
        XCTAssertEqual(l.listProbe.rowFrames["sep"]?.height, 9, "comfortable separator band = 9")
        l.density = .compact
        XCTAssertEqual(l.listProbe.rowFrames["sep"]?.height, 7, "compact separator band = 7")
    }

    func testSeparatorIsNotSelectableAndSkippedByNav() {
        let l = makeList([row("a"), separator(), row("b")])
        l.selectedID = "sep"
        XCTAssertNil(l.selectedItem, "a separator can't be selected")
        l._moveHighlight(1); XCTAssertEqual(l.listProbe.effectiveHighlightID, "a")
        l._moveHighlight(1); XCTAssertEqual(l.listProbe.effectiveHighlightID, "b", "arrow nav skips the separator")
    }

    // MARK: - Wrap (menu) vs clamp (default)

    func testWrapsHighlightCyclesEnds() {
        let l = makeList([row("a"), row("b"), row("c")])
        l.wrapsHighlight = true
        l._moveHighlight(1); XCTAssertEqual(l.listProbe.effectiveHighlightID, "a")
        l._moveHighlight(-1); XCTAssertEqual(l.listProbe.effectiveHighlightID, "c", "up from the first wraps to the last")
        l._moveHighlight(1); XCTAssertEqual(l.listProbe.effectiveHighlightID, "a", "down from the last wraps to the first")
    }

    // MARK: - Pointer hover drives the shared highlight (menu)

    func testHighlightFollowsHoverSharesHighlightAndKeepsLastOnExit() {
        let l = makeList([row("a"), row("b"), row("c")])   // rows 0..30, 30..60, 60..90
        l.highlightFollowsHover = true
        l._hoverRow(atDocY: 45)
        XCTAssertEqual(l.listProbe.effectiveHighlightID, "b", "hover lights the row under the pointer")
        l._hoverRow(atDocY: nil)
        XCTAssertEqual(l.listProbe.effectiveHighlightID, "b", "the last-hovered row stays lit on exit (native menu)")
        l._hoverRow(atDocY: 15)
        XCTAssertEqual(l.listProbe.effectiveHighlightID, "a", "moving to another row re-lights it")
    }

    func testHoverOverSeparatorKeepsPriorHighlight() {
        let l = makeList([row("a"), separator(), row("b")])   // a 0..30, sep 30..39, b 39..69
        l.highlightFollowsHover = true
        l._hoverRow(atDocY: 15)                                 // a
        l._hoverRow(atDocY: 34)                                 // over the separator
        XCTAssertEqual(l.listProbe.effectiveHighlightID, "a", "a separator is not highlightable; the prior row stays lit")
    }

    // MARK: - Synthetic per-row AX (opt-in `.menuItem` children)

    func testNoPerRowAXByDefault() {
        let l = makeList([row("a"), row("b")])
        XCTAssertTrue(l._axChildren().isEmpty, "default: the list vends no per-row AX (the combo's basic limitation)")
    }

    func testAXVendsMenuItemsForActionableRowsWithFlippedFramesAndPress() {
        // H(28)@0 · a(30)@28 · off(30)@58 · sep(9)@88 · b(30)@97 — total 127.
        let items = [header("H"), row("a"),
                     ListItem(id: "off", primary: "Off", isDisabled: true),
                     separator(), row("b")]
        let l = makeList(items)
        l.vendsRowAXElements = true
        let kids = l._axChildren()
        XCTAssertEqual(kids.compactMap { $0.accessibilityLabel() }, ["A", "B"],
                       "only actionable rows vend an element (header / disabled / separator skipped)")
        XCTAssertEqual(kids.first?.accessibilityRole(), .menuItem, "role is .menuItem")
        // The doc view is flipped (y down) but AX frames are y-up: axY = docHeight − rowRect.maxY.
        let aFrame = kids.first?.accessibilityFrameInParentSpace()
        XCTAssertEqual(aFrame?.height, 30)
        XCTAssertEqual(aFrame?.minY ?? -1, 127 - (28 + 30), accuracy: 0.5, "flip-converted frame")
        // AXPress activates the row.
        var fired: [String] = []
        l.onActivate = { fired.append($0.id) }
        _ = kids.first?.accessibilityPerformPress()
        XCTAssertEqual(fired, ["a"], "AXPress on the element activates its row")
    }

    // MARK: - Content sizing (a host that sizes to the list — a menu)

    func testContentHeightSumsRowHeights() {
        let l = makeList([row("a"), row("b", secondary: "x"), separator()])
        XCTAssertEqual(l.contentHeight, 30 + 46 + 9, "content height sums every row (incl. a separator band)")
    }

    func testFittingWidthGrowsWithTextAndCaps() {
        let wide = makeList([row("short"), ListItem(id: "long", primary: "A considerably longer menu label")])
        let narrow = makeList([row("short")])
        XCTAssertGreaterThan(wide.fittingWidth(maxWidth: 1000), narrow.fittingWidth(maxWidth: 1000),
                             "a longer label widens the fit")
        XCTAssertEqual(wide.fittingWidth(maxWidth: 60), 60, "fitting width is capped at maxWidth")
    }

    // MARK: - Leading image column (the combo's image-less option list)

    func testReservesLeadingImageColumnCollapsesTextInset() {
        // DEFAULT (true): an image-less row still reserves the leading image column,
        // so the text budget starts at textXOrigin = leadingInset(12) + imageBox(24)
        // + gapImageToText(8) = 44 (the facet/wand mixed-icon alignment).
        let reserved = makeList([row("hello")])
        // OFF: the column collapses to leadingInset(12) — the combo's option rows, so
        // text sits flush like the old ComboListView. The fit shrinks by exactly the
        // dropped image column = imageBox(24) + gapImageToText(8) = 32 (comfortable).
        let collapsed = makeList([row("hello")])
        collapsed.reservesLeadingImageColumn = false
        XCTAssertEqual(reserved.fittingWidth() - collapsed.fittingWidth(), 32, accuracy: 0.5,
                       "suppressing the leading image column moves text from textXOrigin(44) to leadingInset(12)")
    }

    // MARK: - Drag layer (state machine + target resolution — headless; the ghost is
    // a live-only child window proven in prism). Rows are comfortable single-line =
    // 30pt: row i spans [30i, 30i+30); a separator band = 9pt.

    func testDragGateOffByDefault() {
        let l = makeList([row("a"), row("b")])
        XCTAssertFalse(l.draggable, "draggable defaults OFF")
        l.beginDrag("a")
        XCTAssertFalse(l.isDragging, "no keyboard lift when draggable is off")
        XCTAssertFalse(l._beginMouseDrag(atDocY: 5), "no mouse drag when draggable is off")
        XCTAssertFalse(l.dragProbe.isDragging)
    }

    func testHeaderIsDraggableSeparatorAndDisabledAreNot() {
        let l = makeList([header("H"), row("a"), separator(),
                          ListItem(id: "off", primary: "Off", isDisabled: true)])
        l.draggable = true
        l.beginDrag("sep"); XCTAssertFalse(l.isDragging, "a separator can't be lifted (no identity)")
        l.beginDrag("off"); XCTAssertFalse(l.isDragging, "a disabled row can't be lifted")
        l.beginDrag("H");   XCTAssertTrue(l.isDragging, "a header CAN be lifted (facet header swap)")
        l.cancelDrag()
        l.beginDrag("a");   XCTAssertTrue(l.isDragging, "a normal row lifts")
        l.cancelDrag(); XCTAssertFalse(l.isDragging)
    }

    func testMouseDragDropOntoCommitsOnDrop() {
        let l = makeList([row("a"), row("b"), row("c")])     // a 0..30, b 30..60, c 60..90
        l.draggable = true; l.dragMode = .dropOnto
        var dropped: (String, DropPlacement)?
        l.onDrop = { ctx, t in dropped = (ctx.id, t.placement) }
        XCTAssertTrue(l._beginMouseDrag(atDocY: 5), "lift row a")
        XCTAssertTrue(l.dragProbe.isDragging)
        XCTAssertFalse(l.dragProbe.isKeyboardDrag, "a mouse drag is not a keyboard lift")
        l._updateMouseDrag(atDocY: 45)                       // over b
        XCTAssertEqual(l.dragProbe.target?.placement, .onto(id: "b"))
        l._endMouseDrag(commit: true)
        XCTAssertFalse(l.isDragging, "the drag ends on release")
        XCTAssertEqual(dropped?.0, "a"); XCTAssertEqual(dropped?.1, .onto(id: "b"))
    }

    func testMouseDragCancelFiresNothing() {
        let l = makeList([row("a"), row("b"), row("c")])
        l.draggable = true; l.dragMode = .dropOnto
        var fired = false; l.onDrop = { _, _ in fired = true }
        XCTAssertTrue(l._beginMouseDrag(atDocY: 5))
        l._updateMouseDrag(atDocY: 45)
        l._endMouseDrag(commit: false)
        XCTAssertFalse(l.isDragging); XCTAssertFalse(fired, "an aborted release must not fire onDrop")
    }

    func testOntoSelfIsRejected() {
        let l = makeList([row("a"), row("b")]); l.draggable = true; l.dragMode = .dropOnto
        XCTAssertNil(l._resolveDropTarget(atDocY: 5, source: "a"), "dropping a onto itself is no target")
        XCTAssertEqual(l._resolveDropTarget(atDocY: 45, source: "a")?.placement, .onto(id: "b"))
    }

    func testReorderBetweenZoneModel() {
        let l = makeList([row("a"), row("b"), row("c"), row("d")])   // 30pt each
        l.draggable = true; l.dragMode = .reorderBetween
        XCTAssertEqual(l._resolveDropTarget(atDocY: 62, source: "a")?.placement, .between(beforeID: "c"),
                       "top half of c → insert before c")
        XCTAssertEqual(l._resolveDropTarget(atDocY: 85, source: "a")?.placement, .between(beforeID: "d"),
                       "bottom half of c → insert before d (after c)")
        XCTAssertEqual(l._resolveDropTarget(atDocY: 115, source: "a")?.placement, .between(beforeID: nil),
                       "bottom half of the last row → the end gap")
    }

    func testBetweenSelfAdjacentNoOpRejected() {
        let l = makeList([row("a"), row("b"), row("c")]); l.draggable = true; l.dragMode = .reorderBetween
        XCTAssertNil(l._resolveDropTarget(atDocY: 32, source: "b"), "the gap immediately above self is a no-op")
        XCTAssertNil(l._resolveDropTarget(atDocY: 58, source: "b"), "the gap immediately below self is a no-op")
        XCTAssertEqual(l._resolveDropTarget(atDocY: 5, source: "b")?.placement, .between(beforeID: "a"),
                       "moving b above a IS a real move")
    }

    func testSeparatorIsNotADropTarget() {
        let l = makeList([row("a"), separator(), row("b")])     // a 0..30, sep 30..39, b 39..69
        l.draggable = true; l.dragMode = .dropOnto
        XCTAssertNil(l._resolveDropTarget(atDocY: 34, source: "a"), "can't drop onto a separator")
        XCTAssertEqual(l._resolveDropTarget(atDocY: 50, source: "a")?.placement, .onto(id: "b"))
    }

    func testValidatorVetoesTarget() {
        let l = makeList([row("a"), row("b"), row("c")]); l.draggable = true; l.dragMode = .dropOnto
        l.dropTargetValidator = { _, target in
            if case .onto(let id) = target.placement { return id != "b" }     // veto onto b
            return true
        }
        XCTAssertNil(l._resolveDropTarget(atDocY: 45, source: "a"), "the validator vetoes onto b")
        XCTAssertEqual(l._resolveDropTarget(atDocY: 75, source: "a")?.placement, .onto(id: "c"), "onto c still allowed")
    }

    func testBothModeZones() {
        let l = makeList([row("a"), row("b"), row("c"), row("d")]); l.draggable = true; l.dragMode = .both
        // c spans 60..90: top quarter <67.5 ⇒ between-before; mid ⇒ onto; bottom quarter >82.5 ⇒ between-after.
        XCTAssertEqual(l._resolveDropTarget(atDocY: 62, source: "a")?.placement, .between(beforeID: "c"), "top quarter ⇒ between before")
        XCTAssertEqual(l._resolveDropTarget(atDocY: 75, source: "a")?.placement, .onto(id: "c"), "middle ⇒ onto")
        XCTAssertEqual(l._resolveDropTarget(atDocY: 88, source: "a")?.placement, .between(beforeID: "d"), "bottom quarter ⇒ between after")
    }

    func testOutOfBoundsResolution() {
        let l = makeList([row("a"), row("b"), row("c")]); l.draggable = true
        l.dragMode = .reorderBetween
        XCTAssertEqual(l._resolveDropTarget(atDocY: -5, source: "c")?.placement, .between(beforeID: "a"), "above the top ⇒ before the first row")
        XCTAssertEqual(l._resolveDropTarget(atDocY: 999, source: "a")?.placement, .between(beforeID: nil), "below the last ⇒ the end gap")
        l.dragMode = .dropOnto
        XCTAssertNil(l._resolveDropTarget(atDocY: -5, source: "a"), ".dropOnto has no out-of-bounds target")
        XCTAssertNil(l._resolveDropTarget(atDocY: 999, source: "a"), ".dropOnto has no out-of-bounds target")
    }

    func testKeyboardLiftAimAndCommit() {
        let l = makeList([row("a"), row("b"), row("c")]); l.draggable = true; l.dragMode = .dropOnto
        var dropped: (String, DropPlacement)?
        l.onDrop = { ctx, t in dropped = (ctx.id, t.placement) }
        l.beginDrag("a")
        XCTAssertTrue(l.isDragging); XCTAssertTrue(l.dragProbe.isKeyboardDrag)
        XCTAssertEqual(l._dragCandidates().count, 2, "onto b, onto c (onto-self rejected)")
        XCTAssertEqual(l.dragProbe.target?.placement, .onto(id: "b"), "seeds at the first candidate")
        l.moveDragTarget(1)
        XCTAssertEqual(l.dragProbe.target?.placement, .onto(id: "c"), "arrow aims to the next candidate")
        l.moveDragTarget(1)
        XCTAssertEqual(l.dragProbe.target?.placement, .onto(id: "c"), "clamps at the last candidate")
        l.commitDrag()
        XCTAssertFalse(l.isDragging)
        XCTAssertEqual(dropped?.0, "a"); XCTAssertEqual(dropped?.1, .onto(id: "c"))
    }

    func testKeyboardCancelFiresNothing() {
        let l = makeList([row("a"), row("b")]); l.draggable = true; l.dragMode = .dropOnto
        var fired = false; l.onDrop = { _, _ in fired = true }
        l.beginDrag("a"); l.moveDragTarget(1)
        l.cancelDrag()
        XCTAssertFalse(l.isDragging); XCTAssertFalse(fired, "cancel must not fire onDrop")
    }

    func testMoveHighlightSuppressedDuringLift() {
        let l = makeList([row("a"), row("b"), row("c")]); l.draggable = true; l.dragMode = .reorderBetween
        l._moveHighlight(1); XCTAssertEqual(l.listProbe.effectiveHighlightID, "a")
        l.beginDrag("a")
        let aim = l.dragProbe.target?.placement
        l._moveHighlight(1)
        XCTAssertEqual(l.listProbe.effectiveHighlightID, "a", "highlight nav is suppressed during a lift (decision e)")
        XCTAssertEqual(l.dragProbe.target?.placement, aim, "moveHighlight doesn't move the drop aim")
        l.cancelDrag()
    }

    func testCandidateCompositionByMode() {
        let l = makeList([row("a"), row("b"), row("c")]); l.draggable = true
        l.beginDrag("a")                                     // a live source for the candidate walk
        l.dragMode = .dropOnto
        XCTAssertEqual(l._dragCandidates().map(\.placement), [.onto(id: "b"), .onto(id: "c")])
        l.dragMode = .reorderBetween
        XCTAssertEqual(l._dragCandidates().map(\.placement), [.between(beforeID: "c"), .between(beforeID: nil)],
                       "before-a (self above) and before-b (self below) are no-ops; before-c and the end gap remain")
        l.dragMode = .both
        XCTAssertEqual(l._dragCandidates().map(\.placement),
                       [.onto(id: "b"), .between(beforeID: "c"), .onto(id: "c"), .between(beforeID: nil)],
                       "interleaved between-then-onto per row, trivial self-targets dropped")
        l.cancelDrag()
    }

    func testTurningOffDraggableCancelsInFlightDrag() {
        let l = makeList([row("a"), row("b")]); l.draggable = true; l.dragMode = .dropOnto
        var fired = false; l.onDrop = { _, _ in fired = true }
        l.beginDrag("a"); XCTAssertTrue(l.isDragging)
        l.draggable = false
        XCTAssertFalse(l.isDragging, "disabling draggable cancels the in-flight drag")
        XCTAssertFalse(fired, "and does not commit it")
    }

    // MARK: - Drag key routing (Space lift/commit · arrows aim · Return/Esc · fall-through)

    /// A synthetic keyDown for the `_handleDragKey` seam (it reads only `keyCode`;
    /// `chars` is non-empty so `NSEvent.keyEvent` succeeds). Mirrors ThemedMenuTests.
    private func keyDown(_ keyCode: UInt16, chars: String = " ") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: 0, context: nil, characters: chars,
                         charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode)!
    }

    func testDragKeyRoutingLiftAimCommitAndFallThrough() {
        let l = makeList([row("a"), row("b"), row("c")]); l.draggable = true; l.dragMode = .dropOnto
        l.managesFirstResponder = true
        // Space with nothing highlighted FALLS THROUGH (not silently swallowed).
        XCTAssertFalse(l._handleDragKey(keyDown(49)), "Space with no highlight falls through to the host")
        XCTAssertFalse(l.isDragging)
        l._moveHighlight(1)                                  // highlight 'a'
        XCTAssertTrue(l._handleDragKey(keyDown(49)), "Space lifts the highlighted row")
        XCTAssertTrue(l.isDragging)
        XCTAssertEqual(l.dragProbe.target?.placement, .onto(id: "b"), "seeds at the first candidate")
        XCTAssertTrue(l._handleDragKey(keyDown(125)), "↓ aims to the next candidate while dragging")
        XCTAssertEqual(l.dragProbe.target?.placement, .onto(id: "c"))
        var dropped: DropPlacement?
        l.onDrop = { _, t in dropped = t.placement }
        XCTAssertTrue(l._handleDragKey(keyDown(49)), "Space commits the in-flight lift")
        XCTAssertFalse(l.isDragging)
        XCTAssertEqual(dropped, .onto(id: "c"))
        // Arrows / Return / Esc FALL THROUGH to the ordinary nav when NOT dragging.
        XCTAssertFalse(l._handleDragKey(keyDown(125)), "↓ falls through to nav when not dragging")
        XCTAssertFalse(l._handleDragKey(keyDown(36)),  "Return falls through when not dragging")
        XCTAssertFalse(l._handleDragKey(keyDown(53)),  "Esc falls through when not dragging")
    }

    func testDragKeyEscCancels() {
        let l = makeList([row("a"), row("b")]); l.draggable = true; l.dragMode = .dropOnto
        var fired = false; l.onDrop = { _, _ in fired = true }
        l._moveHighlight(1); _ = l._handleDragKey(keyDown(49))   // lift 'a'
        XCTAssertTrue(l.isDragging)
        XCTAssertTrue(l._handleDragKey(keyDown(53)), "Esc cancels the in-flight lift")
        XCTAssertFalse(l.isDragging); XCTAssertFalse(fired, "Esc cancel fires no onDrop")
    }

    func testDragKeysInertWhenNotDraggable() {
        let l = makeList([row("a"), row("b")]); l.managesFirstResponder = true
        XCTAssertFalse(l._handleDragKey(keyDown(49)),  "Space falls through when not draggable")
        XCTAssertFalse(l._handleDragKey(keyDown(125)), "↓ falls through when not draggable")
        XCTAssertFalse(l.isDragging)
    }
}
