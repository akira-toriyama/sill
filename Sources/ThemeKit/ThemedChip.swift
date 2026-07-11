// ThemeKit — ThemedChip: a compact themed token (MUI <Chip> fused with HTML
// <kbd>), themed by assigning a PaletteKit `ResolvedPalette`. AppKit / @MainActor.
// sill v1.10.0, docs/ROADMAP.md #3.
//
// ONE part for three things the family would otherwise hand-draw: a TAG (facet's
// tag pills — clickable to filter, deletable), a STATUS pill, and a KEYCAP (the
// `⌘⇧N` shortcut glyphs perch builds as bare strings today). The first two are
// MUI <Chip>; the keycap is <kbd> — a mono, key-shaped variant. perch's hint
// OVERLAY is deliberately OUT of scope: it draws N pills in a tight CG loop with
// bespoke appear/winning/miss animation, which an NSView-per-chip cannot serve.
//
//   variant  .filled (default) · .outlined · .keycap
//   size     .small (24h) · .medium (32h)            — MUI Chip has no `large`
//   role     .neutral (default) · .primary · .secondary · .error
//
// Interaction is OPT-IN, MUI-style: `onTap` ⇒ clickable (hover / press / focus /
// Space), `onDelete` ⇒ a trailing × (Phosphor `x-circle`, matching ThemedComboBox's
// clear glyph; Backspace/Delete also fires it while focused), `isSelected` ⇒ the
// canonical `selection` fill. A chip with none of these is fully static (a keycap,
// a display tag). Like ThemedButton the LIVE 演出 runs in `prism`; the
// `preview…` overrides force a state for a deterministic screenshot.
//
// Drawing is PURE LAYER (no drawRect) so the state layer cross-fades cleanly.
// Unlike ThemedButton there is NO elevation (MUI chips are flat) and NO group
// seam machinery; the border is the fill layer's own stroke (chips never abut).
// The pill corner is height/2; the keycap is a 5 pt key. All transitions share
// the kit's house 0.16 s ease-out timing.

import AppKit
import Palette
import PaletteKit
import Motion

extension ThemedChip.Role {
    /// Bridge to the shared `ControlRole`. `neutral` ⇒ `color(for: .neutral)` =
    /// `foreground`, matching the chip's prior direct `palette.foreground`.
    var control: ControlRole {
        switch self {
        case .neutral:   return .neutral
        case .primary:   return .primary
        case .secondary: return .secondary
        case .error:     return .error
        }
    }
}

public final class ThemedChip: ThemedControl {

    /// Visual style. `filled` = MUI's default chip (a calm `muted` wash for
    /// `neutral`, an opaque role fill otherwise); `outlined` = a stroked, clear
    /// box; `keycap` = a mono, key-shaped `<kbd>` (role is ignored — keys are
    /// always neutral).
    public enum Variant { case filled, outlined, keycap }

    /// MUI chip size — sets height / padding / font / icon size. There is no
    /// `large`: MUI's <Chip> ships only small (24) and medium (32).
    public enum Size { case small, medium }

    /// Colour role. `neutral` (the MUI default `color="default"`, a calm grey),
    /// `primary`, `secondary`, or `error`. `keycap` ignores it.
    public enum Role { case neutral, primary, secondary, error }

    // MARK: - Public configuration

    public var variant: Variant = .filled  { didSet { applyTheme(); relayout() } }
    public var size:    Size    = .medium  { didSet { applyTheme(); relayout() } }
    public var role:    Role    = .neutral { didSet { applyTheme() } }

    /// The label. Drawn AS-IS (chips are not uppercased, unlike ThemedButton);
    /// for a keycap this is the glyph run, e.g. `"⇧⌘N"`.
    public var title: String = "" { didSet { applyTheme(); relayout() } }

    /// Leading icon (MUI chip `icon` / `avatar`), tinted to the label colour. The
    /// string is a **Phosphor slug** resolved via `phosphorImage`; for a
    /// pre-resolved image (app icon / favicon / brand logo) use `leadingImage`,
    /// which wins. There is no trailing icon slot — the trailing end is the
    /// delete affordance (`onDelete`), MUI-style.
    public var leadingSymbol: String? { didSet { applyTheme(); relayout() } }
    public var leadingImage:  NSImage? { didSet { applyTheme(); relayout() } }

