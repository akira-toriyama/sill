// prism — the LIVE ink-splatter bench.
//
// `Effects`' `SplatterShape` (rollSplatter → alpha(now:) → drawInkSplatter) is
// pure geometry + a draw helper, so — like the particle bench — the way to
// PROVE it works is to DRIVE it. This hosts the REAL `drawInkSplatter` in a
// tiny `SplatterNSView` that re-stamps a fresh splat on a fixed period and
// fades it (hold ⅔ → fade ⅓), painting it each frame. Theme-tinted: the splat
// units pick from the card's accent + festive hues, so a single stamp can land
// 2–3 differently-coloured splats (the Splatoon multi-shot feel).
//
// A `PRISM_PARTICLE_T` env override freezes a deterministic frame (and a fixed
// seed) for a static screenshot; absent it, the bench runs live.

import SwiftUI
import AppKit
import Palette
import PaletteKit
import Effects

/// Re-stamp cadence — the splat's lifetime plus a short beat.
private let splatPeriod: Double = 1.4 + 0.4

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

// MARK: - The live NSView (hosts the REAL drawInkSplatter renderer)

/// Re-stamps a fresh `SplatterShape` at its centre every `splatPeriod` and
/// paints it with `drawInkSplatter`. Owns a 60 Hz redraw timer; honors a
/// `previewT` freeze (with a fixed seed) for deterministic capture.
final class SplatterNSView: NSView {
    var colors: [UInt32] = splatHues { didSet { needsDisplay = true } }
    var previewT: Double?

    private var shape: SplatterShape?
    private var timer: Timer?

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { timer?.invalidate(); timer = nil; return }
        guard previewT == nil, timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var size: Double { Double(min(bounds.width, bounds.height)) * 0.78 }
    private var center: (x: Double, y: Double) { (x: Double(bounds.midX), y: Double(bounds.midY)) }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 1, bounds.height > 1 else { return }

        // Freeze mode — one deterministic frame (fixed seed + held opacity).
        if let pt = previewT {
            let s = shape ?? rollSplatter(at: center, size: size, colors: colors,
                                          seed: 0xC0FFEE, now: 0, duration: 1.4)
            shape = s
            drawInkSplatter(s, now: max(0, min(1, pt)) * 1.4)
            return
        }

        // Live — re-stamp once the period elapses (pop, hold, fade, beat).
        let now = CACurrentMediaTime()
        if shape == nil || now - (shape?.startedAt ?? 0) >= splatPeriod {
            shape = rollSplatter(at: center, size: size, colors: colors,
                                 seed: nil, now: now, duration: 1.4)
        }
        if let s = shape { drawInkSplatter(s, now: now) }
    }
}

// MARK: - SwiftUI bridge

struct SplatterFieldView: NSViewRepresentable {
    let colors: [UInt32]

    private static let previewT: Double? =
        ProcessInfo.processInfo.environment["PRISM_PARTICLE_T"].flatMap(Double.init)

    func makeNSView(context: Context) -> SplatterNSView {
        let v = SplatterNSView()
        v.colors = colors
        v.previewT = Self.previewT
        return v
    }

    func updateNSView(_ v: SplatterNSView, context: Context) {
        v.colors = colors
        v.needsDisplay = true
    }
}

// MARK: - The showcase mock (wired into Gallery's `.particles` family)

/// The ink-splatter specimen for one theme card: a single live stage that
/// re-stamps a fresh splat (theme accent + festive hues) painting the REAL
/// `drawInkSplatter`, plus a fact note.
struct MockSplatter: View {
    let p: ResolvedPalette

    private var inkColors: [UInt32] {
        [splatHex(p.primary), splatHex(p.secondary)] + splatHues
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Effects · ink splatter — rollSplatter → alpha(now:) → the real drawInkSplatter (Splatoon decal)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            HStack(spacing: 5) {
                Text("インク · splatter")
                    .font(sysFont(8.5, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.foreground))
                liveDot
            }
            SplatterFieldView(colors: inkColors)
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
