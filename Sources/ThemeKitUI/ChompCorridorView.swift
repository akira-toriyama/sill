// ThemeKitUI — SwiftUI-native ChompCorridor (#17h): the composite arcade maze —
// 2-stroke neon walls + interior fillets + a centre pellet row (cherry / app-icon
// bonuses banded by `positionHash01`) + the pac (or, when `valid == false`, a
// panicking ghost) walking it EATING pellets, a wall RAINBOW FLASH + a floating
// "+N" on a bonus crossing. The SwiftUI replacement for the #17a AppKit-backed
// bridge that wrapped the Effects corridor draw: a `Canvas` + nearest-neighbor
// pixel sprites, with the wall glow isolated in its OWN `drawLayer` (SwiftUI
// `addFilter(.shadow)`, no AppKit shadow object). Owns the redraw clock (sill's
// `f(now)`). Transparent background.
//
// GENERAL: `path` (a closure of bounds) is the corridor centreline, and `icon` is
// the app's bonus pellet image — an app feeds its own maze + app icon (wand
// arcade). prism feeds an orthogonal serpentine maze + a tinted Phosphor star and
// gets the same pixels. `frozen` (absolute seconds) freezes one frame.
//
// COORDINATE / ORIENTATION (Approach A — flip the WHOLE polyline up-front)
// ───────────────────────────────────────────────────────────────────────
// The pure geometry (`polylineLength` / `roundedCornerPath` / `markAtArcLength` /
// the cursors / `interiorCorners`) is coordinate-agnostic. The old draw hosted the
// path NON-flipped (+y-UP); the SwiftUI `Canvas` is +y-DOWN, so we flip the whole
// polyline ONCE: `pts = path(bounds).map { CGPoint(x: $0.x, y: bounds.height - $0.y) }`
// and do ALL geometry on `pts`. Sprites stay UPRIGHT with NO per-sprite flip
// (`pixelImage` bakes row-0-at-TOP, upright in a +y-down canvas). The pac rotation
// is `atan2(tangent.y, tangent.x)` on the canvas-space tangent directly; the ghost
// gaze negates y (`GhostLook.facing` uses +y-UP). A score pop RISES → SUBTRACT y.
//
// FIDELITY: the pellet-KIND hash (`positionHash01`) must run on the y-UP coords to
// match #17a's exact cherry/icon placement — so we convert each canvas mark back to
// y-up (`iy = bounds.height - m.point.y`) BEFORE hashing.
//
// CLOCK: live = `TimelineView(.animation)` with a birth-relative clock
// (`context.date.timeIntervalSince(start)`, `start` a read-only `@State`);
// `frozen != nil` = a static `Canvas` at the absolute `frozen` seconds. Every drawn
// pixel is a PURE function of `now` (the sprites/cursors/eat-timeline are pure
// selectors; no randomness) — so NO `@State` is written during render.
//
// `import AppKit` is here ONLY for the `NSImage` type of the public `icon`
// payload (drawn via `Image(nsImage:)`); there is NO AppKit drawing in this file.

import SwiftUI
import AppKit   // NSImage — the pre-resolved `icon` payload type ONLY (no AppKit drawing)
import PixelArt
import Effects
import Motion   // ThemedTransition.dampedSine / Easing.easeOutCubic

public struct ChompCorridorView: View {
    /// The corridor centreline, mapped from the view's bounds (y-up). For clean
    /// 2-stroke walls + fillets it should turn at right angles.
    public var path: (CGRect) -> [CGPoint]
    /// true = pac eats the pellet row; false = the panicking ghost walks it (no eats).
    public var valid: Bool
    /// Arcade dimensions (wall/road/pellet sizing).
    public var tier: ScaleTier
    /// The bonus pellet image (e.g. the app icon). nil = no image bonus.
    public var icon: NSImage?
    public var showBonuses: Bool
    public var scale: CGFloat
    /// Lap speed in points/second.
    public var speed: CGFloat
    /// nil = live; non-nil = freeze at that absolute clock value (seconds).
    public var frozen: Double?

    public init(path: @escaping (CGRect) -> [CGPoint], valid: Bool = true,
                tier: ScaleTier = .m, icon: NSImage? = nil, showBonuses: Bool = true,
                scale: CGFloat = 1, speed: CGFloat = 64, frozen: Double? = nil) {
        self.path = path
        self.valid = valid
        self.tier = tier
        self.icon = icon
        self.showBonuses = showBonuses
        self.scale = scale
        self.speed = speed
        self.frozen = frozen
    }

    /// Birth time of this view — READ only inside the render closure so the live
    /// clock is birth-relative (matching the old `CACurrentMediaTime()` start).
    @State private var start = Date()

