// Splatter — the shared INK-SPLAT decal atom for the family (wand's
// Splatoon-style post-fire splatter, generalized). The celebratory "stamp":
// 2–3 ink-splat units (a round-ish tendril body + a darker wet rim + a few
// detached droplet specks) dropped at a point, held, then faded out.
//
// Same two-tier shape as the rest of Effects, but a SPLATTER doesn't MOVE —
// only its opacity changes — so it is the simplest member of the
// roll → resolve → draw family:
//
//   1. ROLL once at the trigger — `rollSplatter` deterministically generates
//      the whole geometry from a seed (unit count/placement, every blob's
//      vertices, droplet offsets, per-unit color) and stamps `now`. The result
//      is a `Sendable` value the app stores in one cell. A FIXED `seed` makes
//      the shape reproducible (testable + a deterministic screenshot); `nil`
//      rolls a fresh one (`UInt64.random`, exactly as `rollFlash`/`rollBurst`
//      use the stdlib RNG).
//   2. RESOLVE per frame — `SplatterShape.alpha(now:)` is the only thing that
//      changes with time: hold at full for the first 66 %, then linear-fade to
//      0 (wand's post-fire hold-then-fade curve). The geometry is static.
//   3. DRAW per frame — the AppKit `drawInkSplatter` helper fills each unit's
//      rim + body + droplets (smoothing the pure vertices with Catmull-Rom) at
//      the resolved alpha, or the app draws its own from the pure vertices.
//
// PHILOSOPHY — identical to the rest of Effects: the pure tier is `Sendable`,
// AppKit-free, `Double`/`UInt32` only (points are `(x:y:)` tuples, matching
// `rollBurst`'s emitters); the app owns the clock, the `NSColor`, and the off
// gate. Orientation-agnostic: the splat is radial, so the `+y` sense doesn't
// matter (unlike the particle burst's gravity).

import Foundation
import Palette   // HexColor (re-exported by Effects)

#if canImport(AppKit)
import AppKit
#endif

// MARK: - The rolled splatter (pure, Sendable)

/// One ink-splat decal pre-rolled at the trigger — the geometry of 2–3 splat
/// units plus the birth stamp + lifetime. Static shape; only `alpha(now:)`
/// changes. Pure + `Sendable`.
public struct SplatterShape: Sendable {
    /// One splat unit: a tendril body, a slightly-larger rim drawn under it,
    /// and a few detached droplet specks — all as pre-rolled vertex rings in
    /// absolute coordinates (already offset to the unit's place).
    public struct Unit: Sendable {
        /// The unit's centre (absolute).
        public let center: (x: Double, y: Double)
        /// `0xRRGGBB` — the unit's ink color (the rim is a darker blend of it).
        public let color: UInt32
        /// The main body silhouette vertices (smoothed at draw time).
        public let body: [(x: Double, y: Double)]
        /// The wet-rim underlayer vertices (a larger, separately-rolled blob).
        public let rim: [(x: Double, y: Double)]
        /// Detached droplet specks, each its own small blob vertex ring.
        public let droplets: [[(x: Double, y: Double)]]

        public init(center: (x: Double, y: Double), color: UInt32,
                    body: [(x: Double, y: Double)], rim: [(x: Double, y: Double)],
                    droplets: [[(x: Double, y: Double)]]) {
            self.center = center; self.color = color
            self.body = body; self.rim = rim; self.droplets = droplets
        }
    }

    public let units: [Unit]
    /// Wall-clock stamp (`CACurrentMediaTime()`-style seconds) at the roll.
    public let startedAt: Double
    /// Total time-to-live in seconds (hold + fade).
    public let duration: TimeInterval

    public init(units: [Unit], startedAt: Double, duration: TimeInterval) {
        self.units = units
        self.startedAt = startedAt
        self.duration = duration
    }

    /// Fraction of the lifetime spent at FULL opacity before the fade begins —
    /// wand's post-fire curve (hold the first ⅔, fade the last ⅓).
    public static let holdFraction = 0.66

    /// Opacity `0…1` at `now`: full through `holdFraction`, then linear to 0 at
    /// the end. (Outside `[startedAt, startedAt+duration]` it clamps to 1 / 0.)
    public func alpha(now: Double) -> Double {
        guard duration > 0 else { return now >= startedAt ? 0 : 1 }
        let p = (now - startedAt) / duration
        if p <= Self.holdFraction { return 1 }
        return max(0, (1 - p) / (1 - Self.holdFraction))
    }

