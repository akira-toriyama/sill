import XCTest
@testable import ListCore

final class MultiSelectionTests: XCTestCase {
    let sel = ["a", "b", "c", "d"]   // ordered selectable ids (headers/separators pre-filtered by caller)

    func testPlainClickReplaces() {
        let r = resolveClick(id: "c", current: ["a", "b"], anchor: "a", mods: [], selectable: sel)
        XCTAssertEqual(r.selection, ["c"]); XCTAssertEqual(r.anchor, "c")
    }
    func testCommandTogglesAndMovesAnchor() {
        let add = resolveClick(id: "c", current: ["a"], anchor: "a", mods: .command, selectable: sel)
        XCTAssertEqual(add.selection, ["a", "c"]); XCTAssertEqual(add.anchor, "c")
        let remove = resolveClick(id: "a", current: ["a", "c"], anchor: "c", mods: .command, selectable: sel)
        XCTAssertEqual(remove.selection, ["c"], "cmd-click an already-selected id removes it")
    }
    func testShiftSelectsAnchorRangeInclusive() {
        let r = resolveClick(id: "d", current: ["b"], anchor: "b", mods: .shift, selectable: sel)
        XCTAssertEqual(r.selection, ["b", "c", "d"]); XCTAssertEqual(r.anchor, "b", "shift keeps the anchor")
    }
    func testShiftWithNoAnchorFallsBackToSingle() {
        let r = resolveClick(id: "c", current: [], anchor: nil, mods: .shift, selectable: sel)
        XCTAssertEqual(r.selection, ["c"]); XCTAssertEqual(r.anchor, "c")
    }
    func testRangeIDsOrderIndependent() {
        XCTAssertEqual(rangeIDs(from: "d", to: "b", in: sel), ["b", "c", "d"])
        XCTAssertEqual(rangeIDs(from: "b", to: "b", in: sel), ["b"])
        XCTAssertEqual(rangeIDs(from: "x", to: "b", in: sel), [], "an unknown endpoint ⇒ empty")
    }
    func testExtendByKeyGrowsFromAnchor() {
        let r = extendByKey(current: ["b"], anchor: "b", focus: "b", delta: 1,
                            selectable: sel, shiftHeld: true, wraps: false)
        XCTAssertEqual(r.focus, "c"); XCTAssertEqual(r.selection, ["b", "c"]); XCTAssertEqual(r.anchor, "b")
    }
    func testExtendByKeyNoShiftMovesFocusAndCollapsesSelection() {
        let r = extendByKey(current: ["b", "c"], anchor: "b", focus: "c", delta: 1,
                            selectable: sel, shiftHeld: false, wraps: false)
        XCTAssertEqual(r.focus, "d"); XCTAssertEqual(r.selection, ["d"]); XCTAssertEqual(r.anchor, "d")
    }
    func testSelectAll() { XCTAssertEqual(selectAll(selectable: sel), Set(sel)) }
}