    public var body: some View {
        if let f = frozen {
            // Static frozen frame — `now` is the ABSOLUTE frozen seconds.
            Canvas { ctx, size in
                paint(into: &ctx, size: size, now: f)
            }
        } else {
            // Live mode — TimelineView drives the clock; the Canvas is a PURE
            // derivation of `now` (no @State write inside the closure).
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    let now = timeline.date.timeIntervalSince(start)
                    paint(into: &ctx, size: size, now: now)
                }
            }
        }
    }

    // MARK: - Render

    /// One classified pellet on the centre row.
    private enum Kind { case dot, cherry, icon }
    private struct Pellet { let point: CGPoint; let arc: Double; let kind: Kind; let value: Int }

    /// Replicate the Effects corridor draw step-for-step in a +y-down `Canvas`.
    private func paint(into ctx: inout GraphicsContext, size: CGSize, now: Double) {
        let bounds = CGRect(origin: .zero, size: size)
        guard bounds.width > 1, bounds.height > 1 else { return }

        // Approach A: flip the whole polyline up-front into canvas (+y-down) space,
        // then do EVERY geometry op on `pts`.
        let pts = path(bounds).map { CGPoint(x: $0.x, y: bounds.height - $0.y) }
        guard pts.count >= 2, speed > 0 else { return }

        // `tier` is the discrete arcade step (2/3/4.5); `scale` is the render
        // resolution — both legitimately multiply.
        let s = CGFloat(tier.multiplier) * scale
        let roadWidth = 11 * s
        let wallThick = max(1, 0.9 * s)
        let pelletR   = 0.8 * s
        let pelletGap = 5.2 * s
        let roadHalf  = roadWidth / 2

        // Eating is a PURE function of `now`: the face (the eater) is the trailing
        // cursor; pellets behind it are eaten, a bonus crossing flashes the walls +
        // floats a "+N". `valid == false` (the panicking ghost) doesn't eat.
        let total = polylineLength(pts)
        guard total > 0 else { return }
        let faceLag: CGFloat = valid ? roadWidth * 1.4 : 0
        let cursors = pathPetCursors(total: total, speed: Double(speed),
                                     now: now, faceLag: Double(faceLag))
        let faceArc = cursors.pet                       // the eating arc-length

        // Classify the pellet row up front (the wall colour depends on bonus eats).
        let marks = resampleAlongPolyline(pts, interval: Double(pelletGap))
        var pellets: [Pellet] = []
        for (i, m) in marks.enumerated() where i > 0 {
            // Marks sit at uniform pelletGap spacing → mark i is at i*pelletGap
            // (tail mark clamped to total).
            let arc = min(Double(i) * Double(pelletGap), total)
            // FIDELITY-CRITICAL: hash on the y-UP coords (convert the canvas mark
            // back) so the cherry/icon banding matches #17a's exact placement.
            let ix = Int(m.point.x.rounded())
            let iy = Int((Double(bounds.height) - m.point.y).rounded())
            let h = positionHash01(x: ix, y: iy)
            let kind: Kind = !showBonuses ? .dot
                           : (h < 0.04 ? .cherry : (h < 0.08 && icon != nil ? .icon : .dot))
            pellets.append(Pellet(point: CGPoint(x: m.point.x, y: m.point.y),
                                  arc: arc, kind: kind, value: bonusValue(x: ix, y: iy)))
        }
        let bonusArcs = valid ? pellets.filter { $0.kind != .dot }.map(\.arc) : []
        let flash = chompFlashPhase(eventArcs: bonusArcs, total: total, speed: Double(speed),
                                    now: now, faceLag: Double(faceLag), dur: chompEatFlashDur)

        // 1) Black road + 2-stroke neon walls on ONE rounded centreline. A bonus
        //    flash sweeps EffectSpec.chomp.flash (rainbow) with a brighter glow.
        let steps = roundedCornerPath(pts, radius: Double(roadHalf))
        let wallPath = swiftUIPath(from: steps)
        let wallColor: Color
        if let flash {
            let c = blendThrough(EffectSpec.chomp.flash, at: flash)
            wallColor = Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
        } else {
            wallColor = swiftUIColor(SpriteColor.pupilBlue)
        }
        // WIDE neon wall + glow, isolated in its OWN layer (the glow must not bleed
        // onto the road/pellets/pet drawn after it).
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: wallColor.opacity(flash != nil ? 1 : 0.85),
                                radius: (flash != nil ? 5 : 3) * s))
            l.stroke(wallPath, with: .color(wallColor),
                     style: StrokeStyle(lineWidth: roadWidth + 2 * wallThick,
                                        lineCap: .round, lineJoin: .round))
        }
        // BLACK road on top (no shadow) — only the wallThick band reads as wall.
        ctx.stroke(wallPath, with: .color(.black),
                   style: StrokeStyle(lineWidth: roadWidth, lineCap: .round, lineJoin: .round))

        // 2) Interior fillets — a black disc erodes each inner neon notch the round
        //    join leaves. Centre = vertex + bisector · roadHalf/cos(|turn|/2).
        for c in interiorCorners(pts) {
            let d  = Double(roadHalf) / cos(abs(c.turn) / 2)
            let fr = Double(wallThick) * 1.15
            let cx = c.vertex.x + c.bisector.x * d, cy = c.vertex.y + c.bisector.y * d
            ctx.fill(Path(ellipseIn: CGRect(x: cx - fr, y: cy - fr,
                                            width: 2 * fr, height: 2 * fr)),
                     with: .color(.black))
        }

        // 3) Central pellet row — skip the FIRST mark (live cursor) AND any pellet
        //    the face has already eaten this lap (valid only; the ghost keeps them).
        let bonusCell = roadWidth * 0.62 / 12        // cherry is 12 cells wide
        let iconBox   = roadWidth * 0.66
        for p in pellets {
            if valid, faceArc >= p.arc { continue }   // eaten — gone until the lap wraps
            switch p.kind {
            case .cherry:
                drawPixelSprite(in: &ctx, CanonicalSprite.cherry,
                                cell: bonusCell, at: p.point, rotation: 0, color: nil)
            case .icon:
                if let icon {
                    ctx.draw(ctx.resolve(Image(nsImage: icon)),
                             in: CGRect(x: p.point.x - iconBox / 2, y: p.point.y - iconBox / 2,
                                        width: iconBox, height: iconBox))
                }
            case .dot:
                ctx.fill(Path(ellipseIn: CGRect(x: p.point.x - pelletR, y: p.point.y - pelletR,
                                                width: 2 * pelletR, height: 2 * pelletR)),
                         with: .color(swiftUIColor(SpriteColor.pacYellow)))
            }
        }

        // 4) The walking pac / panicking ghost — inline the PathPet draw with the
        //    corridor's `petScale` and NO guide / NO head (the pellets are the
        //    targets now). Mirrors PathPetView's pet section exactly.
        let petScale = roadWidth * 0.78 / chompFaceFootprint
        if let mark = markAtArcLength(pts, distance: cursors.pet) {
            let p = CGPoint(x: mark.point.x, y: mark.point.y)
            if valid {
                // Pac TUMBLES so the mouth (canonical +x) opens along travel.
                let angle = atan2(mark.tangent.y, mark.tangent.x)
                let cell = petScale * chompFaceFootprint / CGFloat(chompFaceCells)
                drawPixelSprite(in: &ctx, chompPacSprite(now: now),
                                cell: cell, at: p, rotation: CGFloat(angle),
                                color: SpriteColor.pacYellow)
            } else {
                // Ghost stays UPRIGHT and PANICS — a sustained 2-D buzz (co-prime
                // 6/7, decay 0), eyes on the travel cardinal.
                var pp = (now * pathPetPanicHz).truncatingRemainder(dividingBy: 1)
                if pp < 0 { pp += 1 }   // fold a negative `now` forward
                let amp = 1.6 * petScale
                let jx = CGFloat(ThemedTransition.dampedSine(pp, frequency: 6, decay: 0)) * amp
                let jy = CGFloat(ThemedTransition.dampedSine(pp, frequency: 7, decay: 0)) * amp
                // GhostLook.facing uses +y-UP; our tangent is canvas +y-down → negate y.
                let look = GhostLook.facing(dx: mark.tangent.x, dy: -mark.tangent.y)
                let ghost = chompGhostSprite(now: now, look: look)
                let cell = petScale * ghostFootprint / CGFloat(ghost.height)
                drawPixelSprite(in: &ctx, ghost,
                                cell: cell, at: CGPoint(x: p.x + jx, y: p.y + jy),
                                rotation: 0, color: nil)
            }
        }

        // 5) Floating "+N" score pops for bonuses eaten in the last ~0.8s (valid).
        if valid {
            let pops = chompScorePops(
                bonuses: pellets.filter { $0.kind != .dot }
                    .map { (point: (x: Double($0.point.x), y: Double($0.point.y)),
                            arc: $0.arc, value: $0.value) },
                total: total, speed: Double(speed), now: now,
                faceLag: Double(faceLag), dur: chompScorePopDur)
            for pop in pops {
                let rise = ThemedTransition.Easing.easeOutCubic(pop.t)   // 0…1 snappy→soft
                let alpha = max(0, 1 - pop.t)                            // linear fade
                // RISE = up → SUBTRACT y in the +y-down canvas.
                let at = CGPoint(x: pop.point.x, y: pop.point.y - CGFloat(rise) * 14 * s)
                let txt = Text("+\(pop.value)")
                    .font(.system(size: 9 * s, weight: .bold, design: .monospaced))
                    .foregroundColor(swiftUIColor(SpriteColor.pacYellow, opacity: alpha))
                ctx.draw(txt, at: at, anchor: .bottom)
            }
        }
    }
}
