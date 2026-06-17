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

@MainActor
public final class ThemedTooltip: NSObject {

    /// Where the bubble sits relative to the anchor. `.auto` (the default)
    /// prefers `.bottom` and flips to the opposite side when it would overflow
    /// the screen's visible frame.
    public enum Placement { case top, bottom, leading, trailing, auto }

    /// The concrete, post-flip side (never `.auto`). Drives the arrow edge.
    enum Side { case top, bottom, leading, trailing }

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
    /// `previewFocused`). still can't screenshot a separate child window, so the
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

    private var panel: NSPanel?
    private var isShown = false
    private var isInvalidated = false

    private var pendingShow: DispatchWorkItem?
    private var pendingHide: DispatchWorkItem?

    /// Monotonic fade token. A fade-out's deferred `orderOut` only fires if no
    /// newer present/hide superseded it — so a quick re-show inside the 0.16 s
    /// fade can't be clobbered by the stale completion.
    private var fadeGen = 0

    /// Last measured fill (surface) size, padding included; arrow excluded.
    private var fillSize: CGSize = .zero

    // Probe / glue state (set by reposition()).
    private var resolvedSide: Side = .bottom
    private var lastBubbleFrame: CGRect = .zero
    private var lastArrowCross: CGFloat = 0

    // MARK: - Metrics (MUI v5 Tooltip values + macOS placement constants)

