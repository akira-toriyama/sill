// Gesture — unit tests. These run in CI ONLY (the maintainer's machine is
// CommandLineTools-only; `import XCTest` needs full Xcode). Pure logic, so the
// coverage is exhaustive: the dominant-axis quantiser (threshold, anchor reset,
// duplicate coalesce, tie-breaking, the Y-grows-up convention), the reversal /
// pattern-validity helpers, and the value-type plumbing. Coordinates use
// whole-number Doubles so every `>=`/`==` boundary is exact in binary (the
// `swift test`-only float-boundary trap from #6/#9c). Empty arrays are typed to
// dodge the literal-inference ambiguity that bit #7/#9c.

import XCTest
@testable import Gesture
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - Direction

final class DirectionTests: XCTestCase {
    func testRawValuesAreLURD() {
        XCTAssertEqual(Direction.left.rawValue, "L")
        XCTAssertEqual(Direction.up.rawValue, "U")
        XCTAssertEqual(Direction.right.rawValue, "R")
        XCTAssertEqual(Direction.down.rawValue, "D")
    }

    func testFourWayOnly() {
        XCTAssertEqual(Direction.allCases.count, 4)
    }

    func testArrowGlyphs() {
        XCTAssertEqual(Direction.left.arrow, "←")
        XCTAssertEqual(Direction.up.arrow, "↑")
        XCTAssertEqual(Direction.right.arrow, "→")
        XCTAssertEqual(Direction.down.arrow, "↓")
    }

    func testPatternString() {
        XCTAssertEqual([Direction.down, .left].patternString, "DL")
        XCTAssertEqual([Direction.left, .up, .right, .down].patternString, "LURD")
        let empty: [Direction] = []
        XCTAssertEqual(empty.patternString, "")
    }
}

// MARK: - Sample plumbing

final class SampleTests: XCTestCase {
    func testStoresCoordinatesAndTime() {
        let s = Sample(x: 3, y: 4, t: 0.5)
        XCTAssertEqual(s.x, 3)
        XCTAssertEqual(s.y, 4)
        XCTAssertEqual(s.t, 0.5)
    }

    func testExcursionIsMaxAbsDisplacementFromFirst() {
        let samples = [Sample(x: 0, y: 0, t: 0),
                       Sample(x: 10, y: -3, t: 1),
                       Sample(x: 4, y: 8, t: 2)]
        let excursion = samples.excursion
        XCTAssertEqual(excursion.dx, 10)   // |10-0| is the largest x excursion
        XCTAssertEqual(excursion.dy, 8)    // |8-0| is the largest y excursion
    }

    func testExcursionOfEmptyIsZero() {
        let empty: [Sample] = []
        let excursion = empty.excursion
        XCTAssertEqual(excursion.dx, 0)
        XCTAssertEqual(excursion.dy, 0)
    }

    func testEquatable() {
        XCTAssertEqual(Sample(x: 1, y: 2, t: 3), Sample(x: 1, y: 2, t: 3))
        XCTAssertNotEqual(Sample(x: 1, y: 2, t: 3), Sample(x: 1, y: 2, t: 4))
    }

    #if canImport(CoreGraphics)
    func testCGPointConvenience() {
        let s = Sample(p: CGPoint(x: 7, y: 9), t: 1.5)
        XCTAssertEqual(s.x, 7)
        XCTAssertEqual(s.y, 9)
        XCTAssertEqual(s.t, 1.5)
        XCTAssertEqual(s.p, CGPoint(x: 7, y: 9))
    }
    #endif
}

// MARK: - recognize

final class RecognizeTests: XCTestCase {

    func testTooFewSamplesIsEmpty() {
        let none: [Sample] = []
        XCTAssertEqual(Recognition.recognize(samples: none, minStrokePx: 10), [])
        let one = [Sample(x: 0, y: 0, t: 0)]
        XCTAssertEqual(Recognition.recognize(samples: one, minStrokePx: 10), [])
    }

    func testNonPositiveThresholdIsEmpty() {
        let s = [Sample(x: 0, y: 0, t: 0), Sample(x: 100, y: 0, t: 1)]
        XCTAssertEqual(Recognition.recognize(samples: s, minStrokePx: 0), [])
        XCTAssertEqual(Recognition.recognize(samples: s, minStrokePx: -5), [])
    }

