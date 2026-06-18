// ThemeKit / ThemedList tests — DETERMINISTIC in headless CI (no Xcode locally →
// these first compile + run in CI). The list is driven via the public config +
// `previewHighlight`/`previewSelection` + the pure `stickyHeader`/`_moveHighlight`
// seams, and read through the DEBUG `listProbe`; no synthetic mouse events, no
// live window (the layout cache + role resolvers are pure of the rendered pixels).
// The selection / hover / solidAccent APPEARANCE is proven LIVE in still, not
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
}
