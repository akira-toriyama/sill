// ThemeKitUI — the imperative driver for a `ThemedListView` hosted in a non-key
// AppKit popup (#17b M3). A non-activating panel's SwiftUI content never becomes
// first responder, so the combo/menu drive the roving highlight from OUTSIDE
// (field key-forwarders / an NSEvent monitor) by mutating this `@Observable`
// controller; the view is the passive renderer of `highlight`/`selection`. Mirrors
// the AppKit `ThemedList`'s imperative surface 1:1 so the hosts translate calls,
// not concepts. Highlight math delegates to the pure M1 `ListCore`.
import SwiftUI
import AppKit
import PaletteKit
import ThemeKit          // Badge / TrailingAccessory value types (measurement)
import ListCore

@Observable @MainActor
public final class ListController<ID: Hashable & Sendable> {
    public var items: [ListItem<ID>] = []
    public var highlight: ID?
    public var selection: Set<ID> = []
    public var query: String = ""
    public var noOptionsText: String = "No options"
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

    /// The hosting `NSView` (`HostingListView` sets it to itself) — used ONLY to
    /// convert a row's viewport rect to screen coords in `rowRectOnScreen`. Weak:
    /// `HostingListView` already holds a strong ref to this controller, so a strong
    /// back-edge would retain-cycle.
    public weak var hostView: NSView?

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

    // MARK: - Measurement (a popup host sizes its panel to the content + anchors a
    // child beside a row). SYNCHRONOUS — a menu sizes/anchors on the SAME tick it
    // opens, before SwiftUI reports `rowRects`. `contentHeight` is pure (metric
    // constants); `fittingWidth` needs `NSFont` so both live here, not in `ListCore`.

    private var metrics: ListMetrics { .forDensity(style.density) }
    private static var headerKern: CGFloat { 0.5 }          // matches ThemedListRow's `.tracking(0.5)`

    /// Total content height — the sum of every row's height. An empty list keeps one
    /// synthetic row (matching the AppKit widget). The host adds its own border / vpad.
    public func contentHeight() -> CGFloat {
        guard !items.isEmpty else { return metrics.singleRow }
        return items.reduce(0) { $0 + $1.laidOutHeight(metrics) }
    }

    /// The content width that fits every row's text without truncation, capped at
    /// `maxWidth` — a menu sizes to its widest item. Ports `ThemedList.fittingWidth`:
    /// leading slot + indent (+ a header's disclosure gutter) + measured text +
    /// trailing cluster (shortcut / chevron / badges) + both insets. Fonts come from
    /// the caller's palette (the value-typed list root owns colour; the host has it).
    public func fittingWidth(maxWidth: CGFloat = .greatestFiniteMagnitude,
                             palette: ResolvedPalette) -> CGFloat {
        let m = metrics
        let textXBase = style.reservesLeadingImageColumn ? m.textXOrigin : m.leadingInset
        var w: CGFloat = 0
        for item in items {
            if case .separator = item.kind { continue }
            let row = item.asRow
            let isHeader = row.isHeader
            let isOneLineHeader = isHeader && row.headerSubtitle == nil
            let indent = CGFloat(max(0, item.indentLevel)) * m.indentStep
            let textX = (isHeader ? m.leadingInset + (row.headerCollapsed != nil ? m.disclosureGutter : 0)
                                  : textXBase) + indent
            let pFont: NSFont = isHeader
                ? (row.headerSubtitle != nil ? palette.uiFont(.sectionTitle) : palette.uiFont(.sectionHeader))
                : palette.uiFont(.body)
            let pText = isOneLineHeader ? item.primary.uppercased() : item.primary
            // A 1-line header is drawn with per-char tracking — measure it the same way.
            var textW = isOneLineHeader
                ? ceil((pText as NSString).size(withAttributes: [.font: pFont, .kern: Self.headerKern]).width)
                : measure(pText, font: pFont)
            if let secondary = item.secondary {
                let sFont = item.secondaryMono ? NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
                                               : palette.uiFont(.secondaryBody)
                textW = max(textW, measure(secondary, font: sFont))
            }
            if let sub = row.headerSubtitle {
                textW = max(textW, measure(sub, font: palette.uiFont(.caption)))
            }
            let trailing = isHeader ? 0 : trailingClusterWidth(item, palette: palette, m: m)
            let rowW = textX + textW + (trailing > 0 ? trailing + m.budgetMargin : 0) + m.trailingInset
            w = max(w, rowW)
        }
        return min(maxWidth, ceil(w))
    }

