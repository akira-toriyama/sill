// prism — the LIVE Motion bench.
//
// `Motion` (the `ThemedTransition` namespace) is pure MATH, not a widget, so
// it can't be "drawn" like a ThemedButton. The way to PROVE it works is to
// drive it: a `TimelineView` clock loops a normalized phase 0→1, and we sample
// every named easing each frame to (a) PLOT its curve with a running marker and
// (b) race a PILL across a track. Differences between `easeOutCubic`,
// `standard`, and a `spring` (which overshoots past the track end and settles)
// are then visible at a glance — the same curves the apps animate with.
//
// Theme-tinted: the plot stroke + pill are the card's `primary`, so the bench
// reads each easing in every theme's palette, exactly like the widget families.

import SwiftUI
import Palette
import PaletteKit
import Motion

/// Seconds for one full demo loop — slow enough to read the curve's pacing.
private let motionLoopSeconds: Double = 1.8

/// The easings demoed, in rough "gentle → snappy → bouncy" order.
private let demoEasings: [(name: String, easing: ThemedTransition.Easing)] = [
    ("linear", .linear),
    ("easeOutCubic", .easeOutCubic),
    ("easeOutQuint", .easeOutQuint),
    ("easeInOutCubic", .easeInOutCubic),
    ("standard", .standard),
    ("spring", .spring()),
]

// MARK: - The live mock (wired into Gallery's `.motion` family)

/// The whole Motion specimen for one theme card: a row of easing-curve plots,
/// a stack of pill tracks racing under those curves, and the Duration-token
/// legend — all on ONE 60 Hz clock so they stay in lockstep.
struct MockMotion: View {
    let p: ResolvedPalette

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let phase = now.truncatingRemainder(dividingBy: motionLoopSeconds) / motionLoopSeconds
            VStack(alignment: .leading, spacing: 10) {
                // Curve plots — the shape of each easing, with a live marker.
                HStack(alignment: .top, spacing: 8) {
                    ForEach(demoEasings, id: \.name) { item in
                        EasingPlot(name: item.name, easing: item.easing, phase: phase, p: p)
                    }
                    liveDot
                }
                // Pill tracks — the SAME easings driving real travel.
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(demoEasings, id: \.name) { item in
                        PillTrack(name: item.name, easing: item.easing, phase: phase, p: p)
                    }
                }
                DurationLegend(p: p)
            }
        }
    }

    /// A small glowing "● live" tag — proof the bench is moving (a screenshot
    /// catches one frame).
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

// MARK: - One easing-curve plot

/// Plots `easing` as `y = f(t)` over a small square (with the linear diagonal +
/// the 0/1 guide lines for reference) and a running marker at the current
/// `phase`. The y-axis spans a little above 1 / below 0 so a spring's overshoot
/// shows instead of clipping.
private struct EasingPlot: View {
    let name: String
    let easing: ThemedTransition.Easing
    let phase: Double
    let p: ResolvedPalette

    var body: some View {
        let accent = Color(nsColor: p.primary)
        let muted = Color(nsColor: p.muted)
        let border = Color(nsColor: p.border)
        VStack(spacing: 3) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let yMin = -0.15, yMax = 1.28           // headroom for spring overshoot
                func px(_ t: Double) -> CGFloat { CGFloat(t) * w }
                func py(_ v: Double) -> CGFloat { CGFloat((yMax - v) / (yMax - yMin)) * h }

                // 0 and 1 guide lines (dashed).
                var guides = Path()
                guides.move(to: CGPoint(x: 0, y: py(0))); guides.addLine(to: CGPoint(x: w, y: py(0)))
                guides.move(to: CGPoint(x: 0, y: py(1))); guides.addLine(to: CGPoint(x: w, y: py(1)))
                ctx.stroke(guides, with: .color(border),
                           style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))

                // Linear diagonal reference.
                var diag = Path()
                diag.move(to: CGPoint(x: px(0), y: py(0)))
                diag.addLine(to: CGPoint(x: px(1), y: py(1)))
                ctx.stroke(diag, with: .color(muted.opacity(0.45)), lineWidth: 0.5)

                // The easing curve.
                var curve = Path()
                curve.move(to: CGPoint(x: px(0), y: py(easing(0))))
                let steps = 64
                for i in 1...steps {
                    let t = Double(i) / Double(steps)
                    curve.addLine(to: CGPoint(x: px(t), y: py(easing(t))))
                }
                ctx.stroke(curve, with: .color(accent), lineWidth: 1.5)

                // Live marker riding the curve.
                let mx = px(phase), my = py(easing(phase))
                ctx.fill(Path(ellipseIn: CGRect(x: mx - 2.5, y: my - 2.5, width: 5, height: 5)),
                         with: .color(accent))
            }
            .frame(width: 60 * uiScale, height: 50 * uiScale)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(p.background.map { Color(nsColor: $0) } ?? Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(border, lineWidth: 1))

            Text(name)
                .font(sysFont(7.5, design: .monospaced))
                .foregroundColor(muted)
                .lineLimit(1).minimumScaleFactor(0.55).frame(width: 60 * uiScale)
        }
    }
}

// MARK: - One pill track

/// A labelled track with a pill at `easing(phase)` along its length — the
/// easing translated into real travel. The spring's overshoot rides slightly
/// past the end and settles back.
private struct PillTrack: View {
    let name: String
    let easing: ThemedTransition.Easing
    let phase: Double
    let p: ResolvedPalette

    var body: some View {
        HStack(spacing: 7) {
            Text(name)
                .font(sysFont(8, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
                .frame(width: 78 * uiScale, alignment: .leading)
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let pillW: CGFloat = 16 * uiScale
                // Track rail.
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: h / 2 - 1.5, width: w, height: 3),
                              cornerSize: CGSize(width: 1.5, height: 1.5)),
                         with: .color(Color(nsColor: p.muted).opacity(0.25)))
                // Pill — eased position; clamped to the rail so it can't clip out.
                let e = easing(phase)
                let x = max(0, min(w - pillW, CGFloat(e) * (w - pillW)))
                ctx.fill(Path(roundedRect: CGRect(x: x, y: h / 2 - 6, width: pillW, height: 12),
                              cornerSize: CGSize(width: 6, height: 6)),
                         with: .color(Color(nsColor: p.primary)))
            }
            .frame(width: 190 * uiScale, height: 16 * uiScale)
        }
    }
}

// MARK: - Duration-token legend

/// The `ThemedTransition.Duration` ladder, read straight from the tokens (no
/// hard-coded numbers — so the legend can't drift from the library), shown as
/// labelled chips in ascending order.
private struct DurationLegend: View {
    let p: ResolvedPalette

    private var tokens: [(String, TimeInterval)] {
        [("snap", ThemedTransition.Duration.snap),
         ("stagger", ThemedTransition.Duration.staggerStep),
         ("exit", ThemedTransition.Duration.exit),
         ("enter", ThemedTransition.Duration.enter),
         ("move", ThemedTransition.Duration.move),
         ("emphasis", ThemedTransition.Duration.emphasis)]
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Duration")
                .font(sysFont(8, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
            ForEach(tokens, id: \.0) { token in
                HStack(spacing: 3) {
                    Text(token.0)
                        .font(sysFont(8, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(nsColor: p.foreground))
                    Text(String(format: "%.0fms", token.1 * 1000))
                        .font(sysFont(7.5, design: .monospaced))
                        .foregroundColor(Color(nsColor: p.primary))
                }
                .padding(.horizontal, 5).padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: p.border), lineWidth: 1))
            }
        }
    }
}
