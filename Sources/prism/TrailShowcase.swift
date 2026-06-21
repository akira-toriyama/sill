// prism — the LIVE trail-geometry bench.
//
// `Effects`' trail primitives (`resampleAlongPolyline` + `roundedCornerPath`)
// are pure geometry, so — like the Motion bench — the way to PROVE them is to
// DRIVE them: a fixed zig-zag polyline is (a) corner-ROUNDED and stroked, and
// (b) RESAMPLED into evenly-spaced chevrons that point along the local tangent.
// A `TimelineView` clock walks a highlight through the marks so the resampler's
// uniform spacing + tangent orientation read at a glance — the same primitives
// wand lays its trail glyphs (pixel / ascii / arrow / paws / chomp) with.
//
// Drawn in a SwiftUI `Canvas` straight off the PURE functions (the load-bearing
// API), exactly as the Motion bench plots off the pure easings.

import SwiftUI
import Palette
import PaletteKit
import Effects

private let trailLoopSeconds: Double = 2.4

/// A fixed zig-zag in unit coordinates (0…1), scaled to the canvas — enough
/// corners to show the rounding + the resampling through joins.
private let trailUnitPoints: [(x: Double, y: Double)] = [
    (0.05, 0.55), (0.28, 0.15), (0.50, 0.85), (0.72, 0.20), (0.95, 0.6),
]

struct MockTrail: View {
    let p: ResolvedPalette

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let phase = now.truncatingRemainder(dividingBy: trailLoopSeconds) / trailLoopSeconds
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 5) {
                    Text("Effects · trail geometry — roundedCornerPath + resampleAlongPolyline (chevrons follow the tangent)")
                        .font(sysFont(9, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(nsColor: p.muted))
                    liveDot
                }
                Canvas { ctx, size in draw(ctx, size, phase: phase) }
                    .frame(height: 150 * uiScale)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: p.background ?? .underPageBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .stroke(Color(nsColor: p.border), lineWidth: 1))
                Text("rounded corners (radius = 4·width, capped to ½ each leg) · marks every 24pt with unit-tangent")
                    .font(sysFont(7.5, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.muted))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: p.background ?? .underPageBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: p.border), lineWidth: 1))
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, phase: Double) {
        let pad = 16.0 * Double(uiScale)
        let w = Double(size.width) - 2 * pad, h = Double(size.height) - 2 * pad
        guard w > 1, h > 1 else { return }
        let pts = trailUnitPoints.map { (x: pad + $0.x * w, y: pad + $0.y * h) }

        // (a) The corner-rounded path — built from the PURE PathStep list.
        let steps = roundedCornerPath(pts, radius: 4 * 2.5)
        var path = Path()
        for step in steps {
            switch step {
            case let .move(x, y): path.move(to: CGPoint(x: x, y: y))
            case let .line(x, y): path.addLine(to: CGPoint(x: x, y: y))
            case let .quadCurve(x, y, cx, cy):
                path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
            }
        }
        ctx.stroke(path, with: .color(Color(nsColor: p.primary).opacity(0.45)),
                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

        // (b) Resampled chevrons — evenly spaced, oriented along the tangent.
        let marks = resampleAlongPolyline(pts, interval: 24)
        guard !marks.isEmpty else { return }
        let live = Int(phase * Double(marks.count)) % marks.count
        let accent = Color(nsColor: p.primary), second = Color(nsColor: p.secondary)
        for (i, m) in marks.enumerated() {
            let isLive = i == live
            chevron(ctx, at: m, scale: isLive ? 1.8 : 1.0,
                    color: isLive ? accent : second.opacity(0.9), glow: isLive)
        }
    }

    /// A small filled chevron at `m.point`, apex pointing along `m.tangent`.
    private func chevron(_ ctx: GraphicsContext, at m: TrailMark, scale: Double,
                         color: Color, glow: Bool) {
        let L = 5.0 * Double(uiScale) * scale          // half-length along tangent
        let W = 3.6 * Double(uiScale) * scale          // half-width across
        let t = m.tangent, n = (x: -t.y, y: t.x)       // tangent + normal
        let px = m.point.x, py = m.point.y
        func pt(_ a: Double, _ b: Double) -> CGPoint {
            CGPoint(x: px + t.x * a + n.x * b, y: py + t.y * a + n.y * b)
        }
        var tri = Path()
        tri.move(to: pt(L, 0))         // apex (forward)
        tri.addLine(to: pt(-L, W))     // back-left
        tri.addLine(to: pt(-L, -W))    // back-right
        tri.closeSubpath()
        var c = ctx
        if glow { c.addFilter(.shadow(color: color, radius: 4)) }
        c.fill(tri, with: .color(color))
    }

    private var liveDot: some View {
        let accent = Color(nsColor: p.primary)
        return HStack(spacing: 3) {
            Circle().fill(accent).frame(width: 6 * uiScale, height: 6 * uiScale)
                .shadow(color: accent, radius: 3)
            Text("live").font(sysFont(8, weight: .bold, design: .monospaced))
                .foregroundColor(accent.opacity(0.9))
        }
    }
}
