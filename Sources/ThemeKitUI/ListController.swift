// ThemeKitUI — the imperative driver for a `ThemedListView` hosted in a non-key
// AppKit popup (#17b M3). A non-activating panel's SwiftUI content never becomes
// first responder, so the combo/menu drive the roving highlight from OUTSIDE
// (field key-forwarders / an NSEvent monitor) by mutating this `@Observable`
// controller; the view is the passive renderer of `highlight`/`selection`. Mirrors
// the AppKit `ThemedList`'s imperative surface 1:1 so the hosts translate calls,
// not concepts. Highlight math delegates to the pure M1 `ListCore`.
import SwiftUI
import ListCore

@Observable @MainActor
public final class ListController<ID: Hashable & Sendable> {
    public var items: [ListItem<ID>] = []
    public var highlight: ID?
    public var selection: Set<ID> = []
    public var query: String = ""
    public var noOptionsText: String = "No options"
    /// Deterministic still-capture seam (mirrors `ThemedList.previewHighlight`).
    public var previewHighlight: ID?
    public var style = ThemedListStyle()
    /// When set, an empty `items` offers ONE synthetic actionable row (the combo's
    /// "create ‹query›"). Returns the row's label, or nil to keep the empty state inert.
    public var emptyActionRow: ((String) -> String?)?

    public var onActivate: (ID) -> Void = { _ in }
    public var onEmptyAction: (String) -> Void = { _ in }
    public var onHover: (ID?) -> Void = { _ in }

    /// Per-row frames in the hosting view's coordinate space, reduced from the
    /// SwiftUI view's `PreferenceKey` (M3 Task 2). The AppKit host reads these to
    /// map a `mouseUp`/`mouseMoved` point back to a row id.
    public var rowRects: [ID: CGRect] = [:]

    public init() {}

    /// True when the empty state is an actionable "create" row (combo parity).
    public var isActionRowActive: Bool { items.isEmpty && (emptyActionRow?(query) != nil) }

    private var selectableIndices: [Int] {
        items.indices.filter { items[$0].asRow.isSelectable }
    }

    public func moveHighlight(_ delta: Int) {
        let cur = highlight.flatMap { id in items.firstIndex { $0.id == id } }
        guard let np = nextHighlight(current: cur, delta: delta,
                                     selectableIndices: selectableIndices,
                                     wraps: style.wrapsHighlight) else { highlight = nil; return }
        highlight = items[np].id
    }

    public func clearHighlight() { highlight = nil }

    /// Read-back of the current highlight (nil for a header / no highlight). The
    /// combo checks this to decide whether Return commits a row or just closes.
    public var highlightedID: ID? { highlight }

    /// Commit the highlighted row (→ `onActivate`) or the actionable empty row
    /// (→ `onEmptyAction`), matching `ThemedList.activateHighlight` + combo parity:
    /// the action row fires even with no highlight.
    public func activateHighlight() {
        if isActionRowActive { onEmptyAction(query); return }
        if let id = highlight { onActivate(id) }
    }

    /// AppKit `mouseUp` entry point — the SYNCHRONOUS commit (M3 Task 3). Same-tick.
    public func fireActivate(_ id: ID) { onActivate(id) }

    /// Resolve a point (hosting-view coords) to the row under it, nil if none.
    public func row(at point: CGPoint) -> ID? {
        rowRects.first { $0.value.contains(point) }?.key
    }

    /// AppKit tracking entry point — set the roving highlight from hover (when
    /// `highlightFollowsHover`) + report the hover edge to the host's guard.
    public func setHover(_ id: ID?) {
        if style.highlightFollowsHover, let id { highlight = id }
        onHover(id)
    }
}
