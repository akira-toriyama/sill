// Corridor-eat timeline tests — the pure f(now) derivation that lets the chomp
// corridor flash + score WITHOUT frame-to-frame state (so PRISM_CHOMP_T freezes
// and XCTest stays deterministic). Boundaries binary-exact (the #6 lesson).
// swift test runs on CI only (CLT has no XCTest).

import XCTest
import AppKit
@testable import Effects

final class CorridorTests: XCTestCase {

    // total 100, speed 50 → lap period 2s. faceLag 0 ⇒ the face crosses arc `a`
    // at `a/50` seconds into the lap.

    func testFlashPhaseActiveAfterCrossing() {
        // bonus at arc 50 → crossed at lapPhase 1.0. now 1.25 ⇒ since 0.25,
        // dur 0.5 ⇒ phase 0.5.
        let p = chompFlashPhase(eventArcs: [50], total: 100, speed: 50,
                                now: 1.25, faceLag: 0, dur: 0.5)
        XCTAssertEqual(p!, 0.5, accuracy: 1e-9)
    }

    func testFlashPhaseNilBeforeCrossOrAfterWindow() {
        // before the cross (now 0.5 < 1.0) → nil.
        XCTAssertNil(chompFlashPhase(eventArcs: [50], total: 100, speed: 50,
                                     now: 0.5, faceLag: 0, dur: 0.5))
        // after the 0.5s window (now 1.75 ⇒ since 0.75 ≥ dur) → nil.
        XCTAssertNil(chompFlashPhase(eventArcs: [50], total: 100, speed: 50,
                                     now: 1.75, faceLag: 0, dur: 0.5))
    }

    func testFlashPhasePicksMostRecentCrossing() {
        // arcs 25 (cross 0.5) and 50 (cross 1.0). now 1.125 ⇒ most recent is 1.0,
        // since 0.125, dur 0.5 ⇒ phase 0.25.
        let p = chompFlashPhase(eventArcs: [25, 50], total: 100, speed: 50,
                                now: 1.125, faceLag: 0, dur: 0.5)
        XCTAssertEqual(p!, 0.25, accuracy: 1e-9)
    }

    func testFlashPhaseSkipsUnreachableTail() {
        // arc 100 with faceLag 20 ⇒ arc+faceLag 120 > total ⇒ never crossed ⇒ nil.
        XCTAssertNil(chompFlashPhase(eventArcs: [100], total: 100, speed: 50,
                                     now: 1.9, faceLag: 20, dur: 0.5))
    }

    func testScorePopsActiveWindowAndProgress() {
        // bonus at arc 50 (cross 1.0), value 700. now 1.25 ⇒ one pop, t 0.5.
        let pops = chompScorePops(
            bonuses: [(point: (x: 5, y: 6), arc: 50, value: 700)],
            total: 100, speed: 50, now: 1.25, faceLag: 0, dur: 0.5)
        XCTAssertEqual(pops.count, 1)
        XCTAssertEqual(pops[0].value, 700)
        XCTAssertEqual(pops[0].t, 0.5, accuracy: 1e-9)
        XCTAssertEqual(pops[0].point.x, 5, accuracy: 1e-9)
        // before the cross → no pop.
        XCTAssertTrue(chompScorePops(
            bonuses: [(point: (x: 5, y: 6), arc: 50, value: 700)],
            total: 100, speed: 50, now: 0.5, faceLag: 0, dur: 0.5).isEmpty)
    }

    func testCorridorEatDegenerateInputs() {
        XCTAssertNil(chompFlashPhase(eventArcs: [50], total: 0, speed: 50,
                                     now: 1, faceLag: 0, dur: 0.5))
        XCTAssertTrue(chompScorePops(bonuses: [], total: 100, speed: 50,
                                     now: 1, faceLag: 0, dur: 0.5).isEmpty)
    }
}
