// Token-scale drift guards — #13's FIXED internal layout scales (`Space`,
// `Radius`, `Elevation`) are the single source of the widget kit's spacing,
// corner radii, and drop-shadow depth, replacing the literals each widget
// copy-pasted. These pin the ramps so a future edit can't silently regress
// a value, and lock the monotonic-ramp + Tailwind/MUI-grounded invariants.
// Pure — no AppKit (the CoreGraphics-free discipline the scales depend on).
import XCTest
import Palette

final class TokenScaleTests: XCTestCase {

    // MARK: - Space (MUI 8pt base / Tailwind 4pt grid)

    func testSpaceRamp() {
        XCTAssertEqual(Space.xxs, 2)
        XCTAssertEqual(Space.xs,  4)
        XCTAssertEqual(Space.sm,  6)
        XCTAssertEqual(Space.md,  8)   // THE default gap (icon↔label, item spacing)
        XCTAssertEqual(Space.lg,  12)
        XCTAssertEqual(Space.xl,  16)  // MUI spacing(2)
    }

    func testSpaceScaleIsOrderedAndStrictlyIncreasing() {
        let pts = Space.scale.map(\.pt)
        XCTAssertEqual(pts, [2, 4, 6, 8, 12, 16])
        XCTAssertEqual(pts, pts.sorted())
        XCTAssertEqual(Set(pts).count, pts.count, "Space steps must be distinct")
        XCTAssertEqual(Space.scale.map(\.name), ["xxs", "xs", "sm", "md", "lg", "xl"])
    }

    // MARK: - Radius (MUI shape.borderRadius 4 / Tailwind radius scale)

    func testRadiusRamp() {
        XCTAssertEqual(Radius.xs, 2)
        XCTAssertEqual(Radius.sm, 4)   // MUI theme.shape.borderRadius — the base control radius
        XCTAssertEqual(Radius.md, 6)
        XCTAssertEqual(Radius.lg, 8)
        XCTAssertEqual(Radius.xl, 12)
    }

    func testRadiusScaleIsOrderedAndStrictlyIncreasing() {
        let pts = Radius.scale.map(\.pt)
        XCTAssertEqual(pts, [2, 4, 6, 8, 12])
        XCTAssertEqual(pts, pts.sorted())
        XCTAssertEqual(Set(pts).count, pts.count, "Radius steps must be distinct")
        XCTAssertEqual(Radius.scale.map(\.name), ["xs", "sm", "md", "lg", "xl"])
    }

    // MARK: - Elevation (Material/MUI dp ladder, grounded in the kit's values)

    func testElevationFlatIsNoShadow() {
        XCTAssertEqual(Elevation.flat.token, ElevationToken(opacity: 0, blur: 0, dy: 0))
    }

    func testElevationLadder() {
        XCTAssertEqual(Elevation.dp2.token,  ElevationToken(opacity: 0.20, blur: 3,  dy: 1))
        XCTAssertEqual(Elevation.dp4.token,  ElevationToken(opacity: 0.24, blur: 5,  dy: 2))
        XCTAssertEqual(Elevation.dp6.token,  ElevationToken(opacity: 0.26, blur: 6,  dy: 2))
        XCTAssertEqual(Elevation.dp8.token,  ElevationToken(opacity: 0.28, blur: 8,  dy: 3))
        XCTAssertEqual(Elevation.dp12.token, ElevationToken(opacity: 0.34, blur: 12, dy: 7))
    }

    /// Depth must read monotonically — a deeper level is never lighter,
    /// blurrier-but-flatter, or higher. Guards the ladder from going jagged.
    func testElevationIsMonotonicallyDeeper() {
        let ordered = Elevation.allCases   // CaseIterable order = the ladder
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThanOrEqual(a.token.opacity, b.token.opacity, "\(a)→\(b) opacity dipped")
            XCTAssertLessThanOrEqual(a.token.blur,    b.token.blur,    "\(a)→\(b) blur dipped")
            XCTAssertLessThanOrEqual(a.token.dy,      b.token.dy,      "\(a)→\(b) offset dipped")
        }
    }

    // MARK: - vocabulary completeness (stable reference counts)

    func testVocabularyCounts() {
        XCTAssertEqual(Space.scale.count, 6)
        XCTAssertEqual(Radius.scale.count, 5)
        XCTAssertEqual(Elevation.allCases.count, 6)
    }
}
