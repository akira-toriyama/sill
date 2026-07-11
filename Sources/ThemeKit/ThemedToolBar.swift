// ThemeKit — ThemedToolBar: a horizontal app bar / toolbar (MUI <AppBar> +
// <Toolbar>, fused). A faithful AppKit port of Material-UI's top bar — MUI's two
// nested components collapse into ONE NSView here: the OUTER `AppBar` chrome
// (surface fill · elevation shadow · square/rounded corners) wraps the INNER
// `Toolbar` content row (a fixed `minHeight` per density variant, leading/trailing
// gutters, and a left-to-right flex layout of items). Themed by assigning a
// PaletteKit `ResolvedPalette`. AppKit / @MainActor.
//
// It COMPOSES the real `ThemedButton` (not a re-draw) for action items — reusing
// its whole state machine (hover / press / focus / disabled, icons, contrast ink,
// key activation) — and the real `ThemedDivider` for separators. The BAR owns
// item GEOMETRY (it frames each item manually, like ThemedButtonGroup frames its
// members), so an `iconOnly` item is a snug SQUARE the size of the control height
// — sidestepping ThemedButton's 64 pt `minWidth` floor without touching it (a
// toolbar icon button is MUI's <IconButton>, not a min-width <Button>).
//
// Sections (MUI has no named start/center/end slots — they are built from
// `flexGrow:1` spacers): a `.flexibleSpace` item is the flex-grow analog — ONE
// greedy spacer = a left group + right group; TWO equal spacers bracket a centred
// element. `.fixedSpace` / `.divider` / `.label` round out the row.
//
// Two load-bearing affordances for a non-activating launcher panel (wand's tome):
// `trackingMode = .nonActivatingPanel` makes the bar's hover tracking `.activeAlways`
// (a `.activeInActiveApp` area never fires under an LSUIElement / non-key panel)
// and DRIVES each item's hover appearance itself; and `frameOnScreen(ofItem:)` +
// `onItemHover` expose per-item geometry so the host can anchor a child panel
// below a folder button. The interaction 演出 runs LIVE in `prism`.
//
// SCOPE (v1): surface · variant · gutters · flex sections · typed items
// (button / label / custom / divider / spaces). A `.primary` / `.secondary`
// coloured bar fills AND re-inks its composed buttons + its own label with the
// bar's contrast (MUI `color="inherit"` / contrastText), so icons + text read on
// the accent. MUI's responsive OVERFLOW (items that don't fit folding into a "…"
// menu) is the one deliberate FOLLOW-UP — it needs live layout tuning and no
// current consumer needs it; today an over-long row simply extends past the bar.

import AppKit
import Palette
import PaletteKit
import Motion

@MainActor
public final class ThemedToolBar: NSView {

    /// MUI AppBar `color`. `surface` = a neutral bar (the `background` role, the
    /// default); `primary` / `secondary` paint the bar with the accent role and
    /// ink the bar's own label with its contrast; `transparent` = no fill (let a
    /// vibrancy backdrop / window show through — the launcher-panel case).
    public enum Surface { case surface, primary, secondary, transparent }

    /// MUI Toolbar density → the bar's `minHeight` + default control size / gutter.
    /// `regular` 64 (the macOS desktop sm+ value) · `dense` 48 · `compact` 40 —
    /// `compact` is the sill addition for an icon-only launcher strip.
    public enum Variant { case regular, dense, compact }

    /// MUI Paper `square`. `square` = sharp corners + a bottom hairline (the full
    /// docked bar); `rounded` = an 8 pt panel (a floating launcher backdrop).
    public enum Corners { case square, rounded }

    /// Where the bar lives. `standard` = a normal in-app surface (items self-track
    /// their hover). `nonActivatingPanel` = a non-key / LSUIElement panel: hover
    /// tracking goes `.activeAlways` and the bar DRIVES item hover (the button's
    /// own `.activeInActiveApp` area would never fire there).
    public enum TrackingMode { case standard, nonActivatingPanel }

