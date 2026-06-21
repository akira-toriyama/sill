// prism — the LIVE PixelArt (chomp arcade decal) bench.
//
// PixelArt is pure pixel geometry (`PixelSprite`, `pacManCells`, `ScaleTier`)
// and Effects owns the blitter (`drawPixelSprite` / `drawPacMan`), so — like the
// splatter + trail benches — the way to PROVE it is to DRAW it. This hosts the
// REAL `drawPacMan` / `drawPixelSprite` in a tiny `isFlipped` `PixelArtNSView`
// (pixel grids read row 0 at top).
//
// #12 Ph2 makes it LIVE: an internal 60 Hz clock drives `Motion.frameStep`, so
// the Pac-Man mouth SNAPS through `[0,0.5,1,0.5]` at 5 Hz and the ghost WADDLES
// (ghost⇄ghostAlt) — the same discrete sprite-swap the unified line-pets use. A
// second NON-flipped `LinePetWalkNSView` runs the REAL `drawLinePets` (now pixel)
// around a perimeter at a small line-pet scale — that is the verification-gate
// view (does the arcade sprite still read when it is tiny?). A `PRISM_CHOMP_T`
// env override (absolute seconds) freezes a deterministic frame for capture.
//
// The colours are INTRINSIC to the sprites (always arcade yellow / red / blue),
// so the card reads identically across every theme — that is the point: chomp is
// a self-contained arcade look, not a role-driven one.

import SwiftUI
import AppKit
import PaletteKit   // ResolvedPalette
import PixelArt     // pacManCells, mouthHalfRad, chompMouthFrames/Hz, ScaleTier
import Motion       // ThemedTransition.frameStep — the discrete sprite-swap sampler
import Effects      // CanonicalSprite, SpriteColor, drawPixelSprite, drawPacMan, drawLinePets

/// Pac-Man face diameter in cells (an odd count centres the mouth wedge).
private let pacDiameter = 13

/// `PRISM_CHOMP_T` (absolute seconds) freezes BOTH live views at one clock value
/// for a deterministic screenshot; absent it, the bench runs live.
private let chompFreezeNow: Double? =
    ProcessInfo.processInfo.environment["PRISM_CHOMP_T"].flatMap(Double.init)

// MARK: - A shared 60 Hz redraw tick (the ParticleBurstNSView pattern)

/// Start a 60 Hz `needsDisplay` timer on `view` while it is in a window, unless
/// it is frozen (`previewNow != nil`). Returns the timer so the caller can hold
/// + invalidate it. Centralised so both live NSViews share one tick shape.
@MainActor
private func startRedrawTick(for view: NSView, frozen: Bool) -> Timer? {
    guard !frozen else { return nil }
    let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak view] _ in
        MainActor.assumeIsolated { view?.needsDisplay = true }
    }
    RunLoop.main.add(t, forMode: .common)
    return t
}

// MARK: - The live sprite NSView (hosts the REAL drawPacMan / drawPixelSprite)

/// Blits the canonical sprites with the real Effects helpers: a row of pac /
/// cherry / ghost at one tier (the mouth flaps + the ghost waddles, live), then a
/// `ScaleTier` ladder of the (flapping) Pac-Man face at ×2 / ×3 / ×4.5.
/// `isFlipped` so row 0 draws at the TOP (the grid convention).
final class PixelArtNSView: NSView {
    /// When set (env `PRISM_CHOMP_T`), render ONE frozen frame at that absolute
    /// clock value instead of running live.
    var previewNow: Double?
    private var timer: Timer?

    override var isFlipped: Bool { true }

    private let unit: CGFloat = 2.0 * uiScale       // base cell, pre-tier
    private let pad: CGFloat = 14 * uiScale
    private let gap: CGFloat = 12 * uiScale          // between sprites in a row
    private let rowGap: CGFloat = 16 * uiScale

