import XCTest
@testable import ListCore

final class MenuLogicTests: XCTestCase {
    func testArrows() {
        XCTAssertEqual(menuKeyIntent(keyCode: 125), .moveDown)
        XCTAssertEqual(menuKeyIntent(keyCode: 126), .moveUp)
        XCTAssertEqual(menuKeyIntent(keyCode: 124), .openSubmenu)
        XCTAssertEqual(menuKeyIntent(keyCode: 123), .closeLevel)
    }
    func testActivateKeys() {
        for k: UInt16 in [36, 76, 49] { XCTAssertEqual(menuKeyIntent(keyCode: k), .activate) }
    }
    func testEscTabDefault() {
        XCTAssertEqual(menuKeyIntent(keyCode: 53), .escapeLevel)
        XCTAssertEqual(menuKeyIntent(keyCode: 48), .dismissTab)
        XCTAssertEqual(menuKeyIntent(keyCode: 99), .passThrough)
    }

    // MARK: - Horizontal (menu-bar) orientation — the axes flip

    func testHorizontalArrowsFlipAxes() {
        // ←→ move ALONG the bar (prev/next); ↓ opens the child BELOW.
        XCTAssertEqual(menuKeyIntent(keyCode: 124, orientation: .horizontal), .moveDown, "→ = next item")
        XCTAssertEqual(menuKeyIntent(keyCode: 123, orientation: .horizontal), .moveUp,   "← = prev item")
        XCTAssertEqual(menuKeyIntent(keyCode: 125, orientation: .horizontal), .openSubmenu, "↓ opens below")
    }
    func testHorizontalUpIsInert() {
        // ↑ has no meaning on a top bar (no parent level) → passes through (IME/host safe).
        XCTAssertEqual(menuKeyIntent(keyCode: 126, orientation: .horizontal), .passThrough)
    }
    func testHorizontalActivateEscTabUnchanged() {
        for k: UInt16 in [36, 76, 49] { XCTAssertEqual(menuKeyIntent(keyCode: k, orientation: .horizontal), .activate) }
        XCTAssertEqual(menuKeyIntent(keyCode: 53, orientation: .horizontal), .escapeLevel)
        XCTAssertEqual(menuKeyIntent(keyCode: 48, orientation: .horizontal), .dismissTab)
        XCTAssertEqual(menuKeyIntent(keyCode: 99, orientation: .horizontal), .passThrough)
    }
    func testVerticalOrientationMatchesDefault() {
        for k: UInt16 in [125, 126, 124, 123, 36, 76, 49, 53, 48, 99] {
            XCTAssertEqual(menuKeyIntent(keyCode: k), menuKeyIntent(keyCode: k, orientation: .vertical),
                           "the no-arg overload is exactly the .vertical mapping")
        }
    }
}
