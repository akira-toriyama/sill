// Trail — the shared PATH-GEOMETRY primitives for the family (wand's gesture
// trail, generalized). NOT an f(now) effect — pure geometry the family
// re-implements when it has to lay marks along, or round the corners of, a
// polyline. Two pure functions plus a tiny AppKit path builder:
//
//   * `resampleAlongPolyline` — the arc-length WALKER (wand's `walkPath`):
//     march a polyline emitting a point + unit-tangent every `interval` points,
//     carrying the leftover across segment joins, with an optional `trimTail`
//     cutoff. The single most reusable piece of wand's trail — it drives every
//     "marks along a path" style (pixel / ascii / arrow-chain / paws / chomp
//     pellets). Pure, `Double`/`(x:y:)` tuples, no AppKit.
//   * `roundedCornerPath` — soften a polyline's interior corners (wand's
//     `buildHybridPath` straight part): each corner is cut back by `radius`
//     (capped to half each adjacent segment so tight corners never overshoot)
//     and bridged by a quadratic. Returns a pure `[PathStep]` description.
//   * `nsBezierPath(_:)` — (AppKit-gated) turn a `[PathStep]` into an
//     `NSBezierPath` to stroke/fill, the `drawLinePets` precedent.
//
// PHILOSOPHY — same split as the rest of Effects: the geometry is pure +
// `Sendable`; the `NSBezierPath` materialization is behind `#if canImport`.
// Coordinate-agnostic (no gravity / no `+y` convention): it just resamples and
// rounds whatever polyline the caller passes, in the caller's own space.

import Foundation

// MARK: - Arc-length resampler (wand's walkPath, as a pure function)

/// One resampled mark: a point on the polyline and the UNIT tangent (travel
/// direction) there — enough to place + orient a glyph (a chevron, a paw, a
/// pellet). Pure value.
public struct TrailMark: Sendable, Equatable {
    public let point: (x: Double, y: Double)
    public let tangent: (x: Double, y: Double)

    public init(point: (x: Double, y: Double), tangent: (x: Double, y: Double)) {
        self.point = point
        self.tangent = tangent
    }

    public static func == (a: TrailMark, b: TrailMark) -> Bool {
        a.point == b.point && a.tangent == b.tangent
    }
}

