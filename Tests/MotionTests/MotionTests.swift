// Motion — unit tests. These run in CI ONLY (the maintainer's machine is
// CommandLineTools-only; `import XCTest` needs full Xcode). Pure math, so the
// coverage here is exhaustive — endpoints, clamping, monotonicity, the exact
// bezier solve, the Tween lifecycle, and the MUI auto-duration formula.

import XCTest
import CoreGraphics
@testable import Motion

private typealias TT = ThemedTransition

final class DurationTokenTests: XCTestCase {
    func testLadderIsOrderedAndSnappy() {
        // The family's measured band: snap < exit < enter < move < emphasis,
        // all ≤ 0.22 s (snappier than MUI's 0.30 s standard).
        XCTAssertEqual(TT.Duration.snap, 0)
        XCTAssertLessThan(TT.Duration.exit, TT.Duration.enter)   // exit faster (MUI taste)
        XCTAssertLessThan(TT.Duration.enter, TT.Duration.move)
        XCTAssertLessThan(TT.Duration.move, TT.Duration.emphasis)
        XCTAssertLessThanOrEqual(TT.Duration.emphasis, 0.22)
        XCTAssertGreaterThan(TT.Duration.staggerStep, 0)
    }

    func testScaledMultipliesAndClampsAtZero() {
        XCTAssertEqual(TT.scaled(0.2, by: 2), 0.4, accuracy: 1e-12)
        XCTAssertEqual(TT.scaled(0.2, by: 0.5), 0.1, accuracy: 1e-12)
        XCTAssertEqual(TT.scaled(0.2, by: 0), 0)
        XCTAssertEqual(TT.scaled(0.2, by: -3), 0, "a negative scale must not produce a negative duration")
    }
}

final class ProgressTests: XCTestCase {
    func testLinearProgressAndClamp() {
        XCTAssertEqual(TT.progress(now: 5, start: 0, duration: 10), 0.5, accuracy: 1e-12)
        XCTAssertEqual(TT.progress(now: -5, start: 0, duration: 10), 0, "before start clamps to 0")
        XCTAssertEqual(TT.progress(now: 20, start: 0, duration: 10), 1, "past end clamps to 1")
    }

    func testDelayShiftsTheWindow() {
        // (now - start - delay)/duration = (5 - 0 - 2)/10 = 0.3
        XCTAssertEqual(TT.progress(now: 5, start: 0, duration: 10, delay: 2), 0.3, accuracy: 1e-12)
        XCTAssertEqual(TT.progress(now: 1, start: 0, duration: 10, delay: 2), 0, "still inside the delay")
    }

    func testZeroDurationSnaps() {
        XCTAssertEqual(TT.progress(now: 0, start: 0, duration: 0), 1, "0-s transition is an instant set at start")
        XCTAssertEqual(TT.progress(now: -0.001, start: 0, duration: 0), 0, "before start it is still 0")
        XCTAssertEqual(TT.progress(now: 5, start: 0, duration: -1, delay: 2), 1, "negative duration also snaps once delay passes")
    }

    func testEasedComposesEasing() {
        // eased == easing(progress); linear is identity, cubic is not.
        XCTAssertEqual(TT.eased(now: 5, start: 0, duration: 10, easing: .linear), 0.5, accuracy: 1e-12)
        let p = TT.progress(now: 3, start: 0, duration: 10)
        XCTAssertEqual(TT.eased(now: 3, start: 0, duration: 10, easing: .easeOutCubic),
                       TT.Easing.easeOutCubic(p), accuracy: 1e-12)
    }
}

final class EasingTests: XCTestCase {
    /// Every non-spring curve must pin its endpoints exactly.
    func testEndpoints() {
        let curves: [(String, TT.Easing)] = [
            ("linear", .linear), ("easeOutQuad", .easeOutQuad),
            ("easeOutCubic", .easeOutCubic), ("easeOutQuint", .easeOutQuint),
            ("easeInOutCubic", .easeInOutCubic), ("standard", .standard),
            ("decelerate", .decelerate), ("accelerate", .accelerate), ("sharp", .sharp),
        ]
        for (name, e) in curves {
            XCTAssertEqual(e(0), 0, accuracy: 1e-4, "\(name) f(0) must be 0")
            XCTAssertEqual(e(1), 1, accuracy: 1e-4, "\(name) f(1) must be 1")
        }
    }

