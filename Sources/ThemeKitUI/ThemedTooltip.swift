// ThemeKitUI — ThemedTooltip: a passive, pointer-driven tooltip (MUI <Tooltip>,
// basic). A small inverted-surface bubble on a free, borderless, non-activating
// `NSPanel` that floats ABOVE the host window — it must draw outside the
// anchor's clip / bounds, so it is a per-anchor CONTROLLER (not an NSView
// wrapper). Themed by assigning a PaletteKit `ResolvedPalette`. AppKit is the
// permitted floor-2 SHELL only; the bubble CONTENT is SwiftUI (`TooltipBubble`
// in an `NSHostingView` — the floor-2 discipline; it replaced the CALayer trio
// under the 2026-08-02 ruling). SwiftUI hosts attach via `.themedTooltip(_:)`,
// which anchors through the shared `PopupAnchorProxy`.
//
// Sill's FIRST owned child window (it LIFTED facet's KeyablePanel / PopupMenu
// child-window ideas — sill must never depend on facet). The shared factory that
// grew out of it — `themedPopupPanel(...)` / `placePopup(...)` — is what this,
// ThemedComboBox and ThemedMenu all consume today (`PopupPanel.swift`, moved to
// ThemeKitUI with the widgets at the #17b M5 retire).
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
//   * Panel GEOMETRY stays measured on the AppKit side (`boundingRect` of the
//     attributed text): `placePopup` needs the size BEFORE SwiftUI lays out,
//     and keeping the measurement unchanged keeps every placement/flip/clamp
//     byte-identical to the CALayer implementation it replaced.

