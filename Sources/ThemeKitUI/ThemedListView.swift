// ThemeKitUI — the SwiftUI-native, generic `ThemedListView<ID>` (#17b M2): the new
// CANONICAL themed list/tree. Replaces the old 37-line `NSViewRepresentable` bridge
// over the AppKit `ThemedList`. Draws hand-built themed rows from `ResolvedPalette`
// roles and projects its image-bearing `ListItem<ID>` down to `ListCore.ListRow` so
// every selection / collapse / DnD decision routes through the pure M1 cores.
//
// M2 stages: M2a = rendering + single-select + hover (this file's initial form);
// M2b = animated collapse + multi-select + keyboard; M2c = drag + overlay ghost.
// The AppKit `ThemedList` was deleted at the M5 retire — this view is the only
// themed list now (combo/menu host it via `ListController`/`HostingListView`).

import SwiftUI
import AppKit
import PaletteKit
import ThemeKit          // shared value types (Badge/TrailingAccessory/ListTint) — NOT the AppKit widget
import ListCore

/// Frozen state for a deterministic static screenshot (prism's per-cell capture).
/// When non-nil the view renders THIS instead of the live bindings.
public struct ListPreview<ID: Hashable & Sendable> {
    public var selection: Set<ID>
    public var highlight: ID?
    /// The row under the pointer. Every other widget in the kit freezes hover
    /// (`ThemedButton`/`Chip`/`FAB`/`Checkbox` take `previewHovered`, the button
    /// group takes `previewHoveredIndex`); the list was the lone holdout, so its
    /// pointer veil was the one row state a static bench shot could never show.
    public var hovered: ID?
    public var scrollX: CGFloat?
    public var scrollY: CGFloat?
    public var dragSource: ID?
    public var dropTarget: ListCore.DropTarget<ID>?
    public var dragChunk: [ID]?
    public init(selection: Set<ID> = [], highlight: ID? = nil,
                scrollX: CGFloat? = nil, scrollY: CGFloat? = nil,
                dragSource: ID? = nil, dropTarget: ListCore.DropTarget<ID>? = nil,
                dragChunk: [ID]? = nil) {
        self.selection = selection; self.highlight = highlight
        self.scrollX = scrollX; self.scrollY = scrollY
        self.dragSource = dragSource; self.dropTarget = dropTarget; self.dragChunk = dragChunk
    }

    /// Freeze the keyboard focus ring on. Live, the ring hangs off a
    /// `@FocusState` no host can reach from outside the view, so this was the
    /// one chrome layer a static bench shot could never show (t-avbj).
    public var focusRing: Bool = false

    /// A copy with the pointer parked on `id`. `hovered` arrives as a method
    /// rather than another initialiser parameter on purpose: the API differ reads
    /// any change to this label list as the old initialiser being REMOVED, which
    /// would force a major rating on a change that breaks no caller. Every future
    /// frozen state should land the same way.
    public func hovering(_ id: ID?) -> ListPreview {
        var c = self; c.hovered = id; return c
    }

    /// A copy with the keyboard focus ring frozen on/off (same API-differ-safe
    /// method shape as `hovering`).
    public func showingFocusRing(_ on: Bool = true) -> ListPreview {
        var c = self; c.focusRing = on; return c
    }
}

public struct ThemedListView<ID: Hashable & Sendable>: View {
    let items: [ListItem<ID>]
    @Binding var selection: Set<ID>
    @Binding var collapsed: Set<ID>          // collapsed-section set: id ∈ set ⇒ that header is collapsed
    @Binding var highlight: ID?
    let style: ThemedListStyle
    @Environment(\.sillPalette) private var ambientPalette
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    var onActivate: (ID) -> Void
    var onSelectionChange: (Set<ID>) -> Void
    var onToggleSection: (ID) -> Void
    var onHover: (ID?) -> Void
    var onDrop: (ListCore.DragContext<ID>, ListCore.DropTarget<ID>) -> Void
    var onEmptyAction: (String) -> Void
    var onRowRects: ([ID: CGRect]) -> Void        // per-row viewport frames: hosted hit-test, standalone anchoring
    var emptyActionRow: ((String) -> String?)?
    var query: String
    var noOptionsText: String
    var preview: ListPreview<ID>?
    /// Host pre-validation for drag resolution — consulted by BOTH the pointer
    /// and the keyboard paths before a placement becomes a target. Set via
    /// `dropTargetValidator(_:)`; the default accepts every placement.
    var dropValidate: (ListCore.DragContext<ID>, ListCore.DropTarget<ID>) -> Bool = { _, _ in true }
    /// Host veto over BEGINNING a lift — consulted before a row becomes a drag
    /// source, on the pointer path and the keyboard path alike. Set via
    /// `dragSourceValidator(_:)`; the default lets every enabled row lift.
    var liftValidate: (ID) -> Bool = { _ in true }
    /// What travels with a lifted row. `nil` ⇒ the kit's rule (a section header
    /// carries its section, every other row travels alone). Set via
    /// `dragChunk(_:)`.
    var chunkProvider: ((ID) -> [ID])?
    /// The rows a resolved drop would actually affect, painted as a BAND.
    /// `nil` ⇒ no band (the line/ring affordances only). Set via `dropBand(_:)`.
    var bandProvider: ((ListCore.DropTarget<ID>) -> [ID])?

