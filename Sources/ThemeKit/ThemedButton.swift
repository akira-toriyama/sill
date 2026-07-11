// ThemeKit — ThemedButton: a themed push button (MUI <Button>, basic). A
// faithful AppKit port of Material-UI v5's three button variants — `text`
// (bare, ink-only), `contained` (filled + elevation), `outlined` (stroked) —
// in three sizes (small / medium / large) and three colour roles (primary /
// secondary / error), themed by assigning a PaletteKit `ResolvedPalette`.
// AppKit / @MainActor.
//
// The family hand-rolls clickable controls today (facet's drawn buttons / popup
// rows); ThemeKit makes it ONE part. Subclasses `NSControl` for the real
// control contract — `isEnabled`, `target`/`action`, `sendAction`, key
// activation — alongside the sill-idiom `onTap` closure. The interaction 演出
// (hover / pressed / keyboard-focus / disabled) is REQUIRED and runs LIVE in
// `still`; `previewHovered` / `previewPressed` / `previewFocused` force a state
// for deterministic screenshots (the analogue of ThemedTextField's
// `previewFocused`).
//
// Drawing is PURE LAYER (no drawRect) so hover / press / elevation cross-fade
// cleanly. The contained variant's drop shadow lives on a SEPARATE, unclipped
// sibling layer with an explicit `shadowPath` — a `masksToBounds=true` layer
// (which the rounded fill needs, to clip its state-layer overlay child) erases
// its own shadow, the canonical Core-Animation gotcha. Contained ink is the
// best-contrast black/white computed on the ACTUAL role fill via Palette's pure
// WCAG helpers (the same path `onPrimary` uses, so it is correct for secondary
// / error fills too, not just primary). All transitions share the kit's house
// 0.16 s ease-out `layerTxn` timing — NOT MUI's 250 ms — for cross-widget
// consistency. Return activates via `performKeyEquivalent` (the window
// default-button path); Space activates the focused button via `keyDown`.

import AppKit
import Palette
import PaletteKit
import Motion

extension ThemedButton.Role {
    /// Bridge to the shared `ControlRole` so the role → colour selection lives in
    /// `ResolvedPalette.color(for:)`. Shared by ThemedButton AND ThemedButtonGroup
    /// (both key off this same `Role` enum).
    var control: ControlRole {
        switch self {
        case .primary:   return .primary
        case .secondary: return .secondary
        case .error:     return .error
        }
    }
}

@MainActor
public final class ThemedButton: ThemedControl {

    /// MUI variant. `text` = bare label, ink-only (the MUI default); `contained`
    /// = filled in the role colour with an elevation shadow; `outlined` = a
    /// stroked box, transparent fill.
    public enum Variant { case text, contained, outlined }

    /// MUI size — sets height / padding / font / icon size.
    public enum Size { case small, medium, large }

    /// Colour role. `primary` (the MUI default), `secondary`, or `error` (a
    /// destructive action). Maps to the matching `ResolvedPalette` role; ignored
    /// while disabled (MUI greys disabled buttons regardless of colour).
    public enum Role { case primary, secondary, error }