    /// Selected (a filter chip that is ON). Paints the canonical `selection`
    /// wash (`neutral`) / a role wash (otherwise). Independent of `onTap`.
    public var isSelected: Bool = false { didSet { applyTheme() } }

    /// Tap handler. Non-nil ⇒ the chip is CLICKABLE: it gains hover / press /
    /// keyboard focus + the themed ring, and activates on a click in the body
    /// (not the ×), Space, or `sendAction`. Nil ⇒ a static chip.
    public var onTap: (() -> Void)? { didSet { invalidateInteraction() } }

    /// Delete handler. Non-nil ⇒ a trailing × (Phosphor `x-circle`) appears; it
    /// has its own hover, fires on a click on the ×, and on Backspace / Delete
    /// while the chip is focused. Nil ⇒ no ×.
    public var onDelete: (() -> Void)? {
        didSet {
            applyTheme(); relayout()
            if !isInteractive, window?.firstResponder === self { window?.makeFirstResponder(nil) }
        }
    }

    // MARK: - Internals

    private let fillLayer     = CALayer()       // rounded fill (clips the overlay child) + own border
    private let overlayLayer  = CALayer()       // hover / press state layer (child of fill)
    private let leadingIconLayer = CALayer()
    private let titleLayer    = CATextLayer()
    private let deleteIconLayer  = CALayer()    // the trailing × (own hover tint)

    private var isDeleteHovered = false

    /// What a mouse-down armed, so mouse-up routes to the right action.
    private enum PressTarget { case none, body, delete }
    private var pressTarget: PressTarget = .none
    /// Whether the pointer is still over the armed target (gates the press visual;
    /// a drag off cancels it, a drag back re-arms — mouse-up only fires inside).
    private var pressArmed = false

    /// Rendered icon point-sizes (nil ⇒ absent) — drive layout + intrinsic width.
    private var leadingImageSize: CGSize?
    private var deleteImageSize: CGSize?
    /// The × frame (expanded) for hit-testing, in view coords. Set in `layout`.
    private var deleteHitRect: CGRect = .null

    private var isClickable: Bool { onTap != nil && isEnabled }
    private var isDeletable: Bool { onDelete != nil }
    /// Focusable when EITHER affordance is live: a clickable body OR a deletable ×
    /// (so Backspace / Delete can reach a delete-only chip). Drives the focus ring
    /// + first-responder; the body state-layer stays clickable-only.
    private var isInteractive: Bool { isEnabled && (onTap != nil || onDelete != nil) }

    // MARK: - Metrics (MUI v5 Chip source values; small 24 / medium 32)

    private struct Metrics {
        let height, hpad, radius, font, iconPt, gap, minWidth, border, outerAdj: CGFloat
    }
    private var metrics: Metrics {
        let small = size == .small
        let h:      CGFloat = small ? 24 : 32
        let font:   CGFloat = 13
        let iconPt: CGFloat = small ? 14 : 16
        // Tuck a leading icon / × toward the edge by eating into the padding (MUI).
        let outerAdj: CGFloat = -2
        let hpad: CGFloat
        switch variant {
        case .keycap:            hpad = small ? 6 : 8
        case .filled, .outlined: hpad = small ? 8 : 12
        }
        let radius: CGFloat = variant == .keycap ? CGFloat(Radius.sm) : h / 2   // pill, except the key
        let minWidth: CGFloat = variant == .keycap ? h : 0     // a 1-glyph key is square
        let border: CGFloat = (variant == .outlined || variant == .keycap) ? 1 : 0
        return Metrics(height: h, hpad: hpad, radius: radius, font: font,
                       iconPt: iconPt, gap: 5, minWidth: minWidth,
                       border: border, outerAdj: outerAdj)
    }

