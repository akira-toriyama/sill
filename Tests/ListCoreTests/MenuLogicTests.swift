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
}
