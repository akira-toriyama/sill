import SwiftUI
import MarkdownKit
import PaletteKit

public struct MarkdownView: View {
    public var palette: ResolvedPalette
    public var blocks: [MarkdownBlock]
    public var style: MarkdownStyle
    public var highlighter: MarkdownHighlighter?
    public var textColor: Color?   // nil ⇒ palette.foreground; set to tertiary inside a blockquote

    public init(palette: ResolvedPalette,
                blocks: [MarkdownBlock],
                style: MarkdownStyle = .default,
                highlighter: MarkdownHighlighter? = nil,
                textColor: Color? = nil) {
        self.palette = palette; self.blocks = blocks
        self.style = style; self.highlighter = highlighter; self.textColor = textColor
    }

    public init(palette: ResolvedPalette,
                source: String,
                style: MarkdownStyle = .default,
                highlighter: MarkdownHighlighter? = nil,
                textColor: Color? = nil) {
        self.init(palette: palette, blocks: parseMarkdown(source), style: style,
                  highlighter: highlighter, textColor: textColor)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    private var bodyFont: Font {
        Font.system(size: style.baseFontSize)   // v1: system family; FontKind threading is a later refinement
    }
    private var effectiveTextColor: Color { textColor ?? Color(nsColor: palette.foreground) }

    @ViewBuilder
    func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, content):
            Text(themedInline(content, palette: palette, style: style,
                              baseFont: .system(size: style.headingSize(level)).weight(.bold),
                              textColor: effectiveTextColor))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .overlay(alignment: .bottom) {
                    if level <= 2 {
                        Rectangle().fill(Color(nsColor: palette.border)).frame(height: 1)
                            .offset(y: 4)
                    }
                }
        case let .paragraph(text):
            Text(themedInline(text, palette: palette, style: style, baseFont: bodyFont,
                              textColor: effectiveTextColor))
                .fixedSize(horizontal: false, vertical: true)
        case .thematicBreak:
            Rectangle().fill(Color(nsColor: palette.border)).frame(height: 1).padding(.vertical, 4)
        case let .htmlBlock(html):
            Text(html)
                .font(.system(size: style.baseFontSize, design: .monospaced))
                .foregroundColor(Color(nsColor: palette.tertiary))
                .fixedSize(horizontal: false, vertical: true)
        case let .image(_, alt):
            Text("[image: \(alt)]").foregroundColor(Color(nsColor: palette.muted))
        case let .codeBlock(language, code):
            CodeBlockView(palette: palette, style: style, language: language, code: code, highlighter: highlighter)
        case let .blockquote(children):
            BlockquoteView(palette: palette, style: style, blocks: children, highlighter: highlighter)
        case let .list(list):
            MarkdownListView(palette: palette, style: style, list: list, highlighter: highlighter)
        case let .table(table):
            MarkdownTableView(palette: palette, style: style, table: table)
        }
    }
}
