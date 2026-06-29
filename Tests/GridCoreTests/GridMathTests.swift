import XCTest
@testable import GridCore

final class GridMathTests: XCTestCase {

    // gridColumns — adaptive count
    func testColumnsBasic() {
        // 3*100 + 2*10 = 320 fits in 320; a 4th needs 430 > 320.
        XCTAssertEqual(gridColumns(availableWidth: 320, minCellWidth: 100, gap: 10, max: 99), 3)
    }
    func testColumnsClampedToMax() {
        XCTAssertEqual(gridColumns(availableWidth: 10_000, minCellWidth: 100, gap: 10, max: 5), 5)
    }
    func testColumnsNeverZero() {
        XCTAssertEqual(gridColumns(availableWidth: 10, minCellWidth: 100, gap: 10, max: 5), 1)
    }

    // gridCellSize — aspect-fit
    func testCellWidthFromColumns() {
        // (300 - 2*10) / 3 = 93.333…
        let s = gridCellSize(availableWidth: 300, columns: 3, gap: 10, aspectRatio: nil)
        XCTAssertEqual(s.width, 280.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(s.height, 280.0 / 3.0, accuracy: 0.001)   // nil ⇒ square
    }
    func testCellHeightFromAspect() {
        // aspectRatio = width/height = 2 ⇒ height = width/2
        let s = gridCellSize(availableWidth: 210, columns: 2, gap: 10, aspectRatio: 2)
        XCTAssertEqual(s.width, 100, accuracy: 0.001)
        XCTAssertEqual(s.height, 50, accuracy: 0.001)
    }

    // nextGridIndex — 2D nav over a 3-col grid of 7 items (rows: [0,1,2][3,4,5][6])
    func testMoveRight() {
        XCTAssertEqual(nextGridIndex(from: 0, dx: 1, dy: 0, count: 7, columns: 3, wrap: false), 1)
    }
    func testMoveDown() {
        XCTAssertEqual(nextGridIndex(from: 1, dx: 0, dy: 1, count: 7, columns: 3, wrap: false), 4)
    }
    func testMoveDownIntoRaggedLastRowSnaps() {
        // from index 4 (row1,col1) down → row2,col1 = index 7 which is past count(7) → snap to 6
        XCTAssertEqual(nextGridIndex(from: 4, dx: 0, dy: 1, count: 7, columns: 3, wrap: false), 6)
    }
    func testNoWrapClampsAtEdge() {
        XCTAssertEqual(nextGridIndex(from: 2, dx: 1, dy: 0, count: 7, columns: 3, wrap: false), 2)
    }
    func testWrapHorizontal() {
        XCTAssertEqual(nextGridIndex(from: 2, dx: 1, dy: 0, count: 7, columns: 3, wrap: true), 0)
    }

    // reconcileGridSelection — drop vanished ids
    func testReconcileDropsMissing() {
        XCTAssertEqual(reconcileGridSelection(Set(["a", "b", "z"]), existing: Set(["a", "b", "c"])),
                       Set(["a", "b"]))
    }
}