    /// One action item. `title == nil` (with a `symbol`) = an icon-only SQUARE
    /// button (MUI <IconButton>); a `title` = an icon+label button (MUI <Button>).
    public struct ButtonItem {
        public var title: String?
        public var symbol: String?          // leading / sole icon — a Phosphor slug
        public var trailingSymbol: String?  // a Phosphor slug
        public var image: NSImage?          // PRE-RESOLVED leading/sole icon (wins
                                            // over `symbol`): app icon / favicon /
                                            // brand logo (Simple Icons) / Phosphor /
                                            // emoji. Template ⇒ tinted; else raw.
        public var role: ThemedButton.Role
        public var variant: ThemedButton.Variant
        public var isEnabled: Bool
        public var tooltip: String?         // hover hint (esp. for icon-only)
        public var keyEquivalent: String
        public init(title: String? = nil, symbol: String? = nil, trailingSymbol: String? = nil,
                    image: NSImage? = nil,
                    role: ThemedButton.Role = .primary, variant: ThemedButton.Variant = .text,
                    isEnabled: Bool = true, tooltip: String? = nil, keyEquivalent: String = "") {
            self.title = title; self.symbol = symbol; self.trailingSymbol = trailingSymbol
            self.image = image
            self.role = role; self.variant = variant; self.isEnabled = isEnabled
            self.tooltip = tooltip; self.keyEquivalent = keyEquivalent
        }
        /// Icon-only ⇒ a square button (no text, an icon — Phosphor slug or image — present).
        public var isIconOnly: Bool { (title?.isEmpty ?? true) && (symbol != nil || image != nil) }
    }

    /// A row element. `flexibleSpace` is the MUI `flexGrow:1` spacer (greedy);
    /// `fixedSpace` a fixed gap; `divider` a vertical ThemedDivider; `label` a
    /// themed text (the AppBar title); `custom` any host-supplied NSView (a search
    /// field, a ThemedButtonGroup, …) — themed by the host, sized by the bar.
    public enum Item {
        case button(ButtonItem)
        case label(String)
        case custom(NSView)
        case flexibleSpace
        case fixedSpace(CGFloat)
        case divider
    }

    // MARK: - Public configuration

    /// The theme. Assigning re-themes the bar + every composed item.
    public var palette: ResolvedPalette { didSet { applyTheme() } }

    public var surface: Surface = .surface { didSet { applyTheme() } }
    public var variant: Variant = .regular {
        didSet { reconfigureControlSizes(); invalidateIntrinsicContentSize(); needsLayout = true }
    }
    public var corners: Corners = .square { didSet { applyTheme(); needsLayout = true } }

    /// MUI AppBar `elevation` (0–24). `0` = flat (a bottom hairline instead of a
    /// shadow, the common "border not shadow" bar); `> 0` = a drop shadow scaled
    /// from the value, no hairline.
    public var elevation: Int = 0 { didSet { applyTheme(); needsLayout = true } }

    /// Horizontal padding each side (MUI gutters). `nil` = the variant default
    /// (24 / 16 / 8); set `0` for an edge-to-edge bar (MUI `disableGutters`).
    public var gutter: CGFloat? = nil {
        didSet { invalidateIntrinsicContentSize(); needsLayout = true }
    }
    /// Gap between adjacent content items (AppKit has no implicit MUI `mr`).
    public var itemSpacing: CGFloat = CGFloat(Space.md) {
        didSet { invalidateIntrinsicContentSize(); needsLayout = true }
    }
    /// Override the composed buttons' size; `nil` = derived from the variant.
    public var controlSize: ThemedButton.Size? = nil {
        didSet { reconfigureControlSizes(); invalidateIntrinsicContentSize(); needsLayout = true }
    }

    /// The row content. Reassigning rebuilds the item views.
    public var items: [Item] = [] { didSet { rebuild() } }

    public var trackingMode: TrackingMode = .standard {
        didSet { updateTrackingAreas(); applyHover() }
    }

    /// Fired when the hovered item changes (`nil` = none) — the host anchors a
    /// child panel off `frameOnScreen(ofItem:)` here. Fires in BOTH tracking modes.
    public var onItemHover: ((Int?) -> Void)?
    /// Fired on an item button activation (mouse-up inside / Space / keyEquivalent).
    public var onItemClick: ((Int) -> Void)?

    /// Force an item's hovered appearance without events — deterministic capture.
    public var previewHoveredItem: Int? { didSet { applyHover() } }

