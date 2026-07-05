// ThemeKitUI — ThemedMenu: an MUI <Menu> (basic) for the family. A themed pop-up
// menu of action rows — the floating list facet's 528-line hand-rolled `PopupMenu`
// and wand's launcher cascade both reinvent today. Themed by assigning a PaletteKit
// `ResolvedPalette`. AppKit popup shell + SwiftUI-native rows / @MainActor.
//
// Like `ThemedTooltip` / `ThemedComboBox` (NOT an NSView), it is a CONTROLLER that
// OWNS a borderless, non-activating `PopupPanel`. The host window stays key — the
// panel never becomes key — so the menu floats above without stealing focus.
// Because the panel is non-key, the hosted list can't receive keyDown; the
// controller drives ↑↓/⏎/Esc through ONE local keyDown monitor (the verified
// mechanism — a non-key panel's content never becomes first responder, so there is
// no responder to route keys through, unlike the combo's embedded field).
//
// #17b M4: the action rows are now the SwiftUI-native `ThemedListView` (via
// `HostedThemedList` / `ListController`, hosted in a `HostingListView`), NOT the
// AppKit `ThemedList` — the same move M3 made for `ThemedComboBox`. That is WHY this
// widget lives in ThemeKitUI (the SwiftUI front) while its non-key `PopupPanel`
// shell + the composed `ThemedToolBar` (horizontal presentation) come from ThemeKit
// (the AppKit floors it depends on) — the reverse edge would cycle. The controller
// is configured `selectionMode = .none` (the menu only HIGHLIGHTS) · `hoverStyle =
// .solidAccent` (+ `onPrimary` ink) · `highlightFollowsHover` · `wrapsHighlight` ·
// `vendsRowAXElements` (per-row `.menuItem` AX) · `hosted` (the host window keeps
// key; the keyDown monitor drives nav and the AppKit `mouseUp` commits a row click).
//
// The React-component contract (the kit's mental model): the component owns render
// + interaction + theming; the HOST passes data + behavior. A `MenuItem` carries
// the title / icon / shortcut / enabled-ness AND its `action` closure (the 実処理);
// ThemedMenu maps it onto a `ListItem`, and on activation runs the matching item's
// closure. The kit knows no domain — the host passes a pre-resolved `NSImage` and
// supplies the action.
//
// Mechanics lifted from the shared `PopupPanel` factory + the combo/tooltip
// precedent: `themedPopupPanel(interactive:role:)`, `placePopup` (with the
// `.anchorCorner` / `.point` / `.submenu` cases), `PopupFade` (monotonic-token
// teardown), `PopupGlue` (host move / resize / close / resign-key),
// `removeMonitorSafely`. The MUI Grow (a gentle scale + fade from the anchor-facing
// corner) is a transient transform on the panel content's layer (model stays
// identity — it never fights the placement's frame resets), fully gated on
// reduce-motion.
//
// Canonical roles only: `background` (surface) · `border` (edge / separator) ·
// `foreground` (row text) · `muted` (shortcut / chevron / header) · `tertiary`
// (disabled) · `selection` + `primary` (the `.solidAccent` highlight = opaque
// `primary` fill + `onPrimary()` ink) · `error` (a destructive item's tint).
//
// PRESENTATION (`.vertical` default / `.toolbar` / `.labeledToolbar`): the ROOT may
// lay its items out HORIZONTALLY as a menu bar. It does NOT re-draw a horizontal
// list — it COMPOSES the real `ThemedToolBar` (icon-only / icon+label, its
// `.nonActivatingPanel` hover + `frameOnScreen(ofItem:)` were built for exactly this
// launcher case) as the panel's content, and a folder bar-item opens its submenu
// BELOW itself (the drop-down `.anchorCorner` placement — no new placement math).
// Submenu CHILDREN stay vertical SwiftUI lists (a menu bar's dropdowns are vertical);
// key routing flips per the active leaf's orientation (←→ along a bar, ↓ opens below).

