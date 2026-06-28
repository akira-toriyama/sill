// ThemeKitUI — SwiftUI-native pixel-pet border lap (#17h). The pac / ghost
// sprites lap the view's inset border, the SAME lap math the old draw used,
// now drawn into a SwiftUI `Canvas` with nearest-neighbor pixel sprites
// (the Task-2 `drawPixelSprite` helper). Owns the redraw clock (sill's
// `f(now)`). Transparent background.
//
// GENERAL: the `pets`, border `inset` (points), pet `scale` and lap `speed` are
// inputs — an app laps pets around a focused-window ring (halo) or a panel edge
// (facet). prism passes its showcase values (chomp+ghost, scaled by the gallery
// knob) and gets the same pixels. `frozen` (absolute seconds) freezes one frame.
//
// COORDINATE / ORIENTATION
// ────────────────────────
// `linePetPosition(on:distance:)` (Effects) places pets in a NON-flipped
// (+y-UP) frame where "top" = `track.maxY`, and returns `rot` as the travel
// angle measured CCW from +x in that +y-up frame. The SwiftUI `Canvas` here is
// kept in its DEFAULT +y-DOWN space — we do NOT flip the whole CTM. Instead each
// pet's placement is converted to canvas space at the point:
//   * `posCanvas = CGPoint(x: px, y: bounds.height - py)`  (flip y only here)
//   * `rotCanvas = -rot`                                   (negate the angle)
// This keeps the sprites UPRIGHT with no per-sprite flip: the Task-2
// `pixelCGImage` bakes row-0-at-TOP, so a sprite drawn in a +y-DOWN canvas is
// already upright. (The earlier draw fought a +y-up frame and needed internal
// y-flips; here we do not.)
//   * `.chomp` TUMBLES so the mouth opens along travel — drawn with `rotCanvas`.
//     The pac wedge is y-symmetric, so negating the angle does not distort it.
//   * `.ghost` stays UPRIGHT (rotation 0); only its eyes track travel. The gaze
//     is picked from the +y-UP tangent `(cos rot, sin rot)` fed to
//     `GhostLook.facing` (which uses the +y-up convention), so the cardinal is
//     correct even though the body is drawn in the +y-down canvas.
//
// CLOCK: live = `TimelineView(.animation)` with a birth-relative clock
// (`context.date.timeIntervalSince(start)`, `start` a read-only `@State`);
// `frozen != nil` = a static `Canvas` at the absolute `frozen` seconds. Every
// drawn pixel is a PURE function of `now` (the sprites come from the pure
// Effects selectors; no randomness) — so NO `@State` is written during render.

import SwiftUI
import Effects

public struct LinePetsView: View {
    /// Which pets lap the border, in chase order (leader first).
    public var pets: [LinePet]
    /// Border inset in points (the pets walk the inset rect's perimeter).
    public var inset: CGFloat
    /// Pet render scale.
    public var scale: CGFloat
    /// Lap speed in points/second.
    public var speed: CGFloat
    /// nil = live; non-nil = freeze at that absolute clock value (seconds).
    public var frozen: Double?

    public init(pets: [LinePet] = [.chomp, .ghost], inset: CGFloat = 18,
                scale: CGFloat = 1, speed: CGFloat = 70, frozen: Double? = nil) {
        self.pets = pets
        self.inset = inset
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

    /// Lap every pet around the inset border and blit its pixel sprite, applying
    /// the +y-up → +y-down conversion at each pet's placement.
    private func paint(into ctx: inout GraphicsContext, size: CGSize, now: Double) {
        let bounds = CGRect(origin: .zero, size: size)
        guard bounds.width > 1, bounds.height > 1, !pets.isEmpty, speed > 0 else { return }

        // Lap math — the SAME perimeter walk the old border-lap draw used.
        let track = bounds.insetBy(dx: inset, dy: inset)
        guard track.width > 0, track.height > 0 else { return }
        let perim = 2 * (track.width + track.height)
        let leader = CGFloat(now).truncatingRemainder(dividingBy: perim / speed) * speed
        let chaseGap: CGFloat = 24 * scale   // ~2× ghost width

        for (i, pet) in pets.enumerated() {
            var pos = leader - CGFloat(i) * chaseGap
            pos = pos.truncatingRemainder(dividingBy: perim)
            if pos < 0 { pos += perim }
            let (px, py, rot) = linePetPosition(on: track, distance: pos)

            // +y-UP frame → +y-DOWN canvas: flip y at the point, negate the angle.
            let posCanvas = CGPoint(x: px, y: bounds.height - py)
            let rotCanvas = -rot

            switch pet {
            case .chomp:
                // Pac TUMBLES so its (y-symmetric) mouth opens along travel.
                let cell = scale * chompFaceFootprint / CGFloat(chompFaceCells)
                drawPixelSprite(in: &ctx, chompPacSprite(now: now),
                                cell: cell, at: posCanvas, rotation: rotCanvas,
                                color: SpriteColor.pacYellow)
            case .ghost:
                // The ghost stays UPRIGHT — only its eyes track travel. Feed the
                // +y-UP tangent (cos rot, sin rot) to GhostLook.facing (+y → up).
                let look = GhostLook.facing(dx: Double(cos(rot)), dy: Double(sin(rot)))
                let ghost = chompGhostSprite(now: now, look: look)
                // Divisor = the sprite's actual height (not a literal 14) — the
                // parity-faithful sizing the old border-lap ghost draw used.
                let cell = scale * ghostFootprint / CGFloat(ghost.height)
                drawPixelSprite(in: &ctx, ghost,
                                cell: cell, at: posCanvas, rotation: 0, color: nil)
            }
        }
    }
}