    /// A PERSISTENT keyboard-navigation cursor (distinct from the transient
    /// `previewHoveredItem` capture override): when a toolbar is driven as a
    /// keyboard-navigable menu bar (ThemedMenu's `.toolbar` presentation), the host
    /// sets this to light the "current" item as the ←→ cursor moves. Precedence in
    /// `applyHover`: `previewHoveredItem` (capture) > `highlightedItem` (keyboard
    /// cursor) > live mouse hover. `nil` (default) ⇒ no cursor, exactly the prior
    /// behavior for a plain toolbar.
    public var highlightedItem: Int? { didSet { if highlightedItem != oldValue { applyHover() } } }

    // MARK: - Internals

    private let shadowLayer   = CALayer()   // elevation — UNCLIPPED, explicit shadowPath
    private let backdropLayer = CALayer()   // surface fill (rounded per corners)
    private let hairlineLayer = CALayer()   // flat-bar bottom border hairline
    private var itemViews: [NSView?] = []   // parallel to `items`; spaces ⇒ nil
    private var buttons: [Int: ThemedButton] = [:]   // item index → composed button
    private var trackingArea: NSTrackingArea?
    private var hoveredItem: Int?

    public override var isFlipped: Bool { false }   // y-up: y == 0 is the bottom edge

    // MARK: - Metrics

    private var resolvedGutter: CGFloat {
        if let gutter { return gutter }
        switch variant { case .regular: return 24; case .dense: return 16; case .compact: return 8 }
    }
    private var minHeight: CGFloat {
        switch variant { case .regular: return 64; case .dense: return 48; case .compact: return 40 }
    }
    private var resolvedControlSize: ThemedButton.Size {
        if let controlSize { return controlSize }
        switch variant { case .regular: return .medium; case .dense, .compact: return .small }
    }
    /// The composed-button height for the current size (mirrors ThemedButton).
    private var controlHeight: CGFloat { resolvedControlSize.controlHeight }
    private var cornerRadius: CGFloat { corners == .rounded ? CGFloat(Radius.lg) : 0 }
    private var dividerHeight: CGFloat { max(16, minHeight * 0.5) }
    private var hairlineThickness: CGFloat { 1.0 / backingScale }

    private var backingScale: CGFloat { themeBackingScale }

    // MARK: - Init

