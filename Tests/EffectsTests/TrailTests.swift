// Trail-geometry tests — the pure path primitives (wand's walkPath +
// buildHybridPath corner-rounding, lifted). Deterministic geometry asserted
// against hand-derived values; all boundaries binary-exact (the #6 lesson).
// swift test runs on CI only (CLT has no XCTest).

import XCTest
import AppKit
@testable import Effects

final class TrailTests: XCTestCase {

    // MARK: - resampleAlongPolyline (arc-length walker)

    func testResampleEvenSpacingNoDuplicateEnd() {
        // 100pt line, interval 25 → marks at 0,25,50,75,100 (end NOT doubled).
        let m = resampleAlongPolyline([(x: 0, y: 0), (x: 100, y: 0)], interval: 25)
        XCTAssertEqual(m.count, 5)
        XCTAssertEqual(m.map { $0.point.x }, [0, 25, 50, 75, 100])
        XCTAssertTrue(m.allSatisfy { $0.point.y == 0 })
        XCTAssertTrue(m.allSatisfy { $0.tangent == (x: 1, y: 0) })  // forward along +x
    }

    func testResampleUnevenAppendsHead() {
        // interval 30 on 100pt → 0,30,60,90, then the head (100) is appended.
        let m = resampleAlongPolyline([(x: 0, y: 0), (x: 100, y: 0)], interval: 30)
        XCTAssertEqual(m.map { $0.point.x }, [0, 30, 60, 90, 100])
    }

    func testResampleCarriesAcrossCorner() {
        // L-shape: right 50 then up 50, interval 25. Spacing must carry through
        // the join: 0,25,50 (corner) along x, then 25,50 up y → y = 25, 50.
        let m = resampleAlongPolyline([(x: 0, y: 0), (x: 50, y: 0), (x: 50, y: 50)],
                                      interval: 25)
        XCTAssertEqual(m.map { $0.point.x }, [0, 25, 50, 50, 50])
        XCTAssertEqual(m.map { $0.point.y }, [0, 0, 0, 25, 50])
        XCTAssertEqual(m[4].tangent.x, 0, accuracy: 1e-9)   // last leg points +y
        XCTAssertEqual(m[4].tangent.y, 1, accuracy: 1e-9)
    }

    func testResampleTrimTailStopsShort() {
        // trimTail 30 on a 100pt line → cutoff 70: 0,25,50, then 70 (exact).
        let m = resampleAlongPolyline([(x: 0, y: 0), (x: 100, y: 0)],
                                      interval: 25, trimTail: 30)
        XCTAssertEqual(m.map { $0.point.x }, [0, 25, 50, 70])
    }

    func testResampleEdgeCases() {
        XCTAssertTrue(resampleAlongPolyline([] as [(x: Double, y: Double)], interval: 10).isEmpty)
        XCTAssertTrue(resampleAlongPolyline([(x: 0, y: 0), (x: 9, y: 0)], interval: 0).isEmpty)
        // trimTail longer than the whole path → nothing.
        XCTAssertTrue(resampleAlongPolyline([(x: 0, y: 0), (x: 10, y: 0)],
                                            interval: 5, trimTail: 99).isEmpty)
        // single point → one mark, default tangent.
        let one = resampleAlongPolyline([(x: 3, y: 4)], interval: 5)
        XCTAssertEqual(one.count, 1)
        XCTAssertTrue(one[0].tangent == (x: 1, y: 0))
    }

    // MARK: - markAtArcLength (single-offset query — the PathPet faceLag anchor)

    func testMarkAtArcLengthMidSegment() {
        // 100pt line along +x; distance 30 → (30,0), tangent +x.
        let m = markAtArcLength([(x: 0, y: 0), (x: 100, y: 0)], distance: 30)
        XCTAssertNotNil(m)
        XCTAssertEqual(m!.point.x, 30, accuracy: 1e-9)
        XCTAssertEqual(m!.point.y, 0, accuracy: 1e-9)
        XCTAssertEqual(m!.tangent.x, 1, accuracy: 1e-9)
        XCTAssertEqual(m!.tangent.y, 0, accuracy: 1e-9)
    }

    func testMarkAtArcLengthClampsBothEnds() {
        let line = [(x: 0.0, y: 0.0), (x: 100.0, y: 0.0)]
        // at/before the start → the first point.
        XCTAssertEqual(markAtArcLength(line, distance: -10)!.point.x, 0, accuracy: 1e-9)
        XCTAssertEqual(markAtArcLength(line, distance: 0)!.point.x, 0, accuracy: 1e-9)
        // at/past the end → the last point.
        XCTAssertEqual(markAtArcLength(line, distance: 999)!.point.x, 100, accuracy: 1e-9)
    }

