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
/// Exposed for consumers that size cells themselves; ThemedGridView defers to SwiftUI's grid sizing.
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
    return target >= count ? count - 1 : target
}

/// Next focused index for a (dx,dy) intent, honoring the grid's main axis. A
/// horizontal grid (LazyHGrid) fills column-major, so the screen-space dx/dy are
/// swapped before the row-major `nextGridIndex`; a vertical grid is unchanged.
/// `columns` is the cross-axis track count (columns for vertical, rows for
/// horizontal).
public func nextGridIndex(from index: Int, dx: Int, dy: Int, count: Int,
                          columns: Int, horizontal: Bool, wrap: Bool) -> Int {
    let (mdx, mdy) = horizontal ? (dy, dx) : (dx, dy)
    return nextGridIndex(from: index, dx: mdx, dy: mdy,
                         count: count, columns: columns, wrap: wrap)
}

/// Drop selected ids no longer present (reconcile a persisted selection).
public func reconcileGridSelection<ID: Hashable>(_ selection: Set<ID>,
                                                  existing ids: Set<ID>) -> Set<ID> {
    selection.intersection(ids)
}

#if canImport(CoreGraphics)
/// Cell size that keeps EVERY row of a `count`-cell, `columns`-track grid inside
/// `available` (no scrolling) — width-driven first, then shrunk if the stacked
/// rows would overflow the height, preserving `aspectRatio` (width/height,
/// nil ⇒ square) either way. The non-scrolling overlay-grid sizing rule
/// (t-mej6 G1): SwiftUI's own grid only ever sizes off the cross axis, so a
/// fit-to-viewport grid must pre-compute the cell.
public func gridFittedCellSize(available: CGSize, count: Int, columns: Int,
                               gap: CGFloat, aspectRatio: CGFloat?) -> CGSize {
    let cols = Swift.max(columns, 1)
    let rows = Swift.max((Swift.max(count, 1) + cols - 1) / cols, 1)
    let ratio = (aspectRatio.flatMap { $0 > 0 ? $0 : nil }) ?? 1
    let w = Swift.max((available.width - gap * CGFloat(cols - 1)) / CGFloat(cols), 1)
    let h = w / ratio
    let maxH = Swift.max((available.height - gap * CGFloat(rows - 1)) / CGFloat(rows), 1)
    guard h > maxH else { return CGSize(width: w, height: h) }
    return CGSize(width: maxH * ratio, height: maxH)
}

/// The candidate index a directional keyboard aim moves to, chosen by GEOMETRY:
/// from `points[current]`, the nearest point whose displacement lies strictly in
/// the pressed direction (`dx`/`dy` ∈ {-1, 0, 1}). A 2-D grid's aim list is not
/// linear (the source drops out, slots interleave), so index arithmetic lies —
/// distance in the direction pressed doesn't. No candidate that way ⇒ `current`
/// (edges don't wrap; the lift stays put). Pure / testable.
public func gridAimIndex(from current: Int, dx: Int, dy: Int,
                         points: [CGPoint]) -> Int {
    guard points.indices.contains(current), dx != 0 || dy != 0 else { return current }
    let origin = points[current]
    var best = current
    var bestDist = CGFloat.greatestFiniteMagnitude
    for (i, p) in points.enumerated() where i != current {
        let vx = p.x - origin.x, vy = p.y - origin.y
        // Strictly on the pressed side, and STRICTLY more forward than
        // sideways — an exact 45° diagonal belongs to neither arrow, else a
        // gap's diagonal neighbour would beat the true row/column neighbour
        // farther away.
        let forward = CGFloat(dx) * vx + CGFloat(dy) * vy
        let sideways = abs(CGFloat(dx) * vy) + abs(CGFloat(dy) * vx)
        guard forward > 0.5, sideways < forward else { continue }
        let d = vx * vx + vy * vy
        if d < bestDist { bestDist = d; best = i }
    }
    return best
}
#endif
