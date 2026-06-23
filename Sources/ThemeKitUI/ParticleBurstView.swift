// ThemeKitUI — SwiftUI-native particle-burst bridge.
//
// Replaces the #17a AppKit-backed bridge with a pure SwiftUI `Canvas` so the
// module contains zero AppKit-backed particle wrappers. The rendering
// model is `f(now)` — the `Canvas` closure is a PURE derivation of the current
// wall-clock; no @State is written during render.
//
// CLOCK DESIGN
// ─────────────
// `@State private var start` is initialised once when the view appears and is
// READ (never written) inside the Canvas/TimelineView closure. The absolute
// reference-date epoch (`Date.timeIntervalSinceReferenceDate`) is used for
// `now` so that `startedAt` math in `resolveParticles` is consistent.
//
// COORDINATE SYSTEM
// ─────────────────
// SwiftUI Canvas has +y DOWN (top-left origin), which matches the Effects sim
// (`+y DOWN` gravity, matching the old `isFlipped = true` NSView). No flip is
// needed — particles are drawn at `(rp.x, rp.y)` directly.
//
// GLOW ISOLATION
// ──────────────
// Each spark's glow is drawn inside `ctx.drawLayer { l in … }` so the
// `.shadow` filter is scoped to that layer only — the hot-white core is then
// painted in the base context (no shadow) for a sharp centre point.

import SwiftUI
import Effects

public struct ParticleBurstView: View {
    public var emission: ParticleEmission
    public var colors: [UInt32]
    public var intensity: EffectIntensity
    public var duration: TimeInterval
    /// Per-particle radius cooling (CAEmitter `scaleSpeed`); negative shrinks.
    public var radiusSpeed: Double
    /// nil = roll ONE burst (one-shot, e.g. a gesture pop); non-nil = re-roll
    /// every `loopPeriod` seconds (a continuous emitter).
    public var loopPeriod: Double?
    /// Maps the view's bounds (+y down, so the sim's gravity falls on-screen)
    /// to the burst emitter point(s). Default = a single centre.
    public var emitters: (CGRect) -> [CGPoint]
    public var scale: CGFloat
    /// nil = live; non-nil = freeze ONE frame at that fraction (0…1) of `duration`.
    public var frozen: Double?

    public init(emission: ParticleEmission = .fireworks,
                colors: [UInt32],
                intensity: EffectIntensity = .bold,
                duration: TimeInterval = 1.1,
                radiusSpeed: Double = 0,
                loopPeriod: Double? = nil,
                scale: CGFloat = 1,
                frozen: Double? = nil,
                emitters: @escaping (CGRect) -> [CGPoint] = { [CGPoint(x: $0.midX, y: $0.midY)] }) {
        self.emission = emission
        self.colors = colors
        self.intensity = intensity
        self.duration = duration
        self.radiusSpeed = radiusSpeed
        self.loopPeriod = loopPeriod
        self.emitters = emitters
        self.scale = scale
        self.frozen = frozen
    }

    // The absolute reference-date epoch for `start` — keeps the `startedAt`
    // math consistent with how `resolveParticles` measures elapsed time.
    @State private var start = Date()

    public var body: some View {
        if let f = frozen {
            // ── Frozen mode ─────────────────────────────────────────────────
            // Static single frame at fraction `f` of `duration`. A fixed seed
            // keeps the geometry deterministic for screenshots (prism's
            // `PRISM_PARTICLE_T` seam). `startedAt: 0` and `now: f*duration`
            // means the resolve time equals the frozen fraction exactly.
            Canvas { ctx, canvasSize in
                let bounds = CGRect(origin: .zero, size: canvasSize)
                let pts = emitters(bounds)
                let frozenNow = max(0, min(1, f)) * duration
                let burst = rollBurst(seed: 0xC0FFEE,
                                      emission: emission,
                                      from: pts,
                                      colors: colors,
                                      intensity: intensity,
                                      now: 0,
                                      duration: duration,
                                      radiusSpeed: radiusSpeed)
                drawBurst(burst, now: frozenNow, scale: scale, into: &ctx)
            }
        } else {
            // ── Live mode ───────────────────────────────────────────────────
            // TimelineView drives the animation clock. The Canvas is a PURE
            // derivation of `now` — no @State writes inside the closure.
            // `start` is captured at launch (READ only) so that one-shot and
            // looping cadence indices are anchored to a stable baseline.
            TimelineView(.animation) { timeline in
                Canvas { ctx, canvasSize in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    let startBaseline = start.timeIntervalSinceReferenceDate
                    let bounds = CGRect(origin: .zero, size: canvasSize)
                    let pts = emitters(bounds)

                    let burst: ParticleBurst
                    if let period = loopPeriod, period > 0 {
                        // ── Loop mode ──────────────────────────────────────
                        // Each cadence window rolls a distinct deterministic
                        // burst (golden-ratio seed mix) that is STABLE within
                        // the window — no flicker, no @State write.
                        let elapsed = now - startBaseline
                        let cadenceIndex = UInt64(max(0, floor(elapsed / period)))
                        let stampNow = startBaseline + Double(cadenceIndex) * period
                        let seed = (cadenceIndex &+ 1) &* 0x9E3779B97F4A7C15
                        burst = rollBurst(seed: seed,
                                          emission: emission,
                                          from: pts,
                                          colors: colors,
                                          intensity: intensity,
                                          now: stampNow,
                                          duration: duration,
                                          radiusSpeed: radiusSpeed)
                    } else {
                        // ── One-shot mode ──────────────────────────────────
                        // A single burst rolled at `startBaseline` with a fixed
                        // seed. It plays once; `resolveParticles` returns [] once
                        // the burst settles — nothing more to draw.
                        burst = rollBurst(seed: 0xB0BAFE77,
                                          emission: emission,
                                          from: pts,
                                          colors: colors,
                                          intensity: intensity,
                                          now: startBaseline,
                                          duration: duration,
                                          radiusSpeed: radiusSpeed)
                    }
                    drawBurst(burst, now: now, scale: scale, into: &ctx)
                }
            }
        }
    }