    func testMarkAtArcLengthAcrossCorner() {
        // L-shape right 50 then up 50 (total 100); distance 75 → 25 up the 2nd
        // leg → (50,25), tangent +y. Carry across the corner like the resampler.
        let m = markAtArcLength([(x: 0, y: 0), (x: 50, y: 0), (x: 50, y: 50)], distance: 75)
        XCTAssertEqual(m!.point.x, 50, accuracy: 1e-9)
        XCTAssertEqual(m!.point.y, 25, accuracy: 1e-9)
        XCTAssertEqual(m!.tangent.x, 0, accuracy: 1e-9)
        XCTAssertEqual(m!.tangent.y, 1, accuracy: 1e-9)
    }

    func testMarkAtArcLengthEdgeCases() {
        XCTAssertNil(markAtArcLength([] as [(x: Double, y: Double)], distance: 5))
        // single point → itself, default tangent (matches resampleAlongPolyline).
        let one = markAtArcLength([(x: 3, y: 4)], distance: 10)
        XCTAssertEqual(one!.point.x, 3, accuracy: 1e-9)
        XCTAssertEqual(one!.point.y, 4, accuracy: 1e-9)
        XCTAssertTrue(one!.tangent == (x: 1, y: 0))
    }

    func testMarkAtArcLengthPastEndTangentMultiLeg() {
        // Past the end of an L-shape → clamp to the last point with the LAST leg's
        // tangent (drawChompPath rotates the pac / gazes the ghost by this tangent,
        // and headDist can sit at the loop terminal).
        let m = markAtArcLength([(x: 0, y: 0), (x: 50, y: 0), (x: 50, y: 50)], distance: 999)
        XCTAssertEqual(m!.point.x, 50, accuracy: 1e-9)
        XCTAssertEqual(m!.point.y, 50, accuracy: 1e-9)
        XCTAssertEqual(m!.tangent.x, 0, accuracy: 1e-9)
        XCTAssertEqual(m!.tangent.y, 1, accuracy: 1e-9)
    }

    func testMarkAtArcLengthZeroLengthSegments() {
        // Leading zero-length segment: the leading-tangent peek skips it and orients
        // along the first NON-zero leg (parity with resampleAlongPolyline).
        let lead = markAtArcLength([(x: 0, y: 0), (x: 0, y: 0), (x: 0, y: 10)], distance: 0)
        XCTAssertEqual(lead!.point.x, 0, accuracy: 1e-9)
        XCTAssertEqual(lead!.point.y, 0, accuracy: 1e-9)
        XCTAssertEqual(lead!.tangent.x, 0, accuracy: 1e-9)
        XCTAssertEqual(lead!.tangent.y, 1, accuracy: 1e-9)
        // Interior zero-length segment is skipped mid-march (still lands at 25 up leg 2).
        let mid = markAtArcLength([(x: 0, y: 0), (x: 50, y: 0), (x: 50, y: 0), (x: 50, y: 50)],
                                  distance: 75)
        XCTAssertEqual(mid!.point.x, 50, accuracy: 1e-9)
        XCTAssertEqual(mid!.point.y, 25, accuracy: 1e-9)
        XCTAssertEqual(mid!.tangent.y, 1, accuracy: 1e-9)
        // All-degenerate multi-point path → the point, default (1,0) tangent.
        let deg = markAtArcLength([(x: 0, y: 0), (x: 0, y: 0)], distance: 5)
        XCTAssertEqual(deg!.point.x, 0, accuracy: 1e-9)
        XCTAssertTrue(deg!.tangent == (x: 1, y: 0))
    }

    // MARK: - polylineLength + pathPetCursors (the PathPet loop/lag math, #12 Ph3)

    func testPolylineLength() {
        XCTAssertEqual(polylineLength([(x: 0, y: 0), (x: 100, y: 0)]), 100, accuracy: 1e-9)
        XCTAssertEqual(polylineLength([(x: 0, y: 0), (x: 50, y: 0), (x: 50, y: 50)]),
                       100, accuracy: 1e-9)
        // < 2 points or all-degenerate → 0.
        XCTAssertEqual(polylineLength([] as [(x: Double, y: Double)]), 0)
        XCTAssertEqual(polylineLength([(x: 1, y: 2)]), 0)
        XCTAssertEqual(polylineLength([(x: 7, y: 7), (x: 7, y: 7)]), 0, accuracy: 1e-9)
    }

