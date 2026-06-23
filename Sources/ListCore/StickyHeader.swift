import Foundation
#if canImport(CoreGraphics)
import CoreGraphics

/// The pinned section header for a given visible-top scroll offset (pure). Returns the
/// active header's index and the y at which to draw it: normally `bandTop`, but pushed
/// up (`nextTop - headerHeight`, may go above `bandTop`) when the next header is within
/// one header-height — the hand-off. nil ⇒ no header at/above the top.
public func stickyHeader(atVisibleTop bandTop: CGFloat, headerIndices: [Int],
                         yOffsets: [CGFloat], heights: [CGFloat]) -> (index: Int, drawY: CGFloat)? {
    guard let active = headerIndices.last(where: { yOffsets[$0] <= bandTop }) else { return nil }
    let hH = heights[active]
    var drawY = bandTop
    if let next = headerIndices.first(where: { yOffsets[$0] > yOffsets[active] }) {
        let nextTop = yOffsets[next]
        if nextTop - bandTop < hH { drawY = nextTop - hH }
    }
    return (active, drawY)
}
#endif
