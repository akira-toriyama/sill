// ThemeKit — ThemedFAB: a Floating Action Button (MUI <Fab>, basic). A
// faithful AppKit port of Material-UI v5's FAB — a circular, icon-first
// action button that floats ABOVE the content with a HIGH resting elevation
// (it sits higher than a contained button), plus the `extended` pill variant
// (icon + label). Two colour roles (primary / secondary — a FAB is an accent,
// so there is no neutral / error role), three sizes (small / medium / large,
// default large per MUI), themed by assigning a PaletteKit `ResolvedPalette`.
// AppKit / @MainActor.
//
// Built on ThemedButton's `contained` toolkit VERBATIM: cell-less NSControl
// (custom isEnabled / target / action storage), tracking-area hover, the
// mouseDown/Dragged/Up press trio, Space / key-equivalent keyboard activation
// (with the isFlashing re-entrancy + isARepeat guards), a SEPARATE unclipped
// shadow layer with an explicit `shadowPath` (a masksToBounds fill erases its
// own shadow — the canonical Core-Animation gotcha), device-pixel-rasterized
// Phosphor SVG icons, the house 0.16 s ease-out `layerTxn` timing, and `preview…`
// overrides for deterministic screenshots. What it DROPS vs the button:
// trailing icon, fullWidth, the outlined border, and grouping — a FAB is a
// single, self-contained accent.
//
// Geometry: `cornerRadius = height / 2`, so a square circular FAB is a perfect
// circle and an extended FAB has fully-rounded pill ends. Ink (icon + extended
// label) is the best-contrast black/white on the role fill via PaletteKit's
// `onPrimary` / `onSecondary` (so a secondary FAB on a neon theme still gets a
// legible glyph). The interaction 演出 (hover / pressed state layer + the
// pressed elevation deepening) is REQUIRED and runs LIVE in `prism`.

import AppKit
import Palette
import PaletteKit
import Motion

extension ThemedFAB.Role {
    /// Bridge to the shared `ControlRole` (a FAB has no `.error` — that's an
    /// intentional API narrowing, not a gap).
    var control: ControlRole {
        switch self {
        case .primary:   return .primary
        case .secondary: return .secondary
        }
    }
}

@MainActor
public final class ThemedFAB: ThemedControl {

    /// MUI variant. `circular` = an icon-only round button (the default FAB);
    /// `extended` = a pill with a leading icon + label.
    public enum Variant { case circular, extended }

    /// MUI size — sets the circular diameter / extended height, icon, and font.
    /// Defaults to `.large` (MUI's default FAB size).
    public enum Size { case small, medium, large }

    /// Colour role. A FAB is an accent action, so only `primary` (the MUI
    /// default) and `secondary` — no neutral / error role. Maps to the matching
    /// `ResolvedPalette` role; greyed while disabled.
    public enum Role { case primary, secondary }

    // MARK: - Public configuration

    public var variant: Variant = .circular { didSet { applyTheme(); relayout() } }
    public var size:    Size    = .large    { didSet { applyTheme(); relayout() } }
    public var role:    Role    = .primary  { didSet { applyTheme() } }

    /// The icon (MUI's FAB icon). The WHOLE control for `circular`; the leading
    /// adornment for `extended`. Tinted to the role's contrast ink. A **Phosphor
    /// slug** (e.g. `"plus"`) resolved via `phosphorImage`; `leadingImage` below is
    /// the pre-resolved-image entry (app icon / favicon / brand logo).
    public var leadingSymbol: String? { didSet { applyTheme(); relayout() } }

    /// Pre-resolved icon image (wins over `leadingSymbol`): `phosphorImage(…)` /
    /// `simpleIconImage(…)` or any app icon / favicon / emoji bitmap. `isTemplate`
    /// ⇒ tinted to the role's contrast ink; else drawn raw (multi-colour).
    public var leadingImage: NSImage? { didSet { applyTheme(); relayout() } }

    /// The label — `extended`-ONLY (a circular FAB is icon-only). Drawn
    /// UPPERCASE with MUI's 0.4 pt tracking, like ThemedButton; the accessible
    /// name keeps the original case. Also used as the AX name for a circular
    /// FAB (which draws no text), so set it for VoiceOver even when circular.
    public var label: String = "" { didSet { applyTheme(); relayout() } }

    /// Tap handler (the sill-idiom convenience). Fires together with the
    /// `NSControl` `target`/`action`, on a mouse-up inside, Space, or the
    /// `keyEquivalent`.
    public var onTap: (() -> Void)?

    // MARK: - Internals

    private let shadowLayer   = CALayer()        // elevation — UNCLIPPED, explicit shadowPath
    private let fillLayer     = CALayer()        // round/pill fill (clips the overlay child)
    private let overlayLayer  = CALayer()        // hover / press state layer (child of fill)
    private let iconLayer     = CALayer()        // the leading / sole icon
    private let titleLayer    = CATextLayer()    // extended label (hidden for circular)

    /// Rendered icon point-size (nil ⇒ no icon) — drives layout + extended width.
    private var iconSize: CGSize?

