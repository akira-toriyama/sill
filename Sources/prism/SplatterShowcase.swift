// prism — the LIVE ink-splatter bench (now a CONSUMER of ThemeKitUI).
//
// `Effects`' `SplatterShape` (rollSplatter → alpha(now:) → drawInkSplatter) is
// pure geometry + a draw helper. #17a promoted the live host into the public
// `ThemeKitUI.InkSplatterView` (a thin `NSViewRepresentable` owning the redraw
// clock + painting the REAL `drawInkSplatter`); prism just drives it (drift-zero,
// the #16 pattern). It re-stamps a fresh splat on a fixed period and fades it
// (hold ⅔ → fade ⅓). Theme-tinted: the splat units pick from the card's accent +
// festive hues, so a single stamp can land 2–3 differently-coloured splats.
//
// `PRISM_PARTICLE_T` freezes a deterministic frame (a stable seed kicks in for a
// frozen view with no explicit seed); absent it, the bench runs live.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import Effects
import ThemeKitUI

/// Festive base hues a splat mixes with the theme accent.
private let splatHues: [UInt32] = [0xFFD700, 0xFF6EC7, 0x00E5FF, 0x9EFF00, 0xBC6BFF]

/// `0xRRGGBB` for a resolved `NSColor` (sRGB).
private func splatHex(_ c: NSColor) -> UInt32 {
    guard let s = c.usingColorSpace(.sRGB) else { return 0xFFFFFF }
    let r = UInt32((s.redComponent * 255).rounded())
    let g = UInt32((s.greenComponent * 255).rounded())
    let b = UInt32((s.blueComponent * 255).rounded())
    return (r << 16) | (g << 8) | b
}

/// `PRISM_PARTICLE_T` (0…1) freezes a deterministic splatter frame.
private let splatterFreezeT: Double? =
    ProcessInfo.processInfo.environment["PRISM_PARTICLE_T"].flatMap(Double.init)

// MARK: - The showcase mock (wired into Gallery's `.particles` family)

/// The ink-splatter specimen for one theme card: a single live stage that
/// re-stamps a fresh splat (theme accent + festive hues) driving the REAL
/// `InkSplatterView`, plus a fact note.
struct MockSplatter: View {
    let p: ResolvedPalette

    private var inkColors: [UInt32] {
        [splatHex(p.primary), splatHex(p.secondary)] + splatHues
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Effects · ink splatter — rollSplatter → alpha(now:) → the real InkSplatterView (Splatoon decal)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            HStack(spacing: 5) {
                Text("インク · splatter")
                    .font(sysFont(8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.foreground))
                liveDot
            }
            InkSplatterView(colors: inkColors, duration: 1.4, loopPeriod: 1.4 + 0.4,
                            frozen: splatterFreezeT)
                .frame(height: 150 * uiScale)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: p.background ?? .underPageBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: p.border), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text("2–3 units · tendril body + wet rim + 3–6 droplets · hold ⅔ → fade ⅓ · seeded (deterministic)")
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
