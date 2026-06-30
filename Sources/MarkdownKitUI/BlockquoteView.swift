import SwiftUI
import MarkdownKit
import PaletteKit

struct BlockquoteView: View {
    var palette: ResolvedPalette
    var style: MarkdownStyle
    var blocks: [MarkdownBlock]
    var highlighter: MarkdownHighlighter?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(Color(nsColor: palette.primary))
                .frame(width: 3)
            MarkdownView(palette: palette, blocks: blocks, style: style,
                         highlighter: highlighter,
                         textColor: Color(nsColor: palette.tertiary))
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
