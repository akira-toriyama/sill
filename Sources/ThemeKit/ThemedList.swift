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
    /// Visual nesting depth (0 = top level). The leading cluster — the image and
    /// text (plus a collapsible header's disclosure triangle) — shifts right by
    /// `indentLevel × indentStep`; the
    /// selection / hover fill and the leading tint bar stay FULL-BLEED (MUI's tree
    /// model: the content indents, the row's hit area + background do not). DEFAULT 0
    /// ⇒ byte-identical to a non-indented list. The kit only DRAWS the depth — the
    /// host owns the tree shape (which rows are children, what a level means).
    public var indentLevel: Int

    public enum Kind: Equatable {
        case row
        /// A group label (1-line, or 2-line with a `subtitle`), optionally sticky.
        /// `collapsed` opts the header into being COLLAPSIBLE: `nil` (default) ⇒ a
        /// plain, non-interactive header exactly as before (no disclosure triangle);
        /// `false` ⇒ collapsible + currently expanded (a ▾ triangle); `true` ⇒
        /// collapsed (a ▸ triangle). Clicking a collapsible header fires
        /// `onToggleSection(id)`. The kit does NOT hide the section's rows itself —
        /// the host owns the collapsed set and rebuilds `items` accordingly (the
        /// React-component contract: the kit reports the toggle, the host owns shape).
        case sectionHeader(subtitle: String? = nil, collapsed: Bool? = nil)
        /// A non-interactive thin rule between groups (a menu separator). Drawn as a
        /// full-bleed 1pt `border` hairline in a short band; skipped by nav / hover /
        /// activation / AX. Its `id` only needs to be unique.
        case separator
    }

    public init(id: String, image: NSImage? = nil, primary: String,
                secondary: String? = nil, secondaryMono: Bool = false,
                badges: [Badge] = [], trailing: TrailingAccessory = .none,
                tint: ListTint = .none, kind: Kind = .row, isDisabled: Bool = false,
                axChecked: Bool = false, indentLevel: Int = 0) {
        self.id = id; self.image = image; self.primary = primary
        self.secondary = secondary; self.secondaryMono = secondaryMono
        self.badges = badges; self.trailing = trailing; self.tint = tint
        self.kind = kind; self.isDisabled = isDisabled; self.axChecked = axChecked
        self.indentLevel = indentLevel
    }

    var isHeader: Bool { if case .sectionHeader = kind { return true }; return false }
    var headerSubtitle: String? { if case let .sectionHeader(s, _) = kind { return s }; return nil }
    /// nil ⇒ a non-collapsible header (or not a header); true/false ⇒ collapsible,
    /// collapsed/expanded.
    var headerCollapsed: Bool? { if case let .sectionHeader(_, c) = kind { return c }; return nil }
    /// A header the user can toggle: collapsible (its `collapsed` flag is non-nil) and
    /// not disabled (mirrors `isSelectable` / `isDragSource` — a disabled item is inert).
    var isCollapsibleHeader: Bool { isHeader && !isDisabled && headerCollapsed != nil }
    var isSeparator: Bool { if case .separator = kind { return true }; return false }
}

// MARK: - Drag-and-drop vocabulary (the additive, default-off drag layer)

/// What kinds of drop a draggable list resolves from the pointer / keyboard aim.
/// The DEFAULT is `.both`; a list opts into dragging at all via `draggable`.
///   * `.dropOnto` — only `.onto(id:)` targets (facet's tree: a window row dropped
///     ONTO a Workspace header re-homes it; headers swap onto each other). The whole
///     target row lights.
///   * `.reorderBetween` — only `.between(beforeID:)` targets (a future plain-list
///     reorder): an insertion line in the gap the row would land in.
///   * `.both` — the kit picks onto vs between by where in the row the pointer sits
///     (top/bottom quarter ⇒ between; middle ⇒ onto), the MUI tree-DnD zone model.
public enum DragMode: Equatable, Sendable { case dropOnto, reorderBetween, both }

/// WHERE a drag would land, as resolved by the kit from the pointer zone or the
/// keyboard aim. The host maps the row `id` onto its own domain (a window → a
/// workspace) — the kit knows no domain (the React-component contract).
public enum DropPlacement: Equatable, Sendable {
    /// Dropped ONTO a row (facet: onto a Workspace header → re-home; header-to-header
    /// swap). `id` is the target row's id.
    case onto(id: String)
    /// Dropped into the GAP before `beforeID` (a reorder insertion point). `nil` ⇒
    /// after the last row (the end gap).
    case between(beforeID: String?)
}

/// The thing being dragged — the source row's identity. A struct (not a bare
/// `String`) so the layer can grow to carry more later (a multi-row selection, an
/// external-pasteboard source) WITHOUT breaking the `onDrop` / validator closure
/// signatures the host already wrote — additive stability past 1.0.
public struct DragContext: Equatable, Sendable {
    /// The dragged row's `id`.
    public let id: String
    public init(id: String) { self.id = id }
}

/// A resolved drop target handed to `dropTargetValidator` / `onDrop`. Wraps the
/// `placement`; a struct (rather than passing the bare `DropPlacement`) for the
/// same forward-compatibility reason as `DragContext` — a later field (a pointer
/// fraction, an `isExternal` flag) is additive on the struct, not a breaking change
/// to the closure type.
public struct DropTarget: Equatable, Sendable {
    /// Where the drop lands.
    public let placement: DropPlacement
    public init(placement: DropPlacement) { self.placement = placement }
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
    /// How the keyboard / nav HIGHLIGHT (the cursor) is drawn — distinct from the
    /// committed selection's fill. `.fill` (default) paints the highlight exactly like
    /// a selection (the menu / combo model); `.outline` draws a stroked ring instead,
    /// so a keyboard cursor reads as a separate affordance ON TOP of a filled
    /// selection (facet's tree, where cursor ≠ selection).
    public enum HighlightStyle { case fill, outline }

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
    /// A font-KIND change (mono↔system) changes glyph advances, so when the list is
    /// horizontally scrolling the cached natural width is recomputed + the doc resized
    /// (text widths are the only metric that depends on the font; heights don't).
    public var palette: ResolvedPalette {
        didSet {
            applyTheme()
            if horizontalContentScroll, oldValue.font != palette.font { recomputeLayout(); syncDocSize() }
        }
    }

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

    /// How the keyboard / nav highlight (the cursor) is drawn. `.fill` (default) is
    /// the menu / combo look (the highlight fills like a selection); `.outline` is a
    /// stroked ring so a facet keyboard cursor is distinct from the filled selection.
    public var highlightStyle: HighlightStyle = .fill { didSet { listView.needsDisplay = true } }

