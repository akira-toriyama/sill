// ThemeKitUI — SwiftUI bridge for `Effects.drawLinePets`: pixel pets (pac /
// ghost) lapping the view's border, the real renderer painted each frame. Owns
// the redraw clock (sill's `f(now)`). NON-flipped (y-up), per `drawLinePets`'
// contract ("top" = maxY). Transparent background.
//
// GENERAL: the `pets`, border `inset` (points), pet `scale` and lap `speed` are
// inputs — an app laps pets around a focused-window ring (halo) or a panel edge
// (facet). prism passes its showcase values (chomp+ghost, scaled by the gallery
// knob) and gets the same pixels. `frozen` (absolute seconds) freezes one frame.

import SwiftUI
import AppKit
import Palette
import Effects

public struct LinePetsView: NSViewRepresentable {
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

    public func makeNSView(context: Context) -> LinePetsNSView {
        let v = LinePetsNSView()
        apply(v)
        return v
    }

    public func updateNSView(_ v: LinePetsNSView, context: Context) {
        apply(v)
        v.needsDisplay = true
    }

    private func apply(_ v: LinePetsNSView) {
        v.pets = pets
        v.inset = inset
        v.scale = scale
        v.speed = speed
        v.frozen = frozen
    }
}

public final class LinePetsNSView: NSView {
    public var pets: [LinePet] = [.chomp, .ghost]
    public var inset: CGFloat = 18
    public var scale: CGFloat = 1
    public var speed: CGFloat = 70
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
        let track = bounds.insetBy(dx: inset, dy: inset)
        drawLinePets(pets, on: track, now: now, scale: scale, speed: speed)
    }
}
