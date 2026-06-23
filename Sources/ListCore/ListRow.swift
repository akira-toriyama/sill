import Foundation

/// The kind of a list row — the pure shadow of `ThemeKit.ListItem.Kind`. Carries no
/// `ID` (a header/separator's identity lives on `ListRow.id`).
public enum RowKind: Hashable, Sendable {
    case row
    /// A group label (1-line, or 2-line with `subtitle`). `collapsed`: `nil` ⇒ plain
    /// non-interactive header; `false` ⇒ collapsible + expanded (▾); `true` ⇒ collapsed (▸).
    case sectionHeader(subtitle: String? = nil, collapsed: Bool? = nil)
    /// A non-interactive thin rule between groups; skipped by nav / hover / activation.
    case separator
}

/// The pure, Sendable shadow of a `ThemedList` row used by every `ListCore` resolver,
/// so the cores never link an `NSImage`. `ThemeKit`/`ThemeKitUI`'s image-bearing item
/// projects to this via `asRow`. Generic over `ID` (the AppKit widget is `String`-keyed).
public struct ListRow<ID: Hashable & Sendable>: Hashable, Sendable {
    public let id: ID
    public let kind: RowKind
    public let isDisabled: Bool
    /// Visual nesting depth (0 = top level). The kit only uses it to know tree shape;
    /// the host owns which rows are children.
    public let indentLevel: Int

    public init(id: ID, kind: RowKind = .row, isDisabled: Bool = false, indentLevel: Int = 0) {
        self.id = id; self.kind = kind; self.isDisabled = isDisabled; self.indentLevel = indentLevel
    }

    public var isHeader: Bool { if case .sectionHeader = kind { return true }; return false }
    public var isSeparator: Bool { if case .separator = kind { return true }; return false }
    public var headerSubtitle: String? { if case let .sectionHeader(s, _) = kind { return s }; return nil }
    public var headerCollapsed: Bool? { if case let .sectionHeader(_, c) = kind { return c }; return nil }
    /// A header the user can toggle: collapsible (its `collapsed` flag is non-nil) and not disabled.
    public var isCollapsibleHeader: Bool { isHeader && !isDisabled && headerCollapsed != nil }
    /// Eligible for selection / roving highlight: an enabled, non-header, non-separator row.
    public var isSelectable: Bool { !isHeader && !isSeparator && !isDisabled }
}
