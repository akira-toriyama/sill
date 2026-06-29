import SwiftUI
import AppKit
import PaletteKit

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
    private let palette: ResolvedPalette
    private let onActivate: ((String) -> Void)?
    private let allowsMultiSelect: Bool

    /// Multi-select (or uncontrolled when `selection == nil`).
    public init(_ items: [ThumbnailItem],
                selection: Binding<Set<String>>? = nil,
                layout: GridLayout = .adaptive(minCellWidth: 160),
                axis: Axis = .vertical,
                aspectRatio: CGFloat? = nil,
                palette: ResolvedPalette,
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
                palette: ResolvedPalette,
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
                 palette: ResolvedPalette,
                 onActivate: ((String) -> Void)?,
                 allowsMultiSelect: Bool) {
        self.items = items
        self.selection = selection
        self.layout = layout
        self.axis = axis
        self.aspectRatio = aspectRatio
        self.palette = palette
        self.onActivate = onActivate
        self.allowsMultiSelect = allowsMultiSelect
    }

    public var body: some View {
        ThemedGridView(items, id: \.id, selection: selection,
                       layout: layout, axis: axis, aspectRatio: aspectRatio,
                       palette: palette, onActivate: onActivate,
                       allowsMultiSelect: allowsMultiSelect) { item, _ in
            ThemedThumbnailCell(image: item.image, label: item.label, palette: palette)
        }
    }
}
