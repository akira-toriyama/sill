// ThemeKit — ThemedList: an MUI <List> (basic) for the family. A PUBLIC,
// EMBEDDABLE themed list view — the reusable, app-agnostic component facet's
// window/tree sidebar and wand's launcher tome both hand-draw today. Themed by
// assigning a PaletteKit `ResolvedPalette`. AppKit / @MainActor.
//
// Unlike ThemedComboBox / ThemedTooltip (per-field CONTROLLERS that own a child
// window), ThemedList is a plain `NSView` a host embeds directly — so it is
// `screencapture`-able in prism, the big win that makes a static per-theme grid
// possible. It PROMOTES ComboBox's private `ComboListView` drawing engine (the
// flipped, custom-drawn, hover-tracked row painter) OUT of the popup and
// generalizes it: mixed-height rows, leading image + primary/secondary text +
// role-typed badges + a trailing accessory, two densities, sticky section
// headers, dividers, single / no selection, two hover looks, and an actionable
// empty state. ThemedMenu (next) will host one of these for its action rows; the
// 0.31 combo refactor will drop its `ComboListView` for this at `.comfortable`
// density (byte-compatible: the comfortable single-line row IS the combo's 30pt).
//
// The React-component contract (the kit's mental model): the component owns
// render + interaction + theming; the HOST passes data + behavior. ThemedList is
// DUMB about the domain — it knows no "tag"/"window"/"favicon": the host passes a
// PRE-RESOLVED `NSImage` (the kit parses no `app:`/`SF:` spec), ROLE-BASED colour
// intent (`ListTint`/`BadgeRole`, resolved to an `NSColor` at DRAW time so they
// re-theme on `palette` didSet — a stored NSColor could not), and behavior via
// callbacks (`onActivate`/`onSelectionChange`/`onEmptyAction`).
//
// Canonical roles only (the theming contract): `background` (surface) · `border`
// (divider / shortcut stroke) · `foreground` (primary text) · `muted` (secondary
// text / header / shortcut) · `tertiary` (disabled / chevron) · `selection` +
// `primary` (the selection wash + 3pt accent bar — the combo's, reads on neon) ·
// `primary` + `onPrimary()` (the opaque `.solidAccent` hover — wand's signature) ·
// `hover` (the pointer veil over a selected row) · `error` (the error badge/tint).

import AppKit
import Palette
import PaletteKit

// MARK: - Row-model vocabulary (shared with the coming ThemedMenu)

/// The role a `Badge` paints in — resolved to a palette colour at draw time.
public enum BadgeRole: Equatable, Sendable { case neutral, primary, secondary, error }

/// A leading accent intent for a whole row — a 3pt bar in the resolved colour.
/// Role-based (re-themes on a palette switch); `.custom` carries a pure
/// `HexColor` (Sendable) for an app-specific tint the roles can't express.
public enum ListTint: Equatable, Sendable {
    case none, primary, secondary, error
    case custom(HexColor)
}

/// The single trailing affordance on a row (right of any badges). One-of — a row
/// has at most one. All glyphs are PRE-RESOLVED by the host (`.custom`) or drawn
/// from a fixed SF name the kit owns (`.chevron`).
public enum TrailingAccessory: Equatable {
    case none
    case chevron               // a disclosure `chevron.right`, `tertiary`
    case shortcut(String)      // a bordered key-hint lozenge ("⌘1"), `muted`
    case custom(NSImage)       // a pre-resolved trailing glyph
}

/// A small role-typed pill in a row's trailing area. A plain (non-Sendable)
/// value — it may carry a pre-resolved `NSImage` symbol (NSImage isn't Sendable);
/// it lives main-actor-side only. The kit parses no SF name — the host passes the
/// image.
public struct Badge: Equatable {
    public var text: String
    public var symbol: NSImage?
    public var role: BadgeRole
    public init(_ text: String, symbol: NSImage? = nil, role: BadgeRole = .neutral) {
        self.text = text; self.symbol = symbol; self.role = role
    }
}

/// One row's data. A plain value holding a pre-resolved `NSImage?` + role-typed
/// colour intent (never a stored `NSColor` — so it re-themes at draw). A `.row` is
/// an activatable line; a `.sectionHeader` is a non-selectable, optionally-sticky
/// group label (1-line, or 2-line with a `subtitle`). Identity is the stable `id`
/// surfaced in callbacks + `rowFrame`.
public struct ListItem {
    public let id: String
    public var image: NSImage?
    public var primary: String
    public var secondary: String?
    public var secondaryMono: Bool          // mono font for the secondary line alone (wand url)
    public var badges: [Badge]
    public var trailing: TrailingAccessory
    public var tint: ListTint
    public var kind: Kind
    public var isDisabled: Bool
    /// Marks the row as in a checked / on state FOR ACCESSIBILITY (a menu's
    /// `isChecked` toggle item). Purely an AX hint — the visible check is the host's
    /// leading image; this folds a "checked" marker into the row's synthetic
    /// `.menuItem` label so VoiceOver can tell a checked row from an unchecked one.
    public var axChecked: Bool

    public enum Kind: Equatable {
        case row
        case sectionHeader(subtitle: String? = nil)
        /// A non-interactive thin rule between groups (a menu separator). Drawn as a
        /// full-bleed 1pt `border` hairline in a short band; skipped by nav / hover /
        /// activation / AX. Its `id` only needs to be unique.
        case separator
    }

    public init(id: String, image: NSImage? = nil, primary: String,
                secondary: String? = nil, secondaryMono: Bool = false,
                badges: [Badge] = [], trailing: TrailingAccessory = .none,
                tint: ListTint = .none, kind: Kind = .row, isDisabled: Bool = false,
                axChecked: Bool = false) {
        self.id = id; self.image = image; self.primary = primary
        self.secondary = secondary; self.secondaryMono = secondaryMono
        self.badges = badges; self.trailing = trailing; self.tint = tint
        self.kind = kind; self.isDisabled = isDisabled; self.axChecked = axChecked
    }

    var isHeader: Bool { if case .sectionHeader = kind { return true }; return false }
    var headerSubtitle: String? { if case let .sectionHeader(s) = kind { return s }; return nil }
    var isSeparator: Bool { if case .separator = kind { return true }; return false }
}

// MARK: - ThemedList

@MainActor
public final class ThemedList: NSView {

    // MARK: Config types (nested — the codebase idiom, like ThemedButton.Size)

    /// Per-character tracking applied to a 1-line section header (the drawn header
    /// AND `fittingWidth` must use the same value or the width contract drifts).
    static let headerKern: CGFloat = 0.5

    public enum Density { case comfortable, compact }   // comfortable == the combo engine's metrics
    public enum SelectionMode { case none, single }      // no .multiple (YAGNI)
    public enum HoverStyle { case wash, solidAccent }    // selection wash + bar (default) vs opaque primary
    public enum ScrollPosition { case nearest, top, center }

    /// The id targeted by `activateRow` / `rowFrame` for the actionable empty
    /// row (a synthetic row with no `ListItem`). Public so a host can drive it.
    public static let emptyActionID = "__themedlist.emptyAction__"

    // MARK: Public configuration (props — assign-and-repaint)

    /// The rows. Assigning relayouts (heights are mixed), reconciles the committed
    /// selection by id (an id that vanished is dropped), and repaints. Backed by
    /// `_items` so `setLeadingImage` can patch one row without the full reload.
    public var items: [ListItem] {
        get { _items }
        set { _items = newValue; reload() }
    }

    /// The theme. Assigning re-snaps the surface and repaints every row (all colour
    /// intent resolves in `drawRows`, so a switch fully re-themes) — the contract.
    public var palette: ResolvedPalette { didSet { applyTheme() } }

    public var density: Density = .comfortable { didSet { if density != oldValue { reload() } } }

    /// `.single` persists one `selectedID`; `.none` paints only hover/highlight
    /// (wand's tome). Switching to `.none` drops any selection silently.
    public var selectionMode: SelectionMode = .single {
        didSet { if selectionMode == .none { setSelection(nil, fire: false) } }
    }

    /// `.wash` = `selection` fill + a 3pt `primary` bar (combo's; reads on neon).
    /// `.solidAccent` = an opaque `primary` fill + `onPrimary()` ink (wand's tome).
    public var hoverStyle: HoverStyle = .wash { didSet { listView.needsDisplay = true } }

