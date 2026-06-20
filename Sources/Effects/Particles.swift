// Particles — the shared one-shot PARTICLE BURST atom for the family
// (perch's confetti/fireworks, wand's gesture burst). The celebratory
// "pop": a field of dots that fly out, arc under gravity, spin, and fade.
//
// This is the SAME pattern Effects already ships for the border flash
// (`FlashState` / `rollFlash` / `resolveBorder`), scaled from a handful of
// blink colors to a field of moving particles:
//
//   1. ROLL once at the trigger — `rollBurst` picks each particle's initial
//      conditions (position, velocity, color, spin, …) and stamps `now`.
//      The result is a `Sendable` value the app stores in one cell, exactly
//      like a `FlashState?`.
//   2. RESOLVE per frame — `resolveParticles(burst, now:)` returns the live
//      particles in CLOSED FORM (`x = x₀ + v·t`, `y = y₀ + v·t + ½g·t²`,
//      `alpha = 1 − t/(duration·life)`). NO Euler integration, NO mutable sim
//      state, NO per-frame `dt`: re-sampling the same `now` always yields the same
//      frame (replayable, unit-testable), and a dropped frame can't drift
//      the trajectory. (perch's driver integrated `dt` each tick — correct,
//      but frame-rate-dependent and stateful; the closed form is exact.)
//   3. DRAW per frame — the app paints the resolved particles. A ready-made
//      AppKit `drawParticles` helper (behind `#if canImport(AppKit)`, the
//      `drawLinePets` precedent) renders glowing sparks + tumbling paper, or
//      the app draws its own from the pure `ResolvedParticle` list.
//
// PHILOSOPHY — identical to the rest of Effects/Motion: the pure tier is
// `Sendable`, AppKit-free, `UInt32`/`Double` only; the app owns the redraw
// clock, the `NSColor` materialization, and the "off" gate. `EffectIntensity`
// (the shared subtle…wild knob, from `Palette`) scales the count + reach.
//
// COORDINATES — the sim's +y points DOWN (gravity is positive-y), the
// screen-natural sense, matching perch's flipped overlay canvas. Host the
// draw in an `isFlipped` (top-left-origin) view so gravity falls on-screen;
// in a y-up context, negate `gravity` at roll time.

import Foundation
import Palette   // EffectIntensity, HexColor (re-exported by Effects)

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Emission pattern (pure)

/// How a burst throws its particles. Two patterns cover the family's
/// celebratory effects (the roadmap's 紙吹雪 / 花火); reconciled from perch's
/// `ParticleEmission`.
public enum ParticleEmission: String, Sendable, Hashable, CaseIterable {
    /// 花火 — a radial omni-directional pop with LIGHT gravity, so the
    /// sparks fan out evenly and drift down slowly. wand's gesture burst is
    /// the same shape (it emitted over a full `2π` range).
    case fireworks
    /// 紙吹雪 — a party-popper cone: paper shoots UP-and-out, then STRONG
    /// gravity arcs it back down to flutter and tumble as it falls.
    case confetti
}

// MARK: - Particle shape (pure identity; drawn AppKit-side)

/// The silhouette a particle draws as. Pure identity — the AppKit
/// `drawParticles` helper switches on it; an app drawing its own ignores it.
public enum ParticleShape: String, Sendable, Hashable, CaseIterable {
    /// A glowing round dot with a hot white core — the firework spark.
    case spark
    /// A small rounded rectangle that tumbles and turns edge-on — paper
    /// confetti.
    case paper
}

// MARK: - One particle's initial conditions (pure, pre-rolled)

/// One particle's PRE-ROLLED initial conditions — everything `resolveParticles`
/// needs to place it at any later `now` in closed form. Rolled once by
/// `rollBurst`; never mutated. Positions/velocities are `Double` (points,
/// points-per-second) so the value stays `Sendable` and CoreGraphics-free.
public struct Particle: Sendable, Hashable {
    /// Spawn position (the emitter), `+y` DOWN.
    public var x0: Double
    public var y0: Double
    /// Initial velocity in pt/s (`+y` DOWN, so an upward pop is negative `vy`).
    public var vx: Double
    public var vy: Double
    /// Base draw radius in points (the spark's radius / the paper's half-extent).
    public var radius: Double
    /// Particle color, `0xRRGGBB`.
    public var color: UInt32
    /// Angular spin rate in rad/s — the paper's tumble (0 for a spark).
    public var spin: Double
    /// Horizontal flutter amplitude in points — the paper's side-to-side
    /// sway (0 for a spark). The sway is a closed-form `sin`, so it stays pure.
    public var sway: Double
    /// Flutter angular frequency in rad/s.
    public var swayFreq: Double
    /// Flutter phase offset in radians (so paper doesn't sway in lockstep).
    public var phase: Double
    /// This particle's OWN lifetime as a fraction (`0…1`) of the burst's
    /// duration — some die early so the burst dissolves organically rather
    /// than every particle vanishing on the same frame.
    public var life: Double
    /// The silhouette to draw.
    public var shape: ParticleShape

