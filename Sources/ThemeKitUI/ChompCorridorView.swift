// ThemeKitUI — SwiftUI bridge for `Effects.drawChompCorridor`: the composite
// arcade maze (2-stroke neon walls + interior fillets + a centre pellet row + the
// pac walking it, EATING pellets, wall-flash + "+N" score on a bonus). The real
// renderer painted each frame; owns the redraw clock (sill's `f(now)`).
// NON-flipped (y-up), per the `drawChompPath` contract. Transparent background.
//
// GENERAL: the `path` (a closure of bounds) is the corridor centreline, and
// `icon` is the app's bonus pellet image — an app feeds its own maze + app icon
// (wand arcade). prism feeds an orthogonal serpentine maze + a tinted Phosphor
// star and gets the same pixels. `frozen` (absolute seconds) freezes one frame.

import SwiftUI
import AppKit
import PixelArt
import Effects

public struct ChompCorridorView: NSViewRepresentable {
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

    public func makeNSView(context: Context) -> ChompCorridorNSView {
        let v = ChompCorridorNSView()
        apply(v)
        return v
    }

    public func updateNSView(_ v: ChompCorridorNSView, context: Context) {
        apply(v)
        v.needsDisplay = true
    }

    private func apply(_ v: ChompCorridorNSView) {
        v.path = path
        v.valid = valid
        v.tier = tier
        v.icon = icon
        v.showBonuses = showBonuses
        v.scale = scale
        v.speed = speed
        v.frozen = frozen
    }
}

public final class ChompCorridorNSView: NSView {
    public var path: (CGRect) -> [CGPoint] = { _ in [] }
    public var valid = true
    public var tier: ScaleTier = .m
    public var icon: NSImage?
    public var showBonuses = true
    public var scale: CGFloat = 1
    public var speed: CGFloat = 64
    public var frozen: Double?

    private let clockStart = CACurrentMediaTime()
    private var timer: Timer?

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { timer?.invalidate(); timer = nil; return }
        guard timer == nil else { return }
        timer = startEffectTick(for: self, frozen: frozen != nil)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let now = frozen ?? (CACurrentMediaTime() - clockStart)
        drawChompCorridor(path(bounds), now: now, valid: valid, tier: tier,
                          scale: scale, speed: speed, icon: icon, showBonuses: showBonuses)
    }
}
