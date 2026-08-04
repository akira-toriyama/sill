// ThemeKitUI — the render-bearing row model for the SwiftUI-native `ThemedListView`
// (#17b M2). It carries an `NSImage`, so it can't live in the pure/Sendable
// `ListCore`; instead it PROJECTS to `ListCore.ListRow` (`asRow`) — the pure shadow
// every selection / collapse / DnD core reasons over. The `Badge` /
// `TrailingAccessory` / `ListTint` value types live beside it in
// `ListAccessories.swift` (rescued at the #17b M5 retire of the AppKit widget).
// Generic over `ID` per the spec.

import AppKit
import ListCore

/// What a click on a row resolves to. Three INDEPENDENT decisions, so none of
/// them can quietly acquire a gate on another — which is exactly how tapping a
/// section header came to require the header be collapsible, and how a
/// `.none` list stopped reporting activation at all.
struct RowTapOutcome: Equatable {
    var togglesSection = false
    var selects = false
    var activates = false
}

public struct ListItem<ID: Hashable & Sendable> {
    public enum Kind: Equatable {
        case row
        case sectionHeader(subtitle: String? = nil, collapsed: Bool? = nil)
        case separator
    }

    /// Pure tap resolution — the decision half of `ThemedListView.handleTap`,
    /// lifted out so it is testable without a click and so each outcome is
    /// derived from only the input that legitimately governs it:
    /// collapsibility governs COLLAPSING, `selectionMode` governs SELECTING,
    /// and neither governs whether an enabled row reports ACTIVATION.
    static func tapOutcome(kind: Kind, isDisabled: Bool, selectionMode: SelectionMode) -> RowTapOutcome {
        guard !isDisabled else { return RowTapOutcome() }
        switch kind {
        case let .sectionHeader(_, collapsed):
            return RowTapOutcome(togglesSection: collapsed != nil, activates: true)
        case .row:
            return RowTapOutcome(selects: selectionMode != .none, activates: true)
        case .separator:
            return RowTapOutcome()
        }
    }

    public let id: ID
    public var image: NSImage?
    public var primary: String
    public var secondary: String?
    public var secondaryMono: Bool
    public var badges: [Badge]
    public var trailing: TrailingAccessory
    public var tint: ListTint
    public var kind: Kind
    public var isDisabled: Bool
    public var indentLevel: Int
    public var axChecked: Bool

    public init(id: ID, image: NSImage? = nil, primary: String,
                secondary: String? = nil, secondaryMono: Bool = false,
                badges: [Badge] = [], trailing: TrailingAccessory = .none,
                tint: ListTint = .none, kind: Kind = .row, isDisabled: Bool = false,
                indentLevel: Int = 0, axChecked: Bool = false) {
        self.id = id; self.image = image; self.primary = primary
        self.secondary = secondary; self.secondaryMono = secondaryMono
        self.badges = badges; self.trailing = trailing; self.tint = tint
        self.kind = kind; self.isDisabled = isDisabled
        self.indentLevel = indentLevel; self.axChecked = axChecked
    }

    /// The pure shadow the cores see — no NSImage crosses into `ListCore`.
    public var asRow: ListRow<ID> {
        let rowKind: RowKind
        switch kind {
        case .row:
            rowKind = .row
        case let .sectionHeader(subtitle, collapsed):
            rowKind = .sectionHeader(subtitle: subtitle, collapsed: collapsed)
        case .separator:
            rowKind = .separator
        }
        return ListRow(id: id, kind: rowKind, isDisabled: isDisabled, indentLevel: indentLevel)
    }

    /// The rows the renderer + every core treat as "visible": a collapsed section
    /// keeps its header and drops its body rows. Delegates to the single canonical
    /// `ListCore.flattenVisible` so renderer / DnD / chunk / sticky share one truth.
    public static func visibleRows(_ items: [ListItem<ID>], collapsed: Set<ID>) -> [ListItem<ID>] {
        let visibleIDs = Set(flattenVisible(rows: items.map(\.asRow), collapsed: collapsed).map(\.id))
        return items.filter { visibleIDs.contains($0.id) }
    }

    /// Selectable id order (headers / separators / disabled excluded) — the ordered
    /// domain every `MultiSelection` / `nextHighlight` call operates on.
    public static func selectableIDs(_ items: [ListItem<ID>]) -> [ID] {
        items.filter { $0.asRow.isSelectable }.map(\.id)
    }

    /// The row's laid-out height under `metrics` — the ONE M2 height rule, shared by
    /// the SwiftUI row (`ThemedListRow.body`) and the synchronous measurer
    /// (`ListController.contentHeight` / row rects).
    func laidOutHeight(_ metrics: ListMetrics) -> CGFloat {
        switch kind {
        case .separator:                       return metrics.separatorBand
        case let .sectionHeader(subtitle, _):  return subtitle == nil ? metrics.header1 : metrics.header2
        case .row:                             return secondary == nil ? metrics.singleRow : metrics.twoLineRow
        }
    }
}
