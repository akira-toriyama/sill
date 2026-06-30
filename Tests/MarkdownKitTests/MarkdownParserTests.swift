// MarkdownKit — parser unit tests. These run in CI ONLY (the maintainer's machine is
// CommandLineTools-only; `import XCTest` needs full Xcode).

import XCTest
import Markdown
@testable import MarkdownKit

final class MarkdownParserTests: XCTestCase {

    // MARK: - Task 3: inline → AttributedString intents

    /// Helper: parse one paragraph and return its inline AttributedString.
    private func inlineOf(_ md: String) -> AttributedString {
        let doc = Document(parsing: md)
        let para = doc.children.compactMap { $0 as? Paragraph }.first!
        return inlineAttributed(para)
    }

    func testStrongAndEmphasisCarryIntents() {
        let attr = inlineOf("normal **bold** _italic_ ~~struck~~ `code`")
        // every run's plain string concatenates back to the source words
        let plain = String(attr.characters)
        XCTAssertEqual(plain, "normal bold italic struck code")

        func intent(forSubstring s: String) -> InlinePresentationIntent? {
            guard let r = attr.range(of: s) else { return nil }
            return attr[r].inlinePresentationIntent
        }
        XCTAssertTrue(intent(forSubstring: "bold")?.contains(.stronglyEmphasized) ?? false)
        XCTAssertTrue(intent(forSubstring: "italic")?.contains(.emphasized) ?? false)
        XCTAssertTrue(intent(forSubstring: "struck")?.contains(.strikethrough) ?? false)
        XCTAssertTrue(intent(forSubstring: "code")?.contains(.code) ?? false)
    }

    func testLinkCarriesURL() {
        let attr = inlineOf("see [docs](https://example.com)")
        let r = attr.range(of: "docs")!
        XCTAssertEqual(attr[r].link, URL(string: "https://example.com"))
    }

    // MARK: - Task 4: block parser — headings, paragraphs, hr, html, image

    func testHeadingAndParagraph() {
        let blocks = parseMarkdown("# Title\n\nbody text")
        XCTAssertEqual(blocks.count, 2)
        guard case let .heading(level, content) = blocks[0] else { return XCTFail() }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(String(content.characters), "Title")
        guard case let .paragraph(p) = blocks[1] else { return XCTFail() }
        XCTAssertEqual(String(p.characters), "body text")
    }

    func testHeadingLevelClamped() {
        // a 7-hash ATX heading is not a heading in CommonMark; ensure 1...6 only ever appear
        let blocks = parseMarkdown("###### h6")
        guard case let .heading(level, _) = blocks[0] else { return XCTFail() }
        XCTAssertEqual(level, 6)
    }

    func testThematicBreakAndHTMLBlock() {
        let blocks = parseMarkdown("---\n\n<div>raw</div>")
        XCTAssertEqual(blocks.first, .thematicBreak)
        guard case let .htmlBlock(html) = blocks[1] else { return XCTFail() }
        XCTAssertTrue(html.contains("<div>raw</div>"))
    }

    func testBlockImageStub() {
        let blocks = parseMarkdown("![alt text](pic.png)")
        // a lone image becomes a paragraph containing one image; we surface it as .image
        guard case let .image(source, alt) = blocks[0] else { return XCTFail() }
        XCTAssertEqual(source, "pic.png")
        XCTAssertEqual(alt, "alt text")
    }

    // MARK: - Task 5: code blocks

    func testFencedCodeBlockLanguageAndTrim() {
        let blocks = parseMarkdown("```swift\nlet x = 1\n```")
        guard case let .codeBlock(lang, code) = blocks[0] else { return XCTFail() }
        XCTAssertEqual(lang, "swift")
        XCTAssertEqual(code, "let x = 1")        // single trailing newline trimmed
    }

    func testCodeBlockNoLanguage() {
        let blocks = parseMarkdown("```\nplain\n```")
        guard case let .codeBlock(lang, _) = blocks[0] else { return XCTFail() }
        XCTAssertNil(lang)
    }

    // MARK: - Task 6: lists (ordered/unordered/task/nested)

    func testUnorderedAndTaskList() {
        let blocks = parseMarkdown("- a\n- [ ] todo\n- [x] done")
        guard case let .list(l) = blocks[0] else { return XCTFail() }
        XCTAssertFalse(l.ordered)
        XCTAssertEqual(l.items.count, 3)
        XCTAssertNil(l.items[0].checkbox)
        XCTAssertEqual(l.items[1].checkbox, .unchecked)
        XCTAssertEqual(l.items[2].checkbox, .checked)
        // first item text
        guard case let .paragraph(p) = l.items[0].blocks[0] else { return XCTFail() }
        XCTAssertEqual(String(p.characters), "a")
    }

    func testOrderedListStart() {
        let blocks = parseMarkdown("3. three\n4. four")
        guard case let .list(l) = blocks[0] else { return XCTFail() }
        XCTAssertTrue(l.ordered)
        XCTAssertEqual(l.start, 3)
    }

    func testNestedList() {
        let blocks = parseMarkdown("- outer\n    - inner")
        guard case let .list(l) = blocks[0] else { return XCTFail() }
        // outer item carries a nested list block
        let nested = l.items[0].blocks.compactMap { b -> MarkdownList? in
            if case let .list(x) = b { return x }; return nil
        }
        XCTAssertEqual(nested.first?.items.count, 1)
    }

    // MARK: - Task 7: blockquote + GFM table

    func testBlockquoteNested() {
        let blocks = parseMarkdown("> quoted\n>\n> > deep")
        guard case let .blockquote(inner) = blocks[0] else { return XCTFail() }
        guard case let .paragraph(p) = inner[0] else { return XCTFail() }
        XCTAssertEqual(String(p.characters), "quoted")
        XCTAssertTrue(inner.contains { if case .blockquote = $0 { return true }; return false })
    }

    func testGFMTable() {
        let md = """
        | A | B |
        |:--|--:|
        | 1 | 2 |
        """
        let blocks = parseMarkdown(md)
        guard case let .table(t) = blocks[0] else { return XCTFail() }
        XCTAssertEqual(t.columns, [.left, .right])
        XCTAssertEqual(t.header.map { String($0.characters) }, ["A", "B"])
        XCTAssertEqual(t.rows.count, 1)
        XCTAssertEqual(t.rows[0].map { String($0.characters) }, ["1", "2"])
    }
}
