import AppKit
import SwiftUI       // Color → NSColor bridge for the injected highlighter
import Markdown
import PaletteKit

/// Renders a GFM document (swift-markdown AST) into one `NSAttributedString` for the
/// floor-3 `NSTextView` host. Ported from glance's `MarkdownRenderer`: the whole
/// document is flattened into a single attributed string (so the host's one
/// `NSTextView` gives continuous selection), with `NSTextTable` carrying real
/// table/code-block/blockquote rules and `.backgroundColor` marking inline code for
/// `InlineCodePillLayoutManager`.
///
/// Two glance couplings are swapped for sill seams: colors come from a `Style` built
/// off a `ResolvedPalette` (roles + `ink` tiers), and syntax highlighting goes
/// through sill's pluggable `MarkdownHighlighter` (no Highlightr dependency in sill).
struct MarkdownRenderer {

    struct Style {
        var baseFontSize: CGFloat
        var bodyLineSpacing: CGFloat
        var foreground: NSColor
        var tertiary: NSColor               // blockquote / raw HTML / lang label / hr
        var primary: NSColor                // link
        var border: NSColor                 // table inner hairline
        var inlineCodeBackground: NSColor   // the pill fill
        var codeBlockBackground: NSColor
        var tableHeaderBackground: NSColor
        var tableOuterBorder: NSColor
        var blockquoteBar: NSColor
        var headingUnderline: NSColor
        var codeBlockIndent: CGFloat
        var blockquoteIndent: CGFloat
        var listIndent: CGFloat
        var codeBlockParagraphSpacing: CGFloat
        var headingScales: [CGFloat]

        /// Map a resolved sill palette + typography knobs into the renderer Style —
        /// glance's `rendererStyle` recipe (neutral white-alpha overlays come from the
        /// shared `ink` tier so they track the theme): wash ≈ inline pill / outer
        /// rule, subtle ≈ block / header bg / heading underline, strong ≈ blockquote
        /// bar.
        @MainActor
        init(palette: ResolvedPalette, markdown: MarkdownStyle) {
            baseFontSize = markdown.baseFontSize
            bodyLineSpacing = markdown.bodyLineSpacing
            foreground = palette.foreground
            tertiary = palette.tertiary
            primary = palette.primary
            border = palette.border
            inlineCodeBackground = palette.ink(.wash, of: .foreground)
            codeBlockBackground = palette.ink(.subtle, of: .foreground)
            tableHeaderBackground = palette.ink(.subtle, of: .foreground)
            tableOuterBorder = palette.ink(.wash, of: .foreground)
            blockquoteBar = palette.ink(.strong, of: .foreground)
            headingUnderline = palette.ink(.subtle, of: .foreground)
            codeBlockIndent = markdown.codeBlockIndent
            blockquoteIndent = markdown.blockquoteIndent
            listIndent = markdown.listIndent
            codeBlockParagraphSpacing = markdown.codeBlockParagraphSpacing
            headingScales = markdown.headingScales
        }
    }

    let style: Style
    let highlighter: MarkdownHighlighter?

    func render(_ text: String) -> NSAttributedString {
        let document = Document(parsing: text)
        var visitor = Visitor(style: style, highlighter: highlighter)
        let out = NSMutableAttributedString()
        let children = Array(document.children)
        for (index, child) in children.enumerated() {
            out.append(visitor.visit(child))
            // single newline + paragraphSpacing between blocks (\n\n doubles the gap).
            if index < children.count - 1 {
                out.append(NSAttributedString(string: "\n"))
            }
        }
        return out
    }
}

// MARK: - Visitor

private struct Visitor: MarkupVisitor {
    typealias Result = NSAttributedString

    let style: MarkdownRenderer.Style
    let highlighter: MarkdownHighlighter?

    // MARK: font helpers

    private var bodyFont: NSFont { .systemFont(ofSize: style.baseFontSize) }
    private var monoFont: NSFont { .monospacedSystemFont(ofSize: style.baseFontSize, weight: .regular) }

