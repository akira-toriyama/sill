// ThemeKit — ThemedMenu: an MUI <Menu> (basic) for the family. A themed pop-up
// menu of action rows — the floating list facet's 528-line hand-rolled `PopupMenu`
// and wand's launcher cascade both reinvent today. Themed by assigning a PaletteKit
// `ResolvedPalette`. AppKit / @MainActor.
//
// Like `ThemedTooltip` / `ThemedComboBox` (NOT an NSView), it is a CONTROLLER that
// OWNS a borderless, non-activating `PopupPanel` and HOSTS a real `ThemedList` of
// action rows. The host window stays key — the panel never becomes key — so the
// menu floats above without stealing focus. Because the panel is non-key, the list
// can't receive keyDown; the controller drives ↑↓/⏎/Esc through ONE local keyDown
// monitor (the verified mechanism — a non-key panel's list never becomes first
// responder, so there is no responder to route keys through, unlike the combo's
// embedded field).
//
// The React-component contract (the kit's mental model): the component owns render
// + interaction + theming; the HOST passes data + behavior. A `MenuItem` carries
// the title / icon / shortcut / enabled-ness AND its `action` closure (the 実処理);
// ThemedMenu maps it onto a `ThemedList` `ListItem`, and on activation runs the
// matching item's closure. The kit knows no domain — the host passes a pre-resolved
// `NSImage` and supplies the action.
//
// Mechanics lifted from the shared `PopupPanel` factory + the combo/tooltip
// precedent: `themedPopupPanel(interactive:role:)`, `placePopup` (with the new
// `.anchorCorner` / `.point` cases), `PopupFade` (monotonic-token teardown),
// `PopupGlue` (host move / resize / close / resign-key), `removeMonitorSafely`.
// The MUI Grow (a gentle scale + fade from the anchor-facing corner) is a transient
// transform on the panel content's layer (model stays identity — it never fights
// the placement's frame resets), fully gated on reduce-motion.
//
// Canonical roles only: `background` (surface) · `border` (edge / separator) ·
// `foreground` (row text) · `muted` (shortcut / chevron / header) · `tertiary`
// (disabled) · `selection` + `primary` (the `.solidAccent` highlight = opaque
// `primary` fill + `onPrimary()` ink) · `error` (a destructive item's tint).

import AppKit
import QuartzCore
import Palette
import PaletteKit

@MainActor
public final class ThemedMenu: NSObject {

    // MARK: - MenuItem

    /// One menu entry. `init(_:action:)` builds the common action row (id == title).
    /// A `.separator` / `.header` is built with the static helpers. A row carries
    /// its OWN behavior (`action`) — the React event-handler model.
    public struct MenuItem {
        public let id: String
        public var title: String
        public var icon: NSImage?            // pre-resolved leading glyph (template ⇒ tinted)
        public var shortcut: String?         // ⌘-hint, drawn as a trailing lozenge
        public var hasSubmenu: Bool          // a trailing chevron (cascade is DEFERRED — facet needs one level)
        public var isChecked: Bool           // a leading checkmark (native toggle item; suppresses `icon`)
        public var isEnabled: Bool
        public var isDestructive: Bool       // tints the leading accent bar `error` (a "Delete" row)
        public var action: (() -> Void)?
        public var kind: Kind

        public enum Kind: Equatable { case item, separator, header }

        public init(id: String, title: String, icon: NSImage? = nil, shortcut: String? = nil,
                    hasSubmenu: Bool = false, isChecked: Bool = false, isEnabled: Bool = true,
                    isDestructive: Bool = false, action: (() -> Void)? = nil) {
            self.id = id; self.title = title; self.icon = icon; self.shortcut = shortcut
            self.hasSubmenu = hasSubmenu; self.isChecked = isChecked; self.isEnabled = isEnabled
            self.isDestructive = isDestructive; self.action = action; self.kind = .item
        }
        public init(_ title: String, icon: NSImage? = nil, shortcut: String? = nil,
                    isEnabled: Bool = true, isDestructive: Bool = false, action: (() -> Void)? = nil) {
            self.init(id: title, title: title, icon: icon, shortcut: shortcut,
                      isEnabled: isEnabled, isDestructive: isDestructive, action: action)
        }

