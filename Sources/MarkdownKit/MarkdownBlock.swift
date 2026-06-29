import Foundation

public enum MarkdownBlock: Sendable, Equatable {
    case heading(level: Int, content: AttributedString)   // level clamped 1...6
    case paragraph(AttributedString)
    case codeBlock(language: String?, code: String)
    case blockquote([MarkdownBlock])
    case list(MarkdownList)
    case table(MarkdownTable)
    case thematicBreak
    case htmlBlock(String)
    case image(source: String, alt: String)
}

public struct MarkdownList: Sendable, Equatable {
    public var ordered: Bool
    public var start: Int
    public var items: [MarkdownListItem]
    public init(ordered: Bool, start: Int = 1, items: [MarkdownListItem]) {
        self.ordered = ordered; self.start = start; self.items = items
    }
}

public struct MarkdownListItem: Sendable, Equatable {
    public enum Checkbox: Sendable, Equatable { case checked, unchecked }
    public var checkbox: Checkbox?
    public var blocks: [MarkdownBlock]
    public init(checkbox: Checkbox? = nil, blocks: [MarkdownBlock]) {
        self.checkbox = checkbox; self.blocks = blocks
    }
}

public struct MarkdownTable: Sendable, Equatable {
    public enum Alignment: Sendable, Equatable { case left, center, right, none }
    public var columns: [Alignment]
    public var header: [AttributedString]
    public var rows: [[AttributedString]]
    public init(columns: [Alignment], header: [AttributedString], rows: [[AttributedString]]) {
        self.columns = columns; self.header = header; self.rows = rows
    }
}