    func testFourCardinalDirections() {
        // Y grows UP (callers sign-flip the platform Y-down coordinate), so a
        // larger y reads as ".up".
        func dir(_ dx: Double, _ dy: Double) -> [Direction] {
            Recognition.recognize(
                samples: [Sample(x: 0, y: 0, t: 0), Sample(x: dx, y: dy, t: 1)],
                minStrokePx: 10)
        }
        XCTAssertEqual(dir(10, 0), [.right])
        XCTAssertEqual(dir(-10, 0), [.left])
        XCTAssertEqual(dir(0, 10), [.up])
        XCTAssertEqual(dir(0, -10), [.down])
    }

    func testThresholdBoundaryIsInclusive() {
        let exact = [Sample(x: 0, y: 0, t: 0), Sample(x: 10, y: 0, t: 1)]
        XCTAssertEqual(Recognition.recognize(samples: exact, minStrokePx: 10), [.right])
        let under = [Sample(x: 0, y: 0, t: 0), Sample(x: 9, y: 0, t: 1)]
        XCTAssertEqual(Recognition.recognize(samples: under, minStrokePx: 10), [])
    }

    func testZeroMovementEmitsNothing() {
        let still = [Sample(x: 5, y: 5, t: 0),
                     Sample(x: 5, y: 5, t: 1),
                     Sample(x: 5, y: 5, t: 2)]
        XCTAssertEqual(Recognition.recognize(samples: still, minStrokePx: 10), [])
    }

    func testDominantAxisTieGoesHorizontal() {
        // |dx| == |dy|: `absX >= absY` resolves the tie to the horizontal axis.
        let diag = [Sample(x: 0, y: 0, t: 0), Sample(x: 10, y: 10, t: 1)]
        XCTAssertEqual(Recognition.recognize(samples: diag, minStrokePx: 10), [.right])
    }

    func testDominantAxisPicksLargerComponent() {
        let mostlyVertical = [Sample(x: 0, y: 0, t: 0), Sample(x: 4, y: 12, t: 1)]
        XCTAssertEqual(Recognition.recognize(samples: mostlyVertical, minStrokePx: 10), [.up])
        let mostlyHorizontal = [Sample(x: 0, y: 0, t: 0), Sample(x: 12, y: -4, t: 1)]
        XCTAssertEqual(Recognition.recognize(samples: mostlyHorizontal, minStrokePx: 10), [.right])
    }

    func testCoalescesDuplicatesAcrossSubThresholdSteps() {
        // A long rightward drag sampled finely (5 px steps, threshold 10) must
        // coalesce into a SINGLE .right — the anchor resets each time the
        // threshold is crossed, so spacing accrues from the last reset.
        let drag = [Sample(x: 0,  y: 0, t: 0),
                    Sample(x: 5,  y: 0, t: 1),   // +5  < 10, skip
                    Sample(x: 10, y: 0, t: 2),   // +10 → .right, anchor=10
                    Sample(x: 15, y: 0, t: 3),   // +5  < 10, skip
                    Sample(x: 20, y: 0, t: 4),   // +10 → .right (dup), anchor=20
                    Sample(x: 30, y: 0, t: 5)]   // +10 → .right (dup), anchor=30
        XCTAssertEqual(Recognition.recognize(samples: drag, minStrokePx: 10), [.right])
    }

    func testAnchorResetsAtEachTurn() {
        // Right then up: the up leg is measured from the post-turn anchor, not
        // the stroke origin.
        let lShape = [Sample(x: 0,  y: 0,  t: 0),
                      Sample(x: 10, y: 0,  t: 1),   // .right, anchor=(10,0)
                      Sample(x: 10, y: 10, t: 2)]   // dy=10 from anchor → .up
        XCTAssertEqual(Recognition.recognize(samples: lShape, minStrokePx: 10), [.right, .up])
    }

    func testZigZagProducesAlternating() {
        let zig = [Sample(x: 0,  y: 0,  t: 0),
                   Sample(x: 10, y: 0,  t: 1),   // .right
                   Sample(x: 10, y: 10, t: 2),   // .up
                   Sample(x: 0,  y: 10, t: 3),   // .left
                   Sample(x: 0,  y: 0,  t: 4)]   // .down
        let dirs = Recognition.recognize(samples: zig, minStrokePx: 10)
        XCTAssertEqual(dirs.patternString, "RULD")
    }
}

