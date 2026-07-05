import XCTest
import ListCore          // ListRow derived-flag members accessed via `.asRow`
@testable import ThemeKitUI
// (The old "NOT import ThemeKit" ambiguity guard is moot since the M5 retire —
// `ListItem` and the accessories all live in ThemeKitUI now.)

final class ListItemProjectionTests: XCTestCase {
    private func item(_ id: String, kind: ListItem<String>.Kind = .row,
                      disabled: Bool = false, indent: Int = 0) -> ListItem<String> {
        ListItem(id: id, primary: id, kind: kind, isDisabled: disabled, indentLevel: indent)
    }

    func testAsRowMapsKindDisabledIndent() {
        let header = item("h", kind: .sectionHeader(subtitle: "2", collapsed: true), indent: 1)
        XCTAssertEqual(header.asRow.id, "h")
        XCTAssertTrue(header.asRow.isHeader)
        XCTAssertEqual(header.asRow.headerCollapsed, true)
        XCTAssertTrue(header.asRow.isCollapsibleHeader)
        XCTAssertEqual(header.asRow.indentLevel, 1)

        let disabledRow = item("d", disabled: true)
        XCTAssertFalse(disabledRow.asRow.isSelectable)      // disabled ⇒ not selectable

        let sep = item("s", kind: .separator)
        XCTAssertTrue(sep.asRow.isSeparator)
        XCTAssertFalse(sep.asRow.isSelectable)
    }

    func testSelectableIDsFiltersHeadersSeparatorsDisabled() {
        let items = [item("h", kind: .sectionHeader()), item("a"),
                     item("b", disabled: true), item("s", kind: .separator), item("c")]
        XCTAssertEqual(ListItem.selectableIDs(items), ["a", "c"])
    }

    func testVisibleRowsDropsCollapsedBodies() {
        // a collapsed header keeps the header, drops its body until the next header
        let items = [item("h", kind: .sectionHeader(collapsed: true)), item("a"), item("b"),
                     item("h2", kind: .sectionHeader()), item("c")]
        let visible = ListItem.visibleRows(items, collapsed: ["h"]).map(\.id)
        XCTAssertEqual(visible, ["h", "h2", "c"])
    }
}