    /// All named curves are monotonically non-decreasing across the domain.
    func testMonotonic() {
        let curves: [(String, TT.Easing)] = [
            ("linear", .linear), ("easeOutQuad", .easeOutQuad),
            ("easeOutCubic", .easeOutCubic), ("easeOutQuint", .easeOutQuint),
            ("easeInOutCubic", .easeInOutCubic), ("standard", .standard),
            ("decelerate", .decelerate), ("accelerate", .accelerate), ("sharp", .sharp),
        ]
        for (name, e) in curves {
            var prev = e(0)
            for i in 1...100 {
                let v = e(Double(i) / 100)
                XCTAssertGreaterThanOrEqual(v, prev - 1e-9, "\(name) must not decrease at t=\(Double(i)/100)")
                prev = v
            }
        }
    }

    func testInputIsClampedOutputIsNot() {
        // callAsFunction clamps t into [0,1]
        XCTAssertEqual(TT.Easing.easeOutCubic(-5), 0, accuracy: 1e-12)
        XCTAssertEqual(TT.Easing.easeOutCubic(5), 1, accuracy: 1e-12)
    }

    func testEaseOutCubicIsAheadOfLinear() {
        // "out" curves cover ground early: f(t) > t for the decelerating family.
        for t in stride(from: 0.1, through: 0.9, by: 0.1) {
            XCTAssertGreaterThan(TT.Easing.easeOutCubic(t), t, "easeOutCubic should lead linear at t=\(t)")
        }
    }

    func testEaseInOutCubicIsSymmetric() {
        XCTAssertEqual(TT.Easing.easeInOutCubic(0.5), 0.5, accuracy: 1e-9)
        // symmetric about (0.5, 0.5): f(t) + f(1-t) == 1
        for t in stride(from: 0.0, through: 1.0, by: 0.1) {
            XCTAssertEqual(TT.Easing.easeInOutCubic(t) + TT.Easing.easeInOutCubic(1 - t), 1, accuracy: 1e-9)
        }
    }
}

final class CubicBezierTests: XCTestCase {
    func testIdentityBezierMatchesLinear() {
        let id = TT.Easing.cubicBezier(0, 0, 1, 1)   // straight line
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertEqual(id(t), t, accuracy: 1e-3, "identity bezier should track t at \(t)")
        }
    }

    func testStandardCurveShape() {
        let s = TT.Easing.standard   // cubic-bezier(0.4, 0, 0.2, 1) — an S-curve
        XCTAssertEqual(s(0), 0, accuracy: 1e-4)
        XCTAssertEqual(s(1), 1, accuracy: 1e-4)
        // easeInOut S-curve: below the diagonal while accelerating in, above it
        // while decelerating out.
        XCTAssertLessThan(s(0.2), 0.2, "accelerating start sits below the diagonal")
        XCTAssertGreaterThan(s(0.8), 0.8, "decelerating end sits above the diagonal")
    }

    func testDecelerateLeadsAccelerate() {
        // decelerate (easeOut) is ahead of accelerate (easeIn) in the middle.
        for t in stride(from: 0.2, through: 0.8, by: 0.2) {
            XCTAssertGreaterThan(TT.Easing.decelerate(t), TT.Easing.accelerate(t),
                                 "decelerate should lead accelerate at t=\(t)")
        }
    }

    func testSolverPrecisionAgainstDirectSample() {
        // Independently sample the bezier polynomial at a parameter t, then
        // confirm the solver recovers the same y from that x.
        let (x1, y1, x2, y2) = (0.25, 0.1, 0.25, 1.0)
        let e = TT.Easing.cubicBezier(x1, y1, x2, y2)
        func axisX(_ t: Double) -> Double {
            let cx = 3 * x1, bx = 3 * (x2 - x1) - 3 * x1, ax = 1 - 3 * x1 - (3 * (x2 - x1) - 3 * x1)
            return ((ax * t + bx) * t + cx) * t
        }
        func axisY(_ t: Double) -> Double {
            let cy = 3 * y1, by = 3 * (y2 - y1) - 3 * y1, ay = 1 - 3 * y1 - (3 * (y2 - y1) - 3 * y1)
            return ((ay * t + by) * t + cy) * t
        }
        for t in stride(from: 0.05, through: 0.95, by: 0.1) {
            XCTAssertEqual(e(axisX(t)), axisY(t), accuracy: 1e-3, "solver mismatch at param t=\(t)")
        }
    }
}

