import Foundation
import Markdown

public func parseMarkdown(_ source: String) -> [MarkdownBlock] {
    let document = Document(parsing: source)
    return blocks(from: document.children)
}

func blocks(from children: MarkupChildren) -> [MarkdownBlock] {
    children.compactMap(block(from:))
}

func block(from markup: Markup) -> MarkdownBlock? {
    switch markup {
    case let h as Heading:
        return .heading(level: min(max(h.level, 1), 6), content: inlineAttributed(h))
    case let p as Paragraph:
        // a paragraph that is exactly one image → image block (v1 stub)
        if p.childCount == 1, let only = p.child(at: 0) as? Markdown.Image {
            return .image(source: only.source ?? "", alt: only.plainText)
        }
        return .paragraph(inlineAttributed(p))
    case is ThematicBreak:
        return .thematicBreak
    case let html as HTMLBlock:
        return .htmlBlock(html.rawHTML)
    case let code as CodeBlock:
        return .codeBlock(language: code.language?.isEmpty == false ? code.language : nil,
                          code: code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code)
    case let quote as BlockQuote:
        return .blockquote(blocks(from: quote.children))
    case let ul as UnorderedList:
        return .list(list(from: ul, ordered: false, start: 1))
    case let ol as OrderedList:
        return .list(list(from: ol, ordered: true, start: Int(ol.startIndex)))
    case let table as Markdown.Table:
        return tableBlock(from: table)
    default:
        return nil   // unknown/unsupported nodes dropped (footnotes etc., v1)
    }
}

// MARK: - List

func list(from container: ListItemContainer, ordered: Bool, start: Int) -> MarkdownList {
    let items: [MarkdownListItem] = container.listItems.map { item -> MarkdownListItem in
        let checkbox: MarkdownListItem.Checkbox?
        switch item.checkbox {
        case .checked: checkbox = .checked
        case .unchecked: checkbox = .unchecked
        case .none: checkbox = nil
        }
        return MarkdownListItem(checkbox: checkbox, blocks: blocks(from: item.children))
    }
    return MarkdownList(ordered: ordered, start: start, items: items)
}

// MARK: - Table

func tableBlock(from table: Markdown.Table) -> MarkdownBlock {
    // Table.ColumnAlignment is [Table.ColumnAlignment?] in swift-markdown 0.8.0;
    // nil means "no specified alignment" — mapped to MarkdownTable.Alignment.none.
    let columns: [MarkdownTable.Alignment] = table.columnAlignments.map {
        switch $0 {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .none: return MarkdownTable.Alignment.none
        }
    }
    let header: [AttributedString] = table.head.cells.map { inlineAttributed($0) }
    let rows: [[AttributedString]] = table.body.rows.map { row in
        Array(row.cells.map { inlineAttributed($0) })
    }
    return .table(MarkdownTable(columns: columns, header: header, rows: rows))
}
