import XCTest
@testable import ListCore

final class HighlightTests: XCTestCase {
    let sel = [0, 2, 3]   // index 1 is non-selectable (header/disabled)

    func testEmptyReturnsNil() {
        XCTAssertNil(nextHighlight(current: nil, delta: 1, selectableIndices: [], wraps: true))
    }
    func testNoCurrentForwardPicksFirst() {
        XCTAssertEqual(nextHighlight(current: nil, delta: 1, selectableIndices: sel, wraps: false), 0)
    }
    func testNoCurrentBackwardPicksLast() {
        XCTAssertEqual(nextHighlight(current: nil, delta: -1, selectableIndices: sel, wraps: false), 3)
    }
    func testForwardSkipsNonSelectable() {
        XCTAssertEqual(nextHighlight(current: 0, delta: 1, selectableIndices: sel, wraps: false), 2)
    }
    func testClampAtEnd() {
        XCTAssertEqual(nextHighlight(current: 3, delta: 1, selectableIndices: sel, wraps: false), 3)
    }
    func testWrapPastEnd() {
        XCTAssertEqual(nextHighlight(current: 3, delta: 1, selectableIndices: sel, wraps: true), 0)
    }
    func testWrapPastStart() {
        XCTAssertEqual(nextHighlight(current: 0, delta: -1, selectableIndices: sel, wraps: true), 3)
    }
}