    // MARK: - Render helpers

    /// Paint all live particles of `burst` at wall-clock `now` into `ctx`.
    private func drawBurst(_ burst: ParticleBurst, now: Double,
                           scale: CGFloat, into ctx: inout GraphicsContext) {
        for rp in resolveParticles(burst, now: now) {
            switch rp.shape {
            case .spark: renderGlowDot(rp, scale: scale, into: &ctx)
            case .paper: renderTumblingRect(rp, scale: scale, into: &ctx)
            }
        }
    }

    /// A glowing dot with a hot white core — the firework spark.
    ///
    /// Glow isolation: the colored oval + its `.shadow` filter live inside
    /// `ctx.drawLayer { l in … }` so the blur is scoped to that sub-layer.
    /// The hot-white core is then painted in the BASE context (no shadow filter
    /// active), keeping the bright centre sharp and free of glow bleed.
    private func renderGlowDot(_ rp: ResolvedParticle, scale: CGFloat,
                                into ctx: inout GraphicsContext) {
        let a = max(0, min(1, rp.alpha))
        let r = CGFloat(rp.radius) * scale
        let cx = CGFloat(rp.x), cy = CGFloat(rp.y)

        // Decode 0xRRGGBB — no AppKit needed.
        let red   = Double((rp.color >> 16) & 0xFF) / 255
        let green = Double((rp.color >>  8) & 0xFF) / 255
        let blue  = Double( rp.color        & 0xFF) / 255
        let sparkColor = Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)

        // Glow oval (isolated layer so shadow doesn't bleed onto the core).
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: Color(.sRGB, red: red, green: green,
                                             blue: blue, opacity: a * 0.85),
                                radius: r * 2.6,
                                options: .shadowAbove))
            l.fill(
                Path(ellipseIn: CGRect(x: cx - r, y: cy - r,
                                       width: 2 * r, height: 2 * r)),
                with: .color(sparkColor.opacity(a)))
        }

        // Hot white core — drawn in the BASE context (no shadow filter active).
        let coreR = r * 0.5
        ctx.fill(
            Path(ellipseIn: CGRect(x: cx - coreR, y: cy - coreR,
                                   width: 2 * coreR, height: 2 * coreR)),
            with: .color(Color.white.opacity(a * 0.85)))
    }

    /// A tumbling paper rectangle — rotated by its spin and squashed
    /// horizontally by `|cos(rotation)|` so it turns edge-on (confetti flip),
    /// with the back face shaded darker for depth.
    private func renderTumblingRect(_ rp: ResolvedParticle, scale: CGFloat,
                                    into ctx: inout GraphicsContext) {
        let a = max(0, min(1, rp.alpha))
        let w = CGFloat(rp.radius) * 2.4 * scale
        let h = CGFloat(rp.radius) * 1.4 * scale
        let flip = max(0.18, abs(cos(CGFloat(rp.rotation))))   // edge-on squash

        // Decode 0xRRGGBB.
        let red   = Double((rp.color >> 16) & 0xFF) / 255
        let green = Double((rp.color >>  8) & 0xFF) / 255
        let blue  = Double( rp.color        & 0xFF) / 255

        // Back-face darkening: lerp channels toward 0 by `(1-flip)*0.45`.
        let darken = (1 - Double(flip)) * 0.45
        let faceColor = Color(.sRGB,
                               red:   red   * (1 - darken),
                               green: green * (1 - darken),
                               blue:  blue  * (1 - darken),
                               opacity: a)

        ctx.drawLayer { l in
            // Translate to the particle centre, rotate, then squash horizontally.
            l.translateBy(x: CGFloat(rp.x), y: CGFloat(rp.y))
            l.rotate(by: .radians(rp.rotation * 0.4))
            l.scaleBy(x: flip, y: 1)
            l.fill(
                Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                     cornerRadius: 1 * scale),
                with: .color(faceColor))
        }
    }
}