    public init(palette: ResolvedPalette) {
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false        // the shadow lives outside bounds

        let s = backingScale
        shadowLayer.configureShadowLayer(scale: s)
        shadowLayer.isHidden = true
        layer?.addSublayer(shadowLayer)

        backdropLayer.contentsScale = s
        layer?.addSublayer(backdropLayer)

        hairlineLayer.contentsScale = s
        hairlineLayer.isHidden = true
        layer?.addSublayer(hairlineLayer)

        setAccessibilityRole(.toolbar)
        applyTheme()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    // MARK: - Build (construct one view per item)

    private func rebuild() {
        for v in itemViews { v?.removeFromSuperview() }
        itemViews.removeAll(keepingCapacity: true)
        buttons.removeAll(keepingCapacity: true)

        for (i, item) in items.enumerated() {
            switch item {
            case .button(let spec):
                let b = ThemedButton(palette: buttonPalette())
                b.variant = spec.variant
                b.size = resolvedControlSize
                b.role = spec.role
                b.title = spec.title ?? ""
                b.leadingSymbol = spec.symbol
                b.leadingImage = spec.image
                b.trailingSymbol = spec.trailingSymbol
                b.isEnabled = spec.isEnabled
                b.keyEquivalent = spec.keyEquivalent
                b.toolTip = spec.tooltip
                b.onTap = { [weak self] in self?.onItemClick?(i) }
                addSubview(b)
                itemViews.append(b)
                buttons[i] = b
            case .label(let text):
                let f = NSTextField(labelWithString: text)
                f.isBezeled = false; f.isEditable = false; f.drawsBackground = false
                f.lineBreakMode = .byTruncatingTail
                addSubview(f)
                itemViews.append(f)
            case .custom(let v):
                addSubview(v)
                itemViews.append(v)
            case .divider:
                let d = ThemedDivider(palette: palette)
                d.orientation = .vertical
                addSubview(d)
                itemViews.append(d)
            case .flexibleSpace, .fixedSpace:
                itemViews.append(nil)
            }
        }
        applyTheme()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func reconfigureControlSizes() {
        for b in buttons.values { b.size = resolvedControlSize }
    }

    // MARK: - Theming

    // Fonts via `palette.uiFont(_:)` — the shared type-scale resolver
    // (honours .mono/.rounded/.menu; the old local helper dropped two).

    /// MUI AppBar `color` → the surface fill. `surface` honors `backgroundAlpha`
    /// (the panel translucency knob); `transparent` paints nothing.
    private var surfaceFill: NSColor? {
        switch surface {
        case .primary:   return palette.color(for: .primary)
        case .secondary: return palette.color(for: .secondary)
        case .surface:
            let base = palette.background ?? .windowBackgroundColor
            if let a = palette.backgroundAlpha { return base.withAlphaComponent(a) }
            return base
        case .transparent: return nil
        }
    }
    /// Ink for the bar's OWN label (contrast on a coloured bar, else foreground).
    private var barInk: NSColor {
        switch surface {
        case .primary:   return palette.onPrimary()
        case .secondary: return palette.onSecondary()
        case .surface, .transparent: return palette.foreground
        }
    }
    /// On a coloured bar a composed button must ink with the bar's CONTRAST, not
    /// its own accent (which would vanish into the same-hue fill) — MUI's
    /// `color="inherit"`. A neutral bar passes the palette through unchanged. We
    /// express it as a palette whose accent roles are remapped to the contrast ink
    /// (so a `.text` button's ink + a tinted icon + the hover wash all read);
    /// `.error` is left intact so a destructive action stays red.
    private func buttonPalette() -> ResolvedPalette {
        guard surface == .primary || surface == .secondary else { return palette }
        let ink = barInk
        return ResolvedPalette(
            background: palette.background, foreground: ink, muted: palette.muted,
            tertiary: palette.tertiary, primary: ink, secondary: ink, border: ink,
            hover: palette.hover, selection: palette.selection, error: palette.error,
            font: palette.font, backgroundAlpha: palette.backgroundAlpha,
            vibrancyMaterial: palette.vibrancyMaterial, forceDarkAqua: palette.forceDarkAqua)
    }
    /// A flat (elevation 0) square bar reads with a bottom hairline instead of a
    /// shadow — sill's idiom for separating a flat surface. Rounded panels and
    /// transparent bars get none.
    private var showsHairline: Bool { elevation == 0 && corners == .square && surface != .transparent }

    private var elevationSpec: (opacity: Float, radius: CGFloat, offsetY: CGFloat) {
        guard elevation > 0 else { return (0, 0, 0) }
        let dp = CGFloat(min(max(elevation, 1), 24))   // MUI dp range
        return (0.24, 1 + dp * 0.5, -(0.5 + dp * 0.25))
    }

    public func applyTheme() {
        // Snap, never cross-fade: a theme switch shouldn't smear the bar.
        layerTxn(animated: false) {
            self.backdropLayer.backgroundColor = (self.surfaceFill ?? .clear).cgColor
            let e = self.elevationSpec
            self.shadowLayer.applyShadowSpec(e)
            self.shadowLayer.isHidden = self.elevation <= 0
            self.hairlineLayer.backgroundColor = self.palette.border.cgColor
            self.hairlineLayer.isHidden = !self.showsHairline
        }
        for (i, item) in items.enumerated() {
            switch item {
            case .button:  (itemViews[i] as? ThemedButton)?.palette = buttonPalette()
            case .divider: (itemViews[i] as? ThemedDivider)?.palette = palette
            case .label:   if let f = itemViews[i] as? NSTextField { themeLabel(f) }
            default:       break   // custom views are themed by the host
            }
        }
        applyHover()
        needsLayout = true
    }

    private func themeLabel(_ f: NSTextField) {
        let pt: CGFloat = variant == .regular ? 14 : 13
        f.font = palette.uiFont(pt, .medium)
        f.textColor = barInk
    }

    // MARK: - Hover (bar-owned; drives item appearance in a non-key panel)

    /// In `.nonActivatingPanel` the bar is the SOLE hover driver (the button's own
    /// area can't fire); in `.standard` it leaves visuals to the buttons and only
    /// reports `onItemHover`. A `previewHoveredItem` forces a state in either mode.
    private var drivesHoverAppearance: Bool { trackingMode == .nonActivatingPanel }

    private func applyHover() {
        let forced: Int?
        if let previewHoveredItem { forced = previewHoveredItem }   // capture override wins
        else if let highlightedItem { forced = highlightedItem }    // then the keyboard cursor
        else if drivesHoverAppearance { forced = hoveredItem }      // then live mouse hover
        else { forced = nil }
        for (idx, b) in buttons { b.previewHovered = (idx == forced) }
    }

    private func setHovered(_ idx: Int?) {
        guard idx != hoveredItem else { return }
        hoveredItem = idx
        onItemHover?(idx)
        applyHover()
    }

    /// The button item whose frame contains `p` (bar coordinates), if any.
    private func itemIndex(at p: NSPoint) -> Int? {
        for (i, v) in itemViews.enumerated() {
            guard case .button = items[i], let v, v.frame.contains(p) else { continue }
            return i
        }
        return nil
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t); trackingArea = nil }
        var opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect]
        opts.insert(trackingMode == .nonActivatingPanel ? .activeAlways : .activeInActiveApp)
        let t = NSTrackingArea(rect: .zero, options: opts, owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }

