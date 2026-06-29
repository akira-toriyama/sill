import CoreGraphics

public struct MarkdownStyle: Sendable {
    public var baseFontSize: CGFloat
    public var headingScales: [CGFloat]   // h1..h6 multipliers of baseFontSize
    public var blockSpacing: CGFloat
    public var listIndent: CGFloat
    public var codeCornerRadius: CGFloat
    public var tableCornerRadius: CGFloat

    public init(baseFontSize: CGFloat = 13,
                headingScales: [CGFloat] = [1.75, 1.45, 1.25, 1.12, 1.05, 1.0],
                blockSpacing: CGFloat = 8,
                listIndent: CGFloat = 18,
                codeCornerRadius: CGFloat = 8,
                tableCornerRadius: CGFloat = 6) {
        self.baseFontSize = baseFontSize
        self.headingScales = headingScales
        self.blockSpacing = blockSpacing
        self.listIndent = listIndent
        self.codeCornerRadius = codeCornerRadius
        self.tableCornerRadius = tableCornerRadius
    }

    public static let `default` = MarkdownStyle()

    /// Point size for an h1...h6 heading.
    public func headingSize(_ level: Int) -> CGFloat {
        let i = min(max(level, 1), headingScales.count) - 1
        return baseFontSize * headingScales[i]
    }
}
