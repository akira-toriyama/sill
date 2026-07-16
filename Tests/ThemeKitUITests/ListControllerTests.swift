import XCTest
import AppKit
import Palette
import PaletteKit
import ListCore
@testable import ThemeKitUI

@MainActor
final class ListControllerTests: XCTestCase {
    private func opt(_ id: String) -> ListItem<String> { ListItem(id: id, primary: id) }
    private func theme(_ name: String = "terminal") -> ResolvedPalette { resolve(paletteFor(name)) }

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

    // MARK: - Measurement (M4 — a popup host sizes its panel + anchors a submenu)

    func testContentHeightSumsRowKinds() {
        let c = ListController<String>()          // .comfortable: header1 28, singleRow 30, separatorBand 9
        c.items = [ListItem(id: "H", primary: "Head", kind: .sectionHeader()),
                   opt("a"), ListItem(id: "s", primary: "", kind: .separator), opt("b")]
        XCTAssertEqual(c.contentHeight(), 28 + 30 + 9 + 30, accuracy: 0.5)
    }

    func testContentHeightEmptyIsOneRowAndCompactShrinks() {
        let c = ListController<String>()
        c.items = []
        XCTAssertEqual(c.contentHeight(), 30, accuracy: 0.5, "empty keeps one synthetic comfortable row")
        c.items = [opt("a"), opt("b")]
        c.style.density = .compact                // singleRow 26
        XCTAssertEqual(c.contentHeight(), 52, accuracy: 0.5)
    }

    func testContentHeightCoversSubtitledHeaderAndTwoLineRow() {
        let c = ListController<String>()          // .comfortable: header2 40, twoLineRow 46
        c.items = [ListItem(id: "H", primary: "Head", kind: .sectionHeader(subtitle: "sub")),
                   ListItem(id: "a", primary: "a", secondary: "detail")]
        XCTAssertEqual(c.contentHeight(), 40 + 46, accuracy: 0.5)
        c.style.density = .compact                // header2 NOT shrunk in compact; twoLineRow 40
        XCTAssertEqual(c.contentHeight(), 40 + 40, accuracy: 0.5)
    }

    func testFittingWidthGrowsWithLabelAndClampsToMax() {
        let c = ListController<String>()
        c.style.reservesLeadingImageColumn = false
        let pal = theme()
        c.items = [opt("Hi")]
        let narrow = c.fittingWidth(palette: pal)
        c.items = [opt("A much much much longer menu label")]
        let wide = c.fittingWidth(palette: pal)
        XCTAssertGreaterThan(wide, narrow, "a longer label needs more width")
        let clamped = c.fittingWidth(maxWidth: 40, palette: pal)
        XCTAssertLessThanOrEqual(clamped, 40, "capped at maxWidth (past the cap ellipsizes)")
    }

    func testFittingWidthAccountsForTrailingShortcut() {
        let c = ListController<String>()
        let pal = theme()
        c.items = [ListItem(id: "x", primary: "Save")]
        let plain = c.fittingWidth(palette: pal)
        c.items = [ListItem(id: "x", primary: "Save", trailing: .shortcut("⌘S"))]
        let withShortcut = c.fittingWidth(palette: pal)
        XCTAssertGreaterThan(withShortcut, plain, "a trailing lozenge widens the row")
    }

    func testRowRectOnScreenNilWithoutHost() {
        let c = ListController<String>()
        c.items = [opt("a")]
        XCTAssertNil(c.rowRectOnScreen("a"), "no hosting view / window ⇒ no screen rect")
    }

    func testRowRectOnScreenPureLayoutStacksRows() {
        let c = ListController<String>()
        c.items = [opt("a"), opt("b"), opt("c")]           // comfortable singleRow 30
        let pal = theme()
        let host = HostingListView(controller: c,
                                   rootView: HostedThemedList(controller: c, style: c.style, palette: pal))
        let win = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 200, height: 200),
                           styleMask: [.borderless], backing: .buffered, defer: true)
        win.contentView?.addSubview(host)
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 120)
        guard let ra = c.rowRectOnScreen("a"), let rb = c.rowRectOnScreen("b") else {
            return XCTFail("a hosted, windowed row resolves a screen rect from the pure layout")
        }
        XCTAssertEqual(ra.width, 200, accuracy: 0.5, "the row spans the hosting view width")
        XCTAssertEqual(ra.height, 30, accuracy: 0.5, "one comfortable row tall")
        XCTAssertEqual(abs(ra.minY - rb.minY), 30, accuracy: 0.5, "adjacent rows sit one row-height apart")
        XCTAssertNil(c.rowRectOnScreen("nope"), "an unknown id has no rect")
    }
}