    public init(items: [ListItem<ID>],
                selection: Binding<Set<ID>> = .constant([]),
                collapsed: Binding<Set<ID>> = .constant([]),
                highlight: Binding<ID?> = .constant(nil),
                style: ThemedListStyle = ThemedListStyle(),
                palette: ResolvedPalette? = nil,
                onActivate: @escaping (ID) -> Void = { _ in },
                onSelectionChange: @escaping (Set<ID>) -> Void = { _ in },
                onToggleSection: @escaping (ID) -> Void = { _ in },
                onHover: @escaping (ID?) -> Void = { _ in },
                onDrop: @escaping (ListCore.DragContext<ID>, ListCore.DropTarget<ID>) -> Void = { _, _ in },
                onEmptyAction: @escaping (String) -> Void = { _ in },
                onRowRects: @escaping ([ID: CGRect]) -> Void = { _ in },
                emptyActionRow: ((String) -> String?)? = nil,
                query: String = "",
                noOptionsText: String = "No options",
                preview: ListPreview<ID>? = nil) {
        self.items = items
        self._selection = selection
        self._collapsed = collapsed
        self._highlight = highlight
        self.style = style
        self.explicitPalette = palette
        self.onActivate = onActivate
        self.onSelectionChange = onSelectionChange
        self.onToggleSection = onToggleSection
        self.onHover = onHover
        self.onDrop = onDrop
        self.onEmptyAction = onEmptyAction
        self.onRowRects = onRowRects
        self.emptyActionRow = emptyActionRow
        self.query = query
        self.noOptionsText = noOptionsText
        self.preview = preview
    }

    /// A copy whose drag resolution consults `validate` before offering a
    /// placement — the host's pre-validation seam (e.g. facet's drop
    /// semantics). A rejected placement draws no affordance, joins no
    /// keyboard aim, and never reaches `onDrop`. (A copy-method rather than
    /// an init label: the API differ reads a changed label set as a removal.)
    public func dropTargetValidator(_ validate: @escaping (ListCore.DragContext<ID>, ListCore.DropTarget<ID>) -> Bool) -> Self {
        var copy = self
        copy.dropValidate = validate
        return copy
    }

    /// A copy whose rows may only BEGIN a drag when `validate` accepts their
    /// id — the "not grabbable" a host cannot spell with `isDisabled`, which
    /// is the first flag `ListItem.tapOutcome` consults and so takes the row's
    /// click, hover and selection down with the lift. A vetoed row stays a
    /// full citizen except as a drag source: no ghost, no dimming, no drop
    /// resolution — whether the lift comes from the pointer or from Space.
    /// (A copy-method rather than an init label: the API differ reads a
    /// changed label set as a removal.)
    public func dragSourceValidator(_ validate: @escaping (ID) -> Bool) -> Self {
        var copy = self
        copy.liftValidate = validate
        return copy
    }

    /// A copy whose lifts carry the ids `members` returns for the lifted row —
    /// the host's grouping seam, consulted by BOTH the pointer and the keyboard
    /// path. The default is the kit's rule: a section header carries its whole
    /// section (`ListCore.chunkMemberIDs`), any other row travels alone.
    ///
    /// Returning `[]` for a header lifts that header ALONE, which is the only
    /// way to aim a header at another ROW (`.onto`) — a chunk is forced to
    /// `.reorderBetween` by `resolveDropTarget`, so a host whose header drag
    /// means "trade these two sections' contents" (facet's workspace swap)
    /// could not express it at all. (A copy-method rather than an init label:
    /// the API differ reads a changed label set as a removal.)
    public func dragChunk(_ members: @escaping (ID) -> [ID]) -> Self {
        var copy = self
        copy.chunkProvider = members
        return copy
    }

    /// A copy that paints the rows `members` returns as a filled, outlined BAND
    /// while a drop is aimed at `target` — for a list whose commit is coarser
    /// than a row (facet drops a window into a WORKSPACE, never between two
    /// specific rows). Without it such a list can only draw a 2pt insertion
    /// line, which promises a row-level placement the commit will not honour,
    /// and shrinks "which section am I dropping into" from an area to a line.
    ///
    /// The band replaces the line/ring for its member rows; rows outside it
    /// draw nothing. Returning `[]` falls back to the normal affordance.
    public func dropBand(_ members: @escaping (ListCore.DropTarget<ID>) -> [ID]) -> Self {
        var copy = self
        copy.bandProvider = members
        return copy
    }

    @State private var selectionAnchor: ID?          // sticky anchor for shift-range
    @State private var hoveredID: ID?                // pointer veil + highlightFollowsHover
    @State private var scrollPos = ScrollPosition(edge: .top)   // frozen-preview + keyboard scroll
    @FocusState private var focused: Bool            // standalone keyboard focus (.onKeyPress)

