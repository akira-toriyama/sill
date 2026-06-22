// ThemeKit — ThemedSkeleton: a themed loading placeholder (MUI <Skeleton>).
// A low-alpha neutral wash (text / circular / rectangular / rounded) that
// alpha-blends over whatever surface hosts it, with a `pulse` (opacity breath)
// or `wave` (gradient sweep) ambient animation — reduce-motion-aware, torn down
// when the window is hidden, and freezable at a fixed phase for deterministic
// still capture. Themed by assigning `palette`. AppKit / @MainActor.
//
// Every app shows a loading state and hand-rolls a grey box today; ThemeKit
// makes it ONE part. The wash is `muted` at a low alpha (PaletteKit's `.subtle`
// ink tier), so it reads as a faint placeholder over any theme's background.
//
// Ambient-animation discipline (the load-bearing correctness here): CoreAnimation
// does NOT pause an infinite animation when its window is miniaturized / occluded
// / detached, so we explicitly remove the animation when the view loses a visible
// window and re-add it when one returns (viewDidMoveToWindow + window observers).
// We also honour `accessibilityDisplayShouldReduceMotion` (live, via NSWorkspace),
// and re-tint under a running animation WITHOUT a glitch by snapping the colour
// on a separate keypath inside a disabled-action transaction.

import AppKit
import QuartzCore
import Palette
import PaletteKit

@MainActor
public final class ThemedSkeleton: NSView {

    /// MUI shape. `text` = a short bar sized to the font line; `circular` = a
    /// pill/avatar; `rectangular` = a sharp block; `rounded` = a soft block.
    public enum Variant { case text, circular, rectangular, rounded }

    /// Ambient animation. `pulse` = an opacity breath (the MUI default);
    /// `wave` = a highlight sweeping left→right; `none` = a static wash.
    public enum Animation { case pulse, wave, none }

    // MARK: - Public configuration

    /// The theme. Assigning re-tints the wash WITHOUT disturbing a running
    /// animation (colour is snapped on its own keypath).
    public var palette: ResolvedPalette { didSet { applyTheme(); invalidate() } }

    public var variant: Variant = .text { didSet { invalidate() } }
    public var animation: Animation = .pulse { didSet { rebuildAnimation() } }

    /// Explicit size. `nil` on a dimension ⇒ that dimension is intrinsic: `text`
    /// derives its height from the themed font line; `circular` derives a
    /// diameter from height-or-width; otherwise width spans the host and height
    /// defaults to a block height. A host typically sets `width` for text rows.
    public var width: CGFloat? { didSet { invalidate() } }
    public var height: CGFloat? { didSet { invalidate() } }

    /// Hold the animation at a FIXED mid-cycle phase (a recognizable shimmer)
    /// WITHOUT a running timer — for previews / screenshots only. A still capture
    /// of a continuous shimmer is non-deterministic, so the bench wires this true
    /// (the analogue of ThemedTextField's `previewFocused`).
    public var previewFrozen: Bool = false { didSet { rebuildAnimation() } }

    // MARK: - Internals

    private let fillLayer = CALayer()             // the tinted placeholder shape
    private let waveLayer = CAGradientLayer()     // wave-only highlight band (child of fill)

    private static let pulseKey = "skeleton.pulse"
    private static let waveKey  = "skeleton.wave"

    // Metrics
    private let pulseRoundTrip: CFTimeInterval = 2.0   // MUI pulse: 2 s ease-in-out round trip
    private let waveSeconds: CFTimeInterval = 1.6      // MUI wave: 1.6 s linear sweep
    private let initialDelay: CFTimeInterval = 0.5     // MUI initial delay
    private let pulseMin: Float = 0.4                  // MUI opacity floor
    private let frozenPhase: CGFloat = 0.5             // mid-cycle hold for still capture
    /// The eased pulse opacity at the frozen phase — a recognizable mid-dim.
    private var frozenPulseOpacity: Float { 1 - (1 - pulseMin) * Float(frozenPhase) }

    private var lastWaveSize: CGSize = .zero
    /// The MUI 0.5 s first-appearance delay applies ONCE; a resume after an
    /// off-screen gap / resize must NOT re-introduce a dead pause.
    private var hasStarted = false
    private var startDelay: CFTimeInterval { hasStarted ? 0 : initialDelay }

    public override var isFlipped: Bool { false }

    /// Text-row height from the themed font (MUI's `scale(1, 0.6)` squash, here
    /// ~0.6 of the font's line box).
    private var lineHeight: CGFloat { ceil(palette.uiFont(.body).boundingRectForFont.height * 0.6) }

