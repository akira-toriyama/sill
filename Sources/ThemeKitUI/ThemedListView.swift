// ThemeKitUI — the SwiftUI-native, generic `ThemedListView<ID>` (#17b M2): the new
// CANONICAL themed list/tree. Replaces the old 37-line `NSViewRepresentable` bridge
// over the AppKit `ThemedList`. Draws hand-built themed rows from `ResolvedPalette`
// roles and projects its image-bearing `ListItem<ID>` down to `ListCore.ListRow` so
// every selection / collapse / DnD decision routes through the pure M1 cores.
//
// M2 stages: M2a = rendering + single-select + hover (this file's initial form);
// M2b = animated collapse + multi-select + keyboard; M2c = drag + overlay ghost.
// The AppKit `ThemedList` and its tests stay intact until the M5 retire.

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
    @Binding var expanded: Set<ID>          // collapsed-section set: id ∈ set ⇒ that header is collapsed
    @Binding var highlight: ID?
    let style: ThemedListStyle
    let palette: ResolvedPalette
    var onActivate: (ID) -> Void
    var onSelectionChange: (Set<ID>) -> Void
    var onToggleSection: (ID) -> Void
    var onHover: (ID?) -> Void
    var onDrop: (ListCore.DragContext<ID>, ListCore.DropTarget<ID>) -> Void
    var onEmptyAction: (String) -> Void
    var emptyActionRow: ((String) -> String?)?
    var query: String
    var noOptionsText: String
    var preview: ListPreview<ID>?

    public init(items: [ListItem<ID>],
                selection: Binding<Set<ID>> = .constant([]),
                expanded: Binding<Set<ID>> = .constant([]),
                highlight: Binding<ID?> = .constant(nil),
                style: ThemedListStyle = ThemedListStyle(),
                palette: ResolvedPalette,
                onActivate: @escaping (ID) -> Void = { _ in },
                onSelectionChange: @escaping (Set<ID>) -> Void = { _ in },
                onToggleSection: @escaping (ID) -> Void = { _ in },
                onHover: @escaping (ID?) -> Void = { _ in },
                onDrop: @escaping (ListCore.DragContext<ID>, ListCore.DropTarget<ID>) -> Void = { _, _ in },
                onEmptyAction: @escaping (String) -> Void = { _ in },
                emptyActionRow: ((String) -> String?)? = nil,
                query: String = "",
                noOptionsText: String = "No options",
                preview: ListPreview<ID>? = nil) {
        self.items = items
        self._selection = selection
        self._expanded = expanded
        self._highlight = highlight
        self.style = style
        self.palette = palette
        self.onActivate = onActivate
        self.onSelectionChange = onSelectionChange
        self.onToggleSection = onToggleSection
        self.onHover = onHover
        self.onDrop = onDrop
        self.onEmptyAction = onEmptyAction
        self.emptyActionRow = emptyActionRow
        self.query = query
        self.noOptionsText = noOptionsText
        self.preview = preview
    }

    @State private var selectionAnchor: ID?          // sticky anchor for shift-range (M2b)
    @State private var hoveredID: ID?                // pointer veil + highlightFollowsHover
    @State private var scrollPos = ScrollPosition(edge: .top)   // frozen-preview scroll offset

    private var metrics: ListMetrics { .forDensity(style.density) }
    private var visible: [ListItem<ID>] { ListItem.visibleRows(items, collapsed: expanded) }
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

    private func rowView(_ item: ListItem<ID>, parity: [ID: Bool], opaque: Bool, dividers: [ID: CGFloat]) -> some View {
        ThemedListRow(item: item, metrics: metrics, style: style, palette: palette,
                      isSelected: effectiveSelection.contains(item.id),
                      isHighlighted: effectiveHighlight == item.id,
                      isHovered: preview == nil && hoveredID == item.id,
                      zebraOdd: parity[item.id] ?? false,
                      surfaceOpaque: opaque,
                      dividerInset: dividers[item.id])
            .contentShape(Rectangle())
            .onTapGesture { handleTap(item) }
            .onHover { handleHover(item, $0) }
    }

    // MARK: interaction (inert under a frozen `preview` / constant bindings)

    private func handleTap(_ item: ListItem<ID>) {
        switch item.kind {
        case let .sectionHeader(_, collapsed):
            if collapsed != nil, !item.isDisabled { onToggleSection(item.id) }   // collapse animates in M2b
        case .row where !item.isDisabled:
            if style.selectionMode == .none { onActivate(item.id); return }
            let r = ThemedListSelect.click(id: item.id, current: selection, anchor: selectionAnchor,
                                           mods: [], selectable: ListItem.selectableIDs(visible))  // multi-mods: M2b
            selection = r.selection
            selectionAnchor = r.anchor
            onSelectionChange(r.selection)
            onActivate(item.id)
        default:
            break
        }
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
        }
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPos)
        .background(surfaceBackground)
        .onAppear {
            // Freeze a deterministic scroll offset for a static prism capture.
            if let p = preview, p.scrollX != nil || p.scrollY != nil {
                scrollPos.scrollTo(point: CGPoint(x: p.scrollX ?? 0, y: p.scrollY ?? 0))
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
