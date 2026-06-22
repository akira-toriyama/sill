// ThemeKit — ThemedBorder: the family's ONE themed surface border. Every app
// outlines its signature surface (facet's tree panel, halo's ring, wand's tome,
// glance's panel, a card) and hand-draws that stroke; this makes it ONE part.
//
// It is the UNIVERSAL border — used for EVERY theme, not just animatable ones:
//   * no effect (or effects toggled OFF) → a static stroke in the `primary`
//     accent (the calm, default border).
//   * an effect + effects ON → the LIVE border: the shared `resolveBorder`
//     animator drawn as a glowing, breathing, colour-cycling stroke (the neon /
//     chomp / rainbow rim). This is the "motion" that used to live app-side,
//     promoted into the shared widget once it earned the rule-of-three.
//
// One master switch — `effectsEnabled` — gates the motion (派手好き ON / 静か OFF),
// the same flag a host also passes to `ResolvedPalette.animated(forTheme:at:)`
// so the WHOLE theme (border + widget accents) animates or rests together.
//
// Themed by assigning `palette`. AppKit / @MainActor.
//
// Ambient-animation discipline — the lifecycle GATING mirrors ThemedSkeleton, but
// the redraw MECHANISM differs: ThemedBorder drives a RunLoop `Timer` (resolveBorder
// is a per-frame f(now), not a keyframe), where Skeleton drives a CAAnimation. The
// gating is the same because CoreAnimation does NOT pause an off-screen view (and a
// repeating run-loop Timer is retained by the run loop, NOT by us) — so we remove the
// clock when the view loses a visible window (viewDidMoveToWindow + window observers),
// honour reduce-motion (live, via NSWorkspace) by resting on the effect's steady hue,
// and freeze at a fixed phase for deterministic still capture. The Timer block is
// [weak self] and self-invalidates the instant `self` is gone (the load-bearing bit
// the CAAnimation version doesn't need). Colour/width are snapped on the shape layers
// inside a disabled-action transaction (never animated by CoreAnimation — resolveBorder
// IS the animation).

import AppKit
import QuartzCore
import Palette
import PaletteKit
import Effects

@MainActor
public final class ThemedBorder: NSView {

    /// Glow under the stroke. `.none` = a flat stroke (the static primary border);
    /// `.bloom` = a neon-tube halo scaled by the breathing width (the effect rim).
    public enum Glow { case none, bloom }

    // MARK: - Public configuration

    /// The theme. Assigning re-tints WITHOUT restarting the clock — a snap, like
    /// ThemedSkeleton's re-tint discipline. (In the live effect state the stroke
    /// colour comes from the effect, not the palette, so a re-theme there is a
    /// no-op; only the static-`primary` rest needs re-snapping.)
    public var palette: ResolvedPalette { didSet { resnapIfResting() } }

    /// The effect to animate, or `nil` for a static `primary` border. A host
    /// resolves it from the theme name via `borderEffectFor(_:)`.
    public var effect: EffectSpec? { didSet { rebuild() } }

    /// Master switch: when `false`, the border rests as a static `primary` stroke
    /// even if `effect` is set (派手好き ON / 静か OFF). The same flag a host passes
    /// to `ResolvedPalette.animated(forTheme:at:)` so the whole theme rests together.
    public var effectsEnabled: Bool = true { didSet { rebuild() } }

    /// Corner radius of the stroked rounded-rect (match the host surface).
    public var cornerRadius: CGFloat = CGFloat(Radius.xl) { didSet { relayout() } }

    /// Resting stroke width. The live effect breathes between this and `breathMultiplier`×.
    public var lineWidth: CGFloat = 1.5 { didSet { relayout() } }

    /// Glow style for the LIVE (effect) state. The static border never glows.
    /// Default `.bloom`; a host wanting its own glow model picks `.none` and
    /// composes its own (halo's `NSShadow` vs facet's layer shadow differ).
    public var glow: Glow = .bloom { didSet { resnapIfResting() } }

    /// Hold the live cycle at a FIXED phase WITHOUT a running clock — for
    /// previews / screenshots only (a moving border captures non-deterministically).
    public var previewFrozen: Bool = false { didSet { rebuild() } }
    /// The phase held when `previewFrozen` (a recognizable mid-cycle colour).
    public var previewPhase: CGFloat = 0.35 { didSet { if previewFrozen { renderRestingFrame() } } }