    private func bodyParagraph() -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.bodyLineSpacing
        return p
    }

    private func bodyAttrs() -> [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: style.foreground, .paragraphStyle: bodyParagraph()]
    }

    // MARK: block join

    /// The block-join policy, in one place: sibling blocks are separated by ONE
    /// body-attributed newline (each block carries its own paragraphSpacing, so
    /// "\n\n" would double the gap), and nothing follows the last sibling.
    ///
    /// This is the block SEPARATOR only. The other bare `"\n"`s in this file are a
    /// different operation and must NOT be routed through here: the code-block /
    /// blockquote / table-cell terminators are unconditional, and the cell's own
    /// paragraph style is stamped over them afterwards — they are deliberately
    /// unattributed.
    private func appendBlockSeparator(to out: NSMutableAttributedString,
                                      after index: Int, of count: Int) {
        guard index < count - 1 else { return }
        out.append(NSAttributedString(string: "\n", attributes: bodyAttrs()))
    }

    // MARK: default / unknown

    mutating func defaultVisit(_ markup: Markup) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for child in markup.children { out.append(visit(child)) }
        return out
    }

    // MARK: inline

    mutating func visitText(_ text: Markdown.Text) -> NSAttributedString {
        NSAttributedString(string: text.plainText, attributes: bodyAttrs())
    }

    mutating func visitSoftBreak(_ break_: SoftBreak) -> NSAttributedString {
        NSAttributedString(string: " ", attributes: bodyAttrs())
    }

    mutating func visitLineBreak(_ break_: LineBreak) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: bodyAttrs())
    }

    mutating func visitStrong(_ strong: Strong) -> NSAttributedString {
        let inner = NSMutableAttributedString()
        for child in strong.children { inner.append(visit(child)) }
        applyTrait(.boldFontMask, to: inner)
        return inner
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> NSAttributedString {
        let inner = NSMutableAttributedString()
        for child in emphasis.children { inner.append(visit(child)) }
        applyTrait(.italicFontMask, to: inner)
        return inner
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> NSAttributedString {
        let inner = NSMutableAttributedString()
        for child in strikethrough.children { inner.append(visit(child)) }
        let r = NSRange(location: 0, length: inner.length)
        inner.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        return inner
    }

    /// Inline code: `.backgroundColor` marks the run; `InlineCodePillLayoutManager`
    /// rounds it into the pill.
    mutating func visitInlineCode(_ code: InlineCode) -> NSAttributedString {
        NSAttributedString(string: code.code, attributes: [
            .font: monoFont,
            .foregroundColor: style.foreground,
            .backgroundColor: style.inlineCodeBackground,
            .paragraphStyle: bodyParagraph(),
        ])
    }

    mutating func visitLink(_ link: Markdown.Link) -> NSAttributedString {
        let inner = NSMutableAttributedString()
        for child in link.children { inner.append(visit(child)) }
        let r = NSRange(location: 0, length: inner.length)
        if let dest = link.destination, let url = URL(string: dest) {
            inner.addAttribute(.link, value: url, range: r)
        }
        inner.addAttribute(.foregroundColor, value: style.primary, range: r)
        inner.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        return inner
    }

    mutating func visitImage(_ image: Markdown.Image) -> NSAttributedString {
        // No image fetch in a transient panel — show alt text / a `[image: …]` stub.
        var alt = ""
        for child in image.children {
            if let text = child as? Markdown.Text { alt += text.plainText }
        }
        let label = alt.isEmpty ? "image" : alt
        return NSAttributedString(string: "[image: \(label)]", attributes: bodyAttrs())
    }

    mutating func visitInlineHTML(_ inline: InlineHTML) -> NSAttributedString {
        NSAttributedString(string: inline.rawHTML, attributes: bodyAttrs())   // raw passthrough
    }

    // MARK: block

    mutating func visitParagraph(_ paragraph: Paragraph) -> NSAttributedString {
        let inner = NSMutableAttributedString()
        for child in paragraph.children { inner.append(visit(child)) }
        return inner   // trailing newline added by the caller (Document / Blockquote / ListItem)
    }

    mutating func visitHeading(_ heading: Heading) -> NSAttributedString {
        let level = max(1, min(6, heading.level))
        let scaleIndex = level - 1
        let scale = scaleIndex < style.headingScales.count ? style.headingScales[scaleIndex] : 1.0
        let size = style.baseFontSize * scale
        let font = NSFont.boldSystemFont(ofSize: size)

        let inner = NSMutableAttributedString()
        for child in heading.children { inner.append(visit(child)) }

        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.bodyLineSpacing
        p.paragraphSpacingBefore = size * 0.4
        p.paragraphSpacing = size * 0.45   // ~1 line of breathing room after a heading

        let r = NSRange(location: 0, length: inner.length)
        inner.addAttributes([.font: font, .foregroundColor: style.foreground, .paragraphStyle: p], range: r)
        // h1 / h2 get a GitHub-style subtle underline; h3+ would be noisy.
        if level <= 2 {
            inner.addAttributes([
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: style.headingUnderline,
            ], range: r)
        }
        return inner
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        var code = codeBlock.code
        if code.hasSuffix("\n") { code.removeLast() }

        // Background = a 1-cell NSTextTable so a paragraph rectangle is drawn:
        //   - `.backgroundColor` would tear into per-line pills across the line gap
        //   - a bare NSTextBlock collapses to one glyph wide without a width
        // (the same mechanism the GFM table uses.)
        let table = NSTextTable()
        table.numberOfColumns = 1
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.hidesEmptyCells = false

        let block = NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1,
                                     startingColumn: 0, columnSpan: 1)
        block.backgroundColor = style.codeBlockBackground
        block.setWidth(12, type: .absoluteValueType, for: .padding)
        block.setWidth(0, type: .absoluteValueType, for: .border)
        block.setWidth(6, type: .absoluteValueType, for: .margin, edge: .minX)
        block.setWidth(6, type: .absoluteValueType, for: .margin, edge: .maxX)

        let codeP = NSMutableParagraphStyle()
        codeP.lineSpacing = 2
        codeP.lineBreakMode = .byCharWrapping   // code has no word boundaries
        codeP.textBlocks = [block]
        codeP.paragraphSpacing = style.codeBlockParagraphSpacing
        codeP.paragraphSpacingBefore = style.codeBlockParagraphSpacing

        let result = NSMutableAttributedString()

        // language label: right-aligned dim first paragraph inside the cell.
        if let lang = codeBlock.language?.trimmingCharacters(in: .whitespaces), !lang.isEmpty {
            let labelP = NSMutableParagraphStyle()
            labelP.alignment = .right
            labelP.lineSpacing = 0
            labelP.textBlocks = [block]
            let labelFont = NSFont.monospacedSystemFont(ofSize: style.baseFontSize * 0.78, weight: .regular)
            result.append(NSAttributedString(string: lang + "\n", attributes: [
                .font: labelFont,
                .foregroundColor: style.tertiary,
                .paragraphStyle: labelP,
            ]))
        }

        // Syntax highlight via sill's pluggable highlighter (bridged Color → NSColor);
        // nil ⇒ plain themed mono.
        let codeAttr: NSMutableAttributedString
        if let highlighted = highlighter?.highlight(code, language: codeBlock.language) {
            codeAttr = NSMutableAttributedString(attributedString: bridge(highlighted))
        } else {
            codeAttr = NSMutableAttributedString(string: code, attributes: [
                .font: monoFont, .foregroundColor: style.foreground])
        }
        codeAttr.append(NSAttributedString(string: "\n"))   // close the cell paragraph
        let codeRange = NSRange(location: 0, length: codeAttr.length)
        codeAttr.addAttribute(.paragraphStyle, value: codeP, range: codeRange)

        result.append(codeAttr)
        return result
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> NSAttributedString {
        NSAttributedString(string: html.rawHTML, attributes: [
            .font: monoFont, .foregroundColor: style.tertiary, .paragraphStyle: bodyParagraph()])
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> NSAttributedString {
        let inner = NSMutableAttributedString()
        let children = Array(blockQuote.children)
        for (index, child) in children.enumerated() {
            inner.append(visit(child))
            appendBlockSeparator(to: inner, after: index, of: children.count)
        }

        // GitHub-style left bar: 1-cell NSTextTable, only the left border thick+colored.
        let table = NSTextTable()
        table.numberOfColumns = 1
        table.collapsesBorders = false   // a 1-cell collapsed table can drop the border
        table.hidesEmptyCells = false

        let block = NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1,
                                     startingColumn: 0, columnSpan: 1)
        block.setWidth(0, type: .absoluteValueType, for: .border)
        block.setWidth(4, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(style.blockquoteBar, for: .minX)
        block.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(4, type: .absoluteValueType, for: .padding, edge: .maxX)
        block.setWidth(2, type: .absoluteValueType, for: .padding, edge: .minY)
        block.setWidth(2, type: .absoluteValueType, for: .padding, edge: .maxY)

        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.bodyLineSpacing
        p.textBlocks = [block]

        inner.append(NSAttributedString(string: "\n"))   // close the cell paragraph
        let r = NSRange(location: 0, length: inner.length)
        inner.addAttribute(.paragraphStyle, value: p, range: r)
        inner.addAttribute(.foregroundColor, value: style.tertiary, range: r)
        return inner
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let items = list.children.compactMap { $0 as? ListItem }
        for (index, item) in items.enumerated() {
            let prefix = listItemPrefix(item) ?? "•  "
            out.append(renderListItem(item, prefix: prefix))
            appendBlockSeparator(to: out, after: index, of: items.count)
        }
        return out
    }

    mutating func visitOrderedList(_ list: OrderedList) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let items = list.children.compactMap { $0 as? ListItem }
        let start = Int(list.startIndex)
        for (index, item) in items.enumerated() {
            out.append(renderListItem(item, prefix: "\(start + index).  "))
            appendBlockSeparator(to: out, after: index, of: items.count)
        }
        return out
    }

    private mutating func listItemPrefix(_ item: ListItem) -> String? {
        switch item.checkbox {   // GFM task list
        case .checked: return "☑  "
        case .unchecked: return "☐  "
        case .none: return nil
        }
    }

    private mutating func renderListItem(_ item: ListItem, prefix: String) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.bodyLineSpacing
        p.firstLineHeadIndent = 0
        p.headIndent = style.listIndent

        let out = NSMutableAttributedString(string: prefix, attributes: [
            .font: bodyFont, .foregroundColor: style.foreground, .paragraphStyle: p])
        let children = Array(item.children)
        for (index, child) in children.enumerated() {
            out.append(visit(child))
            appendBlockSeparator(to: out, after: index, of: children.count)
        }
        // apply headIndent across every paragraph in the item (nesting); first line
        // starts flush so the prefix isn't indented.
        let r = NSRange(location: 0, length: out.length)
        out.enumerateAttribute(.paragraphStyle, in: r) { value, range, _ in
            let ps = (value as? NSParagraphStyle).flatMap { $0.mutableCopy() as? NSMutableParagraphStyle }
                ?? bodyParagraph()
            ps.firstLineHeadIndent = range.location == 0 ? 0 : style.listIndent
            ps.headIndent = style.listIndent
            out.addAttribute(.paragraphStyle, value: ps, range: range)
        }
        return out
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.bodyLineSpacing
        p.paragraphSpacing = style.bodyLineSpacing * 2
        p.paragraphSpacingBefore = style.bodyLineSpacing * 2
        return NSAttributedString(string: String(repeating: "─", count: 40), attributes: [
            .font: bodyFont, .foregroundColor: style.tertiary, .paragraphStyle: p])
    }

    // MARK: table

    /// GFM table via NSTextTable + NSTextTableBlock — real rules, CJK-safe columns.
    mutating func visitTable(_ table: Markdown.Table) -> NSAttributedString {
        let head = Array(table.head.cells)
        let bodyRows: [[Markdown.Table.Cell]] = table.body.rows.map { Array($0.cells) }
        let columns = max(head.count, bodyRows.map { $0.count }.max() ?? 0)
        guard columns > 0 else { return NSAttributedString() }

        let textTable = NSTextTable()
        textTable.numberOfColumns = columns
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false
        // outer frame heavier than inner: collapsed borders let the thicker win.
        textTable.setBorderColor(style.tableOuterBorder)
        textTable.setWidth(1.2, type: .absoluteValueType, for: .border)

        let alignments = table.columnAlignments

        let out = NSMutableAttributedString()
        out.append(renderTableRow(head, columns: columns, rowIndex: 0, isHeader: true,
                                  table: textTable, alignments: alignments))
        for (rowOffset, row) in bodyRows.enumerated() {
            out.append(renderTableRow(row, columns: columns, rowIndex: rowOffset + 1,
                                      isHeader: false, table: textTable, alignments: alignments))
        }
        return out
    }

    /// GFM column alignment (`:--`/`:-:`/`--:`) → cell paragraph alignment; default left.
    private func cellAlignment(_ a: Markdown.Table.ColumnAlignment?) -> NSTextAlignment {
        switch a {
        case .center: return .center
        case .right: return .right
        case .left, .none: return .left
        }
    }

    private mutating func renderTableRow(_ cells: [Markdown.Table.Cell], columns: Int,
                                         rowIndex: Int, isHeader: Bool,
                                         table textTable: NSTextTable,
                                         alignments: [Markdown.Table.ColumnAlignment?]) -> NSAttributedString {
        let row = NSMutableAttributedString()
        for colIndex in 0..<columns {
            let block = makeTableCellBlock(table: textTable, row: rowIndex, column: colIndex, isHeader: isHeader)
            let p = NSMutableParagraphStyle()
            p.textBlocks = [block]
            p.lineSpacing = style.bodyLineSpacing
            p.alignment = cellAlignment(colIndex < alignments.count ? alignments[colIndex] : nil)

            let inner = NSMutableAttributedString()
            if colIndex < cells.count {
                for child in cells[colIndex].children { inner.append(visit(child)) }
            }
            if isHeader { applyTrait(.boldFontMask, to: inner) }
            inner.append(NSAttributedString(string: "\n"))   // cell paragraph terminator
            let r = NSRange(location: 0, length: inner.length)
            inner.addAttribute(.paragraphStyle, value: p, range: r)
            inner.enumerateAttribute(.font, in: r) { value, range, _ in
                if value == nil { inner.addAttribute(.font, value: bodyFont, range: range) }
            }
            row.append(inner)
        }
        return row
    }

    private func makeTableCellBlock(table: NSTextTable, row: Int, column: Int,
                                    isHeader: Bool) -> NSTextTableBlock {
        let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1,
                                     startingColumn: column, columnSpan: 1)
        block.setBorderColor(style.border)
        block.setWidth(0.5, type: .absoluteValueType, for: .border)
        block.setWidth(8, type: .absoluteValueType, for: .padding)
        if isHeader { block.backgroundColor = style.tableHeaderBackground }
        return block
    }

    // MARK: helpers

    private func applyTrait(_ trait: NSFontTraitMask, to s: NSMutableAttributedString) {
        let r = NSRange(location: 0, length: s.length)
        s.enumerateAttribute(.font, in: r) { value, range, _ in
            let original = (value as? NSFont) ?? bodyFont
            s.addAttribute(.font, value: NSFontManager.shared.convert(original, toHaveTrait: trait), range: range)
        }
    }

    /// Bridge an injected highlighter's `AttributedString` (SwiftUI `Color` runs) into
    /// an `NSAttributedString` with the mono font + per-run `NSColor`. Avoids the lossy
    /// `NSAttributedString(AttributedString)` path (which drops SwiftUI-scope colors).
    private func bridge(_ highlighted: AttributedString) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for run in highlighted.runs {
            let text = String(highlighted[run.range].characters)
            let color = run.foregroundColor.map { NSColor($0) } ?? style.foreground
            out.append(NSAttributedString(string: text, attributes: [.font: monoFont, .foregroundColor: color]))
        }
        return out
    }
}