    public override func mouseEntered(with event: NSEvent) {
        setHovered(itemIndex(at: convert(event.locationInWindow, from: nil)))
    }
    public override func mouseMoved(with event: NSEvent) {
        setHovered(itemIndex(at: convert(event.locationInWindow, from: nil)))
    }
    public override func mouseExited(with event: NSEvent) { setHovered(nil) }

    // MARK: - Per-item geometry (child-panel anchoring)

    /// The item's frame in SCREEN coordinates (nil before a window / out of range)
    /// — the host anchors a child launcher panel below a folder button with this.
    public func frameOnScreen(ofItem index: Int) -> NSRect? {
        guard items.indices.contains(index), let v = itemViews[index], let w = window else { return nil }
        return w.convertToScreen(v.convert(v.bounds, to: nil))
    }
    /// The item's frame in the bar's own coordinates (nil = a space / out of range).
    public func frame(ofItem index: Int) -> NSRect? {
        guard items.indices.contains(index) else { return nil }
        return itemViews[index]?.frame
    }

    // MARK: - Item sizing

    private func itemWidth(_ index: Int) -> CGFloat {
        switch items[index] {
        case .button(let spec):
            if spec.isIconOnly { return controlHeight }      // a square icon button
            return (itemViews[index] as? ThemedButton)?.intrinsicContentSize.width ?? 0
        case .label:
            // Measure the string directly: a truncating NSTextField underreports
            // its intrinsic width (it advertises that it CAN shrink), which would
            // clip a title that actually has room. The frame still truncates if the
            // bar later constrains it.
            guard let f = itemViews[index] as? NSTextField, let font = f.font else { return 0 }
            return ceil((f.stringValue as NSString).size(withAttributes: [.font: font]).width) + 4
        case .custom:
            guard let v = itemViews[index] else { return 0 }
            let w = v.intrinsicContentSize.width
            return w == NSView.noIntrinsicMetric ? v.fittingSize.width : w
        case .divider:        return 1
        case .fixedSpace(let w): return w
        case .flexibleSpace:  return 0
        }
    }
    private func itemHeight(_ index: Int) -> CGFloat {
        switch items[index] {
        case .button:  return controlHeight
        case .divider: return dividerHeight
        case .label, .custom:
            guard let v = itemViews[index] else { return 0 }
            let h = v.intrinsicContentSize.height
            return h == NSView.noIntrinsicMetric ? v.fittingSize.height : h
        case .flexibleSpace, .fixedSpace: return 0
        }
    }
    private func isSpace(_ index: Int) -> Bool {
        switch items[index] { case .flexibleSpace, .fixedSpace: return true; default: return false }
    }

    // MARK: - Layout (MUI Toolbar flex row + flexGrow spacers)

    public override var intrinsicContentSize: NSSize {
        let g = resolvedGutter
        var width = g, hasFlex = false, prevContent = false
        for (i, item) in items.enumerated() {
            if case .flexibleSpace = item { hasFlex = true; prevContent = false; continue }
            if case .fixedSpace(let w) = item { width += w; prevContent = false; continue }
            if prevContent { width += itemSpacing }
            width += itemWidth(i); prevContent = true
        }
        width += g
        return NSSize(width: hasFlex ? NSView.noIntrinsicMetric : ceil(width), height: minHeight)
    }