    public override var intrinsicContentSize: NSSize {
        let m = metrics
        let leadW  = leadingImageSize?.width ?? 0
        let delW   = deleteImageSize?.width ?? 0
        let titleW = title.isEmpty ? 0 : titleLayer.bounds.width
        let present = [leadW > 0, titleW > 0, delW > 0].filter { $0 }.count
        let gaps = CGFloat(max(0, present - 1)) * m.gap
        let leftPad  = m.hpad + (leadingImageSize != nil ? m.outerAdj : 0)
        let rightPad = m.hpad + (deleteImageSize  != nil ? m.outerAdj : 0)
        let content = leftPad + leadW + titleW + delW + gaps + rightPad
        return NSSize(width: max(m.minWidth, ceil(content)), height: m.height)
    }

    // MARK: - Init

    public override init(palette: ResolvedPalette) {
        super.init(palette: palette)

        let s = backingScale

        fillLayer.masksToBounds = true      // clips the overlay child to the rounded rect
        fillLayer.contentsScale = s
        layer?.addSublayer(fillLayer)
        overlayLayer.contentsScale = s
        fillLayer.addSublayer(overlayLayer)

        for icon in [leadingIconLayer, deleteIconLayer] {
            icon.contentsGravity = .resizeAspect
            icon.contentsScale = s
            icon.isHidden = true
            layer?.addSublayer(icon)
        }

        titleLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        titleLayer.configureThemedLabel(scale: s, alignment: .center)
        layer?.addSublayer(titleLayer)

        applyTheme()
    }