    // MARK: - Metrics (MUI v5 Fab values; circular diameters 40/48/56,
    //         extended heights 34/40/48, content centred)

    private struct Metrics {
        let diameter, height, hpad, iconPt, font, gap: CGFloat
    }
    private var metrics: Metrics {
        let diameter: CGFloat = size == .small ? 40 : size == .medium ? 48 : 56
        let height:   CGFloat = size == .small ? 34 : size == .medium ? 40 : 48
        let iconPt:   CGFloat = size == .small ? 20 : size == .medium ? 24 : 28
        let font:     CGFloat = size == .small ? 13 : 14
        let hpad:     CGFloat = size == .small ? 8 : 16
        return Metrics(diameter: diameter, height: height, hpad: hpad,
                       iconPt: iconPt, font: font, gap: CGFloat(Space.md))
    }

    public override var intrinsicContentSize: NSSize {
        let m = metrics
        switch variant {
        case .circular:
            // A fixed square — the label (AX-only here) never widens it.
            return NSSize(width: m.diameter, height: m.diameter)
        case .extended:
            let iconW  = iconSize?.width ?? 0
            let labelW = label.isEmpty ? 0 : titleLayer.bounds.width
            let present = [iconW > 0, labelW > 0].filter { $0 }.count
            let gaps = CGFloat(max(0, present - 1)) * m.gap
            let content = m.hpad + iconW + labelW + gaps + m.hpad
            return NSSize(width: max(m.height, ceil(content)), height: m.height)
        }
    }

    // MARK: - Init

