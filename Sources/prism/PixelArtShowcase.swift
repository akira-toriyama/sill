// prism — the LIVE PixelArt (chomp arcade decal) bench (now a CONSUMER of ThemeKitUI).
//
// PixelArt is pure pixel geometry (`PixelSprite`, `pacManCells`, `ScaleTier`)
// and Effects owns the blitter (`drawPixelSprite` / `drawPacMan`). #17a promoted
// the reusable live hosts into public `ThemeKitUI` bridges:
//   • `PixelSpriteView`   — one (optionally animated) sprite (the antialias-off
//                            blitter an app's pixel pet uses);
//   • `LinePetsView`      — pets lapping the border;
//   • `PathPetView`       — a pet walking an arbitrary gesture polyline;
//   • `ChompCorridorView` — the composite arcade maze.
// prism drives those public views (drift-zero, the #16 pattern). What stays
// in-tree here is only the pac + ScaleTier LADDER (`PacLadderView`) — a catalog
// reference for `pacManCells` + `ScaleTier` (no app renders a labelled size
// ladder), and the demo PATH/maze generators + bonus-icon stand-in that prism
// feeds the public views.
//
// The colours are INTRINSIC to the sprites (always arcade yellow / red / blue),
// so the card reads identically across every theme. `PRISM_CHOMP_T` (absolute
// seconds) freezes a deterministic frame (passed to each view's `frozen` seam).

import SwiftUI
import AppKit
import PaletteKit   // ResolvedPalette
import PixelArt     // pacManCells, mouthHalfRad, chompMouthFrames/Hz, ScaleTier
import Motion       // ThemedTransition.frameStep — the discrete sprite-swap sampler
import Effects      // CanonicalSprite, SpriteColor, drawPacMan, GhostLook
import ThemeKit     // phosphorImage — the bonus-icon stand-in for the corridor
import ThemeKitUI   // PixelSpriteView, LinePetsView, PathPetView, ChompCorridorView

/// Pac-Man face diameter in cells (an odd count centres the mouth wedge).
private let pacDiameter = 13

/// `PRISM_CHOMP_T` (absolute seconds) freezes every live view at one clock value
/// for a deterministic screenshot; absent it, the bench runs live.
private let chompFreezeNow: Double? =
    ProcessInfo.processInfo.environment["PRISM_CHOMP_T"].flatMap(Double.init)

// MARK: - Demo path / maze generators + bonus icon (fed to the public views)

/// A zigzag gesture polyline inset into `r` (y-up): x marches left→right in equal
/// steps; y alternates min/max so the pet TUMBLES through sharp corners. `segs`
/// is the corner count.
private func zigzagPath(in r: CGRect, segs: Int = 4) -> [CGPoint] {
    guard segs >= 1, r.width > 0, r.height > 0 else { return [] }
    return (0...segs).map { i in
        CGPoint(x: r.minX + r.width * CGFloat(i) / CGFloat(segs),
                y: (i % 2 == 0) ? r.minY : r.maxY)
    }
}

/// An orthogonal (90°-snapped) serpentine corridor inset into `r` (y-up): a comb
/// of horizontal lanes joined by short verticals, so the centreline turns ONLY at
/// right angles — exactly what the 2-stroke walls + interior fillets are built
/// for. `lanes` = lane count.
private func orthogonalMazePath(in r: CGRect, lanes: Int = 3) -> [CGPoint] {
    guard lanes >= 2, r.width > 0, r.height > 0 else { return [] }
    let gap = r.height / CGFloat(lanes - 1)
    var pts: [CGPoint] = []
    for i in 0..<lanes {
        let y = r.minY + gap * CGFloat(i)
        let ltr = (i % 2 == 0)                       // serpentine: alternate run direction
        pts.append(CGPoint(x: ltr ? r.minX : r.maxX, y: y))
        pts.append(CGPoint(x: ltr ? r.maxX : r.minX, y: y))
    }
    return pts
}

/// A bright bonus stand-in for the app-icon pellet band: an app passes its REAL
/// icon, but prism tints a Phosphor star cyan so it shows on the black road.
@MainActor private let corridorBonusIcon: NSImage? = {
    guard let base = phosphorImage("star", pt: 14, weight: .fill) else { return nil }
    let img = NSImage(size: base.size)
    img.lockFocus()
    NSColor(calibratedRed: 0.30, green: 0.92, blue: 1.0, alpha: 1).set()
    let rect = NSRect(origin: .zero, size: base.size)
    base.draw(in: rect)
    rect.fill(using: .sourceAtop)
    img.unlockFocus()
    img.isTemplate = false
    return img
}()

