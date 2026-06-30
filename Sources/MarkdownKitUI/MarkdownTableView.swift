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

    // LazyVGrid lays out a FLAT stream of cells; a nested ForEach (rows × cols)
    // fails to emit the body cells, so flatten header + body into one sequence.
    private struct CellRef: Identifiable {
        let id: Int
        let text: AttributedString
        let column: Int
        let isHeader: Bool
    }
    private var flatCells: [CellRef] {
        var out: [CellRef] = []
        var i = 0
        for (c, h) in table.header.enumerated() {
            out.append(CellRef(id: i, text: h, column: c, isHeader: true)); i += 1
        }
        for row in table.rows {
            for (c, t) in row.enumerated() {
                out.append(CellRef(id: i, text: t, column: c, isHeader: false)); i += 1
            }
        }
        return out
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(flatCells) { gc in
                cell(gc.text, column: gc.column, header: gc.isHeader)
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
