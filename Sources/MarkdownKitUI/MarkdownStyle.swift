import CoreGraphics

/// Typography knobs for `MarkdownView` — fed into the `NSTextView` renderer's
/// `Style` (colors come from the `ResolvedPalette`, these are the metrics).
public struct MarkdownStyle: Sendable {
    public var baseFontSize: CGFloat
    public var headingScales: [CGFloat]   // h1..h6 multipliers of baseFontSize
    public var bodyLineSpacing: CGFloat
    public var listIndent: CGFloat
    public var codeBlockIndent: CGFloat
    public var blockquoteIndent: CGFloat
    public var codeBlockParagraphSpacing: CGFloat
    public var pillCornerRadius: CGFloat   // inline-code rounded-pill radius

    public init(baseFontSize: CGFloat = 13,
                headingScales: [CGFloat] = [1.75, 1.45, 1.25, 1.12, 1.05, 1.0],
                bodyLineSpacing: CGFloat = 4,
                listIndent: CGFloat = 18,
                codeBlockIndent: CGFloat = 10,
                blockquoteIndent: CGFloat = 16,
                codeBlockParagraphSpacing: CGFloat = 6,
                pillCornerRadius: CGFloat = 4) {
        self.baseFontSize = baseFontSize
        self.headingScales = headingScales
        self.bodyLineSpacing = bodyLineSpacing
        self.listIndent = listIndent
        self.codeBlockIndent = codeBlockIndent
        self.blockquoteIndent = blockquoteIndent
        self.codeBlockParagraphSpacing = codeBlockParagraphSpacing
        self.pillCornerRadius = pillCornerRadius
    }

    public static let `default` = MarkdownStyle()
}