    func testPathPetCursorsHeadLeadsPetTrails() {
        // total 100, speed 50 → period 2s. At now 1 the head is half-way (50) and
        // the pet trails faceLag (10) behind → 40 (the head leads the face).
        let c = pathPetCursors(total: 100, speed: 50, now: 1, faceLag: 10)
        XCTAssertEqual(c.head, 50, accuracy: 1e-9)
        XCTAssertEqual(c.pet, 40, accuracy: 1e-9)
    }

    func testPathPetCursorsLoopWrap() {
        // now == period → head resets to 0 (loop restart); pet goes negative (the
        // caller clamps it to the start via markAtArcLength).
        let wrap = pathPetCursors(total: 100, speed: 50, now: 2, faceLag: 10)
        XCTAssertEqual(wrap.head, 0, accuracy: 1e-9)
        XCTAssertEqual(wrap.pet, -10, accuracy: 1e-9)
        // now past one period keeps marching (now 3 → same phase as now 1).
        XCTAssertEqual(pathPetCursors(total: 100, speed: 50, now: 3, faceLag: 0).head,
                       50, accuracy: 1e-9)
    }

    func testPathPetCursorsNegativeNowWrapsForward() {
        // A negative injected `now` folds FORWARD (frameStep's rule), not into a
        // negative/clamped dead-zone: now -1, period 2 ⇒ phase 1 ⇒ head 50.
        XCTAssertEqual(pathPetCursors(total: 100, speed: 50, now: -1, faceLag: 0).head,
                       50, accuracy: 1e-9)
        // Degenerate total/speed → (0, -faceLag), no divide-by-zero.
        let z = pathPetCursors(total: 0, speed: 50, now: 1, faceLag: 10)
        XCTAssertEqual(z.head, 0, accuracy: 1e-9)
        XCTAssertEqual(z.pet, -10, accuracy: 1e-9)
    }

    // MARK: - eatCrossed (the per-frame eat primitive, #12 Ph5)

    func testEatCrossedForwardInterval() {
        // arc 50 lies in (40, 60] → crossed this frame.
        XCTAssertTrue(eatCrossed(arc: 50, prev: 40, cur: 60))
        // half-open: arc == cur is INCLUDED, arc == prev is EXCLUDED.
        XCTAssertTrue(eatCrossed(arc: 50, prev: 40, cur: 50))
        XCTAssertFalse(eatCrossed(arc: 50, prev: 50, cur: 60))
    }

    func testEatCrossedNotReachedOrAlreadyPast() {
        XCTAssertFalse(eatCrossed(arc: 70, prev: 40, cur: 60))   // ahead of the face
        XCTAssertFalse(eatCrossed(arc: 30, prev: 40, cur: 60))   // already behind
    }

    func testEatCrossedWrapIsNotACrossing() {
        // A loop restart (cur < prev) is NOT a crossing — the caller resets per lap.
        XCTAssertFalse(eatCrossed(arc: 10, prev: 90, cur: 5))
    }

    // MARK: - roundedCornerPath

    func testRoundedCornerCutsAndBridges() {
        // ⌐ corner at (10,0); radius 4 ≤ ½·10 → P=(6,0), Q=(10,4) via (10,0).
        let steps = roundedCornerPath([(x: 0, y: 0), (x: 10, y: 0), (x: 10, y: 10)],
                                      radius: 4)
        XCTAssertEqual(steps, [
            .move(x: 0, y: 0),
            .line(x: 6, y: 0),
            .quadCurve(x: 10, y: 4, cx: 10, cy: 0),
            .line(x: 10, y: 10),
        ])
    }

    func testRoundedCornerRadiusCappedToHalfLeg() {
        // Huge radius is capped to ½ the shorter adjacent leg (5 here).
        let steps = roundedCornerPath([(x: 0, y: 0), (x: 10, y: 0), (x: 10, y: 10)],
                                      radius: 100)
        XCTAssertEqual(steps, [
            .move(x: 0, y: 0),
            .line(x: 5, y: 0),
            .quadCurve(x: 10, y: 5, cx: 10, cy: 0),
            .line(x: 10, y: 10),
        ])
    }

    func testRoundedCornerTrivialCounts() {
        XCTAssertEqual(roundedCornerPath([] as [(x: Double, y: Double)], radius: 4), [])
        XCTAssertEqual(roundedCornerPath([(x: 1, y: 2)], radius: 4), [.move(x: 1, y: 2)])
        XCTAssertEqual(roundedCornerPath([(x: 0, y: 0), (x: 5, y: 5)], radius: 4),
                       [.move(x: 0, y: 0), .line(x: 5, y: 5)])
    }