    /// Round the selection / highlight fill into a 6pt pill (inset 3pt) — wand's
    /// look. The 3pt accent bar is then omitted (the pill IS the affordance).
    public var roundedSelection = false { didSet { listView.needsDisplay = true } }

    /// Draw a 1pt `border` divider between rows (text-inset; full-bleed above a
    /// section header). Default off.
    public var showsDividers = false { didSet { listView.needsDisplay = true } }

    /// Reserve the leading image column on EVERY row so text aligns under a common
    /// left edge even on image-less rows (facet/wand's mixed icon lists). DEFAULT
    /// true. A list whose rows NEVER carry a leading image (the combo's option
    /// list) sets this false so text sits at `leadingInset` with no empty icon
    /// gutter, and such a row renders no leading image (there is no column for one).
    public var reservesLeadingImageColumn = true {
        didSet { if reservesLeadingImageColumn != oldValue { listView.needsDisplay = true } }
    }

    /// Surface behind the rows — the kit-wide escape hatch (mirrors
    /// ThemedTextField / ThemedComboBox / ThemedDivider): a host on a lifted /
    /// vibrant panel sets the panel's colour. Defaults to `palette.background`.
    /// A nil resolved surface (a vibrancy theme, no override) lets the host show
    /// through: the scroll view stops painting and the section-header band isn't
    /// punched opaque.
    public var surfaceColor: NSColor? { didSet { applyTheme() } }

    /// OPT-IN: the list takes first responder and drives ↑↓/⏎/Esc itself (a menu,
    /// an inline-focused facet list). DEFAULT false so an embedding control (the
    /// combo's field) keeps first responder — its IME / cmd-keys / floating label
    /// keep working while it forwards nav into the list.
    public var managesFirstResponder = false {
        didSet {
            window?.recalculateKeyViewLoop()
            if !managesFirstResponder, listView.window?.firstResponder === listView {
                window?.makeFirstResponder(nil)
            }
        }
    }

    /// `moveHighlight` WRAPS top↔bottom instead of clamping (MUI menu nav;
    /// `disableListWrap = false`). DEFAULT false — a plain list / the combo clamp.
    public var wrapsHighlight = false

    /// Pointer hover drives the SAME `highlightedIndex` keyboard nav uses, so one
    /// row is lit at a time whether reached by mouse or arrows (the menu model —
    /// `hoverStyle = .solidAccent` then lights every row under the pointer). The
    /// last-hovered row STAYS lit when the pointer leaves the list (native menu
    /// feel). DEFAULT false — hover only veils an already-selected row (`.wash`).
    public var highlightFollowsHover = false

    /// Vend a synthetic per-row accessibility child (role `.menuItem`, the row's
    /// primary text as its label, an AXPress that activates the row) for every
    /// ACTIONABLE row — so VoiceOver can navigate a menu hosted in this list. The
    /// children are rebuilt from the live layout on each AX query (frames stay
    /// valid across scroll). DEFAULT false — the list vends no per-row AX (the
    /// combo's documented basic limitation). NOTE: the synthetic tree is unit-tested
    /// (count / role / label / flipped frame / press) but VoiceOver TRAVERSAL over a
    /// non-key panel is a live hand-check.
    public var vendsRowAXElements = false { didSet { listView.needsDisplay = true } }

    // Empty state (promoted from ComboBox — B2). When `items` is empty:
    //   * `emptyActionRow?(query)` non-nil ⇒ ONE actionable row (foreground,
    //     highlightable, activatable → `onEmptyAction(query)`);
    //   * else the inert `noOptionsText` (muted, non-selectable).
    public var emptyActionRow: ((_ query: String) -> String?)? = nil { didSet { renderEmptyState() } }
    public var query = "" { didSet { if items.isEmpty { renderEmptyState() } } }
    public var noOptionsText = "No options" { didSet { if items.isEmpty { listView.needsDisplay = true } } }

    /// The committed selection (`.single` mode). The SETTER IS SILENT (programmatic
    /// — repaints + scrolls into view, fires NO callback); `selectRow(_:)` is the
    /// user-intent counterpart that fires `onSelectionChange`. Forced nil in `.none`.
    public var selectedID: String? {
        get { _selectedID }
        set { setSelection(newValue, fire: false) }
    }

    /// The selected `ListItem`, or nil.
    public var selectedItem: ListItem? { _selectedID.flatMap { id in items.first { $0.id == id } } }

    /// The id of the row currently highlighted by keyboard nav / hover (or the
    /// synthetic empty-action row), nil if none. Read-only — drive it with
    /// `moveHighlight` / `clearHighlight` (or hover when `highlightFollowsHover`).
    public var highlightedID: String? {
        effectiveHighlightIndex.flatMap { items.indices.contains($0) ? items[$0].id
            : (isActionRowActive ? ThemedList.emptyActionID : nil) }
    }

    /// Total height of all rows (the laid-out doc height) — for a host that sizes a
    /// container to the list's content (a menu). Independent of the view's frame.
    public var contentHeight: CGFloat { rowLayout.totalHeight }

    // Capture / preview seams (deterministic still capture + tests; id-keyed).
    public var previewHighlight: String? = nil { didSet { listView.needsDisplay = true } }
    public var previewSelection: String? = nil { didSet { listView.needsDisplay = true } }
    /// Force the clip view scrolled to this doc-y (so a static capture shows a
    /// pinned / handing-off sticky header). nil = live scroll. Applied once the
    /// view is actually sized (re-asserted from `layout()` while pending), so it
    /// survives the NSViewRepresentable size-after-make ordering yet never fights a
    /// later manual scroll. A capture/preview seam like `previewHighlight` (always
    /// compiled — the showcase uses it in any build config).
    public var previewScrollY: CGFloat? = nil {
        didSet { previewScrollPending = previewScrollY != nil; applyPreviewScroll(); listView.needsDisplay = true }
    }
    private var previewScrollPending = false

    // MARK: Callbacks (the host's 実処理)

    /// A row activated (click / Enter on the highlight). Never fires for a header,
    /// a disabled row, or the inert no-options row.
    public var onActivate: ((ListItem) -> Void)? = nil
    /// The committed selection changed BY THE USER (a click in `.single` mode or
    /// `selectRow`). NOT fired by a programmatic `selectedID =`.
    public var onSelectionChange: ((String?) -> Void)? = nil
    /// The actionable empty row was committed, carrying the live `query`.
    public var onEmptyAction: ((_ query: String) -> Void)? = nil
    /// The hovered row id changed (nil on exit). Headers / disabled rows report nil.
    public var onHover: ((String?) -> Void)? = nil

    // MARK: Internals

    private var _items: [ListItem] = []
    private var _selectedID: String?
    private var highlightedIndex: Int?       // into `items` (or 0 = the synthetic empty action row)
    private var hoveredIndex: Int?           // into `items`
    private var emptyLabel: String?          // resolved emptyActionRow label (nil ⇒ inert)
    private var rowLayout = RowLayout()         // cached per reload (mixed-height rows)

    private let scrollView = NSScrollView()
    // A vertical-shaped frame so NSScroller infers a vertical scroller; the scroll
    // view resizes it. Themed in `applyTheme` so the knob reads in-palette.
    private let vScroller = ThemedScroller(frame: NSRect(x: 0, y: 0, width: 16, height: 100))
    private var listView: ListDocumentView!
    private var focusRingLayer: CAShapeLayer?

    #if DEBUG
    private(set) var lastInvalidatedRects: [CGRect] = []
    #endif

    /// True when `items` is empty AND an actionable row is offered — the single
    /// synthetic row 0 is then highlightable / activatable.
    private var isActionRowActive: Bool { items.isEmpty && emptyLabel != nil }

    // MARK: Metrics

    private struct Metrics {
        let singleRow, twoLineRow, header1, header2: CGFloat
        let leadingInset, trailingInset, imageBox, iconGlyph, gapImageToText: CGFloat
        let twoLineTop, lineGap: CGFloat
        let primaryPt, secondaryPt: CGFloat
        let accentBar, roundedRadius, roundedHInset: CGFloat
        let badgeHeight, badgeHPad, badgeSymbolPt, badgePt, badgeGap: CGFloat
        let chevronPt, shortcutHeight, shortcutHPad, shortcutRadius, shortcutPt: CGFloat
        let header1Pt, header2TitlePt, header2SubPt: CGFloat
        let clusterGap, budgetMargin, separatorBand: CGFloat
        var textXOrigin: CGFloat { leadingInset + imageBox + gapImageToText }
    }

