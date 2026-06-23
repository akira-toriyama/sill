import XCTest
@testable import ListCore

final class SectionCollapseTests: XCTestCase {
    func rows() -> [ListRow<String>] {[
        ListRow(id: "A", kind: .sectionHeader(collapsed: false)),
        ListRow(id: "a1"), ListRow(id: "a2"),
        ListRow(id: "B", kind: .sectionHeader(collapsed: false)),
        ListRow(id: "b1"),
    ]}
    func testToggleAddsAndRemoves() {
        XCTAssertEqual(toggleSection("A", in: []), ["A"])
        XCTAssertEqual(toggleSection("A", in: ["A"]), [])
    }
    func testFlattenDropsCollapsedSectionBodyKeepingItsHeader() {
        let visible = flattenVisible(rows: rows(), collapsed: ["A"]).map(\.id)
        XCTAssertEqual(visible, ["A", "B", "b1"], "A's header stays; a1/a2 hidden; B intact")
    }
    func testFlattenAllExpandedIsIdentity() {
        XCTAssertEqual(flattenVisible(rows: rows(), collapsed: []).map(\.id), ["A", "a1", "a2", "B", "b1"])
    }
    func testCollapsingBothSectionsLeavesHeadersOnly() {
        XCTAssertEqual(flattenVisible(rows: rows(), collapsed: ["A", "B"]).map(\.id), ["A", "B"])
    }
}
