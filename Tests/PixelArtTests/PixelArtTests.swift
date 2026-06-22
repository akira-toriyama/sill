// PixelArt — unit tests. These run in CI ONLY (the maintainer's machine is
// CommandLineTools-only; `import XCTest` needs full Xcode). Pure logic, so the
// coverage is exhaustive: the sprite flattener (palette mapping, transparent
// sentinel, row-major order, ragged rows), the Pac-Man circle-minus-mouth wedge
// (circle bound, mouth removal, mouth-grows-with-phase), the stable per-cell
// hash (determinism, range, negative-safe, distribution), and the size knob.
//
// `cells()` / `pacManCells` return LABELLED TUPLE arrays — tuples are NOT
// Equatable, so equality is asserted on a projected `[String]` form (never an
// `XCTAssertEqual` of tuple arrays). Empty results are typed to dodge the
// literal-inference ambiguity that bit #7/#9c.

import XCTest
@testable import PixelArt
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - PixelSprite

final class PixelSpriteTests: XCTestCase {
    /// Project labelled cells to a comparable `[String]` ("col,row,hexcolor").
    private func keys(_ cells: [(col: Int, row: Int, color: UInt32)]) -> [String] {
        cells.map { "\($0.col),\($0.row),\(String($0.color, radix: 16))" }
    }

    func testCellsMapsRowsAndPalette() {
        let s = PixelSprite(rows: ["ab", "ba"],
                            palette: ["a": 0x111111, "b": 0x222222])
        XCTAssertEqual(keys(s.cells()),
                       ["0,0,111111", "1,0,222222", "0,1,222222", "1,1,111111"])
    }

    func testTransparentSentinelSkipped() {
        // '.' is absent from the palette → transparent → omitted.
        let s = PixelSprite(rows: ["a.a"], palette: ["a": 0xFF0000])
        XCTAssertEqual(s.cells().count, 2)
        XCTAssertEqual(s.cells().map(\.col), [0, 2])
    }

    func testRowMajorOrder() {
        let s = PixelSprite(rows: ["aa", "aa", "aa"], palette: ["a": 1])
        let rowsSeq = s.cells().map(\.row)
        XCTAssertEqual(rowsSeq, rowsSeq.sorted())   // non-decreasing by row
        XCTAssertEqual(rowsSeq, [0, 0, 1, 1, 2, 2])
    }

    func testEmptySprite() {
        let s = PixelSprite(rows: [], palette: [:])
        XCTAssertTrue(s.cells().isEmpty)
        XCTAssertEqual(s.width, 0)
        XCTAssertEqual(s.height, 0)
    }

    func testWidthIsLongestRowHeightIsRowCount() {
        let s = PixelSprite(rows: ["aaa", "a"], palette: ["a": 1])
        XCTAssertEqual(s.width, 3)
        XCTAssertEqual(s.height, 2)
    }

    func testRaggedRowsEmitFewerCellsNoPadding() {
        // A short row is NOT padded with transparency — it just emits fewer cells.
        let s = PixelSprite(rows: ["aaa", "a"], palette: ["a": 1])
        XCTAssertEqual(s.cells().count, 4)   // 3 + 1, not 3 + 3
    }

    func testEquatable() {
        let a = PixelSprite(rows: ["a"], palette: ["a": 1])
        let b = PixelSprite(rows: ["a"], palette: ["a": 1])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, PixelSprite(rows: ["a"], palette: ["a": 2]))
    }

    #if canImport(CoreGraphics)
    func testPixelSizeConvenience() {
        let s = PixelSprite(rows: ["aaa", "aaa"], palette: ["a": 1])   // 3 × 2
        XCTAssertEqual(s.pixelSize(cell: 4), CGSize(width: 12, height: 8))
    }
    #endif
}

// MARK: - pacManCells

final class PacManCellsTests: XCTestCase {
    private let d = 13
    private var r: Double { Double(d) / 2 }
    private func cx(_ col: Int) -> Double { Double(col) + 0.5 - r }
    private func cy(_ row: Int) -> Double { Double(row) + 0.5 - r }

    func testMouthWedgeRemovedAndOppositeSideKept() {
        // Wide gape (phase 1 = 60°). Centre row of a 13-grid is row 6 (cy = 0).
        let cells = pacManCells(diameterCells: d, mouthHalfRad: mouthHalfRad(phase: 1))
        // A cell straight RIGHT of centre is INSIDE the mouth wedge → removed…
        XCTAssertFalse(cells.contains { $0.col == 10 && $0.row == 6 })
        // …but the mirror cell straight LEFT (opposite the mouth) is kept.
        XCTAssertTrue(cells.contains { $0.col == 2 && $0.row == 6 })
    }

    func testEveryCellInsideTheCircle() {
        let cells = pacManCells(diameterCells: d, mouthHalfRad: mouthHalfRad(phase: 0.5))
        for c in cells {
            let dist2 = cx(c.col) * cx(c.col) + cy(c.row) * cy(c.row)
            XCTAssertLessThanOrEqual(dist2, r * r + 1e-9)
        }
        XCTAssertFalse(cells.isEmpty)
    }

