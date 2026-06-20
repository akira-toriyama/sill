// SplatterShape tests — the ink-splat decal atom (wand DecalManager port).
//
// The geometry is deterministic in the seed, so a fixed seed gives a fixed
// shape (assert reproducibility + ranges). The alpha curve is the only
// time-varying part; its boundaries use accuracy tolerances (0.66 hold
// fraction is not binary-exact) — never an exact-equality float boundary
// (the #6 CI-only lesson). swift test runs on CI only (CLT has no XCTest).

import XCTest
import AppKit
@testable import Palette
@testable import Effects

@MainActor
final class SplatterTests: XCTestCase {

    // MARK: - Deterministic geometry

    func testSameSeedSameShape() {
        let a = rollSplatter(at: (x: 0, y: 0), size: 100, colors: [0x11, 0x22],
                             seed: 42, now: 0)
        let b = rollSplatter(at: (x: 0, y: 0), size: 100, colors: [0x11, 0x22],
                             seed: 42, now: 0)
        XCTAssertEqual(a.units.count, b.units.count)
        for (ua, ub) in zip(a.units, b.units) {
            XCTAssertEqual(ua.center.x, ub.center.x)
            XCTAssertEqual(ua.center.y, ub.center.y)
            XCTAssertEqual(ua.color, ub.color)
            XCTAssertEqual(ua.body.count, ub.body.count)
            XCTAssertEqual(ua.rim.count, ub.rim.count)
            XCTAssertEqual(ua.droplets.count, ub.droplets.count)
        }
    }

    func testGeometryRangesMatchWandModel() {
        let s = rollSplatter(at: (x: 0, y: 0), size: 200, colors: [0xAB],
                             seed: 7, now: 0)
        XCTAssertTrue((2...3).contains(s.units.count))          // 2 + rng.next()%2
        for u in s.units {
            XCTAssertTrue((22...29).contains(u.body.count))     // 22 + rng.next()%8
            XCTAssertTrue((22...29).contains(u.rim.count))
            XCTAssertTrue((3...6).contains(u.droplets.count))   // 3 + rng.next()%4
            XCTAssertTrue(u.droplets.allSatisfy { $0.count == 8 })  // irregularBlob points
        }
    }

    func testColorsPickedFromPaletteAndEmptyFallback() {
        let s = rollSplatter(at: (x: 0, y: 0), size: 100, colors: [0xAA, 0xBB],
                             seed: 99, now: 0)
        XCTAssertTrue(s.units.allSatisfy { $0.color == 0xAA || $0.color == 0xBB })
        let w = rollSplatter(at: (x: 0, y: 0), size: 100, colors: [], seed: 1, now: 0)
        XCTAssertTrue(w.units.allSatisfy { $0.color == 0xFFFFFF })
    }

    func testCGPointOverloadRoutes() {
        let s = rollSplatter(at: CGPoint(x: 5, y: 6), size: 80, colors: [1],
                             seed: 3, now: 0)
        XCTAssertFalse(s.units.isEmpty)
    }

    // MARK: - Alpha curve (hold ⅔ → linear fade ⅓)

    func testAlphaHoldThenFade() {
        let s = SplatterShape(units: [], startedAt: 0, duration: 2)
        XCTAssertEqual(s.alpha(now: 0), 1, accuracy: 1e-9)     // p=0   → hold
        XCTAssertEqual(s.alpha(now: 1), 1, accuracy: 1e-9)     // p=0.5 → hold (< 0.66)
        XCTAssertEqual(s.alpha(now: 1.66), 0.5, accuracy: 1e-9) // p=0.83 → (1-.83)/(1-.66)=0.5
        XCTAssertEqual(s.alpha(now: 2), 0, accuracy: 1e-9)     // p=1   → faded out
        XCTAssertEqual(s.alpha(now: 3), 0, accuracy: 1e-9)     // past  → clamped 0
    }

    func testIsActiveBoundaries() {
        let s = SplatterShape(units: [], startedAt: 0, duration: 2)
        XCTAssertFalse(s.isActive(now: -1))
        XCTAssertTrue(s.isActive(now: 0))
        XCTAssertTrue(s.isActive(now: 1.9))
        XCTAssertFalse(s.isActive(now: 2))   // t == duration → settled
    }

    // MARK: - AppKit draw (smoke — real visual proof is the prism live capture)

    func testDrawInkSplatterRunsIntoAContext() {
        let img = NSImage(size: NSSize(width: 80, height: 80))
        img.lockFocus()
        let s = rollSplatter(at: (x: 40, y: 40), size: 60, colors: [0xFF00FF],
                             seed: 0xC0FFEE, now: 0, duration: 1)
        drawInkSplatter(s, now: 0.2)   // held → full
        drawInkSplatter(s, now: 0.9)   // fading
        drawInkSplatter(s, now: 5)     // settled → alpha 0, no-op, must not crash
        img.unlockFocus()
    }
}
