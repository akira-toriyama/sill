import SwiftUI
import PaletteKit

private let hairspace = "\u{200A}"   // thin padding around inline code

@MainActor
func themedInline(_ source: AttributedString,
                  palette: ResolvedPalette,
                  style: MarkdownStyle,
                  baseFont: Font,
                  textColor: Color) -> AttributedString {
    var result = AttributedString()
    for run in source.runs {
        var slice = AttributedString(source[run.range])
        let intent = run.inlinePresentationIntent ?? []
        let isCode = intent.contains(.code)

        // font: monospaced for code, else weight/italic from emphasis
        var font = isCode ? Font.system(size: style.baseFontSize, design: .monospaced) : baseFont
        if intent.contains(.stronglyEmphasized) { font = font.weight(.bold) }
        if intent.contains(.emphasized) { font = font.italic() }
        slice.font = font

        // color: link → primary, else the threaded textColor (foreground / tertiary-in-quote)
        slice.foregroundColor = run.link != nil ? Color(nsColor: palette.primary) : textColor
        if run.link != nil { slice.underlineStyle = .single }
        if intent.contains(.strikethrough) { slice.strikethroughStyle = .single }
        slice.inlinePresentationIntent = nil   // translated to explicit attrs; prevent SwiftUI double-styling

        if isCode {
            slice.backgroundColor = Color(nsColor: palette.surface(.inset))
            // hairspace padding so the flat fill has breathing room (no rounded run bg in SwiftUI)
            var pad = AttributedString(hairspace)
            pad.font = font
            pad.backgroundColor = Color(nsColor: palette.surface(.inset))
            result.append(pad); result.append(slice); result.append(pad)
        } else {
            result.append(slice)
        }
    }
    return result
}
