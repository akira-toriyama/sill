/// A pixel-art sprite as ASCII rows + a per-character colour map. Each row is a
/// string of palette keys; a key NOT present in `palette` is TRANSPARENT (the
/// sentinel — conventionally `"."`). Pure + `Sendable`: the grid is rigid
/// integer geometry, the draw side scales it (`ScaleTier`) and tints it.
///
/// `rows[0]` is the TOP row; `cells()` flattens to opaque `(col, row, colour)`
/// in row-major order (top first, left to right) so the output is deterministic
/// for tests. Colours are `0xRRGGBB`; the AppKit draw side maps them via
/// `NSColor(HexColor(_:))`.
public struct PixelSprite: Sendable, Equatable {
    /// Top-to-bottom rows; each character indexes `palette`.
    public let rows: [String]
    /// Character → `0xRRGGBB`. A character absent here is transparent.
    public let palette: [Character: UInt32]

    /// Width in cells = the longest row (rows MAY be ragged — a short row simply
    /// emits fewer cells; it is not auto-padded).
    public var width: Int { rows.map(\.count).max() ?? 0 }
    /// Height in cells = the row count.
    public var height: Int { rows.count }

    public init(rows: [String], palette: [Character: UInt32]) {
        self.rows = rows
        self.palette = palette
    }

    /// Flatten to opaque cells: `(col, row)` is the grid coordinate (row 0 =
    /// top), `colour` is the resolved `0xRRGGBB`. Transparent cells are OMITTED.
    /// Row-major order (top row first, left to right) — deterministic.
    public func cells() -> [(col: Int, row: Int, color: UInt32)] {
        var out: [(col: Int, row: Int, color: UInt32)] = []
        for (r, line) in rows.enumerated() {
            for (c, ch) in line.enumerated() {
                guard let color = palette[ch] else { continue }
                out.append((col: c, row: r, color: color))
            }
        }
        return out
    }
}

#if canImport(CoreGraphics)
import CoreGraphics

extension PixelSprite {
    /// The pixel-grid bounding box at a given cell size, as a `CGSize` — a
    /// CoreGraphics convenience for apps laying the sprite out (the Sample /
    /// Trail / Splatter gated-overload idiom; the core stays CG-free).
    public func pixelSize(cell: CGFloat) -> CGSize {
        CGSize(width: CGFloat(width) * cell, height: CGFloat(height) * cell)
    }
}
#endif
