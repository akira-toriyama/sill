// ThemeKitUI — SwiftUI bridge for `Effects.drawChompPath`: a pac (or, when
// `valid == false`, an upright panicking ghost) walking an ARBITRARY polyline —
// the head leads along arc length, the face follows by `faceLag`. The real
// renderer painted each frame; owns the redraw clock (sill's `f(now)`).
// NON-flipped (y-up), per `drawChompPath`'s contract. Transparent background.
//
// GENERAL: the `path` is a closure of the view's bounds, so the SAME view fits
// any size — an app feeds a recognised gesture polyline (wand trail). prism feeds
// a zigzag inset into its bounds and gets the same pixels.

import SwiftUI
import AppKit
import Effects

public struct PathPetView: NSViewRepresentable {
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

    public func makeNSView(context: Context) -> PathPetNSView {
        let v = PathPetNSView()
        apply(v)
        return v
    }

    public func updateNSView(_ v: PathPetNSView, context: Context) {
        apply(v)
        v.needsDisplay = true
    }

    private func apply(_ v: PathPetNSView) {
        v.path = path
        v.valid = valid
        v.scale = scale
        v.speed = speed
        v.faceLag = faceLag
        v.showGuide = showGuide
        v.frozen = frozen
    }
}

public final class PathPetNSView: NSView {
    public var path: (CGRect) -> [CGPoint] = { _ in [] }
    public var valid = true
    public var scale: CGFloat = 1
    public var speed: CGFloat = 60
    public var faceLag: CGFloat = 0
    public var showGuide = true
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
        drawChompPath(path(bounds), now: now, valid: valid, scale: scale,
                      speed: speed, faceLag: faceLag, showGuide: showGuide)
    }
}
