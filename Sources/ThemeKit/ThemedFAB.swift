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

@MainActor
public final class ThemedFAB: NSControl {

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

    /// The theme. Assigning re-themes the whole control.
    public var palette: ResolvedPalette { didSet { applyTheme() } }

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

    /// Optional key equivalent (MUI has none). Set to `"\r"` to make this the
    /// Return-activated default action. Matched in `performKeyEquivalent`.
    public var keyEquivalent: String = ""
    public var keyEquivalentModifierMask: NSEvent.ModifierFlags = []

    /// Force the hovered / pressed / focused APPEARANCE without real events —
    /// for previews / screenshots only (the bench shows the LIVE 演出). A
    /// disabled FAB ignores them.
    public var previewHovered = false { didSet { applyState(animated: false) } }
    public var previewPressed = false { didSet { applyState(animated: false) } }
    public var previewFocused = false { didSet { applyState(animated: false) } }

    // MARK: - NSControl overrides (custom storage — a cell-less NSControl must
    //         NOT lean on the cell-backed isEnabled / target / action).

    private var _enabled = true
    public override var isEnabled: Bool {
        get { _enabled }
        set {
            guard _enabled != newValue else { return }
            _enabled = newValue
            // Clear any in-flight hover / press — a disable can strand them with
            // no matching exit / up event (the stuck-hover gotcha).
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

    private let shadowLayer   = CALayer()        // elevation — UNCLIPPED, explicit shadowPath
    private let fillLayer     = CALayer()        // round/pill fill (clips the overlay child)
    private let overlayLayer  = CALayer()        // hover / press state layer (child of fill)
    private let iconLayer     = CALayer()        // the leading / sole icon
    private let titleLayer    = CATextLayer()    // extended label (hidden for circular)
    private let focusRingLayer = CAShapeLayer()  // themed keyboard-focus ring (top, unclipped)

    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false
    private var isKeyFocused = false
    private var isFlashing = false   // a keyboard-flash activation is in flight

    /// Rendered icon point-size (nil ⇒ no icon) — drives layout + extended width.
    private var iconSize: CGSize?

    public override var isFlipped: Bool { false }   // y-up: a downward shadow is −y

    // MARK: - Metrics (MUI v5 Fab values; circular diameters 40/48/56,
    //         extended heights 34/40/48, content centred)

    private struct Metrics {
        let diameter, height, hpad, iconPt, font, gap, ringInset: CGFloat
    }
    private var metrics: Metrics {
        let diameter: CGFloat = size == .small ? 40 : size == .medium ? 48 : 56
        let height:   CGFloat = size == .small ? 34 : size == .medium ? 40 : 48
        let iconPt:   CGFloat = size == .small ? 20 : size == .medium ? 24 : 28
        let font:     CGFloat = size == .small ? 13 : 14
        let hpad:     CGFloat = size == .small ? 8 : 16
        return Metrics(diameter: diameter, height: height, hpad: hpad,
                       iconPt: iconPt, font: font, gap: 8, ringInset: 2)
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

    public init(palette: ResolvedPalette) {
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false        // the focus ring / shadow live outside bounds
        focusRingType = .none               // we draw our own themed ring

        let s = backingScale

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

    // Fonts via `palette.uiFont(_:)` — the shared type-scale resolver
    // (honours .mono/.rounded/.menu; the old local helper dropped two).

    private var roleColor: NSColor {
        switch role {
        case .primary:   return palette.primary
        case .secondary: return palette.secondary
        }
    }

    /// Best-contrast ink on the role fill via PaletteKit's role accessors
    /// (`onPrimary` / `onSecondary`) — the same WCAG crossover, so a secondary
    /// FAB on a neon theme gets a legible glyph, not just primary.
    private var roleInk: NSColor {
        switch role {
        case .primary:   return palette.onPrimary()
        case .secondary: return palette.onSecondary()
        }
    }

    /// Black or white, whichever best contrasts a fill — a local copy of the
    /// `onPrimary` crossover so the animated overlay is role-correct for ANY
    /// fill (matches ThemedButton's contained overlay).
    private func ink(on c: NSColor) -> NSColor {
        let s = c.usingColorSpace(.sRGB) ?? c
        let l = wcagRelativeLuminance(r: Double(s.redComponent),
                                      g: Double(s.greenComponent),
                                      b: Double(s.blueComponent))
        return prefersBlackForeground(fillRelLuminance: l) ? .black : .white
    }

    /// Icon + extended-label ink for the current state (role contrast / muted).
    private var inkColor: NSColor { isEnabled ? roleInk : palette.muted }

    /// The stable fill (snapped; never animated on hover — the darken is the
    /// overlay). Role fill when enabled; a neutral muted wash when disabled
    /// (matches ThemedButton's contained disabled fill).
    private var baseFillColor: NSColor {
        isEnabled ? roleColor : palette.ink(.subtle, of: .muted)
    }

    private var fxHovered: Bool { (isHovered || previewHovered) && isEnabled }
    private var fxPressed: Bool { (isPressed || previewPressed) && isEnabled }
    private var fxFocused: Bool { (isKeyFocused || previewFocused) && isEnabled }

    /// The hover / press state layer (animated): the contrast ink on the role
    /// fill at MUI's hover / active alpha (darkens a light fill, lightens a dark
    /// one — theme-robust). Focus shows the ring only (no wash), matching the
    /// contained button.
    private var overlayColor: NSColor {
        guard isEnabled else { return .clear }
        let on = ink(on: roleColor)
        if fxPressed { return on.withAlphaComponent(0.12) }
        if fxHovered { return on.withAlphaComponent(0.08) }
        return .clear
    }

    private struct Elevation { let opacity: Float; let radius: CGFloat; let offsetY: CGFloat }
    /// FAB elevation: it floats HIGHER than a button (resting ≈ dp6) and only
    /// deepens on press (≈ dp12). Hover / focus do NOT bump it (a FAB is already
    /// raised) — with only two rungs there is no dip risk.
    private var elevation: Elevation {
        guard isEnabled else { return Elevation(opacity: 0, radius: 0, offsetY: 0) }
        if fxPressed { return Elevation(opacity: 0.34, radius: 12, offsetY: -7) }
        return Elevation(opacity: 0.30, radius: 8, offsetY: -3)
    }

    private var showFocusRing: Bool { fxFocused }

    /// Re-theme: snaps the STABLE visuals (fill / icon / title / structure),
    /// then settles the state layer. Snapping (not cross-fading) matches the
    /// other widgets — a theme switch shouldn't smear.
    public func applyTheme() {
        layerTxn(animated: false) {
            self.fillLayer.backgroundColor = self.baseFillColor.cgColor
            self.focusRingLayer.strokeColor = self.palette.primary.cgColor
        }
        rebuildTitle()
        rebuildIcon()
        syncAccessibility()
        applyState(animated: false)
        needsLayout = true
    }

    /// The interaction-driven layer props — animated on a real hover / press /
    /// focus change, snapped from `applyTheme` / previews / layout.
    private func applyState(animated: Bool) {
        layerTxn(animated: animated) {
            self.overlayLayer.backgroundColor = self.overlayColor.cgColor
            let e = self.elevation
            self.shadowLayer.shadowOpacity = e.opacity
            self.shadowLayer.shadowRadius  = e.radius
            self.shadowLayer.shadowOffset  = CGSize(width: 0, height: e.offsetY)
            self.focusRingLayer.opacity = self.showFocusRing ? 1 : 0
        }
    }

    private func syncAccessibility() {
        setAccessibilityLabel(label.isEmpty ? nil : label)   // original case for VoiceOver
        setAccessibilityEnabled(isEnabled)
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
        let scale = backingScale, pt = metrics.iconPt, tint = inkColor
        let resolved: (CGImage, CGSize)?
        if let leadingImage {
            resolved = renderedIcon(leadingImage, pt: pt, tint: tint, scale: scale)
        } else if let name = leadingSymbol, let base = phosphorImage(name, pt: pt) {
            resolved = renderedIcon(base, pt: pt, tint: tint, scale: scale)
        } else {
            resolved = nil
        }
        guard let (img, sz) = resolved else {
            iconSize = nil
            layerTxn(animated: false) { self.iconLayer.contents = nil; self.iconLayer.isHidden = true }
            return
        }
        iconSize = sz
        layerTxn(animated: false) {
            self.iconLayer.contents = img
            self.iconLayer.contentsScale = scale
            self.iconLayer.isHidden = false
        }
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
            // Half the SHORTER side: a perfect circle when square, pill ends when
            // wider. Reading from bounds (not the metric) keeps it correct even
            // if the host stretches the view.
            let r = min(b.width, b.height) / 2

            self.shadowLayer.frame = b
            self.shadowLayer.shadowPath =
                CGPath(roundedRect: local, cornerWidth: r, cornerHeight: r, transform: nil)

            self.fillLayer.frame = b
            self.fillLayer.cornerRadius = r
            self.overlayLayer.frame = local
            self.overlayLayer.cornerRadius = r

            let ringRect = local.insetBy(dx: -m.ringInset, dy: -m.ringInset)
            self.focusRingLayer.frame = b
            self.focusRingLayer.path = CGPath(roundedRect: ringRect,
                cornerWidth: r + m.ringInset, cornerHeight: r + m.ringInset, transform: nil)

            self.layoutContent(in: b, m: m)
        }
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

    /// Keep text / strokes / symbols crisp across a display-scale change —
    /// `contentsScale` was captured once at init (before a window), and the
    /// rasterized symbol bitmap must be re-rendered at the new scale.
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = backingScale
        for l in [shadowLayer, fillLayer, overlayLayer, iconLayer] { l.contentsScale = s }
        titleLayer.contentsScale = s
        focusRingLayer.contentsScale = s
        rebuildIcon()       // re-rasterize at the new device scale
        needsLayout = true
    }

    // MARK: - Snap-vs-animate (verbatim ThemedButton idiom)

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
    // themed ring arrive via Tab; Return via performKeyEquivalent).
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
        if isEnabled, event.keyCode == 49 {   // Space activates the focused FAB
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
    /// flash atomic: a second Space/Return inside the 0.12 s window is dropped
    /// (no double-fire), and the deferred block re-checks `isEnabled` (via
    /// `activate`) so an async disable mid-flash cancels the activation.
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