    private var metrics: Metrics {
        switch density {
        case .comfortable:
            return Metrics(singleRow: 30, twoLineRow: 46, header1: 28, header2: 40,
                           leadingInset: 12, trailingInset: 12, imageBox: 24, iconGlyph: 18, gapImageToText: 8,
                           twoLineTop: 8, lineGap: 2, primaryPt: 13, secondaryPt: 11,
                           accentBar: 3, roundedRadius: 6, roundedHInset: 3,
                           badgeHeight: 16, badgeHPad: 6, badgeSymbolPt: 11, badgePt: 10, badgeGap: 4,
                           chevronPt: 11, shortcutHeight: 16, shortcutHPad: 5, shortcutRadius: 4, shortcutPt: 10,
                           header1Pt: 11, header2TitlePt: 13, header2SubPt: 11,
                           clusterGap: 6, budgetMargin: 8, separatorBand: 9)
        case .compact:
            // header2 == comfortable's 40: the 2-line title(13)+subtitle(11) content
            // doesn't shrink with density, so a shorter row clipped the subtitle.
            return Metrics(singleRow: 26, twoLineRow: 40, header1: 24, header2: 40,
                           leadingInset: 10, trailingInset: 10, imageBox: 20, iconGlyph: 16, gapImageToText: 6,
                           twoLineTop: 6, lineGap: 2, primaryPt: 13, secondaryPt: 11,
                           accentBar: 3, roundedRadius: 6, roundedHInset: 3,
                           badgeHeight: 14, badgeHPad: 6, badgeSymbolPt: 11, badgePt: 9, badgeGap: 4,
                           chevronPt: 10, shortcutHeight: 14, shortcutHPad: 5, shortcutRadius: 4, shortcutPt: 10,
                           header1Pt: 11, header2TitlePt: 13, header2SubPt: 11,
                           clusterGap: 6, budgetMargin: 8, separatorBand: 7)
        }
    }

    // MARK: Init

    public init(palette: ResolvedPalette) {
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true

        let lv = ListDocumentView()
        listView = lv
        lv.owner = self

        scrollView.documentView = lv
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller = vScroller          // theme-painted knob, not macOS grey
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay              // show only while scrolling (auto-hide)
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        lv.autoresizingMask = [.width]                  // doc width tracks the clip; height set explicitly
        addSubview(scrollView)

        // The sticky header is drawn LAST at the visible top, but on macOS 11+ the
        // clip view ALWAYS minimizes the invalidated area on scroll (copiesOnScroll
        // is a deprecated no-op), so a scroll only repaints the newly-exposed strip —
        // the pinned header would tear / ghost. Observe the clip's bounds change and
        // explicitly invalidate the old ∪ new sticky band so the header stays crisp.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsChanged),
                                               name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)