import AppKit
import SwiftUI
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
    /// `previewFocused`). The panel is a child window, so a static capture of
    /// the HOST window still won't include it — prism's grid draws the real
    /// bubble in-window via `previewBubble` instead; this seam freezes the
    /// live panel for tests and interactive (AX) verification.
    public var previewVisible = false {
        didSet {
            guard previewVisible != oldValue else { return }
            if previewVisible { present(animated: false) } else { hide() }
        }
    }

    nonisolated(unsafe) private weak var _anchor: NSView?
    nonisolated(unsafe) private var trackingArea: NSTrackingArea?

    /// The SwiftUI bubble host — the floor-2 "contents go through NSHostingView"
    /// discipline. Built with the panel; its root view is re-assigned on every
    /// rebuild / reposition.
    private var hosting: NSHostingView<TooltipBubble>?

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

    public init(anchor: NSView, text: String, palette: ResolvedPalette,
                placement: Placement = .auto) {
        self._anchor = anchor
        self.text = text
        self.palette = palette
        self.placement = placement
        super.init()

        installTrackingArea(on: anchor)
        anchor.toolTip = nil                       // no native double-fire
        anchor.setAccessibilityHelp(text.isEmpty ? nil : text)  // VoiceOver reaches text via the anchor
        rebuild()
    }

    /// Tear down the tracking area whose owner (self) is unretained, so a later
    /// mouse event can't message a freed controller. `removeTrackingArea` is
    /// @MainActor: on the main thread we assume isolation; if the controller is
    /// somehow released off-main we bounce the removal to main (laundering the
    /// non-Sendable tracking area through a `nonisolated(unsafe)` local — it is
    /// dead in this object, so there is no real concurrent access, and the work
    /// runs ON main where the call is valid). Releasing `panel` clears the screen.
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        guard let a = _anchor, let t = trackingArea else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { a.removeTrackingArea(t) }
        } else {
            let view = a
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

    private func ensurePanel() {
        guard panel == nil else { return }
        // Passive bubble: click-through + out of AX (VoiceOver reaches the text via
        // the anchor's accessibilityHelp instead).
        let p = themedPopupPanel(interactive: false, role: .unknown)
        let host = NSHostingView(rootView: bubble())
        host.wantsLayer = true                     // the PopupFade surface
        hosting = host
        p.contentView = host
        p.contentView?.setAccessibilityElement(false)
        panel = p
    }

    private func fadeIn(animated: Bool) {
        guard let panel, let hl = hosting?.layer else { return }
        panel.orderFrontRegardless()         // NEVER makeKey — must not steal focus
        fade.fadeIn(hl, animated: animated)
    }

    private func fadeOut(animated: Bool) {
        guard let panel, let hl = hosting?.layer else { return }
        // Order out only if this fade still stands (no re-show superseded it).
        let gen = fadeGen
        fade.fadeOut(hl, panel: panel, animated: animated) { [weak self] in
            guard let self else { return false }
            return self.fadeGen == gen && !self.isShown
        }
    }

    // MARK: - Content (measure the text; the drawing is the SwiftUI bubble)

    // Fonts via `palette.uiFont(_:)` — the shared type-scale resolver
    // (honours .mono/.rounded/.menu; the old local helper dropped two).

    /// The inverted surface — `foreground @ 0.92`. A dark bubble on a light
    /// theme, a light one on a dark / neon theme, theme-robustly.
    private var fillColor: NSColor { palette.foreground.withAlphaComponent(0.92) }
    /// Best-contrast ink on the (opaque) foreground.
    private var textColor: NSColor { palette.bestContrast(on: palette.foreground) }

    /// The current bubble model — everything the SwiftUI content needs to draw
    /// the committed placement.
    private func bubble() -> TooltipBubble {
        TooltipBubble(text: text, font: palette.uiFont(.tooltip),
                      fill: fillColor, ink: textColor,
                      side: resolvedSide, cross: lastArrowCross, fillSize: fillSize,
                      cornerRadius: cornerRadius, hpad: hpad, vpad: vpad,
                      arrowBase: arrowBase, arrowLen: arrowLen)
    }

    /// The REAL bubble as a self-sized in-window SwiftUI view — the bench seam.
    /// The panel is a child window a static capture of the host window can never
    /// include, so prism draws THIS instead of a hand-copied mock (a mock is a
    /// picture of nothing: drift there is exactly the blindness the bench exists
    /// to catch). Runs the controller's own measurement + model pipeline; the
    /// arrow apex is centred on the cross axis (the canonical resting pose — a
    /// live bubble re-points it at the anchor).
    package static func previewBubble(text: String, palette: ResolvedPalette,
                                      placement: Placement) -> some View {
        let anchor = NSView()                     // measurement needs no window
        let tip = ThemedTooltip(anchor: anchor, text: text, palette: palette,
                                placement: placement)   // init runs rebuild()
        let side = tip.resolvePreferred(placement)      // preview = no flip
        tip.resolvedSide = side
        switch side {
        case .top, .bottom:       tip.lastArrowCross = tip.fillSize.width / 2
        case .leading, .trailing: tip.lastArrowCross = tip.fillSize.height / 2
        }
        let size = popupPanelSize(side, fill: tip.fillSize, arrowLen: tip.arrowLen)
        return tip.bubble().frame(width: size.width, height: size.height)
    }

    /// Re-measure the text, refresh the bubble content, and reposition a shown
    /// bubble. Measurement stays on the AppKit side (`boundingRect`) — the
    /// placement engine needs the size before SwiftUI lays out.
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
        fillSize = CGSize(width: ceil(bound.width) + 2 * hpad,
                          height: ceil(bound.height) + 2 * vpad)
        hosting?.rootView = bubble()
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

        // Commit the placement into the SwiftUI content (the arrow re-points at
        // the anchor except within a corner-clear inset).
        let fill = fillRect(in: frame.size, side: side)
        let cross = arrowCross(side: side, onScreen: onScreen, panelOrigin: frame.origin, fill: fill)

        resolvedSide = side
        lastBubbleFrame = frame
        lastArrowCross = cross
        hosting?.rootView = bubble()
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
    /// remaining strip on the anchor-facing edge. Used for the cross-axis clamp;
    /// the SwiftUI bubble derives its own (y-down) twin from the same inputs.
    private func fillRect(in size: CGSize, side: PopupSide) -> CGRect {
        switch side {
        case .bottom:   return CGRect(x: 0,        y: 0,       width: fillSize.width, height: fillSize.height)  // arrow on top
        case .top:      return CGRect(x: 0,        y: arrowLen, width: fillSize.width, height: fillSize.height) // arrow on bottom
        case .leading:  return CGRect(x: 0,        y: 0,       width: fillSize.width, height: fillSize.height)  // arrow on right
        case .trailing: return CGRect(x: arrowLen, y: 0,       width: fillSize.width, height: fillSize.height)  // arrow on left
        }
    }

    /// Arrow centre on the cross axis (panel-local, Y-UP), clamped clear of the
    /// rounded corners so it always reads as one shape — pointed at the anchor
    /// centre, or as close as the corner-clear inset allows when the anchor sits
    /// within (cornerRadius + arrowBase/2) of a corner.
    private func arrowCross(side: PopupSide, onScreen: CGRect, panelOrigin: CGPoint, fill: CGRect) -> CGFloat {
        let inset = cornerRadius + arrowBase / 2
        switch side {
        case .top, .bottom:
            return min(max(onScreen.midX - panelOrigin.x, fill.minX + inset), fill.maxX - inset)
        case .leading, .trailing:
            return min(max(onScreen.midY - panelOrigin.y, fill.minY + inset), fill.maxY - inset)
        }
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

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

// MARK: - The SwiftUI bubble content (floor 2: shell AppKit, contents SwiftUI)

/// The drawn bubble: one path (rounded inverted fill + the anchor-facing arrow,
/// base overlapped 1 pt into the fill so they read seamlessly) plus the wrapped,
/// centred label. Laid out in the PANEL's coordinate space (top-left origin) —
/// the controller commits `side` / `cross` / `fillSize` from the placement
/// engine, so this view is a pure function of the committed placement.
struct TooltipBubble: View {
    let text: String
    let font: NSFont
    let fill: NSColor
    let ink: NSColor
    let side: PopupSide
    let cross: CGFloat          // arrow apex on the cross axis, panel-local Y-UP
    let fillSize: CGSize
    let cornerRadius: CGFloat
    let hpad: CGFloat
    let vpad: CGFloat
    let arrowBase: CGFloat
    let arrowLen: CGFloat

    private var panelSize: CGSize { popupPanelSize(side, fill: fillSize, arrowLen: arrowLen) }

    /// The fill surface in the view's (y-down) space — the y-flipped twin of the
    /// controller's y-up `fillRect`.
    private var fillFrame: CGRect {
        switch side {
        case .bottom:   return CGRect(x: 0, y: arrowLen, width: fillSize.width, height: fillSize.height)  // arrow on top
        case .top:      return CGRect(x: 0, y: 0, width: fillSize.width, height: fillSize.height)         // arrow on bottom
        case .leading:  return CGRect(x: 0, y: 0, width: fillSize.width, height: fillSize.height)         // arrow on right
        case .trailing: return CGRect(x: arrowLen, y: 0, width: fillSize.width, height: fillSize.height)  // arrow on left
        }
    }

    /// The arrow apex on the cross axis, y-flipped for a horizontal side (the
    /// cross is an x for top/bottom — no flip — and a y-up y for leading/trailing).
    private var crossYDown: CGFloat {
        switch side {
        case .top, .bottom:       return cross
        case .leading, .trailing: return panelSize.height - cross
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TooltipBubbleShape(side: side, fill: fillFrame, cross: crossYDown,
                               cornerRadius: cornerRadius,
                               arrowBase: arrowBase, arrowLen: arrowLen)
                .fill(Color(nsColor: fill))
            // Width-only constraint (the AppKit-measured wrap width) + centre
            // via `.position`: clamping the HEIGHT to the measured value too
            // makes SwiftUI truncate to "…" whenever its line height lands a
            // hair over the TextKit measurement (found in the before/after
            // raster comparison, 2026-08-02).
            Text(text)
                .font(Font(font as CTFont))
                .foregroundStyle(Color(nsColor: ink))
                .multilineTextAlignment(.center)
                .frame(width: fillSize.width - 2 * hpad)
                .position(x: fillFrame.midX, y: fillFrame.midY)
        }
        .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
    }
}

/// Rounded fill + the outward-pointing triangle as ONE path (nonzero fill), the
/// triangle's base overlapped 1 pt into the fill. Geometry in y-down view space.
struct TooltipBubbleShape: Shape {
    let side: PopupSide
    let fill: CGRect
    let cross: CGFloat          // apex centre on the cross axis, y-down
    let cornerRadius: CGFloat
    let arrowBase: CGFloat
    let arrowLen: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: fill, cornerRadius: cornerRadius)
        let b = arrowBase, len = arrowLen, ov: CGFloat = 1
        var t = Path()
        switch side {
        case .bottom:   // bubble below the anchor — arrow on the TOP edge, pointing up
            t.move(to: CGPoint(x: cross - b / 2, y: fill.minY + ov))
            t.addLine(to: CGPoint(x: cross + b / 2, y: fill.minY + ov))
            t.addLine(to: CGPoint(x: cross, y: fill.minY - len))
        case .top:      // arrow on the BOTTOM edge, pointing down
            t.move(to: CGPoint(x: cross - b / 2, y: fill.maxY - ov))
            t.addLine(to: CGPoint(x: cross + b / 2, y: fill.maxY - ov))
            t.addLine(to: CGPoint(x: cross, y: fill.maxY + len))
        case .leading:  // arrow on the RIGHT edge, pointing right
            t.move(to: CGPoint(x: fill.maxX - ov, y: cross - b / 2))
            t.addLine(to: CGPoint(x: fill.maxX - ov, y: cross + b / 2))
            t.addLine(to: CGPoint(x: fill.maxX + len, y: cross))
        case .trailing: // arrow on the LEFT edge, pointing left
            t.move(to: CGPoint(x: fill.minX + ov, y: cross - b / 2))
            t.addLine(to: CGPoint(x: fill.minX + ov, y: cross + b / 2))
            t.addLine(to: CGPoint(x: fill.minX - len, y: cross))
        }
        t.closeSubpath()
        p.addPath(t)
        return p
    }
}