    /// True while the decal is still visible at `now` (the redraw-clock gate).
    public func isActive(now: Double) -> Bool {
        let t = now - startedAt
        return t >= 0 && t < duration
    }
}

// MARK: - Rolling a splatter (pure — the rollFlash/rollBurst analog)

/// Roll an ink-splat decal centred at `at`, sized to `size` points across,
/// stamped at `now`. Deterministic in `seed` (pass a fixed value for a
/// reproducible shape; `nil` draws a fresh `UInt64.random`). `colors` are the
/// `0xRRGGBB` candidates each unit picks from — pass the theme accent plus a
/// festive set, or a Splatoon team palette, so one decal can stack 2–3
/// differently-coloured splats; an empty palette falls back to white.
///
/// Faithfully ports wand's `DecalManager` geometry: a lead unit near the
/// centre plus 1–2 smaller orbiting units, each a 22–29-vertex tendril blob
/// (3-tier radius: body / short tendril / long spike) with a 1.08× rim and
/// 3–6 droplet specks.
public func rollSplatter(
    at: (x: Double, y: Double),
    size: Double,
    colors: [UInt32],
    seed: UInt64? = nil,
    now: Double,
    duration: TimeInterval = 1.4
) -> SplatterShape {
    let palette = colors.isEmpty ? [0xFFFFFF] : colors
    var rng = SplitMix64(seed: seed ?? UInt64.random(in: 0 ..< UInt64.max))
    let w = max(0, size)

    let unitCount = 2 + Int(rng.next() % 2)   // 2…3
    var units: [SplatterShape.Unit] = []
    units.reserveCapacity(unitCount)

    for i in 0..<unitCount {
        let center: (x: Double, y: Double)
        let unitR: Double
        if i == 0 {
            // Lead unit — near (not exactly at) centre, largest.
            let dx = (rng.nextUnit() - 0.5) * w * 0.12
            let dy = (rng.nextUnit() - 0.5) * w * 0.12
            center = (x: at.x + dx, y: at.y + dy)
            unitR = w * (0.15 + rng.nextUnit() * 0.05)
        } else {
            // Orbit unit — random angle, smaller.
            let angle = rng.nextUnit() * .pi * 2
            let dist = w * (0.18 + rng.nextUnit() * 0.10)
            center = (x: at.x + cos(angle) * dist, y: at.y + sin(angle) * dist)
            unitR = w * (0.07 + rng.nextUnit() * 0.06)
        }

        let color = palette[Int(rng.next() % UInt64(palette.count))]
        let rim = tendrilBlob(at: center, baseRadius: unitR * 1.08, rng: &rng)
        let body = tendrilBlob(at: center, baseRadius: unitR, rng: &rng)

        let speckCount = 3 + Int(rng.next() % 4)   // 3…6
        var droplets: [[(x: Double, y: Double)]] = []
        droplets.reserveCapacity(speckCount)
        for _ in 0..<speckCount {
            let angle = rng.nextUnit() * .pi * 2
            let dist = unitR * (1.4 + rng.nextUnit() * 0.8)
            let dr = unitR * (0.04 + rng.nextUnit() * 0.10)
            let c = (x: center.x + cos(angle) * dist, y: center.y + sin(angle) * dist)
            droplets.append(irregularBlob(at: c, baseRadius: dr, jitter: 0.4,
                                          points: 8, rng: &rng))
        }

        units.append(SplatterShape.Unit(center: center, color: color,
                                        body: body, rim: rim, droplets: droplets))
    }

    return SplatterShape(units: units, startedAt: now, duration: duration)
}

/// A classic ink-splat silhouette: 22–29 vertices at uniform angle steps, each
/// radius rolled into one of three tiers — body (60 %, 0.70–1.05×), short
/// tendril (30 %, 1.20–1.55×), long spike (10 %, 1.80–2.30×). wand's
/// `tendrilBlobPath`, vertices only (the Catmull-Rom smoothing is a draw step).
private func tendrilBlob(at c: (x: Double, y: Double), baseRadius r: Double,
                         rng: inout SplitMix64) -> [(x: Double, y: Double)] {
    let count = 22 + Int(rng.next() % 8)
    var verts: [(x: Double, y: Double)] = []
    verts.reserveCapacity(count)
    for i in 0..<count {
        let angle = Double(i) * (.pi * 2 / Double(count))
        let roll = rng.nextUnit()
        let mult: Double
        if roll < 0.10 { mult = 1.80 + rng.nextUnit() * 0.50 }
        else if roll < 0.40 { mult = 1.20 + rng.nextUnit() * 0.35 }
        else { mult = 0.70 + rng.nextUnit() * 0.35 }
        let radius = r * mult
        verts.append((x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius))
    }
    return verts
}