    func testNoCellInsideTheMouthWedge() {
        let half = mouthHalfRad(phase: 0.8)
        let cells = pacManCells(diameterCells: d, mouthHalfRad: half)
        for c in cells {
            XCTAssertGreaterThanOrEqual(abs(atan2(cy(c.row), cx(c.col))), half)
        }
    }

    func testMouthGrowsWithPhase() {
        // A bigger mouth removes MORE cells, so the filled count shrinks.
        let small = pacManCells(diameterCells: d, mouthHalfRad: mouthHalfRad(phase: 0.1)).count
        let big = pacManCells(diameterCells: d, mouthHalfRad: mouthHalfRad(phase: 0.9)).count
        XCTAssertGreaterThan(small, big)
    }

    func testZeroDiameterEmpty() {
        let none: [(col: Int, row: Int)] = []
        XCTAssertEqual(pacManCells(diameterCells: 0, mouthHalfRad: 0.5).count, none.count)
        XCTAssertEqual(pacManCells(diameterCells: -3, mouthHalfRad: 0.5).count, 0)
    }

    func testMouthHalfRadFormula() {
        XCTAssertEqual(mouthHalfRad(phase: 0), 5.0 * .pi / 180.0, accuracy: 1e-12)
        XCTAssertEqual(mouthHalfRad(phase: 1), 60.0 * .pi / 180.0, accuracy: 1e-12)
    }
}

// MARK: - Chomp mouth animation data

final class ChompMouthAnimTests: XCTestCase {
    func testFramesAreClosedHalfFullHalf() {
        // The 4-pose swap pattern: closed → half → full → half (opens + closes
        // once per cycle). Phases stay in 0…1 (mouthHalfRad's domain).
        XCTAssertEqual(chompMouthFrames, [0, 0.5, 1, 0.5])
        XCTAssertTrue(chompMouthFrames.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testNeverFullyClosedReadsAsChomp() {
        // The full-gape frame must actually open the wedge (a closed circle is
        // "not a Pac-Man"): phase 1 ⇒ a 60° half-angle ⇒ cells get removed.
        let open = chompMouthFrames.max() ?? 0
        let closed = pacManCells(diameterCells: 13, mouthHalfRad: mouthHalfRad(phase: 0)).count
        let gaping = pacManCells(diameterCells: 13, mouthHalfRad: mouthHalfRad(phase: open)).count
        XCTAssertLessThan(gaping, closed, "the open frame must remove mouth cells")
    }

    func testRateIsFiveHz() {
        XCTAssertEqual(chompMouthHz, 5)
    }
}

// MARK: - positionHash01

final class PositionHashTests: XCTestCase {
    func testDeterministic() {
        XCTAssertEqual(positionHash01(x: 7, y: 9), positionHash01(x: 7, y: 9))
        XCTAssertEqual(positionHash01(x: -2, y: 13), positionHash01(x: -2, y: 13))
    }

    func testRange() {
        for x in 0..<40 {
            for y in 0..<40 {
                let h = positionHash01(x: x, y: y)
                XCTAssertGreaterThanOrEqual(h, 0)
                XCTAssertLessThan(h, 1)
            }
        }
    }

    func testNegativeCoordinatesDoNotTrap() {
        // `bitPattern` keeps the hash total — a plain `UInt64(negativeInt)` would
        // trap. This test would CRASH without that guard.
        let h = positionHash01(x: -3, y: -100)
        XCTAssertGreaterThanOrEqual(h, 0)
        XCTAssertLessThan(h, 1)
    }

    func testReasonablyDistributed() {
        // Over a 32×32 grid, no decile bin is empty (a cheap spread sanity check).
        var bins = [Int](repeating: 0, count: 10)
        for x in 0..<32 {
            for y in 0..<32 {
                bins[min(9, Int(positionHash01(x: x, y: y) * 10))] += 1
            }
        }
        XCTAssertFalse(bins.contains(0), "an empty decile means a degenerate hash: \(bins)")
    }
}

// MARK: - ScaleTier

final class ScaleTierTests: XCTestCase {
    func testMultipliers() {
        XCTAssertEqual(ScaleTier.s.multiplier, 2)
        XCTAssertEqual(ScaleTier.m.multiplier, 3)
        XCTAssertEqual(ScaleTier.l.multiplier, 4.5)
    }

    func testAllCases() {
        XCTAssertEqual(ScaleTier.allCases, [.s, .m, .l])
    }

    // MARK: - Bonus pool (#12 Ph5)

    func testChompBonusPoolIsTheArcadeLadder() {
        XCTAssertEqual(chompBonusPool, [100, 200, 300, 500, 700, 1000, 2000, 5000])
    }

    func testBonusValueIsStableAndInPool() {
        let v = bonusValue(x: 3, y: 7)
        XCTAssertTrue(chompBonusPool.contains(v))
        XCTAssertEqual(v, bonusValue(x: 3, y: 7))                 // deterministic
    }

    func testBonusValueVariesByCell() {
        // Decorrelated from the <0.08 selection band (swapped-coord hash), so
        // neighbouring bonuses are not all 100 — at least two distinct values
        // appear across a small spread of cells.
        let vals = Set((0..<16).map { bonusValue(x: $0 * 13, y: $0 * 7 + 1) })
        XCTAssertGreaterThan(vals.count, 1)
    }
}
