import XCTest
import AppKit
import Palette
import PaletteKit
@testable import MarkdownKitUI

/// Coverage for the floor-3 markdown renderer — MarkdownKitUI was the only
/// Sources module with ZERO tests. Exercises the text → `NSAttributedString`
/// block/inline mapping, exactly the regression class #17f flagged (a parser
/// that stays green while the rendered body is wrong). `@MainActor` because the
/// `Style` init resolves `NSColor`s off a `ResolvedPalette`.
@MainActor
final class MarkdownRendererTests: XCTestCase {

    private func render(_ md: String) -> NSAttributedString {
        let style = MarkdownRenderer.Style(palette: resolve(.terminal),
                                           markdown: .default)
        return MarkdownRenderer(style: style, highlighter: nil).render(md)
    }

    private func font(_ a: NSAttributedString, at i: Int) -> NSFont {
        a.attribute(.font, at: i, effectiveRange: nil) as! NSFont
    }

    // MARK: - MarkdownStyle contract the renderer leans on

    func testDefaultStyleHeadingScales() {
        XCTAssertEqual(MarkdownStyle.default.baseFontSize, 13)
        XCTAssertEqual(MarkdownStyle.default.headingScales.count, 6)
        XCTAssertEqual(MarkdownStyle.default.headingScales.first, 1.75)
        XCTAssertEqual(MarkdownStyle.default.headingScales.last, 1.0)
    }

    // MARK: - Headings (level → bold font at baseFontSize * scale)

    func testHeadingFontScalesBoldWithLevel() {
        let base = MarkdownStyle.default.baseFontSize
        let scales = MarkdownStyle.default.headingScales
        let h1 = font(render("# Title"), at: 0)
        XCTAssertEqual(h1.pointSize, base * scales[0], accuracy: 1e-6)   // 13 * 1.75
        XCTAssertTrue(h1.fontDescriptor.symbolicTraits.contains(.bold))
        let h6 = font(render("###### Small"), at: 0)
        XCTAssertEqual(h6.pointSize, base * scales[5], accuracy: 1e-6)   // 13 * 1.0
    }

    // MARK: - Inline code (the pill seam)

