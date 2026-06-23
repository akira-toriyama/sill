// ThemeKitUI — SwiftUI-native pixel-sprite view (nearest-neighbour, crisp cells).
//
// Replaces the #17a AppKit-backed bridge with a pure SwiftUI `View`.
// Rendering pipeline: `pixelImage(_:color:)` (Task 2) builds a
// 1px/cell CGImage with `.interpolation(.none)`, which `.resizable().frame(…)`
// scales up without any blurring. Same public API as before:
//   • `frames`, `hz`, `cell`, `color`, `frozen` — identical stored properties.
//   • Both inits preserved verbatim.
//   • Intrinsic size: `pixelSize(cell:)` of the first frame, expressed via
//     `.frame(width:height:)` on the Image — same footprint that prism relies on.
//
// Three render branches (NO @State write during render — that's forbidden):
//   1. Single frame (`frames.count == 1`): static Image — no TimelineView.
//   2. Frozen (`frozen != nil`): static Image at `now = frozen!`.
//   3. Live animation: `TimelineView(.animation)`; clock is birth-relative
//      (`now = context.date.timeIntervalSince(start)` where `start` is a `@State`
//      default set exactly once at init — reading it during render is fine).

import SwiftUI
import PixelArt
import Effects
import Motion

public struct PixelSpriteView: View {
    /// The animation frames; a single-element array is a static sprite.
    public var frames: [PixelSprite]
    /// Frame-swap rate (ignored when `frames.count == 1`).
    public var hz: Double
    /// One sprite cell's size in points.
    public var cell: CGFloat
    /// Override tint (nil = the sprite's intrinsic cell colours).
    public var color: UInt32?
    /// nil = live; non-nil = freeze at that absolute clock value (seconds).
    public var frozen: Double?

    public init(frames: [PixelSprite], hz: Double = CanonicalSprite.waddleHz,
                cell: CGFloat, color: UInt32? = nil, frozen: Double? = nil) {
        self.frames = frames
        self.hz = hz
        self.cell = cell
        self.color = color
        self.frozen = frozen
    }

    /// Convenience for a static (single-frame) sprite.
    public init(sprite: PixelSprite, cell: CGFloat, color: UInt32? = nil) {
        self.init(frames: [sprite], cell: cell, color: color, frozen: nil)
    }

    // Birth timestamp — set once at view identity creation; NEVER written during
    // render. `@State` default `Date()` is captured at the first render and stays
    // stable for the lifetime of this view identity.
    @State private var start = Date()

    public var body: some View {
        if frames.isEmpty {
            // Defensive: no frames → zero-size transparent placeholder.
            Color.clear.frame(width: 0, height: 0)
        } else if frames.count == 1 {
            // ── Branch 1: single frame — pure static Image, no clock needed. ──
            spriteImage(frames[0])
        } else if let f = frozen {
            // ── Branch 2: frozen — static Image at the given absolute `now`. ──
            spriteImage(ThemedTransition.frameStep(now: f, hz: hz, frames: frames))
        } else {
            // ── Branch 3: live animation — birth-relative clock via TimelineView. ──
            // `context.date.timeIntervalSince(start)` gives seconds elapsed since
            // this view was born; `start` is read (never written) here.
            TimelineView(.animation) { context in
                let now = context.date.timeIntervalSince(start)
                spriteImage(ThemedTransition.frameStep(now: now, hz: hz, frames: frames))
            }
        }
    }

    // MARK: - Render helper

    /// Render `sprite` as a nearest-neighbour Image sized to `pixelSize(cell:)`.
    @ViewBuilder private func spriteImage(_ sprite: PixelSprite) -> some View {
        let size = sprite.pixelSize(cell: cell)
        pixelImage(sprite, color: color)
            .resizable()
            .frame(width: size.width, height: size.height)
    }
}
