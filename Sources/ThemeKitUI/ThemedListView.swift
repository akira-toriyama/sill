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

    private var metrics: ListMetrics { .forDensity(style.density) }
    private var visible: [ListItem<ID>] { ListItem.visibleRows(items, collapsed: expanded) }
    private var effectiveSelection: Set<ID> { preview?.selection ?? selection }
    private var effectiveHighlight: ID? { preview?.highlight ?? highlight }

    private var scrollAxes: Axis.Set { style.horizontalContentScroll ? [.horizontal, .vertical] : .vertical }

    public var body: some View {
        ScrollView(scrollAxes) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visible, id: \.id) { item in
                    ThemedListRow(item: item, metrics: metrics, style: style, palette: palette,
                                  isSelected: effectiveSelection.contains(item.id),
                                  isHighlighted: effectiveHighlight == item.id)
                }
            }
            .frame(maxWidth: style.horizontalContentScroll ? nil : .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(surfaceBackground)
    }

    @ViewBuilder private var surfaceBackground: some View {
        // opaque ⇒ paint the surface; nil / translucent ⇒ .clear so a host material shows through (vibrancy)
        let surface = style.surfaceColor ?? palette.background
        if let surface, surface.alphaComponent >= 1 {
            Color(nsColor: surface)
        } else {
            Color.clear
        }
    }
}
