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
        public var hasSubmenu: Bool          // a trailing chevron; auto-true when `submenu` is non-empty
        public var isChecked: Bool           // a leading checkmark (native toggle item; suppresses `icon`)
        public var isEnabled: Bool
        public var isDestructive: Bool       // tints the leading accent bar `error` (a "Delete" row)
        public var action: (() -> Void)?
        /// Child rows. Non-empty ⇒ this row opens a ONE-LEVEL cascade (the kit caps
        /// at one level): hover / `→` / click opens a child menu beside the row; its
        /// own rows' `submenu` is ignored (no grandchildren). A submenu row's own
        /// `action` is ignored — opening the child IS its activation.
        public var submenu: [MenuItem]
        public var kind: Kind

        public enum Kind: Equatable { case item, separator, header }

        public init(id: String, title: String, icon: NSImage? = nil, shortcut: String? = nil,
                    hasSubmenu: Bool = false, isChecked: Bool = false, isEnabled: Bool = true,
                    isDestructive: Bool = false, submenu: [MenuItem] = [], action: (() -> Void)? = nil) {
            self.id = id; self.title = title; self.icon = icon; self.shortcut = shortcut
            self.hasSubmenu = hasSubmenu || !submenu.isEmpty
            self.isChecked = isChecked; self.isEnabled = isEnabled
            self.isDestructive = isDestructive; self.submenu = submenu; self.action = action; self.kind = .item
        }
        public init(_ title: String, icon: NSImage? = nil, shortcut: String? = nil,
                    isEnabled: Bool = true, isDestructive: Bool = false,
                    submenu: [MenuItem] = [], action: (() -> Void)? = nil) {
            self.init(id: title, title: title, icon: icon, shortcut: shortcut,
                      isEnabled: isEnabled, isDestructive: isDestructive, submenu: submenu, action: action)
        }

        private init(id: String, title: String, kind: Kind) {
            self.id = id; self.title = title; self.kind = kind
            self.icon = nil; self.shortcut = nil; self.hasSubmenu = false
            self.isChecked = false; self.isEnabled = false; self.isDestructive = false
            self.submenu = []; self.action = nil
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
    public var items: [MenuItem] = [] { didSet { rebuildRows(); if isOpen { reframe(); validateOpenChild() } } }

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

    // Submenu cascade (ONE level). A submenu row owns a CHILD ThemedMenu placed beside
    // it; the ROOT owns ALL keyboard / mouse / glue, so a child installs none of them.
    // `parentMenu` is set on a child (≠ nil ⇒ this menu is a submenu and will NOT open
    // grandchildren — the one-level cap). `submenuRowOnScreen` is a child's placement
    // anchor (its parent row's screen rect).
    private weak var parentMenu: ThemedMenu?
    private var child: ThemedMenu?
    private var childRowID: String?
    private var submenuRowOnScreen: CGRect?
    private var hoverWork: DispatchWorkItem?
    private let submenuHoverDelay: TimeInterval = 0.16

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
        list.onHover = { [weak self] id in self?.handleHover(id) }
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
    private static let checkmark: NSImage? = phosphorImage("check", pt: 12, weight: .bold)

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
        closeChild()                                    // tear the whole cascade down first
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
        hoverWork?.cancel(); hoverWork = nil
        child?.invalidate(); child = nil; childRowID = nil
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
        } else if let rowRect = submenuRowOnScreen {
            // A child menu beside its parent row (the row's rect is already on-screen,
            // captured at open from the parent's list); gap 2 so it reads connected.
            result = placePopup(panel, anchorRectOnScreen: rowRect, .submenu(size: size, gap: 2))
        } else {
            return
        }

        let frame: CGRect
        switch result {
        case let .anchorCorner(f, corner): frame = f; resolvedCorner = corner
        case let .point(f, corner):        frame = f; resolvedCorner = corner
        case let .submenu(f, corner):      frame = f; resolvedCorner = corner
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
        if !mi.submenu.isEmpty {
            // A submenu row: opening the child IS its activation (its own `action` is
            // ignored). Light the child's first row so ⏎-into-submenu reads naturally.
            openSubmenu(rowID: id, highlightFirst: true)
            return
        }
        // A leaf row: close the WHOLE chain (root + any open child) so the action may
        // freely re-present a menu / mutate state, THEN run the host's behavior. The
        // panels are non-key, so there is no first responder to restore — order-out, act.
        rootMenu().dismiss(animated: false)
        mi.action?()
    }

    // MARK: - Submenu cascade (ONE level; the ROOT owns all monitors / glue)

    /// Pointer rested on row `id` (nil ⇒ left the rows). Open a hovered submenu row's
    /// child after a short intent delay; collapse an open child when the pointer rests
    /// on a DIFFERENT row. A nil id (pointer between the panels — e.g. travelling INTO
    /// the open child) is IGNORED so the child stays put.
    private func handleHover(_ id: String?) {
        guard parentMenu == nil else { return }         // only the root drives the cascade
        hoverWork?.cancel(); hoverWork = nil
        guard let id else { return }                    // left the rows — keep any open child
        let isSubmenuRow = items.first(where: { $0.id == id })?.submenu.isEmpty == false
        if isSubmenuRow {
            if childRowID == id, child?.isOpen == true { return }   // already showing this one
            schedule { [weak self] in self?.openSubmenu(rowID: id, highlightFirst: false) }
        } else if child != nil {
            schedule { [weak self] in self?.closeChild() }          // collapse on a non-submenu row
        }
    }

    private func schedule(_ body: @escaping () -> Void) {
        let work = DispatchWorkItem(block: body)
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + submenuHoverDelay, execute: work)
    }

    /// Open (or re-target) the submenu child for parent row `id`, placed beside it.
    /// No-op on a child (the one-level cap) or a disabled / non-submenu / off-screen row.
    private func openSubmenu(rowID id: String, highlightFirst: Bool) {
        guard parentMenu == nil else { return }         // a child opens no grandchild
        hoverWork?.cancel(); hoverWork = nil
        guard isOpen, let host = hostWindow,
              let mi = items.first(where: { $0.id == id }), mi.isEnabled, !mi.submenu.isEmpty,
              let rowRect = list.rowRectOnScreen(for: id) else { return }
        if childRowID == id, child?.isOpen == true {                // already showing this one
            if highlightFirst { child?.list.moveHighlight(1) }      // re-light its first row (Enter/→ intent)
            return
        }
        closeChild()
        let c = ThemedMenu(palette: palette)
        c.parentMenu = self
        c.surfaceColor = surfaceColor
        c.highlightsFirstOnOpen = false
        c.density = density
        c.items = mi.submenu
        child = c
        childRowID = id
        c.presentAsSubmenu(rowRectOnScreen: rowRect, in: host)
        if highlightFirst { c.list.moveHighlight(1) }
    }

    /// Collapse the open submenu child (idempotent). Cancels a pending hover-intent.
    private func closeChild() {
        hoverWork?.cancel(); hoverWork = nil
        guard let c = child else { return }
        child = nil
        childRowID = nil
        c.teardownAsChild()
    }

    /// Close THIS menu as a submenu child: collapse any descendant, drop the highlight,
    /// snap the panel out. It installed NO monitors / glue (the root owns them), so
    /// there is nothing to remove.
    private func teardownAsChild() {
        closeChild()
        guard isOpen else { return }
        isOpen = false
        list.clearHighlight()
        fadeOut(animated: false)
        submenuRowOnScreen = nil
    }

    /// Keep an open child glued to its parent row when the parent relayouts (it
    /// scrolled, or its items changed): re-anchor the child to the row's new screen
    /// rect, or close it if the row vanished / is no longer a submenu. Root-only.
    private func validateOpenChild() {
        guard let c = child, let id = childRowID else { return }
        guard items.first(where: { $0.id == id })?.submenu.isEmpty == false else {
            closeChild(); return                             // the submenu row is gone / lost its children
        }
        if let rect = list.rowRectOnScreen(for: id) {
            c.submenuRowOnScreen = rect
            c.reframe()
        } else {
            closeChild()                                     // the parent row scrolled out of view
        }
    }

    private func presentAsSubmenu(rowRectOnScreen rect: CGRect, in window: NSWindow) {
        anchorView = nil
        pointInHost = nil
        submenuRowOnScreen = rect
        hostWindow = window
        open(animated: !reduceMotion, installDismiss: false)        // the root owns the monitors / glue
    }

    /// The deepest currently-open menu in the cascade (self if no open child).
    private func activeLeaf() -> ThemedMenu { (child?.isOpen == true) ? child!.activeLeaf() : self }
    /// The cascade's root (self if not a submenu child).
    private func rootMenu() -> ThemedMenu { parentMenu?.rootMenu() ?? self }

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
        // The ROOT owns the only monitor; route the keys to the DEEPEST open menu
        // (the active leaf) so a cascade navigates its open child, not the root.
        let leaf = activeLeaf()
        switch ev.keyCode {
        case 125: leaf.list.moveHighlight(1);  return nil    // ↓
        case 126: leaf.list.moveHighlight(-1); return nil    // ↑
        case 124:                                            // → open the highlighted submenu (else pass through)
            if let id = leaf.list.highlightedID,
               leaf.items.first(where: { $0.id == id })?.submenu.isEmpty == false {
                leaf.openSubmenu(rowID: id, highlightFirst: true)
                return nil
            }
            return ev                                        // no submenu on this row → host keeps → (IME safe)
        case 123:                                            // ← close the current submenu level
            guard let parent = leaf.parentMenu else { return ev }   // at the root there's no level to close
            parent.closeChild()
            return nil
        case 36, 76, 49: leaf.list.activateHighlight(); return nil   // ⏎ / keypad ⏎ / Space
        case 53:                                             // Esc — close one level (root ⇒ dismiss all)
            if let parent = leaf.parentMenu { parent.closeChild() } else { dismiss() }
            return nil
        case 48:  dismiss(); return ev                       // Tab — dismiss all, don't trap focus
        default:  return ev                                  // pass everything else through (host IME, etc.)
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
        if let child, child.clickIsInside(ev) { return true }   // a click in any open descendant panel
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
            validateOpenChild()                             // re-anchor / close an open submenu after the parent moves
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
        let childOpen: Bool               // a submenu child is currently shown
        let childRowID: String?           // the parent row owning the open child
        let childRowCount: Int            // the open child's hosted-list row count (0 = none)
        let childHighlightedID: String?   // the open child's highlighted row
        let leafIsChild: Bool             // the active leaf is the child (keys route there)
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
            reduceMotionRespected: !(reduceMotion && animating),
            childOpen: child?.isOpen ?? false,
            childRowID: childRowID,
            childRowCount: child?.list.listProbe.rowCount ?? 0,
            childHighlightedID: child?.list.highlightedID,
            leafIsChild: activeLeaf() !== self)
    }
    /// The hosted list (drive its probe / nav directly in tests).
    var _list: ThemedList { list }
    /// The open submenu child controller, if any (drive its probe in tests).
    var _child: ThemedMenu? { child }
    /// Activate a row by id as if clicked (fires the item's action + dismisses).
    func _activate(_ id: String) { activate(id) }
    /// Open a submenu by its parent row id (as if hovered / →-keyed).
    func _openSubmenu(_ id: String) { openSubmenu(rowID: id, highlightFirst: true) }
    /// Collapse the open submenu child.
    func _closeChild() { closeChild() }
    /// Route a keyDown through the REAL monitor logic (swallow-vs-passthrough).
    func _handleKey(_ ev: NSEvent) -> NSEvent? { handleKeyDown(ev) }
}
#endif
