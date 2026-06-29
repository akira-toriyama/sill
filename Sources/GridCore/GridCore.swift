import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// GridCore — Foundation-only, Sendable, AppKit-free pure math behind ThemeKitUI's
// native `ThemedGridView` (#17e). No type named `GridCore` (module==type
// collision); the surface is top-level free functions, like ListCore/Motion.

/// Adaptive column count: the most cells of width ≥ `minCellWidth` (separated by
/// `gap`) that fit in `availableWidth`, clamped to `1...maxColumns`.
public func gridColumns(availableWidth: CGFloat, minCellWidth: CGFloat,
                        gap: CGFloat, max maxColumns: Int) -> Int {
    guard availableWidth > 0, minCellWidth > 0, maxColumns > 0 else { return 1 }
    // n cells fit when n*minCellWidth + (n-1)*gap ≤ availableWidth
    //   ⇒ n ≤ (availableWidth + gap) / (minCellWidth + gap)
    let raw = Int((availableWidth + gap) / (minCellWidth + gap))
    return Swift.min(Swift.max(raw, 1), maxColumns)
}

/// One cell's size given `columns`. `aspectRatio` = width/height (nil ⇒ square).
public func gridCellSize(availableWidth: CGFloat, columns: Int,
                         gap: CGFloat, aspectRatio: CGFloat?) -> CGSize {
    let cols = Swift.max(columns, 1)
    let totalGap = gap * CGFloat(cols - 1)
    let w = Swift.max((availableWidth - totalGap) / CGFloat(cols), 0)
    let h = (aspectRatio.map { $0 > 0 ? w / $0 : w }) ?? w
    return CGSize(width: w, height: h)
}

/// Next focused index after a (dx,dy) move over a row-major grid of `count`
/// items in `columns`. `wrap` wraps at edges; a move into the ragged last row
/// past the final item snaps back to the last real index.
public func nextGridIndex(from index: Int, dx: Int, dy: Int,
                          count: Int, columns: Int, wrap: Bool) -> Int {
    guard count > 0 else { return index }
    let cols = Swift.max(columns, 1)
    let i = Swift.min(Swift.max(index, 0), count - 1)
    let rows = (count + cols - 1) / cols
    var row = i / cols
    var col = i % cols
    if dx != 0 {
        col += dx
        if col < 0 { col = wrap ? cols - 1 : 0 }
        if col >= cols { col = wrap ? 0 : cols - 1 }
    }
    if dy != 0 {
        row += dy
        if row < 0 { row = wrap ? rows - 1 : 0 }
        if row >= rows { row = wrap ? 0 : rows - 1 }
    }
    let target = row * cols + col
    return target >= count ? count - 1 : target   // ragged last-row snap
}

/// Drop selected ids no longer present (reconcile a persisted selection).
public func reconcileGridSelection<ID: Hashable>(_ selection: Set<ID>,
                                                  existing ids: Set<ID>) -> Set<ID> {
    selection.intersection(ids)
}