        applyTheme()
        reload()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    public override func layout() {
        super.layout()
        // Keep the doc view as wide as the clip (height owned by `reload`).
        let w = scrollView.contentView.bounds.width
        if w > 0, listView.bounds.width != w {
            listView.setFrameSize(NSSize(width: w, height: rowLayout.totalHeight))
        }
        updateFocusRingPath()
        if previewScrollPending { applyPreviewScroll() }
    }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        let w = scrollView.contentView.bounds.width
        if w > 0, listView.bounds.width != w {
            listView.setFrameSize(NSSize(width: w, height: rowLayout.totalHeight))
        }
        updateFocusRingPath()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The eager `recalculateKeyViewLoop()` in the `managesFirstResponder` didSet
        // is a no-op when the flag is set BEFORE the view is in a window (the common
        // NSViewRepresentable configure-during-make ordering) — rebuild it on attach.
        if managesFirstResponder { window?.recalculateKeyViewLoop() }
    }

    // MARK: Theming

    public func applyTheme() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)           // snap — no implicit cross-fade (combo parity)
        let surface = effectiveSurface
        // Paint the surface only when it is fully opaque; a nil (vibrancy) or
        // translucent surface lets the lifted/vibrant host show through.
        scrollView.drawsBackground = (surface?.alphaComponent ?? 0) >= 1
        scrollView.backgroundColor = surface ?? .clear
        vScroller.knobColor = palette.muted              // themed scroll knob (vs macOS grey)
        focusRingLayer?.strokeColor = palette.primary.cgColor
        CATransaction.commit()
        listView?.needsDisplay = true
    }

    /// The resolved row surface (override → theme background → nil for vibrancy).
    /// nil means "don't paint" (vs the opaque scroll-view fallback).
    private var effectiveSurface: NSColor? { surfaceColor ?? palette.background }

    private func themedFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        switch palette.font {
        case .mono: return .monospacedSystemFont(ofSize: size, weight: weight)
        default:    return .systemFont(ofSize: size, weight: weight)
        }
    }

    // MARK: Data / layout

    /// Relayout (mixed heights), reconcile selection + highlight, resize the doc
    /// view, repaint. The single entry point for any `items`/`density` change.
    public func reload() {
        renderEmptyState()
        recomputeLayout()
        // Reconcile the committed selection BY ID (cleaner than the combo's index
        // reconcile): keep it if still present + selectable, else drop (silently).
        if let id = _selectedID, !(items.contains { $0.id == id && isSelectable($0) }) {
            _selectedID = nil
        }
        if let h = highlightedIndex, !(items.indices.contains(h) && isSelectable(items[h])) {
            highlightedIndex = isActionRowActive ? 0 : nil
        }
        hoveredIndex = nil
        listView.setFrameSize(NSSize(width: scrollView.contentView.bounds.width, height: rowLayout.totalHeight))
        listView.needsDisplay = true
        listView.window?.invalidateCursorRects(for: listView)
    }

    private func renderEmptyState() {
        emptyLabel = items.isEmpty ? emptyActionRow?(query) : nil
        listView?.needsDisplay = true
    }

    private func recomputeLayout() {
        var ys: [CGFloat] = [], hs: [CGFloat] = [], headers: [Int] = []
        var y: CGFloat = 0
        if items.isEmpty {
            ys = [0]; hs = [metrics.singleRow]; y = metrics.singleRow         // one synthetic row
        } else {
            for (i, item) in items.enumerated() {
                let h = rowHeight(for: item)
                ys.append(y); hs.append(h); y += h
                if item.isHeader { headers.append(i) }
            }
        }
        rowLayout = RowLayout(yOffsets: ys, heights: hs, totalHeight: y, headerIndices: headers)
    }

    private func rowHeight(for item: ListItem) -> CGFloat {
        let m = metrics
        if item.isSeparator { return m.separatorBand }
        if item.isHeader { return item.headerSubtitle != nil ? m.header2 : m.header1 }
        return item.secondary != nil ? m.twoLineRow : m.singleRow
    }

    private var docWidth: CGFloat { listView.bounds.width }

    /// Where a row's text/secondary starts: after the reserved leading image
    /// column, or at `leadingInset` when the column is suppressed (an image-less
    /// list — the combo's option rows, so they sit flush like the old ComboListView).
    private var rowTextX: CGFloat { reservesLeadingImageColumn ? metrics.textXOrigin : metrics.leadingInset }

    /// A row's rect in the flipped doc view (y grows down).
    private func rowRect(_ i: Int) -> CGRect {
        if items.isEmpty { return CGRect(x: 0, y: 0, width: docWidth, height: metrics.singleRow) }
        guard rowLayout.yOffsets.indices.contains(i) else { return .zero }
        return CGRect(x: 0, y: rowLayout.yOffsets[i], width: docWidth, height: rowLayout.heights[i])
    }

    private func isSelectable(_ item: ListItem) -> Bool { !item.isHeader && !item.isSeparator && !item.isDisabled }

    private func indexOf(_ id: String?) -> Int? { id.flatMap { id in items.firstIndex { $0.id == id } } }

    // MARK: Selection / highlight resolution

    private var effectiveSelectionIndex: Int? {
        // Mode guard FIRST so a `previewSelection` can't paint a wash in `.none`
        // mode (the live path can't); then resolve preview-over-live and reject a
        // non-selectable target, exactly mirroring what `setSelection` permits.
        guard selectionMode == .single else { return nil }
        guard let i = indexOf(previewSelection ?? _selectedID), isSelectable(items[i]) else { return nil }
        return i
    }

    private var effectiveHighlightIndex: Int? {
        if items.isEmpty {
            // Honor a forced preview of the synthetic action row (capture seam); else the live highlight.
            if previewHighlight == ThemedList.emptyActionID { return isActionRowActive ? 0 : nil }
            return (isActionRowActive && highlightedIndex == 0) ? 0 : nil
        }
        if let pv = previewHighlight {
            // Never highlight a non-selectable row (mirrors effectiveSelectionIndex);
            // the live nav already skips them, so this only guards the preview seam.
            guard let i = indexOf(pv), isSelectable(items[i]) else { return nil }
            return i
        }
        return highlightedIndex
    }

    /// The ONLY selection mutator — repaints old+new, optionally scrolls + fires.
    private func setSelection(_ id: String?, fire: Bool) {
        let resolved: String? = id.flatMap { id in
            items.contains { $0.id == id && isSelectable($0) } ? id : nil
        }
        let old = _selectedID
        guard resolved != old else { if fire { onSelectionChange?(resolved) }; return }
        _selectedID = resolved
        invalidateRows([indexOf(old), indexOf(resolved)])
        // Reveal the committed row (honours the documented "scrolls into view"; a
        // no-op before layout or for an already-visible row — e.g. the click path).
        if let i = indexOf(resolved) { scrollRowVisible(i, position: .nearest) }
        if fire { onSelectionChange?(resolved) }
    }

    // MARK: Public methods

    /// Swap one row's leading image (an async favicon landing) WITHOUT a full
    /// reload — invalidates only that row's rect (+ the sticky band if it pins).
    public func setLeadingImage(_ image: NSImage?, forID id: String) {
        guard let i = indexOf(id) else { return }
        _items[i].image = image         // patch the backing store — no full reload (height is unchanged)
        invalidateRows([i])
    }

    /// The row's rect in the flipped doc view (for a host DnD / accessory overlay).
    /// nil if the id isn't on the list. `emptyActionID` returns the synthetic row.
    public func rowFrame(for id: String) -> CGRect? {
        if items.isEmpty { return (isActionRowActive && id == ThemedList.emptyActionID) ? rowRect(0) : nil }
        return indexOf(id).map { rowRect($0) }
    }

    public func scrollToRow(_ id: String, position: ScrollPosition = .nearest) {
        guard let i = indexOf(id) else { return }
        scrollRowVisible(i, position: position)
    }

    /// The row's rect in SCREEN coordinates (the flipped-doc rect walked out through
    /// the scroll offset → window → screen), or nil if off-list / no window. For a
    /// host anchoring a child popup to a specific row (a submenu beside its parent
    /// row) or a drag drop-band; the conversion accounts for the current scroll.
    public func rowRectOnScreen(for id: String) -> CGRect? {
        guard let win = window, let r = rowFrame(for: id) else { return nil }
        return win.convertToScreen(listView.convert(r, to: nil))
    }

    /// The content width that fits every row's text without truncation, capped at
    /// `maxWidth` — for a host that sizes a container to the list (a menu sizes to
    /// its widest item). Accounts for the leading slot, the trailing cluster
    /// (shortcut / chevron / badges) and both insets. Rows past the cap ellipsize.
    public func fittingWidth(maxWidth: CGFloat = .greatestFiniteMagnitude) -> CGFloat {
        let m = metrics
        var w: CGFloat = 0
        for item in items where !item.isSeparator {
            let textX = item.isHeader ? m.leadingInset : rowTextX
            let pFont: NSFont = item.isHeader
                ? (item.headerSubtitle != nil ? themedFont(m.header2TitlePt, .medium) : themedFont(m.header1Pt, .semibold))
                : themedFont(m.primaryPt)
            let isOneLineHeader = item.isHeader && item.headerSubtitle == nil
            let pText = isOneLineHeader ? item.primary.uppercased() : item.primary
            // A 1-line header is DRAWN with `headerKern` per character — measure it
            // the same way (else it under-measures by kern × (chars−1)).
            var textW = isOneLineHeader
                ? ceil((pText as NSString).size(withAttributes: [.font: pFont, .kern: ThemedList.headerKern]).width)
                : measureWidth(pText, font: pFont)
            if let secondary = item.secondary {
                let sFont = item.secondaryMono ? .monospacedSystemFont(ofSize: m.secondaryPt, weight: .regular)
                                               : themedFont(m.secondaryPt)
                textW = max(textW, measureWidth(secondary, font: sFont))
            }
            if let sub = item.headerSubtitle {
                textW = max(textW, measureWidth(sub, font: themedFont(m.header2SubPt)))
            }
            let trailing = item.isHeader ? 0 : trailingClusterWidth(item)
            let rowW = textX + textW + (trailing > 0 ? trailing + m.budgetMargin : 0) + m.trailingInset
            w = max(w, rowW)
        }
        return min(maxWidth, ceil(w))
    }

    private func measureWidth(_ s: String, font: NSFont) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: font]).width)
    }

    /// USER-intent selection (fires `onSelectionChange`). Ignored in `.none`.
    public func selectRow(_ id: String?) {
        guard selectionMode == .single else { return }
        setSelection(id, fire: true)
    }

    /// Activate a row by id (fires `onActivate`, or `onEmptyAction` for the empty
    /// row). A header / disabled / unknown id is a no-op.
    public func activateRow(_ id: String) {
        if isActionRowActive, id == ThemedList.emptyActionID { fireEmptyAction(); return }
        guard let i = indexOf(id) else { return }
        activate(i)
    }

    // MARK: Accessibility (synthetic per-row `.menuItem` children — opt-in)

    fileprivate var vendsRowAXElementsFlag: Bool { vendsRowAXElements }

    /// Build the synthetic per-row AX children FRESH from the current layout (so
    /// frames stay valid across scroll / reload). One element per ACTIONABLE row
    /// (+ an active empty-action row); headers / separators / disabled rows get
    /// none. Role `.menuItem`, label = the row's primary text, AXPress activates it.
    fileprivate func buildAXChildren() -> [NSAccessibilityElement] {
        guard vendsRowAXElements, let lv = listView else { return [] }
        let docHeight = lv.bounds.height
        if items.isEmpty {
            guard isActionRowActive, let label = emptyLabel else { return [] }
            return [makeAXRow(id: ThemedList.emptyActionID, label: label, checked: false, rect: rowRect(0), docHeight: docHeight)]
        }
        return items.indices.filter { isSelectable(items[$0]) }
            .map { makeAXRow(id: items[$0].id, label: items[$0].primary, checked: items[$0].axChecked,
                             rect: rowRect($0), docHeight: docHeight) }
    }

    private func makeAXRow(id: String, label: String, checked: Bool, rect: CGRect, docHeight: CGFloat) -> RowAXElement {
        let el = RowAXElement(owner: self, rowID: id)
        el.setAccessibilityRole(.menuItem)
        // Fold a "checked" marker into the label VoiceOver reads (a synthetic
        // `.menuItem` element doesn't reliably surface AXMenuItemMarkChar).
        el.setAccessibilityLabel(checked ? "\(label), checked" : label)
        el.setAccessibilityParent(listView)
        // The doc view is FLIPPED (row 0 at top, y grows down) but AX frames are
        // y-up → convert the flipped rowRect into the parent's y-up space.
        el.setAccessibilityFrameInParentSpace(
            CGRect(x: rect.minX, y: docHeight - rect.maxY, width: rect.width, height: rect.height))
        return el
    }

    // MARK: Interaction (driven by the doc view)

    fileprivate func rowIndex(atDocY y: CGFloat) -> Int? {
        guard y >= 0 else { return nil }
        if items.isEmpty { return y < metrics.singleRow ? 0 : nil }
        for i in items.indices where y >= rowLayout.yOffsets[i] && y < rowLayout.yOffsets[i] + rowLayout.heights[i] {
            return i
        }
        return nil
    }

    fileprivate func handleClick(atDocY y: CGFloat) {
        guard let i = rowIndex(atDocY: y) else { return }
        if items.isEmpty { if isActionRowActive { fireEmptyAction() }; return }
        // Swallow a click that lands under the PINNED sticky header — the row there
        // is occluded, and the header (pin.index) is never selectable.
        if let pin = stickyHeader(atVisibleTop: listView.visibleRect.minY),
           y >= pin.drawY, y < pin.drawY + rowLayout.heights[pin.index], i != pin.index {
            return
        }
        activate(i)
    }

    private func activate(_ i: Int) {
        guard items.indices.contains(i), isSelectable(items[i]) else { return }
        if selectionMode == .single { setSelection(items[i].id, fire: true) }
        onActivate?(items[i])
    }

    private func fireEmptyAction() {
        guard isActionRowActive else { return }
        onEmptyAction?(query)
    }

    fileprivate func hoverRow(atDocY y: CGFloat?) {
        // The actionable empty row is the one empty-state row that lights on hover
        // (combo parity — its highlight drives drawEmptyRow's wash); report its
        // synthetic id. Dedup via highlightedIndex (setHighlight early-returns).
        if isActionRowActive {
            let target: Int? = (y.map { $0 >= 0 && $0 < metrics.singleRow } ?? false) ? 0 : nil
            guard target != highlightedIndex else { return }
            setHighlight(target)
            onHover?(target == 0 ? ThemedList.emptyActionID : nil)
            return
        }
        var idx = y.flatMap { rowIndex(atDocY: $0) }
        // A point under the pinned header, or over a header / separator / disabled
        // row, hovers nothing (`isSelectable` covers all three).
        if let i = idx {
            if items.isEmpty || !isSelectable(items[i]) { idx = nil }
            else if let yy = y, let pin = stickyHeader(atVisibleTop: listView.visibleRect.minY),
                    yy >= pin.drawY, yy < pin.drawY + rowLayout.heights[pin.index] { idx = nil }
        }
        // Menu model: the pointer drives the SAME highlight as the arrows (one lit
        // row), and the last-hovered row STAYS lit when the pointer leaves (native
        // menu feel — don't clear on a nil/over-gap move).
        if highlightFollowsHover {
            if let idx { setHighlight(idx) }
            onHover?(idx.flatMap { items.indices.contains($0) ? items[$0].id : nil })
            return
        }
        guard idx != hoveredIndex else { return }
        let old = hoveredIndex
        hoveredIndex = idx
        invalidateRows([old, idx])
        onHover?(idx.flatMap { items.indices.contains($0) ? items[$0].id : nil })
    }

    fileprivate func clearHover() { hoverRow(atDocY: nil) }

    /// Move the keyboard highlight to the next / previous selectable row (skips
    /// headers / separators / disabled). CLAMPED at the ends by default; WRAPS
    /// top↔bottom when `wrapsHighlight` (the menu). Scrolls the target into view;
    /// opens nothing (the host owns visibility). Public so a host driving keys
    /// itself (a menu's keyDown monitor) can move the highlight without the list
    /// being first responder.
    public func moveHighlight(_ delta: Int) {
        if isActionRowActive { setHighlight(0); return }
        let sel = items.indices.filter { isSelectable(items[$0]) }
        guard !sel.isEmpty else { setHighlight(nil); return }
        let target: Int
        if let cur = highlightedIndex, let pos = sel.firstIndex(of: cur) {
            let n = sel.count
            let np = wrapsHighlight ? ((pos + delta) % n + n) % n
                                    : min(max(pos + delta, 0), n - 1)
            target = sel[np]
        } else {
            target = delta > 0 ? sel.first! : sel.last!
        }
        setHighlight(target)
        scrollRowVisible(target, position: .nearest)
    }

    private func setHighlight(_ i: Int?) {
        guard i != highlightedIndex else { return }
        let old = highlightedIndex
        highlightedIndex = i
        invalidateRows([old, i])
    }

    /// Activate the highlighted row (fires `onActivate`, or `onEmptyAction`). A
    /// no-op when nothing is highlighted. Public — a menu's Enter routes here.
    public func activateHighlight() {
        if isActionRowActive { fireEmptyAction(); return }
        if let h = highlightedIndex, items.indices.contains(h), isSelectable(items[h]) { activate(h) }
    }

    /// Drop the keyboard / hover highlight. Public — a menu clears it on dismiss.
    public func clearHighlight() { setHighlight(nil) }

    // MARK: Invalidation (per-row — D1, never the blunt full bounds)

    private func invalidateRows(_ indices: [Int?]) {
        guard listView != nil else { return }
        var rects: [CGRect] = []
        let bandTop = listView.visibleRect.minY
        let maxHeader = rowLayout.headerIndices.map { rowLayout.heights[$0] }.max() ?? 0
        var touchesBand = false
        // Filter by row VALIDITY (height > 0), NOT `!isEmpty` — a real row is
        // zero-WIDTH before the view is sized (headless tests), and an empty
        // CGRect is also zero-width, so `isEmpty` would wrongly drop valid rows.
        for case let i? in indices where rowRect(i).height > 0 {
            let r = rowRect(i)
            rects.append(r)
            if maxHeader > 0, r.minY < bandTop + maxHeader, r.maxY > bandTop { touchesBand = true }
        }
        // If an invalidated row sits within (or under) the sticky band, the pinned
        // header must repaint ON TOP — invalidate that top strip too (D1 gotcha).
        if touchesBand {
            rects.append(CGRect(x: 0, y: bandTop, width: docWidth, height: maxHeader))
        }
        for r in rects { listView.setNeedsDisplay(r) }
        #if DEBUG
        lastInvalidatedRects = rects
        #endif
    }

    private var lastBandTop: CGFloat = 0

    /// On scroll, repaint the union of the OLD and NEW sticky-band top strips so the
    /// pinned header redraws (the clip view only invalidates the newly-exposed rows).
    @objc private func clipBoundsChanged() {
        let maxHeader = rowLayout.headerIndices.map { rowLayout.heights[$0] }.max() ?? 0
        let newTop = listView.visibleRect.minY
        guard maxHeader > 0 else { lastBandTop = newTop; return }
        let lo = min(newTop, lastBandTop)
        let hi = max(newTop, lastBandTop) + maxHeader
        listView.setNeedsDisplay(CGRect(x: 0, y: lo, width: docWidth, height: hi - lo))
        lastBandTop = newTop
    }

    // MARK: Sticky header (draw-last math — D2)

    /// The section header to PIN for a given visible-top y, and the y at which to
    /// draw it (handing off — the next header pushes the current one up). nil when
    /// no header is at/above the top. Pure (takes the scroll y) so tests need no
    /// live window.
    func stickyHeader(atVisibleTop bandTop: CGFloat) -> (index: Int, drawY: CGFloat)? {
        guard let active = rowLayout.headerIndices.last(where: { rowLayout.yOffsets[$0] <= bandTop }) else { return nil }
        let hH = rowLayout.heights[active]
        var drawY = bandTop
        if let next = rowLayout.headerIndices.first(where: { rowLayout.yOffsets[$0] > rowLayout.yOffsets[active] }) {
            let nextTop = rowLayout.yOffsets[next]
            if nextTop - bandTop < hH { drawY = nextTop - hH }      // push up (may go < bandTop)
        }
        return (active, drawY)
    }

    private func scrollRowVisible(_ i: Int, position: ScrollPosition) {
        guard rowLayout.yOffsets.indices.contains(i) else { return }
        let y = rowLayout.yOffsets[i], h = rowLayout.heights[i]
        // Inflate the target UP by the tallest header so an up-arrow row never
        // lands UNDER the pinned header (the sticky band occludes the top strip).
        let occluder = rowLayout.headerIndices.map { rowLayout.heights[$0] }.max() ?? 0
        let target: CGRect
        switch position {
        case .nearest: target = CGRect(x: 0, y: max(0, y - occluder), width: docWidth, height: h + occluder)
        case .top:     target = CGRect(x: 0, y: max(0, y - occluder), width: docWidth, height: scrollView.contentView.bounds.height)
        case .center:
            let vh = scrollView.contentView.bounds.height
            target = CGRect(x: 0, y: max(0, y - (vh - h) / 2), width: docWidth, height: vh)
        }
        listView.scrollToVisible(target)
    }

    private func applyPreviewScroll() {
        guard let y = previewScrollY else { return }
        // Needs a real clip size + scrollable overflow; retried from layout() while pending.
        guard scrollView.contentView.bounds.height > 0,
              rowLayout.totalHeight > scrollView.contentView.bounds.height else { return }
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        previewScrollPending = false
    }

    // MARK: First-responder ring (managesFirstResponder)

    fileprivate var managesFR: Bool { managesFirstResponder }

    fileprivate func setFocusRing(visible: Bool) {
        if visible {
            let ring = focusRingLayer ?? makeFocusRing()
            ring.isHidden = false
            updateFocusRingPath()
        } else {
            focusRingLayer?.isHidden = true
        }
    }

    private func makeFocusRing() -> CAShapeLayer {
        let ring = CAShapeLayer()
        ring.fillColor = nil
        ring.strokeColor = palette.primary.cgColor
        ring.lineWidth = 2
        layer?.addSublayer(ring)
        focusRingLayer = ring
        return ring
    }

    private func updateFocusRingPath() {
        guard let ring = focusRingLayer, !ring.isHidden else { return }
        ring.frame = bounds
        ring.path = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: 4, cornerHeight: 4, transform: nil)
    }
}