// MARK: - The pac + ScaleTier ladder (prism-local catalog reference)

/// Blits the Pac-Man face (live flapping mouth) at tier .m, then a `ScaleTier`
/// ladder of the same face at ×2 / ×3 / ×4.5 — a direct catalog reference for
/// `pacManCells` (the circle-minus-wedge) + `ScaleTier.multiplier`. `isFlipped`
/// so row 0 draws at the TOP. Stays in prism: no app renders a labelled ladder.
final class PacLadderNSView: NSView {
    var previewNow: Double?
    private let clockStart = CACurrentMediaTime()
    private var timer: Timer?

    override var isFlipped: Bool { true }

    private let unit: CGFloat = 2.0 * uiScale       // base cell, pre-tier
    private let pad: CGFloat = 14 * uiScale
    private let gap: CGFloat = 12 * uiScale
    private let rowGap: CGFloat = 16 * uiScale

    private func cell(_ t: ScaleTier) -> CGFloat { CGFloat(t.multiplier) * unit }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { timer?.invalidate(); timer = nil; return }
        guard previewNow == nil, timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        NSColor(white: 0.04, alpha: 1).setFill()
        bounds.fill()

        let now = previewNow ?? (CACurrentMediaTime() - clockStart)
        let mouth = mouthHalfRad(phase: ThemedTransition.frameStep(
            now: now, hz: chompMouthHz, frames: chompMouthFrames))

        // Row 1 — the Pac-Man face at tier .m.
        let m = cell(.m)
        let y1 = pad
        drawPacMan(diameterCells: pacDiameter, mouthHalfRad: mouth, cell: m, at: CGPoint(x: pad, y: y1))

        // Row 2 — the ScaleTier ladder: ×2 / ×3 / ×4.5, all flapping in sync.
        let y2 = y1 + CGFloat(pacDiameter) * m + rowGap
        var x = pad
        for t in ScaleTier.allCases {
            let c = cell(t)
            drawPacMan(diameterCells: pacDiameter, mouthHalfRad: mouth, cell: c, at: CGPoint(x: x, y: y2))
            x += CGFloat(pacDiameter) * c + gap
        }
    }
}

struct PacLadderView: NSViewRepresentable {
    func makeNSView(context: Context) -> PacLadderNSView {
        let v = PacLadderNSView()
        v.previewNow = chompFreezeNow
        return v
    }
    func updateNSView(_ v: PacLadderNSView, context: Context) { v.needsDisplay = true }
}

// MARK: - The showcase mock (wired into Gallery's `.particles` family)

/// The PixelArt specimen for one theme card: the public sprite/pet bridges driven
/// by the REAL Effects blitter (mouth flapping + ghost waddling LIVE), plus the
/// in-tree pac/ScaleTier catalog ladder. Theme-invariant by design.
struct MockPixelArt: View {
    let p: ResolvedPalette
    /// Bumped by the `↺ replay` button — re-identifies the live cards so they
    /// rebuild and restart their animation clocks from t=0.
    @State private var replay = 0