    public override var intrinsicContentSize: NSSize {
        switch variant {
        case .text:
            return NSSize(width: width ?? NSView.noIntrinsicMetric, height: height ?? lineHeight)
        case .circular:
            let d = height ?? width ?? 40
            return NSSize(width: d, height: d)
        case .rectangular, .rounded:
            return NSSize(width: width ?? NSView.noIntrinsicMetric, height: height ?? 16)
        }
    }

    private var cornerRadius: CGFloat {
        switch variant {
        case .rectangular: return 0
        case .rounded:     return 4               // ~MUI theme.shape.borderRadius
        case .text:        return 4               // approximated uniform (MUI's ellipse radius)
        case .circular:    return min(bounds.width, bounds.height) / 2
        }
    }

    // MARK: - Init

    public init(palette: ResolvedPalette) {
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        let s = NSScreen.main?.backingScaleFactor ?? 2
        fillLayer.contentsScale = s
        fillLayer.masksToBounds = true            // clip the wave child to the rounded shape
        layer?.addSublayer(fillLayer)

        waveLayer.contentsScale = s
        waveLayer.startPoint = CGPoint(x: 0, y: 0.5)
        waveLayer.endPoint   = CGPoint(x: 1, y: 0.5)
        waveLayer.isHidden = true                 // shown only for .wave
        fillLayer.addSublayer(waveLayer)

        setAccessibilityElement(false)            // a placeholder — AX-ignored
        applyTheme()
        rebuildAnimation()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    private func invalidate() {
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    // Symmetric with stopObserving() — clear BOTH centres. (Selector observers
    // auto-deregister on dealloc on 13+, so this is belt-and-suspenders; deinit
    // is nonisolated, so we call the non-isolated removeObserver APIs directly
    // rather than the @MainActor stopObserving().)
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Theming

    // Fonts via `palette.uiFont(_:)` — the shared type-scale resolver
    // (honours .mono/.rounded/.menu; the old local helper dropped two).

    /// The wash — `muted` at the `.subtle` alpha tier (≈0.16). Translucent on
    /// purpose: it alpha-blends over the host backdrop, and the pulse breathes
    /// its opacity (MUI models the skeleton as a low-alpha element).
    private var tint: NSColor { palette.ink(.subtle, of: .muted) }
    /// The wave's brighter band — `foreground` at the same tier.
    private var highlight: NSColor { palette.ink(.subtle, of: .foreground) }

    /// Snap the colours (never animate the colour keypath) so a theme switch
    /// re-tints under a running pulse/wave without a glitch.
    public func applyTheme() {
        layerTxn(animated: false) {
            self.fillLayer.backgroundColor = self.tint.cgColor
            self.waveLayer.colors = [NSColor.clear.cgColor,
                                     self.highlight.cgColor,
                                     NSColor.clear.cgColor]
            self.waveLayer.locations = [0, 0.5, 1]
        }
    }

    // MARK: - Ambient-animation lifecycle

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    /// A window that is actually on screen — neither miniaturized nor fully
    /// occluded. `occlusionState` is a bitmask, so test membership (never `==`).
    private var windowVisible: Bool {
        guard let w = window else { return false }
        return !w.isMiniaturized && w.occlusionState.contains(.visible)
    }
    /// Motion should run only for an animated variant, not frozen, not
    /// reduce-motion, and only while the view has a visible window.
    private var motionOK: Bool {
        animation != .none && !previewFrozen && !reduceMotion && windowVisible
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        if let w = window { startObserving(w) }
        rebuildAnimation()
    }

    /// Any change to the ambient conditions (reduce-motion toggled, window
    /// miniaturized / deminiaturized / occlusion changed) re-derives the state.
    @objc private func ambientConditionsChanged() { rebuildAnimation() }

    private func startObserving(_ w: NSWindow) {
        let dc = NotificationCenter.default
        for name in [NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification,
                     NSWindow.didChangeOcclusionStateNotification] {
            dc.addObserver(self, selector: #selector(ambientConditionsChanged),
                           name: name, object: w)
        }
        // Reduce-motion changes post on NSWorkspace's OWN centre (not the
        // default one), object nil so we never miss a poster.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(ambientConditionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    private func stopObserving() {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// The single source of truth for the animation state — called on every
    /// condition change. Removes any running animation, then either re-adds it
    /// (motion OK) or settles a deterministic FROZEN phase (frozen / reduce-
    /// motion / off-screen). Color is left untouched (see applyTheme).
    private func rebuildAnimation() {
        fillLayer.removeAnimation(forKey: Self.pulseKey)
        waveLayer.removeAnimation(forKey: Self.waveKey)
        layerTxn(animated: false) {
            switch self.animation {
            case .none:
                self.waveLayer.isHidden = true
                self.fillLayer.opacity = 1
            case .pulse:
                self.waveLayer.isHidden = true
                if self.motionOK {
                    self.fillLayer.opacity = 1
                    self.fillLayer.add(self.makePulse(), forKey: Self.pulseKey)
                    self.hasStarted = true
                } else {
                    self.fillLayer.opacity = self.frozenPulseOpacity
                }
            case .wave:
                self.waveLayer.isHidden = false
                self.fillLayer.opacity = 1
                if self.motionOK {
                    self.positionWave(atPhase: 0)
                    self.waveLayer.add(self.makeWave(), forKey: Self.waveKey)
                    self.hasStarted = true
                } else {
                    // Frozen for capture → centre the highlight (mid-shimmer);
                    // reduce-motion / off-screen → rest at phase 0 (highlight off
                    // the left edge, the documented model rest), so a reduce-
                    // motion user sees a calm uniform wash, not a parked band.
                    self.positionWave(atPhase: self.previewFrozen ? self.frozenPhase : 0)
                }
            }
        }
    }

    private func makePulse() -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1.0
        a.toValue   = pulseMin
        a.duration  = pulseRoundTrip / 2          // each way; autoreverse → full round trip
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.autoreverses = true
        a.repeatCount = .infinity
        a.beginTime = CACurrentMediaTime() + startDelay   // 0.5 s ONLY on first start
        return a
    }

    private func makeWave() -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: "position.x")
        a.fromValue = waveX(atPhase: 0)
        a.toValue   = waveX(atPhase: 1)
        a.duration  = waveSeconds
        a.timingFunction = CAMediaTimingFunction(name: .linear)
        a.repeatCount = .infinity                  // restart sweep (no autoreverse)
        a.beginTime = CACurrentMediaTime() + startDelay   // 0.5 s ONLY on first start
        return a
    }