// MARK: - Drawing

extension ThemedList {

    /// Called by the flipped doc view's `draw(_:)`. Rows first (culled by the dirty
    /// rect), then the sticky header LAST so it overpaints whatever it pins.
    fileprivate func drawRows(_ view: ListDocumentView, dirty: NSRect) {
        let width = view.bounds.width

        if items.isEmpty { drawEmptyRow(width: width); return }

        let effSel = effectiveSelectionIndex
        let effHi = effectiveHighlightIndex
        for i in items.indices {
            let r = rowRect(i)
            guard r.intersects(dirty) else { continue }
            drawRow(i, in: r, width: width, isSel: effSel == i, isHi: effHi == i)
        }
        drawStickyHeader(view, width: width)
    }

    private func drawEmptyRow(width: CGFloat) {
        let m = metrics
        let r = CGRect(x: 0, y: 0, width: width, height: m.singleRow)
        if let label = emptyLabel {
            if effectiveHighlightIndex == 0 { paintSelectionBackground(r, onAccent: false) }
            drawLine(label, font: themedFont(m.primaryPt), color: palette.foreground,
                     x: m.leadingInset, maxWidth: width - m.leadingInset * 2, row: r, mode: .byTruncatingTail)
        } else {
            drawLine(noOptionsText, font: themedFont(m.primaryPt), color: palette.muted,
                     x: m.leadingInset, maxWidth: width - m.leadingInset * 2, row: r, mode: .byTruncatingTail)
        }
    }