        private init(id: String, title: String, kind: Kind) {
            self.id = id; self.title = title; self.kind = kind
            self.icon = nil; self.shortcut = nil; self.hasSubmenu = false
            self.isChecked = false; self.isEnabled = false; self.isDestructive = false; self.action = nil
        }
        /// A non-interactive divider between groups. `id` only needs to be unique.
        public static func separator(id: String = "—") -> MenuItem { MenuItem(id: id, title: "", kind: .separator) }
        /// A non-interactive group label (uppercased, muted).
        public static func header(_ title: String, id: String? = nil) -> MenuItem {
            MenuItem(id: id ?? "header.\(title)", title: title, kind: .header)
        }
    }

    // MARK: - Public configuration

    /// The theme. Assigning re-themes the hosted list AND the (snapped) panel
    /// surface + edge — the mandated contract.
    public var palette: ResolvedPalette { didSet { list.palette = palette; applyTheme() } }

    /// The items. Assigning rebuilds the hosted list rows + reframes an open menu.
    public var items: [MenuItem] = [] { didSet { rebuildRows(); if isOpen { reframe() } } }

    /// Row density — `.compact` (the native-menu default, 26pt rows) or
    /// `.comfortable` (30pt, the dropdown-list metric).
    public var density: ThemedList.Density = .compact {
        didSet { list.density = density; if isOpen { reframe() } }
    }

    /// Surface behind the rows (a lifted / vibrant host sets its panel colour).
    /// Defaults to `palette.background`. A menu is always OPAQUE (you don't see
    /// through it) — a vibrancy theme (nil background) falls back to the system
    /// menu surface rather than showing the host through.
    public var surfaceColor: NSColor? { didSet { applyTheme() } }

    /// Pre-highlight the FIRST enabled row on open (a popup-button-style menu). The
    /// native default is false — an action menu opens with nothing lit until you
    /// arrow or hover (MUI's `autoFocusItem` vs NSMenu).
    public var highlightsFirstOnOpen = false

    // MARK: Callbacks

    /// Menu open / close edge.
    public var onOpenChange: ((Bool) -> Void)?

    // MARK: Preview / capture seam

    /// Force the menu OPEN against a stored `previewAnchor`, skipping the fade + the
    /// dismiss monitors — deterministic still capture + tests (the combo's
    /// `previewOpen` analogue). A child window can't be `screencapture`d, so the
    /// bench renders an inline mock for the per-theme grid; this exists for tests.
    /// BENCH/TEST-ONLY: do not toggle this on a controller that also has a live
    /// `present(...)` open — they share one open state.
    public var previewOpen = false {
        didSet {
            guard previewOpen != oldValue else { return }
            if previewOpen { presentForPreview() } else { dismiss(animated: false) }
        }
    }
    /// Anchor used by `previewOpen` when no `present(...)` target is live.
    public weak var previewAnchor: NSView?
    /// Force a highlighted row (by id) for capture/tests; nil = the live highlight.
    public var previewHighlight: String? {
        get { list.previewHighlight }
        set { list.previewHighlight = newValue }
    }

    // MARK: - Internals

    /// The hosted list, configured for menu semantics once.
    private let list: ThemedList
    private let container = NSView()             // rounded, bordered menu surface

    private var panel: PopupPanel?
    private var isOpen = false
    private var isInvalidated = false

    // Placement context (one of: an anchor view, or a screen point in a host window).
    private weak var anchorView: NSView?
    private var pointInHost: CGPoint?
    private weak var hostWindow: NSWindow?
    private var anchorGap: CGFloat = 4
    private var resolvedCorner: PopupCorner = .topLeading

    private var fadeGen = 0
    nonisolated(unsafe) private var keyMon: Any?
    nonisolated(unsafe) private var mouseMon: Any?

    /// 0.14 s fade (a hair longer than the combo's 0.12 — a menu is taller, and the
    /// Grow scale wants a beat to read) + host glue (dismiss on move / close / resign).
    private let fade = PopupFade(duration: 0.14)
    private let glue = PopupGlue()

