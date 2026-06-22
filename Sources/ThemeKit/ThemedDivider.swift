// ThemeKit — ThemedDivider: a themed hairline separator (MUI <Divider>).
// A 1-device-pixel rule in a ResolvedPalette's `border` role: horizontal
// (default) or vertical, with fullWidth / inset / middle margin variants and
// an optional centred text-in-divider label. Decorative + non-hit-testable;
// no animation. Themed by assigning `palette`. AppKit / @MainActor.
//
// The family hand-draws list / panel separators today (perch list rows, wand
// tome sections, facet panels); ThemeKit makes it ONE part. Tinted with the
// canonical `border` role — the same neutral@0.10 every card outline uses — so
// a divider always reads as the theme's hairline. The rule is rendered at one
// DEVICE pixel (1/scale pt), pixel-phase-aligned, so it stays crisp on Retina
// rather than blurring across two rows like a literal 1pt line.

import AppKit
import Palette
import PaletteKit
import Motion

@MainActor
public final class ThemedDivider: NSView {

    /// Long-axis direction. `horizontal` = a left-to-right rule (the default);
    /// `vertical` = a top-to-bottom rule that fills the host's height.
    public enum Orientation { case horizontal, vertical }

    /// MUI margin variant. `fullWidth` = flush edge to edge; `inset` = a leading
    /// inset (MUI's 72 pt list-content gutter) — a horizontal-list affordance, so
    /// a VERTICAL rule ignores it and renders as `fullWidth` (like `label`);
    /// `middle` = a symmetric margin along the rule's LENGTH: 16 pt horizontal
    /// (MUI spacing(2)), 8 pt vertical (MUI spacing(1)).
    public enum Variant { case fullWidth, inset, middle }

    // MARK: - Public configuration

    /// The theme. Assigning re-themes the rule.
    public var palette: ResolvedPalette { didSet { applyTheme() } }

    public var orientation: Orientation = .horizontal {
        didSet { syncLabel(); invalidate() }
    }
    public var variant: Variant = .fullWidth { didSet { invalidate() } }

    /// The `.inset`-variant leading inset (MUI's 72 pt list gutter — exposed, not
    /// hardcoded, so a host with a different content inset can match it). Applies
    /// to HORIZONTAL rules only; a vertical `.inset` rule renders as `fullWidth`.
    public var inset: CGFloat = 72 { didSet { if variant == .inset { invalidate() } } }

    /// Hairline thickness in POINTS — honored only when `deviceHairline` is
    /// false. Default 1 is the MUI "thin" intent; with `deviceHairline` true the
    /// rule is a single device pixel regardless (crisper than a literal 1 pt on
    /// Retina). Set > 1 (and `deviceHairline = false`) for a heavier rule.
    public var thickness: CGFloat = 1 { didSet { invalidate() } }

    /// When true (default) the rule is one device pixel (1/backingScale pt),
    /// pixel-phase-aligned. Set false to honor `thickness` literally in points.
    public var deviceHairline: Bool = true { didSet { invalidate() } }

    /// Optional text-in-divider (MUI `children`). A cheap centre-only port: the
    /// label is drawn centred over a gap cut in the rule. `nil` ⇒ a plain rule.
    /// Honored only for `.horizontal` (vertical + left/right alignment are out
    /// of scope — a host wanting those composes its own label + two dividers).
    public var label: String? { didSet { syncLabel(); invalidate() } }

    /// The colour BEHIND the rule — used to fill the gap the label sits in (so
    /// the rule reads as cut, not struck through). Defaults to
    /// `palette.background`; a host on a lifted panel sets the panel's colour.
    /// Only the gap fill depends on it, so the `didSet` repaints JUST that — the
    /// narrow path, mirroring ThemedTextField's `surfaceColor`, not a re-theme.
    public var surfaceColor: NSColor? {
        didSet { layerTxn(animated: false) { gapLayer.backgroundColor = surface.cgColor } }
    }

    // MARK: - Internals

    private let ruleLayer = CALayer()        // the hairline fill (solid backgroundColor)
    private let gapLayer = CALayer()         // surface fill cutting the rule under the label
    private let labelLayer = CATextLayer()   // optional centred text-in-divider