// MARK: - reversals / isOpposite

final class ReversalTests: XCTestCase {
    func testIsOpposite() {
        XCTAssertTrue(Recognition.isOpposite("L", "R"))
        XCTAssertTrue(Recognition.isOpposite("R", "L"))
        XCTAssertTrue(Recognition.isOpposite("U", "D"))
        XCTAssertTrue(Recognition.isOpposite("D", "U"))
        XCTAssertFalse(Recognition.isOpposite("L", "U"))   // different axis
        XCTAssertFalse(Recognition.isOpposite("L", "L"))   // same direction
        XCTAssertFalse(Recognition.isOpposite("X", "Y"))   // not in alphabet
    }

    func testReversalsCount() {
        XCTAssertEqual(Recognition.reversals(""), 0)
        XCTAssertEqual(Recognition.reversals("L"), 0)
        XCTAssertEqual(Recognition.reversals("LR"), 1)
        XCTAssertEqual(Recognition.reversals("LRL"), 2)
        XCTAssertEqual(Recognition.reversals("UD"), 1)
        XCTAssertEqual(Recognition.reversals("LU"), 0)     // axis change, not a reversal
        XCTAssertEqual(Recognition.reversals("LRUD"), 2)   // LR + UD, the RU join is not opposite
    }
}

// MARK: - patternIssue

final class PatternIssueTests: XCTestCase {
    func testValidPatternsHaveNoIssue() {
        XCTAssertNil(Recognition.patternIssue("L"))
        XCTAssertNil(Recognition.patternIssue("DR"))
        XCTAssertNil(Recognition.patternIssue("LURD"))
    }

    func testEmptyPattern() {
        XCTAssertEqual(Recognition.patternIssue(""), "empty pattern")
    }

    func testInvalidCharacterIsReported() {
        let issue = Recognition.patternIssue("DX")
        XCTAssertNotNil(issue)
        XCTAssertTrue(issue?.contains("invalid character") ?? false)
    }

    func testConsecutiveDuplicateIsUnreachable() {
        // The recogniser coalesces same-direction segments, so "DRR" can never
        // be drawn — patternIssue flags it at config-load.
        let issue = Recognition.patternIssue("DRR")
        XCTAssertNotNil(issue)
        XCTAssertTrue(issue?.contains("consecutive duplicate") ?? false)
    }
}

// MARK: - Integration: a recognised stroke is always a valid pattern

final class RecognitionRoundTripTests: XCTestCase {
    func testRecognisedPatternNeverHasAnIssue() {
        // Whatever recognize emits is coalesced + in-alphabet by construction,
        // so patternIssue must accept it — the recogniser and the validator
        // agree on what a drawable pattern is.
        let zig = [Sample(x: 0,  y: 0,  t: 0),
                   Sample(x: 10, y: 0,  t: 1),
                   Sample(x: 10, y: 10, t: 2),
                   Sample(x: 0,  y: 10, t: 3)]
        let pattern = Recognition.recognize(samples: zig, minStrokePx: 10).patternString
        XCTAssertEqual(pattern, "RUL")
        XCTAssertNil(Recognition.patternIssue(pattern))
    }
}

// MARK: - GestureRecognitionSpec

final class GestureRecognitionSpecTests: XCTestCase {
    func testDefaults() {
        let s = GestureRecognitionSpec.default
        XCTAssertEqual(s.minStrokePx, 16)
        XCTAssertEqual(s.maxSegmentMs, 0)
        XCTAssertEqual(s.cancelReversals, 2)
        XCTAssertEqual(s.cancelWindowMs, 500)
    }

    func testCustomValuesAndEquatable() {
        let a = GestureRecognitionSpec(minStrokePx: 24, maxSegmentMs: 800,
                                       cancelReversals: 3, cancelWindowMs: 400)
        let b = GestureRecognitionSpec(minStrokePx: 24, maxSegmentMs: 800,
                                       cancelReversals: 3, cancelWindowMs: 400)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, .default)
    }
}
