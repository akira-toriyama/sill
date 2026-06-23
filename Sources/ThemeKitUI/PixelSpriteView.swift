// ThemeKitUI — SwiftUI bridge for a single (optionally animated) pixel sprite,
// blitted by the real `Effects.drawPixelSprite` (antialias OFF — crisp cells).
//
// This is the shared **antialias-off blitter** the deep-dive (#17a §0.6) calls
// for: SwiftUI `Canvas` is vector-only and can't draw per-pixel crisp cells, so a
// thin `NSViewRepresentable` over the AppKit blitter is the intended home for an
// app's pixel pet (facet/pet). GENERAL: pass any `PixelSprite` frames — one frame
// is static; several swap at `hz` via `Motion`'s discrete `frameStep` (the same
// sampler the line-pets use). `color` overrides the sprite's intrinsic palette
// (nil = the sprite's own colours). `frozen` (absolute seconds) freezes one frame
// for a deterministic capture. Sizes to the sprite (`pixelSize(cell:)`).

import SwiftUI
import AppKit
import PixelArt
import Effects
import Motion

public struct PixelSpriteView: NSViewRepresentable {
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

    public func makeNSView(context: Context) -> PixelSpriteNSView {
        let v = PixelSpriteNSView()
        apply(v)
        return v
    }

    public func updateNSView(_ v: PixelSpriteNSView, context: Context) {
        apply(v)
        v.needsDisplay = true
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: PixelSpriteNSView,
                             context: Context) -> CGSize? {
        frames.first?.pixelSize(cell: cell)
    }

    private func apply(_ v: PixelSpriteNSView) {
        v.frames = frames
        v.hz = hz
        v.cell = cell
        v.color = color
        v.frozen = frozen
        v.refreshTick()
    }
}

/// The live host: blits `frameStep(now)`'s frame with the real `drawPixelSprite`.
/// `isFlipped` so row 0 draws at the TOP (the grid convention). Transparent
/// background. The timer runs only while animating (more than one frame).
public final class PixelSpriteNSView: NSView {
    public var frames: [PixelSprite] = []
    public var hz: Double = CanonicalSprite.waddleHz
    public var cell: CGFloat = 1
    public var color: UInt32?
    public var frozen: Double?

    // Live clock ORIGIN: `now` runs from this view's birth (a rebuilt view
    // restarts at t=0), matching the prism benches' clock contract.
    private let clockStart = CACurrentMediaTime()
    private var timer: Timer?

    public override var isFlipped: Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { timer?.invalidate(); timer = nil; return }
        refreshTick()
    }

    /// (Re)start or stop the tick to match the current animate/frozen state.
    func refreshTick() {
        let animating = frames.count > 1 && frozen == nil && window != nil
        if animating, timer == nil {
            timer = startEffectTick(for: self, frozen: false)
        } else if !animating, timer != nil {
            timer?.invalidate(); timer = nil
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard !frames.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
        let now = frozen ?? (CACurrentMediaTime() - clockStart)
        let sprite = frames.count > 1
            ? ThemedTransition.frameStep(now: now, hz: hz, frames: frames)
            : frames[0]
        drawPixelSprite(sprite, cell: cell, at: .zero, color: color)
    }
}