    private func drawRow(_ i: Int, in r: CGRect, width: CGFloat, isSel: Bool, isHi: Bool) {
        let item = items[i]
        if item.isHeader { drawHeader(item, in: r, width: width); return }
        if item.isSeparator { drawSeparator(in: r, width: width); return }

        let m = metrics
        let onAccent = (isSel || isHi) && hoverStyle == .solidAccent

        // 1. Backgrounds: tint bar (under everything), then selection/hover.
        if item.tint != .none, !onAccent {
            resolvedTint(item.tint).setFill()
            CGRect(x: 0, y: r.minY, width: m.accentBar, height: r.height).fill()
        }
        if isSel || isHi { paintSelectionBackground(r, onAccent: onAccent) }
        // Pointer veil over a selected row (wash mode) so the hovered row reads on top.
        if hoverStyle == .wash, isSel, hoveredIndex == i {
            palette.hover.setFill()
            selectionPath(r).fill()
        }

        // 2. Trailing cluster width FIRST (so the text budget is right), drawn later.
        let trailingW = trailingClusterWidth(item)

        // 3. Leading image: a TEMPLATE glyph centres at `iconGlyph` (18/16) inside
        //    the `imageBox` reservation (no upscale); a colour favicon fills the box.
        if reservesLeadingImageColumn, let image = item.image {
            let side = image.isTemplate ? m.iconGlyph : m.imageBox
            let box = CGRect(x: m.leadingInset + (m.imageBox - side) / 2, y: r.midY - side / 2, width: side, height: side)
            drawImage(image, fitting: box, tint: onAccent ? palette.onPrimary(1) : (image.isTemplate ? palette.foreground : nil))
        }

        // 4. Text stack.
        let xText = rowTextX
        let textMax = max(0, r.maxX - m.trailingInset - (trailingW > 0 ? trailingW + m.budgetMargin : 0) - xText)
        let primaryColor = primaryTextColor(disabled: item.isDisabled, onAccent: onAccent)
        if let secondary = item.secondary {
            let pFont = themedFont(m.primaryPt)
            let pH = (pFont.ascender - pFont.descender)
            let pRow = CGRect(x: 0, y: r.minY + m.twoLineTop, width: r.width, height: pH)
            drawLine(item.primary, font: pFont, color: primaryColor, x: xText, maxWidth: textMax, row: pRow, mode: .byTruncatingTail)
            let sFont = item.secondaryMono ? .monospacedSystemFont(ofSize: m.secondaryPt, weight: .regular) : themedFont(m.secondaryPt)
            let sColor = secondaryTextColor(disabled: item.isDisabled, onAccent: onAccent)
            let sRow = CGRect(x: 0, y: pRow.maxY + m.lineGap, width: r.width, height: sFont.ascender - sFont.descender)
            drawLine(secondary, font: sFont, color: sColor, x: xText, maxWidth: textMax, row: sRow,
                     mode: item.secondaryMono ? .byTruncatingMiddle : .byTruncatingTail)
        } else {
            drawLine(item.primary, font: themedFont(m.primaryPt), color: primaryColor,
                     x: xText, maxWidth: textMax, row: r, mode: .byTruncatingTail)
        }

        // 5. Trailing cluster (right-to-left).
        drawTrailingCluster(item, in: r, onAccent: onAccent)

        // 6. Divider between rows (not after the last; full-bleed above a header;
        //    suppressed above a separator row, which draws its own rule).
        if showsDividers, i < items.count - 1, !items[i + 1].isSeparator {
            let nextIsHeader = items[i + 1].isHeader
            let x = nextIsHeader ? 0 : rowTextX
            palette.border.setFill()
            CGRect(x: x, y: r.maxY - 1, width: width - x - (nextIsHeader ? 0 : m.trailingInset), height: 1).fill()
        }
    }

    // MARK: Backgrounds

    private func selectionPath(_ r: CGRect) -> NSBezierPath {
        roundedSelection
            ? NSBezierPath(roundedRect: r.insetBy(dx: metrics.roundedHInset, dy: 0),
                           xRadius: metrics.roundedRadius, yRadius: metrics.roundedRadius)
            : NSBezierPath(rect: r)
    }

    private func paintSelectionBackground(_ r: CGRect, onAccent: Bool) {
        if onAccent {
            palette.primary.setFill()
            selectionPath(r).fill()
        } else {
            palette.selection.setFill()
            selectionPath(r).fill()
            if !roundedSelection {                          // the 3pt accent bar (combo's; reads on neon)
                palette.primary.setFill()
                CGRect(x: 0, y: r.minY, width: metrics.accentBar, height: r.height).fill()
            }
        }
    }

    private func resolvedTint(_ tint: ListTint) -> NSColor {
        switch tint {
        case .none:      return .clear
        case .primary:   return palette.primary
        case .secondary: return palette.secondary
        case .error:     return palette.error
        case .custom(let hex): return NSColor(hex)
        }
    }

    // Row text-colour decisions — the SINGLE source the renderer + the DEBUG probe
    // both call (so the test exercises real draw logic, like `_badgeFill`).
    fileprivate func primaryTextColor(disabled: Bool, onAccent: Bool) -> NSColor {
        onAccent ? palette.onPrimary(1) : (disabled ? palette.tertiary : palette.foreground)
    }
    fileprivate func secondaryTextColor(disabled: Bool, onAccent: Bool) -> NSColor {
        onAccent ? palette.onPrimary(0.65) : (disabled ? palette.tertiary : palette.muted)
    }

    // MARK: Header

