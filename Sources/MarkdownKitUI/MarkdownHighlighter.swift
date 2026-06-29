import Foundation

/// Inject to color code blocks; return nil to fall back to plain themed monospaced.
public protocol MarkdownHighlighter: Sendable {
    func highlight(_ code: String, language: String?) -> AttributedString?
}
