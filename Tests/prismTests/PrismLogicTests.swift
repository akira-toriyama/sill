import XCTest
@testable import prism

final class PrismConfigTests: XCTestCase {
    private func loadTOML(_ body: String) -> PrismConfig {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prism-\(UUID().uuidString).toml")
        try! body.write(to: url, atomically: true, encoding: .utf8)
        setenv("PRISM_CONFIG", url.path, 1)
        defer { unsetenv("PRISM_CONFIG"); try? FileManager.default.removeItem(at: url) }
        return PrismConfig.load()
    }
    func testDefaultThemeIsSingleNotAll() {
        let c = loadTOML("")
        XCTAssertEqual(c.theme, "dracula")
        XCTAssertEqual(c.section, "overview")
        XCTAssertFalse(c.showAll)
        XCTAssertEqual(c.widget, "")
    }
    func testDeepLinkKeysParse() {
        let c = loadTOML("widget = \"ThemedList\"\ntheme = \"nord\"\nsection = \"Specimens\"\nshow-all = true")
        XCTAssertEqual(c.widget, "ThemedList")
        XCTAssertEqual(c.theme, "nord")
        XCTAssertEqual(c.section, "specimens")
        XCTAssertTrue(c.showAll)
    }
    func testExplicitAllHonored() { XCTAssertEqual(loadTOML("theme = \"all\"").theme, "all") }
}

final class CopyRefTests: XCTestCase {
    func testThemedListViewCoreIsCompilableShape() {
        let ref = kitComponent("ThemedListView").pasteReadyCore
        XCTAssertTrue(ref.contains("TYPE TO USE (SwiftUI): ThemedListView"))
        XCTAssertTrue(ref.contains("import ThemeKitUI"))
        XCTAssertTrue(ref.contains("ThemedListView("))
        XCTAssertTrue(ref.contains("onActivate: { id in open(id) }"))
        XCTAssertTrue(ref.contains("SOURCE: ThemeKitUI/ThemedListView.swift"))
        XCTAssertFalse(ref.contains("list.items ="))   // not the old non-existent builder shape
        XCTAssertFalse(ref.contains("{ list in"))
    }
}