// MARK: - The SwiftUI attachment (`.themedTooltip`)

public extension View {
    /// Attach a themed tooltip to ANY SwiftUI view. The bubble floats on its
    /// own non-activating child window (floor 2), anchored through the shared
    /// invisible `PopupAnchorProxy` laid under this view — hover the view to
    /// show it after the enter delay. Palette: explicit argument > ambient
    /// `.sillTheme(_:)` > the process default.
    func themedTooltip(_ text: String, palette: ResolvedPalette? = nil,
                       placement: ThemedTooltip.Placement = .auto) -> some View {
        modifier(ThemedTooltipModifier(text: text, explicitPalette: palette,
                                       placement: placement))
    }

    /// The capture/test variant: `previewVisible` freezes the live bubble shown
    /// (skipping hover delays and the fade) — the controller `previewVisible`
    /// seam surfaced on the SwiftUI front. The bubble still floats on its child
    /// window, so a static capture of the HOST window won't include it; for the
    /// in-window bench cell see `ThemedTooltip.previewBubble`.
    func themedTooltip(_ text: String, palette: ResolvedPalette? = nil,
                       placement: ThemedTooltip.Placement = .auto,
                       previewVisible: Bool) -> some View {
        modifier(ThemedTooltipModifier(text: text, explicitPalette: palette,
                                       placement: placement,
                                       previewVisible: previewVisible))
    }
}