    public override init(palette: ResolvedPalette) {
        super.init(palette: palette)

        let s = themeBackingScale

        // Shadow (bottom) — never clipped, explicit rounded/circular silhouette.
        shadowLayer.masksToBounds = false
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.contentsScale = s
        layer?.addSublayer(shadowLayer)

        // Fill clips the overlay child to the round / pill rect.
        fillLayer.masksToBounds = true
        fillLayer.contentsScale = s
        layer?.addSublayer(fillLayer)
        overlayLayer.contentsScale = s
        fillLayer.addSublayer(overlayLayer)

        iconLayer.contentsGravity = .resizeAspect
        iconLayer.contentsScale = s
        iconLayer.isHidden = true
        layer?.addSublayer(iconLayer)

        titleLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        titleLayer.contentsScale = s
        titleLayer.alignmentMode = .center
        titleLayer.truncationMode = .end
        titleLayer.isWrapped = false
        titleLayer.isHidden = true
        layer?.addSublayer(titleLayer)

        setAccessibilityRole(.button)
        applyTheme()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    private func relayout() {
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    // MARK: - Theming

    // Fonts via `palette.uiFont(_:)` — the shared type-scale resolver
    // (honours .mono/.rounded/.menu; the old local helper dropped two).

    private var roleColor: NSColor { palette.color(for: role.control) }

    /// Best-contrast ink on the role fill via PaletteKit's role accessors
    /// (`onPrimary` / `onSecondary`) — the same WCAG crossover, so a secondary
    /// FAB on a neon theme gets a legible glyph, not just primary.
    private var roleInk: NSColor {
        switch role {
        case .primary:   return palette.onPrimary()
        case .secondary: return palette.onSecondary()
        }
    }

    /// Icon + extended-label ink for the current state (role contrast / muted).
    private var inkColor: NSColor { isEnabled ? roleInk : palette.muted }

    /// The stable fill (snapped; never animated on hover — the darken is the
    /// overlay). Role fill when enabled; a neutral muted wash when disabled
    /// (matches ThemedButton's contained disabled fill).
    private var baseFillColor: NSColor {
        isEnabled ? roleColor : palette.ink(.subtle, of: .muted)
    }

    /// The hover / press state layer (animated): the contrast ink on the role
    /// fill at MUI's hover / active alpha (darkens a light fill, lightens a dark
    /// one — theme-robust). Focus shows the ring only (no wash), matching the
    /// contained button.
    private var overlayColor: NSColor {
        guard isEnabled else { return .clear }
        let on = palette.bestContrast(on: roleColor)
        if fxPressed { return on.withAlphaComponent(0.12) }
        if fxHovered { return on.withAlphaComponent(0.08) }
        return .clear
    }

    /// FAB elevation: it floats HIGHER than a button (resting dp8) and only
    /// deepens on press (dp12). Hover / focus do NOT bump it (a FAB is already
    /// raised) — with only two rungs there is no dip risk. (Rest snapped from a
    /// bespoke 0.30 to the dp8 ladder value 0.28 in #14a — ~7% lighter, per the
    /// #13 elevation-token plan.)
    private var elevation: (opacity: Float, radius: CGFloat, offsetY: CGFloat) {
        guard isEnabled else { return palette.shadow(.flat) }
        if fxPressed { return palette.shadow(.dp12) }
        return palette.shadow(.dp8)
    }

    // MARK: - Base hook overrides

    override func applyThemeSnap() {
        fillLayer.backgroundColor = baseFillColor.cgColor
    }

    override func rebuildContent() {
        rebuildTitle()
        rebuildIcon()
    }

    override func syncAccessibility() {
        setAccessibilityLabel(label.isEmpty ? nil : label)   // original case for VoiceOver
        setAccessibilityEnabled(isEnabled)
    }

    override func applyInteractionState() {
        overlayLayer.backgroundColor = overlayColor.cgColor
        let e = elevation
        shadowLayer.shadowOpacity = e.opacity
        shadowLayer.shadowRadius  = e.radius
        shadowLayer.shadowOffset  = CGSize(width: 0, height: e.offsetY)
    }

    /// Push the uppercased, tracked label into the text layer — extended only;
    /// hidden (but kept for AX) when circular.
    private func rebuildTitle() {
        let drawsTitle = (variant == .extended && !label.isEmpty)
        let f = palette.uiFont(metrics.font, .medium)
        let s = label.uppercased()
        let attr = NSAttributedString(string: s, attributes: [
            .font: f, .kern: 0.4, .foregroundColor: inkColor])
        let sz = attr.size()
        layerTxn(animated: false) {
            self.titleLayer.string = drawsTitle ? attr : nil
            self.titleLayer.foregroundColor = self.inkColor.cgColor
            self.titleLayer.isHidden = !drawsTitle
            self.titleLayer.bounds = CGRect(x: 0, y: 0,
                                            width: ceil(sz.width) + 2, height: ceil(sz.height))
        }
    }

    private func rebuildIcon() {
        iconSize = applyIconSlot(iconLayer, symbol: leadingSymbol, image: leadingImage,
                                 pt: metrics.iconPt, tint: inkColor, scale: themeBackingScale)
    }

    // MARK: - Layout

    override func positionLayers(in bounds: CGRect, local: CGRect) {
        let b = bounds
        let r = min(b.width, b.height) / 2
        shadowLayer.frame = b
        shadowLayer.shadowPath =
            CGPath(roundedRect: local, cornerWidth: r, cornerHeight: r, transform: nil)
        fillLayer.frame = b
        fillLayer.cornerRadius = r
        overlayLayer.frame = local
        overlayLayer.cornerRadius = r
        layoutContent(in: b, m: metrics)
    }

    override func focusRingPath(in rect: CGRect) -> CGPath {
        let r = min(rect.width, rect.height) / 2
        return concentricRingPath(in: rect, radius: r)
    }

    /// Centre the icon (+ extended label) row, with `gap` between the two when
    /// both are present. Circular draws the icon only.
    private func layoutContent(in b: NSRect, m: Metrics) {
        var segs: [(CALayer, CGSize, Bool)] = []   // (layer, size, isTitle)
        if let sz = iconSize { segs.append((iconLayer, sz, false)) }
        if variant == .extended, !label.isEmpty {
            segs.append((titleLayer, titleLayer.bounds.size, true))
        }
        let total = segs.reduce(0) { $0 + $1.1.width }
                  + CGFloat(max(0, segs.count - 1)) * m.gap
        var x = (b.width - total) / 2
        let cy = b.midY
        for (lyr, sz, isTitle) in segs {
            if isTitle {
                titleLayer.position = CGPoint(x: x + sz.width / 2, y: cy)
            } else {
                lyr.frame = CGRect(x: x, y: cy - sz.height / 2, width: sz.width, height: sz.height)
            }
            x += sz.width + m.gap
        }
    }

    override func updateContentsScale(_ s: CGFloat) {
        for l in [shadowLayer, fillLayer, overlayLayer, iconLayer] { l.contentsScale = s }
        titleLayer.contentsScale = s
        rebuildIcon()        // re-rasterize at the new device scale
        needsLayout = true
    }

    // MARK: - Activation

    override func activate() {
        guard isEnabled else { return }
        onTap?()
        super.activate()
    }
}

#if DEBUG
// Test-only window into the resolved appearance, so a deterministic test can
// assert the per-variant / per-state colours + geometry WITHOUT synthetic
// events (use the `preview…` overrides to drive the state). Same-file extension
// so it can read the private layers; not built into release.
extension ThemedFAB {
    struct FABProbe {
        public let fillColor: CGColor?
        public let inkColor: CGColor?
        public let overlayColor: CGColor?
        public let shadowOpacity: Float
        public let shadowRadius: CGFloat
        public let shadowOffsetY: CGFloat
        public let focusRingOpacity: Float
        public let focusRingStroke: CGColor?
        public let cornerRadius: CGFloat
        public let titleHidden: Bool
        public let hasIcon: Bool
    }
    var fabProbe: FABProbe {
        FABProbe(
            fillColor: fillLayer.backgroundColor,
            inkColor: inkColor.cgColor,
            overlayColor: overlayLayer.backgroundColor,
            shadowOpacity: shadowLayer.shadowOpacity,
            shadowRadius: shadowLayer.shadowRadius,
            shadowOffsetY: shadowLayer.shadowOffset.height,
            focusRingOpacity: focusRingLayer.opacity,
            focusRingStroke: focusRingLayer.strokeColor,
            cornerRadius: fillLayer.cornerRadius,
            titleHidden: titleLayer.isHidden,
            hasIcon: iconSize != nil)
    }
}
#endif
