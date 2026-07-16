// ListCore / ListDecoration tests — the pure zebra-parity + divider-inset rules
// lifted out of `ThemedListView` (R10). Zebra: ordinal among `.row`s resets at
// each header, separators neither paint nor consume parity. Dividers: only
// after a `.row`, suppressed above a separator, full-bleed (0) above a header,
// else inset to the row's text x (base + indent).

import XCTest
import CoreGraphics
@testable import ListCore

final class ListDecorationTests: XCTestCase {

    private func row(_ id: String, indent: Int = 0) -> ListRow<String> {
        ListRow(id: id, indentLevel: indent)
    }
    private func header(_ id: String) -> ListRow<String> {
        ListRow(id: id, kind: .sectionHeader())
    }
    private func separator(_ id: String) -> ListRow<String> {
        ListRow(id: id, kind: .separator)
    }

    // MARK: - zebraParity

    func testZebraAlternatesAmongRows() {
        let parity = zebraParity(rows: [row("a"), row("b"), row("c"), row("d")])
        XCTAssertEqual(parity, ["a": false, "b": true, "c": false, "d": true])
    }

    func testZebraResetsAtEachHeader() {
        let parity = zebraParity(rows: [row("a"), row("b"),
                                        header("H"), row("c"), row("d")])
        XCTAssertEqual(parity["b"], true)
        XCTAssertEqual(parity["c"], false, "ordinal resets to 0 after a header")
        XCTAssertEqual(parity["d"], true)
        XCTAssertNil(parity["H"], "headers carry no zebra flag")
    }

    func testZebraSeparatorNeitherPaintsNorConsumes() {
        let parity = zebraParity(rows: [row("a"), separator("s"), row("b")])
        XCTAssertNil(parity["s"], "separators carry no zebra flag")
        XCTAssertEqual(parity["b"], true, "the separator does not consume an ordinal")
    }

    // MARK: - dividerInsets

    func testDividerOnlyAfterARowAndNeverOnLast() {
        let insets = dividerInsets(rows: [header("H"), row("a"), row("b")],
                                   textXBase: 44, indentStep: 16)
        XCTAssertNil(insets["H"], "no divider after a header")
        XCTAssertEqual(insets["a"], 44, "row above a row: inset to text x")
        XCTAssertNil(insets["b"], "the last row draws no divider")
    }

    func testDividerSuppressedAboveASeparator() {
        let insets = dividerInsets(rows: [row("a"), separator("s"), row("b")],
                                   textXBase: 44, indentStep: 16)
        XCTAssertNil(insets["a"], "the separator band replaces the divider")
        XCTAssertNil(insets["s"])
    }

    func testDividerFullBleedAboveAHeader() {
        let insets = dividerInsets(rows: [row("a"), header("H"), row("b")],
                                   textXBase: 44, indentStep: 16)
        XCTAssertEqual(insets["a"], 0, "full-bleed above a header")
    }

    func testDividerInsetFollowsIndent() {
        let insets = dividerInsets(rows: [row("a", indent: 2), row("b", indent: -3)],
                                   textXBase: 44, indentStep: 16)
        XCTAssertEqual(insets["a"], 44 + 2 * 16, "indent shifts the divider inset")
        XCTAssertNil(insets["b"], "last row still none (negative indent clamps, not crashes)")
    }

    func testDividerNegativeIndentClampsToBase() {
        let insets = dividerInsets(rows: [row("a", indent: -3), row("b")],
                                   textXBase: 44, indentStep: 16)
        XCTAssertEqual(insets["a"], 44, "negative indent clamps to 0")
    }
}