    public init(x0: Double, y0: Double, vx: Double, vy: Double,
                radius: Double, color: UInt32, spin: Double = 0,
                sway: Double = 0, swayFreq: Double = 0, phase: Double = 0,
                life: Double = 1, shape: ParticleShape = .spark) {
        self.x0 = x0; self.y0 = y0
        self.vx = vx; self.vy = vy
        self.radius = radius; self.color = color
        self.spin = spin; self.sway = sway
        self.swayFreq = swayFreq; self.phase = phase
        self.life = life; self.shape = shape
    }
}

// MARK: - The rolled burst (pure, Sendable — the FlashState analog)

/// A burst pre-rolled ONCE at the trigger and decayed by wall-clock — the
/// particle analog of `FlashState`. The app stores one `ParticleBurst?` cell
/// (set it via `rollBurst` on the celebratory moment), ticks its redraw clock
/// while `isActive`, and samples `resolveParticles` each frame. Holds no
/// clock of its own; pure.
public struct ParticleBurst: Sendable {
    /// The pre-rolled particles (initial conditions).
    public let particles: [Particle]
    /// Wall-clock stamp (`CACurrentMediaTime()`-style seconds) at the roll.
    public let startedAt: Double
    /// Total burst lifetime in seconds — the longest-lived particle's fade.
    public let duration: TimeInterval
    /// Downward acceleration in pt/s² applied to every particle's `vy`
    /// (`+y` DOWN). `fireworks` ≈ 360, `confetti` ≈ 900 (perch's values).
    public let gravity: Double
    /// The pattern this burst was rolled for (drives nothing in the resolve;
    /// carried so a consumer can branch on it).
    public let emission: ParticleEmission

    public init(particles: [Particle], startedAt: Double,
                duration: TimeInterval, gravity: Double,
                emission: ParticleEmission) {
        self.particles = particles
        self.startedAt = startedAt
        self.duration = duration
        self.gravity = gravity
        self.emission = emission
    }

    /// True while the burst is mid-flight at `now` — the app's redraw-clock
    /// gate (keep ticking while a burst is alive; stop when it settles).
    public func isActive(now: Double) -> Bool {
        let t = now - startedAt
        return t >= 0 && t < duration
    }

    /// Linear `0…1` progress of the whole burst at `now` (clamped).
    public func progress(now: Double) -> Double {
        guard duration > 0 else { return now >= startedAt ? 1 : 0 }
        return min(1, max(0, (now - startedAt) / duration))
    }
}

// MARK: - One particle resolved to a frame (pure)

/// A particle at a point in time — its closed-form position, current alpha,
/// and rotation, ready to draw. `color` stays `0xRRGGBB`; the app (or the
/// AppKit helper) materializes the `NSColor` so the pure tier links no AppKit.
public struct ResolvedParticle: Sendable {
    public let x: Double
    public let y: Double
    public let radius: Double
    public let color: UInt32
    /// Remaining opacity `0…1` (linear tail-dim).
    public let alpha: Double
    /// Current rotation in radians (`spin · t`).
    public let rotation: Double
    public let shape: ParticleShape

    public init(x: Double, y: Double, radius: Double, color: UInt32,
                alpha: Double, rotation: Double, shape: ParticleShape) {
        self.x = x; self.y = y; self.radius = radius; self.color = color
        self.alpha = alpha; self.rotation = rotation; self.shape = shape
    }
}

