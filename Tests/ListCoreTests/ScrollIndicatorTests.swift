// ListCore / ScrollIndicator tests — the pure knob geometry behind the themed
// overlay scroll indicator (t-8649). One axis at a time: nil when the content
// fits, proportional length floored at `minLength` and capped at the track,
// linear offset over the track's spare room, clamped against overscroll so a
// rubber-band never pushes the pill out of the viewport.

import XCTest
import CoreGraphics
@testable import ListCore

final class ScrollIndicatorTests: XCTestCase {

    // MARK: nil — nothing to indicate

    func testContentThatFitsProducesNoKnob() {
        XCTAssertNil(scrollKnob(content: 100, viewport: 200, offset: 0))
        XCTAssertNil(scrollKnob(content: 200, viewport: 200, offset: 0),
                     "an exact fit does not overflow")
    }

    func testDegenerateViewportProducesNoKnob() {
        XCTAssertNil(scrollKnob(content: 100, viewport: 0, offset: 0))
        XCTAssertNil(scrollKnob(content: 100, viewport: -10, offset: 0))
        XCTAssertNil(scrollKnob(content: 100, viewport: 4, offset: 0, endInset: 3),
                     "a viewport thinner than its two end insets has no track")
    }

    // MARK: length

    func testLengthIsTheVisibleFractionOfTheTrack() {
        // viewport 200, insets 3 → track 194; half the content visible → 97.
        let k = scrollKnob(content: 400, viewport: 200, offset: 0)
        XCTAssertEqual(k?.length ?? 0, 97, accuracy: 0.001)
    }

    func testLengthFloorsAtMinLength() {
        let k = scrollKnob(content: 100_000, viewport: 200, offset: 0)
        XCTAssertEqual(k?.length, 20, "a huge document still shows a grabbable pill")
    }

    func testLengthNeverExceedsTheTrack() {
        // minLength larger than the track: the cap wins.
        let k = scrollKnob(content: 30, viewport: 20, offset: 0, minLength: 50, endInset: 3)
        XCTAssertEqual(k?.length ?? 0, 14, accuracy: 0.001)
    }

    // MARK: offset

    func testEndpointsMapToTheTrackEnds() {
        let top = scrollKnob(content: 400, viewport: 200, offset: 0)
        XCTAssertEqual(top?.offset ?? -1, 3, accuracy: 0.001, "at rest the pill starts at endInset")
        let bottom = scrollKnob(content: 400, viewport: 200, offset: 200)
        // endInset + (track − length) = 3 + (194 − 97) = 100 → pill ends at 197 = viewport − endInset.
        XCTAssertEqual(bottom?.offset ?? -1, 100, accuracy: 0.001)
    }

    func testMidScrollMapsLinearly() {
        let k = scrollKnob(content: 400, viewport: 200, offset: 100)
        XCTAssertEqual(k?.offset ?? -1, 3 + (194 - 97) / 2, accuracy: 0.001)
    }

    func testOverscrollClampsToTheEnds() {
        let above = scrollKnob(content: 400, viewport: 200, offset: -40)
        XCTAssertEqual(above?.offset ?? -1, 3, accuracy: 0.001,
                       "a rubber-band above the top parks the pill at the top")
        let below = scrollKnob(content: 400, viewport: 200, offset: 500)
        XCTAssertEqual(below?.offset ?? -1, 100, accuracy: 0.001,
                       "a rubber-band past the bottom parks the pill at the bottom")
    }
}