    private func relayout() {
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    /// `onTap` flipping nil↔non-nil changes focusability AND the accessibility
    /// role (`isClickable` drives `.button` vs `.staticText`), so resync a11y too —
    /// unlike ThemedButton's fixed `.button`, the chip's role is dynamic.
    private func invalidateInteraction() {
        if !isInteractive, window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
        syncAccessibility()
        applyState(animated: false)
    }

    // MARK: - Disable hook

    override func didDisable() {
        isDeleteHovered = false
        pressTarget = .none
    }

    // MARK: - Gates

    override var appearanceGate: Bool { isClickable }
    override var focusGate: Bool { isInteractive }

    // MARK: - fx overrides

    override var fxPressed: Bool {
        ((pressTarget == .body && pressArmed) || previewPressed) && isClickable
    }

    override var showFocusRing: Bool { (isKeyFocused || previewFocused) && isInteractive }

    // MARK: - Theming

    // Fonts via `palette.uiFont(_:)` — the shared type-scale resolver
    // (honours .mono/.rounded/.menu). The `.keycap` variant forces a
    // monospaced face inline at the label call site.

    private var roleColor: NSColor { palette.color(for: role.control) }

    /// The selected wash: the canonical `selection` for neutral, a role wash
    /// (≈ MUI's selected tint) otherwise.
    private var selectionFill: NSColor {
        role == .neutral ? palette.selection
                         : roleColor.withAlphaComponent(ResolvedPalette.InkTier.wash.alpha)
    }

    /// Does the resting fill present an OPAQUE role colour (so the ink must be the
    /// contrast black/white)? Only an enabled, unselected, role-coloured `filled`.
    private var hasOpaqueRoleFill: Bool {
        isEnabled && variant == .filled && !isSelected && role != .neutral
    }

    /// The stable fill (snapped). Disabled = a neutral wash; keycap = a faint key
    /// face; selected = the selection wash; else the variant's resting fill.
    private var baseFillColor: NSColor {
        guard isEnabled else {
            return variant == .filled ? palette.ink(.subtle, of: .muted) : .clear
        }
        switch variant {
        case .keycap:
            return palette.ink(.faint, of: .foreground)
        case .filled:
            if isSelected { return selectionFill }
            return role == .neutral ? palette.ink(.wash, of: .muted) : roleColor
        case .outlined:
            return isSelected ? selectionFill : .clear
        }
    }

    /// Label + leading-icon ink for the current state.
    private var inkColor: NSColor {
        guard isEnabled else { return palette.muted }
        if variant == .keycap { return palette.foreground }
        if hasOpaqueRoleFill {
            switch role {
            case .primary:   return palette.onPrimary()
            case .secondary: return palette.onSecondary()
            case .error:     return palette.bestContrast(on: palette.error)
            case .neutral:   return palette.foreground   // unreachable (guarded out)
            }
        }
        // On a translucent / clear surface: the role tint (neutral ⇒ foreground).
        return roleColor
    }

    /// The × tint: muted at rest, emphasised on hover (error role ⇒ `error`).
    private var deleteColor: NSColor {
        guard isEnabled else { return palette.ink(.subtle, of: .muted) }
        if isDeleteHovered || previewHovered {
            return role == .error ? palette.error : palette.foreground
        }
        return palette.muted
    }

    /// The hover / press / focus state layer (animated) — only on a clickable
    /// body. Mirrors ThemedButton: contrast-ink overlay on an opaque role fill,
    /// role / foreground tint otherwise.
    private var overlayColor: NSColor {
        guard isClickable else { return .clear }
        if hasOpaqueRoleFill {
            let on = palette.bestContrast(on: roleColor)
            if fxPressed { return on.withAlphaComponent(0.12) }
            if fxHovered { return on.withAlphaComponent(0.08) }
            return .clear
        }
        let tint = role == .neutral ? palette.foreground : roleColor
        if fxPressed              { return tint.withAlphaComponent(0.16) }
        if fxHovered || fxFocused { return tint.withAlphaComponent(0.06) }
        return .clear
    }

    /// Border (outlined / keycap only): neutral / keycap ⇒ the `border` role;
    /// a role outline rests at role@0.5 and goes full on interaction / selection.
    private var borderColor: NSColor {
        switch variant {
        case .filled:  return .clear
        case .keycap:  return palette.border
        case .outlined:
            if !isEnabled { return palette.border }
            if role == .neutral { return palette.border }
            if isSelected || fxHovered || fxPressed || fxFocused { return roleColor }
            return roleColor.withAlphaComponent(0.5)
        }
    }

    // MARK: - Theming hooks

    override func applyThemeSnap() {
        let m = metrics
        fillLayer.backgroundColor = baseFillColor.cgColor
        fillLayer.borderWidth = m.border
        fillLayer.borderColor = borderColor.cgColor
    }

    override func rebuildContent() {
        rebuildTitle()
        rebuildIcons()
    }

    override func syncAccessibility() {
        setAccessibilityRole(isClickable ? .button : .staticText)
        setAccessibilityLabel(title.isEmpty ? nil : title)
        setAccessibilityEnabled(isEnabled)
        setAccessibilityValue(isSelected ? 1 : 0)
    }

    override func applyInteractionState() {
        overlayLayer.backgroundColor = overlayColor.cgColor
        fillLayer.borderColor = borderColor.cgColor
        deleteIconLayer.contents = renderedDelete()
    }

    private func rebuildTitle() {
        let f: NSFont = variant == .keycap
            ? .monospacedSystemFont(ofSize: metrics.font, weight: .medium)
            : palette.uiFont(.body)
        let attr = NSAttributedString(string: title, attributes: [
            .font: f, .foregroundColor: inkColor])
        let sz = attr.size()
        layerTxn(animated: false) {
            self.titleLayer.string = title.isEmpty ? nil : attr
            self.titleLayer.foregroundColor = self.inkColor.cgColor
            self.titleLayer.isHidden = title.isEmpty
            self.titleLayer.bounds = CGRect(x: 0, y: 0,
                                            width: ceil(sz.width) + 2, height: ceil(sz.height))
        }
    }

    private func rebuildIcons() {
        let scale = backingScale, pt = metrics.iconPt
        leadingImageSize = applyIconSlot(leadingIconLayer, symbol: leadingSymbol,
                                         image: leadingImage, pt: pt, tint: inkColor, scale: scale)
        // The × is resolved here for sizing; its tint re-renders per state in applyState.
        if isDeletable, let base = phosphorImage("x-circle", pt: pt),
           let (img, sz) = renderedIcon(base, pt: pt, tint: deleteColor, scale: scale) {
            deleteImageSize = sz
            layerTxn(animated: false) {
                self.deleteIconLayer.contents = img
                self.deleteIconLayer.contentsScale = scale
                self.deleteIconLayer.isHidden = false
            }
        } else {
            deleteImageSize = nil
            layerTxn(animated: false) {
                self.deleteIconLayer.contents = nil; self.deleteIconLayer.isHidden = true
            }
        }
    }

    /// Re-tint the × for the current state (cheap — reuses the cached SVG raster).
    private func renderedDelete() -> CGImage? {
        guard isDeletable, let base = phosphorImage("x-circle", pt: metrics.iconPt),
              let (img, _) = renderedIcon(base, pt: metrics.iconPt,
                                          tint: deleteColor, scale: backingScale)
        else { return nil }
        return img
    }

    // MARK: - Layout

    private var backingScale: CGFloat { themeBackingScale }

    override func positionLayers(in bounds: CGRect, local: CGRect) {
        let m = metrics
        fillLayer.frame = bounds
        fillLayer.cornerRadius = m.radius
        overlayLayer.frame = local
        overlayLayer.cornerRadius = m.radius
        layoutContent(in: bounds, m: m)
    }

    override func focusRingPath(in rect: CGRect) -> CGPath {
        concentricRingPath(in: rect, radius: metrics.radius)
    }

    /// Centre the leading-icon / title / × row, with `gap` between present pieces.
    private func layoutContent(in b: NSRect, m: Metrics) {
        var segs: [(CALayer, CGSize, Bool)] = []   // (layer, size, isTitle)
        if let sz = leadingImageSize { segs.append((leadingIconLayer, sz, false)) }
        if !title.isEmpty            { segs.append((titleLayer, titleLayer.bounds.size, true)) }
        if let sz = deleteImageSize  { segs.append((deleteIconLayer, sz, false)) }

        let total = segs.reduce(0) { $0 + $1.1.width }
                  + CGFloat(max(0, segs.count - 1)) * m.gap
        var x = (b.width - total) / 2
        let cy = b.midY
        deleteHitRect = .null
        for (lyr, sz, isTitle) in segs {
            if isTitle {
                titleLayer.position = CGPoint(x: x + sz.width / 2, y: cy)
            } else {
                let frame = CGRect(x: x, y: cy - sz.height / 2, width: sz.width, height: sz.height)
                lyr.frame = frame
                if lyr === deleteIconLayer {
                    // Expand the × hit-target for easy clicking (full chip height).
                    deleteHitRect = CGRect(x: frame.minX - m.gap / 2, y: 0,
                                           width: frame.width + m.gap, height: b.height)
                }
            }
            x += sz.width + m.gap
        }
    }

    override func updateContentsScale(_ s: CGFloat) {
        for l in [fillLayer, overlayLayer, leadingIconLayer, deleteIconLayer] { l.contentsScale = s }
        titleLayer.contentsScale = s
        rebuildIcons()
        needsLayout = true
    }

    // MARK: - Hover (chip body + the × sub-region)

    override var trackingOptions: NSTrackingArea.Options {
        [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect]
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()   // base removes/re-adds with trackingOptions + reconciles isHovered
        if isDeleteHovered, let w = window {
            let local = convert(w.mouseLocationOutsideOfEventStream, from: nil)
            if !bounds.contains(local) { isDeleteHovered = false; applyState(animated: false) }
        }
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isEnabled }

    public override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        updateHover(at: convert(event.locationInWindow, from: nil), animated: true)
    }
    public override func mouseMoved(with event: NSEvent) {
        guard isEnabled else { return }
        updateHover(at: convert(event.locationInWindow, from: nil), animated: true)
    }
    public override func mouseExited(with event: NSEvent) {
        guard isHovered || isDeleteHovered else { return }
        isHovered = false; isDeleteHovered = false
        applyState(animated: true)
    }

