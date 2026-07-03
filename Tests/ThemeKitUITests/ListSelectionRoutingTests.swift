import XCTest
import ListCore          // SelectMods
@testable import ThemeKitUI

/// Pins that ThemedListView's selection routes through the pure ListCore resolvers
/// (so the M1 green net actually protects the shipped selection behavior).
final class ListSelectionRoutingTests: XCTestCase {
    func testSingleClickReplacesSelection() {
        let r = ThemedListSelect.click(id: "b", current: ["a"], anchor: "a",
                                       mods: [], selectable: ["a", "b", "c"])
        XCTAssertEqual(r.selection, ["b"])
        XCTAssertEqual(r.anchor, "b")
    }

    func testNonSelectableTapIsNoOp() {
        let r = ThemedListSelect.click(id: "h", current: ["a"], anchor: "a",
                                       mods: [], selectable: ["a", "b"])   // "h" not selectable
        XCTAssertEqual(r.selection, ["a"])
        XCTAssertEqual(r.anchor, "a")
    }
}