    // MARK: - Internals

    private let glowLayer = CAShapeLayer()               // the wide soft bloom (behind)
    private let strokeLayer = CAShapeLayer()             // the stroke + tight bright bloom
    private static let cycleSeconds: Double = 5          // one full colour cycle
    /// The live effect breathes the stroke width between `lineWidth` and this ×.
    /// ONE source of truth: the resolveBorder maxWidth AND the clip inset derive
    /// from it, so the inset is provably half the fattest breath (no edge clip).
    private static let breathMultiplier: CGFloat = 2.5
    private var clock: Timer?

    public override var isFlipped: Bool { false }
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }   // decorative

    // MARK: - Init

    public init(palette: ResolvedPalette, effect: EffectSpec? = nil) {
        self.palette = palette
        self.effect = effect
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false                     // the glow blooms outward
        let s = NSScreen.main?.backingScaleFactor ?? 2
        for l in [glowLayer, strokeLayer] {              // glow added FIRST → drawn behind
            l.contentsScale = s
            l.fillColor = NSColor.clear.cgColor
            l.masksToBounds = false
            layer?.addSublayer(l)
        }
        setAccessibilityElement(false)                   // decorative — AX-ignored
        rebuild()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    deinit {
        // nonisolated — call the non-isolated APIs directly (mirrors ThemedSkeleton).
        // The clock is NOT touched here (a Timer? is non-Sendable / MainActor-isolated):
        // it is invalidated on every motion-stop in `rebuild()`, and the repeating block
        // self-invalidates the moment `self` is gone, so no leaked tick survives dealloc.
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Geometry

    public override func layout() {
        super.layout()
        relayout()
    }

    /// Re-path the stroke to the current bounds + corner radius. The stroke sits
    /// INSIDE the bounds (inset by half the max breathing width) so the glow and a
    /// fat breath never clip at the edge.
    private func relayout() {
        let inset = lineWidth * Self.breathMultiplier / 2     // half the fattest breath
        let rect = bounds.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = max(0, cornerRadius - inset)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                          transform: nil)
        layerTxn(animated: false) {
            for l in [self.glowLayer, self.strokeLayer] {
                l.frame = self.bounds
                l.path = path
            }
        }
        // Re-apply the current frame's colour/width onto the fresh path.
        if previewFrozen || !motionOK { renderRestingFrame() }
    }

    /// A palette/glow change while RESTING (no clock) re-snaps the static frame; a
    /// change while the clock runs is handled by the next tick — never restart it.
    private func resnapIfResting() { if clock == nil { renderRestingFrame() } }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        strokeLayer.contentsScale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    // MARK: - Ambient-animation lifecycle (mirrors ThemedSkeleton)

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    private var windowVisible: Bool {
        guard let w = window else { return false }
        return !w.isMiniaturized && w.occlusionState.contains(.visible)
    }
    /// Motion runs only for an enabled effect, not frozen, not reduce-motion, and
    /// only while the view has a visible window.
    private var motionOK: Bool {
        effect != nil && effectsEnabled && !previewFrozen && !reduceMotion && windowVisible
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        if let w = window { startObserving(w) }
        rebuild()
    }

    @objc private func ambientConditionsChanged() { rebuild() }

    private func startObserving(_ w: NSWindow) {
        let dc = NotificationCenter.default
        for name in [NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification,
                     NSWindow.didChangeOcclusionStateNotification] {
            dc.addObserver(self, selector: #selector(ambientConditionsChanged),
                           name: name, object: w)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(ambientConditionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    private func stopObserving() {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Single source of truth for the animation state — called on every config /
    /// condition change. Starts the 30 Hz clock when motion is OK, else stops it
    /// and settles a deterministic resting frame.
    private func rebuild() {
        clock?.invalidate(); clock = nil
        if motionOK {
            // A dumb 30 Hz heartbeat (the cadence the apps already use); .common so
            // it keeps cycling while the host scrolls / resizes. Weak self → no cycle.
            let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }   // self-clean on dealloc
                MainActor.assumeIsolated { self.tick() }
            }
            RunLoop.main.add(t, forMode: .common)
            clock = t
            tick()
        } else {
            renderRestingFrame()
        }
    }

    // MARK: - Drawing (snap, never animate the layer — resolveBorder is the motion)

    /// One live frame at wall-clock `now`.
    private func tick() {
        apply(resolveBorder(
            spec: effect, baseWidth: lineWidth,
            minWidth: lineWidth, maxWidth: lineWidth * Self.breathMultiplier,
            cycleSeconds: Self.cycleSeconds, cycleColors: true,
            now: CACurrentMediaTime(), flash: nil))
    }

    /// The resting (non-animating) frame: a frozen/reduce-motion effect colour, or
    /// — with no enabled effect — the flat `primary` stroke.
    private func renderRestingFrame() {
        guard let fx = effect, effectsEnabled else {
            // Static border: flat primary stroke, no glow.
            layerTxn(animated: false) {
                self.strokeLayer.strokeColor = self.palette.primary.cgColor
                self.strokeLayer.lineWidth = self.lineWidth
                self.strokeLayer.shadowOpacity = 0
                self.glowLayer.isHidden = true
            }
            return
        }
        // Frozen capture → the chosen phase; reduce-motion → steady (phase 0).
        let phase = previewFrozen ? Double(previewPhase) : 0
        apply(resolveBorder(
            spec: fx, baseWidth: lineWidth,
            minWidth: lineWidth, maxWidth: lineWidth * Self.breathMultiplier,
            cycleSeconds: Self.cycleSeconds, cycleColors: true,
            now: phase * Self.cycleSeconds, flash: nil))
    }

    /// Materialize a `BorderFrame` onto the stroke layer — snapped, no implicit
    /// animation (the per-frame resolve IS the animation).
    private func apply(_ frame: BorderFrame) {
        let color: NSColor
        switch frame.color {
        case .off:
            color = palette.primary                       // the palette-side fallback
        case .rgb(let r, let g, let b):
            color = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        case .rainbowHue(let h):
            // The apps' calibrated rainbow — pre-converting to sRGB shifts the gamut.
            color = NSColor(hue: h, saturation: 0.9, brightness: 1, alpha: 1)
        }
        let w = CGFloat(frame.width)
        layerTxn(animated: false) {
            self.strokeLayer.strokeColor = color.cgColor
            self.strokeLayer.lineWidth = w
            guard self.glow == .bloom else {
                self.strokeLayer.shadowOpacity = 0
                self.glowLayer.isHidden = true
                return
            }
            // Two-stop neon-tube bloom (the retired AnimatedCardBorder's look): a
            // tight bright halo on the stroke + a wide soft wash on a layer behind,
            // both scaled by the breathing width.
            self.strokeLayer.shadowColor = color.cgColor
            self.strokeLayer.shadowRadius = w * 2.2
            self.strokeLayer.shadowOpacity = 0.85
            self.strokeLayer.shadowOffset = .zero
            self.glowLayer.isHidden = false
            self.glowLayer.strokeColor = color.cgColor      // coincident stroke → casts the wide shadow
            self.glowLayer.lineWidth = w
            self.glowLayer.shadowColor = color.cgColor
            self.glowLayer.shadowRadius = w * 4.8
            self.glowLayer.shadowOpacity = 0.45
            self.glowLayer.shadowOffset = .zero
        }
    }

    // MARK: - Snap-vs-animate (the ThemedSkeleton snap idiom)

    private func layerTxn(animated: Bool, _ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        body()
        CATransaction.commit()
    }
}

#if DEBUG
// Test-only window into the resolved stroke + its clock, so a deterministic test
// can assert the static-vs-effect colour, the breathing width, and the clock state
// WITHOUT a screenshot. Same-file extension to read the private layer; not in release.
extension ThemedBorder {
    struct BorderProbe {
        public let isAnimating: Bool          // a live 30 Hz clock is attached
        public let reduceMotionRespected: Bool
        public let strokeColor: CGColor?
        public let lineWidth: CGFloat
        public let glows: Bool
    }
    var borderProbe: BorderProbe {
        BorderProbe(
            isAnimating: clock != nil,
            reduceMotionRespected: !(reduceMotion && clock != nil),
            strokeColor: strokeLayer.strokeColor,
            lineWidth: strokeLayer.lineWidth,
            glows: strokeLayer.shadowOpacity > 0)
    }
}
#endif
