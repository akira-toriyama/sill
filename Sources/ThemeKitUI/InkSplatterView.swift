// ThemeKitUI — SwiftUI-native ink-splatter decal bridge
// (`rollSplatter` → `alpha(now:)` → SwiftUI Canvas + Catmull-Rom Path).
//
// GENERAL by design: colours, the stamp `center`/`size` (bounds-relative
// closures), `seed`, `duration` and loop cadence are inputs — an app stamps a
// splat wherever a shot lands (wand decal). prism passes its showcase data and
// gets the same pixels. `frozen` (0…1 of `duration`) freezes one held frame;
// when frozen without an explicit `seed` a stable default keeps it deterministic
// (prism's old fixed-seed capture).
//
// Live mode: `TimelineView(.animation)` drives the Canvas; the splat is a PURE
// derivation of `now` — the cadence index (`floor(now/loopPeriod)`) picks a
// deterministic per-cadence seed (golden-ratio mix), so a new splat rolls each
// cadence and is stable within it, with NO state mutation during render (the
// f(now)/replayable contract). Frozen mode: no TimelineView — one static Canvas
// frame with the stable seed and the frozen fraction.

import SwiftUI
import Effects

public struct InkSplatterView: View {
    /// Birth time — READ only inside the live Canvas/TimelineView closure so the
    /// one-shot and loop branches are birth-anchored (mirrors ParticleBurstView).
    @State private var start = Date()
    public var colors: [UInt32]
    /// Where the splat stamps, from the view's bounds. Default = centre.
    public var center: (CGRect) -> CGPoint
    /// The splat extent in points, from the view's bounds. Default = 0.78·min side.
    public var size: (CGRect) -> Double
    /// Live re-stamp seed. nil = a fresh random splat each cadence.
    public var seed: UInt64?
    public var duration: TimeInterval
    /// nil = stamp ONCE; non-nil = re-stamp every `loopPeriod` seconds.
    public var loopPeriod: Double?
    /// nil = live; non-nil = freeze ONE frame at that fraction (0…1) of `duration`.
    public var frozen: Double?

    /// Stable seed used when a frozen view was given no explicit `seed`, so a
    /// capture is always deterministic (matches prism's old fixed-seed freeze).
    public static let frozenSeedDefault: UInt64 = 0xC0FFEE

    public init(colors: [UInt32],
                seed: UInt64? = nil,
                duration: TimeInterval = 1.4,
                loopPeriod: Double? = nil,
                frozen: Double? = nil,
                center: @escaping (CGRect) -> CGPoint = { CGPoint(x: $0.midX, y: $0.midY) },
                size: @escaping (CGRect) -> Double = { Double(min($0.width, $0.height)) * 0.78 }) {
        self.colors = colors
        self.seed = seed
        self.duration = duration
        self.loopPeriod = loopPeriod
        self.frozen = frozen
        self.center = center
        self.size = size
    }

    public var body: some View {
        if let f = frozen {
            // Static frozen frame — no animation clock needed.
            Canvas { ctx, size in
                let bounds = CGRect(origin: .zero, size: size)
                let c = center(bounds)
                let sz = self.size(bounds)
                let shape = rollSplatter(at: c, size: sz, colors: colors,
                                         seed: seed ?? InkSplatterView.frozenSeedDefault,
                                         now: 0, duration: duration)
                let frozenNow = max(0, min(1, f)) * duration
                drawSplat(shape, now: frozenNow, into: &ctx)
            }
        } else {
            // Live mode — TimelineView drives the animation clock. The stamp is a
            // PURE derivation of `now` (no @State write during render — that's
            // forbidden in SwiftUI). Each cadence rolls a deterministic, replayable
            // splat from a per-cadence seed; the index changes per cadence so the
            // shape varies, but it never re-rolls (and never flickers) within a frame.
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    let startBaseline = start.timeIntervalSinceReferenceDate
                    let bounds = CGRect(origin: .zero, size: size)
                    let c = center(bounds)
                    let sz = self.size(bounds)

                    // Which cadence are we in, and when did it stamp?
                    // Both branches are birth-anchored so one-shot (stampNow = startBaseline)
                    // and loop both measure `now - stampNow` as a small in-range value.
                    let cadenceIndex: UInt64
                    let stampNow: Double
                    if let period = loopPeriod, period > 0 {
                        let elapsed = now - startBaseline
                        cadenceIndex = UInt64(max(0, floor(elapsed / period)))
                        stampNow = startBaseline + Double(cadenceIndex) * period
                    } else {
                        cadenceIndex = 0
                        stampNow = startBaseline
                    }

                    // Deterministic per-cadence seed (no randomness during render).
                    let stampSeed: UInt64
                    if let s = seed {
                        stampSeed = s &+ cadenceIndex &* 0x9E3779B97F4A7C15
                    } else {
                        stampSeed = (cadenceIndex &+ 1) &* 0x9E3779B97F4A7C15
                    }

                    let shape = rollSplatter(at: c, size: sz, colors: colors,
                                             seed: stampSeed, now: stampNow,
                                             duration: duration)
                    // alpha(now:) measures `now - stampNow`, so the fade is correct.
                    drawSplat(shape, now: now, into: &ctx)
                }
            }
        }
    }

    // MARK: - Render helpers

    /// Paint one `SplatterShape` at wall-clock `now` into `ctx`.
    private func drawSplat(_ shape: SplatterShape, now: Double,
                           into ctx: inout GraphicsContext) {
        let a = max(0, min(1, shape.alpha(now: now)))
        guard a > 0 else { return }
        for unit in shape.units {
            // Rim: ink blended 45 % toward black (manual lerp matching AppKit ref
            // `NSColor.black.blended(withFraction: 0.45, of: ink)` — no AppKit).
            let inkR = Double((unit.color >> 16) & 0xFF) / 255
            let inkG = Double((unit.color >> 8)  & 0xFF) / 255
            let inkB = Double( unit.color        & 0xFF) / 255
            let rimColor = Color(.sRGB, red: inkR * 0.45, green: inkG * 0.45, blue: inkB * 0.45,
                                 opacity: 0.78 * a)
            ctx.fill(catmullRom(unit.rim), with: .color(rimColor))
            // Body.
            let inkColor = Color(.sRGB, red: inkR, green: inkG, blue: inkB, opacity: 0.96 * a)
            ctx.fill(catmullRom(unit.body), with: .color(inkColor))
            // Droplet specks.
            let dropColor = Color(.sRGB, red: inkR, green: inkG, blue: inkB, opacity: 0.88 * a)
            for speck in unit.droplets {
                ctx.fill(catmullRom(speck), with: .color(dropColor))
            }
        }
    }

    /// Build a closed, smooth `SwiftUI.Path` through `v` using Catmull-Rom →
    /// cubic-bézier (1/6 tension) — the same smoothing as the AppKit reference.
    private func catmullRom(_ v: [(x: Double, y: Double)]) -> Path {
        var p = Path(); let n = v.count; guard n > 1 else { return p }
        func cg(_ q: (x: Double, y: Double)) -> CGPoint { CGPoint(x: q.x, y: q.y) }
        p.move(to: cg(v[0]))
        for i in 0..<n {
            let p0 = v[(i-1+n)%n], p1 = v[i], p2 = v[(i+1)%n], p3 = v[(i+2)%n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x)/6, y: p1.y + (p2.y - p0.y)/6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x)/6, y: p2.y - (p3.y - p1.y)/6)
            p.addCurve(to: cg(p2), control1: c1, control2: c2)
        }
        p.closeSubpath(); return p
    }
}