    // Drag/reorder (M2c) — the live lift + the per-row geometry the pure resolvers consume.
    private struct DragInfo { var source: ID; var chunkIDs: [ID]; var target: ListCore.DropTarget<ID>?; var location: CGPoint; var isKeyboard: Bool = false; var tilt: CGFloat = 0 }
    @State private var dragState: DragInfo?
    @State private var geomMap: [AnyHashable: RowGeom] = [:]
    /// Content-space width — the sideways drag-abort boundary (see `dragGesture`).
    @State private var contentWidth: CGFloat = 0
    @State private var dragAim: [ListCore.DropTarget<ID>] = []   // ordered keyboard-drag targets
    @State private var dragAimIndex = 0

    // Themed scroll indicator (t-8649) — the live scroll geometry the knob is
    // computed from, and the show-then-fade activity state.
    private struct ScrollGeom: Equatable {
        var offset: CGPoint; var content: CGSize; var container: CGSize
    }
    @State private var scrollGeom: ScrollGeom?
    @State private var indicatorShown = false
    @State private var indicatorFade: Task<Void, Never>?

    private var metrics: ListMetrics { .forDensity(style.density) }
    private var visible: [ListItem<ID>] { ListItem.visibleRows(items, collapsed: collapsed) }
    private var effectiveSelection: Set<ID> { preview?.selection ?? selection }
    private var effectiveHighlight: ID? { preview?.highlight ?? highlight }
    /// A frozen `preview` OWNS hover — falling through to the live `hoveredID`
    /// would let a stray pointer contaminate a deterministic capture.
    private var effectiveHovered: ID? { preview != nil ? preview?.hovered : hoveredID }
    /// Same ownership rule for the focus ring: a frozen `preview` decides, live
    /// falls through to the real `@FocusState`.
    private var effectiveFocusRing: Bool { preview != nil ? (preview?.focusRing ?? false) : focused }

    private var scrollAxes: Axis.Set { style.horizontalContentScroll ? [.horizontal, .vertical] : .vertical }

    /// A preview that pins an explicit offset owns the viewport — the follow
    /// scrolls below must not move a deterministically framed capture.
    private var previewPinsScroll: Bool { preview?.scrollX != nil || preview?.scrollY != nil }

    /// The row a drop target is anchored to — what the viewport must show for
    /// the aim to be visible. End-of-list (`between(nil)`) anchors to the last
    /// visible row.
    private var dropTargetAnchor: ID? {
        guard let t = effDropTarget else { return nil }
        switch t.placement {
        case .onto(let id): return id
        case .between(let beforeID): return beforeID ?? visible.last?.id
        }
    }

    /// The effective surface — nil ⇒ vibrancy (host material shows through).
    private var effectiveSurface: NSColor? { style.surfaceColor ?? palette.background }
    private var surfaceIsOpaque: Bool { (effectiveSurface?.alphaComponent ?? 0) >= 1 }

    /// Zebra parity per row id — the pure `ListCore.zebraParity` rule over the
    /// visible rows (ordinal among `.row`s, resetting at each header).
    private var zebraParity: [ID: Bool] {
        ListCore.zebraParity(rows: visible.map(\.asRow))
    }

    /// Per-row divider leading x, keyed by id — the pure `ListCore.dividerInsets`
    /// rule (only after a `.row`, suppressed above a separator, full-bleed above
    /// a header, else text-x + indent), gated on `style.showsDividers`.
    private var dividerMap: [ID: CGFloat] {
        guard style.showsDividers else { return [:] }
        return dividerInsets(rows: visible.map(\.asRow),
                             textXBase: style.reservesLeadingImageColumn ? metrics.textXOrigin
                                                                         : metrics.leadingInset,
                             indentStep: metrics.indentStep)
    }

    private struct RowSection { let header: ListItem<ID>?; let rows: [ListItem<ID>] }

    /// Group `visible` into header-led sections (rows before the first header form a
    /// header-less section) so section headers can pin via `.sectionHeaders`.
    private var groupedSections: [RowSection] {
        var result: [RowSection] = []
        var header: ListItem<ID>? = nil
        var rows: [ListItem<ID>] = []
        for item in visible {
            if case .sectionHeader = item.kind {
                if header != nil || !rows.isEmpty { result.append(RowSection(header: header, rows: rows)) }
                header = item; rows = []
            } else {
                rows.append(item)
            }
        }
        if header != nil || !rows.isEmpty { result.append(RowSection(header: header, rows: rows)) }
        return result
    }

