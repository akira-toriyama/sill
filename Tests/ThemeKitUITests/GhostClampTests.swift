// ThemeKitUI / drag-ghost x-clamp PURE tests — deterministic, no window. The
// ghost is an in-bounds overlay clipped at the scroll viewport, so its centre
// x must keep the card inside the content width; the placement itself is
// proven LIVE (facet tree DnD), not here.

import XCTest
@testable import ThemeKitUI

final class GhostClampTests: XCTestCase {

    func test_insideBand_passesThrough() {
        // content 1000, ghost 976 ⇒ band [488, 512]
        XCTAssertEqual(ghostClampedX(500, ghostWidth: 976, contentWidth: 1000), 500)
        XCTAssertEqual(ghostClampedX(488, ghostWidth: 976, contentWidth: 1000), 488)
        XCTAssertEqual(ghostClampedX(512, ghostWidth: 976, contentWidth: 1000), 512)
    }

    func test_leftOverflow_clampsToHalfWidth() {
        XCTAssertEqual(ghostClampedX(200, ghostWidth: 976, contentWidth: 1000), 488)
        XCTAssertEqual(ghostClampedX(-40, ghostWidth: 976, contentWidth: 1000), 488)
    }

    func test_rightOverflow_clampsToContentMinusHalfWidth() {
        XCTAssertEqual(ghostClampedX(900, ghostWidth: 976, contentWidth: 1000), 512)
        XCTAssertEqual(ghostClampedX(1040, ghostWidth: 976, contentWidth: 1000), 512)
    }

    func test_ghostWiderThanContent_pinsToHalfWidth() {
        // The 120pt width floor can exceed a very narrow list; the lower bound
        // wins so the card pins (left edge flush) instead of oscillating.
        XCTAssertEqual(ghostClampedX(10, ghostWidth: 120, contentWidth: 100), 60)
        XCTAssertEqual(ghostClampedX(95, ghostWidth: 120, contentWidth: 100), 60)
    }
}
