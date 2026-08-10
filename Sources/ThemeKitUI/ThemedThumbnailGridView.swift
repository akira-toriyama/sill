import SwiftUI
import AppKit
import PaletteKit
import GridCore

// ThemeKitUI — the batteries-included form of `ThemedGridView` (#17e): pass a list
// of {id, image?, label?} and get a themed thumbnail grid with the default
// `ThemedThumbnailCell`. Two inits: multi-select (`Binding<Set<String>>`) and
// single-select (`Binding<String?>`, bridged to a 0/1 set internally).

// @unchecked Sendable: all stored props are immutable (`let`) value types; `image` is an NSImage set once at init and only read on @MainActor.
public struct ThumbnailItem: Identifiable, @unchecked Sendable {
    public let id: String
    public let image: NSImage?
    public let label: String?
    public init(id: String, image: NSImage?, label: String? = nil) {
        self.id = id; self.image = image; self.label = label
    }
}

public struct ThemedThumbnailGridView: View {
    private let items: [ThumbnailItem]
    private let selection: Binding<Set<String>>?
    private let layout: GridLayout
    private let axis: Axis
    private let aspectRatio: CGFloat?
    @Environment(\.sillPalette) private var ambientPalette
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    private let onActivate: ((String) -> Void)?
    private let allowsMultiSelect: Bool

    /// Frozen chrome / shimmer for a static capture, forwarded to the inner
    /// `ThemedGridView` / `ThemedThumbnailCell`. Set via the methods below,
    /// not init parameters (the API differ reads an init-label change as a
    /// removal — see `ListPreview.hovering`).
    private var previewState: GridPreview<String>?
    private var frozenShimmerPhase: CGFloat?

    /// A copy rendering the frozen grid chrome (hover / cursor / focus).
    public func preview(_ p: GridPreview<String>?) -> Self {
        var c = self; c.previewState = p; return c
    }
    /// A copy with every loading cell's shimmer parked at `phase` (nil = live).
    public func previewShimmerPhase(_ phase: CGFloat?) -> Self {
        var c = self; c.frozenShimmerPhase = phase; return c
    }

    // DnD opt-in, forwarded verbatim to the inner `ThemedGridView` (t-n3be).
    private var dragMode: GridDragMode?
    private var dropValidate: (GridDragContext<String>, GridDropTarget<String>) -> Bool = { _, _ in true }
    private var onDropHandler: ((GridDragContext<String>, GridDropTarget<String>) -> Void)?

    /// A copy whose cells can be pointer-dragged (see `ThemedGridView.draggable`).
    public func draggable(_ mode: GridDragMode = .dropOnto) -> Self {
        var c = self; c.dragMode = mode; return c
    }
    /// A copy whose drag resolution consults `validate` first.
    public func dropTargetValidator(_ validate: @escaping (GridDragContext<String>, GridDropTarget<String>) -> Bool) -> Self {
        var c = self; c.dropValidate = validate; return c
    }
    /// A copy that delivers a committed drop.
    public func onGridDrop(_ handler: @escaping (GridDragContext<String>, GridDropTarget<String>) -> Void) -> Self {
        var c = self; c.onDropHandler = handler; return c
    }

    /// Multi-select (or uncontrolled when `selection == nil`).
    public init(_ items: [ThumbnailItem],
                selection: Binding<Set<String>>? = nil,
                layout: GridLayout = .adaptive(minCellWidth: 160),
                axis: Axis = .vertical,
                aspectRatio: CGFloat? = nil,
                palette: ResolvedPalette? = nil,
                onActivate: ((String) -> Void)? = nil) {
        self.init(items, selection: selection, layout: layout, axis: axis,
                  aspectRatio: aspectRatio, palette: palette, onActivate: onActivate,
                  allowsMultiSelect: true)
    }

    /// Single-select convenience — bridges a `Binding<String?>` to the 0/1 set.
    public init(_ items: [ThumbnailItem],
                selection single: Binding<String?>,
                layout: GridLayout = .adaptive(minCellWidth: 160),
                axis: Axis = .vertical,
                aspectRatio: CGFloat? = nil,
                palette: ResolvedPalette? = nil,
                onActivate: ((String) -> Void)? = nil) {
        let bridged = Binding<Set<String>>(
            get: { single.wrappedValue.map { [$0] } ?? [] },
            set: { single.wrappedValue = $0.first }
        )
        self.init(items, selection: bridged, layout: layout, axis: axis,
                  aspectRatio: aspectRatio, palette: palette, onActivate: onActivate,
                  allowsMultiSelect: false)
    }

    /// Designated init — carries the internal `allowsMultiSelect` flag the two
    /// public inits set (multi ⇒ true, single ⇒ false).
    private init(_ items: [ThumbnailItem],
                 selection: Binding<Set<String>>?,
                 layout: GridLayout,
                 axis: Axis,
                 aspectRatio: CGFloat?,
                 palette: ResolvedPalette? = nil,
                 onActivate: ((String) -> Void)?,
                 allowsMultiSelect: Bool) {
        self.items = items
        self.selection = selection
        self.layout = layout
        self.axis = axis
        self.aspectRatio = aspectRatio
        self.explicitPalette = palette
        self.onActivate = onActivate
        self.allowsMultiSelect = allowsMultiSelect
    }

    public var body: some View {
        configuredGrid
    }

    /// Plain accessor (not a @ViewBuilder) so the DnD copy-methods can chain
    /// conditionally onto the concrete `ThemedGridView` value.
    private var configuredGrid: some View {
        var grid = ThemedGridView(items, id: \.id, selection: selection,
                                  layout: layout, axis: axis, aspectRatio: aspectRatio,
                                  palette: palette, onActivate: onActivate,
                                  allowsMultiSelect: allowsMultiSelect) { item, _ in
            ThemedThumbnailCell(image: item.image, label: item.label, palette: palette)
                .previewShimmerPhase(frozenShimmerPhase)
        }
        .preview(previewState)
        .dropTargetValidator(dropValidate)
        if let mode = dragMode { grid = grid.draggable(mode) }
        if let handler = onDropHandler { grid = grid.onGridDrop(handler) }
        return grid
    }
}