    private let gap: CGFloat = 8            // anchor edge → arrow tip
    private let screenMargin: CGFloat = 4   // keep this far inside the visible frame
    private let cornerRadius: CGFloat = 4
    private let hpad: CGFloat = 8           // MUI padding 4×8
    private let vpad: CGFloat = 4
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
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = true          // a borderless panel gets no free hide-on-deactivate
        p.level = .popUpMenu                 // above .floating
        p.ignoresMouseEvents = true          // click-through (passive)
        p.hasShadow = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                .ignoresCycle, .stationary]
        p.contentView = bubbleView
        p.contentView?.setAccessibilityElement(false)
        p.setAccessibilityRole(.unknown)     // keep the panel out of AX
        panel = p
    }

    private func fadeIn(animated: Bool) {
        guard let panel, let bl = bubbleView.layer else { return }
        panel.orderFrontRegardless()         // NEVER makeKey — must not steal focus
        if animated {
            bl.opacity = 0
            layerTxn(animated: true) { bl.opacity = 1 }
        } else {
            layerTxn(animated: false) { bl.opacity = 1 }
        }
    }

    private func fadeOut(animated: Bool) {
        guard let panel, let bl = bubbleView.layer else { return }
        if animated {
            let gen = fadeGen
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.16)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            // Order out only if this fade still stands (no re-show superseded it).
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.fadeGen == gen, !self.isShown else { return }
                panel.orderOut(nil)
            }
            bl.opacity = 0
            CATransaction.commit()
        } else {
            layerTxn(animated: false) { bl.opacity = 0 }
            panel.orderOut(nil)
        }
    }

    // MARK: - Content (measure + theme the bubble; size is text-driven)

    private func themedFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        switch palette.font {
        case .mono: return .monospacedSystemFont(ofSize: size, weight: weight)
        default:    return .systemFont(ofSize: size, weight: weight)
        }
    }

    /// Black or white, whichever best contrasts a fill — the same WCAG crossover
    /// `onPrimary` uses, via the pure `Palette` helpers (no drift). PaletteKit's
    /// `bestContrast` is internal, so the contained / FAB widgets keep this local
    /// copy; the tooltip does the same for its `onForeground` text.
    private func ink(on c: NSColor) -> NSColor {
        let s = c.usingColorSpace(.sRGB) ?? c
        let l = wcagRelativeLuminance(r: Double(s.redComponent),
                                      g: Double(s.greenComponent),
                                      b: Double(s.blueComponent))
        return prefersBlackForeground(fillRelLuminance: l) ? .black : .white
    }

    /// The inverted surface — `foreground @ 0.92`. A dark bubble on a light
    /// theme, a light one on a dark / neon theme, theme-robustly.
    private var fillColor: NSColor { palette.foreground.withAlphaComponent(0.92) }
    /// Best-contrast ink on the (opaque) foreground.
    private var textColor: NSColor { ink(on: palette.foreground) }

    /// Re-measure the text, re-theme the layers, and reposition a shown bubble.
    /// Snapped (a theme / text swap should not smear).
    private func rebuild() {
        let font = themedFont(11, .medium)
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
        layerTxn(animated: false) {
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

        // Pick the screen by GEOMETRY (not win.screen!) — the anchor's centre.
        let centre = CGPoint(x: onScreen.midX, y: onScreen.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(centre) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let vf = screen?.visibleFrame else { return }

        // Resolve preferred side, then edge-flip against the visible frame.
        var side = resolvePreferred(placement)
        var size = panelSize(for: side)
        var origin = originFor(side: side, onScreen: onScreen, size: size)
        switch side {
        case .bottom:   if origin.y < vf.minY { side = .top }
        case .top:      if origin.y + size.height > vf.maxY { side = .bottom }
        case .leading:  if origin.x < vf.minX { side = .trailing }
        case .trailing: if origin.x + size.width > vf.maxX { side = .leading }
        }
        size = panelSize(for: side)
        origin = originFor(side: side, onScreen: onScreen, size: size)

        // Clamp BOTH axes into the visible frame (post-flip the opposite side
        // can still graze an edge); the arrow re-point tracks the anchor except
        // within (cornerRadius + arrowBase/2) of a corner, where it pins to the
        // corner-clear inset.
        let m = screenMargin
        origin.x = min(max(origin.x, vf.minX + m), max(vf.minX + m, vf.maxX - m - size.width))
        origin.y = min(max(origin.y, vf.minY + m), max(vf.minY + m, vf.maxY - m - size.height))

        let frame = CGRect(origin: origin, size: size)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()             // the cached silhouette goes stale on resize

        let fill = fillRect(in: size, side: side)
        let cross = arrowCross(side: side, onScreen: onScreen, panelOrigin: origin, fill: fill)
        layoutBubble(side: side, panelSize: size, fill: fill, cross: cross)

        resolvedSide = side
        lastBubbleFrame = frame
        lastArrowCross = cross
    }

    private func resolvePreferred(_ p: Placement) -> Side {
        switch p {
        case .auto, .bottom: return .bottom
        case .top:           return .top
        case .leading:       return .leading
        case .trailing:      return .trailing
        }
    }

    /// Panel size = fill surface + the arrow protrusion on the anchor-facing axis.
    private func panelSize(for side: Side) -> CGSize {
        switch side {
        case .top, .bottom:     return CGSize(width: fillSize.width, height: fillSize.height + arrowLen)
        case .leading, .trailing: return CGSize(width: fillSize.width + arrowLen, height: fillSize.height)
        }
    }

    /// Pre-flip / pre-clamp panel origin (Y-up), bubble centred on the cross axis,
    /// `gap` from the anchor edge to the arrow tip.
    private func originFor(side: Side, onScreen: CGRect, size: CGSize) -> CGPoint {
        switch side {
        case .bottom:   return CGPoint(x: onScreen.midX - size.width / 2, y: onScreen.minY - gap - size.height)
        case .top:      return CGPoint(x: onScreen.midX - size.width / 2, y: onScreen.maxY + gap)
        case .leading:  return CGPoint(x: onScreen.minX - gap - size.width, y: onScreen.midY - size.height / 2)
        case .trailing: return CGPoint(x: onScreen.maxX + gap, y: onScreen.midY - size.height / 2)
        }
    }

    /// The fill surface within the panel content (Y-up); the arrow occupies the
    /// remaining strip on the anchor-facing edge.
    private func fillRect(in size: CGSize, side: Side) -> CGRect {
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
    private func arrowCross(side: Side, onScreen: CGRect, panelOrigin: CGPoint, fill: CGRect) -> CGFloat {
        let inset = cornerRadius + arrowBase / 2
        switch side {
        case .top, .bottom:
            return min(max(onScreen.midX - panelOrigin.x, fill.minX + inset), fill.maxX - inset)
        case .leading, .trailing:
            return min(max(onScreen.midY - panelOrigin.y, fill.minY + inset), fill.maxY - inset)
        }
    }

    private func layoutBubble(side: Side, panelSize: CGSize, fill: CGRect, cross: CGFloat) {
        layerTxn(animated: false) {
            self.fillLayer.frame = fill
            self.fillLayer.cornerRadius = self.cornerRadius
            self.textLayer.position = CGPoint(x: fill.midX, y: fill.midY)
            self.arrowLayer.frame = CGRect(origin: .zero, size: panelSize)
            self.arrowLayer.path = self.arrowPath(side: side, fill: fill, cross: cross)
        }
    }

    /// A filled triangle pointing OUTWARD (toward the anchor), its base overlapped
    /// 1 pt into the fill so the rounded surface + arrow read seamlessly.
    private func arrowPath(side: Side, fill: CGRect, cross: CGFloat) -> CGPath {
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
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(hostGeometryChanged),
                       name: NSWindow.didMoveNotification, object: win)
        nc.addObserver(self, selector: #selector(hostGeometryChanged),
                       name: NSWindow.didResizeNotification, object: win)
        nc.addObserver(self, selector: #selector(hostWillClose),
                       name: NSWindow.willCloseNotification, object: win)
        if let clip = _anchor?.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            nc.addObserver(self, selector: #selector(hostGeometryChanged),
                           name: NSView.boundsDidChangeNotification, object: clip)
        }
    }

    private func stopGlue() { NotificationCenter.default.removeObserver(self) }

    @objc private func hostGeometryChanged() {
        guard isShown else { return }
        // Scrolled fully out of a clip view (or off the window edge) → dismiss,
        // rather than parking the bubble at a screen edge pointing at nothing.
        if let a = _anchor, a.visibleRect.isEmpty { hide(); return }
        reposition()
    }
    @objc private func hostWillClose() { hide() }

    // MARK: - Helpers

    private var backingScale: CGFloat {
        _anchor?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func layerTxn(animated: Bool, _ body: () -> Void) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.16)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        body()
        CATransaction.commit()
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
        let resolvedSide: Side
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