    // MARK: - interiorCorners (concave fillet anchors — #12 Ph4 neon corridor)

    func testInteriorCornersLeftTurn() {
        // ⌐ right-then-up: a LEFT (CCW) turn at (10,0). The concave side faces
        // up-left, so the inner bisector is (-1,1)/√2; signed turn +π/2.
        let c = interiorCorners([(x: 0, y: 0), (x: 10, y: 0), (x: 10, y: 10)])
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].vertex.x, 10, accuracy: 1e-9)
        XCTAssertEqual(c[0].vertex.y, 0, accuracy: 1e-9)
        XCTAssertEqual(c[0].bisector.x, -0.7071067811865476, accuracy: 1e-9)
        XCTAssertEqual(c[0].bisector.y,  0.7071067811865476, accuracy: 1e-9)
        XCTAssertEqual(c[0].turn, .pi / 2, accuracy: 1e-9)
    }

    func testInteriorCornersRightTurn() {
        // right-then-down: a RIGHT (CW) turn at (10,0): inner bisector (-1,-1)/√2,
        // signed turn −π/2.
        let c = interiorCorners([(x: 0, y: 0), (x: 10, y: 0), (x: 10, y: -10)])
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].bisector.x, -0.7071067811865476, accuracy: 1e-9)
        XCTAssertEqual(c[0].bisector.y, -0.7071067811865476, accuracy: 1e-9)
        XCTAssertEqual(c[0].turn, -.pi / 2, accuracy: 1e-9)
    }

    func testInteriorCornersSkipsCollinear() {
        // A straight run continues in the same direction → no corner to fillet.
        XCTAssertTrue(interiorCorners([(x: 0, y: 0), (x: 10, y: 0), (x: 20, y: 0)]).isEmpty)
    }

    func testInteriorCornersOrthogonalSnake() {
        // ⊓ right, up, left → two LEFT turns at (10,0) and (10,10). The second
        // (up-then-left) has inner bisector (-1,-1)/√2, turn +π/2.
        let c = interiorCorners([(x: 0, y: 0), (x: 10, y: 0), (x: 10, y: 10), (x: 0, y: 10)])
        XCTAssertEqual(c.count, 2)
        XCTAssertEqual(c[0].vertex.x, 10, accuracy: 1e-9)
        XCTAssertEqual(c[0].vertex.y, 0, accuracy: 1e-9)
        XCTAssertEqual(c[1].vertex.x, 10, accuracy: 1e-9)
        XCTAssertEqual(c[1].vertex.y, 10, accuracy: 1e-9)
        XCTAssertEqual(c[1].bisector.x, -0.7071067811865476, accuracy: 1e-9)
        XCTAssertEqual(c[1].bisector.y, -0.7071067811865476, accuracy: 1e-9)
        XCTAssertEqual(c[1].turn, .pi / 2, accuracy: 1e-9)
    }

    func testInteriorCornersEdgeCases() {
        // No interior vertex → nothing (empty, single point, lone segment).
        XCTAssertTrue(interiorCorners([] as [(x: Double, y: Double)]).isEmpty)
        XCTAssertTrue(interiorCorners([(x: 1, y: 2)]).isEmpty)
        XCTAssertTrue(interiorCorners([(x: 0, y: 0), (x: 10, y: 0)]).isEmpty)
        // A zero-length segment adjacent to the vertex is skipped (no NaN bisector):
        // i=1 has a degenerate OUT seg, i=2 a degenerate IN seg → both skipped.
        XCTAssertTrue(interiorCorners([(x: 0, y: 0), (x: 10, y: 0),
                                       (x: 10, y: 0), (x: 10, y: 10)]).isEmpty)
    }

    // MARK: - AppKit path builder

    @MainActor
    func testNSBezierPathFromSteps() {
        let steps = roundedCornerPath([(x: 0, y: 0), (x: 10, y: 0), (x: 10, y: 10)],
                                      radius: 4)
        let path = nsBezierPath(steps, lineWidth: 2)
        XCTAssertEqual(path.elementCount, 4)        // move, line, curve, line
        XCTAssertEqual(path.lineWidth, 2, accuracy: 1e-9)
        var pts = [NSPoint](repeating: .zero, count: 3)
        XCTAssertEqual(path.element(at: 0, associatedPoints: &pts), .moveTo)
        XCTAssertEqual(path.element(at: 2, associatedPoints: &pts), .curveTo)
    }
}
