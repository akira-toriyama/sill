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

@MainActor
public final class ThemedButton: NSControl {

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

    /// The theme. Assigning re-themes the whole button.
    public var palette: ResolvedPalette { didSet { applyTheme() } }

    public var variant: Variant = .text   { didSet { applyTheme(); relayout() } }
    public var size:    Size    = .medium { didSet { applyTheme(); relayout() } }
    public var role:    Role    = .primary { didSet { applyTheme() } }

    /// The label. Drawn UPPERCASE with MUI's 0.4 pt tracking; the accessible
    /// name keeps the original case.
    public var title: String = "" { didSet { applyTheme(); relayout() } }

    /// Leading / trailing SF-Symbol adornments (MUI startIcon / endIcon), tinted
    /// to the label colour.
    public var leadingSymbol:  String? { didSet { applyTheme(); relayout() } }
    public var trailingSymbol: String? { didSet { applyTheme(); relayout() } }

    /// Stretch to the host's width (MUI `fullWidth`) — content stays centred.
    /// `true` drops the intrinsic width so the host / Auto Layout sizes it.
    public var fullWidth = false { didSet { relayout() } }

    /// Tap handler (the sill-idiom convenience). Fires together with the
    /// `NSControl` `target`/`action`, on a mouse-up inside, Space, or the
    /// `keyEquivalent`.
    public var onTap: (() -> Void)?

    /// Optional key equivalent (MUI has none; AppKit dialogs want a default
    /// button). Set to `"\r"` to make this the Return-activated default button.
    /// Matched in `performKeyEquivalent` against `keyEquivalentModifierMask`.
    public var keyEquivalent: String = ""
    public var keyEquivalentModifierMask: NSEvent.ModifierFlags = []

    /// Force the hovered / pressed / focused APPEARANCE without real events —
    /// for previews / screenshots only (the bench shows the LIVE 演出; these
    /// make a static capture deterministic). Disabled buttons ignore them.
    public var previewHovered = false { didSet { applyState(animated: false) } }
    public var previewPressed = false { didSet { applyState(animated: false) } }
    public var previewFocused = false { didSet { applyState(animated: false) } }

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

    // MARK: - NSControl overrides (custom storage — a cell-less NSControl must
    //         NOT lean on the cell-backed isEnabled / target / action).

    private var _enabled = true
    public override var isEnabled: Bool {
        get { _enabled }
        set {
            guard _enabled != newValue else { return }
            _enabled = newValue
            // Actively clear any in-flight hover / press — a disable can strand
            // them with no matching exit / up event (the stuck-hover gotcha).
            if !newValue {
                isHovered = false; isPressed = false
                if window?.firstResponder === self { window?.makeFirstResponder(nil) }
            }
            applyTheme()
        }
    }

    private weak var _target: AnyObject?
    private var _action: Selector?
    public override var target: AnyObject? { get { _target } set { _target = newValue } }
    public override var action: Selector?  { get { _action } set { _action = newValue } }

    // MARK: - Internals

    private let shadowLayer  = CALayer()          // contained elevation — UNCLIPPED, explicit shadowPath
    private let fillLayer    = CALayer()          // rounded fill (clips the overlay child)
    private let overlayLayer = CALayer()          // hover / press / focus state layer (child of fill)
    private let borderLayer  = CAShapeLayer()     // outlined stroke
    private let leadingIconLayer  = CALayer()
    private let trailingIconLayer = CALayer()
    private let titleLayer   = CATextLayer()
    private let focusRingLayer = CAShapeLayer()   // themed keyboard-focus ring (top, unclipped)

    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false
    private var isKeyFocused = false
    private var isFlashing = false   // a keyboard-flash activation is in flight

    /// Rendered icon point-sizes (nil ⇒ no icon) — drive layout + intrinsic width.
    private var leadingImageSize: CGSize?
    private var trailingImageSize: CGSize?

    public override var isFlipped: Bool { false }   // y-up: a downward shadow is −y

    // MARK: - Metrics (MUI v5 Button source values; heights rounded from MUI's
    //         fractional line-box to device-friendly integers, content centred)