    private func cell(_ t: ScaleTier) -> CGFloat { CGFloat(t.multiplier) * unit }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { timer?.invalidate(); timer = nil; return }
        guard timer == nil else { return }
        timer = startRedrawTick(for: self, frozen: previewNow != nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 1, bounds.height > 1 else { return }

        // Arcade black field — chomp is theme-invariant, so the sprites sit on
        // near-black regardless of the card's theme.
        NSColor(white: 0.04, alpha: 1).setFill()
        bounds.fill()

        // The injected clock → the discrete swaps (mouth phase + ghost pose).
        let now = previewNow ?? CACurrentMediaTime()
        let mouth = mouthHalfRad(phase: ThemedTransition.frameStep(
            now: now, hz: chompMouthHz, frames: chompMouthFrames))
        let ghostPose = ThemedTransition.frameStep(
            now: now, hz: CanonicalSprite.waddleHz, frames: CanonicalSprite.waddleFrames)

        // Row 1 — pac (live mouth) · cherry · ghost (live waddle pose), at tier .m.
        let m = cell(.m)
        var x = pad
        let y1 = pad
        drawPacMan(diameterCells: pacDiameter, mouthHalfRad: mouth, cell: m, at: CGPoint(x: x, y: y1))
        x += CGFloat(pacDiameter) * m + gap
        drawPixelSprite(CanonicalSprite.cherry, cell: m, at: CGPoint(x: x, y: y1))
        x += CGFloat(CanonicalSprite.cherry.width) * m + gap
        drawPixelSprite(ghostPose, cell: m, at: CGPoint(x: x, y: y1))

        // Row 2 — the ScaleTier ladder: the Pac-Man face at ×2 / ×3 / ×4.5, all
        // flapping in sync, baseline-aligned at the band top.
        let y2 = y1 + CGFloat(CanonicalSprite.ghost.height) * m + rowGap
        x = pad
        for t in ScaleTier.allCases {
            let c = cell(t)
            drawPacMan(diameterCells: pacDiameter, mouthHalfRad: mouth, cell: c, at: CGPoint(x: x, y: y2))
            x += CGFloat(pacDiameter) * c + gap
        }
    }
}

// MARK: - The line-pet perimeter walk (the verification-gate view)

/// The REAL `drawLinePets` (now PIXEL, #12 Ph2) walking the chomp + ghost around
/// this view's perimeter at a small line-pet `scale` — so the gate question
/// ("does the arcade sprite still read when it is tiny?") is answerable at a
/// glance. NON-flipped (y-up), per `drawLinePets`' contract ("top" = maxY).
final class LinePetWalkNSView: NSView {
    var petScale: CGFloat = 1.6
    var previewNow: Double?
    private var timer: Timer?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { timer?.invalidate(); timer = nil; return }
        guard timer == nil else { return }
        timer = startRedrawTick(for: self, frozen: previewNow != nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        NSColor(white: 0.04, alpha: 1).setFill()
        bounds.fill()
        let now = previewNow ?? CACurrentMediaTime()
        let track = bounds.insetBy(dx: 18 * uiScale, dy: 18 * uiScale)
        drawLinePets([.chomp, .ghost], on: track, now: now,
                     scale: petScale * uiScale, speed: 70 * uiScale)
    }
}

// MARK: - SwiftUI bridges

struct PixelArtFieldView: NSViewRepresentable {
    func makeNSView(context: Context) -> PixelArtNSView {
        let v = PixelArtNSView()
        v.previewNow = chompFreezeNow
        return v
    }
    func updateNSView(_ v: PixelArtNSView, context: Context) { v.needsDisplay = true }
}

struct LinePetWalkView: NSViewRepresentable {
    let scale: CGFloat
    func makeNSView(context: Context) -> LinePetWalkNSView {
        let v = LinePetWalkNSView()
        v.petScale = scale
        v.previewNow = chompFreezeNow
        return v
    }
    func updateNSView(_ v: LinePetWalkNSView, context: Context) {
        v.petScale = scale
        v.needsDisplay = true
    }
}

// MARK: - The showcase mock (wired into Gallery's `.particles` family)

/// The PixelArt specimen for one theme card: the canonical arcade sprites drawn
/// by the REAL Effects blitter (mouth flapping + ghost waddling LIVE), a
/// `ScaleTier` size ladder, and the unified pixel line-pets walking a perimeter
/// at a small scale (the verification-gate view). Theme-invariant by design.
struct MockPixelArt: View {
    let p: ResolvedPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Text("PixelArt + Effects · arcade decals — pacManCells wedge + 12×13 cherry + 14×14 ghost; mouth flaps 5 Hz, ghost waddles (Motion.frameStep)")
                    .font(sysFont(9, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.muted))
                liveDot
            }

            PixelArtFieldView()
                // The NSView's interior metrics (unit/pad/gap/rowGap) are ALL × uiScale,
                // so the host frame must scale with the gallery knob too. Interior bottom
                // ≈ 231pt @ uiScale=1; 255 leaves a margin.
                .frame(height: 255 * uiScale)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: NSColor(white: 0.04, alpha: 1))))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: p.border), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text("unified line-pets — the REAL drawLinePets, now PIXEL: chomp + ghost lap the border at a small scale (#12 Ph2 gate: does it read when tiny?)")
                .font(sysFont(7.5, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            LinePetWalkView(scale: 1.6)
                .frame(height: 96 * uiScale)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: NSColor(white: 0.04, alpha: 1))))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: p.border), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text("pac · cherry · ghost @ .m · face ladder ×2 ×3 ×4.5 (ScaleTier) · intrinsic arcade palette · clock injected (PRISM_CHOMP_T freezes)")
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
