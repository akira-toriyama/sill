// ThemeKitUI — SwiftUI-native PathPet (#17h): a pac (or, when `valid == false`,
// an upright panicking ghost) walking an ARBITRARY polyline. A head cursor leads
// along the arc length and the face FOLLOWS by `faceLag` — wand's Chomp gap. The
// open-path counterpart to LinePetsView's closed perimeter lap, replacing the
// #17a AppKit-backed bridge with a SwiftUI `Canvas` + nearest-neighbor pixel
// sprites (the Task-2 `drawPixelSprite` helper). Owns the redraw clock (sill's
// `f(now)`). Transparent background.
//
// GENERAL: the `path` is a closure of the view's bounds, so the SAME view fits
// any size — an app feeds a recognised gesture polyline (wand trail). prism feeds
// a zigzag inset into its bounds and gets the same pixels.
//
// COORDINATE / ORIENTATION (Approach A — flip the WHOLE polyline up-front)
// ───────────────────────────────────────────────────────────────────────
// The pure geometry (`polylineLength` / `roundedCornerPath` / `markAtArcLength` /
// the cursors) is coordinate-agnostic — it just walks whatever polyline it's
// handed. The old draw hosted the path in a NON-flipped (+y-UP) view; the SwiftUI
// `Canvas` is +y-DOWN. So we flip the whole polyline ONCE at the top:
//   `pts = path(bounds).map { CGPoint(x: $0.x, y: bounds.height - $0.y) }`
// and do ALL geometry on `pts` in canvas (+y-down) space. Then:
//   * pac rotation = `atan2(mark.tangent.y, mark.tangent.x)` on the CANVAS-space
//     tangent DIRECTLY (the up-front flip already accounts for orientation —
//     this equals LinePetsView's `-rot`). The wedge is y-symmetric, so no
//     distortion.
//   * ghost gaze = `GhostLook.facing(dx: tangent.x, dy: -tangent.y)` — negate y
//     because `GhostLook.facing` uses the +y-UP convention while our tangent is
//     canvas +y-down.
//   * sprites stay UPRIGHT with NO per-sprite flip: `pixelCGImage` bakes
//     row-0-at-TOP, so a sprite drawn in a +y-down canvas is already upright.
//
// CLOCK: live = `TimelineView(.animation)` with a birth-relative clock
// (`context.date.timeIntervalSince(start)`, `start` a read-only `@State`);
// `frozen != nil` = a static `Canvas` at the absolute `frozen` seconds. Every
// drawn pixel is a PURE function of `now` (the sprites/cursors are pure
// selectors; no randomness) — so NO `@State` is written during render.

import SwiftUI
import Effects
import Motion   // ThemedTransition.dampedSine (the panic-buzz envelope)

public struct PathPetView: View {
    /// The polyline the pet walks, mapped from the view's bounds (y-up).
    public var path: (CGRect) -> [CGPoint]
    /// true = chasing pac; false = upright panicking ghost (a 2-D `dampedSine` buzz).
    public var valid: Bool
    public var scale: CGFloat
    /// Lap speed in points/second.
    public var speed: CGFloat
    /// How far (points) the face trails the leading head.
    public var faceLag: CGFloat
    /// Draw the faint rounded guide trail under the pet.
    public var showGuide: Bool
    /// nil = live; non-nil = freeze at that absolute clock value (seconds).
    public var frozen: Double?