    private func drawHeader(_ item: ListItem, in r: CGRect, width: CGFloat) {
        let m = metrics
        // Cover scrolled rows beneath a pinned header with the surface. Skipped when
        // the surface is nil (pure vibrancy) — there is no opaque colour to punch,
        // and a hard block would defeat the vibrancy the host opted into.
        if let s = effectiveSurface { s.setFill(); r.fill() }
        if let subtitle = item.headerSubtitle {
            let title = themedFont(m.header2TitlePt, .medium)
            let tRow = CGRect(x: 0, y: r.minY + 6, width: r.width, height: title.ascender - title.descender)
            drawLine(item.primary, font: title, color: palette.foreground,
                     x: m.leadingInset, maxWidth: width - m.leadingInset * 2, row: tRow, mode: .byTruncatingTail)
            let sub = themedFont(m.header2SubPt)
            let sRow = CGRect(x: 0, y: tRow.maxY + m.lineGap, width: r.width, height: sub.ascender - sub.descender)
            drawLine(subtitle, font: sub, color: palette.muted,
                     x: m.leadingInset, maxWidth: width - m.leadingInset * 2, row: sRow, mode: .byTruncatingTail)
        } else {
            let f = themedFont(m.header1Pt, .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: palette.muted, .kern: ThemedList.headerKern]
            let label = item.primary.uppercased() as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: m.leadingInset, y: r.minY + (r.height - size.height) / 2), withAttributes: attrs)
        }
        palette.border.setFill()                            // a full-bleed underline
        CGRect(x: 0, y: r.maxY - 1, width: width, height: 1).fill()
    }

    /// A menu separator: a full-bleed 1pt `border` hairline centred in its short
    /// band (the band gives it the breathing room above/below). Non-interactive.
    private func drawSeparator(in r: CGRect, width: CGFloat) {
        palette.border.setFill()
        CGRect(x: 0, y: r.midY - 0.5, width: width, height: 1).fill()
    }

    private func drawStickyHeader(_ view: ListDocumentView, width: CGFloat) {
        guard !rowLayout.headerIndices.isEmpty,
              let pin = stickyHeader(atVisibleTop: view.visibleRect.minY) else { return }
        // Only pin when the header's natural slot is scrolled off the top (else it
        // is already drawn in place by the row loop — pinning would double-draw at
        // the same spot, which is harmless but pointless).
        guard pin.drawY != rowLayout.yOffsets[pin.index] || view.visibleRect.minY > rowLayout.yOffsets[pin.index] else { return }
        let r = CGRect(x: 0, y: pin.drawY, width: width, height: rowLayout.heights[pin.index])
        drawHeader(items[pin.index], in: r, width: width)
    }

    // MARK: Trailing cluster

    private enum TrailingPiece { case accessory(TrailingAccessory); case badge(Badge) }

    private func trailingPieces(_ item: ListItem) -> [TrailingPiece] {
        var pieces: [TrailingPiece] = []
        if item.trailing != .none { pieces.append(.accessory(item.trailing)) }   // rightmost
        for b in item.badges.reversed() { pieces.append(.badge(b)) }
        return pieces
    }

    private func pieceWidth(_ p: TrailingPiece) -> CGFloat {
        switch p {
        case .accessory(let a): return accessoryWidth(a)
        case .badge(let b):     return badgeSize(b).width
        }
    }

    private func gapBefore(_ index: Int, _ pieces: [TrailingPiece]) -> CGFloat {
        guard index > 0 else { return 0 }
        if case (.badge, .badge) = (pieces[index - 1], pieces[index]) { return metrics.badgeGap }
        return metrics.clusterGap
    }

    private func trailingClusterWidth(_ item: ListItem) -> CGFloat {
        let pieces = trailingPieces(item)
        guard !pieces.isEmpty else { return 0 }
        return pieces.enumerated().reduce(0) { $0 + pieceWidth($1.element) + gapBefore($1.offset, pieces) }
    }

    private func drawTrailingCluster(_ item: ListItem, in r: CGRect, onAccent: Bool) {
        let pieces = trailingPieces(item)
        guard !pieces.isEmpty else { return }
        var x = r.maxX - metrics.trailingInset            // right edge, moving left
        for (idx, piece) in pieces.enumerated() {
            x -= gapBefore(idx, pieces)
            let w = pieceWidth(piece)
            let cell = CGRect(x: x - w, y: r.minY, width: w, height: r.height)
            switch piece {
            case .accessory(let a): drawAccessory(a, in: cell, onAccent: onAccent)
            case .badge(let b):     drawBadge(b, in: cell, onAccent: onAccent)
            }
            x -= w
        }
    }

    private func accessoryWidth(_ a: TrailingAccessory) -> CGFloat {
        let m = metrics
        switch a {
        case .none:      return 0
        case .chevron:   return m.chevronPt
        case .shortcut(let s):
            let w = (s as NSString).size(withAttributes: [.font: themedFont(m.shortcutPt, .medium)]).width
            return ceil(w) + m.shortcutHPad * 2
        case .custom(let img):
            guard img.size.height > 0 else { return m.badgeHeight }
            return m.badgeHeight * (img.size.width / img.size.height)
        }
    }

    private func drawAccessory(_ a: TrailingAccessory, in cell: CGRect, onAccent: Bool) {
        let m = metrics
        switch a {
        case .none: break
        case .chevron:
            let color = onAccent ? palette.onPrimary(0.55) : palette.tertiary
            let box = CGRect(x: cell.minX, y: cell.midY - m.chevronPt / 2, width: m.chevronPt, height: m.chevronPt)
            if let img = sfImage("chevron.right", pt: m.chevronPt) { drawImage(img, fitting: box, tint: color) }
        case .shortcut(let s):
            let h = m.shortcutHeight
            let lozenge = CGRect(x: cell.minX, y: cell.midY - h / 2, width: cell.width, height: h)
            let path = NSBezierPath(roundedRect: lozenge, xRadius: m.shortcutRadius, yRadius: m.shortcutRadius)
            (onAccent ? palette.onPrimary(0.4) : palette.border).setStroke()
            path.lineWidth = 1; path.stroke()
            let attrs: [NSAttributedString.Key: Any] = [.font: themedFont(m.shortcutPt, .medium),
                                                         .foregroundColor: onAccent ? palette.onPrimary(1) : palette.muted]
            let str = s as NSString
            let size = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(x: lozenge.midX - size.width / 2, y: lozenge.midY - size.height / 2), withAttributes: attrs)
        case .custom(let img):
            drawImage(img, fitting: cell, tint: onAccent && img.isTemplate ? palette.onPrimary(1) : nil)
        }
    }

    // MARK: Badge

    private func badgeSize(_ b: Badge) -> CGSize {
        let m = metrics
        let attrs: [NSAttributedString.Key: Any] = [.font: themedFont(m.badgePt, .medium)]
        var w = ceil((b.text as NSString).size(withAttributes: attrs).width) + m.badgeHPad * 2
        if b.symbol != nil { w += m.badgeSymbolPt + 3 }
        return CGSize(width: w, height: m.badgeHeight)
    }

    private func drawBadge(_ b: Badge, in cell: CGRect, onAccent: Bool) {
        let m = metrics
        let h = m.badgeHeight
        let pill = CGRect(x: cell.minX, y: cell.midY - h / 2, width: cell.width, height: h)
        let (fill, ink) = badgeColors(b.role, onAccent: onAccent)
        fill.setFill()
        NSBezierPath(roundedRect: pill, xRadius: h / 2, yRadius: h / 2).fill()
        var x = pill.minX + m.badgeHPad
        if let symbol = b.symbol {
            let box = CGRect(x: x, y: pill.midY - m.badgeSymbolPt / 2, width: m.badgeSymbolPt, height: m.badgeSymbolPt)
            drawImage(symbol, fitting: box, tint: ink)
            x += m.badgeSymbolPt + 3
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: themedFont(m.badgePt, .medium), .foregroundColor: ink]
        let str = b.text as NSString
        let size = str.size(withAttributes: attrs)
        str.draw(at: NSPoint(x: x, y: pill.midY - size.height / 2), withAttributes: attrs)
    }

    private func badgeColors(_ role: BadgeRole, onAccent: Bool) -> (fill: NSColor, ink: NSColor) {
        if onAccent { return (palette.onPrimary(0.18), palette.onPrimary(1)) }
        switch role {
        case .neutral:   return (palette.ink(.subtle, of: .muted), palette.muted)
        case .primary:   return (palette.ink(.subtle, of: .primary), palette.primary)
        case .secondary: return (palette.secondary.withAlphaComponent(0.16), palette.secondary)
        case .error:     return (palette.error.withAlphaComponent(0.16), palette.error)
        }
    }

    // MARK: Text / image primitives

    private func drawLine(_ s: String, font: NSFont, color: NSColor, x: CGFloat, maxWidth: CGFloat,
                          row: CGRect, mode: NSLineBreakMode) {
        guard maxWidth > 0 else { return }
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = mode
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
        let str = s as NSString
        let h = str.size(withAttributes: attrs).height
        // For a single-line `row` (no explicit text box) centre vertically; for an
        // explicit line-box (the two-line stack / header) the caller sized `row` to
        // the line height, so this still centres correctly.
        let rect = CGRect(x: x, y: row.minY + (row.height - h) / 2, width: maxWidth, height: h)
        str.draw(in: rect, withAttributes: attrs)
    }

    /// Aspect-fit `image` centred in `box`; tint a TEMPLATE image (a colour image
    /// draws as-is — the kit can't knock out a favicon).
    ///
    /// `respectFlipped: true` is REQUIRED: this list's document view is
    /// `isFlipped` (row 0 at top), and the plain `draw(in:)` ignores the context
    /// flip, so every glyph (a checkmark, a hammer, an app favicon) rendered
    /// upside-down. The flag makes NSImage honour the flip and draw upright.
    private func drawImage(_ image: NSImage, fitting box: CGRect, tint: NSColor?) {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return }
        let scale = min(box.width / s.width, box.height / s.height)
        let w = s.width * scale, h = s.height * scale
        let fit = CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
        if let tint, image.isTemplate {
            NSGraphicsContext.saveGraphicsState()
            image.draw(in: fit, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
            tint.set()
            fit.fill(using: .sourceAtop)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            image.draw(in: fit, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
        }
    }

    private func sfImage(_ name: String, pt: CGFloat) -> NSImage? {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let conf = NSImage.SymbolConfiguration(pointSize: pt, weight: .regular)
        let out = img.withSymbolConfiguration(conf) ?? img
        out.isTemplate = true
        return out
    }
}