    // Metrics
    private let labelPadX: CGFloat = 10          // breathing room each side of the label
    private let middleInset: CGFloat = CGFloat(Space.xl)        // MUI spacing(2) — horizontal `.middle` long-axis margin
    private let middleVerticalInset: CGFloat = CGFloat(Space.md) // MUI spacing(1) — vertical `.middle` long-axis (top/bottom) margin
    private var labelSize: CGFloat { 11 }        // small caption tier

    public override var isFlipped: Bool { false }   // symmetric, y-up bottom-origin

    public override var intrinsicContentSize: NSSize {
        let t = ruleThickness
        switch orientation {
        case .horizontal:
            // With a label the view must be tall enough for the text.
            let h = hasLabel ? max(t, ceil(labelSize) + 6) : t
            return NSSize(width: NSView.noIntrinsicMetric, height: h)
        case .vertical:
            return NSSize(width: t, height: NSView.noIntrinsicMetric)
        }
    }

    private var hasLabel: Bool { label != nil && orientation == .horizontal }

    // MARK: - Init

    public init(palette: ResolvedPalette) {
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        // contentsScale matters for the TEXT-bearing sublayer (the label) — AppKit
        // auto-manages only the view's own backing layer. Solid-fill layers (rule /
        // gap) raster no contents, so it's cosmetic for them; we seed the rule too
        // for symmetry. Refreshed in viewDidChangeBackingProperties on a DPI change.
        let s = NSScreen.main?.backingScaleFactor ?? 2

        ruleLayer.contentsScale = s
        layer?.addSublayer(ruleLayer)         // bottom

        gapLayer.opacity = 0                   // shown only when a label is present
        layer?.addSublayer(gapLayer)

        labelLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        labelLayer.contentsScale = s
        labelLayer.alignmentMode = .center
        labelLayer.truncationMode = .end
        labelLayer.isWrapped = false
        layer?.addSublayer(labelLayer)         // top, over the gap

        setAccessibilityElement(false)         // decorative — AX-ignored
        applyTheme()
        syncLabel()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    private func invalidate() {
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    // MARK: - Theming

    // The label is `.caption` (11pt) via `palette.uiFont(_:)` — the shared
    // type-scale resolver (honours .mono/.rounded/.menu).

    private var surface: NSColor { surfaceColor ?? palette.background ?? .textBackgroundColor }

    public func applyTheme() {
        // Snap, never cross-fade: a divider has no animated transition, and an
        // unwrapped sublayer mutation would implicitly ~0.25 s fade on a theme
        // switch (these layers have no action-disabling delegate).
        layerTxn(animated: false) {
            self.ruleLayer.backgroundColor = self.palette.border.cgColor
            self.gapLayer.backgroundColor = self.surface.cgColor
            self.labelLayer.foregroundColor = self.palette.muted.cgColor
            self.labelLayer.font = self.palette.uiFont(.caption)
            self.labelLayer.fontSize = self.labelSize
        }
        sizeLabel()
        needsLayout = true
    }

    /// Push the current `label` into the text layer + (un)hide it. Snapped, like
    /// every other layer mutation here.
    private func syncLabel() {
        layerTxn(animated: false) {
            self.labelLayer.string = self.label ?? ""
            self.labelLayer.isHidden = !self.hasLabel
        }
        sizeLabel()
    }

    /// CATextLayer renders nothing without a non-zero `bounds`; size it to the
    /// label text at the caption font.
    private func sizeLabel() {
        let s = ((label ?? "") as NSString)
            .size(withAttributes: [.font: palette.uiFont(.caption)])
        layerTxn(animated: false) {
            self.labelLayer.bounds = CGRect(x: 0, y: 0,
                                            width: ceil(s.width) + 2, height: ceil(s.height))
        }
    }

    // MARK: - Device-pixel geometry

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    /// Hairline thickness in points: one device pixel when `deviceHairline`, else
    /// the caller's `thickness` floored at a device pixel — so a degenerate 0 /
    /// negative value still draws a hairline instead of silently vanishing.
    private var ruleThickness: CGFloat {
        deviceHairline ? (1.0 / backingScale) : max(thickness, 1.0 / backingScale)
    }

    /// Snap a coordinate so a `ruleThickness`-thin bar's leading edge lands ON a
    /// device-pixel boundary (no straddle → no blur). Phase-align the EDGE in
    /// backing space — do NOT round-trip the whole rect through
    /// `backingAlignedRect`, which would round the sub-point thickness to 0.
    private func pixelSnap(_ coord: CGFloat) -> CGFloat {
        let s = backingScale
        return (coord * s).rounded(.down) / s
    }

    /// (leading, trailing) insets along the rule's long axis for the variant.
    /// `inset` is a horizontal-list affordance — a vertical rule treats `.inset`
    /// as `.fullWidth`. `.middle` is a symmetric long-axis margin in BOTH
    /// orientations: 16 pt horizontal, 8 pt vertical (MUI spacing(2) / spacing(1)).
    private func longAxisInsets() -> (CGFloat, CGFloat) {
        switch (orientation, variant) {
        case (_, .fullWidth):            return (0, 0)
        case (.horizontal, .inset):      return (inset, 0)
        case (.vertical, .inset):        return (0, 0)   // inset is horizontal-only → fullWidth
        case (.horizontal, .middle):     return (middleInset, middleInset)
        case (.vertical, .middle):       return (middleVerticalInset, middleVerticalInset)
        }
    }

    // MARK: - Layout

    public override func layout() {
        super.layout()
        layerTxn(animated: false) {
            let t = self.ruleThickness
            let (lead, trail) = self.longAxisInsets()
            switch self.orientation {
            case .horizontal:
                let y = self.pixelSnap(self.bounds.midY - t / 2)
                self.ruleLayer.frame = CGRect(
                    x: lead, y: y,
                    width: max(self.bounds.width - lead - trail, 0), height: t)
            case .vertical:
                let x = self.pixelSnap(self.bounds.midX - t / 2)
                self.ruleLayer.frame = CGRect(
                    x: x, y: lead, width: t,
                    height: max(self.bounds.height - lead - trail, 0))
            }
            self.layoutLabelGap()
        }
    }

    /// Centre the label + cut a surface-coloured gap in the rule beneath it.
    /// No-op (and hides the gap) when there is no horizontal label.
    private func layoutLabelGap() {
        guard hasLabel else {
            gapLayer.opacity = 0
            return
        }
        let cx = bounds.midX, cy = bounds.midY
        labelLayer.position = CGPoint(x: cx, y: cy)
        let gapW = labelLayer.bounds.width + 2 * labelPadX
        let gapH = max(ruleThickness, ceil(labelSize))
        gapLayer.frame = CGRect(x: cx - gapW / 2, y: cy - gapH / 2,
                                width: gapW, height: gapH)
        gapLayer.opacity = 1
    }

    /// Keep the rule + label crisp across a display-scale change. `contentsScale`
    /// was captured once at init from `NSScreen.main` (before a window existed) —
    /// stale after a move to a different-DPI display. The pixel snap is also
    /// scale-dependent, so re-lay-out.
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = backingScale
        ruleLayer.contentsScale = s
        labelLayer.contentsScale = s
        needsLayout = true
    }

    // MARK: - Snap-vs-animate (verbatim ThemedTextField idiom)

    /// Wrap layer mutations so they SNAP (a divider never animates). Kept as a
    /// local helper — there is no shared one; each widget re-declares it.
    private func layerTxn(animated: Bool, _ body: () -> Void) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(ThemedTransition.Duration.enter)
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        body()
        CATransaction.commit()
    }

    // MARK: - Decorative: clicks pass through

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

#if DEBUG
// Test-only window into the rendered rule, so a deterministic test can assert
// the theme colour / thickness / orientation / inset WITHOUT a screenshot.
// Same-file extension so it can read the private layers; not built into release.
extension ThemedDivider {
    struct DividerProbe {
        public let strokeColor: CGColor?
        public let thickness: CGFloat       // the thin-axis extent of the rule
        public let isVertical: Bool
        public let ruleFrame: CGRect
        public let hasLabel: Bool
    }
    var dividerProbe: DividerProbe {
        let f = ruleLayer.frame
        return DividerProbe(
            strokeColor: ruleLayer.backgroundColor,
            thickness: orientation == .vertical ? f.width : f.height,
            isVertical: orientation == .vertical,
            ruleFrame: f,
            hasLabel: hasLabel)
    }
}
#endif
