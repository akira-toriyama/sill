// ThemeKit — ThemedTooltip: a passive, pointer-driven tooltip (MUI <Tooltip>,
// basic). A small inverted-surface bubble on a free, borderless, non-activating
// `NSPanel` that floats ABOVE the host window — it must draw outside the
// anchor's clip / bounds, so it is a per-anchor CONTROLLER (not an NSView
// wrapper). Themed by assigning a PaletteKit `ResolvedPalette`. AppKit /
// @MainActor.
//
// This is sill's FIRST owned child window. It LIFTS (does not fork) facet's
// KeyablePanel / PopupMenu child-window ideas — panel configuration, the
// visibleFrame placement + 4-side flip, and deterministic teardown — as
// ThemeKit-LOCAL code (sill must never depend on facet). A future shared
// `themedPopupPanel(...)` / `placePopup(...)` factory that this and the coming
// ComboBox / Popover consume is DEFERRED.
//
// Mechanics worth calling out:
//   * The panel is a FREE (un-parented) NSPanel — NOT addChildWindow (a child
//     relationship resurrects on every parent move and must be torn down; we do
//     the visibleFrame math by hand anyway). Ordered in with
//     `orderFrontRegardless` (NEVER makeKey — a tooltip must not steal focus),
//     click-through (`ignoresMouseEvents`), at `.popUpMenu` level.
//   * `invalidateShadow()` is called after EVERY frame change — a borderless
//     panel caches its silhouette shadow, which goes stale the instant a text
//     swap resizes the bubble (the #1 bug in this class of widget).
//   * The tracking area lives ON THE ANCHOR (the ThemedButton / FAB idiom). The
//     controller is the area's owner, so it must be an `NSObject` exposing the
//     exact `mouseEntered:` / `mouseExited:` selectors (a plain Swift class
//     would map to the wrong selector). The owner is UNRETAINED, so the area is
//     removed in `invalidate()` AND defensively in `deinit` (nonisolated-safe).
//   * Inverted themed colours, canonical roles only: fill =
//     `foreground @ 0.92` (a dark surface on light themes, a light one on
//     dark / neon — theme-robust "grey 700"); text = best-contrast black/white
//     on the foreground (the same WCAG crossover `onPrimary` uses). No border;
//     the shadow + the inversion carry the separation.

import AppKit
import QuartzCore
import Palette
import PaletteKit
import Motion

@MainActor
public final class ThemedTooltip: NSObject {

    /// Where the bubble sits relative to the anchor. `.auto` (the default)
    /// prefers `.bottom` and flips to the opposite side when it would overflow
    /// the screen's visible frame.
    public enum Placement { case top, bottom, leading, trailing, auto }

    // The concrete, post-flip side (never `.auto`) is the shared `PopupSide`
    // (see PopupPanel.swift) — it drives the arrow edge.

    // MARK: - Public configuration

    /// The anchor the tooltip describes. Held WEAK — the anchor owns its own
    /// lifecycle; the tooltip must not keep a dead view alive.
    public weak var anchor: NSView? { _anchor }

    /// The tooltip text. Assigning re-measures + repositions a shown bubble and
    /// refreshes the anchor's accessibility help.
    public var text: String { didSet { rebuild(); _anchor?.setAccessibilityHelp(text.isEmpty ? nil : text) } }

    /// The theme. Assigning re-themes the bubble (the mandated contract). Colour
    /// only — size is text-driven.
    public var palette: ResolvedPalette { didSet { rebuild() } }

    /// Preferred placement; a shown bubble re-resolves immediately.
    public var placement: Placement { didSet { if isShown { reposition() } } }

    /// Hover dwell before showing. macOS feel — MUI's 100 ms is too eager for a
    /// desktop pointer.
    public var enterDelay: TimeInterval = 0.5
    /// Grace before hiding after the pointer leaves (anti-flicker).
    public var leaveDelay: TimeInterval = 0.1

    /// Force-show the bubble inline, skipping the enter/leave delays and the
    /// fade — the capture / test seam (the analogue of ThemedTextField's
    /// `previewFocused`). prism can't screenshot a separate child window, so the
    /// bench draws an inline MOCK of the bubble instead; this exists for tests.
    public var previewVisible = false {
        didSet {
            guard previewVisible != oldValue else { return }
            if previewVisible { present(animated: false) } else { hide() }
        }
    }

    // MARK: - Internals

