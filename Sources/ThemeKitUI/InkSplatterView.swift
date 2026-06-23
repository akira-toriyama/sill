// ThemeKitUI — SwiftUI bridge for `Effects`' ink-splatter decal
// (`rollSplatter` → `alpha(now:)` → the real AppKit `drawInkSplatter`). Pure
// geometry + a draw helper, so the bridge OWNS the redraw clock and re-stamps a
// fresh splat on a fixed cadence (hold ⅔ → fade ⅓), painting it each frame. The
// renderer is `NSBezierPath`/`NSColor` (Catmull-Rom wet rim), so this is a
// `NSViewRepresentable` — byte-identical to the AppKit draw.
//
// GENERAL by design: colours, the stamp `center`/`size` (bounds-relative
// closures), `seed`, `duration` and loop cadence are inputs — an app stamps a
// splat wherever a shot lands (wand decal). prism passes its showcase data and
// gets the same pixels. `frozen` (0…1 of `duration`) freezes one held frame;
// when frozen without an explicit `seed` a stable default keeps it deterministic
// (prism's old fixed-seed capture).

import SwiftUI
import AppKit
import Effects

public struct InkSplatterView: NSViewRepresentable {
    public var colors: [UInt32]
    /// Where the splat stamps, from the view's bounds. Default = centre.
    public var center: (CGRect) -> CGPoint
    /// The splat extent in points, from the view's bounds. Default = 0.78·min side.
    public var size: (CGRect) -> Double
    /// Live re-stamp seed. nil = a fresh random splat each cadence.
    public var seed: UInt64?
    public var duration: TimeInterval
    /// nil = stamp ONCE; non-nil = re-stamp every `loopPeriod` seconds.
    public var loopPeriod: Double?
    /// nil = live; non-nil = freeze ONE frame at that fraction (0…1) of `duration`.
    public var frozen: Double?

    /// Stable seed used when a frozen view was given no explicit `seed`, so a
    /// capture is always deterministic (matches prism's old fixed-seed freeze).
    public static let frozenSeedDefault: UInt64 = 0xC0FFEE

    public init(colors: [UInt32],
                seed: UInt64? = nil,
                duration: TimeInterval = 1.4,
                loopPeriod: Double? = nil,
                frozen: Double? = nil,
                center: @escaping (CGRect) -> CGPoint = { CGPoint(x: $0.midX, y: $0.midY) },
                size: @escaping (CGRect) -> Double = { Double(min($0.width, $0.height)) * 0.78 }) {
        self.colors = colors
        self.seed = seed
        self.duration = duration
        self.loopPeriod = loopPeriod
        self.frozen = frozen
        self.center = center
        self.size = size
    }

    public func makeNSView(context: Context) -> InkSplatterNSView {
        let v = InkSplatterNSView()
        apply(v)
        return v
    }

    public func updateNSView(_ v: InkSplatterNSView, context: Context) {
        apply(v)
        v.needsDisplay = true
    }

    private func apply(_ v: InkSplatterNSView) {
        v.colors = colors
        v.center = center
        v.size = size
        v.seed = seed
        v.duration = duration
        v.loopPeriod = loopPeriod
        v.frozen = frozen
    }
}

/// The live host: re-stamps a fresh `SplatterShape` at its configured centre and
/// paints it with `drawInkSplatter`. Owns a 60 Hz redraw timer; honours `frozen`
/// for a deterministic capture. Transparent background.
public final class InkSplatterNSView: NSView {
    public var colors: [UInt32] = [] { didSet { needsDisplay = true } }
    public var center: (CGRect) -> CGPoint = { CGPoint(x: $0.midX, y: $0.midY) }
    public var size: (CGRect) -> Double = { Double(min($0.width, $0.height)) * 0.78 }
    public var seed: UInt64?
    public var duration: TimeInterval = 1.4
    public var loopPeriod: Double?
    public var frozen: Double?

    private var shape: SplatterShape?
    private var timer: Timer?

    public override var isFlipped: Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { timer?.invalidate(); timer = nil; return }
        guard timer == nil else { return }
        timer = startEffectTick(for: self, frozen: frozen != nil)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let c = center(bounds)
        let sz = size(bounds)

        // Freeze mode — one deterministic frame (stable seed + held opacity).
        if let f = frozen {
            let s = shape ?? rollSplatter(at: c, size: sz, colors: colors,
                                          seed: seed ?? InkSplatterView.frozenSeedDefault,
                                          now: 0, duration: duration)
            shape = s
            drawInkSplatter(s, now: max(0, min(1, f)) * duration)
            return
        }

        // Live — re-stamp once, or every `loopPeriod` (pop, hold, fade, beat).
        let now = CACurrentMediaTime()
        let reroll: Bool
        if let period = loopPeriod {
            reroll = shape == nil || now - (shape?.startedAt ?? 0) >= period
        } else {
            reroll = shape == nil
        }
        if reroll {
            shape = rollSplatter(at: c, size: sz, colors: colors,
                                 seed: seed, now: now, duration: duration)
        }
        if let s = shape { drawInkSplatter(s, now: now) }
    }
}
