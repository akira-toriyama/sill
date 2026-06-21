import Foundation

/// One sampled point along a gesture stroke: position + time since the stroke
/// began. `t` is seconds since stroke START (NOT wall-clock) so recognition is
/// reproducible from a fixture. Pure `Double` coordinates keep the module free
/// of CoreGraphics; apps that already work in `CGPoint` use the gated
/// convenience `init(p:t:)` / `p` below.
public struct Sample: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let t: Double
    public init(x: Double, y: Double, t: Double) {
        self.x = x
        self.y = y
        self.t = t
    }
}

extension Array where Element == Sample {
    /// Largest absolute displacement from the FIRST sample on each axis.
    /// Diagnostic for "why was nothing recognised" — a tiny span means the
    /// user barely moved.
    public var span: (dx: Double, dy: Double) {
        guard let first = first else { return (0, 0) }
        var dx = 0.0, dy = 0.0
        for s in self {
            dx = Swift.max(dx, abs(s.x - first.x))
            dy = Swift.max(dy, abs(s.y - first.y))
        }
        return (dx, dy)
    }
}

#if canImport(CoreGraphics)
import CoreGraphics

extension Sample {
    /// `CGPoint` / `TimeInterval` convenience for apps working in CoreGraphics
    /// (the Trail.swift / Splatter.swift gated-overload idiom). The core stores
    /// plain `Double`, so this only adds an entry point — it doesn't pull
    /// CoreGraphics into the pure layer.
    public init(p: CGPoint, t: TimeInterval) {
        self.init(x: Double(p.x), y: Double(p.y), t: Double(t))
    }
    /// The sample position as a `CGPoint` (apps stroke / hit-test in CG space).
    public var p: CGPoint { CGPoint(x: x, y: y) }
}
#endif
