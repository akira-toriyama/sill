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