/// March `points` and return a mark every `interval` points of ARC LENGTH,
/// each carrying the local unit-tangent. The first point is always emitted
/// (oriented along the first non-zero segment, or `(1,0)` if none); the LAST
/// point is emitted too — UNLESS `trimTail > 0`, which stops the walk that
/// much distance short of the end (wand's Chomp gap, so the head leads the
/// trail) and emits the exact cutoff point instead of the final one.
///
/// Faithful port of wand's `walkPath`: leftover distance `carry`s across
/// segment joins so the spacing stays uniform through corners. Returns `[]`
/// for `interval <= 0`, no points, or a `trimTail` longer than the whole path.
public func resampleAlongPolyline(
    _ points: [(x: Double, y: Double)],
    interval: Double,
    trimTail: Double = 0
) -> [TrailMark] {
    guard interval > 0, let first = points.first else { return [] }
    if points.count == 1 { return [TrailMark(point: first, tangent: (1, 0))] }

    // Trim cutoff (total length − trimTail), computed once.
    let cutoff: Double?
    if trimTail > 0 {
        var total = 0.0
        for i in 1..<points.count {
            total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        if total <= trimTail { return [] }
        cutoff = total - trimTail
    } else {
        cutoff = nil
    }

    // Leading tangent: peek forward to the first non-zero segment.
    var lastTangent = (x: 1.0, y: 0.0)
    for i in 1..<points.count {
        let dx = points[i].x - points[i - 1].x, dy = points[i].y - points[i - 1].y
        let len = hypot(dx, dy)
        if len > 0 { lastTangent = (x: dx / len, y: dy / len); break }
    }

    var marks = [TrailMark(point: first, tangent: lastTangent)]
    var carry = 0.0      // distance already consumed into the next interval
    var traveled = 0.0   // total arc length walked so far
    for i in 1..<points.count {
        let a = points[i - 1], b = points[i]
        let dx = b.x - a.x, dy = b.y - a.y
        let segLen = hypot(dx, dy)
        if segLen <= 0 { continue }
        let ux = dx / segLen, uy = dy / segLen
        lastTangent = (x: ux, y: uy)
        var t = interval - carry
        while t <= segLen {
            if let cutoff, traveled + t > cutoff {
                let tEnd = t - (traveled + t - cutoff)
                marks.append(TrailMark(point: (x: a.x + ux * tEnd, y: a.y + uy * tEnd),
                                       tangent: lastTangent))
                return marks
            }
            marks.append(TrailMark(point: (x: a.x + ux * t, y: a.y + uy * t),
                                   tangent: lastTangent))
            t += interval
        }
        traveled += segLen
        carry = segLen - (t - interval)
    }
    // Cap with the final point (the trail head) when not trimming — but only
    // if it isn't already the last emitted mark (when `interval` divides the
    // length evenly the loop already lands on the end; wand double-emits it,
    // we don't — a duplicate head glyph is just two stacked marks).
    if cutoff == nil, let last = points.last, marks[marks.count - 1].point != last {
        marks.append(TrailMark(point: last, tangent: lastTangent))
    }
    return marks
}

// MARK: - Rounded-corner path (wand's buildHybridPath, as a pure description)

/// One step of a pure path description — the cross-platform analog of the few
/// `NSBezierPath` calls the trail builds. `quadCurve` is a quadratic (one
/// control point), matching wand's `curve(to:controlPoint1:B controlPoint2:B)`.
public enum PathStep: Sendable, Equatable {
    case move(x: Double, y: Double)
    case line(x: Double, y: Double)
    case quadCurve(x: Double, y: Double, cx: Double, cy: Double)
}

/// Round the interior corners of the polyline `points`: each corner `B` is cut
/// back to `P` (entering) and `Q` (leaving) by `radius` — capped to half each
/// adjacent segment so a tight corner can't overshoot — and bridged by a
/// quadratic through `B`. Returns a pure `[PathStep]` (move → line/quadCurve…).
/// Faithful port of wand's `buildHybridPath` straight part (pass `lineWidth*4`
/// as `radius` for wand's look). `< 2` points → just the move (or empty).
public func roundedCornerPath(
    _ points: [(x: Double, y: Double)],
    radius: Double
) -> [PathStep] {
    guard let first = points.first else { return [] }
    var steps: [PathStep] = [.move(x: first.x, y: first.y)]
    if points.count == 2 {
        steps.append(.line(x: points[1].x, y: points[1].y))
    } else if points.count > 2 {
        for i in 1..<(points.count - 1) {
            let a = points[i - 1], b = points[i], c = points[i + 1]
            let inLen = hypot(b.x - a.x, b.y - a.y)
            let outLen = hypot(c.x - b.x, c.y - b.y)
            let r = min(radius, inLen / 2, outLen / 2)
            let inU = (x: (b.x - a.x) / max(inLen, 1), y: (b.y - a.y) / max(inLen, 1))
            let outU = (x: (c.x - b.x) / max(outLen, 1), y: (c.y - b.y) / max(outLen, 1))
            steps.append(.line(x: b.x - inU.x * r, y: b.y - inU.y * r))           // P
            steps.append(.quadCurve(x: b.x + outU.x * r, y: b.y + outU.y * r,     // Q
                                    cx: b.x, cy: b.y))                            // via B
        }
        let last = points[points.count - 1]
        steps.append(.line(x: last.x, y: last.y))
    }
    return steps
}

#if canImport(CoreGraphics)
import CoreGraphics

/// `CGPoint` convenience for `resampleAlongPolyline` (apps work in `CGPoint`).
public func resampleAlongPolyline(
    _ points: [CGPoint], interval: Double, trimTail: Double = 0
) -> [TrailMark] {
    resampleAlongPolyline(points.map { (x: Double($0.x), y: Double($0.y)) },
                          interval: interval, trimTail: trimTail)
}

/// `CGPoint` convenience for `roundedCornerPath`.
public func roundedCornerPath(_ points: [CGPoint], radius: Double) -> [PathStep] {
    roundedCornerPath(points.map { (x: Double($0.x), y: Double($0.y)) }, radius: radius)
}
#endif

// MARK: - AppKit path builder (the drawLinePets analog)

#if canImport(AppKit)
import AppKit

/// Build an `NSBezierPath` from a pure `[PathStep]` (round caps/joins, ready to
/// stroke or fill) — the AppKit materialization of `roundedCornerPath`'s
/// output. `quadCurve` becomes a cubic with both control points at the corner,
/// reproducing wand's `curve(to:controlPoint1:cp controlPoint2:cp)` quadratic.
@MainActor
public func nsBezierPath(_ steps: [PathStep], lineWidth: CGFloat = 1) -> NSBezierPath {
    let path = NSBezierPath()
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    for step in steps {
        switch step {
        case let .move(x, y): path.move(to: CGPoint(x: x, y: y))
        case let .line(x, y): path.line(to: CGPoint(x: x, y: y))
        case let .quadCurve(x, y, cx, cy):
            let cp = CGPoint(x: cx, y: cy)
            path.curve(to: CGPoint(x: x, y: y), controlPoint1: cp, controlPoint2: cp)
        }
    }
    return path
}
#endif
