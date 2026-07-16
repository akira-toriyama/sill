// ListCore — pure list DECORATION rules (R10): zebra parity + divider insets,
// lifted out of `ThemedListView` so the parity/geometry logic is testable and
// shared. Both walk the VISIBLE rows in order (the renderer passes
// `visible.map(\.asRow)`); neither knows about selection/hover — those gate the
// PAINTING of a decoration, in the row view, not its computation.

import Foundation

/// Zebra parity per row id: ordinal among `.row`s, RESETTING to 0 at each
/// header (the AppKit widget's recomputeLayout rule). Headers and separators
/// carry no flag — and a separator does not consume an ordinal, so the stripe
/// rhythm continues across it.
public func zebraParity<ID: Hashable>(rows: [ListRow<ID>]) -> [ID: Bool] {
    var map: [ID: Bool] = [:]
    var ordinal = 0
    for row in rows {
        switch row.kind {
        case .row:            map[row.id] = (ordinal % 2 == 1); ordinal += 1
        case .sectionHeader:  ordinal = 0
        case .separator:      break
        }
    }
    return map
}

#if canImport(CoreGraphics)
import CoreGraphics

/// Per-row divider leading x, keyed by the id of the row ABOVE the divider.
/// Only after a `.row` (not headers / separators, and never the last row),
/// suppressed above a separator (the band replaces the rule); full-bleed (0)
/// above a header, else inset to the row's text x — `textXBase` plus the row's
/// own indent (`max(0, indentLevel) * indentStep`). The caller gates on its
/// `showsDividers` style and supplies `textXBase` from its metrics
/// (`textXOrigin` when the leading image column is reserved, else
/// `leadingInset`).
public func dividerInsets<ID: Hashable>(rows: [ListRow<ID>],
                                        textXBase: CGFloat,
                                        indentStep: CGFloat) -> [ID: CGFloat] {
    var map: [ID: CGFloat] = [:]
    for i in rows.indices where i < rows.count - 1 {
        let cur = rows[i]
        guard case .row = cur.kind else { continue }
        let next = rows[i + 1]
        if case .separator = next.kind { continue }
        let indent = CGFloat(max(0, cur.indentLevel)) * indentStep
        map[cur.id] = next.isHeader ? 0 : textXBase + indent
    }
    return map
}
#endif
