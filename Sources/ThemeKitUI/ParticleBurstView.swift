// ThemeKitUI — SwiftUI bridge for `Effects`' one-shot particle atom
// (`rollBurst` → `resolveParticles` (closed-form) → the real AppKit
// `drawParticles`). The atom is pure MATH + a draw helper, not a widget, so the
// bridge OWNS the redraw clock (sill's `f(now)` contract — the clock lives with
// the consumer) in a tiny flipped `NSView` and paints the real renderer each
// frame. Antialias/glow are AppKit `NSShadow` (the renderer's), so this is a
// `NSViewRepresentable` (not a SwiftUI `Canvas`) — byte-identical to the AppKit
// draw, no glow re-port.
//
// GENERAL by design (the #17a build-best line): the emitter point(s), colours,
// emission, intensity, duration, cooling `radiusSpeed`, loop cadence and render
// `scale` are all inputs — an app drives a one-shot burst at a gesture point
// (`loopPeriod: nil`) or a continuous emitter (`loopPeriod:`), perch/wand style.
// prism passes its showcase data (festive hues, bounds-relative emitters) and
// gets the same pixels. `frozen` (0…1 of `duration`) freezes one mid-burst frame
// for a deterministic capture (prism's `PRISM_PARTICLE_T`, now a public seam).

import SwiftUI
import AppKit
import Effects

public struct ParticleBurstView: NSViewRepresentable {
    public var emission: ParticleEmission
    public var colors: [UInt32]
    public var intensity: EffectIntensity
    public var duration: TimeInterval
    /// Per-particle radius cooling (CAEmitter `scaleSpeed`); negative shrinks.
    public var radiusSpeed: Double
    /// nil = roll ONE burst (one-shot, e.g. a gesture pop); non-nil = re-roll
    /// every `loopPeriod` seconds (a continuous emitter).
    public var loopPeriod: Double?
    /// Maps the view's bounds (flipped: +y down, so the sim's gravity falls
    /// on-screen) to the burst emitter point(s). Default = a single centre.
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

    public func makeNSView(context: Context) -> ParticleBurstNSView {
        let v = ParticleBurstNSView()
        apply(v)
        return v
    }

    public func updateNSView(_ v: ParticleBurstNSView, context: Context) {
        apply(v)
        v.needsDisplay = true
    }

    private func apply(_ v: ParticleBurstNSView) {
        v.emission = emission
        v.colors = colors
        v.intensity = intensity
        v.duration = duration
        v.radiusSpeed = radiusSpeed
        v.loopPeriod = loopPeriod
        v.emitters = emitters
        v.scale = scale
        v.frozen = frozen
    }
}

/// The live host: a flipped (top-left-origin, so +y-down gravity falls
/// on-screen) `NSView` that re-rolls the configured emission's burst and paints
/// it with the shared `drawParticles`. Owns a 60 Hz redraw timer; honours
/// `frozen` for a deterministic capture. Transparent background — the consumer
/// composes whatever sits behind it.
public final class ParticleBurstNSView: NSView {
    public var emission: ParticleEmission = .fireworks
    public var colors: [UInt32] = [] { didSet { needsDisplay = true } }
    public var intensity: EffectIntensity = .bold
    public var duration: TimeInterval = 1.1
    public var radiusSpeed: Double = 0
    public var loopPeriod: Double?
    public var emitters: (CGRect) -> [CGPoint] = { [CGPoint(x: $0.midX, y: $0.midY)] }
    public var scale: CGFloat = 1
    public var frozen: Double?

    private var burst: ParticleBurst?
    private var timer: Timer?

    public override var isFlipped: Bool { true }   // +y down → gravity falls on-screen
    public override var wantsDefaultClipping: Bool { true }

    // Start the redraw tick when added to a window; stop it when removed.
    // viewDidMoveToWindow is MainActor-isolated, so it (not a nonisolated deinit)
    // owns the timer's lifetime.
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { timer?.invalidate(); timer = nil; return }
        guard timer == nil else { return }
        timer = startEffectTick(for: self, frozen: frozen != nil)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 1, bounds.height > 1 else { return }

        // Freeze mode — one deterministic mid-burst frame.
        if let f = frozen {
            let b = burst ?? rollBurst(emission: emission, from: emitters(bounds),
                                       colors: colors, intensity: intensity,
                                       now: 0, duration: duration, radiusSpeed: radiusSpeed)
            burst = b
            drawParticles(b, now: max(0, min(1, f)) * duration, scale: scale)
            return
        }

        // Live — re-roll a one-shot once, or re-fire every `loopPeriod`.
        let now = CACurrentMediaTime()
        let reroll: Bool
        if let period = loopPeriod {
            reroll = burst == nil || now - (burst?.startedAt ?? 0) >= period
        } else {
            reroll = burst == nil
        }
        if reroll {
            burst = rollBurst(emission: emission, from: emitters(bounds),
                              colors: colors, intensity: intensity,
                              now: now, duration: duration, radiusSpeed: radiusSpeed)
        }
        if let b = burst { drawParticles(b, now: now, scale: scale) }
    }
}