    private func measure(_ s: String, font: NSFont) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: font]).width)
    }

    /// The trailing cluster's width — badges (in order) + the accessory (rightmost),
    /// with the AppKit inter-piece gaps (badge↔badge = `badgeGap`, else `clusterGap`).
    private func trailingClusterWidth(_ item: ListItem<ID>, palette: ResolvedPalette, m: ListMetrics) -> CGFloat {
        // Piece widths in AppKit order: accessory first (rightmost), then badges reversed.
        var pieceIsBadge: [Bool] = []
        var widths: [CGFloat] = []
        if item.trailing != .none { widths.append(accessoryWidth(item.trailing, palette: palette, m: m)); pieceIsBadge.append(false) }
        for b in item.badges.reversed() { widths.append(badgeWidth(b, palette: palette, m: m)); pieceIsBadge.append(true) }
        guard !widths.isEmpty else { return 0 }
        var total: CGFloat = 0
        for i in widths.indices {
            if i > 0 { total += (pieceIsBadge[i - 1] && pieceIsBadge[i]) ? m.badgeGap : m.clusterGap }
            total += widths[i]
        }
        return total
    }

    private func accessoryWidth(_ a: TrailingAccessory, palette: ResolvedPalette, m: ListMetrics) -> CGFloat {
        switch a {
        case .none:            return 0
        case .chevron:         return m.chevronPt
        case let .shortcut(s): return ceil((s as NSString).size(withAttributes: [.font: palette.uiFont(.shortcut)]).width) + m.shortcutHPad * 2
        case let .custom(img): return img.size.height > 0 ? m.badgeHeight * (img.size.width / img.size.height) : m.badgeHeight
        }
    }

    private func badgeWidth(_ b: Badge, palette: ResolvedPalette, m: ListMetrics) -> CGFloat {
        var w = ceil((b.text as NSString).size(withAttributes: [.font: palette.uiFont(.badge)]).width) + m.badgeHPad * 2
        if b.symbol != nil { w += m.badgeSymbolPt + 3 }
        return w
    }

    /// A row's rect in SCREEN coordinates — a host anchoring a child popup beside a
    /// parent row (a submenu). Live `rowRects` (scroll-aware) when SwiftUI has
    /// reported them, else a synchronous pure-layout rect (scroll 0 — a fresh /
    /// non-scrolling popup), converted out through the hosting view → window → screen.
    public func rowRectOnScreen(_ id: ID) -> CGRect? {
        guard let host = hostView, let win = host.window,
              let vp = rowRects[id] ?? pureRowRect(id) else { return nil }
        // `vp` is viewport space (top-left origin, y-down, like `RowRectPreference`).
        // Mirror `HostingListView.viewportPoint`'s inverse to reach the view's coords.
        var r = vp
        if !host.isFlipped { r.origin.y = host.bounds.height - vp.maxY }
        return win.convertToScreen(host.convert(r, to: nil))
    }

    /// A row's viewport rect from the pure layout (scroll 0) — the synchronous
    /// fallback before SwiftUI reports `rowRects`.
    private func pureRowRect(_ id: ID) -> CGRect? {
        guard let host = hostView, let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        var y: CGFloat = 0
        for i in 0..<idx { y += items[i].laidOutHeight(metrics) }
        return CGRect(x: 0, y: y, width: host.bounds.width, height: items[idx].laidOutHeight(metrics))
    }
}