// MARK: - RowLayout (cached per reload — rows have mixed heights)

private struct RowLayout {
    var yOffsets: [CGFloat] = []          // cumulative top of each row, doc-view coords
    var heights: [CGFloat] = []
    var totalHeight: CGFloat = 0
    var headerIndices: [Int] = []
}

// MARK: - ListDocumentView (flipped, custom-drawn, hover + keyboard → owner)

@MainActor
private final class ListDocumentView: NSView {
    weak var owner: ThemedList?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }                 // row 0 at top, y grows down
    override var acceptsFirstResponder: Bool { owner?.managesFR ?? false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }                 // the scroll view paints the surface

    // Accessibility — vend synthetic per-row `.menuItem` children when the owner
    // opts in (a menu hosts this list); otherwise default (no per-row AX — the
    // combo's documented basic limitation).
    override func accessibilityRole() -> NSAccessibility.Role? {
        owner?.vendsRowAXElementsFlag == true ? .menu : super.accessibilityRole()
    }
    override func accessibilityChildren() -> [Any]? {
        guard owner?.vendsRowAXElementsFlag == true else { return super.accessibilityChildren() }
        return owner?.buildAXChildren()
    }

    override func draw(_ dirtyRect: NSRect) { owner?.drawRows(self, dirty: dirtyRect) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeInActiveApp],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    private func docY(_ event: NSEvent) -> CGFloat { convert(event.locationInWindow, from: nil).y }

    override func mouseMoved(with event: NSEvent) { owner?.hoverRow(atDocY: docY(event)) }
    override func mouseExited(with event: NSEvent) { owner?.clearHover() }
    override func mouseUp(with event: NSEvent) { owner?.handleClick(atDocY: docY(event)) }

    // Keyboard nav — only reached when `managesFirstResponder` makes us FR.
    override func keyDown(with event: NSEvent) { interpretKeyEvents([event]) }
    override func moveUp(_ sender: Any?) { owner?.moveHighlight(-1) }
    override func moveDown(_ sender: Any?) { owner?.moveHighlight(1) }
    override func insertNewline(_ sender: Any?) { owner?.activateHighlight() }
    override func cancelOperation(_ sender: Any?) { owner?.clearHighlight() }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { owner?.setFocusRing(visible: true) }
        return ok
    }
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { owner?.setFocusRing(visible: false) }
        return ok
    }
}

// MARK: - RowAXElement (synthetic `.menuItem` accessibility child)

/// One synthetic accessibility element standing in for a custom-drawn row (the
/// list has NO per-row subviews). Built fresh by `ThemedList.buildAXChildren`;
/// its role / label / frame are set there, and AXPress activates the row. NOT
/// `@MainActor` — `accessibilityPerformPress` overrides a nonisolated AppKit
/// method, so it assumes main isolation (AX is delivered on main) to reach the
/// owner.
private final class RowAXElement: NSAccessibilityElement {
    weak var owner: ThemedList?
    let rowID: String

    init(owner: ThemedList, rowID: String) {
        self.owner = owner
        self.rowID = rowID
        super.init()
    }

    override func accessibilityPerformPress() -> Bool {
        guard let owner else { return false }
        let id = rowID
        MainActor.assumeIsolated { owner.activateRow(id) }
        return true
    }
}

#if DEBUG
// Test-only window into the resolved layout + selection state (mirrors
// `comboProbe`): driven via `previewHighlight`/`previewSelection` + the public
// callbacks + the pure `stickyHeader(atVisibleTop:)` seam — no synthetic events,
// no live window. The visual selection/hover/solidAccent appearance is proven
// LIVE in prism, not asserted as pixels.
extension ThemedList {
    struct ListProbe {
        let rowCount: Int
        let totalHeight: CGFloat
        let rowFrames: [String: CGRect]
        let effectiveHighlightID: String?
        let effectiveSelectionID: String?
        let emptyActionActive: Bool
        let emptyActionLabel: String?
        let isNoOptions: Bool
        let acceptsFirstResponder: Bool
        let lastInvalidatedRects: [CGRect]
    }

    var listProbe: ListProbe {
        var frames: [String: CGRect] = [:]
        for (i, item) in items.enumerated() { frames[item.id] = rowRect(i) }
        return ListProbe(
            rowCount: items.count,
            totalHeight: rowLayout.totalHeight,
            rowFrames: frames,
            effectiveHighlightID: effectiveHighlightIndex.flatMap { items.indices.contains($0) ? items[$0].id : (isActionRowActive ? ThemedList.emptyActionID : nil) },
            effectiveSelectionID: effectiveSelectionIndex.flatMap { items.indices.contains($0) ? items[$0].id : nil },
            emptyActionActive: isActionRowActive,
            emptyActionLabel: emptyLabel,
            isNoOptions: items.isEmpty && emptyLabel == nil,
            acceptsFirstResponder: listView.acceptsFirstResponder,
            lastInvalidatedRects: lastInvalidatedRects)
    }

    /// Drive the keyboard nav without a live first responder.
    func _moveHighlight(_ delta: Int) { moveHighlight(delta) }
    /// The synthetic per-row AX children (role / label / flipped frame / AXPress) —
    /// asserted deterministically headlessly; VoiceOver traversal is a live check.
    func _axChildren() -> [NSAccessibilityElement] { buildAXChildren() }
    /// Drive a pointer hover at a doc-y (or nil = exit) without synthetic events —
    /// exercises `highlightFollowsHover` deterministically.
    func _hoverRow(atDocY y: CGFloat?) { hoverRow(atDocY: y) }
    /// The pinned sticky section + its draw-y for a given scroll offset (pure).
    func _stickyHeader(atScrollY y: CGFloat) -> (id: String?, drawY: CGFloat) {
        guard let pin = stickyHeader(atVisibleTop: y) else { return (nil, 0) }
        return (items[pin.index].id, pin.drawY)
    }
    /// Resolved primary-text colour for a row state (colour-equality assert) — the
    /// REAL renderer path, so the test can't silently diverge from drawRow.
    func _primaryTextColor(disabled: Bool, onAccent: Bool) -> NSColor {
        primaryTextColor(disabled: disabled, onAccent: onAccent)
    }
    /// Resolved badge fill for a role (colour-equality assert).
    func _badgeFill(_ role: BadgeRole, onAccent: Bool) -> NSColor { badgeColors(role, onAccent: onAccent).fill }
}
#endif
