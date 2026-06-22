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
import Effects      // CanonicalSprite, SpriteColor, drawPixelSprite, drawPacMan, drawLinePets, drawChompCorridor
import ThemeKit     // phosphorImage — the bonus-icon stand-in for the corridor

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

// MARK: - The directional-eye ghost strip (#12 Ph3)

/// The four UPRIGHT Blinky gazes side by side — up · right · down · left — each
/// WADDLING live. This is the #12 Ph3 directional ghost the line-pet now uses: it
/// stays vertical (no tumbling with the lap) and only swivels its 2×2 pupils
/// toward travel (`GhostLook.facing` snaps the tangent to a cardinal). Drawn big
/// enough to read the gaze; `isFlipped` so row 0 (the dome) sits at the TOP.
final class DirectionalGhostNSView: NSView {
    var previewNow: Double?
    private var timer: Timer?

    override var isFlipped: Bool { true }

    private let cell: CGFloat = 3.0 * uiScale
    private let pad: CGFloat = 14 * uiScale
    private let gap: CGFloat = 20 * uiScale

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
        var x = pad
        for look in [GhostLook.up, .right, .down, .left] {
            let pose = ThemedTransition.frameStep(
                now: now, hz: CanonicalSprite.waddleHz,
                frames: CanonicalSprite.ghostFrames(look: look))
            drawPixelSprite(pose, cell: cell, at: CGPoint(x: x, y: pad))
            x += CGFloat(pose.width) * cell + gap
        }
    }
}

struct DirectionalGhostView: NSViewRepresentable {
    func makeNSView(context: Context) -> DirectionalGhostNSView {
        let v = DirectionalGhostNSView()
        v.previewNow = chompFreezeNow
        return v
    }
    func updateNSView(_ v: DirectionalGhostNSView, context: Context) { v.needsDisplay = true }
}

// MARK: - The PathPet — pac/ghost walking an arbitrary gesture line (#12 Ph3)

/// A zigzag gesture polyline inset into `r` (y-up): x marches left→right in equal
/// steps; y alternates min/max so the pet TUMBLES through sharp corners — the
/// tangent orientation + the faceLag follow are obvious at a glance. `segs` is
/// the corner count.
private func zigzagPath(in r: CGRect, segs: Int = 4) -> [CGPoint] {
    guard segs >= 1, r.width > 0, r.height > 0 else { return [] }
    return (0...segs).map { i in
        CGPoint(x: r.minX + r.width * CGFloat(i) / CGFloat(segs),
                y: (i % 2 == 0) ? r.minY : r.maxY)
    }
}

/// Hosts the REAL `drawChompPath` walking a zigzag at this view's scale — the
/// #12 Ph3 "first MOVING card". NON-flipped (y-up), per `drawChompPath`'s
/// contract ("+y up" = `GhostLook.facing`). `valid == false` swaps the chasing
/// pac for the UPRIGHT Blinky panicking in place (2-D `dampedSine` buzz).
final class PathPetNSView: NSView {
    var valid = true
    var petScale: CGFloat = 2.4
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
        let track = bounds.insetBy(dx: 26 * uiScale, dy: 22 * uiScale)
        // faceLag ≈ one pac diameter (footprint 14pt × petScale) so the head
        // clearly leads the face by a body length at any tier; 0 for the ghost.
        let lag = valid ? petScale * 15 * uiScale : 0
        drawChompPath(zigzagPath(in: track), now: now, valid: valid,
                      scale: petScale * uiScale, speed: 60 * uiScale, faceLag: lag)
    }
}

struct PathPetView: NSViewRepresentable {
    var valid = true
    var scale: CGFloat = 2.4
    func makeNSView(context: Context) -> PathPetNSView {
        let v = PathPetNSView()
        v.valid = valid
        v.petScale = scale
        v.previewNow = chompFreezeNow
        return v
    }
    func updateNSView(_ v: PathPetNSView, context: Context) {
        v.valid = valid; v.petScale = scale; v.needsDisplay = true
    }
}