struct ThemedTooltipModifier: ViewModifier {
    @Environment(\.sillPalette) private var ambientPalette
    let text: String
    let explicitPalette: ResolvedPalette?
    let placement: ThemedTooltip.Placement
    var previewVisible = false

    private var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }

    func body(content: Content) -> some View {
        content.background(PopupAnchorProxy<ThemedTooltip>(
            attach: { [text, placement, palette] anchor in
                ThemedTooltip.attach(to: anchor, text: text, palette: palette,
                                     placement: placement)
            },
            update: { [text, placement, palette, previewVisible] tip, anchor in
                tip.text = text
                tip.palette = palette
                tip.placement = placement
                // Only assert the preview once the anchor sits in a window —
                // `present` needs one, and the proxy re-runs this closure on
                // window attach, so an early `true` is not lost.
                tip.previewVisible = previewVisible && anchor.window != nil
            },
            detach: { $0.invalidate() }))
    }
}

#if DEBUG
// Test-only window into the resolved bubble — placement (POST flip / clamp),
// colours, arrow point, AX — so a deterministic test can assert them via
// `previewVisible` without synthetic mouse events. Same-file extension so it can
// read the private state; not built into release. The colour fields are the
// MODEL the SwiftUI bubble draws from (the drawn pixels themselves are covered
// by `ThemedTooltipRenderTests` on `TooltipBubble`).
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
        let animating = hosting?.layer?.animation(forKey: "opacity") != nil
        return TooltipProbe(
            isVisible: isShown,
            resolvedSide: resolvedSide,
            fillColor: fillColor.cgColor,
            textColor: textColor.cgColor,
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