/// A jittered-circle blob: `points` vertices each pushed `±jitter·r`. wand's
/// `irregularBlobPath`, vertices only — the droplet-speck primitive.
private func irregularBlob(at c: (x: Double, y: Double), baseRadius r: Double,
                           jitter: Double, points: Int,
                           rng: inout SplitMix64) -> [(x: Double, y: Double)] {
    var verts: [(x: Double, y: Double)] = []
    verts.reserveCapacity(points)
    for i in 0..<points {
        let angle = Double(i) * (.pi * 2 / Double(points))
        let j = (rng.nextUnit() - 0.5) * 2 * jitter
        let radius = r * (1 + j)
        verts.append((x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius))
    }
    return verts
}

// MARK: - Deterministic RNG (SplitMix64)

/// A deterministic 64-bit RNG so a splatter's shape is reproducible from its
/// seed (a fixed seed → the same splat every time; tests + screenshots rely on
/// it). Ported verbatim from wand's `DecalManager.SplitMix64`.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform `0…1` double (53-bit mantissa) for angle / jitter picks.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / Double(1 << 53))
    }
}

#if canImport(CoreGraphics)
import CoreGraphics

/// `CGPoint` convenience for `rollSplatter` (apps work in `CGPoint`; the pure
/// core stays `Double`-tuple, like `rollBurst`).
public func rollSplatter(
    at: CGPoint,
    size: Double,
    colors: [UInt32],
    seed: UInt64? = nil,
    now: Double,
    duration: TimeInterval = 1.4
) -> SplatterShape {
    rollSplatter(at: (x: Double(at.x), y: Double(at.y)), size: size,
                 colors: colors, seed: seed, now: now, duration: duration)
}
#endif

// MARK: - AppKit draw helper (the drawParticles/drawLinePets analog)

#if canImport(AppKit)

/// Paint `shape`'s ink splat at wall-clock `now` into the CURRENT
/// `NSGraphicsContext`, faded to `alpha(now:)`. Each unit draws a darker wet
/// rim, then the body, then the droplet specks — every blob smoothed from its
/// pure vertices with Catmull-Rom-to-bézier (the curve is a render concern, so
/// it lives here, not in the value). The app owns the clock + where it draws;
/// an app wanting its own look reads `shape.units` directly.
@MainActor
public func drawInkSplatter(_ shape: SplatterShape, now: Double) {
    let a = CGFloat(max(0, min(1, shape.alpha(now: now))))
    guard a > 0 else { return }
    for unit in shape.units {
        let ink = NSColor(HexColor(unit.color))
        // Wet-rim underlayer — a darker blend of the unit ink.
        let rimColor = (NSColor.black.blended(withFraction: 0.45, of: ink) ?? ink)
            .withAlphaComponent(0.78 * a)
        rimColor.setFill(); catmullRomPath(unit.rim).fill()
        // Main body.
        ink.withAlphaComponent(0.96 * a).setFill(); catmullRomPath(unit.body).fill()
        // Droplet specks.
        ink.withAlphaComponent(0.88 * a).setFill()
        for speck in unit.droplets { catmullRomPath(speck).fill() }
    }
}

/// Build a closed, smooth `NSBezierPath` through `verts` using the standard
/// uniform Catmull-Rom → cubic-bézier conversion (1/6 tension) — the same
/// smoothing wand applied to its blob vertices.
private func catmullRomPath(_ verts: [(x: Double, y: Double)]) -> NSBezierPath {
    let path = NSBezierPath()
    let n = verts.count
    guard n > 1 else { return path }
    func pt(_ p: (x: Double, y: Double)) -> CGPoint { CGPoint(x: p.x, y: p.y) }
    path.move(to: pt(verts[0]))
    for i in 0..<n {
        let p0 = verts[(i - 1 + n) % n], p1 = verts[i]
        let p2 = verts[(i + 1) % n], p3 = verts[(i + 2) % n]
        let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6.0, y: p1.y + (p2.y - p0.y) / 6.0)
        let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6.0, y: p2.y - (p3.y - p1.y) / 6.0)
        path.curve(to: pt(p2), controlPoint1: cp1, controlPoint2: cp2)
    }
    path.close()
    return path
}

#endif
