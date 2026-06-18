// ThemeKit / ThemedScroller tests — pure, headless-safe (no rendering). The
// scroller's contract is (a) opt into overlay-style custom drawing so AppKit
// keeps the subclass under `.overlay`, and (b) hold a host-assigned knob / track
// NSColor. The PAINTED appearance (themed knob vs macOS grey) is proven LIVE in
// prism, not asserted here (the list/menu/combo precedent).

import XCTest
import AppKit
@testable import ThemeKit

@MainActor
final class ThemedScrollerTests: XCTestCase {

    private func scroller() -> ThemedScroller {
        ThemedScroller(frame: NSRect(x: 0, y: 0, width: 16, height: 100))
    }

    private func srgb(_ c: NSColor) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
        guard let s = c.usingColorSpace(.sRGB) else { return nil }
        return (s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent)
    }

    /// REQUIRED: without it an `.overlay` scroll view drops the custom subclass
    /// back to a stock system scroller and the themed knob never draws.
    func testIsCompatibleWithOverlayScrollers() {
        XCTAssertTrue(ThemedScroller.isCompatibleWithOverlayScrollers)
    }

    func testKnobColorHoldsAssignedColor() {
        let s = scroller()
        s.knobColor = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        guard let c = srgb(s.knobColor) else { return XCTFail("knobColor unconvertible") }
        XCTAssertEqual(c.0, 0.2, accuracy: 0.001)
        XCTAssertEqual(c.1, 0.4, accuracy: 0.001)
        XCTAssertEqual(c.2, 0.6, accuracy: 0.001)
        XCTAssertEqual(c.3, 1.0, accuracy: 0.001)
    }

    func testTrackColorDefaultsNilThenHoldsAssignedColor() {
        let s = scroller()
        XCTAssertNil(s.trackColor, "transparent track by default (overlay convention)")
        s.trackColor = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 0.5)
        XCTAssertNotNil(s.trackColor)
    }
}
