// Motion — easing curves.
//
// An `Easing` is a pure, Sendable `f(t) -> value` over normalized time
// `t ∈ [0,1]`. Unlike a CSS easing (4 control points the browser solves),
// each curve here is DIRECTLY EVALUABLE so the app — which owns the clock —
// samples it per frame. Two flavours, both backed by the same type:
//   * POWER curves (`easeOutCubic`, …) — the workhorses the apps already
//     hand-roll (`1 - pow(1-t, 3)` appears in perch, facet AND wand). Lifted
//     once, named once.
//   * BEZIER curves (`standard`, `decelerate`, …) — the EXACT Material
//     cubic-beziers, solved with the WebKit unit-bezier algorithm, so a
//     consumer that wants the genuine MUI easing gets it to the bit.
//
// `callAsFunction` CLAMPS the input to `[0,1]` (so a slightly-overshot
// `progress` can't read off the curve's defined domain); the OUTPUT is left
// unclamped on purpose — a spring is supposed to overshoot past 1 and settle.

import Foundation

public extension ThemedTransition {
    /// A normalized easing curve: maps eased-time `f(t)` for `t ∈ [0,1]`.
    /// Wraps a `@Sendable (Double) -> Double` so callers can also pass a
    /// custom curve (MUI lets you hand `create()` any cubic-bezier); the
    /// named statics below cover the family's needs. Input is clamped to
    /// `[0,1]`; output is not (springs overshoot).
    struct Easing: Sendable {
        /// The raw transform. Prefer `callAsFunction` (it clamps the input);
        /// this is exposed for composition (e.g. reversing or chaining).
        public let transform: @Sendable (Double) -> Double

        public init(_ transform: @escaping @Sendable (Double) -> Double) {
            self.transform = transform
        }

        /// Evaluate the curve at `t`, clamping `t` into `[0,1]` first.
        public func callAsFunction(_ t: Double) -> Double {
            transform(min(1, max(0, t)))
        }
    }
}

// MARK: - Named curves

public extension ThemedTransition.Easing {
    /// No easing — identity. Constant velocity (a steady sweep / a wave).
    static let linear = Self { $0 }

    // --- Power "out" family (decelerating; the app workhorses) ---

    /// Ease-out quadratic `1 - (1-t)²` — a gentle deceleration (facet's grid
    /// FLIP reorder).
    static let easeOutQuad = Self { let i = 1 - $0; return 1 - i * i }

    /// Ease-out cubic `1 - (1-t)³` — THE family default for moving things:
    /// snappy start, soft landing. The single most duplicated curve (perch
    /// match/translate, facet rail/commit-zoom, wand badge/chomp/HUD).
    static let easeOutCubic = Self { let i = 1 - $0; return 1 - i * i * i }

    /// Ease-out quintic `1 - (1-t)⁵` — a sharper, snappier "キレ" landing than
    /// cubic (facet's window-move).
    static let easeOutQuint = Self {
        let i = 1 - $0; return 1 - i * i * i * i * i
    }

    // --- Power "in-out" (accelerate then decelerate; silky both ends) ---

    /// Ease-in-out cubic — eased at BOTH ends for a "silky" feel where the
    /// object starts and ends at rest (facet's window-move alt).
    static let easeInOutCubic = Self { t in
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    // --- Material cubic-bezier curves (exact, solved per frame) ---

    /// Material STANDARD curve `cubic-bezier(0.4, 0, 0.2, 1)` = MUI's
    /// `easeInOut`, the web default. Objects that begin and end at rest.
    static let standard = cubicBezier(0.4, 0, 0.2, 1)
    /// Material DECELERATE `cubic-bezier(0, 0, 0.2, 1)` = MUI `easeOut`. An
    /// element ENTERING at full velocity, easing to rest.
    static let decelerate = cubicBezier(0, 0, 0.2, 1)
    /// Material ACCELERATE `cubic-bezier(0.4, 0, 1, 1)` = MUI `easeIn`. An
    /// element LEAVING from rest, accelerating off-screen.
    static let accelerate = cubicBezier(0.4, 0, 1, 1)
    /// Material SHARP `cubic-bezier(0.4, 0, 0.6, 1)` = MUI `sharp`. For an
    /// object that may return to screen (a temporary slide-off).
    static let sharp = cubicBezier(0.4, 0, 0.6, 1)

    /// An underdamped SPRING as an easing — overshoots past 1 and settles
    /// (input clamped, output intentionally not). See `ThemedTransition.spring`
    /// for the math + parameter meaning.
    static func spring(zeta: Double = 0.55, omega: Double = 9.0) -> Self {
        Self { ThemedTransition.spring($0, zeta: zeta, omega: omega) }
    }

    /// An easing from arbitrary cubic-bezier control points `(x1,y1)`,
    /// `(x2,y2)` with the implicit anchors `(0,0)` and `(1,1)` — the same
    /// parameterization as CSS `cubic-bezier()` / `CAMediaTimingFunction`.
    /// Solves `x(t) = input` for the bezier parameter `t` (Newton–Raphson
    /// with a bisection fallback, the WebKit `UnitBezier` algorithm), then
    /// returns `y(t)`. Exact, allocation-free, evaluated each frame.
    static func cubicBezier(_ x1: Double, _ y1: Double,
                            _ x2: Double, _ y2: Double) -> Self {
        let curve = UnitBezier(x1: x1, y1: y1, x2: x2, y2: y2)
        return Self { curve.solve($0) }
    }
}

// MARK: - Unit cubic bezier solver

/// A cubic bezier through `(0,0)`, `(x1,y1)`, `(x2,y2)`, `(1,1)`, solved as
/// `y` for a given `x` — the standard WebKit `UnitBezier`. Value type, so the
/// `Easing` closure that captures it stays `Sendable`. Coefficients are the
/// expanded Bernstein polynomial (P0 at origin, P3 at (1,1)).
struct UnitBezier: Sendable {
    private let ax, bx, cx: Double
    private let ay, by, cy: Double

    init(x1: Double, y1: Double, x2: Double, y2: Double) {
        cx = 3 * x1
        bx = 3 * (x2 - x1) - cx
        ax = 1 - cx - bx
        cy = 3 * y1
        by = 3 * (y2 - y1) - cy
        ay = 1 - cy - by
    }

    private func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
    private func sampleDX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

    /// `y` at a given `x ∈ [0,1]`.
    func solve(_ x: Double, epsilon: Double = 1e-6) -> Double {
        sampleY(solveForT(x, epsilon: epsilon))
    }

    /// Find the bezier parameter `t` whose `x(t) == x`.
    private func solveForT(_ x: Double, epsilon: Double) -> Double {
        // Fast path: Newton–Raphson from `x` as the initial guess.
        var t = x
        for _ in 0..<8 {
            let xError = sampleX(t) - x
            if abs(xError) < epsilon { return t }
            let dx = sampleDX(t)
            if abs(dx) < 1e-9 { break }
            t -= xError / dx
        }
        // Fallback: bisection over `[0,1]` (guaranteed to converge).
        var lo = 0.0, hi = 1.0
        t = x
        if t < lo { return lo }
        if t > hi { return hi }
        while lo < hi {
            let xValue = sampleX(t)
            if abs(xValue - x) < epsilon { return t }
            if x > xValue { lo = t } else { hi = t }
            t = (hi - lo) * 0.5 + lo
        }
        return t
    }
}
