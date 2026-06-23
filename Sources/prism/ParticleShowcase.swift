// prism — the LIVE particle-burst bench (now a CONSUMER of ThemeKitUI).
//
// `Effects`' particle atom (`rollBurst` / `resolveParticles` / `drawParticles`)
// is pure MATH + a draw helper, not a widget. #17a promoted the live host into
// the public `ThemeKitUI.ParticleBurstView` (a thin `NSViewRepresentable` that
// owns the redraw clock and paints the REAL `drawParticles`); prism drops its
// in-tree bridge and just drives that public view — drift-zero, the #16 pattern.
//
// Two stages per card — 花火 fireworks (radial glow) and 紙吹雪 confetti (a
// party-popper of tumbling paper) — feed the SAME public view different inputs
// (emitter, duration, cooling, loop), so every theme shows both emissions cycling
// live. Theme-tinted: each burst's palette is the card's `primary` + `secondary`
// plus a festive constant set. `PRISM_PARTICLE_T=0.35` freezes a deterministic
// mid-burst frame (passed straight to the view's public `frozen` seam).

import SwiftUI
import AppKit
import Palette
import PaletteKit
import Effects
import ThemeKitUI

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

/// `PRISM_PARTICLE_T` (0…1) freezes a deterministic mid-burst frame for a static
/// screenshot; absent it, the bench runs live.
private let particleFreezeT: Double? =
    ProcessInfo.processInfo.environment["PRISM_PARTICLE_T"].flatMap(Double.init)

// MARK: - The showcase mock (wired into Gallery's `.particles` family)

/// The whole particle specimen for one theme card: two live stages — 花火 and
/// 紙吹雪 — each driving the REAL `ParticleBurstView`, plus a fact legend.
struct MockParticles: View {
    let p: ResolvedPalette

    /// Theme accent + festive hues — the burst inherits the theme while
    /// staying celebratory (perch's "accent + gold/pink/cyan", generalized).
    private var burstColors: [UInt32] {
        [hexU32(p.primary), hexU32(p.secondary)] + festiveHues
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Effects · particles — rollBurst → resolveParticles (closed-form) → the real ParticleBurstView (ThemeKitUI)")
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
    /// plays inside, with a "● live" tag so a screenshot reads as moving. The
    /// per-emission inputs (emitter, duration, cooling) that the in-tree NSView
    /// used to compute internally are now passed to the public view.
    private func stage(_ title: String, emission: ParticleEmission) -> some View {
        // The burst origin: fireworks from upper-centre; confetti shoots up from
        // near the bottom edge (a party popper). The view is flipped (+y down).
        let emitters: (CGRect) -> [CGPoint] = { r in
            switch emission {
            case .fireworks: return [CGPoint(x: r.midX, y: r.height * 0.46)]
            case .confetti:  return [CGPoint(x: r.midX, y: r.height * 0.94)]
            }
        }
        let duration: TimeInterval = emission == .fireworks ? 1.05 : 1.6
        // Fireworks cool + shrink as they fade; confetti paper keeps its size.
        let radiusSpeed: Double = emission == .fireworks ? -2.0 : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(title)
                    .font(sysFont(8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.foreground))
                liveDot
            }
            ParticleBurstView(emission: emission, colors: burstColors, intensity: .bold,
                              duration: duration, radiusSpeed: radiusSpeed,
                              loopPeriod: duration + 0.4, scale: uiScale,
                              frozen: particleFreezeT, emitters: emitters)
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