    nonisolated(unsafe) private weak var _anchor: NSView?
    nonisolated(unsafe) private var trackingArea: NSTrackingArea?

    private let bubbleView = NSView()
    private let fillLayer  = CALayer()        // rounded inverted surface (clips nothing)
    private let arrowLayer = CAShapeLayer()   // triangle on the anchor-facing edge
    private let textLayer  = CATextLayer()    // wrapped label

    private var panel: PopupPanel?
    private var isShown = false
    private var isInvalidated = false

    private var pendingShow: DispatchWorkItem?
    private var pendingHide: DispatchWorkItem?

    /// Monotonic fade token. A fade-out's deferred `orderOut` only fires if no
    /// newer present/hide superseded it — so a quick re-show inside the 0.16 s
    /// fade can't be clobbered by the stale completion.
    private var fadeGen = 0

    /// The shared 0.16 s fade (MUI Tooltip timing) + host glue.
    private let fade = PopupFade(duration: ThemedTransition.Duration.enter)
    private let glue = PopupGlue()

    /// Last measured fill (surface) size, padding included; arrow excluded.
    private var fillSize: CGSize = .zero

    // Probe / glue state (set by reposition()).
    private var resolvedSide: PopupSide = .bottom
    private var lastBubbleFrame: CGRect = .zero
    private var lastArrowCross: CGFloat = 0

    // MARK: - Metrics (MUI v5 Tooltip values + macOS placement constants)

    private let gap: CGFloat = CGFloat(Space.md)            // anchor edge → arrow tip
    // (the visible-frame margin now lives in the shared `popupScreenMargin`)
    private let cornerRadius: CGFloat = CGFloat(Radius.sm)
    private let hpad: CGFloat = CGFloat(Space.md)           // MUI padding 4×8
    private let vpad: CGFloat = CGFloat(Space.xs)
    private let maxWidth: CGFloat = 300     // wrap past this
    private let arrowBase: CGFloat = 11     // triangle base width
    private let arrowLen: CGFloat = 8       // triangle protrusion (≈ base / √2)

    // MARK: - Init

    public init(anchor: NSView, text: String, palette: ResolvedPalette,
                placement: Placement = .auto) {
        self._anchor = anchor
        self.text = text
        self.palette = palette
        self.placement = placement
        super.init()

        // Layer tree lives on the (cheap) bubble view from the start; the
        // window-server-backed NSPanel is created lazily on first show.
        bubbleView.wantsLayer = true
        bubbleView.layer?.masksToBounds = false
        let s = backingScale
        fillLayer.contentsScale = s
        arrowLayer.contentsScale = s
        arrowLayer.lineWidth = 0
        textLayer.contentsScale = s
        textLayer.isWrapped = true
        textLayer.truncationMode = .none
        bubbleView.layer?.addSublayer(fillLayer)
        bubbleView.layer?.addSublayer(arrowLayer)
        bubbleView.layer?.addSublayer(textLayer)

        installTrackingArea(on: anchor)
        anchor.toolTip = nil                       // no native double-fire
        anchor.setAccessibilityHelp(text.isEmpty ? nil : text)  // VoiceOver reaches text via the anchor
        rebuild()
    }