    func testInlineCodeSetsBackgroundPillAndMono() {
        // InlineCodePillLayoutManager rounds every `.backgroundColor` run into
        // the pill — so the renderer MUST tag inline code with `.backgroundColor`
        // (+ a mono font). Missing either is the floor-3 break.
        let a = render("run `code` now")
        let r = (a.string as NSString).range(of: "code")
        XCTAssertGreaterThan(r.length, 0)
        XCTAssertNotNil(a.attribute(.backgroundColor, at: r.location, effectiveRange: nil))
        XCTAssertTrue(font(a, at: r.location).fontDescriptor.symbolicTraits.contains(.monoSpace))
        // Surrounding body text is NOT pilled.
        XCTAssertNil(a.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    }

    // MARK: - Lists (prefix mapping)

    func testUnorderedListBulletPrefix() {
        let s = render("- alpha\n- beta").string
        XCTAssertTrue(s.contains("•  alpha"))
        XCTAssertTrue(s.contains("•  beta"))
    }

    func testOrderedListNumberPrefix() {
        let s = render("1. one\n2. two").string
        XCTAssertTrue(s.contains("1.  one"))
        XCTAssertTrue(s.contains("2.  two"))
    }

    func testTaskListCheckboxGlyphs() {
        let s = render("- [x] done\n- [ ] todo").string
        XCTAssertTrue(s.contains("☑  done"))
        XCTAssertTrue(s.contains("☐  todo"))
    }

    // MARK: - Block separator (the one block-join policy)

    func testSiblingBlocksJoinedByOneBodyAttributedNewlineWithNoTrailer() {
        let a = render("- alpha\n- beta")
        // ONE "\n" between the items and NOTHING after the last: dropping the
        // `index < count - 1` guard would trail a separator, which the panel
        // renders as a stray blank line.
        XCTAssertEqual(a.string, "•  alpha\n•  beta")

        // The separator is body-ATTRIBUTED, not a bare "\n" — the blank line has to
        // carry body metrics. A regression to `NSAttributedString(string: "\n")`
        // leaves these nil.
        let sep = (a.string as NSString).range(of: "\n").location
        XCTAssertNotNil(a.attribute(.font, at: sep, effectiveRange: nil))
        XCTAssertNotNil(a.attribute(.foregroundColor, at: sep, effectiveRange: nil))
        let ps = a.attribute(.paragraphStyle, at: sep, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(ps?.lineSpacing, MarkdownStyle.default.bodyLineSpacing)
    }

    func testBlockSeparatorIsAttributedButCellTerminatorStaysBare() {
        // Guards the classification the block-join helper is built on: the "\n"
        // BETWEEN two blockquote paragraphs is a block separator (body-attributed),
        // while the trailing "\n" is the NSTextTable CELL TERMINATOR — deliberately
        // bare, because the cell's own paragraph style is stamped over the whole
        // range afterwards. They look alike but are different operations; routing
        // the terminator through appendBlockSeparator would give it a font and
        // fail this test.
        let a = render("> alpha\n>\n> beta")
        XCTAssertEqual(a.string, "alpha\nbeta\n")
        let sep = (a.string as NSString).range(of: "\n").location
        XCTAssertNotNil(a.attribute(.font, at: sep, effectiveRange: nil),
                        "separator between blockquote paragraphs must be body-attributed")
        XCTAssertNil(a.attribute(.font, at: a.length - 1, effectiveRange: nil),
                     "cell terminator must stay bare — it is not a block separator")
    }

    // MARK: - Block separator, DOCUMENT level (`render`'s own join loop)

    // The two tests above render a SINGLE top-level block ("- a\n- b" is one
    // list, "> a\n>\n> b" is one blockquote), so they only ever exercise the
    // visitor's nested join. `render` joins the document's top-level siblings in
    // its own loop, and that one used to append a BARE "\n" — the exact
    // regression the test above warns about, one level up and untested.
    //
    // It is invisible after a paragraph, where the newline merges into the
    // preceding line. After a block that ends with its own unconditional
    // terminator (code block / blockquote / table) the separator starts a FRESH
    // line fragment and is sized by its own font, so bare vs body-attributed is
    // a real 14.0pt vs 20.0pt (system 13 + `bodyLineSpacing` 4, measured).

    func testDocumentLevelBlockSeparatorIsAttributedAfterACodeBlock() {
        let a = render("```\ncode\n```\n\nbeta")
        XCTAssertEqual(a.string, "code\n\nbeta")
        // [4] is the code CELL TERMINATOR — unconditional, deliberately bare.
        XCTAssertNil(a.attribute(.font, at: 4, effectiveRange: nil),
                     "cell terminator must stay bare — it is not a block separator")
        // [5] is the document-level BLOCK SEPARATOR — must carry body metrics.
        XCTAssertNotNil(a.attribute(.font, at: 5, effectiveRange: nil))
        XCTAssertNotNil(a.attribute(.foregroundColor, at: 5, effectiveRange: nil))
        let ps = a.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(ps?.lineSpacing, MarkdownStyle.default.bodyLineSpacing)
    }

    func testDocumentLevelSeparatorLineIsNotShorterThanABodyLine() {
        // The geometric consequence, asserted RELATIVELY so it survives a font
        // metric change: a bare separator lays out SHORTER than the body line
        // that follows it (14.0 vs 16.0), a body-attributed one taller (20.0).
        for source in ["```\ncode\n```\n\nbeta",       // code block
                       "> quoted\n\nbeta",             // blockquote
                       "| A | B |\n|---|---|\n| 1 | 2 |\n\nbeta"] {   // table
            let a = render(source)
            let sep = a.length - "\nbeta".count   // the separator before the trailer
            let heights = fragmentHeights(a)
            XCTAssertGreaterThanOrEqual(
                heights[sep], heights[a.length - 1],
                "separator line collapsed below a body line in \(source.debugDescription)")
        }
    }

    /// Lay the string out in the real TextKit 1 stack and return, per character
    /// index, the height of the line fragment it lands in.
    private func fragmentHeights(_ a: NSAttributedString) -> [CGFloat] {
        let storage = NSTextStorage(attributedString: a)
        let lm = InlineCodePillLayoutManager()
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: 400,
                                                     height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        lm.addTextContainer(container)
        lm.ensureLayout(for: container)

        var out = [CGFloat](repeating: 0, count: a.length)
        var glyph = 0
        while glyph < lm.numberOfGlyphs {
            var glyphRange = NSRange()
            let rect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &glyphRange)
            let chars = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            for i in chars.location ..< min(NSMaxRange(chars), a.length) { out[i] = rect.height }
            glyph = NSMaxRange(glyphRange)
        }
        return out
    }

    // MARK: - GFM table (floor-3 NSTextTable path)

    func testGFMTableParsesIntoCellsNotLiteralPipes() {
        // A GFM table must go through visitTable (NSTextTable cells), not fall
        // back to a literal-pipe paragraph.
        let a = render("| A | B |\n|---|---|\n| 1 | 2 |")
        XCTAssertGreaterThan(a.length, 0)
        let s = a.string
        for cell in ["A", "B", "1", "2"] { XCTAssertTrue(s.contains(cell)) }
        XCTAssertFalse(s.contains("|"), "table should lay out cells, not raw pipes")
    }
}