/// Resolve every still-alive particle of `burst` to its frame at wall-clock
/// `now`. PURE closed-form — no integration, no state:
///   * `x = x₀ + vx·t + sway·sin(swayFreq·t + phase)`  (flutter is closed-form)
///   * `y = y₀ + vy·t + ½·gravity·t²`                   (ballistic arc)
///   * `alpha = 1 − t / (duration·life)`                (per-particle linear fade)
///   * `rotation = spin·t`
/// Particles past their own lifetime are dropped, so the returned count
/// shrinks toward the end (the organic dissolve). Returns `[]` before the
/// roll, and once every particle has died.
public func resolveParticles(_ burst: ParticleBurst, now: Double) -> [ResolvedParticle] {
    let t = now - burst.startedAt
    guard t >= 0, t < burst.duration else { return [] }
    var out: [ResolvedParticle] = []
    out.reserveCapacity(burst.particles.count)
    for p in burst.particles {
        let lifeSpan = burst.duration * max(0.01, min(1, p.life))
        let localP = t / lifeSpan
        if localP >= 1 { continue }   // this particle has already faded out
        let x = p.x0 + p.vx * t + p.sway * sin(p.swayFreq * t + p.phase)
        let y = p.y0 + p.vy * t + 0.5 * burst.gravity * t * t
        out.append(ResolvedParticle(
            x: x, y: y, radius: p.radius, color: p.color,
            alpha: 1 - localP, rotation: p.spin * t, shape: p.shape))
    }
    return out
}

// MARK: - Rolling a burst (pure — the rollFlash analog)

/// Roll a fresh burst from each emitter point, stamped at `now`. The
/// `rollFlash` analog for particles: deterministic given the rolled value,
/// random in the roll (uniform `Double.random`, exactly as `rollFlash` uses
/// `Int.random`).
///
/// `colors` are the candidate `0xRRGGBB` hues each particle picks from — pass
/// an `EffectSpec.flash` palette to tint a burst with the live theme effect,
/// or a festive set plus the theme accent (perch's gold/pink/cyan + accent).
/// `intensity` scales BOTH the per-emitter count and the launch speed (its
/// reach); the count is hard-capped so an every-emitter burst on a busy
/// screen can't spawn thousands of particles (perch's 4…30 guard, widened).
///
/// `count` overrides the per-emitter particle count outright (skips the
/// intensity-derived default) — for a bench or a deliberately dense pop.
/// An empty `colors` falls back to white; empty `emitters` yields an inert
/// (already-settled) burst.
public func rollBurst(
    emission: ParticleEmission,
    from emitters: [(x: Double, y: Double)],
    colors: [UInt32],
    intensity: EffectIntensity = .normal,
    now: Double,
    duration: TimeInterval = 1.1,
    count: Int? = nil
) -> ParticleBurst {
    let palette = colors.isEmpty ? [0xFFFFFF] : colors
    let scale = intensity.multiplier
    // Per-emitter count: scale with intensity, hard-cap so a many-emitter
    // burst stays bounded. Confetti reads denser than fireworks.
    let base = emission == .fireworks ? 18 : 24
    let perEmitter = count ?? max(6, min(40, Int(Double(base) * scale)))

    var particles: [Particle] = []
    particles.reserveCapacity(emitters.count * perEmitter)
    for e in emitters {
        for _ in 0..<perEmitter {
            particles.append(emission == .fireworks
                ? rollSpark(at: e, palette: palette, scale: scale)
                : rollPaper(at: e, palette: palette, scale: scale))
        }
    }
    let gravity = emission == .fireworks ? 360.0 : 900.0
    return ParticleBurst(particles: particles, startedAt: now,
                         duration: duration, gravity: gravity, emission: emission)
}

/// A radial firework spark: uniform random angle, 120–260 pt/s × intensity.
private func rollSpark(at e: (x: Double, y: Double),
                       palette: [UInt32], scale: Double) -> Particle {
    let angle = Double.random(in: 0 ..< (2 * .pi))
    let speed = Double.random(in: 120...260) * scale
    return Particle(
        x0: e.x, y0: e.y,
        vx: cos(angle) * speed, vy: sin(angle) * speed,
        radius: Double.random(in: 1.6...3.2),
        color: palette.randomElement() ?? 0xFFFFFF,
        life: Double.random(in: 0.6...1.0),
        shape: .spark)
}

/// A confetti paper: a party-popper cone — shoots UP-and-out (negative `vy`)
/// with a wide horizontal spread, then gravity arcs it down; given a tumble
/// spin and a horizontal flutter so it reads as paper, not a falling dot.
private func rollPaper(at e: (x: Double, y: Double),
                       palette: [UInt32], scale: Double) -> Particle {
    let dx = Double.random(in: -150...150) * scale
    let dy = Double.random(in: -240 ... -90) * scale   // up-and-out
    return Particle(
        x0: e.x, y0: e.y,
        vx: dx, vy: dy,
        radius: Double.random(in: 2.2...3.6),
        color: palette.randomElement() ?? 0xFFFFFF,
        spin: Double.random(in: -7 ... 7),
        sway: Double.random(in: 8...22),
        swayFreq: Double.random(in: 3...6),
        phase: Double.random(in: 0 ..< (2 * .pi)),
        life: Double.random(in: 0.7...1.0),
        shape: .paper)
}

