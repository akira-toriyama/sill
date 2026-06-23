import XCTest
@testable import ListCore
#if canImport(CoreGraphics)
import CoreGraphics

final class StickyHeaderTests: XCTestCase {
    // headers at indices 0 and 3; A: y0 h40, then rows, B: y110 h40.
    let headerIndices = [0, 3]
    let yOffsets: [CGFloat] = [0, 40, 75, 110]
    let heights: [CGFloat] = [40, 35, 35, 40]

    func testPinAndHandoff() {
        XCTAssertEqual(stickyHeader(atVisibleTop: 0, headerIndices: headerIndices, yOffsets: yOffsets, heights: heights)?.index, 0)
        let pushed = stickyHeader(atVisibleTop: 75, headerIndices: headerIndices, yOffsets: yOffsets, heights: heights)
        XCTAssertEqual(pushed?.index, 0, "A is still active until B's top reaches it")
        XCTAssertEqual(pushed?.drawY, 110 - 40, "B (top 110) pushes A up: drawY = nextTop - headerHeight")
        XCTAssertEqual(stickyHeader(atVisibleTop: 110, headerIndices: headerIndices, yOffsets: yOffsets, heights: heights)?.index, 3, "past B's top, B takes over")
    }
    func testNoneAbove() {
        XCTAssertNil(stickyHeader(atVisibleTop: -5, headerIndices: headerIndices, yOffsets: yOffsets, heights: heights))
    }
}
#endif