    /// One black arcade panel wrapping a live view (the sprites read on near-black
    /// regardless of the card's theme — chomp is a self-contained arcade look).
    private func panel<V: View>(_ height: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: NSColor(white: 0.04, alpha: 1))))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: p.border), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func caption(_ s: String) -> some View {
        Text(s)
            .font(sysFont(7.5, design: .monospaced))
            .foregroundColor(Color(nsColor: p.muted))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                liveDot
                Spacer(minLength: 6)
                replayButton
            }

            Text("PixelArt + Effects · arcade decals — pacManCells wedge + 12×13 cherry + 14×14 ghost; mouth flaps 5 Hz, ghost waddles (Motion.frameStep)")
                .font(sysFont(9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            cards.id(replay)   // ↺ replay rebuilds every live card → clocks reset to t=0
        }
        .showcasePanel(p, stroke: p.border)
    }

    @ViewBuilder private var cards: some View {
        VStack(alignment: .leading, spacing: 9) {
            caption("PixelSpriteView (ThemeKitUI) — the antialias-off blitter an app's pixel pet uses: cherry (static) · ghost (waddle), live (Motion.frameStep):")
            panel(120 * uiScale) {
                HStack(alignment: .top, spacing: 20 * uiScale) {
                    PixelSpriteView(sprite: CanonicalSprite.cherry, cell: 6 * uiScale)
                    PixelSpriteView(frames: CanonicalSprite.waddleFrames,
                                    hz: CanonicalSprite.waddleHz, cell: 6 * uiScale,
                                    frozen: chompFreezeNow)
                }
                .padding(14 * uiScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            caption("PixelSpriteView · directional — the four UPRIGHT Blinky gazes (up · right · down · left), each WADDLING live; only the pupils swivel toward travel (GhostLook):")
            panel(90 * uiScale) {
                HStack(alignment: .top, spacing: 20 * uiScale) {
                    ForEach([GhostLook.up, .right, .down, .left], id: \.self) { look in
                        PixelSpriteView(frames: CanonicalSprite.ghostFrames(look: look),
                                        hz: CanonicalSprite.waddleHz, cell: 3 * uiScale,
                                        frozen: chompFreezeNow)
                    }
                }
                .padding(14 * uiScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            caption("pac · ScaleTier ladder ×2 ×3 ×4.5 (pacManCells + ScaleTier catalog) · intrinsic arcade palette · clock injected (PRISM_CHOMP_T freezes):")
            panel(170 * uiScale) { PacLadderView() }

            caption("LinePetsView (ThemeKitUI) — the REAL drawLinePets, PIXEL: chomp + ghost lap the border at a small scale (#12 Ph2 gate: does it read when tiny?):")
            panel(96 * uiScale) {
                LinePetsView(pets: [.chomp, .ghost], inset: 18 * uiScale,
                             scale: 1.6 * uiScale, speed: 70 * uiScale, frozen: chompFreezeNow)
            }

            caption("PathPetView (ThemeKitUI) — the first MOVING card: pac walks an arbitrary gesture line. drawChompPath marches a head along the arc length; the face FOLLOWS by faceLag, tumbling so the mouth opens along travel (markAtArcLength + tangent):")
            panel(124 * uiScale) {
                PathPetView(path: { zigzagPath(in: $0.insetBy(dx: 26 * uiScale, dy: 22 * uiScale)) },
                            valid: true, scale: 2.4 * uiScale, speed: 60 * uiScale,
                            faceLag: 2.4 * 15 * uiScale, frozen: chompFreezeNow)
            }

            caption("mismatch — the gesture matched no rule: pac SWAPS to the upright Blinky (eyes track the travel cardinal) panicking as it follows — a 2-D dampedSine buzz (co-prime 6/7):")
            panel(84 * uiScale) {
                PathPetView(path: { zigzagPath(in: $0.insetBy(dx: 26 * uiScale, dy: 22 * uiScale)) },
                            valid: false, scale: 1.9 * uiScale, speed: 60 * uiScale,
                            faceLag: 0, frozen: chompFreezeNow)
            }

            caption("ChompCorridorView (#12 Ph5) — the FULL loop: pac walks the maze EATING the pellet row (each vanishes as the mouth reaches it, all respawn on the lap wrap); a cherry / app-icon eat flashes the walls (EffectSpec.chomp.flash, ~450ms) and floats a +N score. All derived PURELY from now — PRISM_CHOMP_T freezes it:")
            panel(200 * uiScale) {
                ChompCorridorView(path: { orthogonalMazePath(in: $0.insetBy(dx: 34 * uiScale, dy: 30 * uiScale), lanes: 3) },
                                  valid: true, tier: .s, icon: corridorBonusIcon,
                                  showBonuses: true, scale: uiScale, speed: 64 * uiScale,
                                  frozen: chompFreezeNow)
            }

            caption("mismatch corridor — the gesture matched no rule: the panicking Blinky walks the same maze (valid == false). Dots only (no cherry / icon bonuses — the ghost never eats):")
            panel(120 * uiScale) {
                ChompCorridorView(path: { orthogonalMazePath(in: $0.insetBy(dx: 34 * uiScale, dy: 30 * uiScale), lanes: 3) },
                                  valid: false, tier: .s, icon: corridorBonusIcon,
                                  showBonuses: false, scale: uiScale, speed: 64 * uiScale,
                                  frozen: chompFreezeNow)
            }
        }
    }

    private var replayButton: some View {
        Button { replay += 1 } label: {
            Text("↺ replay")
                .font(sysFont(9, weight: .bold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.primary))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: p.primary), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("最初から再生")
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