    /// Which edges of the outlined border to stroke — for ThemedButtonGroup
    /// seams (a grouped member drops its shared edge). Standalone = `.all`.
    public struct BorderEdges: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let top    = BorderEdges(rawValue: 1 << 0)
        public static let left   = BorderEdges(rawValue: 1 << 1)
        public static let bottom = BorderEdges(rawValue: 1 << 2)
        public static let right  = BorderEdges(rawValue: 1 << 3)
        public static let all: BorderEdges = [.top, .left, .bottom, .right]
    }

    // MARK: - Public configuration

    public var variant: Variant = .text   { didSet { applyTheme(); relayout() } }
    public var size:    Size    = .medium { didSet { applyTheme(); relayout() } }
    public var role:    Role    = .primary { didSet { applyTheme() } }

    /// The label. Drawn UPPERCASE with MUI's 0.4 pt tracking; the accessible
    /// name keeps the original case.
    public var title: String = "" { didSet { applyTheme(); relayout() } }

    /// Leading / trailing icon adornments (MUI startIcon / endIcon), tinted to the
    /// label colour. The string is a **Phosphor slug** (e.g. `"caret-right"`,
    /// `"magnifying-glass"`) resolved via `phosphorImage`; for a pre-resolved image
    /// (app icon / favicon / brand logo) use `leadingImage` / `trailingImage` below.
    public var leadingSymbol:  String? { didSet { applyTheme(); relayout() } }
    public var trailingSymbol: String? { didSet { applyTheme(); relayout() } }

    /// Pre-resolved leading / trailing image (wins over the matching `*Symbol`).
    /// The SVG entry point: pass `phosphorImage(…)` / `simpleIconImage(…)`, or any
    /// app icon / favicon / emoji bitmap. `isTemplate` ⇒ tinted to the label
    /// colour; else drawn raw (multi-colour).
    public var leadingImage:  NSImage? { didSet { applyTheme(); relayout() } }
    public var trailingImage: NSImage? { didSet { applyTheme(); relayout() } }

    /// Stretch to the host's width (MUI `fullWidth`) — content stays centred.
    /// `true` drops the intrinsic width so the host / Auto Layout sizes it.
    public var fullWidth = false { didSet { relayout() } }

    /// Tap handler (the sill-idiom convenience). Fires together with the
    /// `NSControl` `target`/`action`, on a mouse-up inside, Space, or the
    /// `keyEquivalent`.
    public var onTap: (() -> Void)?

    // MARK: - Grouping (ThemedButtonGroup composes these; defaults = standalone)

    /// Which corners get the corner radius; the rest are squared. Default = all
    /// four (a standalone button). A ButtonGroup member rounds only the group's
    /// OUTER corners and squares the shared-seam corners.
    public var roundedCorners: CACornerMask =
        [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner, .layerMinXMaxYCorner]
        { didSet { needsLayout = true } }

    /// Which edges of the outlined border to stroke. Default `.all` (a closed
    /// perimeter). A grouped non-last outlined member drops its shared (trailing)
    /// edge so two abutting strokes collapse to one hairline seam.
    public var drawnBorderEdges: BorderEdges = .all { didSet { needsLayout = true } }

    /// Forgo the button's own elevation so a GROUP can own one continuous shadow.
    /// Default false (a standalone contained button keeps its own shadow).
    public var groupedShadow = false { didSet { applyState(animated: false) } }

    // MARK: - Internals

    private let shadowLayer  = CALayer()          // contained elevation — UNCLIPPED, explicit shadowPath
    private let fillLayer    = CALayer()          // rounded fill (clips the overlay child)
    private let overlayLayer = CALayer()          // hover / press / focus state layer (child of fill)
    private let borderLayer  = CAShapeLayer()     // outlined stroke
    private let leadingIconLayer  = CALayer()
    private let trailingIconLayer = CALayer()
    private let titleLayer   = CATextLayer()

    /// Rendered icon point-sizes (nil ⇒ no icon) — drive layout + intrinsic width.
    private var leadingImageSize: CGSize?
    private var trailingImageSize: CGSize?

    // MARK: - Metrics (MUI v5 Button source values; heights rounded from MUI's
    //         fractional line-box to device-friendly integers, content centred)

    private struct Metrics {
        let height, hpad, radius, font, minWidth, border, iconPt, gap, outerAdj: CGFloat
    }
    private var metrics: Metrics {
        let h:      CGFloat = size.controlHeight
        let font:   CGFloat = size == .small ? 13 : size == .medium ? 14 : 15
        let iconPt: CGFloat = size == .small ? 18 : size == .medium ? 20 : 22
        // MUI's negative outer icon margin (−2 small / −4 otherwise) tucks an
        // icon toward the edge by eating into the horizontal padding.
        let outerAdj: CGFloat = size == .small ? -2 : -4
        let hpad: CGFloat
        switch (variant, size) {
        case (.text, .small):       hpad = 5
        case (.text, .medium):      hpad = 8
        case (.text, .large):       hpad = 11
        case (.contained, .small):  hpad = 10
        case (.contained, .medium): hpad = 16
        case (.contained, .large):  hpad = 22
        case (.outlined, .small):   hpad = 9    // 1 pt less than contained: absorbs the border
        case (.outlined, .medium):  hpad = 15
        case (.outlined, .large):   hpad = 21
        }
        return Metrics(height: h, hpad: hpad, radius: CGFloat(Radius.sm), font: font, minWidth: 64,
                       border: variant == .outlined ? 1 : 0,
                       iconPt: iconPt, gap: CGFloat(Space.md), outerAdj: outerAdj)
    }

    public override var intrinsicContentSize: NSSize {
        let m = metrics
        if fullWidth { return NSSize(width: NSView.noIntrinsicMetric, height: m.height) }
        let leadW  = leadingImageSize?.width ?? 0
        let trailW = trailingImageSize?.width ?? 0
        let titleW = title.isEmpty ? 0 : titleLayer.bounds.width
        let present = [leadW > 0, titleW > 0, trailW > 0].filter { $0 }.count
        let gaps = CGFloat(max(0, present - 1)) * m.gap
        let leftPad  = m.hpad + (leadingImageSize  != nil ? m.outerAdj : 0)
        let rightPad = m.hpad + (trailingImageSize != nil ? m.outerAdj : 0)
        let content = leftPad + leadW + titleW + trailW + gaps + rightPad
        return NSSize(width: max(m.minWidth, ceil(content)), height: m.height)
    }

    // MARK: - Init

    public override init(palette: ResolvedPalette) {
        super.init(palette: palette)
        let s = themeBackingScale

        // Shadow (bottom) — never clipped, explicit rounded silhouette.
        shadowLayer.configureShadowLayer(scale: s)
        layer?.addSublayer(shadowLayer)

        // Fill clips the overlay child to the rounded rect.
        fillLayer.masksToBounds = true
        fillLayer.contentsScale = s
        layer?.addSublayer(fillLayer)
        overlayLayer.contentsScale = s
        fillLayer.addSublayer(overlayLayer)

        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.contentsScale = s
        layer?.addSublayer(borderLayer)

        for icon in [leadingIconLayer, trailingIconLayer] {
            icon.contentsGravity = .resizeAspect
            icon.contentsScale = s
            icon.isHidden = true
            layer?.addSublayer(icon)
        }

        titleLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        titleLayer.configureThemedLabel(scale: s, alignment: .center)
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

    /// Label + icon ink for the current state.
    private var titleColor: NSColor {
        guard isEnabled else { return palette.muted }
        switch variant {
        case .contained:        return palette.bestContrast(on: roleColor)
        case .text, .outlined:  return roleColor
        }
    }

    /// The stable fill (snapped; never animated on hover — the darken is the
    /// overlay). Contained = role fill / disabled neutral wash; others clear.
    private var baseFillColor: NSColor {
        switch variant {
        case .contained:        return isEnabled ? roleColor : palette.ink(.subtle, of: .muted)
        case .text, .outlined:  return .clear
        }
    }

    /// The hover / press / focus state layer (animated). For contained it is the
    /// contrast ink (darkens a light fill, lightens a dark fill — theme-robust,
    /// MUI's "darker shade" expressed as a Material-3 on-colour overlay); for
    /// text / outlined it is the role colour at MUI's hover / active alpha band.
    private var overlayColor: NSColor {
        guard isEnabled else { return .clear }
        switch variant {
        case .contained:
            let on = palette.bestContrast(on: roleColor)
            if fxPressed { return on.withAlphaComponent(0.12) }
            if fxHovered { return on.withAlphaComponent(0.08) }
            return .clear
        case .text, .outlined:
            if fxPressed            { return roleColor.withAlphaComponent(0.16) }   // ≈ subtle tier
            if fxHovered || fxFocused { return roleColor.withAlphaComponent(0.06) } // ≈ faint tier / MUI hover
            return .clear
        }
    }

    /// Outlined stroke: resting role@0.5 (MUI), full role on interaction,
    /// neutral `border` when disabled.
    private var borderColor: NSColor {
        guard variant == .outlined else { return .clear }
        if !isEnabled { return palette.border }
        if fxHovered || fxPressed || fxFocused { return roleColor }
        return roleColor.withAlphaComponent(0.5)
    }

    /// Contained elevation per state (the #13 dp ladder: rest dp2 → hover dp4 →
    /// focus dp6 → press dp8); flat otherwise. Order pressed → focused → hovered
    /// so adding an interaction never LOWERS the shadow (focus dp6 sits above
    /// hover dp4; hovering a focused button must not dip to dp4).
    private var elevation: (opacity: Float, radius: CGFloat, offsetY: CGFloat) {
        guard variant == .contained, isEnabled else { return palette.shadow(.flat) }
        if fxPressed { return palette.shadow(.dp8) }
        if fxFocused { return palette.shadow(.dp6) }
        if fxHovered { return palette.shadow(.dp4) }
        return palette.shadow(.dp2)
    }

    // MARK: - Base hook overrides

    override func applyThemeSnap() {
        fillLayer.backgroundColor = baseFillColor.cgColor
        borderLayer.isHidden = (variant != .outlined)
        borderLayer.lineWidth = metrics.border
        shadowLayer.isHidden = (variant != .contained)
    }

    override func rebuildContent() {
        rebuildTitle()
        rebuildIcons()
    }

    override func syncAccessibility() {
        setAccessibilityLabel(title.isEmpty ? nil : title)
        setAccessibilityEnabled(isEnabled)
    }

    override func applyInteractionState() {
        overlayLayer.backgroundColor = overlayColor.cgColor
        borderLayer.strokeColor = borderColor.cgColor
        let e = elevation
        shadowLayer.applyShadowSpec((opacity: groupedShadow ? 0 : e.opacity, radius: e.radius, offsetY: e.offsetY))
    }

    /// Push the uppercased, tracked title into the text layer (snapped, sized to
    /// the text — a CATextLayer renders nothing with zero bounds).
    private func rebuildTitle() {
        let f = palette.uiFont(metrics.font, .medium)
        let s = title.uppercased()
        let attr = NSAttributedString(string: s, attributes: [
            .font: f, .kern: 0.4, .foregroundColor: titleColor])
        let sz = attr.size()
        layerTxn(animated: false) {
            self.titleLayer.string = s.isEmpty ? nil : attr
            self.titleLayer.foregroundColor = self.titleColor.cgColor
            self.titleLayer.isHidden = s.isEmpty
            self.titleLayer.bounds = CGRect(x: 0, y: 0,
                                            width: ceil(sz.width) + 2, height: ceil(sz.height))
        }
    }

    private func rebuildIcons() {
        let scale = themeBackingScale, pt = metrics.iconPt, tint = titleColor
        leadingImageSize  = applyIconSlot(leadingIconLayer,  symbol: leadingSymbol,
                                          image: leadingImage,  pt: pt, tint: tint, scale: scale)
        trailingImageSize = applyIconSlot(trailingIconLayer, symbol: trailingSymbol,
                                          image: trailingImage, pt: pt, tint: tint, scale: scale)
    }

    // MARK: - Corner-aware paths (standalone = a plain rounded rect; a grouped
    //         member squares the seam corners and drops the shared edge)

    /// A CLOSED rounded-rect path rounding only `corners` (the rest squared).
    /// Byte-identical to `CGPath(roundedRect:)` when all four corners are set, so
    /// the standalone button's shadow / focus ring are unchanged.
    private func closedCornerPath(_ rect: CGRect, radius: CGFloat,
                                  corners: CACornerMask) -> CGPath {
        if corners == Self.allCorners {
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        let r = min(radius, min(rect.width, rect.height) / 2)
        let bl = CGPoint(x: rect.minX, y: rect.minY), br = CGPoint(x: rect.maxX, y: rect.minY)
        let tr = CGPoint(x: rect.maxX, y: rect.maxY), tl = CGPoint(x: rect.minX, y: rect.maxY)
        func rad(_ c: CACornerMask) -> CGFloat { corners.contains(c) ? r : 0 }
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addArc(tangent1End: br, tangent2End: tr, radius: rad(.layerMaxXMinYCorner))
        p.addArc(tangent1End: tr, tangent2End: tl, radius: rad(.layerMaxXMaxYCorner))
        p.addArc(tangent1End: tl, tangent2End: bl, radius: rad(.layerMinXMaxYCorner))
        p.addArc(tangent1End: bl, tangent2End: br, radius: rad(.layerMinXMinYCorner))
        p.closeSubpath()
        return p
    }

    /// The outlined border path: a closed perimeter when `edges == .all`, else an
    /// OPEN path that strokes only the present edges (a grouped member drops its
    /// shared seam edge). Only the two seam configs the group produces — gap on
    /// the trailing edge (`.right` horizontal / `.bottom` vertical) — are handled;
    /// anything else falls back to the closed path.
    private func borderPath(_ rect: CGRect, radius: CGFloat,
                            corners: CACornerMask, edges: BorderEdges) -> CGPath {
        if edges == .all { return closedCornerPath(rect, radius: radius, corners: corners) }
        let r = min(radius, min(rect.width, rect.height) / 2)
        let bl = CGPoint(x: rect.minX, y: rect.minY), br = CGPoint(x: rect.maxX, y: rect.minY)
        let tr = CGPoint(x: rect.maxX, y: rect.maxY), tl = CGPoint(x: rect.minX, y: rect.maxY)
        func rad(_ c: CACornerMask) -> CGFloat { corners.contains(c) ? r : 0 }
        let p = CGMutablePath()
        if !edges.contains(.right) {        // horizontal seam: open on the right
            p.move(to: tr)                  // TR (square endpoint) → top → TL → left → BL → bottom → BR
            p.addArc(tangent1End: tl, tangent2End: bl, radius: rad(.layerMinXMaxYCorner))
            p.addArc(tangent1End: bl, tangent2End: br, radius: rad(.layerMinXMinYCorner))
            p.addLine(to: br)
        } else if !edges.contains(.bottom) { // vertical seam: open on the bottom
            p.move(to: br)                  // BR → right → TR → top → TL → left → BL
            p.addArc(tangent1End: tr, tangent2End: tl, radius: rad(.layerMaxXMaxYCorner))
            p.addArc(tangent1End: tl, tangent2End: bl, radius: rad(.layerMinXMaxYCorner))
            p.addLine(to: bl)
        } else {
            return closedCornerPath(rect, radius: radius, corners: corners)
        }
        return p
    }

    // MARK: - Layout hooks

    override func positionLayers(in bounds: CGRect, local: CGRect) {
        let m = metrics
        let b = bounds
        shadowLayer.frame = b
        shadowLayer.shadowPath = closedCornerPath(local, radius: m.radius, corners: roundedCorners)
        fillLayer.frame = b
        fillLayer.cornerRadius = m.radius
        fillLayer.maskedCorners = roundedCorners
        overlayLayer.frame = local
        overlayLayer.cornerRadius = m.radius
        overlayLayer.maskedCorners = roundedCorners
        borderLayer.frame = b
        let inset = m.border / 2
        borderLayer.path = borderPath(local.insetBy(dx: inset, dy: inset),
            radius: m.radius, corners: roundedCorners, edges: drawnBorderEdges)
        layoutContent(in: b, m: m)
    }

    override func focusRingPath(in rect: CGRect) -> CGPath {
        closedCornerPath(rect.insetBy(dx: -focusRingOutset, dy: -focusRingOutset),
                         radius: metrics.radius + focusRingOutset,
                         corners: roundedCorners)
    }

    /// Centre the leading-icon / title / trailing-icon row, with `gap` between
    /// consecutive present pieces.
    private func layoutContent(in b: NSRect, m: Metrics) {
        var segs: [(CALayer, CGSize, Bool)] = []   // (layer, size, isTitle)
        if let sz = leadingImageSize  { segs.append((leadingIconLayer, sz, false)) }
        if !title.isEmpty             { segs.append((titleLayer, titleLayer.bounds.size, true)) }
        if let sz = trailingImageSize { segs.append((trailingIconLayer, sz, false)) }

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
        for l in [shadowLayer, fillLayer, overlayLayer, leadingIconLayer, trailingIconLayer] { l.contentsScale = s }
        titleLayer.contentsScale = s
        borderLayer.contentsScale = s
        rebuildIcons()
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
// assert the per-variant / per-state colours WITHOUT synthetic events (use the
// `preview…` overrides to drive the state). Same-file extension so it can read
// the private layers; not built into release.
extension ThemedButton {
    struct ButtonProbe {
        public let titleColor: CGColor?
        public let fillColor: CGColor?
        public let overlayColor: CGColor?
        public let borderColor: CGColor?
        public let borderVisible: Bool
        public let shadowOpacity: Float
        public let focusRingOpacity: Float
        public let height: CGFloat
        public let hasLeadingIcon: Bool
        public let hasTrailingIcon: Bool
        // Grouping geometry (ThemedButtonGroup)
        public let maskedCorners: CACornerMask
        public let drawnBorderEdges: BorderEdges
        public let groupedShadow: Bool
        public let borderPathBounds: CGRect
    }
    var buttonProbe: ButtonProbe {
        ButtonProbe(
            titleColor: titleLayer.foregroundColor,
            fillColor: fillLayer.backgroundColor,
            overlayColor: overlayLayer.backgroundColor,
            borderColor: borderLayer.strokeColor,
            borderVisible: !borderLayer.isHidden,
            shadowOpacity: shadowLayer.shadowOpacity,
            focusRingOpacity: focusRingLayer.opacity,
            height: metrics.height,
            hasLeadingIcon: leadingImageSize != nil,
            hasTrailingIcon: trailingImageSize != nil,
            maskedCorners: fillLayer.maskedCorners,
            drawnBorderEdges: drawnBorderEdges,
            groupedShadow: groupedShadow,
            borderPathBounds: borderLayer.path?.boundingBoxOfPath ?? .null)
    }
}
#endif