    // Metrics (native-menu trims — MUI's 48/8 px touch metrics shrunk for macOS).
    private let cornerRadius: CGFloat = 6
    private let menuVPad: CGFloat = 4            // breathing room above/below the rows
    private let minWidth: CGFloat = 120
    private let maxWidth: CGFloat = 320
    private let maxHeight: CGFloat = 480         // taller menus scroll (NSMenu does too)
    private let growScale: CGFloat = 0.92        // a gentle native pop (MUI's 0.75 reads gimmicky on macOS)

    // Probe state (set by reframe()).
    private var lastFrame: CGRect = .zero

    // MARK: - Init

    public init(palette: ResolvedPalette) {
        self.palette = palette
        self.list = ThemedList(palette: palette)
        super.init()
        // Menu semantics: no persistent selection, opaque hover highlight that the
        // pointer AND the arrows share, MUI wrap, real per-row AX; the controller
        // owns the keys (the list must not try to be first responder).
        list.selectionMode = .none
        list.hoverStyle = .solidAccent
        list.highlightFollowsHover = true
        list.wrapsHighlight = true
        list.vendsRowAXElements = true
        list.managesFirstResponder = false
        list.density = density
        list.onActivate = { [weak self] item in self?.activate(item.id) }
        rebuildRows()
    }

    /// Build + return the RETAINED controller (one-liner ergonomics, like
    /// `ThemedTooltip.attach` / `ThemedComboBox.make`). The caller MUST retain it —
    /// the panel + monitors live as long as the controller does.
    @discardableResult
    public static func make(palette: ResolvedPalette, items: [MenuItem] = []) -> ThemedMenu {
        let m = ThemedMenu(palette: palette)
        m.items = items
        return m
    }

    // MARK: - Item → row mapping

    private func rebuildRows() {
        list.items = items.map { mi in
            switch mi.kind {
            case .separator:
                return ListItem(id: mi.id, primary: "", kind: .separator)
            case .header:
                return ListItem(id: mi.id, primary: mi.title, kind: .sectionHeader())
            case .item:
                let leading = mi.isChecked ? ThemedMenu.checkmark : mi.icon
                let trailing: TrailingAccessory = mi.hasSubmenu ? .chevron
                    : (mi.shortcut.map { .shortcut($0) } ?? .none)
                return ListItem(id: mi.id, image: leading, primary: mi.title,
                                trailing: trailing,
                                tint: mi.isDestructive ? .error : .none,
                                isDisabled: !mi.isEnabled, axChecked: mi.isChecked)
            }
        }
    }

