import XCTest
import ListCore
@testable import ThemeKitUI

@MainActor
final class ListControllerTests: XCTestCase {
    private func opt(_ id: String) -> ListItem<String> { ListItem(id: id, primary: id) }

    func testMoveHighlightWrapsAndSkipsHeaders() {
        let c = ListController<String>()
        c.style.wrapsHighlight = true
        c.items = [ListItem(id: "H", primary: "Head", kind: .sectionHeader()),
                   opt("a"), opt("b")]
        c.moveHighlight(1)                    // no current, delta>0 → first selectable
        XCTAssertEqual(c.highlight, "a")
        c.moveHighlight(1)
        XCTAssertEqual(c.highlight, "b")
        c.moveHighlight(1)                    // wraps past the header back to "a"
        XCTAssertEqual(c.highlight, "a")
    }

    func testActivateHighlightFiresOnActivate() {
        let c = ListController<String>()
        c.items = [opt("a"), opt("b")]
        var fired: String?
        c.onActivate = { fired = $0 }
        c.highlight = "b"
        c.activateHighlight()
        XCTAssertEqual(fired, "b")
    }

    func testEmptyActionRowActivates() {
        let c = ListController<String>()
        c.items = []
        c.query = "xyz"
        c.emptyActionRow = { q in "Create \(q)" }
        XCTAssertTrue(c.isActionRowActive)
        var firedQuery: String?
        c.onEmptyAction = { firedQuery = $0 }
        c.activateHighlight()                 // no highlight, but the action row fires
        XCTAssertEqual(firedQuery, "xyz")
    }

    func testClearHighlightAndReadBack() {
        let c = ListController<String>()
        c.items = [opt("a")]
        c.highlight = "a"
        XCTAssertEqual(c.highlightedID, "a")
        c.clearHighlight()
        XCTAssertNil(c.highlight)
        XCTAssertNil(c.highlightedID)
    }
}