// MARK: - The Neon Corridor — the composite arcade maze (#12 Ph4)

/// An orthogonal (90°-snapped) serpentine corridor inset into `r` (y-up): a comb
/// of horizontal lanes joined by short verticals, so the centreline turns ONLY at
/// right angles — exactly what the 2-stroke walls + interior fillets are built for
/// (a true Pac-Man maze, not the freeform PathPet zigzag). `lanes` = lane count.
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
/// `@MainActor` (its initializer calls the `@MainActor` `phosphorImage` loader).
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

/// Hosts the REAL `drawChompCorridor` walking an orthogonal maze at this view's
/// scale — the #12 Ph4 composite card (2-stroke walls + fillets + pellet row + the
/// Ph3 pac walking it). NON-flipped (y-up), per the `drawChompPath` contract.
/// `valid == false` swaps the pac for the panicking Blinky on the same corridor.
final class CorridorNSView: NSView {
    var valid = true
    var tier: ScaleTier = .s
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
        NSColor(white: 0.04, alpha: 1).setFill(); bounds.fill()
        let now = previewNow ?? CACurrentMediaTime()
        // Inset so the widest stroke (road + both walls) clears the card edge.
        let track = bounds.insetBy(dx: 34 * uiScale, dy: 30 * uiScale)
        drawChompCorridor(orthogonalMazePath(in: track, lanes: 3),
                          now: now, valid: valid, tier: tier, scale: uiScale,
                          speed: 64 * uiScale, icon: corridorBonusIcon)
    }
}

struct NeonCorridorView: NSViewRepresentable {
    var valid = true
    var tier: ScaleTier = .s
    func makeNSView(context: Context) -> CorridorNSView {
        let v = CorridorNSView()
        v.valid = valid; v.tier = tier
        v.previewNow = chompFreezeNow
        return v
    }
    func updateNSView(_ v: CorridorNSView, context: Context) {
        v.valid = valid; v.tier = tier; v.needsDisplay = true
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

            Text("directional ghost (#12 Ph3) — UPRIGHT: the body no longer tumbles with the lap; only the pupils swivel toward travel. up · right · down · left:")
                .font(sysFont(7.5, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            DirectionalGhostView()
                .frame(height: 80 * uiScale)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: NSColor(white: 0.04, alpha: 1))))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: p.border), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text("PathPet (#12 Ph3) — the first MOVING card: pac walks an arbitrary gesture line. drawChompPath marches a head (the glowing dot) along the arc length; the face FOLLOWS by faceLag, tumbling so the mouth opens along travel (markAtArcLength + tangent):")
                .font(sysFont(7.5, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            PathPetView(valid: true, scale: 2.4)
                .frame(height: 124 * uiScale)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: NSColor(white: 0.04, alpha: 1))))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: p.border), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text("mismatch — the gesture matched no rule: pac SWAPS to the upright Blinky (eyes track the travel cardinal) panicking as it follows — a 2-D dampedSine buzz (co-prime 6/7):")
                .font(sysFont(7.5, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            PathPetView(valid: false, scale: 1.9)
                .frame(height: 84 * uiScale)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: NSColor(white: 0.04, alpha: 1))))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: p.border), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text("ChompCorridor (#12 Ph5) — the FULL loop: the pac walks the maze EATING the pellet row (each vanishes as the mouth reaches it, all respawn on the lap wrap); a cherry / app-icon eat flashes the walls (EffectSpec.chomp.flash, ~450ms) and floats a +N score (bonus ladder, rise+fade). All derived PURELY from now — PRISM_CHOMP_T freezes it:")
                .font(sysFont(7.5, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            NeonCorridorView(valid: true, tier: .s)
                .frame(height: 200 * uiScale)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: NSColor(white: 0.04, alpha: 1))))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: p.border), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text("mismatch corridor — the gesture matched no rule: the panicking Blinky walks the same maze (valid == false):")
                .font(sysFont(7.5, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            NeonCorridorView(valid: false, tier: .s)
                .frame(height: 120 * uiScale)
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