    public init(path: @escaping (CGRect) -> [CGPoint], valid: Bool = true,
                scale: CGFloat = 1, speed: CGFloat = 60, faceLag: CGFloat = 0,
                showGuide: Bool = true, frozen: Double? = nil) {
        self.path = path
        self.valid = valid
        self.scale = scale
        self.speed = speed
        self.faceLag = faceLag
        self.showGuide = showGuide
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

    /// Replicate the Effects PathPet draw (with the standalone view's `showHead`
    /// default = true): guide trail → glowing head dot → the pac / panic ghost.
    private func paint(into ctx: inout GraphicsContext, size: CGSize, now: Double) {
        let bounds = CGRect(origin: .zero, size: size)
        guard bounds.width > 1, bounds.height > 1 else { return }

        // Approach A: flip the whole polyline up-front into canvas (+y-down)
        // space, then do EVERY geometry op on `pts`.
        let pts = path(bounds).map { CGPoint(x: $0.x, y: bounds.height - $0.y) }
        guard pts.count >= 2, speed > 0 else { return }
        let total = polylineLength(pts)   // arc length = the loop period (in points)
        guard total > 0 else { return }

        // The faint rounded guide trail (round cap/join to match the old look).
        if showGuide {
            let guide = swiftUIPath(from: roundedCornerPath(pts, radius: Double(6 * scale)))
            ctx.stroke(guide, with: .color(color(SpriteColor.pupilBlue, opacity: 0.22)),
                       style: StrokeStyle(lineWidth: 1.5 * scale,
                                          lineCap: .round, lineJoin: .round))
        }

        // Head marches the arc length and loops; the pet trails it by `faceLag`.
        let (headDist, petDist) = pathPetCursors(total: total, speed: Double(speed),
                                                 now: now, faceLag: Double(faceLag))

        // The chased head — a small glowing pellet-dot (only when valid + lagging;
        // a mismatch has no target). Isolated in its OWN layer so the glow doesn't
        // bleed onto the pet.
        if valid, faceLag > 0, let head = markAtArcLength(pts, distance: headDist) {
            let r: CGFloat = 2.5 * scale
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: color(SpriteColor.pacYellow, opacity: 1),
                                    radius: 4 * scale))
                let rect = CGRect(x: head.point.x - r, y: head.point.y - r,
                                  width: 2 * r, height: 2 * r)
                l.fill(Path(ellipseIn: rect),
                       with: .color(color(SpriteColor.pacYellow, opacity: 1)))
            }
        }

        guard let mark = markAtArcLength(pts, distance: petDist) else { return }
        let p = CGPoint(x: mark.point.x, y: mark.point.y)

        if valid {
            // Pac TUMBLES so the mouth (canonical +x) opens along travel — the
            // canvas-space tangent drives the rotation directly.
            let angle = atan2(mark.tangent.y, mark.tangent.x)
            let cell = scale * chompFaceFootprint / CGFloat(chompFaceCells)
            drawPixelSprite(in: &ctx, chompPacSprite(now: now),
                            cell: cell, at: p, rotation: CGFloat(angle),
                            color: SpriteColor.pacYellow)
        } else {
            // Ghost stays UPRIGHT (no rotate) and PANICS — a sustained 2-D buzz
            // (co-prime 6/7, decay 0 so it doesn't fade), eyes on the travel
            // cardinal.
            var pp = (now * pathPetPanicHz).truncatingRemainder(dividingBy: 1)
            if pp < 0 { pp += 1 }   // fold a negative `now` forward (frameStep's rule)
            let amp = 1.6 * scale
            let jx = CGFloat(ThemedTransition.dampedSine(pp, frequency: 6, decay: 0)) * amp
            let jy = CGFloat(ThemedTransition.dampedSine(pp, frequency: 7, decay: 0)) * amp
            // GhostLook.facing uses +y-UP; our tangent is canvas +y-down → negate y.
            let look = GhostLook.facing(dx: mark.tangent.x, dy: -mark.tangent.y)
            let ghost = chompGhostSprite(now: now, look: look)
            // Divisor = the sprite's actual height — the parity-faithful sizing.
            let cell = scale * ghostFootprint / CGFloat(ghost.height)
            drawPixelSprite(in: &ctx, ghost,
                            cell: cell, at: CGPoint(x: p.x + jx, y: p.y + jy),
                            rotation: 0, color: nil)
        }
    }

    /// A SwiftUI `Color` from a `SpriteColor` `0xRRGGBB` (the intrinsic arcade
    /// palette is theme-invariant, like the sprites).
    private func color(_ rgb: UInt32, opacity: Double) -> Color {
        Color(.sRGB,
              red: Double((rgb >> 16) & 0xFF) / 255,
              green: Double((rgb >> 8) & 0xFF) / 255,
              blue: Double(rgb & 0xFF) / 255,
              opacity: opacity)
    }
}