    /// Track body-hover (clickable) and ×-hover (deletable) separately so each
    /// affordance lights only its own target.
    private func updateHover(at p: CGPoint, animated: Bool) {
        let overDelete = isDeletable && deleteHitRect.contains(p)
        let body = bounds.contains(p) && !overDelete
        let changed = (isHovered != body) || (isDeleteHovered != overDelete)
        isHovered = body
        isDeleteHovered = overDelete
        if changed { applyState(animated: animated) }
    }

    // MARK: - Press / activate

    /// Is `p` over the armed target (× for `.delete`, the body for `.body`)?
    private func pointer(_ p: CGPoint, over target: PressTarget) -> Bool {
        switch target {
        case .delete: return deleteHitRect.contains(p)
        case .body:   return bounds.contains(p) && !(isDeletable && deleteHitRect.contains(p))
        case .none:   return false
        }
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let p = convert(event.locationInWindow, from: nil)
        if isDeletable, deleteHitRect.contains(p) { pressTarget = .delete }
        else if isClickable { pressTarget = .body }
        else { pressTarget = .none }
        pressArmed = pressTarget != .none
        applyState(animated: true)
    }
    public override func mouseDragged(with event: NSEvent) {
        guard isEnabled, pressTarget != .none else { return }
        let inside = pointer(convert(event.locationInWindow, from: nil), over: pressTarget)
        if inside != pressArmed { pressArmed = inside; applyState(animated: false) }
    }
    public override func mouseUp(with event: NSEvent) {
        guard isEnabled else { pressTarget = .none; return }
        let p = convert(event.locationInWindow, from: nil)
        let target = pressTarget
        pressTarget = .none; pressArmed = false
        if pointer(p, over: target) {
            if target == .delete { onDelete?() } else if target == .body { activate() }
        }
        updateHover(at: p, animated: true)
    }

