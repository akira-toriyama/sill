// prism — the LIVE particle-burst bench.
//
// `Effects`' particle atom (`rollBurst` / `resolveParticles` / `drawParticles`)
// is pure MATH + a draw helper, not a widget — so, like the Motion bench, the
// way to PROVE it works is to DRIVE it. This hosts the REAL AppKit
// `drawParticles` renderer in a tiny `ParticleBurstNSView` that owns a redraw
// clock (prism owns the clock here — there is no widget to own it), re-rolls a
// burst on a fixed period, and paints it. Two stages per card — 花火 fireworks
// (radial glow) and 紙吹雪 confetti (a party-popper of tumbling paper) — so
// every theme shows both emissions cycling live.
//
// Theme-tinted: each burst's palette is the card's `primary` + `secondary`
// plus a festive constant set, so the pop reads in every theme (perch's
// "accent + gold/pink/cyan" generalized). A `previewT` env override
// (`PRISM_PARTICLE_T=0.35`) freezes a deterministic mid-burst frame for a
// static screenshot; absent it, the bench runs live.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import Effects

/// The festive base hues every burst mixes with the theme accent (gold / pink
/// / cyan / lime / violet) — guarantees variety even on a monochrome theme.
private let festiveHues: [UInt32] = [0xFFD700, 0xFF6EC7, 0x00E5FF, 0x9EFF00, 0xBC6BFF]

/// `0xRRGGBB` for a resolved `NSColor` (sRGB) — feeds the pure `rollBurst`.
private func hexU32(_ c: NSColor) -> UInt32 {
    guard let s = c.usingColorSpace(.sRGB) else { return 0xFFFFFF }
    let r = UInt32((s.redComponent * 255).rounded())
    let g = UInt32((s.greenComponent * 255).rounded())
    let b = UInt32((s.blueComponent * 255).rounded())
    return (r << 16) | (g << 8) | b
}

// MARK: - The live NSView (hosts the REAL drawParticles renderer)

/// A flipped (top-left-origin, so the sim's `+y`-down gravity falls on-screen)
/// NSView that re-rolls one emission's burst every `burstPeriod` and paints it
/// with the shared `drawParticles`. Owns a 60 Hz redraw timer; honors a
/// `previewT` freeze for deterministic capture.
final class ParticleBurstNSView: NSView {
    var emission: ParticleEmission = .fireworks
    var colors: [UInt32] = festiveHues { didSet { needsDisplay = true } }
    /// When set (env `PRISM_PARTICLE_T`, 0…1), render ONE frozen frame at that
    /// fraction of the burst instead of running live.
    var previewT: Double?

    private var burst: ParticleBurst?
    private var timer: Timer?

    override var isFlipped: Bool { true }   // +y down → gravity falls on-screen
    override var wantsDefaultClipping: Bool { true }

    // Start the redraw tick when added to a window; stop it when removed.
    // viewDidMoveToWindow is MainActor-isolated, so it (not a nonisolated
    // deinit) owns the timer's lifetime.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            timer?.invalidate(); timer = nil
            return
        }
        guard previewT == nil, timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// The burst origin: fireworks from upper-center; confetti shoots up from
    /// near the bottom edge (a party popper).
    private var emitter: (x: Double, y: Double) {
        switch emission {
        case .fireworks: return (Double(bounds.midX), Double(bounds.height * 0.46))
        case .confetti:  return (Double(bounds.midX), Double(bounds.height * 0.94))
        }
    }

    private var duration: TimeInterval { emission == .fireworks ? 1.05 : 1.6 }

    /// Re-roll cadence — the burst's own length plus a short beat, so the pop
    /// reads then re-fires before a long dead frame (fireworks ≠ confetti, so
    /// the two stages drift out of phase and the card is never fully still).
    private var period: Double { duration + 0.4 }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 1, bounds.height > 1 else { return }

        // Freeze mode — one deterministic mid-burst frame.
        if let pt = previewT {
            let b = burst ?? rollBurst(emission: emission, from: [emitter],
                                       colors: colors, intensity: .bold,
                                       now: 0, duration: duration)
            burst = b
            drawParticles(b, now: max(0, min(1, pt)) * duration, scale: uiScale)
            return
        }

        // Live — re-roll once the period has elapsed (a popped-then-rests beat).
        let now = CACurrentMediaTime()
        if burst == nil || now - (burst?.startedAt ?? 0) >= period {
            burst = rollBurst(emission: emission, from: [emitter],
                              colors: colors, intensity: .bold,
                              now: now, duration: duration)
        }
        if let b = burst { drawParticles(b, now: now, scale: uiScale) }
    }
}

// MARK: - SwiftUI bridge

struct ParticleFieldView: NSViewRepresentable {
    let emission: ParticleEmission
    let colors: [UInt32]

    private static let previewT: Double? =
        ProcessInfo.processInfo.environment["PRISM_PARTICLE_T"].flatMap(Double.init)

    func makeNSView(context: Context) -> ParticleBurstNSView {
        let v = ParticleBurstNSView()
        v.emission = emission
        v.colors = colors
        v.previewT = Self.previewT
        return v
    }

    func updateNSView(_ v: ParticleBurstNSView, context: Context) {
        v.emission = emission
        v.colors = colors
        v.needsDisplay = true
    }
}

// MARK: - The showcase mock (wired into Gallery's `.particles` family)

/// The whole particle specimen for one theme card: two live stages — 花火 and
/// 紙吹雪 — each painting the REAL `drawParticles`, plus a fact legend.
struct MockParticles: View {
    let p: ResolvedPalette

    /// Theme accent + festive hues — the burst inherits the theme while
    /// staying celebratory (perch's "accent + gold/pink/cyan", generalized).
    private var burstColors: [UInt32] {
        [hexU32(p.primary), hexU32(p.secondary)] + festiveHues
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Effects · particles — rollBurst → resolveParticles (closed-form) → the real drawParticles")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            HStack(spacing: 12) {
                stage("花火 · fireworks", emission: .fireworks)
                stage("紙吹雪 · confetti", emission: .confetti)
            }
            legend
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: p.background ?? .underPageBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(nsColor: p.border), lineWidth: 1))
    }

    /// One labelled live stage — a contained dark-or-theme panel the burst
    /// plays inside, with a "● live" tag so a screenshot reads as moving.
    private func stage(_ title: String, emission: ParticleEmission) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(title)
                    .font(sysFont(8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.foreground))
                liveDot
            }
            ParticleFieldView(emission: emission, colors: burstColors)
                .frame(height: 132 * uiScale)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: p.background ?? .underPageBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: p.border), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .frame(maxWidth: .infinity)
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

    /// The atom's facts, read off the vocabulary (no hard-coded numbers drift).
    private var legend: some View {
        HStack(spacing: 6) {
            Text("intensity").font(sysFont(8, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))
            ForEach(EffectIntensity.allCases, id: \.self) { i in
                HStack(spacing: 3) {
                    Text(i.rawValue)
                        .font(sysFont(8, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(nsColor: p.foreground))
                    Text(String(format: "%.1f×", i.multiplier))
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
