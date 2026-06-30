import SwiftUI
import MarkdownKit
import PaletteKit

// TEMP — replaced by Tasks 12–14. Each becomes its own file; delete the matching stub there.
struct BlockquoteView: View {
    var palette: ResolvedPalette; var style: MarkdownStyle
    var blocks: [MarkdownBlock]; var highlighter: MarkdownHighlighter?
    var body: some View { Text("quote") }
}
struct MarkdownListView: View {
    var palette: ResolvedPalette; var style: MarkdownStyle
    var list: MarkdownList; var highlighter: MarkdownHighlighter?
    var body: some View { Text("list") }
}
struct MarkdownTableView: View {
    var palette: ResolvedPalette; var style: MarkdownStyle; var table: MarkdownTable
    var body: some View { Text("table") }
}