    private struct Metrics {
        let height, hpad, radius, font, minWidth, border, iconPt, gap, outerAdj: CGFloat
    }
    private var metrics: Metrics {
        let h:      CGFloat = size == .small ? 30 : size == .medium ? 36 : 42
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
        return Metrics(height: h, hpad: hpad, radius: 4, font: font, minWidth: 64,
                       border: variant == .outlined ? 1 : 0,
                       iconPt: iconPt, gap: 8, outerAdj: outerAdj)
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

    public init(palette: ResolvedPalette) {
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false        // the focus ring / shadow live outside bounds
        focusRingType = .none               // we draw our own themed ring

        let s = backingScale

        // Shadow (bottom) — never clipped, explicit rounded silhouette.
        shadowLayer.masksToBounds = false
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.contentsScale = s
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
        titleLayer.contentsScale = s
        titleLayer.alignmentMode = .center
        titleLayer.truncationMode = .end
        titleLayer.isWrapped = false
        layer?.addSublayer(titleLayer)

        focusRingLayer.fillColor = NSColor.clear.cgColor
        focusRingLayer.lineWidth = 2
        focusRingLayer.opacity = 0
        focusRingLayer.contentsScale = s
        layer?.addSublayer(focusRingLayer)

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

    private func themedFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        switch palette.font {
        case .mono: return .monospacedSystemFont(ofSize: size, weight: weight)
        default:    return .systemFont(ofSize: size, weight: weight)
        }
    }

    private var roleColor: NSColor {
        switch role {
        case .primary:   return palette.primary
        case .secondary: return palette.secondary
        case .error:     return palette.error
        }
    }

    /// Black or white, whichever best contrasts a fill — the same WCAG
    /// crossover `PaletteKit.onPrimary` uses (shared pure Palette helpers, so a
    /// secondary / error fill gets correct ink, not just primary).
    private func ink(on c: NSColor) -> NSColor {
        let s = c.usingColorSpace(.sRGB) ?? c
        let l = wcagRelativeLuminance(r: Double(s.redComponent),
                                      g: Double(s.greenComponent),
                                      b: Double(s.blueComponent))
        return prefersBlackForeground(fillRelLuminance: l) ? .black : .white
    }

    /// Label + icon ink for the current state.
    private var titleColor: NSColor {
        guard isEnabled else { return palette.muted }
        switch variant {
        case .contained:        return ink(on: roleColor)
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

    private var fxHovered: Bool { (isHovered || previewHovered) && isEnabled }
    private var fxPressed: Bool { (isPressed || previewPressed) && isEnabled }
    private var fxFocused: Bool { (isKeyFocused || previewFocused) && isEnabled }

    /// The hover / press / focus state layer (animated). For contained it is the
    /// contrast ink (darkens a light fill, lightens a dark fill — theme-robust,
    /// MUI's "darker shade" expressed as a Material-3 on-colour overlay); for
    /// text / outlined it is the role colour at MUI's hover / active alpha band.
    private var overlayColor: NSColor {
        guard isEnabled else { return .clear }
        switch variant {
        case .contained:
            let on = ink(on: roleColor)
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

    private struct Elevation { let opacity: Float; let radius: CGFloat; let offsetY: CGFloat }
    /// Contained elevation per state (≈ MUI dp 2 / 4 / 6 / 8); flat otherwise.
    /// Order pressed → focused → hovered so adding an interaction never LOWERS
    /// the shadow (MUI's focus dp6 sits above hover dp4; hovering a focused
    /// button must not dip to dp4).
    private var elevation: Elevation {
        guard variant == .contained, isEnabled else { return Elevation(opacity: 0, radius: 0, offsetY: 0) }
        if fxPressed { return Elevation(opacity: 0.28, radius: 8, offsetY: -3) }
        if fxFocused { return Elevation(opacity: 0.26, radius: 6, offsetY: -2) }
        if fxHovered { return Elevation(opacity: 0.24, radius: 5, offsetY: -2) }
        return Elevation(opacity: 0.20, radius: 3, offsetY: -1)
    }

    private var showFocusRing: Bool { fxFocused }

    /// Re-theme: snaps the STABLE visuals (fill / title / icons / structure),
    /// then settles the state layer. Snapping (not cross-fading) matches the
    /// other widgets — a theme switch shouldn't smear, and these sublayers have
    /// no action-disabling delegate.
    public func applyTheme() {
        layerTxn(animated: false) {
            self.fillLayer.backgroundColor = self.baseFillColor.cgColor
            self.borderLayer.isHidden = (self.variant != .outlined)
            self.borderLayer.lineWidth = self.metrics.border
            self.shadowLayer.isHidden = (self.variant != .contained)
            self.focusRingLayer.strokeColor = self.palette.primary.cgColor
        }
        rebuildTitle()
        rebuildIcons()
        syncAccessibility()
        applyState(animated: false)
        needsLayout = true
    }

    /// The interaction-driven layer props — animated on a real hover / press /
    /// focus change, snapped from `applyTheme` / previews / layout.
    private func applyState(animated: Bool) {
        layerTxn(animated: animated) {
            self.overlayLayer.backgroundColor = self.overlayColor.cgColor
            self.borderLayer.strokeColor = self.borderColor.cgColor
            let e = self.elevation
            // A grouped member forgoes its own shadow — the group owns one.
            self.shadowLayer.shadowOpacity = self.groupedShadow ? 0 : e.opacity
            self.shadowLayer.shadowRadius  = e.radius
            self.shadowLayer.shadowOffset  = CGSize(width: 0, height: e.offsetY)
            self.focusRingLayer.opacity = self.showFocusRing ? 1 : 0
        }
    }

    private func syncAccessibility() {
        setAccessibilityLabel(title.isEmpty ? nil : title)   // original case for VoiceOver
        setAccessibilityEnabled(isEnabled)
    }

    /// Push the uppercased, tracked title into the text layer (snapped, sized to
    /// the text — a CATextLayer renders nothing with zero bounds).
    private func rebuildTitle() {
        let f = themedFont(metrics.font, .medium)
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
        let scale = backingScale, pt = metrics.iconPt, tint = titleColor
        leadingImageSize  = applyIcon(leadingIconLayer,  symbol: leadingSymbol,  pt: pt, tint: tint, scale: scale)
        trailingImageSize = applyIcon(trailingIconLayer, symbol: trailingSymbol, pt: pt, tint: tint, scale: scale)
    }

    @discardableResult
    private func applyIcon(_ iconLayer: CALayer, symbol: String?, pt: CGFloat,
                           tint: NSColor, scale: CGFloat) -> CGSize? {
        guard let name = symbol, let (img, sz) = tintedSymbol(name, pt: pt, color: tint, scale: scale) else {
            layerTxn(animated: false) { iconLayer.contents = nil; iconLayer.isHidden = true }
            return nil
        }
        layerTxn(animated: false) {
            iconLayer.contents = img
            iconLayer.contentsScale = scale
            iconLayer.isHidden = false
        }
        return sz
    }

    /// Rasterize an SF Symbol AT THE BACKING SCALE and template-tint it (the
    /// ThemedTextField fill recipe, but into a device-pixel bitmap). Setting
    /// `contentsScale` alone leaves a vector symbol's 1× CGImage blurry on
    /// Retina — the bitmap must be sized in device pixels. Returns the POINT
    /// size for layout.
    private func tintedSymbol(_ name: String, pt: CGFloat, color: NSColor,
                              scale: CGFloat) -> (CGImage, CGSize)? {
        let cfg = NSImage.SymbolConfiguration(pointSize: pt, weight: .medium)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return nil }
        let sizePt = base.size
        let pxW = max(1, Int((sizePt.width  * scale).rounded()))
        let pxH = max(1, Int((sizePt.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = sizePt
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let r = NSRect(origin: .zero, size: sizePt)
        base.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
        color.set()
        r.fill(using: .sourceIn)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = rep.cgImage else { return nil }
        return (cg, sizePt)
    }

    // MARK: - Corner-aware paths (standalone = a plain rounded rect; a grouped
    //         member squares the seam corners and drops the shared edge)

    private static let allCorners: CACornerMask =
        [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner, .layerMinXMaxYCorner]

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

    // MARK: - Layout

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    public override func layout() {
        super.layout()
        let m = metrics
        layerTxn(animated: false) {
            let b = self.bounds
            let local = CGRect(origin: .zero, size: b.size)

            self.shadowLayer.frame = b
            self.shadowLayer.shadowPath = self.closedCornerPath(local, radius: m.radius,
                corners: self.roundedCorners)

            self.fillLayer.frame = b
            self.fillLayer.cornerRadius = m.radius
            self.fillLayer.maskedCorners = self.roundedCorners
            self.overlayLayer.frame = local
            self.overlayLayer.cornerRadius = m.radius
            self.overlayLayer.maskedCorners = self.roundedCorners

            self.borderLayer.frame = b
            let inset = m.border / 2
            self.borderLayer.path = self.borderPath(local.insetBy(dx: inset, dy: inset),
                radius: m.radius, corners: self.roundedCorners, edges: self.drawnBorderEdges)

            self.focusRingLayer.frame = b
            self.focusRingLayer.path = self.closedCornerPath(local.insetBy(dx: -2, dy: -2),
                radius: m.radius + 2, corners: self.roundedCorners)

            self.layoutContent(in: b, m: m)
        }
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

    /// Keep text / strokes / symbols crisp across a display-scale change —
    /// `contentsScale` was captured once at init (before a window), and the
    /// rasterized symbol bitmaps must be re-rendered at the new scale.
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = backingScale
        for l in [shadowLayer, fillLayer, overlayLayer, leadingIconLayer,
                  trailingIconLayer] { l.contentsScale = s }
        titleLayer.contentsScale = s
        borderLayer.contentsScale = s
        focusRingLayer.contentsScale = s
        rebuildIcons()      // re-rasterize at the new device scale
        needsLayout = true
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

    // MARK: - Hover (tracking area)

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t); trackingArea = nil }
        let t = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
        // A geometry change can move the view out from under a stationary
        // pointer with no exit event — clear a now-false hover.
        if isHovered, let w = window {
            let local = convert(w.mouseLocationOutsideOfEventStream, from: nil)
            if !bounds.contains(local) { isHovered = false; applyState(animated: false) }
        }
    }

    public override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovered = true; applyState(animated: true)
    }
    public override func mouseExited(with event: NSEvent) {
        guard isHovered else { return }
        isHovered = false; applyState(animated: true)
    }

    // MARK: - Press (mouseDown/Dragged/Up trio — keeps the run loop turning so
    //         the overlay / elevation animate during the press)

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isEnabled }

    // A click presses + activates but deliberately does NOT take first
    // responder — standard macOS push-button behaviour (keyboard focus + the
    // themed ring arrive via Tab; Return via performKeyEquivalent). Diverges
    // from ThemedTextField.mouseDown, which DOES focus its field, on purpose.
    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true; applyState(animated: true)
    }
    public override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != isPressed { isPressed = inside; applyState(animated: true) }
    }
    public override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if isPressed { isPressed = false; applyState(animated: true) }
        if inside { activate() }
    }