#if canImport(CoreGraphics)
import CoreGraphics

/// `CGPoint` convenience for `rollBurst` — apps work in `CGPoint`; the pure
/// core stays `Double`-tuple + CoreGraphics-free (mirrors how `Motion` gates
/// its `CGPoint` lerp overloads behind a CoreGraphics import).
public func rollBurst(
    emission: ParticleEmission,
    from emitters: [CGPoint],
    colors: [UInt32],
    intensity: EffectIntensity = .normal,
    now: Double,
    duration: TimeInterval = 1.1,
    count: Int? = nil
) -> ParticleBurst {
    rollBurst(emission: emission,
              from: emitters.map { (x: Double($0.x), y: Double($0.y)) },
              colors: colors, intensity: intensity, now: now,
              duration: duration, count: count)
}
#endif

// MARK: - AppKit draw helper (the drawLinePets analog)

#if canImport(AppKit)

/// Paint `burst`'s live particles at wall-clock `now` into the CURRENT
/// `NSGraphicsContext` — the ready-made renderer for the rich look (glowing
/// sparks + tumbling, edge-flipping paper). The `drawLinePets` precedent: the
/// caller owns the view + redraw timer and has set up the context; this draws
/// each particle at its sim `(x, y)`.
///
/// The sim's `+y` is DOWN, so host this in an `isFlipped` (top-left-origin)
/// view and confetti falls on-screen; in a y-up view, negate `gravity` at
/// roll time. An app wanting a different silhouette skips this and draws from
/// `resolveParticles` directly.
@MainActor
public func drawParticles(_ burst: ParticleBurst, now: Double, scale: CGFloat = 1) {
    for rp in resolveParticles(burst, now: now) {
        switch rp.shape {
        case .spark: drawSpark(rp, scale: scale)
        case .paper: drawPaper(rp, scale: scale)
        }
    }
}

/// A glowing dot with a hot white core — the firework spark.
@MainActor
private func drawSpark(_ rp: ResolvedParticle, scale: CGFloat) {
    let a = CGFloat(max(0, min(1, rp.alpha)))
    let base = NSColor(HexColor(rp.color)).withAlphaComponent(a)
    let r = CGFloat(rp.radius) * scale
    let cx = CGFloat(rp.x), cy = CGFloat(rp.y)

    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = base.withAlphaComponent(a * 0.85)
    glow.shadowBlurRadius = r * 2.6
    glow.shadowOffset = .zero
    glow.set()
    base.setFill()
    NSBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Hot white core (no glow) for the sparkle.
    let coreR = r * 0.5
    NSColor.white.withAlphaComponent(a * 0.85).setFill()
    NSBezierPath(ovalIn: CGRect(x: cx - coreR, y: cy - coreR,
                                width: 2 * coreR, height: 2 * coreR)).fill()
}

/// A tumbling paper rectangle — rotated by its spin and squashed horizontally
/// by `|cos(rotation)|` so it turns edge-on (the classic confetti flip), with
/// the back face shaded darker for depth.
@MainActor
private func drawPaper(_ rp: ResolvedParticle, scale: CGFloat) {
    let a = CGFloat(max(0, min(1, rp.alpha)))
    let base = NSColor(HexColor(rp.color)).withAlphaComponent(a)
    let w = CGFloat(rp.radius) * 2.4 * scale
    let h = CGFloat(rp.radius) * 1.4 * scale
    let flip = max(0.18, abs(cos(CGFloat(rp.rotation))))   // edge-on squash

    NSGraphicsContext.saveGraphicsState()
    let tx = NSAffineTransform()
    tx.translateX(by: CGFloat(rp.x), yBy: CGFloat(rp.y))
    tx.rotate(byRadians: CGFloat(rp.rotation) * 0.4)        // gentle visible tumble
    tx.scaleX(by: flip, yBy: 1)
    tx.concat()
    let face = (base.blended(withFraction: (1 - flip) * 0.45, of: .black) ?? base)
        .withAlphaComponent(a)
    face.setFill()
    NSBezierPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                 xRadius: 1 * scale, yRadius: 1 * scale).fill()
    NSGraphicsContext.restoreGraphicsState()
}

#endif