    /// A template checkmark glyph — the list tints it to `foreground` (resting) /
    /// `onPrimary` (highlighted), so it re-themes with the palette (a native menu
    /// check is the control text colour, not an accent).
    private static let checkmark: NSImage? = {
        guard let base = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "checked") else { return nil }
        let out = base.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold)) ?? base
        out.isTemplate = true
        return out
    }()

    // MARK: - Theming

    public func applyTheme() {
        // Paint the OPAQUE menu surface on BOTH the list and the container (the
        // container shows in the vertical-padding strips + carries the rounded
        // edge), so the menu reads as one seamless opaque card on every theme.
        list.surfaceColor = menuSurface
        // Snap the panel surface / edge (these CALayer props would otherwise
        // implicitly cross-fade on a theme switch — combo parity).
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.layer?.backgroundColor = menuSurface.cgColor
        container.layer?.borderColor = palette.border.cgColor
        CATransaction.commit()
    }

    private var menuSurface: NSColor { surfaceColor ?? palette.background ?? .textBackgroundColor }

    // MARK: - Present (drop-down from an anchor, or a context menu at a point)

    /// Open the menu as a drop-down below `anchor` (flipping above on underflow).
    public func present(from anchor: NSView, gap: CGFloat = 4) {
        guard anchor.window != nil else { return }
        anchorView = anchor
        pointInHost = nil
        hostWindow = anchor.window
        anchorGap = gap
        open(animated: !reduceMotion)
    }

    /// Open the menu as a context menu at `point` (in `window`'s coordinates —
    /// e.g. from `event.locationInWindow`), growing down-right from the point.
    public func present(at point: CGPoint, in window: NSWindow) {
        anchorView = nil
        pointInHost = point
        hostWindow = window
        open(animated: !reduceMotion, deferMouseMonitor: true)   // let the opening click pass first
    }

    /// Close the menu (idempotent).
    public func dismiss(animated: Bool = true) {
        guard isOpen else { return }
        isOpen = false
        removeKeyMonitor()
        removeMouseMonitor()
        glue.stop()
        list.clearHighlight()
        fadeOut(animated: animated && !reduceMotion)
        onOpenChange?(false)
    }

    /// Deterministic teardown — idempotent; also reached from `deinit`.
    public func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        removeKeyMonitor()
        removeMouseMonitor()
        glue.stop()
        panel?.orderOut(nil)
        panel = nil
        isOpen = false
    }

    private func presentForPreview() {
        guard let anchor = previewAnchor, anchor.window != nil else { return }
        anchorView = anchor
        pointInHost = nil
        hostWindow = anchor.window
        anchorGap = 4
        open(animated: false, installDismiss: false)
    }

    private func open(animated: Bool, installDismiss: Bool = true, deferMouseMonitor: Bool = false) {
        guard !isInvalidated, hostWindow != nil else { return }
        if isOpen {                                     // idempotent re-show
            reframe()
            if installDismiss { startGlue() }           // rebind glue to the (possibly new) host / anchor
            return
        }
        fadeGen &+= 1
        ensurePanel()
        isOpen = true
        rebuildRows()                                   // never open stale
        if installDismiss { list.previewHighlight = nil }   // the preview path keeps a caller-set highlight
        list.clearHighlight()
        if highlightsFirstOnOpen { list.moveHighlight(1) }
        reframe()
        panel?.orderFrontRegardless()                   // NEVER makeKey — keep the host's focus
        if installDismiss {
            installKeyMonitor()
            installMouseMonitor(deferred: deferMouseMonitor)
            startGlue()
        }
        growIn(animated: animated)
        onOpenChange?(true)
    }

    // MARK: - Panel + layout

    private func ensurePanel() {
        guard panel == nil else { return }
        let p = themedPopupPanel(interactive: true, role: .menu)
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        container.addSubview(list)
        p.contentView = container
        p.contentView?.setAccessibilityElement(true)    // the popup IS a menu (role set by the factory)
        panel = p
        applyTheme()
    }

    /// The menu's size from its content: width = the widest row clamped to
    /// [minWidth, maxWidth]; height = the rows + the vertical padding, capped at
    /// `maxHeight` (overflow scrolls).
    private func menuSize() -> CGSize {
        let contentW = list.fittingWidth(maxWidth: maxWidth - 2)
        let width = min(maxWidth, max(minWidth, contentW + 2))      // +2 for the 1pt border L/R
        let rows = list.contentHeight
        let height = min(maxHeight, rows + 2 * (1 + menuVPad))       // border + vpad, top & bottom
        return CGSize(width: width, height: height)
    }

    private func reframe() {
        guard let panel, let host = hostWindow else { return }
        let size = menuSize()

        let result: PopupPlacementResult?
        if let anchor = anchorView {
            let onScreen = host.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            result = placePopup(panel, anchorRectOnScreen: onScreen, .anchorCorner(size: size, gap: anchorGap))
        } else if let p = pointInHost {
            let onScreen = host.convertToScreen(CGRect(origin: p, size: .zero))
            result = placePopup(panel, anchorRectOnScreen: onScreen, .point(onScreen.origin, size: size))
        } else {
            return
        }

        let frame: CGRect
        switch result {
        case let .anchorCorner(f, corner): frame = f; resolvedCorner = corner
        case let .point(f, corner):        frame = f; resolvedCorner = corner
        default: return
        }

        // Lay out the inner tree (panel content is NOT flipped → y-up; the list
        // sits inside the 1pt border with `menuVPad` above/below).
        container.frame = CGRect(origin: .zero, size: frame.size)
        list.frame = CGRect(x: 1, y: 1 + menuVPad,
                            width: frame.size.width - 2,
                            height: frame.size.height - 2 * (1 + menuVPad))

        let s = host.backingScaleFactor
        container.layer?.contentsScale = s

        lastFrame = frame
    }

    // MARK: - Activation

    private func activate(_ id: String) {
        guard let mi = items.first(where: { $0.id == id }), mi.isEnabled, mi.kind == .item else { return }
        // Close FIRST (so the action may freely re-present a menu / mutate state),
        // then run the host's behavior. The panel is non-key, so there is no first
        // responder to restore — order-out then act.
        dismiss(animated: false)
        mi.action?()
    }

    // MARK: - Keyboard (ONE local keyDown monitor — the panel is non-key)

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMon = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            self?.handleKeyDown(ev) ?? ev
        }
    }

    /// Route a keyDown while the menu is open. Returns nil to SWALLOW the keys the
    /// menu OWNS (↑↓ nav, ⏎/Space activate, Esc dismiss) so the host's first
    /// responder doesn't also act on them; returns the event UNCHANGED for Tab (and
    /// everything else — letters, cmd-combos, an active IME marked-text session) so
    /// the host keeps working. The single source of truth (the monitor + tests both
    /// call it).
    func handleKeyDown(_ ev: NSEvent) -> NSEvent? {
        guard isOpen else { return ev }
        switch ev.keyCode {
        case 125: list.moveHighlight(1);  return nil    // ↓
        case 126: list.moveHighlight(-1); return nil    // ↑
        case 36, 76, 49: list.activateHighlight(); return nil   // ⏎ / keypad ⏎ / Space
        case 53:  dismiss(); return nil                 // Esc — swallow
        case 48:  dismiss(); return ev                  // Tab — dismiss, don't trap focus
        default:  return ev                             // pass everything else through (host IME, etc.)
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMon { NSEvent.removeMonitor(m); keyMon = nil }
    }

    // MARK: - Outside-click dismiss (one local mouseDown monitor)

    private func installMouseMonitor(deferred: Bool) {
        removeMouseMonitor()
        // For a context menu opened BY a click, arm on the next runloop turn so the
        // triggering click can't immediately self-dismiss the menu.
        if deferred {
            DispatchQueue.main.async { [weak self] in self?.armMouseMonitor() }
        } else {
            armMouseMonitor()
        }
    }

    private func armMouseMonitor() {
        guard isOpen, mouseMon == nil else { return }
        mouseMon = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] ev in
            guard let self else { return ev }
            if !self.clickIsInside(ev) { self.dismiss() }
            return ev                                           // never swallow (a row click must reach the panel)
        }
    }

    private func removeMouseMonitor() {
        if let m = mouseMon { NSEvent.removeMonitor(m); mouseMon = nil }
    }

    /// A click is "inside" when it lands on the panel OR (for a drop-down) on the
    /// anchor view — so the click that opened the menu / toggled the anchor doesn't
    /// instantly dismiss it.
    private func clickIsInside(_ ev: NSEvent) -> Bool {
        if ev.window === panel { return true }
        if let anchor = anchorView, ev.window === anchor.window {
            let p = anchor.convert(ev.locationInWindow, from: nil)
            return anchor.bounds.contains(p)
        }
        return false
    }

    // MARK: - Glue (dismiss on host move / resize / close / resign-key)

    private func startGlue() {
        guard let host = hostWindow else { return }
        glue.start(window: host, clip: anchorView?.enclosingScrollView?.contentView,
                   onGeometryChange: { [weak self] in self?.hostGeometryChanged() },
                   onClose: { [weak self] in self?.dismiss(animated: false) },
                   onResignKey: { [weak self] in
                       guard let self, self.isOpen else { return }
                       self.dismiss(animated: false)
                   })
    }

    private func hostGeometryChanged() {
        guard isOpen else { return }
        // A drop-down tracks its anchor (dismiss if it scrolled out of a clip); a
        // context menu at a fixed point has no anchor to follow → dismiss.
        if let anchor = anchorView {
            if anchor.visibleRect.isEmpty { dismiss(); return }
            reframe()
        } else {
            dismiss()
        }
    }

    // MARK: - Grow (corner-anchored scale + fade; reduce-motion gated)

    private func growIn(animated: Bool) {
        guard let cl = container.layer else { return }
        if !animated {
            fade.fadeIn(cl, animated: false)            // snap to opacity 1, identity transform
            return
        }
        // Opacity AND a transient corner-anchored scale in ONE transaction (MUI Grow,
        // simultaneous). The transform's MODEL stays identity (only an animation) so
        // a placement reframe mid-Grow never fights it.
        let from = ThemedMenu.growTransform(about: cornerPoint(in: cl.bounds), scale: growScale, bounds: cl.bounds)
        cl.opacity = 0
        CATransaction.begin()
        CATransaction.setAnimationDuration(fade.duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        cl.opacity = 1                                  // implicit fade (model → 1)
        let grow = CABasicAnimation(keyPath: "transform")
        grow.fromValue = NSValue(caTransform3D: from)
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        grow.duration = fade.duration
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        grow.isRemovedOnCompletion = true
        cl.add(grow, forKey: "grow")
        CATransaction.commit()
    }

    private func fadeOut(animated: Bool) {
        guard let panel, let cl = container.layer else { return }
        let gen = fadeGen
        fade.fadeOut(cl, panel: panel, animated: animated) { [weak self] in
            guard let self else { return false }
            return self.fadeGen == gen && !self.isOpen
        }
    }

    /// The pinned corner in the (UN-FLIPPED, y-up) layer space — the Grow origin.
    private func cornerPoint(in bounds: CGRect) -> CGPoint {
        let w = bounds.width, h = bounds.height
        switch resolvedCorner {
        case .topLeading:     return CGPoint(x: 0, y: h)
        case .topTrailing:    return CGPoint(x: w, y: h)
        case .bottomLeading:  return CGPoint(x: 0, y: 0)
        case .bottomTrailing: return CGPoint(x: w, y: 0)
        }
    }

    /// Scale by `s` ABOUT a corner `c` while the layer's anchor stays its centre:
    /// translate(c−centre) · scale(s) · translate(−(c−centre)). Pins `c`, grows the
    /// body toward it — no anchorPoint mutation (which AppKit would stomp on the
    /// next frame reset).
    static func growTransform(about c: CGPoint, scale s: CGFloat, bounds: CGRect) -> CATransform3D {
        let dx = c.x - bounds.midX, dy = c.y - bounds.midY
        var m = CATransform3DIdentity
        m = CATransform3DTranslate(m, dx, dy, 0)
        m = CATransform3DScale(m, s, s, 1)
        m = CATransform3DTranslate(m, -dx, -dy, 0)
        return m
    }

    // MARK: - Helpers

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    deinit {
        removeMonitorSafely(keyMon)
        removeMonitorSafely(mouseMon)
    }
}