    /// Tint every other data row with a faint `hover`-derived stripe (a zebra list —
    /// facet). Headers / separators are never striped; the parity restarts at each
    /// section header. Default off. No new palette role (the stripe is `hover` at low
    /// alpha), and a selection / hover fill paints over it.
    public var alternatingRowBackground = false { didSet { listView.needsDisplay = true } }

    /// Let rows extend PAST the clip width and scroll horizontally instead of
    /// truncating — facet's tree shows long window titles in full. DEFAULT false
    /// (rows truncate to the pane, the doc width tracks the clip — byte-identical).
    /// When true: the doc view widens to the natural content width (the widest row,
    /// floored at the clip), text draws untruncated (clipped, never ellipsized — a
    /// sub-pixel gap can't reintroduce "…"), and a themed horizontal scroller appears.
    /// Trailing accessories right-align to the content's right edge (a column) and
    /// scroll WITH the row — there is no frozen/pinned column (facet's model).
    public var horizontalContentScroll = false {
        didSet {
            guard horizontalContentScroll != oldValue else { return }
            scrollView.hasHorizontalScroller = horizontalContentScroll
            // Give up the width-tracks-clip autoresize when we own the width.
            listView.autoresizingMask = horizontalContentScroll ? [] : [.width]
            recomputeLayout()        // refresh the cached natural content width
            syncDocSize()
            listView.needsDisplay = true
        }
    }

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
        didSet { previewScrollPending = (previewScrollY ?? previewScrollX) != nil; applyPreviewScroll(); listView.needsDisplay = true }
    }
    /// Force the clip horizontally to this doc-x (a static capture of a
    /// `horizontalContentScroll` list scrolled sideways). nil = live scroll.
    public var previewScrollX: CGFloat? = nil {
        didSet { previewScrollPending = (previewScrollY ?? previewScrollX) != nil; applyPreviewScroll(); listView.needsDisplay = true }
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
    /// A COLLAPSIBLE section header (its `collapsed` flag is non-nil) was clicked,
    /// carrying the header's id. The host flips its own collapsed state and rebuilds
    /// `items` (the kit hides nothing itself). Never fires for a plain header.
    public var onToggleSection: ((String) -> Void)? = nil

    // MARK: Drag-and-drop (opt-in — the additive drag layer; default OFF)

    /// MASTER GATE. `false` (default) ⇒ the list behaves EXACTLY as before: a press
    /// is a click, no ghost, no drop affordance, the mouse path is untouched. `true`
    /// ⇒ a press-and-drag past a small threshold lifts the row under it (a ghost
    /// follows the pointer) and the kit resolves a `DropTarget`; releasing fires
    /// `onDrop`. A keyboard lift (`beginDrag`/arrows/`commitDrag`) needs only this
    /// gate, not the pointer. Turning it OFF mid-drag cancels the in-flight drag.
    public var draggable = false {
        didSet { if draggable != oldValue { if !draggable { cancelDrag() }; listView.needsDisplay = true } }
    }

    /// onto vs between resolution (see `DragMode`). DEFAULT `.both`; facet's tree
    /// sets `.dropOnto`. Consulted only while `draggable`.
    public var dragMode: DragMode = .both

    /// Veto a resolved drop (the host's domain rule — facet rejects a drop onto the
    /// SAME workspace, or onto self). Returns `true` to ALLOW. The kit ALWAYS first
    /// rejects the structurally-trivial targets (onto self, a no-move reorder, a
    /// separator) before consulting this — so the host only encodes DOMAIN vetoes.
    /// nil ⇒ every structurally-valid target is allowed.
    public var dropTargetValidator: ((DragContext, DropTarget) -> Bool)? = nil

    /// Override the floating drag ghost for a row id (facet's snapshot card). Return
    /// nil to fall back to the kit default (a snapshot of the row on a surface card).
    /// Mouse-drag only — a keyboard lift shows no floating ghost (it dims the lifted
    /// row + moves the drop affordance under the arrows).
    public var dragImageProvider: ((String) -> NSImage?)? = nil

    /// The drop was COMMITTED on a valid target (the host's 実処理 — performs the
    /// move). Never fires on a cancel, an invalid target, or a no-op self-drop.
    public var onDrop: ((DragContext, DropTarget) -> Void)? = nil

    /// `true` while a drag (mouse or keyboard) is in flight. Read-only.
    public var isDragging: Bool { drag != nil }

    // Capture / preview seams for the drag affordance (deterministic prism shots —
    // a live drag's ghost is a child window and can't be `screencapture`d, so the
    // bench forces the static affordance via these). `previewDropTarget` paints the
    // onto-ring / insertion-line; `previewDragSource` dims the lifted row.
    public var previewDropTarget: DropTarget? = nil { didSet { listView.needsDisplay = true } }
    public var previewDragSource: String? = nil { didSet { listView.needsDisplay = true } }

    // MARK: Internals

    private var _items: [ListItem] = []
    private var _selectedID: String?
    private var highlightedIndex: Int?       // into `items` (or 0 = the synthetic empty action row)
    private var hoveredIndex: Int?           // into `items`
    private var emptyLabel: String?          // resolved emptyActionRow label (nil ⇒ inert)
    private var rowLayout = RowLayout()         // cached per reload (mixed-height rows)

    // Drag state (one session at a time; nil when idle). `target` is the live aim;
    // `isKeyboard` selects the lift model (no ghost, arrows aim). `dragGhost` is the
    // floating child window (mouse only). `dragCandidateIndex` walks the validated
    // `dragCandidates()` for a keyboard lift.
    private struct DragSession { let sourceID: String; var target: DropTarget?; let isKeyboard: Bool }
    private var drag: DragSession?
    private var dragGhost: DragGhost?
    private var dragCandidateIndex: Int?
    private var dragGhostGrab: CGPoint = .zero        // row top-left − cursor, screen pts (mouse ghost follow)

    private let scrollView = NSScrollView()
    // A vertical-shaped frame so NSScroller infers a vertical scroller; the scroll
    // view resizes it. Themed in `applyTheme` so the knob reads in-palette.
    private let vScroller = ThemedScroller(frame: NSRect(x: 0, y: 0, width: 16, height: 100))
    // A horizontal-shaped frame so NSScroller infers a horizontal scroller (installed
    // only when `horizontalContentScroll` is on). Themed in `applyTheme`.
    private let hScroller = ThemedScroller(frame: NSRect(x: 0, y: 0, width: 100, height: 16))
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
        let indentStep, disclosurePt, disclosureGap: CGFloat
        var textXOrigin: CGFloat { leadingInset + imageBox + gapImageToText }
        /// Width reserved at a collapsible header's leading edge for the disclosure
        /// triangle (the triangle glyph + the gap before the title).
        var disclosureGutter: CGFloat { disclosurePt + disclosureGap }
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
                           clusterGap: 6, budgetMargin: 8, separatorBand: 9,
                           indentStep: 16, disclosurePt: 11, disclosureGap: 5)
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
                           clusterGap: 6, budgetMargin: 8, separatorBand: 7,
                           indentStep: 14, disclosurePt: 10, disclosureGap: 5)
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
        scrollView.horizontalScroller = hScroller        // themed too; enabled by horizontalContentScroll
        scrollView.hasHorizontalScroller = false         // off until horizontalContentScroll opts in
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
        syncDocSize()                  // doc width = clip (or natural content width when h-scrolling)
        updateFocusRingPath()
        if previewScrollPending { applyPreviewScroll() }
    }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        syncDocSize()
        updateFocusRingPath()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The eager `recalculateKeyViewLoop()` in the `managesFirstResponder` didSet
        // is a no-op when the flag is set BEFORE the view is in a window (the common
        // NSViewRepresentable configure-during-make ordering) — rebuild it on attach.
        if managesFirstResponder { window?.recalculateKeyViewLoop() }
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        // A live drag is normally torn down by mouseUp / commit / cancel. If the list
        // is pulled out of its window mid-gesture (host teardown, a re-made
        // NSViewRepresentable bridge), that mouseUp never arrives — cancel so the
        // ghost child window can't orphan on screen and the session can't stick.
        if newWindow == nil, isDragging { cancelDrag() }
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
        hScroller.knobColor = palette.muted
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
        syncDocSize()
        listView.needsDisplay = true
        listView.window?.invalidateCursorRects(for: listView)
    }

    /// Size the doc view: width = the clip width, or — when `horizontalContentScroll`
    /// is on — the wider of the clip and the natural content width (so long rows draw
    /// untruncated and the panel scrolls sideways); height = the laid-out total.
    /// Before the view is sized (clip width 0) the WIDTH is left as-is but the HEIGHT
    /// is still stamped to `totalHeight` — 1.4.0 set both unconditionally, and the AX
    /// flip-frame conversion (`buildAXChildren`) reads the doc height pre-layout.
    private func syncDocSize() {
        let clip = scrollView.contentView.bounds.width
        let w = clip > 0 ? (horizontalContentScroll ? max(clip, rowLayout.naturalWidth) : clip)
                         : listView.bounds.width
        if listView.bounds.width != w || listView.bounds.height != rowLayout.totalHeight {
            listView.setFrameSize(NSSize(width: w, height: rowLayout.totalHeight))
        }
    }

    private func renderEmptyState() {
        emptyLabel = items.isEmpty ? emptyActionRow?(query) : nil
        listView?.needsDisplay = true
    }

    private func recomputeLayout() {
        var ys: [CGFloat] = [], hs: [CGFloat] = [], headers: [Int] = [], zebra: [Bool] = []
        var y: CGFloat = 0
        var dataOrdinal = 0          // counts .row items within a section; resets at each header
        if items.isEmpty {
            ys = [0]; hs = [metrics.singleRow]; y = metrics.singleRow; zebra = [false]   // one synthetic row
        } else {
            for (i, item) in items.enumerated() {
                let h = rowHeight(for: item)
                ys.append(y); hs.append(h); y += h
                if item.isHeader { headers.append(i); dataOrdinal = 0; zebra.append(false) }
                else if item.isSeparator { zebra.append(false) }
                else { zebra.append(dataOrdinal % 2 == 1); dataOrdinal += 1 }   // every 2nd data row
            }
        }
        // The natural content width (widest untruncated row) is needed only when
        // horizontalContentScroll is on — skip the per-row text measuring otherwise.
        let natural = horizontalContentScroll ? ceil(fittingWidth()) : 0
        rowLayout = RowLayout(yOffsets: ys, heights: hs, totalHeight: y,
                              headerIndices: headers, zebra: zebra, naturalWidth: natural)
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

    /// The horizontal offset a row's leading content (disclosure / image / text) is
    /// pushed right by its nesting depth. 0 for a top-level (or non-indented) row, so
    /// a list whose rows never set `indentLevel` is geometrically unchanged.
    private func indentInset(_ item: ListItem) -> CGFloat { CGFloat(max(0, item.indentLevel)) * metrics.indentStep }
    private func indentInset(forID id: String?) -> CGFloat { indexOf(id).map { indentInset(items[$0]) } ?? 0 }

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
            // Match drawHeader / drawRow: a header's text starts after its indent + the
            // disclosure gutter (when collapsible); a row's after its indent + leading slot.
            let textX = (item.isHeader ? m.leadingInset + (item.headerCollapsed != nil ? m.disclosureGutter : 0) : rowTextX)
                + indentInset(item)
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
        // A click inside the PINNED sticky header's band acts on the PINNED header (it
        // occludes the row scrolled beneath it): toggle it if collapsible, else swallow
        // the click — except when the header sits in its own natural slot (i == pin.index),
        // where a non-collapsible header just no-ops through `activate`.
        if let pin = stickyHeader(atVisibleTop: listView.visibleRect.minY),
           y >= pin.drawY, y < pin.drawY + rowLayout.heights[pin.index] {
            if items[pin.index].isCollapsibleHeader { onToggleSection?(items[pin.index].id) }
            else if i != pin.index { return }
            else { activate(i) }
            return
        }
        // A collapsible header (anywhere else) toggles; any other row activates.
        if items[i].isCollapsibleHeader { onToggleSection?(items[i].id); return }
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
        if isDragging { return }                // a live drag owns the row feedback (the drop affordance)
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
        if isDragging { return }               // a lift replaces highlight nav with drop-target aim (decision e)
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
        guard previewScrollY != nil || previewScrollX != nil else { return }
        let clip = scrollView.contentView.bounds
        // Needs a real clip size + scrollable overflow on the requested axis; retried
        // from layout() while pending.
        guard clip.height > 0, clip.width > 0 else { return }
        let canY = rowLayout.totalHeight > clip.height
        let canX = listView.bounds.width > clip.width
        guard (previewScrollY != nil && canY) || (previewScrollX != nil && canX) else { return }
        scrollView.contentView.scroll(to: NSPoint(x: previewScrollX ?? 0, y: previewScrollY ?? 0))
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
        drawDropAffordance(width: width)            // the lifted-row dim + drop target ring / insertion line
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
        let indent = indentInset(item)        // leading content shifts right by depth; fills stay full-bleed
        // The highlight fills (like a selection) under `.fill`; under `.outline` it is a
        // ring drawn last and contributes no accent fill (so text keeps normal ink).
        let (drawHighlightFill, onAccent) = highlightFillAndAccent(isSel: isSel, isHi: isHi)

        // 1. Backgrounds: zebra stripe (base), the leading tint bar, then the selection /
        //    highlight fill + hover veil. All FULL-BLEED (x=0 / full width) — only the
        //    row's CONTENT indents (the MUI tree model).
        if paintsZebra(i, isSel: isSel, drawHighlightFill: drawHighlightFill) {
            zebraColor.setFill()
            CGRect(x: 0, y: r.minY, width: r.width, height: r.height).fill()
        }
        if item.tint != .none, !onAccent {
            resolvedTint(item.tint).setFill()
            CGRect(x: 0, y: r.minY, width: m.accentBar, height: r.height).fill()
        }
        if isSel || drawHighlightFill { paintSelectionBackground(r, onAccent: onAccent) }
        // Pointer veil over a selected row (wash mode) so the hovered row reads on top.
        if hoverStyle == .wash, isSel, hoveredIndex == i {
            palette.hover.setFill()
            selectionPath(r).fill()
        }
        // The keyboard cursor as a stroked ring, distinct from a filled selection.
        if isHi, highlightStyle == .outline { paintHighlightOutline(r) }

        // 2. Trailing cluster width FIRST (so the text budget is right), drawn later.
        let trailingW = trailingClusterWidth(item)

        // 3. Leading image: a TEMPLATE glyph centres at `iconGlyph` (18/16) inside
        //    the `imageBox` reservation (no upscale); a colour favicon fills the box.
        if reservesLeadingImageColumn, let image = item.image {
            let side = image.isTemplate ? m.iconGlyph : m.imageBox
            let box = CGRect(x: m.leadingInset + indent + (m.imageBox - side) / 2, y: r.midY - side / 2, width: side, height: side)
            drawImage(image, fitting: box, tint: onAccent ? palette.onPrimary(1) : (image.isTemplate ? palette.foreground : nil))
        }

        // 4. Text stack.
        let xText = rowTextX + indent
        let textMax = max(0, r.maxX - m.trailingInset - (trailingW > 0 ? trailingW + m.budgetMargin : 0) - xText)
        let primaryColor = primaryTextColor(disabled: item.isDisabled, onAccent: onAccent)
        if let secondary = item.secondary {
            let pFont = themedFont(m.primaryPt)
            let pH = (pFont.ascender - pFont.descender)
            let pRow = CGRect(x: 0, y: r.minY + m.twoLineTop, width: r.width, height: pH)
            drawLine(item.primary, font: pFont, color: primaryColor, x: xText, maxWidth: textMax, row: pRow, mode: textBreakMode)
            let sFont = item.secondaryMono ? .monospacedSystemFont(ofSize: m.secondaryPt, weight: .regular) : themedFont(m.secondaryPt)
            let sColor = secondaryTextColor(disabled: item.isDisabled, onAccent: onAccent)
            let sRow = CGRect(x: 0, y: pRow.maxY + m.lineGap, width: r.width, height: sFont.ascender - sFont.descender)
            drawLine(secondary, font: sFont, color: sColor, x: xText, maxWidth: textMax, row: sRow,
                     mode: horizontalContentScroll ? .byClipping : (item.secondaryMono ? .byTruncatingMiddle : .byTruncatingTail))
        } else {
            drawLine(item.primary, font: themedFont(m.primaryPt), color: primaryColor,
                     x: xText, maxWidth: textMax, row: r, mode: textBreakMode)
        }

        // 5. Trailing cluster (right-to-left).
        drawTrailingCluster(item, in: r, onAccent: onAccent)

        // 6. Divider between rows (not after the last; full-bleed above a header;
        //    suppressed above a separator row, which draws its own rule).
        if showsDividers, i < items.count - 1, !items[i + 1].isSeparator {
            let nextIsHeader = items[i + 1].isHeader
            let x = nextIsHeader ? 0 : rowTextX + indent     // align the rule under this row's (indented) text
            // A deep indent in a narrow pane can push `x` past the right inset — clamp
            // (a negative-width fill would paint a stray sliver LEFT of `x`).
            let w = max(0, width - x - (nextIsHeader ? 0 : m.trailingInset))
            if w > 0 {
                palette.border.setFill()
                CGRect(x: x, y: r.maxY - 1, width: w, height: 1).fill()
            }
        }
    }

    // MARK: Backgrounds

    private func selectionPath(_ r: CGRect) -> NSBezierPath {
        roundedSelection
            ? NSBezierPath(roundedRect: r.insetBy(dx: metrics.roundedHInset, dy: 0),
                           xRadius: metrics.roundedRadius, yRadius: metrics.roundedRadius)
            : NSBezierPath(rect: r)
    }

    /// The keyboard cursor as a 1.5pt `primary` ring (`highlightStyle == .outline`) —
    /// a distinct affordance ON TOP of any selection fill, inset so the stroke isn't
    /// clipped at the row edges.
    private func paintHighlightOutline(_ r: CGRect) {
        let path = NSBezierPath(roundedRect: r.insetBy(dx: 1.5, dy: 1.5),
                                xRadius: metrics.roundedRadius, yRadius: metrics.roundedRadius)
        palette.primary.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    /// The zebra stripe — `hover` at low alpha (no new palette role); reads as a faint
    /// lighter/darker band on light/dark surfaces alike.
    private var zebraColor: NSColor { palette.hover.withAlphaComponent(0.4) }

    /// Whether row `i` paints a zebra stripe — the SINGLE source the renderer + the
    /// probe both use. Gated on the opt-in flag, an OPAQUE surface (a translucent stripe
    /// over a vibrancy backdrop reads inconsistently AND would bleed through a pinned
    /// header whose punch is skipped on a nil surface), the data-row parity, and NOT a
    /// selected / fill-highlighted row (whose fill paints over it).
    private func paintsZebra(_ i: Int, isSel: Bool, drawHighlightFill: Bool) -> Bool {
        alternatingRowBackground && effectiveSurface != nil && !isSel && !drawHighlightFill
            && rowLayout.zebra.indices.contains(i) && rowLayout.zebra[i]
    }

    /// Whether a row's highlight fills like a selection (`.fill`) vs draws a ring
    /// (`.outline`), and whether it sits on an opaque accent fill (`.solidAccent` →
    /// `onPrimary` ink). The SINGLE source the renderer + the DEBUG probe both use.
    fileprivate func highlightFillAndAccent(isSel: Bool, isHi: Bool) -> (fill: Bool, onAccent: Bool) {
        let fill = isHi && highlightStyle == .fill
        return (fill, (isSel || fill) && hoverStyle == .solidAccent)
    }

    /// Primary/secondary text break mode: clip (never ellipsize) when the list scrolls
    /// horizontally so a long row draws in full; truncate to the pane otherwise.
    private var textBreakMode: NSLineBreakMode { horizontalContentScroll ? .byClipping : .byTruncatingTail }

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
        // and a hard block would defeat the vibrancy the host opted into. The punch
        // fill stays FULL-WIDTH (it occludes scrolled rows) even when the header's
        // own content is indented.
        if let s = effectiveSurface { s.setFill(); r.fill() }
        // The header content's leading edge: indented by depth, then a disclosure
        // gutter when collapsible (the ▸/▾ triangle is drawn there below).
        let indent = indentInset(item)
        let collapsed = item.headerCollapsed                // nil ⇒ not collapsible
        let leadX = m.leadingInset + indent + (collapsed != nil ? m.disclosureGutter : 0)
        let textMax = max(0, width - leadX - m.leadingInset)
        if let subtitle = item.headerSubtitle {
            let title = themedFont(m.header2TitlePt, .medium)
            let tRow = CGRect(x: 0, y: r.minY + 6, width: r.width, height: title.ascender - title.descender)
            drawLine(item.primary, font: title, color: palette.foreground,
                     x: leadX, maxWidth: textMax, row: tRow, mode: .byTruncatingTail)
            let sub = themedFont(m.header2SubPt)
            let sRow = CGRect(x: 0, y: tRow.maxY + m.lineGap, width: r.width, height: sub.ascender - sub.descender)
            drawLine(subtitle, font: sub, color: palette.muted,
                     x: leadX, maxWidth: textMax, row: sRow, mode: .byTruncatingTail)
        } else {
            let f = themedFont(m.header1Pt, .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: palette.muted, .kern: ThemedList.headerKern]
            let label = item.primary.uppercased() as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: leadX, y: r.minY + (r.height - size.height) / 2), withAttributes: attrs)
        }
        // The leading disclosure triangle (collapsible headers): ▸ when collapsed, ▾
        // when expanded, drawn upright (the doc view is flipped → drawImage respects it).
        if let collapsed {
            let box = CGRect(x: m.leadingInset + indent, y: r.midY - m.disclosurePt / 2,
                             width: m.disclosurePt, height: m.disclosurePt)
            if let tri = sfImage(collapsed ? "chevron.right" : "chevron.down", pt: m.disclosurePt) {
                drawImage(tri, fitting: box, tint: palette.muted)
            }
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

// MARK: - Drag-and-drop (state machine · target resolution · ghost · affordance)
//
// The additive drag layer (default OFF via `draggable`). One `DragSession` runs at
// a time, started either by the pointer (the doc view's down→drag→up sequence) or by
// the keyboard (`beginDrag` + arrows + `commitDrag`/`cancelDrag`). The kit resolves a
// `DropTarget` (onto a row / between rows) from the pointer zone or the keyboard
// candidate walk, rejects the structurally-trivial targets, then defers a DOMAIN
// veto to the host's `dropTargetValidator`. The floating ghost is a non-key child
// window (mouse only — it escapes the scroll clip like the tooltip/combo/menu do);
// the keyboard lift shows no ghost (it dims the row + moves the affordance). On a
// committed valid target the host's `onDrop` performs the move. The whole feature is
// proven LIVE in prism for the visuals; the state machine + target resolution are
// unit-tested headlessly (no window, no synthetic events). Autoscroll-on-drag is OUT
// of this first cut (facet's tree is short — documented follow-up).

extension ThemedList {

    // MARK: Source eligibility

    /// A row may be LIFTED when the list is draggable and the row is neither a
    /// separator (no identity to drag) nor disabled. Headers ARE liftable — facet's
    /// tree swaps Workspace headers onto each other; the host's validator + onDrop
    /// decide what a header drop means (the kit knows no domain).
    fileprivate func isDragSource(_ item: ListItem) -> Bool {
        draggable && !item.isSeparator && !item.isDisabled
    }

    // MARK: Mouse drag (the doc view's down → drag → up sequence)

    /// Begin a pointer drag from the row at `docY`. Returns false (the press stays a
    /// click) when the row isn't a valid source. Captures the ghost image BEFORE the
    /// lifted row dims, shows the floating ghost, and seeds the first aim.
    fileprivate func beginMouseDrag(atDocY docY: CGFloat, locationInWindow: NSPoint) -> Bool {
        guard drag == nil, let i = rowIndex(atDocY: docY), isDragSource(items[i]) else { return false }
        let image = ghostImage(forRow: i)                 // capture while the row is still un-dimmed
        drag = DragSession(sourceID: items[i].id, target: nil, isKeyboard: false)
        showGhost(image: image, forRow: i, locationInWindow: locationInWindow)
        updateMouseDrag(atDocY: docY, locationInWindow: locationInWindow)
        return true
    }

    /// Update the pointer drag: re-resolve the aim from `docY`, keep the ghost under
    /// the pointer.
    fileprivate func updateMouseDrag(atDocY docY: CGFloat, locationInWindow: NSPoint) {
        guard let s = drag, !s.isKeyboard else { return }
        setDragTarget(resolveDropTarget(atDocY: docY, source: s.sourceID))
        moveGhost(locationInWindow: locationInWindow)
    }

    /// End the pointer drag: hide the ghost; fire `onDrop` on a valid target if committing.
    fileprivate func endMouseDrag(commit: Bool) {
        guard let s = drag, !s.isKeyboard else { return }
        finishDrag(commit: commit, session: s)
    }

    // MARK: Keyboard lift (PUBLIC — the host drives Space/arrows/Return/Esc, or a
    // managesFirstResponder list routes them here via `handleDragKey`)

    /// Lift row `id` for a keyboard drag. No-op if not draggable / not a valid source
    /// / already dragging. Seeds the aim at the first valid candidate; arrows then aim
    /// via `moveDragTarget` (highlight nav is suppressed while lifting — decision e).
    public func beginDrag(_ id: String) {
        guard drag == nil, let i = indexOf(id), isDragSource(items[i]) else { return }
        drag = DragSession(sourceID: id, target: nil, isKeyboard: true)
        let candidates = dragCandidates()
        dragCandidateIndex = candidates.isEmpty ? nil : 0
        setDragTarget(candidates.first)
        listView.needsDisplay = true
    }

    /// Move the keyboard drop aim by `delta` through the validated candidates (clamped).
    /// Scrolls the aimed row into view. No-op outside a keyboard lift.
    public func moveDragTarget(_ delta: Int) {
        guard let s = drag, s.isKeyboard else { return }
        let candidates = dragCandidates()
        guard !candidates.isEmpty else { setDragTarget(nil); return }
        let next = min(max((dragCandidateIndex ?? 0) + delta, 0), candidates.count - 1)
        dragCandidateIndex = next
        setDragTarget(candidates[next])
        if let id = targetRowID(candidates[next]) { scrollToRow(id) }
        else if let lastID = items.last(where: { !$0.isSeparator })?.id { scrollToRow(lastID) }   // the end gap → reveal the content bottom
    }

    /// Commit the in-flight drag (mouse OR keyboard) — fires `onDrop` on a valid target.
    public func commitDrag() {
        guard let s = drag else { return }
        finishDrag(commit: true, session: s)
    }

    /// Cancel any in-flight drag without firing `onDrop`.
    public func cancelDrag() {
        guard let s = drag else { return }
        finishDrag(commit: false, session: s)
    }

    // MARK: Shared session teardown / target mutation

    private func finishDrag(commit: Bool, session s: DragSession) {
        let target = s.target
        drag = nil
        dragCandidateIndex = nil
        hideGhost()
        listView.needsDisplay = true
        if commit, let target { onDrop?(DragContext(id: s.sourceID), target) }
    }

    private func setDragTarget(_ t: DropTarget?) {
        guard drag != nil, drag?.target != t else { return }
        drag?.target = t
        // A drag is a transient, interactive gesture over a short list (facet's tree).
        // The per-row invalidation discipline guards the STEADY state (a long scrolled
        // list); here a full repaint as the pointer / aim moves is correct + simplest
        // (the affordance can span the whole content, so there is no tidy row band).
        listView.needsDisplay = true
    }

    // MARK: Target resolution

    /// Resolve the `DropTarget` for a pointer at `docY` (the zone model), validated.
    /// nil ⇒ no valid drop here (paint no affordance, a release is a no-op).
    fileprivate func resolveDropTarget(atDocY docY: CGFloat, source: String) -> DropTarget? {
        guard !items.isEmpty else { return nil }
        if docY < 0 {                                       // above the top
            return dragMode == .dropOnto ? nil : validatedTarget(.between(beforeID: items[0].id), source)
        }
        guard let i = rowIndex(atDocY: docY) else {         // below the last row
            return dragMode == .dropOnto ? nil : validatedTarget(.between(beforeID: nil), source)
        }
        if items[i].isSeparator { return nil }
        let r = rowRect(i)
        let frac = r.height > 0 ? (docY - r.minY) / r.height : 0.5    // 0 = top edge … 1 = bottom edge
        switch dragMode {
        case .dropOnto:
            return validatedTarget(.onto(id: items[i].id), source)
        case .reorderBetween:
            return validatedTarget(.between(beforeID: frac < 0.5 ? items[i].id : nextRowID(after: i)), source)
        case .both:
            if frac < 0.25 { return validatedTarget(.between(beforeID: items[i].id), source) }
            if frac > 0.75 { return validatedTarget(.between(beforeID: nextRowID(after: i)), source) }
            // The middle zone is an onto; fall back to a between when onto is vetoed,
            // so the mid-zone of a non-droppable row still offers the natural reorder.
            return validatedTarget(.onto(id: items[i].id), source)
                ?? validatedTarget(.between(beforeID: items[i].id), source)
        }
    }

    /// Wrap a placement into a validated `DropTarget`: reject the structurally-trivial
    /// (onto self, a no-move reorder, a separator target), THEN consult the host's
    /// domain veto. nil ⇒ not a legal drop.
    private func validatedTarget(_ placement: DropPlacement, _ source: String) -> DropTarget? {
        guard !isTrivialSelfDrop(placement, source) else { return nil }
        if case let .onto(id) = placement, let i = indexOf(id), items[i].isSeparator { return nil }
        let target = DropTarget(placement: placement)
        guard dropTargetValidator?(DragContext(id: source), target) ?? true else { return nil }
        return target
    }

    /// A drop that wouldn't move the source: onto itself, or into the gap immediately
    /// above or below itself (incl. the end gap when the source is already last).
    private func isTrivialSelfDrop(_ placement: DropPlacement, _ source: String) -> Bool {
        switch placement {
        case .onto(let id):
            return id == source
        case .between(let beforeID):
            guard let si = indexOf(source) else { return false }
            return beforeID == source || beforeID == nextRowID(after: si)
        }
    }

    /// The ordered, validated keyboard candidates for the current source + `dragMode`:
    /// `.dropOnto` ⇒ onto each row; `.reorderBetween` ⇒ each gap; `.both` ⇒ both,
    /// interleaved in row order, then the end gap.
    private func dragCandidates() -> [DropTarget] {
        guard let source = drag?.sourceID else { return [] }
        var out: [DropTarget] = []
        for item in items where !item.isSeparator {
            switch dragMode {
            case .dropOnto:
                if let t = validatedTarget(.onto(id: item.id), source) { out.append(t) }
            case .reorderBetween:
                if let t = validatedTarget(.between(beforeID: item.id), source) { out.append(t) }
            case .both:
                if let t = validatedTarget(.between(beforeID: item.id), source) { out.append(t) }
                if let t = validatedTarget(.onto(id: item.id), source) { out.append(t) }
            }
        }
        if dragMode != .dropOnto, let t = validatedTarget(.between(beforeID: nil), source) { out.append(t) }
        return out
    }

    private func nextRowID(after i: Int) -> String? {
        let n = i + 1
        return items.indices.contains(n) ? items[n].id : nil
    }

    /// The row a target visually references (for scroll-into-view); nil for the end gap.
    private func targetRowID(_ target: DropTarget) -> String? {
        switch target.placement {
        case .onto(let id):           return id
        case .between(let beforeID):  return beforeID
        }
    }

    // MARK: Ghost (the floating drag image — a non-key, click-through child window)

    /// The ghost image for a row: the host's `dragImageProvider` if it returns one,
    /// else a snapshot of the drawn row. The doc view is FLIPPED and `cacheDisplay`
    /// honours that, so the capture is upright. nil ⇒ no ghost (a zero-size row
    /// before layout, or headless tests).
    private func ghostImage(forRow i: Int) -> NSImage? {
        if let provider = dragImageProvider, let img = provider(items[i].id) { return img }
        let r = rowRect(i)
        guard r.width > 0, r.height > 0,
              let rep = listView.bitmapImageRepForCachingDisplay(in: r) else { return nil }
        listView.cacheDisplay(in: r, to: rep)
        let img = NSImage(size: r.size)
        img.addRepresentation(rep)
        return img
    }

    /// Show the floating ghost over the lifted row and remember the cursor→row-top
    /// vector so `moveGhost` keeps it under the pointer. No-op without a window or an
    /// image (the ghost is a live-only affordance — headless tests skip it).
    private func showGhost(image: NSImage?, forRow i: Int, locationInWindow: NSPoint) {
        guard let image, let win = window, let onScreen = rowRectOnScreen(for: items[i].id) else { return }
        let cursor = win.convertPoint(toScreen: locationInWindow)
        // `onScreen` is y-up; its top edge is `maxY`. Hold a constant cursor→top-left
        // vector so the ghost tracks naturally from wherever the row was grabbed.
        dragGhostGrab = CGPoint(x: onScreen.minX - cursor.x, y: onScreen.maxY - cursor.y)
        let ghost = dragGhost ?? DragGhost()
        dragGhost = ghost
        ghost.show(image: image, size: onScreen.size, backgroundColor: effectiveSurface,
                   topLeftOnScreen: CGPoint(x: onScreen.minX, y: onScreen.maxY))
    }

    private func moveGhost(locationInWindow: NSPoint) {
        guard let ghost = dragGhost, let win = window else { return }
        let cursor = win.convertPoint(toScreen: locationInWindow)
        ghost.move(topLeftOnScreen: CGPoint(x: cursor.x + dragGhostGrab.x, y: cursor.y + dragGhostGrab.y))
    }

    private func hideGhost() { dragGhost?.hide(); dragGhost = nil }

    // MARK: Affordance (the lifted-row dim + the onto-ring / insertion-line)

    /// Paint the drag feedback: the lifted SOURCE row dimmed, plus the resolved
    /// target's affordance (an `.onto` ring + faint fill on the target row, or a
    /// `.between` insertion line in the gap). Driven by the live drag OR the prism
    /// `previewDragSource` / `previewDropTarget` seams (a live ghost can't be captured).
    fileprivate func drawDropAffordance(width: CGFloat) {
        let source = drag?.sourceID ?? previewDragSource
        let target = drag?.target ?? previewDropTarget
        if let source, let si = indexOf(source) {
            (effectiveSurface ?? palette.background ?? .windowBackgroundColor).withAlphaComponent(0.55).setFill()
            rowRect(si).fill()
        }
        guard let placement = target?.placement else { return }
        switch placement {
        case .onto(let id):
            guard let i = indexOf(id) else { return }
            let path = NSBezierPath(roundedRect: rowRect(i).insetBy(dx: 1.5, dy: 1.5), xRadius: 5, yRadius: 5)
            palette.primary.withAlphaComponent(0.12).setFill(); path.fill()
            palette.primary.setStroke(); path.lineWidth = 2; path.stroke()
        case .between(let beforeID):
            let y = insertionY(beforeID: beforeID)
            let x = insertionLineX(beforeID: beforeID)        // align to the target row's depth
            palette.primary.setFill()
            CGRect(x: x, y: y - 1, width: max(0, width - x - metrics.trailingInset), height: 2).fill()
            NSBezierPath(ovalIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)).fill()   // MUI insertion dot
        }
    }

    /// The doc-y of a `.between` insertion line: the top of `beforeID`'s row, or the
    /// content bottom for the end gap (`beforeID == nil`).
    private func insertionY(beforeID: String?) -> CGFloat {
        guard let beforeID, let i = indexOf(beforeID) else { return rowLayout.totalHeight }
        return rowLayout.yOffsets[i]
    }

    /// The leading x of a `.between` insertion line — aligned to the TARGET row's
    /// depth (the end gap / an unknown id uses the base text x). Shared by the draw
    /// path and the test seam so they can't drift.
    private func insertionLineX(beforeID: String?) -> CGFloat { rowTextX + indentInset(forID: beforeID) }

    // MARK: Key routing (the managesFirstResponder list's keyDown calls this first)

    /// Route a keyDown for the drag layer. Returns true when the key is a drag command
    /// and was consumed; false to fall through to the normal nav. Space lifts the
    /// highlighted row (or commits an in-flight lift); WHILE dragging, ↑↓ aim, ⏎
    /// commits, Esc cancels — when NOT dragging those return false so the list's
    /// ordinary ↑↓/⏎/Esc nav still runs.
    fileprivate func handleDragKey(_ ev: NSEvent) -> Bool {
        guard draggable else { return false }
        switch ev.keyCode {
        case 49:                                    // Space — lift the highlighted row, or commit a lift
            if isDragging { commitDrag(); return true }
            if let id = highlightedID { beginDrag(id); return true }
            return false                            // nothing to lift → let Space fall through to the host
        case 36, 76:                                // Return / keypad Return — commit a lift
            guard isDragging else { return false }
            commitDrag(); return true
        case 53:                                    // Esc — cancel a lift
            guard isDragging else { return false }
            cancelDrag(); return true
        case 125:                                   // ↓ — aim down
            guard isDragging else { return false }
            moveDragTarget(1); return true
        case 126:                                   // ↑ — aim up
            guard isDragging else { return false }
            moveDragTarget(-1); return true
        default:
            return false
        }
    }
}

