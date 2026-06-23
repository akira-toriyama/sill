import XCTest
@testable import ListCore

final class ListRowTests: XCTestCase {
    func testDerivedFlags() {
        let row = ListRow(id: "r", kind: .row)
        XCTAssertTrue(row.isSelectable)
        XCTAssertFalse(row.isHeader); XCTAssertFalse(row.isSeparator)

        let sep = ListRow(id: "s", kind: .separator)
        XCTAssertTrue(sep.isSeparator); XCTAssertFalse(sep.isSelectable)

        let plainHeader = ListRow(id: "h", kind: .sectionHeader(subtitle: "sub", collapsed: nil))
        XCTAssertTrue(plainHeader.isHeader)
        XCTAssertEqual(plainHeader.headerSubtitle, "sub")
        XCTAssertNil(plainHeader.headerCollapsed)
        XCTAssertFalse(plainHeader.isCollapsibleHeader, "collapsed: nil ⇒ not togglable")
        XCTAssertFalse(plainHeader.isSelectable, "a header is never selectable")

        let collapsible = ListRow(id: "h2", kind: .sectionHeader(collapsed: false))
        XCTAssertTrue(collapsible.isCollapsibleHeader)
        XCTAssertEqual(collapsible.headerCollapsed, false)

        let disabledRow = ListRow(id: "d", kind: .row, isDisabled: true)
        XCTAssertFalse(disabledRow.isSelectable, "disabled ⇒ not selectable")
        let disabledHeader = ListRow(id: "dh", kind: .sectionHeader(collapsed: true), isDisabled: true)
        XCTAssertFalse(disabledHeader.isCollapsibleHeader, "disabled ⇒ not togglable")
    }
}