    // MARK: - Keyboard + focus

    public override var acceptsFirstResponder: Bool { isEnabled }

    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { isKeyFocused = true; applyState(animated: true) }
        return ok
    }
    public override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { isKeyFocused = false; applyState(animated: true) }
        return ok
    }

    public override func keyDown(with event: NSEvent) {
        if isEnabled, event.keyCode == 49 {   // Space activates the focused button
            // Activate once per press; swallow auto-repeat (a held Space must
            // not re-fire) — consume the repeat too, so it doesn't beep.
            if !event.isARepeat { flashAndActivate() }
            return
        }
        super.keyDown(with: event)
    }

    /// Return / a set key equivalent activates via the window's default-button
    /// path (delivered BEFORE keyDown, regardless of first responder).
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard isEnabled, !keyEquivalent.isEmpty,
              event.charactersIgnoringModifiers == keyEquivalent,
              mods == keyEquivalentModifierMask else {
            return super.performKeyEquivalent(with: event)
        }
        flashAndActivate()
        return true
    }

    /// A brief visible press before firing — keyboard activation has no natural
    /// down/up, so synthesize the flash. The `isFlashing` guard makes a single
    /// flash atomic: a second Space/Return arriving inside the 0.12 s window is
    /// dropped (no double-fire), and the deferred block re-checks `isEnabled`
    /// (via `activate`) so an async disable mid-flash cancels the activation.
    private func flashAndActivate() {
        guard !isFlashing else { return }
        isFlashing = true
        isPressed = true; applyState(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            self.isFlashing = false
            self.isPressed = false; self.applyState(animated: true)
            self.activate()
        }
    }

    private func activate() {
        guard isEnabled else { return }   // authoritative even against an in-flight flash
        onTap?()
        if let a = _action { NSApp.sendAction(a, to: _target, from: self) }
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