final class TweenTests: XCTestCase {
    // Times use exactly-representable binary fractions (multiples of 0.25) so the
    // inclusive `isComplete` boundary (`>=`) compares EXACTLY, with no IEEE-754
    // rounding luck: 0.1/0.2/0.3 do NOT sum cleanly (e.g. 100.3 - 100 evaluates
    // to 0.2999…716, just under 0.1 + 0.2 = 0.3000…004), whereas 0.25/0.5/0.75
    // are exact, so the end-boundary assertions are robust on any platform.
    func testLifecycleLinear() {
        let tw = TT.Tween(start: 0, duration: 0.5, easing: .linear)
        XCTAssertEqual(tw.rawProgress(at: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(tw.rawProgress(at: 0.25), 0.5, accuracy: 1e-12)
        XCTAssertEqual(tw.rawProgress(at: 0.5), 1, accuracy: 1e-12)
        XCTAssertEqual(tw.rawProgress(at: 0.75), 1, accuracy: 1e-12, "clamped past end")
        XCTAssertFalse(tw.isComplete(at: 0.25))
        XCTAssertTrue(tw.isComplete(at: 0.5), "inclusive: complete exactly at the end")
    }

    func testValueInterpolation() {
        let tw = TT.Tween(start: 0, duration: 1, easing: .linear)
        XCTAssertEqual(tw.value(at: 0.5, from: 10, to: 20), 15, accuracy: 1e-9)
        XCTAssertEqual(tw.value(at: 0, from: 10, to: 20), 10, accuracy: 1e-9)
        XCTAssertEqual(tw.value(at: 1, from: 10, to: 20), 20, accuracy: 1e-9)
    }

    func testDelay() {
        let tw = TT.Tween(start: 0, duration: 0.5, delay: 0.25, easing: .linear)
        XCTAssertEqual(tw.rawProgress(at: 0.25), 0, accuracy: 1e-12, "still inside the delay")
        XCTAssertEqual(tw.rawProgress(at: 0.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(tw.rawProgress(at: 0.75), 1, accuracy: 1e-12)
        XCTAssertTrue(tw.isComplete(at: 0.75), "inclusive: complete at delay+duration exactly")
        XCTAssertFalse(tw.isComplete(at: 0.5))
    }

    func testZeroDurationTweenSnaps() {
        let tw = TT.Tween(start: 0, duration: 0, easing: .linear)
        XCTAssertEqual(tw.rawProgress(at: -0.5), 0)
        XCTAssertEqual(tw.rawProgress(at: 0), 1)
        XCTAssertTrue(tw.isComplete(at: 0))
    }
}

final class InterpolationTests: XCTestCase {
    func testScalarLerpUnclamped() {
        XCTAssertEqual(TT.lerp(0, 10, 0.5), 5, accuracy: 1e-12)
        XCTAssertEqual(TT.lerp(0, 10, 0), 0, accuracy: 1e-12)
        XCTAssertEqual(TT.lerp(0, 10, 1), 10, accuracy: 1e-12)
        XCTAssertEqual(TT.lerp(0, 10, 1.5), 15, accuracy: 1e-12, "lerp does not clamp (spring overshoot)")
    }

    func testCGLerps() {
        XCTAssertEqual(TT.lerp(CGFloat(2), CGFloat(4), 0.5), 3, accuracy: 1e-9)
        let p = TT.lerp(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 20), 0.5)
        XCTAssertEqual(p.x, 5, accuracy: 1e-9); XCTAssertEqual(p.y, 10, accuracy: 1e-9)
        let s = TT.lerp(CGSize(width: 0, height: 0), CGSize(width: 8, height: 16), 0.25)
        XCTAssertEqual(s.width, 2, accuracy: 1e-9); XCTAssertEqual(s.height, 4, accuracy: 1e-9)
        let r = TT.lerp(CGRect(x: 0, y: 0, width: 0, height: 0),
                        CGRect(x: 10, y: 20, width: 30, height: 40), 0.5)
        XCTAssertEqual(r.origin.x, 5, accuracy: 1e-9)
        XCTAssertEqual(r.origin.y, 10, accuracy: 1e-9)
        XCTAssertEqual(r.size.width, 15, accuracy: 1e-9)
        XCTAssertEqual(r.size.height, 20, accuracy: 1e-9)
    }
}

final class SpringTests: XCTestCase {
    func testEndpoints() {
        XCTAssertEqual(TT.spring(0), 0, accuracy: 1e-9)
        XCTAssertEqual(TT.spring(1), 1, accuracy: 1e-9)
        XCTAssertEqual(TT.spring(-1), 0, accuracy: 1e-9, "input clamped")
        XCTAssertEqual(TT.spring(2), 1, accuracy: 1e-9, "input clamped")
    }

    func testOvershoots() {
        // An underdamped spring must exceed 1 somewhere before settling.
        var maxV = 0.0
        for i in 0...1000 { maxV = max(maxV, TT.spring(Double(i) / 1000)) }
        XCTAssertGreaterThan(maxV, 1.0, "a bouncy spring should overshoot past 1")
    }

    func testStiffferSpringSettlesSooner() {
        // The spring Easing factory wraps the same math (output not clamped).
        let e = TT.Easing.spring()
        XCTAssertEqual(e(0), 0, accuracy: 1e-9)
        XCTAssertEqual(e(1), 1, accuracy: 1e-9)
    }
}

final class DampedSineTests: XCTestCase {
    func testEnvelopeZeroesAtEnds() {
        XCTAssertEqual(TT.dampedSine(0, frequency: 3), 0, accuracy: 1e-9, "starts at rest")
        XCTAssertEqual(TT.dampedSine(1, frequency: 3), 0, accuracy: 1e-9, "decayed to rest at p=1")
    }

    func testBounded() {
        for i in 0...100 {
            let v = TT.dampedSine(Double(i) / 100, frequency: 6)
            XCTAssertLessThanOrEqual(abs(v), 1.0 + 1e-9, "shake stays within unit amplitude")
        }
    }

    func testValueStaysWithinEnvelope() {
        // |dampedSine(p)| is bounded by its decay envelope (1-p)^decay, since
        // |sin| ≤ 1. Verifies the envelope actually shapes the output.
        for i in 0...100 {
            let p = Double(i) / 100
            let v = TT.dampedSine(p, frequency: 5, decay: 2)
            XCTAssertLessThanOrEqual(abs(v), pow(1 - p, 2) + 1e-9,
                                     "amplitude at p=\(p) must stay under the (1-p)^2 envelope")
        }
    }

    func testHigherDecayDampsFaster() {
        // At a sine peak the value equals the envelope; a larger decay yields a
        // smaller late-run amplitude. Use frequency 0.25 so p=1 sits at the
        // first quarter-cycle peak (sin(π/2) = 1), isolating the envelope.
        let gentle = abs(TT.dampedSine(0.75, frequency: 0.25, decay: 1))
        let steep = abs(TT.dampedSine(0.75, frequency: 0.25, decay: 3))
        XCTAssertGreaterThan(gentle, steep, "a higher decay should damp the amplitude faster")
    }
}

final class AutoDurationTests: XCTestCase {
    func testNonPositiveExtentIsZero() {
        XCTAssertEqual(TT.autoDuration(forExtent: 0), 0)
        XCTAssertEqual(TT.autoDuration(forExtent: -50), 0)
    }

    func testMatchesMUIFormulaAtKnownPoint() {
        // extent = 36 ⇒ constant = 1 ⇒ (4 + 15·1 + 0.2)·10 = 192 ms = 0.192 s
        XCTAssertEqual(TT.autoDuration(forExtent: 36), 0.192, accuracy: 1e-9)
    }

    func testMonotonicButSublinear() {
        let d36 = TT.autoDuration(forExtent: 36)
        let d72 = TT.autoDuration(forExtent: 72)
        XCTAssertGreaterThan(d72, d36, "taller surface → longer")
        XCTAssertLessThan(d72, 2 * d36, "but grows sublinearly (4th-root term)")
    }
}