    /// The wave band is one bounds-width wide (anchored centre); at phase 0 the
    /// highlight sits off the left, at phase 1 off the right. The model rest is
    /// phase 0, so removing the animation leaves no highlight showing.
    private func waveX(atPhase p: CGFloat) -> CGFloat {
        -bounds.width / 2 + p * bounds.width * 2
    }
    private func positionWave(atPhase p: CGFloat) {
        waveLayer.position = CGPoint(x: waveX(atPhase: p), y: bounds.height / 2)
    }

    // MARK: - Layout

    public override func layout() {
        super.layout()
        layerTxn(animated: false) {
            self.fillLayer.frame = self.bounds
            self.fillLayer.cornerRadius = self.cornerRadius   // circular depends on bounds
        }
        // The wave geometry depends on bounds; refresh only on a REAL size change
        // (so a routine layout pass doesn't restart the sweep).
        if bounds.size != lastWaveSize {
            lastWaveSize = bounds.size
            layerTxn(animated: false) {
                self.waveLayer.frame = CGRect(x: -self.bounds.width, y: 0,
                                              width: self.bounds.width, height: self.bounds.height)
            }
            if animation == .wave { rebuildAnimation() }
        }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        fillLayer.contentsScale = s
        waveLayer.contentsScale = s
    }

    // MARK: - Snap-vs-animate (verbatim ThemedTextField idiom)

    private func layerTxn(animated: Bool, _ body: () -> Void) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.16)
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        body()
        CATransaction.commit()
    }
}

#if DEBUG
// Test-only window into the rendered placeholder + its animation state, so a
// deterministic test can assert the tint / corner / frozen-phase / animating
// flags WITHOUT a screenshot or a running clock. Same-file extension so it can
// read the private layers; not built into release.
extension ThemedSkeleton {
    struct SkeletonProbe {
        public let frozen: Bool
        public let phase: CGFloat
        public let isAnimating: Bool          // a live CAAnimation is attached
        public let reduceMotionRespected: Bool // never animating while reduce-motion is on
        public let tintColor: CGColor?
        public let cornerRadius: CGFloat
        public let wavePositionX: CGFloat      // the wave band's centre x (rest = off-left)
    }
    var skeletonProbe: SkeletonProbe {
        let anim = fillLayer.animation(forKey: Self.pulseKey) != nil
                || waveLayer.animation(forKey: Self.waveKey) != nil
        return SkeletonProbe(
            frozen: previewFrozen,
            phase: previewFrozen ? frozenPhase : 0,
            isAnimating: anim,
            reduceMotionRespected: !(reduceMotion && anim),
            tintColor: fillLayer.backgroundColor,
            cornerRadius: fillLayer.cornerRadius,
            wavePositionX: waveLayer.position.x)
    }
}
#endif