    public override func layout() {
        super.layout()
        let g = resolvedGutter

        // Pass 1: fixed extent (flexibles count as 0) to find the slack.
        var fixed = g + g, flexCount = 0, prevContent = false
        for (i, item) in items.enumerated() {
            if case .flexibleSpace = item { flexCount += 1; prevContent = false; continue }
            if case .fixedSpace(let w) = item { fixed += w; prevContent = false; continue }
            if prevContent { fixed += itemSpacing }
            fixed += itemWidth(i); prevContent = true
        }
        let slack = max(0, bounds.width - fixed)
        let perFlex = flexCount > 0 ? slack / CGFloat(flexCount) : 0

        // Pass 2: place left-to-right, vertically centred.
        var x = g; prevContent = false
        for (i, item) in items.enumerated() {
            if case .flexibleSpace = item { x += perFlex; prevContent = false; continue }
            if case .fixedSpace(let w) = item { x += w; prevContent = false; continue }
            if prevContent { x += itemSpacing }
            let w = itemWidth(i), h = itemHeight(i)
            itemViews[i]?.frame = NSRect(x: x, y: (bounds.height - h) / 2, width: w, height: h)
            x += w; prevContent = true
        }
        layoutBackdrop()
    }

    private func layoutBackdrop() {
        layerTxn(animated: false) {
            let b = self.bounds, r = self.cornerRadius
            self.backdropLayer.frame = b
            self.backdropLayer.cornerRadius = r
            self.backdropLayer.masksToBounds = r > 0

            self.shadowLayer.frame = b
            self.shadowLayer.shadowPath = CGPath(
                roundedRect: CGRect(origin: .zero, size: b.size),
                cornerWidth: r, cornerHeight: r, transform: nil)

            let t = self.hairlineThickness
            self.hairlineLayer.frame = NSRect(x: 0, y: 0, width: b.width, height: t)  // bottom edge (y-up)
        }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = backingScale
        for l in [shadowLayer, backdropLayer, hairlineLayer] { l.contentsScale = s }
        needsLayout = true
    }
}

#if DEBUG
// Test-only window into the resolved chrome + item geometry, so a deterministic
// test can assert surface / elevation / variant / flex distribution / item kinds
// WITHOUT a screenshot or synthetic events. Same-file extension so it can read
// the private layers / item views; not built into release.
extension ThemedToolBar {
    struct ToolBarProbe {
        public let minHeight: CGFloat
        public let gutter: CGFloat
        public let itemSpacing: CGFloat
        public let surfaceFill: CGColor?
        public let shadowOpacity: Float
        public let hairlineVisible: Bool
        public let hairlineColor: CGColor?
        public let cornerRadius: CGFloat
        public let itemCount: Int
        public let itemFrames: [CGRect]          // per item (space ⇒ .zero)
        public let buttonOverlay: [Int: CGColor?]  // composed button state layer per item
        public let hoveredItem: Int?
        public let highlightedItem: Int?         // the keyboard-nav cursor (menu-bar mode)
        public let forcedItem: Int?              // the item currently drawn hovered (precedence-resolved)
    }
    var toolBarProbe: ToolBarProbe {
        var frames: [CGRect] = []
        for v in itemViews { frames.append(v?.frame ?? .zero) }
        var overlay: [Int: CGColor?] = [:]
        for (i, b) in buttons { overlay[i] = b.buttonProbe.overlayColor }
        return ToolBarProbe(
            minHeight: minHeight,
            gutter: resolvedGutter,
            itemSpacing: itemSpacing,
            surfaceFill: backdropLayer.backgroundColor,
            shadowOpacity: shadowLayer.shadowOpacity,
            hairlineVisible: !hairlineLayer.isHidden,
            hairlineColor: hairlineLayer.backgroundColor,
            cornerRadius: backdropLayer.cornerRadius,
            itemCount: items.count,
            itemFrames: frames,
            buttonOverlay: overlay,
            hoveredItem: hoveredItem,
            highlightedItem: highlightedItem,
            forcedItem: previewHoveredItem ?? highlightedItem ?? (drivesHoverAppearance ? hoveredItem : nil))
    }

    /// Drive a button item's activation dispatch without synthetic events — the
    /// same closure a real mouse-up-inside fires.
    func simulateItemTapForTesting(_ i: Int) { buttons[i]?.onTap?() }
    /// Drive the hover state machine without a tracking event.
    func simulateHoverForTesting(_ i: Int?) { setHovered(i) }
}
#endif