import AppKit
import QuartzCore
import Palette
import PaletteKit
import ThemeKit          // PopupPanel/placePopup/PopupFade/PopupGlue shell + ThemedToolBar + phosphorImage + Trailing/Tint value types (AppKit floors)
import ListCore

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
        /// Child rows. Non-empty ⇒ this row opens a cascade: hover / `→` / click
        /// opens a child menu beside the row, and the child's own submenu rows
        /// cascade further (N-level, arbitrary depth). A submenu row's own `action`
        /// is ignored — opening the child IS its activation.
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
    public var palette: ResolvedPalette { didSet { applyTheme() } }

    /// The items. Assigning rebuilds the hosted list rows + reframes an open menu.
    public var items: [MenuItem] = [] { didSet { rebuildRows(); if isOpen { reframe(); validateOpenChild() } } }

    /// Row density — `.compact` (the native-menu default, 26pt rows) or
    /// `.comfortable` (30pt, the dropdown-list metric).
    public var density: Density = .compact {
        didSet { rehostList(); if isOpen { reframe() } }
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

    /// How the ROOT lays out its items. `.vertical` (default) is the classic
    /// drop-down list; `.toolbar` a horizontal ICON-ONLY bar (MUI IconButton row);
    /// `.labeledToolbar` a horizontal ICON+LABEL bar. A folder item on a horizontal
    /// root opens its submenu BELOW it; the cascade underneath is the same N-level
    /// machinery and its CHILDREN are always vertical (mirrors a menu bar). Assigning
    /// swaps the hosted content (a real `ThemedToolBar` vs the SwiftUI list) and
    /// reframes an open menu.
    public enum Presentation: Equatable { case vertical, toolbar, labeledToolbar }
    public var presentation: Presentation = .vertical {
        didSet { guard presentation != oldValue else { return }; applyPresentation() }
    }

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
    /// Horizontal presentations light the matching toolbar item instead. (The hosted
    /// list has no separate preview override — its `highlight` IS the state — so the
    /// vertical case drives the controller's live highlight directly.)
    public var previewHighlight: String? {
        get { isHorizontal ? _horizPreviewHighlight : controller.highlight }
        set {
            if isHorizontal {
                _horizPreviewHighlight = newValue
                toolbar?.previewHoveredItem = newValue.flatMap { id in items.firstIndex(where: { $0.id == id }) }
            } else {
                controller.highlight = newValue
            }
        }
    }

    // MARK: - Internals

    /// The hosted SwiftUI list, driven imperatively via `controller` and hosted in an
    /// AppKit `HostingListView` (its `mouseUp` does the synchronous row-click commit).
    /// It is the content for a `.vertical` root AND for EVERY submenu child (children
    /// are always vertical). #17b M4: was the AppKit `ThemedList`.
    private let controller = ListController<String>()
    private var hosting: HostingListView<String>!
    /// The horizontal menu-bar content, built lazily on the first `.toolbar` /
    /// `.labeledToolbar` presentation (the ROOT only — children never host one).
    private var toolbar: ThemedToolBar?
    /// The keyboard/hover cursor index into `items` while horizontal (nil = none).
    private var toolbarHighlightIndex: Int?
    private var _horizPreviewHighlight: String?
    private let container = NSView()             // rounded, bordered menu surface

    private var panel: PopupPanel?
    private var isOpen = false
    private var isInvalidated = false

    // Placement context (one of: an anchor view, or a screen point in a host window).
    private weak var anchorView: NSView?
    private var pointInHost: CGPoint?
    private weak var hostWindow: NSWindow?
    private var anchorGap: CGFloat = CGFloat(Space.xs)
    private var resolvedCorner: PopupCorner = .topLeading

    // Submenu cascade (N-level). A submenu row owns a CHILD ThemedMenu placed beside
    // it, and that child may open its OWN child — the cascade chains to arbitrary
    // depth, but only ONE path is open at a time (each menu has a single `child`).
    // The ROOT owns ALL keyboard / mouse / glue and routes keys to the active leaf,
    // so a child installs none. `parentMenu` marks a child (walk to the root / close
    // one level). `submenuRowOnScreen` is a child's placement anchor (its parent row).
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
    /// `PopupFade.duration` is module-internal, so the Grow reads this local copy.
    private let fadeDuration: TimeInterval = 0.14
    private lazy var fade = PopupFade(duration: fadeDuration)
    private let glue = PopupGlue()

    // Metrics (native-menu trims — MUI's 48/8 px touch metrics shrunk for macOS).
    private let cornerRadius: CGFloat = CGFloat(Radius.md)
    private let menuVPad: CGFloat = CGFloat(Space.xs)            // breathing room above/below the rows
    private let minWidth: CGFloat = 120
    private let maxWidth: CGFloat = 320
    private let maxHeight: CGFloat = 480         // taller menus scroll (NSMenu does too)
    private let growScale: CGFloat = 0.92        // a gentle native pop (MUI's 0.75 reads gimmicky on macOS)

    // Probe state (set by reframe()).
    private var lastFrame: CGRect = .zero

    // MARK: - Init

    public init(palette: ResolvedPalette) {
        self.palette = palette
        super.init()
        // Menu semantics: no persistent selection, opaque hover highlight that the
        // pointer AND the arrows share, MUI wrap, real per-row AX, hosted (the host
        // window keeps key — the list never becomes first responder). Route a row
        // COMMIT (mouseUp → fireActivate, or ⏎ → activateHighlight) and hover through
        // the menu's own handlers.
        controller.style = menuListStyle()
        controller.onActivate = { [weak self] id in self?.activate(id) }
        controller.onHover = { [weak self] id in self?.handleHover(id) }
        rebuildRows()
    }

    /// The hosted list's config — menu semantics, re-derived on a theme / density /
    /// surface change (the surface lives in the style so a theme switch rebuilds it).
    private func menuListStyle() -> ThemedListStyle {
        var s = ThemedListStyle()
        s.density = density
        s.selectionMode = .none
        s.hoverStyle = .solidAccent
        s.highlightFollowsHover = true
        s.wrapsHighlight = true
        s.vendsRowAXElements = true          // per-row `.menuItem` AX (VoiceOver)
        s.hosted = true                      // AppKit mouseUp owns the click; rows are inert
        s.surfaceColor = menuSurface
        return s                             // reservesLeadingImageColumn stays true (checkmark/icon gutter)
    }

    /// Build the hosted `NSHostingView` once (the controller was configured in init).
    private func buildHosting() {
        controller.style = menuListStyle()
        let root = HostedThemedList(controller: controller, style: controller.style, palette: palette)
        hosting = HostingListView(controller: controller, rootView: root)
    }

    /// Re-render the hosted SwiftUI list (palette / surface / density live in the
    /// value-typed root, so those changes rebuild it; `@Bindable` handles items /
    /// highlight). A no-op before the panel (and its hosting view) is created.
    private func rehostList() {
        controller.style = menuListStyle()
        hosting?.rootView = HostedThemedList(controller: controller, style: controller.style, palette: palette)
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
        if isHorizontal {
            ensureToolbar().items = items.map(toolbarItem)
            return
        }
        controller.items = items.map { mi in
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

    /// A `MenuItem` → `ThemedToolBar.Item` for a horizontal root. `.toolbar` is
    /// icon-only (title dropped, tooltip = title — MUI IconButton); `.labeledToolbar`
    /// keeps the label and adds a `caret-down` on a folder item. An icon-only item
    /// with NO icon degrades to a text button (never a blank square).
    private func toolbarItem(_ mi: MenuItem) -> ThemedToolBar.Item {
        switch mi.kind {
        case .separator: return .divider
        case .header:    return .label(mi.title)
        case .item:
            let iconOnly = (presentation == .toolbar) && (mi.icon != nil)
            let trailing: String? = (presentation == .labeledToolbar && mi.hasSubmenu) ? "caret-down" : nil
            return .button(.init(
                title: iconOnly ? nil : mi.title,
                trailingSymbol: trailing,
                image: mi.icon,
                role: mi.isDestructive ? .error : .primary,
                variant: .text,
                isEnabled: mi.isEnabled,
                tooltip: mi.title))
        }
    }

    // MARK: - Presentation (vertical list vs horizontal ThemedToolBar bar)

    private var isHorizontal: Bool { presentation != .vertical }
    private var orientation: MenuOrientation { isHorizontal ? .horizontal : .vertical }

    /// Build (once) the horizontal toolbar the root hosts. Transparent surface +
    /// square corners so the container's rounded, stroked menu surface is the chrome;
    /// `.nonActivatingPanel` tracking because the panel is never key; hover / click
    /// route back through the same cascade the vertical list drives.
    @discardableResult
    private func ensureToolbar() -> ThemedToolBar {
        if let toolbar { return toolbar }
        let tb = ThemedToolBar(palette: palette)
        tb.trackingMode = .nonActivatingPanel
        tb.surface = .transparent
        tb.corners = .square
        tb.onItemHover = { [weak self] idx in self?.toolbarHover(idx) }
        tb.onItemClick = { [weak self] idx in self?.toolbarClick(idx) }
        toolbar = tb
        return tb
    }

    /// Swap the hosted content view (list ⇄ toolbar) + reframe, after a presentation
    /// change. The toolbar's variant follows the mode (`.compact` icon strip vs
    /// `.dense` labeled bar).
    private func applyPresentation() {
        if isHorizontal {
            let tb = ensureToolbar()
            tb.variant = (presentation == .toolbar) ? .compact : .dense
        }
        if panel != nil { installContentView() }
        rebuildRows()
        applyTheme()
        if isOpen { reframe() }
    }

    /// Make the container host the CURRENT presentation's content view (idempotent).
    private func installContentView() {
        hosting?.removeFromSuperview()
        toolbar?.removeFromSuperview()
        if isHorizontal, let toolbar { container.addSubview(toolbar) }
        else if let hosting { container.addSubview(hosting) }
    }

    // MARK: Content (orientation-aware highlight / activation / anchor)

    /// The screen rect of the row / bar-item with `id` — a child's placement anchor.
    private func rowRectOnScreen(for id: String) -> CGRect? {
        if isHorizontal {
            guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
            return toolbar?.frameOnScreen(ofItem: idx)
        }
        return controller.rowRectOnScreen(id)
    }

    /// Move the highlight one navigable step (wraps — MUI). Vertical → the list;
    /// horizontal → the toolbar cursor among ENABLED action items (skips
    /// dividers/labels/disabled).
    private func moveContentHighlight(_ delta: Int) {
        guard isHorizontal else { controller.moveHighlight(delta); return }
        let nav = items.indices.filter { items[$0].kind == .item && items[$0].isEnabled }
        guard !nav.isEmpty else { return }
        let step = delta >= 0 ? 1 : -1
        let cur = toolbarHighlightIndex.flatMap { nav.firstIndex(of: $0) }
        let next = cur.map { ($0 + step + nav.count) % nav.count } ?? (step > 0 ? 0 : nav.count - 1)
        setToolbarHighlight(nav[next])
    }

    private func setToolbarHighlight(_ idx: Int?) {
        toolbarHighlightIndex = idx
        toolbar?.highlightedItem = idx
    }

    /// The id of the currently highlighted row / bar-item.
    private var highlightedContentID: String? {
        if isHorizontal { return toolbarHighlightIndex.flatMap { items.indices.contains($0) ? items[$0].id : nil } }
        return controller.highlightedID
    }

    /// Activate the highlighted row / bar-item (⏎ / Space).
    private func activateContentHighlight() {
        if isHorizontal { if let id = highlightedContentID { activate(id) } }
        else { controller.activateHighlight() }
    }

    private func clearContentHighlight() {
        if isHorizontal { setToolbarHighlight(nil) } else { controller.clearHighlight() }
    }

    /// A hovered toolbar item → move the cursor there + run the same hover-intent the
    /// list's `onHover` drives (open a folder's child after a beat / collapse on a
    /// non-folder). A nil idx (pointer left the bar) keeps state (travelling into the
    /// open child below).
    private func toolbarHover(_ idx: Int?) {
        guard let idx, items.indices.contains(idx) else { handleHover(nil); return }
        setToolbarHighlight(idx)
        handleHover(items[idx].id)
    }

    /// A clicked toolbar item → activate it (a folder opens its child below; a leaf
    /// runs its action + dismisses).
    private func toolbarClick(_ idx: Int) {
        guard items.indices.contains(idx) else { return }
        setToolbarHighlight(idx)
        activate(items[idx].id)
    }

    /// A template checkmark glyph — the list tints it to `foreground` (resting) /
    /// `onPrimary` (highlighted), so it re-themes with the palette (a native menu
    /// check is the control text colour, not an accent).
    private static let checkmark: NSImage? = phosphorImage("check", pt: 12, weight: .bold)

    // MARK: - Theming

    public func applyTheme() {
        // Paint the OPAQUE menu surface on BOTH the hosted list (via its style) and
        // the container (which shows in the vertical-padding strips + carries the
        // rounded edge), so the menu reads as one seamless opaque card on every theme.
        toolbar?.palette = palette          // transparent surface → the container shows through
        // Snap the panel surface / edge (these CALayer props would otherwise
        // implicitly cross-fade on a theme switch — combo parity).
        layerTxn(animated: false) {
            container.layer?.backgroundColor = menuSurface.cgColor
            container.layer?.borderColor = palette.border.cgColor
        }
        rehostList()          // re-render the hosted SwiftUI list with the new palette + surface
    }

    private var menuSurface: NSColor { surfaceColor ?? palette.background ?? .textBackgroundColor }

    // MARK: - Present (drop-down from an anchor, or a context menu at a point)

    /// Open the menu as a drop-down below `anchor` (flipping above on underflow).
    public func present(from anchor: NSView, gap: CGFloat = CGFloat(Space.xs)) {
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
        clearContentHighlight()
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
        anchorGap = CGFloat(Space.xs)
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
        // The preview path keeps a caller-set highlight: the hosted list's `highlight`
        // IS the vertical preview seam now (no separate override), so only a NON-preview
        // open clears it — else `previewHighlight` set before `previewOpen` is wiped.
        if installDismiss { previewHighlight = nil; clearContentHighlight() }
        if highlightsFirstOnOpen { moveContentHighlight(1) }
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
        if hosting == nil { buildHosting() }        // the SwiftUI list host (vertical content)
        if isHorizontal {
            ensureToolbar().variant = (presentation == .toolbar) ? .compact : .dense
        }
        installContentView()
        p.contentView = container
        p.contentView?.setAccessibilityElement(true)    // the popup IS a menu (role set by the factory)
        panel = p
        applyTheme()
    }

    /// The menu's size from its content: width = the widest row clamped to
    /// [minWidth, maxWidth]; height = the rows + the vertical padding, capped at
    /// `maxHeight` (overflow scrolls).
    private func menuSize() -> CGSize {
        if isHorizontal, let toolbar {
            // A menu bar sizes to the toolbar's own flex layout (its gutters replace
            // the list's vpad); + the 1pt border L/R + T/B. Overflow wrap/scroll is a
            // deliberate follow-up (a launcher strip fits its items today).
            let s = toolbar.intrinsicContentSize
            let w = (s.width == NSView.noIntrinsicMetric ? maxWidth : s.width) + 2
            return CGSize(width: w, height: s.height + 2)
        }
        let contentW = controller.fittingWidth(maxWidth: maxWidth - 2, palette: palette)
        let width = min(maxWidth, max(minWidth, contentW + 2))      // +2 for the 1pt border L/R
        let rows = controller.contentHeight()
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
            // A child menu anchored to its parent row (rect already on-screen, captured
            // at open); gap 2 so it reads connected. A HORIZONTAL parent (menu bar) drops
            // its child BELOW the bar item — a drop-down, so it reuses `.anchorCorner`
            // (below · flip-up on underflow · right-align on overflow); a vertical parent
            // opens the child to its RIGHT via `.submenu` (flips left on overflow).
            if parentMenu?.isHorizontal == true {
                result = placePopup(panel, anchorRectOnScreen: rowRect, .anchorCorner(size: size, gap: 2))
            } else {
                result = placePopup(panel, anchorRectOnScreen: rowRect, .submenu(size: size, gap: 2))
            }
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

        // Lay out the inner content (panel content is NOT flipped → y-up). The list
        // sits inside the 1pt border with `menuVPad` above/below; the toolbar fills the
        // border box (its own gutters are the breathing room).
        container.frame = CGRect(origin: .zero, size: frame.size)
        if isHorizontal, let toolbar {
            toolbar.frame = CGRect(x: 1, y: 1, width: frame.size.width - 2, height: frame.size.height - 2)
        } else if let hosting {
            hosting.frame = CGRect(x: 1, y: 1 + menuVPad,
                                   width: frame.size.width - 2,
                                   height: frame.size.height - 2 * (1 + menuVPad))
        }

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
        // Each menu drives its OWN child; the cascade chains N deep and only one
        // path is ever open, so there is no cross-level contention.
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
    /// Runs at any depth (a child opens its own child — the cascade chains). No-op on
    /// a disabled / non-submenu / off-screen row.
    private func openSubmenu(rowID id: String, highlightFirst: Bool) {
        hoverWork?.cancel(); hoverWork = nil
        guard isOpen, let host = hostWindow,
              let mi = items.first(where: { $0.id == id }), mi.isEnabled, !mi.submenu.isEmpty,
              let rowRect = rowRectOnScreen(for: id) else { return }
        if childRowID == id, child?.isOpen == true {                // already showing this one
            if highlightFirst { child?.controller.moveHighlight(1) }    // re-light its first row (Enter/→ intent)
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
        if highlightFirst { c.controller.moveHighlight(1) }
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
        clearContentHighlight()
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
        if let rect = rowRectOnScreen(for: id) {
            c.submenuRowOnScreen = rect
            c.reframe()
            c.validateOpenChild()                            // recurse: re-anchor the whole descendant chain
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
        // Intent flips with the LEAF's orientation: a horizontal bar keys ←→ + ↓;
        // its vertical child (and every vertical menu) keys ↑↓ + → / ←.
        switch menuKeyIntent(keyCode: ev.keyCode, orientation: leaf.orientation) {
        case .moveDown: leaf.moveContentHighlight(1);  return nil
        case .moveUp:   leaf.moveContentHighlight(-1); return nil
        case .openSubmenu:
            if let id = leaf.highlightedContentID,
               leaf.items.first(where: { $0.id == id })?.submenu.isEmpty == false {
                leaf.openSubmenu(rowID: id, highlightFirst: true)
                return nil
            }
            return ev                                        // no submenu on this row → host keeps the key (IME safe)
        case .closeLevel:
            guard let parent = leaf.parentMenu else { return ev }
            parent.closeChild()
            return nil
        case .activate: leaf.activateContentHighlight(); return nil
        case .escapeLevel:
            if let parent = leaf.parentMenu { parent.closeChild() } else { dismiss() }
            return nil
        case .dismissTab: dismiss(); return ev
        case .passThrough: return ev
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
        CATransaction.setAnimationDuration(fadeDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        cl.opacity = 1                                  // implicit fade (model → 1)
        let grow = CABasicAnimation(keyPath: "transform")
        grow.fromValue = NSValue(caTransform3D: from)
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        grow.duration = fadeDuration
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
        let presentation: Presentation    // vertical list vs horizontal toolbar bar
        let rowCount: Int                 // hosted content item count (list rows, or bar items)
        let highlightedID: String?        // the highlighted row / bar-item id (orientation-aware)
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
            presentation: presentation,
            rowCount: isHorizontal ? items.count : controller.items.count,      // bar items are 1:1 with menu items
            highlightedID: highlightedContentID,
            resolvedCorner: resolvedCorner,
            menuFrame: lastFrame,
            panelOrderedIn: panel?.isVisible ?? false,
            hasKeyMonitor: keyMon != nil,
            hasMouseMonitor: mouseMon != nil,
            axMenuItemLabels: axMenuItemLabels,
            hasOpacityAnimation: animating,
            reduceMotionRespected: !(reduceMotion && animating),
            childOpen: child?.isOpen ?? false,
            childRowID: childRowID,
            childRowCount: child?.controller.items.count ?? 0,
            childHighlightedID: child?.controller.highlightedID,
            leafIsChild: activeLeaf() !== self)
    }
    /// The per-row AX menu-item labels VoiceOver reads — the vertical list's ACTIONABLE
    /// rows (enabled `.item`s), with a "checked" marker folded in (mirrors the AppKit
    /// widget's synthetic `.menuItem` children; the real SwiftUI AX is proven in prism).
    /// Empty for a horizontal root (the composed `ThemedToolBar` vends its own button AX).
    private var axMenuItemLabels: [String] {
        guard !isHorizontal else { return [] }
        return items.filter { $0.kind == .item && $0.isEnabled }
                    .map { $0.isChecked ? "\($0.title), checked" : $0.title }
    }
    /// The hosted list controller (drive its probe / nav directly in tests).
    var _controller: ListController<String> { controller }
    /// The hosted horizontal toolbar (nil until a `.toolbar`/`.labeledToolbar` open).
    var _toolbar: ThemedToolBar? { toolbar }
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
