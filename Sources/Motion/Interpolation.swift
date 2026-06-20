// Motion — interpolation + physical motion primitives.
//
//   * `lerp` — the linear blend `a + (b-a)·t`. Scalar `Double` is pure; the
//     `CGFloat`/`CGPoint`/`CGSize`/`CGRect` overloads (behind
//     `#if canImport(CoreGraphics)`) cover the geometry tweens the apps
//     re-implement field-by-field (facet's `frame(atEased:)`, commit-zoom and
//     grid FLIP rect lerps, wand's cursor-point lerp).
//   * `spring` — facet's underdamped step response, lifted verbatim (it was
//     already the family's best spring). The single source for "bouncy".
//   * `dampedSine` — perch's and wand's shake/vibrate decay, generalized: a
//     sine that fades to nothing over the run. Compose two (different
//     frequencies) for a 2-D Lissajous buzz.
//
// All pure functions of their inputs — no clock, no state.

import Foundation

public extension ThemedTransition {
    /// Linear interpolation `a + (b - a) · t`. `t` is NOT clamped — pass an
    /// eased `0…1` (or a spring's overshoot) and it extrapolates accordingly.
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    /// An underdamped SPRING step response `0 → 1` with overshoot-and-settle
    /// — the "弾む" landing. `t ∈ [0,1]` is clamped; the return rises past 1,
    /// rings, and settles back to 1. `zeta` is the damping ratio (clamped
    /// `0.2…0.95`; lower = bouncier) and `omega` the angular frequency
    /// (higher = faster settle). Lifted from facet's `SlideAnimation.spring`
    /// so every app's spring is bit-identical.
    static func spring(_ t: Double, zeta: Double = 0.55, omega: Double = 9.0) -> Double {
        let c = min(1, max(0, t))
        if c >= 1 { return 1 }
        let z = min(0.95, max(0.2, zeta))
        let wd = omega * (1 - z * z).squareRoot()
        return 1 - exp(-z * omega * c)
            * (cos(wd * c) + (z * omega / wd) * sin(wd * c))
    }

    /// A decaying sinusoid for shake / vibrate: `sin(2π·frequency·p)` enveloped
    /// by `(1 - p)^decay`, so it oscillates `frequency` times over the run and
    /// fades to 0 at `p = 1`. Returns roughly `[-1, 1]` — the app multiplies by
    /// a pixel amplitude. `p ∈ [0,1]` is clamped. The shared form of perch's
    /// `amplitude · sin(2π·3·p) · (1-p)` and wand's panic-jitter; for a 2-D
    /// buzz call it twice with co-prime frequencies (e.g. 6 and 7) on x / y.
    static func dampedSine(_ p: Double, frequency: Double, decay: Double = 1) -> Double {
        let c = min(1, max(0, p))
        let envelope = pow(1 - c, max(0, decay))
        return sin(2 * .pi * frequency * c) * envelope
    }
}

#if canImport(CoreGraphics)
import CoreGraphics

public extension ThemedTransition {
    /// Linear interpolation for `CGFloat` (geometry-axis blend).
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    /// Component-wise point lerp — a cursor / anchor gliding `a → b`.
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t))
    }

    /// Component-wise size lerp.
    static func lerp(_ a: CGSize, _ b: CGSize, _ t: CGFloat) -> CGSize {
        CGSize(width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
    }

    /// Component-wise rect lerp (origin + size) — a thumbnail / cell tweening
    /// from one frame to another (facet's reorder + commit-zoom in one call).
    static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(origin: lerp(a.origin, b.origin, t), size: lerp(a.size, b.size, t))
    }
}
#endif
