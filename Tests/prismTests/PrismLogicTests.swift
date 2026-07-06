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
        let c = loadTOML("widget = \"ThemedListView\"\ntheme = \"nord\"\nsection = \"Specimens\"\nshow-all = true")
        XCTAssertEqual(c.widget, "ThemedListView")
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
    func testEveryRecipeFilled() {
        for c in kitCatalog where c.name != "MarkdownView" {
            XCTAssertFalse(c.imports.isEmpty, "\(c.name) missing imports")
            XCTAssertFalse(c.initSnippet.isEmpty, "\(c.name) missing initSnippet")
            if !c.isAtom {
                XCTAssertFalse(c.defaultType.isEmpty, "\(c.name) (widget) missing SwiftUI defaultType")
            }
        }
        // Pin the atom set itself — a widget mistakenly flagged isAtom: true would
        // silently skip the defaultType check above.
        XCTAssertEqual(Set(kitCatalog.filter { $0.isAtom }.map { $0.name }),
                       ["WindowShell", "ThemedTransition", "TrailGeometry"])
    }
}

final class SidebarRegistryTests: XCTestCase {
    private var widgetRows: Set<String> {
        Set(sidebarSections.flatMap { $0.items }.compactMap { if case .widget(let n) = $0 { return n }; return nil })
    }
    func testEveryCataloguedStandaloneWidgetHasARow() {
        for c in kitCatalog where c.name != "MarkdownView" {
            XCTAssertTrue(widgetRows.contains(c.name), "\(c.name) cataloged but no sidebar row")
        }
    }
    func testRenderMapExactlyMatchesWidgetRows() {
        // Drift guard: a widget row with no render case, or a render case with no row.
        XCTAssertEqual(Set(wiredMockNames), widgetRows, "wiredMockNames must equal the .widget sidebar rows")
    }
    func testEveryWiredMockNameIsRendered() {
        // Links wiredMockNames to the ACTUAL render switch (mock(for:) in
        // Gallery.swift, probed here via its mockHandles twin) — combined with
        // testRenderMapExactlyMatchesWidgetRows above, this pins catalog rows →
        // wiredMockNames → the render switch, closing the gap the #17f blank-page
        // failure mode exploited (a name could be in wiredMockNames/widgetRows
        // without a real mock(for:) case, silently falling to `default: EmptyView()`).
        for n in wiredMockNames { XCTAssertTrue(mockHandles(n), "\(n) is in wiredMockNames but mock(for:) has no case → blank page") }
        XCTAssertFalse(mockHandles("NoSuchWidget"))
    }
    func testThemedGridCatalogued() { XCTAssertFalse(kitComponent("ThemedGrid").kind.isEmpty) }
    func testLookups() {
        XCTAssertEqual(sidebarItem(forWidget: "themedlistview"), .widget("ThemedListView"))
        XCTAssertNil(sidebarItem(forWidget: "nope"))
        XCTAssertEqual(sidebarItem(forFamily: "facet"), .app(.facet))
        XCTAssertEqual(sidebarItem(forFamily: "palette"), .foundation(.palette))
    }
}