    // MARK: - Keyboard + focus

    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { super.keyDown(with: event); return }
        // Space activates a clickable chip; Backspace / Delete fires its × (MUI).
        if event.keyCode == 49, isClickable {            // Space
            if !event.isARepeat { activate() }
            return
        }
        if (event.keyCode == 51 || event.keyCode == 117), isDeletable {  // Backspace / fwd-Delete
            if !event.isARepeat { onDelete?() }
            return
        }
        super.keyDown(with: event)
    }

    override func activate() {
        guard isClickable else { return }
        onTap?()
        sendActionToTarget()
        // Refresh the AX value attr AFTER onTap / sendActionToTarget have run so
        // that a consumer who toggles `isSelected` synchronously in onTap is
        // reflected before the post. (isSelected.didSet → applyTheme →
        // syncAccessibility already sets it when the toggle is sync, but calling
        // syncAccessibility here guarantees correctness even if the consumer
        // defers the toggle — the value attribute is always current at post time.)
        syncAccessibility()
        postAXValueChanged()
    }
}

#if DEBUG
// Test-only window into the resolved appearance, so a deterministic test can
// assert the per-variant / per-state colours WITHOUT synthetic events (drive the
// state via the `preview…` overrides). Same-file extension so it can read the
// private layers; not built into release.
extension ThemedChip {
    struct ChipProbe {
        public let fillColor: CGColor?
        public let overlayColor: CGColor?
        public let titleColor: CGColor?
        public let borderColor: CGColor?
        public let borderWidth: CGFloat
        public let cornerRadius: CGFloat
        public let focusRingOpacity: Float
        public let height: CGFloat
        public let intrinsicWidth: CGFloat
        public let hasLeadingIcon: Bool
        public let hasDelete: Bool
    }
    var chipProbe: ChipProbe {
        ChipProbe(
            fillColor: fillLayer.backgroundColor,
            overlayColor: overlayLayer.backgroundColor,
            titleColor: titleLayer.foregroundColor,
            borderColor: fillLayer.borderColor,
            borderWidth: fillLayer.borderWidth,
            cornerRadius: metrics.radius,
            focusRingOpacity: focusRingLayer.opacity,
            height: metrics.height,
            intrinsicWidth: intrinsicContentSize.width,
            hasLeadingIcon: leadingImageSize != nil,
            hasDelete: deleteImageSize != nil)
    }
}
#endif