    @ViewBuilder private func rowView(_ item: ListItem<ID>, parity: [ID: Bool], opaque: Bool,
                                      dividers: [ID: CGFloat], band: DropBand? = nil) -> some View {
        ThemedListRow(item: item, metrics: metrics, style: style, palette: palette,
                      isSelected: effectiveSelection.contains(item.id),
                      isHighlighted: effectiveHighlight == item.id,
                      isHovered: effectiveHovered == item.id,
                      zebraOdd: parity[item.id] ?? false,
                      surfaceOpaque: opaque,
                      dividerInset: dividers[item.id],
                      isCollapsed: headerIsCollapsed(item),
                      dimmed: dimmedIDs.contains(item.id),
                      drop: rowDrop(item.id, band: band))
            .reportRowGeom(item.id)
            .reportRowRect(item.id)
            .contentShape(Rectangle())
            .modifier(StandaloneRowInteraction(active: !style.hosted,
                                               onTap: { handleTap(item) },
                                               onHover: { handleHover(item, $0) }))
            .modifier(OptionalDrag(active: style.draggable && isDragSource(item), gesture: dragGesture(item)))
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: interaction (inert under a frozen `preview` / constant bindings)

    /// A header is collapsed if the binding says so (view-managed) OR its declared Kind
    /// says so (host-managed / prism static). Drives the caret + row visibility.
    private func headerIsCollapsed(_ item: ListItem<ID>) -> Bool {
        if collapsed.contains(item.id) { return true }
        if case let .sectionHeader(_, c) = item.kind { return c == true }
        return false
    }

    /// Reduce Motion collapses sections without animating the row diff.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// COLLAPSING needs a collapsible header; being TAPPABLE does not. Those were
    /// one guard, so a host that declared a plain header (`collapsed: nil`) lost
    /// the click entirely — while Enter on the same header still activated it,
    /// because `activateHighlight` never consulted the Kind. The decision now
    /// lives in `ListItem.tapOutcome`, which derives each outcome separately, and
    /// the mouse reaches exactly what the keyboard reaches.
    private func handleTap(_ item: ListItem<ID>) {
        let outcome = ListItem<ID>.tapOutcome(kind: item.kind,
                                              isDisabled: item.isDisabled,
                                              selectionMode: style.selectionMode)
        if outcome.togglesSection {
            // Reduce Motion applies the same state change with no row-diff
            // animation: the rows appear/disappear rather than sliding. A nil
            // animation is how SwiftUI spells "do it, don't animate it".
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                collapsed = toggleSection(item.id, in: collapsed)          // ListCore — animates the row diff + caret
            }
            onToggleSection(item.id)
        }
        if outcome.selects {
            let r = ThemedListSelect.click(id: item.id, current: selection, anchor: selectionAnchor,
                                           mods: currentSelectMods(), selectable: ListItem.selectableIDs(visible))
            selection = r.selection
            selectionAnchor = r.anchor
            onSelectionChange(r.selection)
        }
        if outcome.activates { onActivate(item.id) }
    }

    /// Live keyboard modifiers at click time → pure `SelectMods` (only in `.multiple`;
    /// single/none always resolve as a plain click).
    private func currentSelectMods() -> SelectMods {
        guard style.selectionMode == .multiple else { return [] }
        var mods: SelectMods = []
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        return mods
    }

    private func handleHover(_ item: ListItem<ID>, _ hovering: Bool) {
        guard case .row = item.kind, !item.isDisabled else { return }
        if hovering {
            hoveredID = item.id
            onHover(item.id)
            if style.highlightFollowsHover { highlight = item.id }    // menu: hover drives the cursor
        } else if hoveredID == item.id {
            hoveredID = nil
            onHover(nil)
            // highlightFollowsHover keeps the last-lit row on exit (AppKit menu parity) — don't clear highlight
        }
    }

