import XCTest
@testable import ListCore

final class ListSelectionTests: XCTestCase {
    // Treat "a", "b" as present+selectable; "x" as absent/non-selectable.
    private func sel(_ id: String) -> Bool { id == "a" || id == "b" }

    func testKeepsSelectableProposed() {
        let r = resolveSelection(proposed: "a", current: nil, isSelectable: sel)
        XCTAssertEqual(r.resolved, "a"); XCTAssertTrue(r.didChange)
    }
    func testRejectsNonSelectable() {
        let r = resolveSelection(proposed: "x", current: nil, isSelectable: sel)
        XCTAssertNil(r.resolved); XCTAssertFalse(r.didChange)
    }
    func testNilProposedClears() {
        let r = resolveSelection(proposed: nil, current: "a", isSelectable: sel)
        XCTAssertNil(r.resolved); XCTAssertTrue(r.didChange)
    }
    func testNoChangeWhenSame() {
        let r = resolveSelection(proposed: "a", current: "a", isSelectable: sel)
        XCTAssertEqual(r.resolved, "a"); XCTAssertFalse(r.didChange)
    }
}
