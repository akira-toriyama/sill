import XCTest
@testable import ThemeKitUI

/// Pins the fidelity constants so a later "cleanup" can't silently drift the
/// AppKit-parity metrics the SwiftUI renderer reproduces 1:1.
final class ListStyleMetricsTests: XCTestCase {
    func testComfortableMetrics() {
        let m = ListMetrics.forDensity(.comfortable)
        XCTAssertEqual(m.singleRow, 30);    XCTAssertEqual(m.twoLineRow, 46)
        XCTAssertEqual(m.header1, 28);      XCTAssertEqual(m.header2, 40)
        XCTAssertEqual(m.leadingInset, 12); XCTAssertEqual(m.imageBox, 24)
        XCTAssertEqual(m.iconGlyph, 18);    XCTAssertEqual(m.indentStep, 16)
        XCTAssertEqual(m.separatorBand, 9)
        XCTAssertEqual(m.textXOrigin, 44)          // 12 + 24 + 8
        XCTAssertEqual(m.disclosureGutter, 16)     // 11 + 5
    }

    func testCompactMetrics() {
        let m = ListMetrics.forDensity(.compact)
        XCTAssertEqual(m.singleRow, 26);    XCTAssertEqual(m.twoLineRow, 40)
        XCTAssertEqual(m.header1, 24);      XCTAssertEqual(m.header2, 40)   // header2 NOT shrunk
        XCTAssertEqual(m.leadingInset, 10); XCTAssertEqual(m.imageBox, 20)
        XCTAssertEqual(m.indentStep, 14);   XCTAssertEqual(m.separatorBand, 7)
        XCTAssertEqual(m.textXOrigin, 36)          // 10 + 20 + 6
        XCTAssertEqual(m.disclosureGutter, 15)     // 10 + 5
    }

    func testDefaultStyle() {
        let s = ListStyle()
        XCTAssertEqual(s.density, .comfortable)
        XCTAssertEqual(s.selectionMode, .single)
        XCTAssertFalse(s.draggable)
        XCTAssertTrue(s.reservesLeadingImageColumn)
        XCTAssertEqual(s.backgroundAlpha, 1)
    }
}
