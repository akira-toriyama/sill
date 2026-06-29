import CoreGraphics

// Value types for `ThemedGridView` (#17e). Pure/Sendable so a consumer can build
// them off the main actor and pass them in.

/// How the grid distributes cells across the cross-axis.
public enum GridLayout: Sendable {
    /// A fixed number of equal-width columns (rows for a horizontal axis).
    case fixed(columns: Int)
    /// As many columns as fit, each at least `minCellWidth` wide.
    case adaptive(minCellWidth: CGFloat)
}

/// The render state of one cell, handed to the cell builder so it can add its
/// own emphasis on top of the chrome `ThemedGridView` already draws.
public struct GridCellState: Sendable {
    public let isSelected: Bool
    public let isHovered: Bool
    public let isFocused: Bool
    public init(isSelected: Bool, isHovered: Bool, isFocused: Bool) {
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.isFocused = isFocused
    }
}
