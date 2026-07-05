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
}

public struct ThemedListView<ID: Hashable & Sendable>: View {
    let items: [ListItem<ID>]
    @Binding var selection: Set<ID>
    @Binding var collapsed: Set<ID>          // collapsed-section set: id ∈ set ⇒ that header is collapsed
    @Binding var highlight: ID?
    let style: ThemedListStyle
    let palette: ResolvedPalette
    var onActivate: (ID) -> Void
    var onSelectionChange: (Set<ID>) -> Void
    var onToggleSection: (ID) -> Void
    var onHover: (ID?) -> Void
    var onDrop: (ListCore.DragContext<ID>, ListCore.DropTarget<ID>) -> Void
    var onEmptyAction: (String) -> Void
    var onRowRects: ([ID: CGRect]) -> Void        // hosted popup: per-row viewport frames → host hit-test
    var emptyActionRow: ((String) -> String?)?
    var query: String
    var noOptionsText: String
    var preview: ListPreview<ID>?

    public init(items: [ListItem<ID>],
                selection: Binding<Set<ID>> = .constant([]),
                collapsed: Binding<Set<ID>> = .constant([]),
                highlight: Binding<ID?> = .constant(nil),
                style: ThemedListStyle = ThemedListStyle(),
                palette: ResolvedPalette,
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
        self.palette = palette
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

    @State private var selectionAnchor: ID?          // sticky anchor for shift-range
    @State private var hoveredID: ID?                // pointer veil + highlightFollowsHover
    @State private var scrollPos = ScrollPosition(edge: .top)   // frozen-preview + keyboard scroll
    @FocusState private var focused: Bool            // standalone keyboard focus (.onKeyPress)

    // Drag/reorder (M2c) — the live lift + the per-row geometry the pure resolvers consume.
    private struct DragInfo { var source: ID; var chunkIDs: [ID]; var target: ListCore.DropTarget<ID>?; var location: CGPoint; var isKeyboard: Bool = false }
    @State private var dragState: DragInfo?
    @State private var geomMap: [AnyHashable: RowGeom] = [:]
    @State private var dragAim: [ListCore.DropTarget<ID>] = []   // ordered keyboard-drag targets
    @State private var dragAimIndex = 0

    private var metrics: ListMetrics { .forDensity(style.density) }
    private var visible: [ListItem<ID>] { ListItem.visibleRows(items, collapsed: collapsed) }
    private var effectiveSelection: Set<ID> { preview?.selection ?? selection }
    private var effectiveHighlight: ID? { preview?.highlight ?? highlight }

    private var scrollAxes: Axis.Set { style.horizontalContentScroll ? [.horizontal, .vertical] : .vertical }

    /// The effective surface — nil ⇒ vibrancy (host material shows through).
    private var effectiveSurface: NSColor? { style.surfaceColor ?? palette.background }
    private var surfaceIsOpaque: Bool { (effectiveSurface?.alphaComponent ?? 0) >= 1 }

    /// Zebra parity per row id: ordinal among `.row`s, RESETTING to 0 at each header
    /// (mirror ThemedList recomputeLayout :670-682). Headers/separators get `false`.
    private var zebraParity: [ID: Bool] {
        var map: [ID: Bool] = [:]
        var ordinal = 0
        for item in visible {
            switch item.kind {
            case .row:            map[item.id] = (ordinal % 2 == 1); ordinal += 1
            case .sectionHeader:  ordinal = 0
            case .separator:      break
            }
        }
        return map
    }

    /// Per-row divider leading x, keyed by id. Only after a `.row` (not headers /
    /// separators), suppressed above a separator; full-bleed (0) above a header, else
    /// inset to the row's text x (mirror drawRow :1211-1220).
    private var dividerMap: [ID: CGFloat] {
        guard style.showsDividers else { return [:] }
        var map: [ID: CGFloat] = [:]
        let rows = visible
        for i in rows.indices where i < rows.count - 1 {
            let cur = rows[i]
            guard case .row = cur.kind else { continue }
            let next = rows[i + 1]
            if case .separator = next.kind { continue }
            var nextIsHeader = false
            if case .sectionHeader = next.kind { nextIsHeader = true }
            let indent = CGFloat(max(0, cur.indentLevel)) * metrics.indentStep
            map[cur.id] = nextIsHeader ? 0
                : (style.reservesLeadingImageColumn ? metrics.textXOrigin : metrics.leadingInset) + indent
        }
        return map
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

    @ViewBuilder private func rowView(_ item: ListItem<ID>, parity: [ID: Bool], opaque: Bool, dividers: [ID: CGFloat]) -> some View {
        ThemedListRow(item: item, metrics: metrics, style: style, palette: palette,
                      isSelected: effectiveSelection.contains(item.id),
                      isHighlighted: effectiveHighlight == item.id,
                      isHovered: preview == nil && hoveredID == item.id,
                      zebraOdd: parity[item.id] ?? false,
                      surfaceOpaque: opaque,
                      dividerInset: dividers[item.id],
                      isCollapsed: headerIsCollapsed(item),
                      dimmed: dimmedIDs.contains(item.id),
                      drop: rowDrop(item.id))
            .reportRowGeom(item.id)
            .reportRowRect(item.id, when: style.hosted)
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

    private func handleTap(_ item: ListItem<ID>) {
        switch item.kind {
        case let .sectionHeader(_, kindCollapsed):
            guard kindCollapsed != nil, !item.isDisabled else { return }   // collapsible only
            withAnimation(.easeInOut(duration: 0.2)) {
                collapsed = toggleSection(item.id, in: collapsed)          // ListCore — animates the row diff + caret
            }
            onToggleSection(item.id)
        case .row where !item.isDisabled:
            if style.selectionMode == .none { onActivate(item.id); return }
            let r = ThemedListSelect.click(id: item.id, current: selection, anchor: selectionAnchor,
                                           mods: currentSelectMods(), selectable: ListItem.selectableIDs(visible))
            selection = r.selection
            selectionAnchor = r.anchor
            onSelectionChange(r.selection)
            onActivate(item.id)
        default:
            break
        }
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
        ScrollView(scrollAxes) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, sec in
                    if let header = sec.header {
                        Section {
                            ForEach(sec.rows, id: \.id) { rowView($0, parity: parity, opaque: opaque, dividers: dividers) }
                        } header: {
                            rowView(header, parity: parity, opaque: opaque, dividers: dividers)
                        }
                    } else {
                        ForEach(sec.rows, id: \.id) { rowView($0, parity: parity, opaque: opaque, dividers: dividers) }
                    }
                }
            }
            .frame(maxWidth: style.horizontalContentScroll ? nil : .infinity, alignment: .leading)
            .scrollTargetLayout()
            .coordinateSpace(.named(themedListContentSpace))
            .onPreferenceChange(RowGeomPreference.self) { geomMap = $0 }
            .overlay { dragGhostLayer }
        }
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPos)
        .coordinateSpace(.named(themedListViewportSpace))          // hosted hit-test (M3)
        .onPreferenceChange(RowRectPreference.self) { rects in
            onRowRects(Dictionary(uniqueKeysWithValues: rects.compactMap { key, rect in
                (key.base as? ID).map { ($0, rect) }
            }))
        }
        .background(surfaceBackground)
        .focusable(style.selectionMode != .none)          // standalone lists take keyboard focus
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
            if focused {
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
        if let h = highlight { scrollPos.scrollTo(id: h) }
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
    private var effDragSource: ID? { preview?.dragSource ?? dragState?.source }
    private var effDragChunk: [ID] { preview?.dragChunk ?? dragState?.chunkIDs ?? [] }
    private var effDropTarget: ListCore.DropTarget<ID>? { preview?.dropTarget ?? dragState?.target }
    private var dimmedIDs: Set<ID> {
        guard style.draggable || preview != nil else { return [] }
        var s = Set(effDragChunk)
        if let src = effDragSource { s.insert(src) }
        return s
    }
    private func geom(_ id: ID) -> RowGeom? { geomMap[AnyHashable(id)] }

    private func isDragSource(_ item: ListItem<ID>) -> Bool {
        guard style.draggable else { return false }
        if case .separator = item.kind { return false }
        return !item.isDisabled            // headers ARE liftable (they carry their chunk)
    }

    private func dragGesture(_ item: ListItem<ID>) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(themedListContentSpace))
            .onChanged { value in
                guard isDragSource(item) else { return }
                if dragState == nil {
                    var chunk: [ID] = []
                    if case .sectionHeader = item.kind { chunk = chunkMemberIDs(forHeader: item.id, rows: visible.map(\.asRow)) }
                    dragState = DragInfo(source: item.id, chunkIDs: chunk, target: nil, location: value.location)
                }
                var ds = dragState!
                ds.location = value.location
                let geomArr = visible.map { geom($0.id) ?? RowGeom(yOffset: 0, height: 0) }
                ds.target = resolveDropTarget(atDocY: value.location.y, source: ds.source, rows: visible.map(\.asRow),
                                              geom: geomArr, mode: style.dragMode, chunkIDs: ds.chunkIDs,
                                              validate: { _, _ in true })
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
    @ViewBuilder private var dragGhostLayer: some View {
        if let ds = dragState, preview == nil {
            let count = ds.chunkIDs.isEmpty ? 1 : ds.chunkIDs.count
            let title = items.first { $0.id == ds.source }?.primary ?? ""
            HStack(spacing: 6) {
                Text(title).font(Font(palette.uiFont(.body) as CTFont)).lineLimit(1)
                    .foregroundColor(Color(nsColor: palette.foreground))
                if count > 1 {
                    Text("\(count)")
                        .font(Font(palette.uiFont(.badge) as CTFont))
                        .foregroundColor(Color(nsColor: palette.onPrimary(1)))
                        .padding(.horizontal, 7).frame(height: 16)
                        .background(Capsule().fill(Color(nsColor: palette.primary)))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: palette.background ?? .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: palette.primary), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            .position(ds.location)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    // MARK: keyboard drag (lift / aim / commit / cancel — ThemedList handleDragKey)

    private var keyboardDragging: Bool { dragState?.isKeyboard == true }

    private func liftKeyboard() {
        guard style.draggable, let h = highlight else { return }
        var chunk: [ID] = []
        if let item = visible.first(where: { $0.id == h }), case .sectionHeader = item.kind {
            chunk = chunkMemberIDs(forHeader: h, rows: visible.map(\.asRow))
        }
        dragAim = dragCandidates(source: h, rows: visible.map(\.asRow), mode: style.dragMode,
                                 chunkIDs: chunk, validate: { _, _ in true })
        dragAimIndex = 0
        dragState = DragInfo(source: h, chunkIDs: chunk, target: dragAim.first, location: .zero, isKeyboard: true)
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

    private func rowDrop(_ id: ID) -> RowDrop? {
        guard let target = effDropTarget else { return nil }
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

    @ViewBuilder private var surfaceBackground: some View {
        // opaque ⇒ paint the surface; nil / translucent ⇒ .clear so a host material shows through (vibrancy)
        if let surface = effectiveSurface, surface.alphaComponent >= 1 {
            Color(nsColor: surface)
        } else {
            Color.clear
        }
    }
}
