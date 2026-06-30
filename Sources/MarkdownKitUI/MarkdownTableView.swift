import SwiftUI
import MarkdownKit
import PaletteKit

struct MarkdownTableView: View {
    var palette: ResolvedPalette
    var style: MarkdownStyle
    var table: MarkdownTable

    private var columnCount: Int { max(table.columns.count, table.header.count) }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: max(columnCount, 1))
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<table.header.count, id: \.self) { c in
                cell(table.header[c], column: c, header: true)
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                ForEach(0..<row.count, id: \.self) { c in
                    cell(row[c], column: c, header: false)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: style.tableCornerRadius)
            .stroke(Color(nsColor: palette.border)))
        .clipShape(RoundedRectangle(cornerRadius: style.tableCornerRadius))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func alignment(_ c: Int) -> Alignment {
        guard c < table.columns.count else { return .leading }
        switch table.columns[c] {
        case .center: return .center
        case .right: return .trailing
        case .left, .none: return .leading
        }
    }

    private func textAlignment(_ c: Int) -> TextAlignment {
        guard c < table.columns.count else { return .leading }
        switch table.columns[c] {
        case .center: return .center
        case .right: return .trailing
        case .left, .none: return .leading
        }
    }

    @ViewBuilder
    private func cell(_ content: AttributedString, column c: Int, header: Bool) -> some View {
        let baseFont = Font.system(size: style.baseFontSize).weight(header ? .semibold : .regular)
        Text(themedInline(content, palette: palette, style: style, baseFont: baseFont,
                          textColor: Color(nsColor: palette.foreground)))
            .multilineTextAlignment(textAlignment(c))
            .frame(maxWidth: .infinity, alignment: alignment(c))
            .padding(6)
            .background(header ? Color(nsColor: palette.surface(.inset)) : Color.clear)
            .overlay(Rectangle().stroke(Color(nsColor: palette.border), lineWidth: 0.5))
    }
}