    public var body: some View {
        let parity = zebraParity
        let opaque = surfaceIsOpaque
        let dividers = dividerMap
        let sections = groupedSections
        let band = dropBand
        ScrollView(scrollAxes) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, sec in
                    if let header = sec.header {
                        Section {
                            ForEach(sec.rows, id: \.id) { rowView($0, parity: parity, opaque: opaque, dividers: dividers, band: band) }
                        } header: {
                            // Explicit scroll-target identity: a Section header is not a
                            // ForEach child, so without this `.id` the keyboard follow's
                            // `scrollTo(id:)` cannot resolve a header row and silently
                            // no-ops (facet's tree — every row a header — never scrolled;
                            // an Int-keyed list masks the gap by colliding with the outer
                            // ForEach's `\.offset` identity).
                            rowView(header, parity: parity, opaque: opaque, dividers: dividers, band: band)
                                .id(header.id)
                        }
                    } else {
                        ForEach(sec.rows, id: \.id) { rowView($0, parity: parity, opaque: opaque, dividers: dividers, band: band) }
                    }
                }
            }
            .frame(maxWidth: style.horizontalContentScroll ? nil : .infinity, alignment: .leading)
            .scrollTargetLayout()
            .coordinateSpace(.named(themedListContentSpace))
            .background(GeometryReader { geo in
                Color.clear.onChange(of: geo.size.width, initial: true) { _, w in
                    contentWidth = w                   // sideways abort boundary
                }
            })
            .onPreferenceChange(RowGeomPreference.self) { geomMap = $0 }
            .overlay { dragGhostLayer }
        }
        // `.never`, NOT `.hidden`: on the AppKit-backed macOS `ScrollView` the
        // `.hidden` visibility is a no-op — the hosting scroll view keeps a
        // persistent legacy-style `NSScroller` (system grey, and it reserves a
        // 17pt gutter), identical to passing nothing. `.never` is what removes
        // the scroller from the hierarchy. Measured with an `NSHostingView`
        // probe, 2026-08-08 (t-8649) — and guarded by
        // ThemedListScrollIndicatorTests, because this is exactly the shipped
        // regression. The themed replacement is `scrollIndicatorLayer` below.
        .scrollIndicators(.never)
        .scrollPosition($scrollPos)
        .onScrollGeometryChange(for: ScrollGeom.self) { g in
            ScrollGeom(offset: g.contentOffset, content: g.contentSize, container: g.containerSize)
        } action: { _, new in
            scrollGeom = new
            flashScrollIndicators()
        }
        .overlay { scrollIndicatorLayer }
        // The viewport FOLLOWS the keyboard: the cursor and the drop aim scroll
        // into view whichever side moved them — sill's own `.onKeyPress` path or
        // a host driving `highlight` / `preview.dropTarget` from its own key
        // monitor (facet swallows the arrows before `.onKeyPress` can run, so a
        // scroll that lives only inside `moveHighlight` is unreachable for it).
        // `scrollTo(id:)` is the minimal scroll — a no-op for a visible row —
        // so hover-driven highlight (`highlightFollowsHover`) never jiggles, and
        // a mouse drag's target, which sits under the pointer, never fights it.
        .onChange(of: effectiveHighlight) { _, h in
            guard let h, !previewPinsScroll else { return }
            scrollPos.scrollTo(id: h)
        }
        .onChange(of: dropTargetAnchor) { _, anchor in
            guard let anchor, !previewPinsScroll else { return }
            scrollPos.scrollTo(id: anchor)
        }
        .coordinateSpace(.named(themedListViewportSpace))          // hosted hit-test (M3)
        .onPreferenceChange(RowRectPreference.self) { rects in
            onRowRects(Dictionary(uniqueKeysWithValues: rects.compactMap { key, rect in
                (key.base as? ID).map { ($0, rect) }
            }))
        }
        .background(surfaceBackground)
        .focusable(style.takesKeyboardFocus)              // independent of selectionMode (see ThemedListStyle)
        .focused($focused)
        .onKeyPress(.upArrow)   { if keyboardDragging { aimKeyboard(-1) } else { moveHighlight(-1) }; return .handled }
        .onKeyPress(.downArrow) { if keyboardDragging { aimKeyboard(1) }  else { moveHighlight(1) };  return .handled }
        .onKeyPress(.return)    { if keyboardDragging { commitDrag() } else { activateHighlight() }; return .handled }
        .onKeyPress(.escape)    { if keyboardDragging { cancelDrag() } else { highlight = nil }; return .handled }
        .onKeyPress(.space)     {
            if keyboardDragging { commitDrag() }
            else if style.draggable && highlight != nil { liftKeyboard() }
            else { spacePressed() }
            return .handled
        }
        .overlay {
            if effectiveFocusRing {
                RoundedRectangle(cornerRadius: 4).inset(by: 1)   // Radius.sm; matches AppKit managesFirstResponder ring
                    .stroke(Color(nsColor: palette.primary), lineWidth: 2)
            }
        }
        .onAppear {
            // Freeze a deterministic scroll offset for a static prism capture.
            if let p = preview, p.scrollX != nil || p.scrollY != nil {
                scrollPos.scrollTo(point: CGPoint(x: p.scrollX ?? 0, y: p.scrollY ?? 0))
            }
        }
    }

    // MARK: keyboard navigation (standalone focusable list — .onKeyPress)

    private func moveHighlight(_ delta: Int) {
        let sel = ListItem.selectableIDs(visible)
        guard !sel.isEmpty else { return }
        if style.selectionMode == .multiple, NSEvent.modifierFlags.contains(.shift) {
            let r = extendByKey(current: selection, anchor: selectionAnchor, focus: highlight, delta: delta,
                                selectable: sel, shiftHeld: true, wraps: style.wrapsHighlight)
            selection = r.selection; selectionAnchor = r.anchor; highlight = r.focus
            onSelectionChange(r.selection)
        } else {
            let cur = highlight.flatMap { sel.firstIndex(of: $0) }
            if let next = nextHighlight(current: cur, delta: delta,
                                        selectableIndices: Array(sel.indices), wraps: style.wrapsHighlight) {
                highlight = sel[next]
            }
        }
        // No manual scroll here — the `.onChange(of: effectiveHighlight)` follow
        // covers this path and every host-driven one alike.
    }

    private func activateHighlight() {
        guard let h = highlight else { return }
        if style.selectionMode != .none {
            let r = ThemedListSelect.click(id: h, current: selection, anchor: selectionAnchor,
                                           mods: [], selectable: ListItem.selectableIDs(visible))
            selection = r.selection; selectionAnchor = r.anchor; onSelectionChange(r.selection)
        }
        onActivate(h)
    }

    private func spacePressed() {
        guard let h = highlight else { return }
        if style.selectionMode == .multiple {
            let r = ThemedListSelect.click(id: h, current: selection, anchor: selectionAnchor,
                                           mods: .command, selectable: ListItem.selectableIDs(visible))
            selection = r.selection; selectionAnchor = r.anchor; onSelectionChange(r.selection)
        } else {
            activateHighlight()
        }
    }

    // MARK: drag/reorder (M2c) — geometry produced here, drop math in ListCore

    /// Effective drag state = the frozen `preview` seam (static prism shot) OR the live lift.
    ///
    /// A lift the source validator vetoes must not RENDER either: live it can
    /// never begin (the gesture/keyboard gates), so a frozen `preview` pinning
    /// `dragSource` on a vetoed row would make the bench show a state the
    /// widget cannot reach — a mock, in the t-avbj sense. A chunk-only preview
    /// (no `dragSource`) has no source to judge and passes through.
    private var liftVetoed: Bool {
        guard let s = preview?.dragSource ?? dragState?.source else { return false }
        return !liftValidate(s)
    }
    private var effDragSource: ID? { liftVetoed ? nil : (preview?.dragSource ?? dragState?.source) }
    private var effDragChunk: [ID] { liftVetoed ? [] : (preview?.dragChunk ?? dragState?.chunkIDs ?? []) }
    private var effDropTarget: ListCore.DropTarget<ID>? { liftVetoed ? nil : (preview?.dropTarget ?? dragState?.target) }
    private var dimmedIDs: Set<ID> {
        guard style.draggable || preview != nil else { return [] }
        var s = Set(effDragChunk)
        if let src = effDragSource { s.insert(src) }
        return s
    }
    private func geom(_ id: ID) -> RowGeom? { geomMap[AnyHashable(id)] }

    /// Whether a lift of `item` may begin — the ONE gate every lift entry
    /// consults (the row's drag-gesture attach, the gesture's own guard, and
    /// the keyboard Space lift). `package` so the validator plumbing is
    /// testable without synthesizing input, same as `pointerDropTarget`.
    package func isDragSource(_ item: ListItem<ID>) -> Bool {
        guard style.draggable else { return false }
        if case .separator = item.kind { return false }
        guard !item.isDisabled else { return false }   // headers ARE liftable (they carry their chunk)
        return liftValidate(item.id)
    }

    private func dragGesture(_ item: ListItem<ID>) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(themedListContentSpace))
            .onChanged { value in
                guard isDragSource(item) else { return }
                if dragState == nil {
                    dragState = DragInfo(source: item.id, chunkIDs: chunkIDs(for: item.id),
                                         target: nil, location: value.location)
                }
                var ds = dragState!
                // Lean into the sideways motion, the way a held card does. Smoothed
                // against the previous frame so a jittery pointer doesn't flutter it.
                let dx = value.location.x - ds.location.x
                ds.tilt = max(-7, min(7, ds.tilt * 0.6 + dx * 0.8))
                ds.location = value.location
                // The SIDEWAYS abort zone: a pointer dragged more than the
                // escape margin past the list's left/right edge resolves no
                // target (release does nothing) — the vertical twin lives in
                // `resolveDropTarget`. Flicking a lift off the list is the
                // one way to abandon a mouse drag, so the affordances must
                // disappear out there rather than promise the clamped edge.
                if value.location.x < -dropEscapeMargin
                    || value.location.x > contentWidth + dropEscapeMargin {
                    ds.target = nil
                    dragState = ds
                    return
                }
                let geomArr = visible.map { geom($0.id) ?? RowGeom(yOffset: 0, height: 0) }
                ds.target = pointerDropTarget(atDocY: value.location.y, source: ds.source,
                                              chunkIDs: ds.chunkIDs, geom: geomArr)
                dragState = ds
            }
            .onEnded { _ in
                if let ds = dragState, let target = ds.target {
                    let members = ds.chunkIDs.isEmpty ? [ds.source] : ds.chunkIDs
                    onDrop(ListCore.DragContext(sourceID: ds.source, memberIDs: members), target)
                }
                dragState = nil
            }
    }

    // MARK: drop affordance — computed PER ROW (each row draws relative to itself; no
    // cross-row geometry). Mirrors drawDropAffordance :1872.

    // SwiftUI drag ghost — follows the pointer during a live lift; REPLACES the AppKit
    // DragGhost child window (an in-bounds overlay, so it's screencaptureable + no window).
    //
    // It carries the LIFTED ROWS THEMSELVES, not a label for them: the rows are
    // already here as `ListItem`s, so re-rendering them through `ThemedListRow` is
    // both cheaper and truer than the text chip that used to stand in for them —
    // and unlike a bitmap snapshot it re-themes and re-scales for free.
    //
    // It also reads the `eff*` seam like every other drag affordance. Reading
    // `dragState` directly and refusing to draw under a `preview` is what kept it
    // out of prism's four drag cells since M2c: the bench rendered the dimming and
    // the insertion line but never once the ghost, so no capture could show it
    // regressing.

    /// How many lifted rows the card shows before collapsing the rest into `+N`.
    private var ghostRowCap: Int { 4 }

    /// The rows the lift is carrying, in visible order. A chunk lift may name only
    /// its members (prism's chunk cells do), so the chunk alone is enough.
    private var ghostItems: [ListItem<ID>] {
        var ids = Set(effDragChunk)
        if let src = effDragSource { ids.insert(src) }
        guard !ids.isEmpty else { return [] }
        return visible.filter { ids.contains($0.id) }
    }

    /// The row the card is pinned to when there is no pointer to follow.
    private var ghostAnchor: ID? { effDragSource ?? effDragChunk.first }

    /// The source row's top in content space, summed from the metrics rather than
    /// read out of `geomMap` — the frozen `preview` path has to place the ghost on
    /// the FIRST render pass, before any preference has propagated.
    private func metricRowTop(_ id: ID) -> CGFloat? {
        var y: CGFloat = 0
        for item in visible {
            if item.id == id { return y }
            y += item.laidOutHeight(metrics)
        }
        return nil
    }

    /// Live lift follows the pointer. A frozen `preview` has no pointer, so the card
    /// parks just below the row it lifted — the pose a real lift settles into.
    private func ghostCentre(in size: CGSize) -> CGPoint? {
        if let ds = dragState { return ds.location }
        guard preview != nil, let src = ghostAnchor, let top = metricRowTop(src),
              let first = ghostItems.first
        else { return nil }
        return CGPoint(x: size.width / 2,
                       y: top + first.laidOutHeight(metrics) / 2 + 22)
    }

    @ViewBuilder private func ghostCard(width: CGFloat) -> some View {
        let shown = Array(ghostItems.prefix(ghostRowCap))
        let hidden = ghostItems.count - shown.count
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shown, id: \.id) { item in
                ThemedListRow(item: item, metrics: metrics, style: style, palette: palette,
                              isSelected: false, isHighlighted: false, surfaceOpaque: true)
            }
            if hidden > 0 {
                Text("+\(hidden)")
                    .font(Font(palette.uiFont(.badge) as CTFont))
                    .foregroundColor(Color(nsColor: palette.onPrimary(1)))
                    .padding(.horizontal, 7).frame(height: 16)
                    .background(Capsule().fill(Color(nsColor: palette.primary)))
                    .padding(.horizontal, metrics.leadingInset).padding(.bottom, 6)
            }
        }
        .frame(width: width, alignment: .leading)
        .background(Color(nsColor: palette.background ?? .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: palette.primary), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }

    @ViewBuilder private var dragGhostLayer: some View {
        if !ghostItems.isEmpty {
            GeometryReader { proxy in
                if let centre = ghostCentre(in: proxy.size) {
                    ghostCard(width: max(120, proxy.size.width - 24))
                        .rotationEffect(.degrees(Double(dragState?.tilt ?? 0)))
                        .position(centre)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: keyboard drag (lift / aim / commit / cancel — ThemedList handleDragKey)

    private var keyboardDragging: Bool { dragState?.isKeyboard == true }

    private func liftKeyboard() {
        // The same source gate as the pointer path: a host can drive `highlight`
        // from its own key monitor, so the cursor CAN sit on a row the kit's own
        // ↑↓ (which walks selectable ids) would never reach — disabled or vetoed.
        guard style.draggable, let h = highlight,
              let item = visible.first(where: { $0.id == h }), isDragSource(item) else { return }
        let chunk = kbChunk(for: h)
        dragAim = kbDragAim(from: h, chunkIDs: chunk)
        dragAimIndex = 0
        dragState = DragInfo(source: h, chunkIDs: chunk, target: dragAim.first, location: .zero, isKeyboard: true)
    }

    // The two drag-resolution paths, lifted out of the gesture/keypress
    // closures so the validator plumbing is testable without synthesizing
    // input (package = the ThemedListDropValidatorTests seam).

    /// The validated target a pointer at `docY` resolves to — the single
    /// resolution the mouse drag uses per move.
    package func pointerDropTarget(atDocY docY: CGFloat, source: ID, chunkIDs: [ID],
                                   geom: [RowGeom]) -> ListCore.DropTarget<ID>? {
        resolveDropTarget(atDocY: docY, source: source, rows: visible.map(\.asRow),
                          geom: geom, mode: style.dragMode, chunkIDs: chunkIDs,
                          validate: dropValidate)
    }

    /// The ids a keyboard lift of `h` carries (the section chunk, or none).
    package func kbChunk(for h: ID) -> [ID] { chunkIDs(for: h) }

    /// What a lift of `id` carries — the host's `dragChunk(_:)` provider when
    /// set, else the kit's rule (`chunkMemberIDs`: a header carries its section,
    /// every other row returns []). ONE rule for the pointer and the keyboard:
    /// the two used to compute it separately, which is how a header could lift
    /// under one path and not the other.
    package func chunkIDs(for id: ID) -> [ID] {
        if let chunkProvider { return chunkProvider(id) }
        return chunkMemberIDs(forHeader: id, rows: visible.map(\.asRow))
    }

    /// The ordered keyboard-drag aim a lift of `h` cycles through.
    package func kbDragAim(from h: ID, chunkIDs: [ID]) -> [ListCore.DropTarget<ID>] {
        dragCandidates(source: h, rows: visible.map(\.asRow), mode: style.dragMode,
                       chunkIDs: chunkIDs, validate: dropValidate)
    }

    private func aimKeyboard(_ delta: Int) {
        guard keyboardDragging, !dragAim.isEmpty else { return }
        dragAimIndex = max(0, min(dragAim.count - 1, dragAimIndex + delta))
        dragState?.target = dragAim[dragAimIndex]
    }

    private func commitDrag() {
        guard let ds = dragState, let target = ds.target else { cancelDrag(); return }
        let members = ds.chunkIDs.isEmpty ? [ds.source] : ds.chunkIDs
        onDrop(ListCore.DragContext(sourceID: ds.source, memberIDs: members), target)
        cancelDrag()
    }

    private func cancelDrag() { dragState = nil; dragAim = []; dragAimIndex = 0 }

    /// The band a drop paints, resolved ONCE per render (the body hands the same
    /// value to every row): the member set plus its first/last row in VISIBLE
    /// order. Visible order — not the host array's order — decides which row
    /// draws the top edge and which the bottom.
    package struct DropBand {
        package var members: Set<ID>
        package var first: ID?
        package var last: ID?
    }

    package var dropBand: DropBand? {
        guard let target = effDropTarget, let bandProvider else { return nil }
        let members = Set(bandProvider(target))
        guard !members.isEmpty else { return nil }
        let ordered = visible.map(\.id).filter { members.contains($0) }
        guard !ordered.isEmpty else { return nil }
        return DropBand(members: members, first: ordered.first, last: ordered.last)
    }

    package func rowDrop(_ id: ID, band: DropBand? = nil) -> RowDrop? {
        guard let target = effDropTarget else { return nil }
        // A band OWNS the affordance for its rows: the line/ring would otherwise
        // draw a second, finer promise on top of the area the drop really hits.
        if let band {
            guard band.members.contains(id) else { return nil }
            if band.first == id { return band.last == id ? .bandSolo : .bandTop }
            return band.last == id ? .bandBottom : .bandBody
        }
        let isChunk = !effDragChunk.isEmpty
        switch target.placement {
        case let .onto(tid):
            return id == tid ? .onto : nil
        case let .between(beforeID):
            if let bid = beforeID {
                guard id == bid else { return nil }
                return isChunk ? .sectionBarAbove : .betweenAbove
            } else {                                   // end gap → bottom of the last row
                guard id == visible.last?.id else { return nil }
                return isChunk ? .sectionBarBelow : .betweenBelow
            }
        }
    }

    // MARK: themed scroll indicator (t-8649) — the SwiftUI replacement for the
    // suppressed native `NSScroller`. Geometry comes from `scrollKnob` (pure,
    // ListCore); this layer only paints. `muted` is the knob role — the same
    // "subtle chrome on every theme" convention as the AppKit `ThemedScroller`
    // facet used before the SwiftUI migration. Overlay-style: no track, no
    // reserved gutter, pills float over the content's trailing/bottom edge.

    private var indicatorThickness: CGFloat { 6 }
    private var indicatorEdgeMargin: CGFloat { 3 }

    /// Visible while the viewport moves (then fades), or PERSISTENTLY under a
    /// preview that pins a scroll offset — a static prism capture has no
    /// scroll activity, so activity-gating would make the knob unshowable.
    private var indicatorVisible: Bool { indicatorShown || previewPinsScroll }

    @ViewBuilder private var scrollIndicatorLayer: some View {
        if style.showsScrollIndicators, indicatorVisible, let g = scrollGeom {
            let ink = Color(nsColor: palette.muted)
            ZStack(alignment: .topLeading) {
                Color.clear
                if let v = scrollKnob(content: g.content.height,
                                      viewport: g.container.height,
                                      offset: g.offset.y) {
                    Capsule().fill(ink)
                        .frame(width: indicatorThickness, height: v.length)
                        .offset(x: g.container.width - indicatorThickness - indicatorEdgeMargin,
                                y: v.offset)
                }
                if style.horizontalContentScroll,
                   let h = scrollKnob(content: g.content.width,
                                      viewport: g.container.width,
                                      offset: g.offset.x) {
                    Capsule().fill(ink)
                        .frame(width: h.length, height: indicatorThickness)
                        .offset(x: h.offset,
                                y: g.container.height - indicatorThickness - indicatorEdgeMargin)
                }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Show the pills now, and (re)arm the fade-out. Any frozen `preview` opts
    /// out: activity there is layout noise, and a deterministic capture either
    /// pins a scroll offset (→ persistent knob) or shows no knob at all.
    private func flashScrollIndicators() {
        guard style.showsScrollIndicators, preview == nil else { return }
        indicatorShown = true
        indicatorFade?.cancel()
        indicatorFade = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { indicatorShown = false }
        }
    }

    @ViewBuilder private var surfaceBackground: some View {
        // opaque ⇒ paint the surface; nil / translucent ⇒ .clear so a host material shows through (vibrancy)
        if let surface = effectiveSurface, surface.alphaComponent >= 1 {
            Color(nsColor: surface)
        } else {
            Color.clear
        }
    }
}
