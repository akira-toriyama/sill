import SwiftUI
import MarkdownKit
import PaletteKit

struct CodeBlockView: View {
    var palette: ResolvedPalette
    var style: MarkdownStyle
    var language: String?
    var code: String
    var highlighter: MarkdownHighlighter?

    private var monoFont: Font { .system(size: style.baseFontSize, design: .monospaced) }

    private var rendered: AttributedString {
        if let highlighter, let hl = highlighter.highlight(code, language: language) { return hl }
        var plain = AttributedString(code)
        plain.font = monoFont
        plain.foregroundColor = Color(nsColor: palette.foreground)
        return plain
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.system(size: style.baseFontSize * 0.78, design: .monospaced))
                    .foregroundColor(Color(nsColor: palette.tertiary))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(rendered).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: style.codeCornerRadius)
            .fill(Color(nsColor: palette.surface(.inset))))
        .overlay(RoundedRectangle(cornerRadius: style.codeCornerRadius)
            .stroke(Color(nsColor: palette.border), lineWidth: 0.5))
    }
}
