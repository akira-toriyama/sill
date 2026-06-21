// prism — the PixelArt (chomp arcade decal) bench.
//
// PixelArt is pure pixel geometry (`PixelSprite`, `pacManCells`, `ScaleTier`)
// and Effects owns the blitter (`drawPixelSprite` / `drawPacMan`), so — like the
// splatter + trail benches — the way to PROVE it is to DRAW it. This hosts the
// REAL `drawPacMan` / `drawPixelSprite` in a tiny `isFlipped` `PixelArtNSView`
// (pixel grids read row 0 at top). Ph1 is STATIC (a fixed mouth phase), so the
// card is deterministic with no clock and no freeze env — the mouth animation
// (`Motion.frameStep`) lands in Ph2.
//
// The colours are INTRINSIC to the sprites (always arcade yellow / red / blue),
// so the card reads identically across every theme — that is the point: chomp is
// a self-contained arcade look, not a role-driven one.

import SwiftUI
import AppKit
import PaletteKit   // ResolvedPalette
import PixelArt
import Effects   // CanonicalSprite, SpriteColor, drawPixelSprite, drawPacMan

/// The Pac-Man face mouth shown statically — clearly open so it reads as chomp.
private let demoMouthPhase: Double = 0.55
/// Pac-Man face diameter in cells (an odd count centres the mouth wedge).
private let pacDiameter = 13

// MARK: - The live NSView (hosts the REAL drawPacMan / drawPixelSprite)

/// Blits the three canonical sprites with the real Effects helpers: a row of all
/// four sprites at one tier, then a `ScaleTier` ladder of the Pac-Man face at
/// ×2 / ×3 / ×4.5. `isFlipped` so row 0 draws at the TOP (the grid convention).
/// Static — no timer.
final class PixelArtNSView: NSView {
    override var isFlipped: Bool { true }

    private let unit: CGFloat = 2.0 * uiScale       // base cell, pre-tier
    private let pad: CGFloat = 14 * uiScale
    private let gap: CGFloat = 12 * uiScale          // between sprites in a row
    private let rowGap: CGFloat = 16 * uiScale

    private func cell(_ t: ScaleTier) -> CGFloat { CGFloat(t.multiplier) * unit }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 1, bounds.height > 1 else { return }

        // Arcade black field — chomp is theme-invariant, so the sprites sit on
        // near-black regardless of the card's theme.
        NSColor(white: 0.04, alpha: 1).setFill()
        bounds.fill()

        // Row 1 — the three canonical sprites (+ the ghost's 2nd waddle pose) at
        // tier .m, so the authored art reads clearly.
        let m = cell(.m)
        var x = pad
        let y1 = pad
        drawPacMan(diameterCells: pacDiameter,
                   mouthHalfRad: mouthHalfRad(phase: demoMouthPhase),
                   cell: m, at: CGPoint(x: x, y: y1))
        x += CGFloat(pacDiameter) * m + gap
        drawPixelSprite(CanonicalSprite.cherry, cell: m, at: CGPoint(x: x, y: y1))
        x += CGFloat(CanonicalSprite.cherry.width) * m + gap
        drawPixelSprite(CanonicalSprite.ghost, cell: m, at: CGPoint(x: x, y: y1))
        x += CGFloat(CanonicalSprite.ghost.width) * m + gap
        drawPixelSprite(CanonicalSprite.ghostAlt, cell: m, at: CGPoint(x: x, y: y1))

        // Row 2 — the ScaleTier ladder: the Pac-Man face (pacManCells geometry)
        // at ×2 / ×3 / ×4.5, baseline-aligned at the band top.
        let y2 = y1 + CGFloat(CanonicalSprite.ghost.height) * m + rowGap
        x = pad
        for t in ScaleTier.allCases {
            let c = cell(t)
            drawPacMan(diameterCells: pacDiameter,
                       mouthHalfRad: mouthHalfRad(phase: demoMouthPhase),
                       cell: c, at: CGPoint(x: x, y: y2))
            x += CGFloat(pacDiameter) * c + gap
        }
    }
}

// MARK: - SwiftUI bridge

struct PixelArtFieldView: NSViewRepresentable {
    func makeNSView(context: Context) -> PixelArtNSView { PixelArtNSView() }
    func updateNSView(_ v: PixelArtNSView, context: Context) { v.needsDisplay = true }
}

// MARK: - The showcase mock (wired into Gallery's `.particles` family)

/// The PixelArt specimen for one theme card: the three canonical arcade sprites
/// drawn by the REAL Effects blitter, plus a `ScaleTier` size ladder + a fact
/// note. Theme-invariant by design (intrinsic arcade colours).
struct MockPixelArt: View {
    let p: ResolvedPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("PixelArt + Effects · arcade decals — pacManCells (circle − mouth wedge) + 12×13 cherry + 14×14 ghost, crisp integer cells")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            PixelArtFieldView()
                // The NSView's interior metrics (unit/pad/gap/rowGap) are ALL × uiScale,
                // so the host frame must scale with the gallery knob too (siblings do the
                // same). Interior bottom ≈ 231pt @ uiScale=1; 255 leaves a margin.
                .frame(height: 255 * uiScale)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: NSColor(white: 0.04, alpha: 1))))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: p.border), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text("pac · cherry · ghost (+alt waddle) @ .m · then the Pac-Man face at ×2 ×3 ×4.5 (ScaleTier) · intrinsic arcade palette · static")
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
}
