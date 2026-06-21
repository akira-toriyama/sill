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