    /// Tear down the tracking area whose owner (self) is unretained, so a later
    /// mouse event can't message a freed controller. `removeTrackingArea` is
    /// @MainActor: on the main thread we assume isolation; if the controller is
    /// somehow released off-main we bounce the removal to main (laundering the
    /// non-Sendable anchor / area through `nonisolated(unsafe)` locals — they are
    /// dead in this object, so there is no real concurrent access, and the work
    /// runs ON main where the call is valid). Releasing `panel` clears the screen.
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        guard let a = _anchor, let t = trackingArea else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { a.removeTrackingArea(t) }
        } else {
            nonisolated(unsafe) let view = a
            nonisolated(unsafe) let area = t
            DispatchQueue.main.async { MainActor.assumeIsolated { view.removeTrackingArea(area) } }
        }
    }

    /// One-liner ergonomics: build + return the RETAINED controller. The caller
    /// MUST retain it (AppKit holds the tracking-area owner weakly — like
    /// ThemedTextField retaining its `delegateBox`). Dropping it removes the
    /// tooltip.
    @discardableResult
    public static func attach(to anchor: NSView, text: String,
                              palette: ResolvedPalette,
                              placement: Placement = .auto) -> ThemedTooltip {
        ThemedTooltip(anchor: anchor, text: text, palette: palette, placement: placement)
    }

    // MARK: - Show / hide (public, programmatic — bypass the hover delays)

    /// Show now (no enter delay). No-op if the anchor has no window or the text
    /// is empty.
    public func show() { present(animated: !reduceMotion) }

    /// Hide now (no leave delay).
    public func hide() {
        pendingShow?.cancel(); pendingShow = nil
        pendingHide?.cancel(); pendingHide = nil
        guard isShown else { return }
        isShown = false
        stopGlue()
        fadeOut(animated: !reduceMotion)
    }

    /// Deterministic teardown: order out, drop the panel, remove the tracking
    /// area + observers, cancel timers. Idempotent; also called from `deinit`.
    public func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        pendingShow?.cancel(); pendingShow = nil
        pendingHide?.cancel(); pendingHide = nil
        stopGlue()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let a = _anchor, let t = trackingArea { a.removeTrackingArea(t) }
        trackingArea = nil
        panel?.orderOut(nil)
        panel = nil
        isShown = false
    }

    private func present(animated: Bool) {
        guard !isInvalidated else { return }
        pendingShow?.cancel(); pendingShow = nil
        pendingHide?.cancel(); pendingHide = nil
        guard !text.isEmpty, _anchor?.window != nil else { return }
        // Already up → just re-resolve placement; don't re-register glue or
        // re-fade (a redundant show() / previewVisible toggle is idempotent).
        if isShown { reposition(); return }
        fadeGen &+= 1               // supersede any pending fade-out completion
        ensurePanel()
        rebuild()
        reposition()
        isShown = true
        startGlue()
        fadeIn(animated: animated)
    }

    // MARK: - Hover debounce (tracking area ON THE ANCHOR; owner = self)

    private func installTrackingArea(on view: NSView) {
        // `.inVisibleRect` keeps the area synced to the anchor's visible rect
        // automatically (AppKit refreshes it on the anchor's own
        // updateTrackingAreas), so the controller never re-installs it.
        let t = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self, userInfo: nil)
        view.addTrackingArea(t)
        trackingArea = t
    }

    // Explicit objc selectors: a plain Swift `mouseEntered(with:)` would map to
    // `mouseEnteredWith:`, NOT the `mouseEntered:` the tracking area sends.
    @objc(mouseEntered:) private func anchorMouseEntered(_ event: NSEvent) {
        pendingHide?.cancel(); pendingHide = nil
        guard !previewVisible, !isShown, !isInvalidated else { return }
        let work = DispatchWorkItem { [weak self] in self?.show() }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + enterDelay, execute: work)
    }

    @objc(mouseExited:) private func anchorMouseExited(_ event: NSEvent) {
        pendingShow?.cancel(); pendingShow = nil
        guard !previewVisible, isShown else { return }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + leaveDelay, execute: work)
    }

    // MARK: - Panel

    private func ensurePanel() {
        guard panel == nil else { return }
        // Passive bubble: click-through + out of AX (VoiceOver reaches the text via
        // the anchor's accessibilityHelp instead).
        let p = themedPopupPanel(interactive: false, role: .unknown)
        p.contentView = bubbleView
        p.contentView?.setAccessibilityElement(false)
        panel = p
    }

    private func fadeIn(animated: Bool) {
        guard let panel, let bl = bubbleView.layer else { return }
        panel.orderFrontRegardless()         // NEVER makeKey — must not steal focus
        fade.fadeIn(bl, animated: animated)
    }

    private func fadeOut(animated: Bool) {
        guard let panel, let bl = bubbleView.layer else { return }
        // Order out only if this fade still stands (no re-show superseded it).
        let gen = fadeGen
        fade.fadeOut(bl, panel: panel, animated: animated) { [weak self] in
            guard let self else { return false }
            return self.fadeGen == gen && !self.isShown
        }
    }

    // MARK: - Content (measure + theme the bubble; size is text-driven)

    // Fonts via `palette.uiFont(_:)` — the shared type-scale resolver
    // (honours .mono/.rounded/.menu; the old local helper dropped two).

    /// The inverted surface — `foreground @ 0.92`. A dark bubble on a light
    /// theme, a light one on a dark / neon theme, theme-robustly.
    private var fillColor: NSColor { palette.foreground.withAlphaComponent(0.92) }
    /// Best-contrast ink on the (opaque) foreground.
    private var textColor: NSColor { palette.bestContrast(on: palette.foreground) }

    /// Re-measure the text, re-theme the layers, and reposition a shown bubble.
    /// Snapped (a theme / text swap should not smear).
    private func rebuild() {
        let font = palette.uiFont(.tooltip)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        let attr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: textColor, .paragraphStyle: para])
        let maxTextW = maxWidth - 2 * hpad
        let bound = attr.boundingRect(
            with: CGSize(width: maxTextW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let tw = ceil(bound.width), th = ceil(bound.height)
        fillSize = CGSize(width: tw + 2 * hpad, height: th + 2 * vpad)

        let s = backingScale
        fade.transact(animated: false) {
            self.textLayer.string = attr
            self.textLayer.bounds = CGRect(x: 0, y: 0, width: tw, height: th)
            self.textLayer.foregroundColor = self.textColor.cgColor
            self.textLayer.contentsScale = s
            self.fillLayer.backgroundColor = self.fillColor.cgColor
            self.fillLayer.cornerRadius = self.cornerRadius
            self.fillLayer.contentsScale = s
            self.arrowLayer.fillColor = self.fillColor.cgColor
            self.arrowLayer.contentsScale = s
        }
        if isShown { reposition() }
    }

    // MARK: - Placement + flip (all math in Cocoa global space, Y-UP)

    private func reposition() {
        guard let panel, let anchor = _anchor, let win = anchor.window else { return }
        let onScreen = win.convertToScreen(anchor.convert(anchor.bounds, to: nil))

        // Shared engine: screen-by-geometry pick · side resolve + 4-side edge-flip
        // (panel size = fill + arrow on the facing axis) · clamp · setFrame +
        // invalidateShadow. Returns the post-flip side + the committed frame.
        guard case let .sideRelative(frame, side)? =
                placePopup(panel, anchorRectOnScreen: onScreen,
                           .sideRelative(preferred: resolvePreferred(placement),
                                         fillSize: fillSize, gap: gap, arrowLen: arrowLen))
        else { return }

        // Lay out the bubble + arrow in the committed frame (tooltip-local; the
        // arrow re-points at the anchor except within a corner-clear inset).
        let fill = fillRect(in: frame.size, side: side)
        let cross = arrowCross(side: side, onScreen: onScreen, panelOrigin: frame.origin, fill: fill)
        layoutBubble(side: side, panelSize: frame.size, fill: fill, cross: cross)

        resolvedSide = side
        lastBubbleFrame = frame
        lastArrowCross = cross
    }

    private func resolvePreferred(_ p: Placement) -> PopupSide {
        switch p {
        case .auto, .bottom: return .bottom
        case .top:           return .top
        case .leading:       return .leading
        case .trailing:      return .trailing
        }
    }

    /// The fill surface within the panel content (Y-up); the arrow occupies the
    /// remaining strip on the anchor-facing edge.
    private func fillRect(in size: CGSize, side: PopupSide) -> CGRect {
        switch side {
        case .bottom:   return CGRect(x: 0,        y: 0,       width: fillSize.width, height: fillSize.height)  // arrow on top
        case .top:      return CGRect(x: 0,        y: arrowLen, width: fillSize.width, height: fillSize.height) // arrow on bottom
        case .leading:  return CGRect(x: 0,        y: 0,       width: fillSize.width, height: fillSize.height)  // arrow on right
        case .trailing: return CGRect(x: arrowLen, y: 0,       width: fillSize.width, height: fillSize.height)  // arrow on left
        }
    }

    /// Arrow centre on the cross axis (panel-local), clamped clear of the rounded
    /// corners so it always reads as one shape — pointed at the anchor centre, or
    /// as close as the corner-clear inset allows when the anchor sits within
    /// (cornerRadius + arrowBase/2) of a corner.
    private func arrowCross(side: PopupSide, onScreen: CGRect, panelOrigin: CGPoint, fill: CGRect) -> CGFloat {
        let inset = cornerRadius + arrowBase / 2
        switch side {
        case .top, .bottom:
            return min(max(onScreen.midX - panelOrigin.x, fill.minX + inset), fill.maxX - inset)
        case .leading, .trailing:
            return min(max(onScreen.midY - panelOrigin.y, fill.minY + inset), fill.maxY - inset)
        }
    }

    private func layoutBubble(side: PopupSide, panelSize: CGSize, fill: CGRect, cross: CGFloat) {
        fade.transact(animated: false) {
            self.fillLayer.frame = fill
            self.fillLayer.cornerRadius = self.cornerRadius
            self.textLayer.position = CGPoint(x: fill.midX, y: fill.midY)
            self.arrowLayer.frame = CGRect(origin: .zero, size: panelSize)
            self.arrowLayer.path = self.arrowPath(side: side, fill: fill, cross: cross)
        }
    }

    /// A filled triangle pointing OUTWARD (toward the anchor), its base overlapped
    /// 1 pt into the fill so the rounded surface + arrow read seamlessly.
    private func arrowPath(side: PopupSide, fill: CGRect, cross: CGFloat) -> CGPath {
        let b = arrowBase, len = arrowLen, ov: CGFloat = 1
        let path = CGMutablePath()
        switch side {
        case .bottom:   // arrow on top edge, pointing up
            path.move(to: CGPoint(x: cross - b / 2, y: fill.maxY - ov))
            path.addLine(to: CGPoint(x: cross + b / 2, y: fill.maxY - ov))
            path.addLine(to: CGPoint(x: cross, y: fill.maxY + len))
        case .top:      // arrow on bottom edge, pointing down
            path.move(to: CGPoint(x: cross - b / 2, y: fill.minY + ov))
            path.addLine(to: CGPoint(x: cross + b / 2, y: fill.minY + ov))
            path.addLine(to: CGPoint(x: cross, y: fill.minY - len))
        case .leading:  // arrow on right edge, pointing right
            path.move(to: CGPoint(x: fill.maxX - ov, y: cross - b / 2))
            path.addLine(to: CGPoint(x: fill.maxX - ov, y: cross + b / 2))
            path.addLine(to: CGPoint(x: fill.maxX + len, y: cross))
        case .trailing: // arrow on left edge, pointing left
            path.move(to: CGPoint(x: fill.minX + ov, y: cross - b / 2))
            path.addLine(to: CGPoint(x: fill.minX + ov, y: cross + b / 2))
            path.addLine(to: CGPoint(x: fill.minX - len, y: cross))
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Host glue (keep the bubble pinned to a moving / scrolling anchor)

    private func startGlue() {
        guard let win = _anchor?.window else { return }
        // No resign-key observer — a tooltip does not dismiss on the host losing
        // key focus (the combo does; that's the opt-in `onResignKey`).
        glue.start(window: win, clip: _anchor?.enclosingScrollView?.contentView,
                   onGeometryChange: { [weak self] in self?.hostGeometryChanged() },
                   onClose: { [weak self] in self?.hide() })
    }

    private func stopGlue() { glue.stop() }

    private func hostGeometryChanged() {
        guard isShown else { return }
        // Scrolled fully out of a clip view (or off the window edge) → dismiss,
        // rather than parking the bubble at a screen edge pointing at nothing.
        if let a = _anchor, a.visibleRect.isEmpty { hide(); return }
        reposition()
    }

    // MARK: - Helpers

    private var backingScale: CGFloat {
        _anchor?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

#if DEBUG
// Test-only window into the resolved bubble — placement (POST flip / clamp),
// colours, arrow point, AX — so a deterministic test can assert them via
// `previewVisible` without synthetic mouse events. Same-file extension so it can
// read the private state; not built into release.
extension ThemedTooltip {
    struct TooltipProbe {
        let isVisible: Bool
        let resolvedSide: PopupSide
        let fillColor: CGColor?
        let textColor: CGColor?
        let bubbleFrame: CGRect        // screen coords, post-clamp
        let arrowCross: CGFloat        // arrow centre, panel-local (cross axis)
        let cornerRadius: CGFloat
        let hasOpacityAnimation: Bool   // a live fade is attached to the bubble layer
        let panelOrderedIn: Bool        // the panel window is actually on screen
        let reduceMotionRespected: Bool
        let axHelpOnAnchor: String?
    }
    var tooltipProbe: TooltipProbe {
        let animating = bubbleView.layer?.animation(forKey: "opacity") != nil
        return TooltipProbe(
            isVisible: isShown,
            resolvedSide: resolvedSide,
            fillColor: fillLayer.backgroundColor,
            textColor: textLayer.foregroundColor,
            bubbleFrame: lastBubbleFrame,
            arrowCross: lastArrowCross,
            cornerRadius: cornerRadius,
            hasOpacityAnimation: animating,
            panelOrderedIn: panel?.isVisible ?? false,
            reduceMotionRespected: !(reduceMotion && animating),
            axHelpOnAnchor: _anchor?.accessibilityHelp())
    }
}
#endif