// MARK: - DragGhost (the floating drag image — a non-key, click-through child panel)

/// A borderless, non-activating, click-through child window showing the drag image.
/// It reuses the shared `themedPopupPanel` plumbing (like the tooltip / combo / menu),
/// so it floats ABOVE the list — escaping the scroll clip AND the list's own bounds —
/// and never becomes key or steals first responder. Mouse-drag only.
@MainActor
private final class DragGhost {
    private let panel: PopupPanel
    private let imageView = NSImageView()

    init() {
        panel = themedPopupPanel(interactive: false, role: .unknown)   // click-through, out of AX
        imageView.imageScaling = .scaleAxesIndependently               // the snapshot is already row-sized → 1:1
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        panel.contentView = imageView
        panel.alphaValue = 0.9                                          // the translucent drag look
    }

    /// Show the ghost with its TOP-LEFT at `topLeftOnScreen` (y-up; the panel origin
    /// is its bottom-left, so subtract the height).
    func show(image: NSImage, size: CGSize, backgroundColor: NSColor?, topLeftOnScreen: CGPoint) {
        imageView.image = image
        imageView.layer?.backgroundColor = (backgroundColor ?? .windowBackgroundColor).cgColor
        panel.setFrame(CGRect(x: topLeftOnScreen.x, y: topLeftOnScreen.y - size.height,
                              width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
        panel.orderFrontRegardless()                                   // NEVER makeKey — keep the host's focus
    }

    func move(topLeftOnScreen: CGPoint) {
        panel.setFrameOrigin(CGPoint(x: topLeftOnScreen.x, y: topLeftOnScreen.y - panel.frame.height))
    }

    func hide() { panel.orderOut(nil) }
}

// MARK: - RowLayout (cached per reload — rows have mixed heights)

private struct RowLayout {
    var yOffsets: [CGFloat] = []          // cumulative top of each row, doc-view coords
    var heights: [CGFloat] = []
    var totalHeight: CGFloat = 0
    var headerIndices: [Int] = []
    var zebra: [Bool] = []                // per-item: paint the alternating stripe (data rows only)
    var naturalWidth: CGFloat = 0         // widest untruncated row (only computed for horizontalContentScroll)
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

    // Drag press tracking — only engaged when the owner is `draggable`. Otherwise the
    // mouse path is byte-identical to before: `mouseDown`/`mouseDragged` defer to
    // `super` (the no-override behaviour), and a `mouseUp` is a click.
    private var pressLocationInWindow: NSPoint?
    private var pressDocY: CGFloat = 0
    private var didDrag = false
    private let dragThreshold: CGFloat = 4          // a click jitter under this isn't a drag

    override func mouseDown(with event: NSEvent) {
        guard owner?.draggable == true else { super.mouseDown(with: event); return }
        pressLocationInWindow = event.locationInWindow
        pressDocY = docY(event)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard owner?.draggable == true, let start = pressLocationInWindow else {
            super.mouseDragged(with: event); return
        }
        if !didDrag {
            let dx = event.locationInWindow.x - start.x, dy = event.locationInWindow.y - start.y
            guard (dx * dx + dy * dy).squareRoot() >= dragThreshold else { return }
            guard owner?.beginMouseDrag(atDocY: pressDocY, locationInWindow: event.locationInWindow) == true else {
                pressLocationInWindow = nil          // not a valid source → abandon (mouseUp still clicks)
                return
            }
            didDrag = true
        }
        owner?.updateMouseDrag(atDocY: docY(event), locationInWindow: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {                                 // a drag gesture — commit on release, no click
            owner?.endMouseDrag(commit: true)
            didDrag = false
            pressLocationInWindow = nil
            return
        }
        pressLocationInWindow = nil
        owner?.handleClick(atDocY: docY(event))      // the unchanged click path
    }

    // Keyboard nav — only reached when `managesFirstResponder` makes us FR. Drag keys
    // (Space/arrows/Return/Esc while draggable) are routed first; the rest fall through
    // to the standard nav commands below.
    override func keyDown(with event: NSEvent) {
        if owner?.handleDragKey(event) == true { return }
        interpretKeyEvents([event])
    }
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

    // MARK: Drag seams (the state machine + target resolution, window-independent —
    // the ghost is a live-only child window, hand-checked in prism)

    struct DragProbe {
        let isDragging: Bool
        let isKeyboardDrag: Bool
        let sourceID: String?
        let target: DropTarget?
        let candidateCount: Int        // validated keyboard candidates for the live source
    }
    var dragProbe: DragProbe {
        DragProbe(isDragging: isDragging, isKeyboardDrag: drag?.isKeyboard ?? false,
                  sourceID: drag?.sourceID, target: drag?.target, candidateCount: dragCandidates().count)
    }
    /// The `DropTarget` a pointer at `docY` would resolve to (validated) for `source` —
    /// no window, no live drag needed (the resolver is pure of the ghost).
    func _resolveDropTarget(atDocY y: CGFloat, source: String) -> DropTarget? {
        resolveDropTarget(atDocY: y, source: source)
    }
    /// Drive a mouse drag's begin / update / end headlessly (no synthetic events, no
    /// window — the ghost simply doesn't show).
    @discardableResult func _beginMouseDrag(atDocY y: CGFloat) -> Bool { beginMouseDrag(atDocY: y, locationInWindow: .zero) }
    func _updateMouseDrag(atDocY y: CGFloat) { updateMouseDrag(atDocY: y, locationInWindow: .zero) }
    func _endMouseDrag(commit: Bool) { endMouseDrag(commit: commit) }
    /// The ordered, validated keyboard drop candidates for the live source.
    func _dragCandidates() -> [DropTarget] { dragCandidates() }
    /// Route a keyDown through the real drag-key logic (consume-vs-fall-through).
    @discardableResult func _handleDragKey(_ ev: NSEvent) -> Bool { handleDragKey(ev) }

    // MARK: Indent / disclosure seams

    /// Drive a click at a doc-y through the real `handleClick` (a collapsible header
    /// fires `onToggleSection`; a row activates) — no synthetic events / window.
    func _handleClick(atDocY y: CGFloat) { handleClick(atDocY: y) }
    /// The leading x where a row's text / a header's title is DRAWN (after its indent,
    /// and a header's disclosure gutter) — so a test can assert the depth offset matches
    /// the real draw path. nil for an unknown id.
    func _contentLeadingX(forID id: String) -> CGFloat? {
        guard let i = indexOf(id) else { return nil }
        let item = items[i]
        if item.isHeader {
            return metrics.leadingInset + indentInset(item) + (item.headerCollapsed != nil ? metrics.disclosureGutter : 0)
        }
        return rowTextX + indentInset(item)
    }
    /// The x a `.between` drop insertion line draws at for `beforeID` (the real draw
    /// path) — locks the "insertion line follows the target's depth" contract.
    func _insertionLineX(beforeID: String?) -> CGFloat { insertionLineX(beforeID: beforeID) }

    // MARK: Polish seams (highlightStyle / zebra / horizontalContentScroll)

    /// Whether a row in (isSel, isHi) state fills its highlight + sits on an accent —
    /// the real renderer decision (so `.outline` keeping normal ink is asserted).
    func _highlightFillAndAccent(isSel: Bool, isHi: Bool) -> (fill: Bool, onAccent: Bool) {
        highlightFillAndAccent(isSel: isSel, isHi: isHi)
    }
    /// The zebra parity for a row id (true = striped). nil for an unknown id. This is
    /// the raw layout parity (always computed); whether a stripe actually PAINTS is
    /// `_zebraPaints` (it folds in the flag / surface / selection suppression).
    func _zebraParity(forID id: String) -> Bool? {
        indexOf(id).flatMap { rowLayout.zebra.indices.contains($0) ? rowLayout.zebra[$0] : nil }
    }
    /// Whether row `id` would actually paint its stripe in (isSel, isHi) state — the
    /// real draw decision (asserts the suppression-under-selection + surface gating).
    func _zebraPaints(forID id: String, isSel: Bool = false, isHi: Bool = false) -> Bool {
        guard let i = indexOf(id) else { return false }
        let (fill, _) = highlightFillAndAccent(isSel: isSel, isHi: isHi)
        return paintsZebra(i, isSel: isSel, drawHighlightFill: fill)
    }
    /// The cached natural content width (0 unless horizontalContentScroll is on).
    var _naturalContentWidth: CGFloat { rowLayout.naturalWidth }
}
#endif
