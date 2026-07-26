import SwiftUI
import PaletteKit

/// The public themed Markdown front. Renders a GFM string into a **selectable**,
/// copyable `NSTextView` (floor-3 AppKit render core) themed by `ResolvedPalette`:
/// inline code is a rounded pill, tables/code-blocks/blockquotes get real
/// `NSTextTable` rules, and selection/find work natively. Re-themes by reassigning
/// `palette`. Content-sized — wrap in a `ScrollView` for a clamped/scrolling popover.
public struct MarkdownView: View {
    @Environment(\.sillPalette) private var ambientPalette
    private let explicitPalette: ResolvedPalette?
    /// Explicit argument > ambient `.sillTheme(_:)` > the process default.
    public var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }
    public var source: String
    public var style: MarkdownStyle
    public var highlighter: MarkdownHighlighter?

    public init(palette: ResolvedPalette? = nil,
                source: String,
                style: MarkdownStyle = .default,
                highlighter: MarkdownHighlighter? = nil) {
        self.explicitPalette = palette
        self.source = source
        self.style = style
        self.highlighter = highlighter
    }

    public var body: some View {
        MarkdownTextView(palette: palette, source: source, style: style, highlighter: highlighter)
    }
}
