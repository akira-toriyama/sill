import SwiftUI
import MarkdownKit
import PaletteKit
import ThemeKit

struct MarkdownListView: View {
    var palette: ResolvedPalette
    var style: MarkdownStyle
    var list: MarkdownList
    var highlighter: MarkdownHighlighter?

    var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing / 2) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    marker(for: item, index: i)
                        .frame(width: style.listIndent, alignment: .trailing)
                    MarkdownView(palette: palette, blocks: item.blocks, style: style, highlighter: highlighter)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(for item: MarkdownListItem, index i: Int) -> some View {
        if let checkbox = item.checkbox {
            let slug = checkbox == .checked ? "check-square" : "square"
            if let img = phosphorImage(slug, pt: style.baseFontSize) {
                Image(nsImage: img)
                    .renderingMode(.template)
                    .foregroundColor(Color(nsColor: palette.foreground))
            } else {
                Text(checkbox == .checked ? "☑" : "☐")
                    .foregroundColor(Color(nsColor: palette.foreground))
            }
        } else if list.ordered {
            Text("\(list.start + i).")
                .font(.system(size: style.baseFontSize))
                .foregroundColor(Color(nsColor: palette.foreground))
        } else {
            Text("•")
                .font(.system(size: style.baseFontSize))
                .foregroundColor(Color(nsColor: palette.foreground))
        }
    }
}