#if DEBUG
// Test-only window into the resolved menu — open state, row mapping, placement
// corner, monitor lifecycle, AX — asserted via `previewOpen`/`previewHighlight`
// + the public callbacks (no synthetic events). Same-file extension so it reads
// the private state; not built into release.
extension ThemedMenu {
    struct MenuProbe {
        let isOpen: Bool
        let rowCount: Int                 // hosted-list row count (incl. separators / headers)
        let highlightedID: String?
        let resolvedCorner: PopupCorner
        let menuFrame: CGRect
        let panelOrderedIn: Bool
        let hasKeyMonitor: Bool
        let hasMouseMonitor: Bool
        let axMenuItemLabels: [String]    // synthetic per-row AX labels (actionable rows only)
        let hasOpacityAnimation: Bool
        let reduceMotionRespected: Bool
    }
    var menuProbe: MenuProbe {
        let animating = container.layer?.animation(forKey: "opacity") != nil
        return MenuProbe(
            isOpen: isOpen,
            rowCount: list.listProbe.rowCount,
            highlightedID: list.highlightedID,
            resolvedCorner: resolvedCorner,
            menuFrame: lastFrame,
            panelOrderedIn: panel?.isVisible ?? false,
            hasKeyMonitor: keyMon != nil,
            hasMouseMonitor: mouseMon != nil,
            axMenuItemLabels: list._axChildren().compactMap { $0.accessibilityLabel() },
            hasOpacityAnimation: animating,
            reduceMotionRespected: !(reduceMotion && animating))
    }
    /// The hosted list (drive its probe / nav directly in tests).
    var _list: ThemedList { list }
    /// Activate a row by id as if clicked (fires the item's action + dismisses).
    func _activate(_ id: String) { activate(id) }
    /// Route a keyDown through the REAL monitor logic (swallow-vs-passthrough).
    func _handleKey(_ ev: NSEvent) -> NSEvent? { handleKeyDown(ev) }
}
#endif
