# prism shell single-widget-focus — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign prism's shell into a Storybook/MUI searchable-sidebar split-view so one widget fills one screen and any widget/cell is reached fastest — widget rendering unchanged.

**Architecture:** Replace prism's header (theme-chip wall + Kit/Apps tab rows) + per-theme card stack with a `NavigationSplitView`: an in-content top bar (theme `Picker` + `EffectToggle` + sidebar toggle), a `.searchable(.sidebar)` `List` driven by an explicit `SidebarItem` registry, and a detail column rendering one widget page (Overview | Specimens | API + copy ref) or a bespoke foundation/app page. Deep-link config (`widget`/`family`/`theme`/`section`/`showAll`) makes captures deterministic without activating the window.

**Tech Stack:** Swift 6.3 / macOS 26 floor, SwiftUI (shell) hosted in an AppKit `NSWindow` via `NSHostingController`, SwiftPM. Design spec: [docs/superpowers/specs/2026-07-03-prism-shell-single-widget-focus-design.md](../specs/2026-07-03-prism-shell-single-widget-focus-design.md).

## Global Constraints

- **Widget rendering is frozen.** Every previewed widget (`ThemedListView`, `ThemedButton`, …) draws pixel-for-pixel as today. Only prism's shell + specimen *arrangement* changes (per-cell rendering stays identical; a mock's aggregate column/row layout is preserved where decomposed).
- **Shell is pure SwiftUI.** No new AppKit widget/chrome in the shell. The only `Prism.swift` AppKit changes allowed: `NSHostingController`, `window.contentMinSize`, opening-height clamp. Do **NOT** attach an `NSToolbar`, set `sceneBridgingOptions`, or drop an AppKit `ThemedTextField` into the shell search (CLAUDE.md「AppKit 使用可ポリシー」— widening AppKit scope is 要相談).
- **Commits:** gitmoji + Conventional Commits (commit-lint enforced), e.g. `:sparkles: feat(prism): …`. prism is not a library ⇒ **no version bump / tag**.
- **Build gates:** `swift build` (CLT quick compile bar) AND `scripts/test.sh` (full XCTest via installed Xcode) before every commit. UI render is proven **live in prism**, not by tests.
- **uiScale = 1.5** ([Gallery.swift:18](../../../Sources/prism/Gallery.swift#L18)) is global; do not touch it.
- **No feature bloat** — findability + readability only. Live prop-editing inspector and `state=` deep-link are icebox.

## Testing approach (read before Task 1)

prism is an `.executableTarget` with **no test target today**. Task 2 adds a `prismTests` target (`@testable import prism`) for the **pure-logic** pieces only (config parse, copy-ref serialization, `SidebarItem` registry ↔ render-map completeness). `@testable import` of an `@main` executable builds on the pinned Swift 6.3 toolchain; if a future toolchain rejects it, the fallback is a `Prism.selfTest() -> [String]` (returns failure messages) called from `main()` under `PRISM_SELFTEST=1` and asserted by a shell step in `scripts/test.sh` — but do NOT pre-build that unless `@testable import` fails. **UI tasks are verified by `swift build` + a live prism launch** using a concrete `PRISM_CONFIG`, following the prism-bench recipe (launch `.build/debug/prism` with `PRISM_CONFIG=…`, resolve the window id by matching "prism", `screencapture -l<winid> -o out.png` **without** osascript-activating).

**Section model note (deviation from the spec's illustrative labels):** the spec §4.2 sketches a 4-label rhythm (Overview | Variants | States | API). The mocks mix "variant" and "state" cells in one specimen grid with no reliable split, so this plan implements **3 meaningful sections — Overview | Specimens | API** (Variants+States collapse into one full-specimen grid). Overview = compact representative cells; Specimens = the full cell grid; API = the paste-ref's full-API text. Faithful to the spec's intent (compact default + one-click to everything); per-mock variant/state splitting is a later refinement.

---

## File Structure

- **Create** `Sources/prism/SidebarModel.swift` — `SidebarItem`, `PrismFoundation`, `sidebarSections` registry, `sidebarLabel`/`sidebarSearchText`/`sidebarItem(forWidget:)`/`sidebarItem(forFamily:)`, `wiredMockNames`.
- **Create** `Sources/prism/WidgetPage.swift` — `WidgetPage` view + `PageSection` enum.
- **Create** `Sources/prism/FoundationAppPage.swift` — `FoundationAppPage` view.
- **Create** `Tests/prismTests/PrismLogicTests.swift` — XCTest.
- **Modify** `Sources/prism/Prism.swift` — `NSHostingController`; `PrismConfig` + `widget`/`section`/`showAll` (keep `family`); `theme` default → `"dracula"`; display-safe `contentMinSize` + opening-height clamp (preserving `PRISM_WINDOW_H`).
- **Modify** `prism.toml` — `theme` default off `"all"`.
- **Modify** `Sources/prism/KitCatalog.swift` — structured `KitComponent` fields (defaulted) + `pasteReadyCore`/`fullAPI`; add `ThemedGrid` entry; per-widget recipe content.
- **Modify** `Sources/prism/Gallery.swift` — replace header + `ThemeCard` stack with the split-view; **extract** `paletteFoundations`/`appCaption` to file-level; add `mock(for:)`; **keep** `ThemeChip`/`FlowLayout` (reused in the Palette page).
- **Modify** `Sources/prism/ListShowcase.swift` (`MockList`) — expose addressable cells (Task 8). Additional tall mocks → Task 11.
- **Modify** `Package.swift` — add `prismTests`.

## Interface contract (defined once; other tasks depend on these exact names)

```swift
// SidebarModel.swift — 'PrismFoundation' (NOT 'Foundation' — that shadows the Foundation module)
enum PrismFoundation: String, CaseIterable, Hashable { case palette = "Palette", icons = "Icons" }

enum SidebarItem: Identifiable, Hashable {
    case foundation(PrismFoundation)   // Palette swatches / Icons
    case widget(String)                // a KitComponent.name
    case app(KitFamily)                // .facet/.wand/.perch/.halo/.glance
    var id: String {
        switch self {
        case .foundation(let f): return "foundation:\(f.rawValue)"
        case .widget(let n):     return "widget:\(n)"
        case .app(let a):        return "app:\(a.rawValue)"
        }
    }
}
struct SidebarSection: Identifiable { let title: String; let items: [SidebarItem]; var id: String { title } }
let sidebarSections: [SidebarSection]
func sidebarLabel(_ item: SidebarItem) -> String
func sidebarSearchText(_ item: SidebarItem) -> String            // name+module+kind(+family), lowercased
func sidebarItem(forWidget name: String) -> SidebarItem?         // case-insensitive
func sidebarItem(forFamily raw: String) -> SidebarItem?          // "palette"/"icons"/"facet"/… → foundation/app
let wiredMockNames: [String]                                     // hand-maintained: widget names mock(for:) renders

// WidgetPage.swift
enum PageSection: String, CaseIterable, Identifiable { case overview = "Overview", specimens = "Specimens", api = "API"; var id: String { rawValue } }
struct WidgetPage: View { /* init(component:themeName:showEffects:section:showAll:mock:cells:) */ }

// Gallery.swift — file-level (extracted from ThemeCard so pages can reuse)
func paletteFoundations(spec: ThemeSpec, p: ResolvedPalette, name: String, scale: CGFloat, showEffects: Bool) -> AnyView
func appCaption(_ tab: KitFamily, p: ResolvedPalette) -> AnyView
@ViewBuilder func mock(for name: String, p: ResolvedPalette, themeName: String, showEffects: Bool) -> some View

// Prism.swift — PrismConfig additions (keep existing theme/font-scale/show-effects/family)
var widget: String     // "" = none; a KitComponent.name (case-insensitive)
var section: String    // "overview"|"specimens"|"api"; default "overview"
var showAll: Bool      // default false → forces initial section = .specimens when true
// theme default becomes "dracula" (an explicit theme="all" is still honored)

// KitCatalog.swift — KitComponent additions (defaulted → existing 23 call sites compile unchanged)
let defaultType: String    // SwiftUI type for real widgets; "" for pure/effects atoms
let imports: [String]
let initSnippet: String
let cellType: String
let cellInit: String
let sourcePath: String
let appkitEscape: String
let isAtom: Bool           // true for pure/free-function specimens (no SwiftUI type) — default false
var pasteReadyCore: String // labeled paste block ("copy ref" emits this)
var fullAPI: String        // former keyAPI/variants dump, under ADVANCED
```

---

## Task 1: Host + reachability + config keys (Prism.swift)

Low-risk win; prism still shows today's UI after this task.

**Files:** Modify `Sources/prism/Prism.swift` (bootstrap ~L21-38; `PrismConfig` L51-87; parse switch L71-77); Modify `prism.toml`.

**Interfaces produced:** `PrismConfig.widget`/`.section`/`.showAll`; `theme` default `"dracula"` (keeps existing `family`); `NSHostingController` host; display-safe sizing.

- [ ] **Step 1: Host + display-safe sizing.** In `main()`, host via a controller and add sizing (the window is built ~L26-38 with `winH` at L31):
```swift
let controller = NSHostingController(rootView: Gallery(config: config))
window.contentViewController = controller

let visibleH = NSScreen.main?.visibleFrame.height ?? 900
window.contentMinSize = NSSize(width: 920 * uiScale, height: min(600 * uiScale, visibleH - 40))
```

- [ ] **Step 2: Clamp the opening height WITHOUT dropping `PRISM_WINDOW_H`.** The height is `let winH = env["PRISM_WINDOW_H"].flatMap{Double($0)}.map{CGFloat($0)} ?? 820 * uiScale` (L31). Clamp the *default* only:
```swift
let winH = ProcessInfo.processInfo.environment["PRISM_WINDOW_H"].flatMap { Double($0) }.map { CGFloat($0) }
    ?? min(820 * uiScale, NSScreen.main?.visibleFrame.height ?? 820 * uiScale)
```
(The explicit env override is still honored; only the default is display-clamped.)

- [ ] **Step 3: Add the deep-link fields.** In `struct PrismConfig` add `var widget = ""`, `var section = "overview"`, `var showAll = false`; change `var theme: String = "dracula"`. (Keep the existing `family`.)

- [ ] **Step 4: Parse the new keys.** In the `switch key` block add:
```swift
case "widget":   if !val.isEmpty { c.widget = val }
case "section":  if !val.isEmpty { c.section = val.lowercased() }
case "show-all": c.showAll = (val.lowercased() == "true")
```

- [ ] **Step 5: Update `prism.toml`.** Change `theme = "all"` → `theme = "dracula"`.

- [ ] **Step 6: Build.** `swift build` — Expected: clean.

- [ ] **Step 7: Live-verify reachability.** Launch prism (no `PRISM_CONFIG`): opens on a single theme (dracula) at a height that fits the display; resizing short does not strand the bottom. (Old shell still shown — expected.)

- [ ] **Step 8: Commit.**
```bash
git add Sources/prism/Prism.swift prism.toml
git commit -m ":wrench: refactor(prism): NSHostingController host, display-safe sizing, deep-link config keys"
```

---

## Task 2: prismTests target + PrismConfig parse tests

**Files:** Modify `Package.swift`; Create `Tests/prismTests/PrismLogicTests.swift`.
**Interfaces:** Consumes `PrismConfig` (Task 1); Produces the `prismTests` target.

- [ ] **Step 1: Add the target.** In `Package.swift`, after the other `.testTarget`s: `.testTarget(name: "prismTests", dependencies: ["prism"]),`

- [ ] **Step 2: Write the tests.** Create `Tests/prismTests/PrismLogicTests.swift`:
```swift
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
```

- [ ] **Step 3: Run.** `scripts/test.sh --filter PrismConfigTests` — Expected: PASS (3). If it fails to BUILD on `@testable import prism`, apply the Testing-approach fallback and note it; otherwise proceed.

- [ ] **Step 4: Commit.**
```bash
git add Package.swift Tests/prismTests/PrismLogicTests.swift
git commit -m ":white_check_mark: test(prism): prismTests target + config deep-link parse tests"
```

---

## Task 3: KitComponent structured fields + paste-ready serializer (+ ThemedList recipe)

**Files:** Modify `Sources/prism/KitCatalog.swift` (`struct KitComponent` L39-51; `referenceText`; `ThemedList` entry ~L395); Modify `Sources/prism/Gallery.swift` (`CopyRefButton` L456-482); Modify `Tests/prismTests/PrismLogicTests.swift`.
**Interfaces:** Produces `KitComponent.pasteReadyCore`/`.fullAPI` + the new fields.

- [ ] **Step 1: Add fields (defaulted so all 23 existing sites compile unchanged).** After the existing `let`s in `struct KitComponent`:
```swift
let defaultType: String = ""
let imports: [String] = []
let initSnippet: String = ""
let cellType: String = ""
let cellInit: String = ""
let sourcePath: String = ""
let appkitEscape: String = ""
let isAtom: Bool = false
```

- [ ] **Step 2: Serializers.** Replace `referenceText` with:
```swift
var pasteReadyCore: String {
    var s = "\(name) — \(kind) (sill · \(module) widget)\n"
    if !defaultType.isEmpty { s += "TYPE TO USE (SwiftUI): \(defaultType)\n" }
    if !imports.isEmpty { s += "IMPORTS:\n" + imports.map { "  \($0)" }.joined(separator: "\n") + "\n" }
    if !initSnippet.isEmpty { s += (isAtom ? "USE:\n" : "MINIMAL:\n") + initSnippet + "\n" }
    if !cellInit.isEmpty { s += "CELL: \(cellInit)\n" }
    if !appkitEscape.isEmpty { s += "ESCAPE HATCH (AppKit only): \(appkitEscape)\n" }
    if !sourcePath.isEmpty { s += "SOURCE: \(sourcePath)  ·  ADVANCED (opt-in) → full API." }
    return s
}
var referenceText: String { pasteReadyCore }   // back-compat alias
var fullAPI: String {
    var s = "\(name) · \(module) (sill)\n\(kind)\n\n\(summary)\n\nKEY API:\n"
    s += keyAPI.map { "  • \($0)" }.joined(separator: "\n")
    s += "\n\nVARIANTS:\n" + variants.map { "  • \($0)" }.joined(separator: "\n")
    return s
}
```

- [ ] **Step 3: ThemedList recipe (worked example, verified vs [ThemedListView.swift:55-77](../../../Sources/ThemeKitUI/ThemedListView.swift#L55) / [ListStyle.swift:19-39](../../../Sources/ThemeKitUI/ListStyle.swift#L19) / [ListItem.swift:13-39](../../../Sources/ThemeKitUI/ListItem.swift#L13)).** Add to the `ThemedList` entry:
```swift
defaultType: "ThemedListView<ID>",
imports: [
    "import ThemeKitUI   // ThemedListView, ListItem",
    "import ThemeKit     // Badge, TrailingAccessory (list accessory types)",
    "import PaletteKit   // ResolvedPalette + resolve(_:)",
],
initSnippet: """
  let palette = resolve(themeSpec)              // @MainActor; themeSpec: ThemeSpec
  var style = ThemedListStyle()                 // selectionMode defaults to .single
  ThemedListView(
      items: [ ListItem(id: "inbox",   primary: "Inbox"),
               ListItem(id: "starred", primary: "Starred", secondary: "3 unread") ],
      style: style,
      palette: palette,
      onActivate: { id in open(id) })           // id IS the ListItem.id
""",
cellType: "ListItem",
cellInit: "ListItem(id:primary:) — only id + primary required (image/secondary/badges/trailing/tint/kind default).",
sourcePath: "ThemeKitUI/ThemedListView.swift",
appkitEscape: "ThemedList(palette:) → addSubview (plain NSView), only if NOT in SwiftUI.",
```

- [ ] **Step 4: Point copy-ref at the core.** In `CopyRefButton`, write `component.pasteReadyCore` (was `component.referenceText`).

- [ ] **Step 5: Tests.** Add:
```swift
final class CopyRefTests: XCTestCase {
    func testThemedListCoreIsCompilableShape() {
        let ref = kitComponent("ThemedList").pasteReadyCore
        XCTAssertTrue(ref.contains("TYPE TO USE (SwiftUI): ThemedListView"))
        XCTAssertTrue(ref.contains("import ThemeKitUI"))
        XCTAssertTrue(ref.contains("ThemedListView("))
        XCTAssertTrue(ref.contains("onActivate: { id in open(id) }"))
        XCTAssertTrue(ref.contains("SOURCE: ThemeKitUI/ThemedListView.swift"))
        XCTAssertFalse(ref.contains("list.items ="))   // not the old non-existent builder shape
        XCTAssertFalse(ref.contains("{ list in"))
    }
}
```

- [ ] **Step 6: Build + test.** `swift build` then `scripts/test.sh --filter CopyRefTests` — Expected: PASS.

- [ ] **Step 7: Commit.**
```bash
git add Sources/prism/KitCatalog.swift Sources/prism/Gallery.swift Tests/prismTests/PrismLogicTests.swift
git commit -m ":sparkles: feat(prism): agent-optimized paste-ready copy-ref (fields + serializer)"
```

---

## Task 4: SidebarItem registry + render-map completeness test

**Files:** Create `Sources/prism/SidebarModel.swift`; Modify `Sources/prism/KitCatalog.swift` (add `ThemedGrid`); Modify `Tests/prismTests/PrismLogicTests.swift`.
**Interfaces:** Consumes `KitFamily`, `kitCatalog`, `kitComponent()`; Produces the registry + helpers + `wiredMockNames` (contract above).

- [ ] **Step 1: Add `ThemedGrid` catalog entry + decide `MarkdownView`.** Add a real `KitComponent(name: "ThemedGrid", module: "ThemeKitUI", kind: …, family: .collection, …)` (verify the SwiftUI type/module at source). `MarkdownView` stays cataloged but is **excluded** from standalone widget rows (renders only inside the glance app page).

- [ ] **Step 2: Write the registry.** Create `Sources/prism/SidebarModel.swift`:
```swift
import Foundation

enum PrismFoundation: String, CaseIterable, Hashable { case palette = "Palette", icons = "Icons" }

enum SidebarItem: Identifiable, Hashable {
    case foundation(PrismFoundation), widget(String), app(KitFamily)
    var id: String {
        switch self {
        case .foundation(let f): return "foundation:\(f.rawValue)"
        case .widget(let n):     return "widget:\(n)"
        case .app(let a):        return "app:\(a.rawValue)"
        }
    }
}
struct SidebarSection: Identifiable { let title: String; let items: [SidebarItem]; var id: String { title } }

private let excludedStandalone: Set<String> = ["MarkdownView"]

let sidebarSections: [SidebarSection] = {
    var out: [SidebarSection] = [
        SidebarSection(title: "Foundations", items: PrismFoundation.allCases.map { .foundation($0) })
    ]
    for fam in KitFamily.kitCases where fam != .palette && fam != .icon {
        let widgets = kitCatalog.filter { $0.family == fam && !excludedStandalone.contains($0.name) }
                                .map { SidebarItem.widget($0.name) }
        if !widgets.isEmpty { out.append(SidebarSection(title: fam.rawValue, items: widgets)) }
    }
    out.append(SidebarSection(title: "Apps", items: KitFamily.appCases.map { .app($0) }))
    return out
}()

func sidebarLabel(_ item: SidebarItem) -> String {
    switch item { case .foundation(let f): return f.rawValue; case .widget(let n): return n; case .app(let a): return a.rawValue }
}
func sidebarSearchText(_ item: SidebarItem) -> String {
    switch item {
    case .foundation(let f): return f.rawValue.lowercased()
    case .widget(let n): let c = kitComponent(n); return "\(c.name) \(c.module) \(c.kind) \(c.family.rawValue)".lowercased()
    case .app(let a): return "\(a.rawValue) app".lowercased()
    }
}
func sidebarItem(forWidget name: String) -> SidebarItem? {
    let lower = name.lowercased()
    for s in sidebarSections { for case let .widget(n) in s.items where n.lowercased() == lower { return .widget(n) } }
    return nil
}
func sidebarItem(forFamily raw: String) -> SidebarItem? {
    let lower = raw.lowercased()
    if let f = PrismFoundation.allCases.first(where: { $0.rawValue.lowercased() == lower }) { return .foundation(f) }
    if let a = KitFamily.appCases.first(where: { $0.rawValue.lowercased() == lower }) { return .app(a) }
    return nil
}

/// Hand-maintained: the widget names Gallery.mock(for:) actually renders. Kept in
/// sync with the mock(for:) switch (Task 6 Step 1) — the completeness test asserts
/// this set exactly equals the .widget sidebar rows, catching drift in either direction.
let wiredMockNames: [String] = [
    "ThemedTextField", "ThemedComboBox",
    "ThemedButton", "ThemedButtonGroup", "ThemedToolBar", "ThemedChip", "ThemedPill", "ThemedCheckbox", "ThemedFAB",
    "ThemedDivider", "AnimatedBorderView", "ThemedSkeleton", "ThemedTooltip", "ThemedBackdrop", "WindowShell",
    "ThemedList", "ThemedMenu", "ThemedGrid",
    "ThemedTransition",
    "ParticleBurst", "SplatterShape", "TrailGeometry", "PixelSprite",
]
```
(Adjust the `wiredMockNames` list to the exact standalone widget rows once ThemedGrid is added — the test in Step 3 forces it to match.)

- [ ] **Step 3: Completeness test (non-circular — asserts the render map matches the registry).** Add:
```swift
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
    func testThemedGridCatalogued() { XCTAssertFalse(kitComponent("ThemedGrid").kind.isEmpty) }
    func testLookups() {
        XCTAssertEqual(sidebarItem(forWidget: "themedlist"), .widget("ThemedList"))
        XCTAssertNil(sidebarItem(forWidget: "nope"))
        XCTAssertEqual(sidebarItem(forFamily: "facet"), .app(.facet))
        XCTAssertEqual(sidebarItem(forFamily: "palette"), .foundation(.palette))
    }
}
```

- [ ] **Step 4: Build + test.** `swift build` then `scripts/test.sh --filter SidebarRegistryTests` — Expected: PASS (fix `wiredMockNames`/catalog until `testRenderMapExactlyMatchesWidgetRows` is green — this locks the render map).

- [ ] **Step 5: Commit.**
```bash
git add Sources/prism/SidebarModel.swift Sources/prism/KitCatalog.swift Tests/prismTests/PrismLogicTests.swift
git commit -m ":sparkles: feat(prism): SidebarItem registry (single source) + ThemedGrid entry"
```

---

## Task 5: Split-view shell — top bar + searchable sidebar + focus routing

Detail routes to placeholder text per item type (real pages in Tasks 6-7). Proves the split-view + in-content chrome render in the `NSHostingController` host, and that keyboard nav works.

**Files:** Modify `Sources/prism/Gallery.swift` (`Gallery` state + `body` L39-88; `init` L52-65; remove `header`/`tabGroup` L92-146; **keep** `ThemeChip`/`FlowLayout`/`EffectToggle`).
**Interfaces:** Consumes the registry helpers (Task 4), `PrismConfig` (Task 1), `EffectToggle`; Produces `@State selection: SidebarItem?`, `selectedTheme`, `searchText`, `columnVisibility`, `@FocusState focus`.

- [ ] **Step 1: Replace `Gallery`'s state block.** Remove `selected`, `selectedFamily` and their init seeds and the `shown` computed property (L34/39/42/54-64/68). **Keep** the existing `showEffects` (L50/57) — do not re-declare it. Add:
```swift
@State private var selection: SidebarItem?          // optional — List(selection:) needs Binding<Value?>
@State private var selectedTheme: String
@State private var searchText = ""
@State private var columnVisibility: NavigationSplitViewVisibility = .all
@FocusState private var searchFocused: Bool
```

- [ ] **Step 2: Seed in `init` (widget → family → default).**
```swift
_selectedTheme = State(initialValue:
    (config.theme == "all" || Gallery.switchable.contains(config.theme)) ? config.theme : "all")
_showEffects = State(initialValue: config.showEffects)        // keep existing seed
_selection = State(initialValue:
    sidebarItem(forWidget: config.widget)
    ?? sidebarItem(forFamily: config.family)
    ?? .widget(Gallery.firstWidgetName))
```
Add `static let firstWidgetName: String = sidebarSections.first { $0.title != "Foundations" && $0.title != "Apps" }?.items.compactMap { if case .widget(let n) = $0 { return n }; return nil }.first ?? "ThemedButton"`. (`switchable` and `firstWidgetName` stay `private` — all consumers are in Gallery.swift.)

- [ ] **Step 3: Body = split-view.**
```swift
var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
        sidebar
    } detail: {
        VStack(spacing: 0) { topBar; Divider(); detailPage }
    }
    .frame(minWidth: 920 * uiScale, minHeight: 480 * uiScale)
}
```

- [ ] **Step 4: In-content top bar (renders in the bare-NSHostingView host — NOT window `.toolbar`).** Use a vendored slug for the toggle — verify it exists in `Sources/ThemeKit/Resources/Phosphor/`; if `sidebar-simple` is absent, vendor it per [Resources/README.md](../../../Sources/ThemeKit/Resources/README.md) as its own step, or use an already-vendored slug (`list`):
```swift
private var topBar: some View {
    HStack(spacing: 12) {
        Button { withAnimation { columnVisibility = columnVisibility == .all ? .detailOnly : .all } }
            label: { phosphorIcon("list", 13) }.buttonStyle(.plain).help("Toggle the sidebar")
        Picker("Theme", selection: $selectedTheme) {
            Text("All").tag("all")
            ForEach(Gallery.switchable, id: \.self) { Text($0).tag($0) }
        }.labelsHidden().frame(maxWidth: 220 * uiScale)
        Spacer()
        EffectToggle(on: showEffects) { showEffects.toggle() }
    }.padding(.horizontal, 14).padding(.vertical, 8)
}
```

- [ ] **Step 5: Searchable sidebar with focus routing.** `.searchable` can steal initial focus; keep search focus separate so ↑/↓ drives the List:
```swift
private var sidebar: some View {
    List(selection: $selection) {
        ForEach(filteredSections) { section in
            Section(section.title) {
                ForEach(section.items) { item in Text(sidebarLabel(item)).tag(item) }
            }
        }
    }
    .searchable(text: $searchText, placement: .sidebar, prompt: "Search widgets")
    .searchFocused($searchFocused)
    .frame(minWidth: 190 * uiScale)
}
private var filteredSections: [SidebarSection] {
    let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return sidebarSections }
    return sidebarSections.compactMap { s in
        let items = s.items.filter { sidebarSearchText($0).contains(q) }
        return items.isEmpty ? nil : SidebarSection(title: s.title, items: items)
    }
}
```

- [ ] **Step 6: Placeholder detail routing (unwrap the optional).**
```swift
@ViewBuilder private var detailPage: some View {
    if let selection {
        switch selection {
        case .widget(let n):     Text("widget → \(n) @ \(selectedTheme)")
        case .foundation(let f): Text("foundation → \(f.rawValue)")
        case .app(let a):        Text("app → \(a.rawValue)")
        }
    } else { Text("Select a widget").foregroundColor(.secondary) }
}
```

- [ ] **Step 7: Delete retired header machinery.** Remove `header`, `tabGroup`, the old `ScrollView { LazyVStack { ThemeCard } }` body, and `FamilyTab` if now unused. **Keep** `ThemeChip` and `FlowLayout` — Task 7 renders the 36-chip swatch grid inside the Palette page. `ThemeCard`: keep for now (its `mock`/`paletteFoundations`/`appCaption` helpers are extracted in Tasks 6-7; delete the card-chrome body once unused).

- [ ] **Step 8: Build.** `swift build` — Expected: clean.

- [ ] **Step 9: Live-verify the shell renders (the `.toolbar`/`.searchable` trap).** Launch prism. Confirm: **top bar (theme Picker + Effects + sidebar toggle) is VISIBLE**; **sidebar search field is VISIBLE and typeable**; typing "list" filters to ThemedList; selecting a row updates the placeholder; the toggle collapses/expands the sidebar. `screencapture -l<winid> -o /tmp/prism-shell.png` (non-activating).

- [ ] **Step 10: Live-verify keyboard nav (LIVE/manual — window activated; separate from the capture path).** With prism focused, click a sidebar row, press ↑/↓ — selection moves through rows and the placeholder updates. Confirm typing in the search field does NOT move the List selection (focus is separated). This step is manual and NOT part of the non-activating screenshot recipe.

- [ ] **Step 11: Commit.**
```bash
git add Sources/prism/Gallery.swift
git commit -m ":sparkles: feat(prism): NavigationSplitView shell — in-content top bar + searchable sidebar + focus routing"
```

---

## Task 6: WidgetPage — Overview | Specimens | API, anchors, copy ref (whole mock)

Overview shows the whole mock for now (decomposition = Task 8). Structure, anchors, live theming, copy-ref land here.

**Files:** Create `Sources/prism/WidgetPage.swift`; Modify `Sources/prism/Gallery.swift` (extract `mock(for:)`; wire `.widget` arm).
**Interfaces:** Consumes `KitComponent`/`kitComponent()`, `CopyRefButton`, the mocks, `resolve`/`paletteFor`/`isAnimatableTheme`/`animated(forTheme:at:)`/`effectCycleSeconds`; Produces `WidgetPage` + `PageSection`.

- [ ] **Step 1: Extract `mock(for:)` in Gallery.swift** (file-level, factored from `widgetFamily` L339-390). Thread the extra args some mocks need (`MockBorder(p:themeName:)`, `MockThemedPill(p:themeName:)`, `MockPerchOverlay`/`MockHalo` take `themeName:showEffects:`; `ThemedGrid` → `MockThumbnailGrid`). Terminal `default:` required (String switch is not exhaustive):
```swift
@ViewBuilder func mock(for name: String, p: ResolvedPalette, themeName: String, showEffects: Bool) -> some View {
    switch name {
    case "ThemedTextField": MockField(p: p)
    case "ThemedComboBox":  MockComboBox(p: p)
    case "ThemedButton":    MockButton(p: p)
    case "ThemedButtonGroup": MockButtonGroup(p: p)
    case "ThemedToolBar":   MockToolBar(p: p)
    case "ThemedChip":      MockChip(p: p)
    case "ThemedPill":      MockThemedPill(p: p, themeName: themeName)
    case "ThemedCheckbox":  MockCheckbox(p: p)
    case "ThemedFAB":       MockFAB(p: p)
    case "ThemedDivider":   MockDivider(p: p)
    case "AnimatedBorderView": MockBorder(p: p, themeName: themeName)
    case "ThemedSkeleton":  MockSkeleton(p: p)
    case "ThemedTooltip":   MockTooltip(p: p)
    case "ThemedBackdrop":  MockBackdrop(p: p)
    case "WindowShell":     MockWindowShell(p: p)
    case "ThemedList":      MockList(p: p)
    case "ThemedMenu":      MockMenu(p: p)
    case "ThemedGrid":      MockThumbnailGrid(p: p)
    case "ThemedTransition": MockMotion(p: p)
    case "ParticleBurst":   MockParticles(p: p)
    case "SplatterShape":   MockSplatter(p: p)
    case "TrailGeometry":   MockTrail(p: p)
    case "PixelSprite":     MockPixelArt(p: p)
    default:                EmptyView()
    }
}
```
(This list IS `wiredMockNames` from Task 4 — keep them equal; the Task 4 test enforces it.)

- [ ] **Step 2: Write `WidgetPage`.** Create `Sources/prism/WidgetPage.swift` (note `import Effects` for `isAnimatableTheme`; `mock`/`cells` are plain closures — NO `@ViewBuilder` on stored properties):
```swift
import SwiftUI
import Palette
import PaletteKit
import Effects      // isAnimatableTheme lives here (not re-exported by PaletteKit)

enum PageSection: String, CaseIterable, Identifiable {
    case overview = "Overview", specimens = "Specimens", api = "API"
    var id: String { rawValue }
}

struct WidgetPage: View {
    let component: KitComponent
    let themeName: String
    let showEffects: Bool
    let mock: (ResolvedPalette) -> AnyView                     // whole-mock renderer (Gallery supplies)
    let cells: ((ResolvedPalette) -> [(String, AnyView)])?     // set by Task 8 for decomposed mocks; else nil
    @State var section: PageSection
    @State var showAll: Bool

    var body: some View {
        let base = resolve(paletteFor(themeName))
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(base)
                    Picker("", selection: $section) {
                        ForEach(PageSection.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    block(.overview, base) { overviewBody(base) }
                    block(.specimens, base) { specimensBody(base) }
                    block(.api, base) {
                        Text(component.fullAPI).font(sysFont(9, design: .monospaced))
                            .foregroundColor(Color(nsColor: base.foreground)).textSelection(.enabled)
                    }
                }.padding(18)
            }
            .onChange(of: section) { _, s in withAnimation { proxy.scrollTo(s, anchor: .top) } }
            .onAppear { proxy.scrollTo(section, anchor: .top) }   // section= deep-link lands here, zero clicks
        }
    }

    @ViewBuilder private func overviewBody(_ base: ResolvedPalette) -> some View {
        if let cells { living(base) { p in AnyView(VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(cells(p).prefix(2).enumerated()), id: \.offset) { $0.element.1 } }) } }
        else { living(base, mock) }         // whole mock (compact enough or not yet decomposed)
    }
    @ViewBuilder private func specimensBody(_ base: ResolvedPalette) -> some View {
        if let cells { living(base) { p in AnyView(VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(cells(p).enumerated()), id: \.offset) { $0.element.1 } }) } }
        else { living(base, mock) }
    }

    // Live (animated) for animatable themes, else static — mirrors ThemeCard (Gallery.swift:282-293).
    @ViewBuilder private func living(_ base: ResolvedPalette, _ render: @escaping (ResolvedPalette) -> AnyView) -> some View {
        if showEffects, isAnimatableTheme(themeName) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { t in
                render(base.animated(forTheme: themeName, at: CGFloat(t.date.timeIntervalSinceReferenceDate / effectCycleSeconds)))
            }
        } else { render(base) }
    }

    @ViewBuilder private func header(_ p: ResolvedPalette) -> some View {
        HStack(spacing: 8) {
            Text(component.name).font(sysFont(16, weight: .bold)).foregroundColor(Color(nsColor: p.foreground))
            Text("MUI \(component.kind) · \(component.family.rawValue)")
                .font(sysFont(9, design: .monospaced)).foregroundColor(Color(nsColor: p.muted)).lineLimit(1)
            Spacer(); CopyRefButton(component: component, p: p)
        }
    }
    @ViewBuilder private func block<C: View>(_ s: PageSection, _ p: ResolvedPalette, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(s.rawValue.uppercased()).font(sysFont(9, weight: .bold, design: .monospaced)).foregroundColor(Color(nsColor: p.muted))
            c()
        }.id(s)
    }
}
```

- [ ] **Step 3: Wire the `.widget` arm (case-insensitive section seed; `showAll` forces `.specimens`).**
```swift
case .widget(let name):
    WidgetPage(
        component: kitComponent(name),
        themeName: selectedTheme == "all" ? "dracula" : selectedTheme,   // "all" tiling → Task 9
        showEffects: showEffects,
        mock: { p in AnyView(mock(for: name, p: p, themeName: selectedTheme == "all" ? "dracula" : selectedTheme, showEffects: showEffects)) },
        cells: nil,                                                       // Task 8 supplies for decomposed mocks
        section: config.showAll ? .specimens
                 : (PageSection.allCases.first { $0.rawValue.lowercased() == config.section } ?? .overview),
        showAll: config.showAll)
```

- [ ] **Step 4: Build.** `swift build` — Expected: clean.

- [ ] **Step 5: Live-verify.** `PRISM_CONFIG` with `widget = "ThemedList"`, `theme = "dracula"`: the page shows header + MUI kind + copy ref; the segmented control + `section=` land on each anchor; the widget renders live for an animatable theme; **copy ref → paste yields the ~15-line core** (`TYPE TO USE: ThemedListView`…). Also test `section = "api"` opens scrolled to API. Non-activating capture.

- [ ] **Step 6: Commit.**
```bash
git add Sources/prism/WidgetPage.swift Sources/prism/Gallery.swift
git commit -m ":sparkles: feat(prism): one-widget page — Overview/Specimens/API, anchors, live mock, copy ref"
```

---

## Task 7: Foundation/app page (+ extract reused helpers, + preserve 36-chip preview)

**Files:** Create `Sources/prism/FoundationAppPage.swift`; Modify `Sources/prism/Gallery.swift` (extract `paletteFoundations`/`appCaption` to file-level; wire `.foundation`/`.app` arms).
**Interfaces:** Consumes the extracted helpers + `MockIcons`/`MockTree`/`MockWandLauncher`/`MockPerchOverlay`/`MockHalo`/`MockGlancePopover`/`ThemeChip`/`resolve`/`paletteFor`; Produces `FoundationAppPage`.

- [ ] **Step 1: Extract `paletteFoundations` + `appCaption` to file-level** (they are `private func`s on `ThemeCard` reading `self.name/scale/showEffects` — parameterize them so a separate struct can call them):
```swift
func paletteFoundations(spec: ThemeSpec, p: ResolvedPalette, name: String, scale: CGFloat, showEffects: Bool) -> AnyView {
    AnyView(VStack(alignment: .leading, spacing: 14) {
        SwatchRow(p: p)
        Text("AaBbCcGg 0123 — The quick brown fox jumps").font(themeFont(spec.font, size: 15 * scale)).foregroundColor(Color(nsColor: p.foreground))
        TypeScaleSpecimen(p: p); TokenSpecimen(p: p)
        if showEffects, let fx = borderEffectFor(name) { LiveEffectStrip(fx: fx, name: name, fallback: p.primary) }
    })
}
func appCaption(_ tab: KitFamily, p: ResolvedPalette) -> AnyView {
    guard let a = appChrome(tab) else { return AnyView(EmptyView()) }
    return AnyView(VStack(alignment: .leading, spacing: 2) {
        Text(a.blurb).font(sysFont(10, weight: .medium)).foregroundColor(Color(nsColor: p.foreground))
        Text("uses: \(a.uses)").font(sysFont(8.5, design: .monospaced)).foregroundColor(Color(nsColor: p.muted))
        Text(a.themes).font(sysFont(8.5, design: .monospaced)).foregroundColor(Color(nsColor: p.muted))
    }.fixedSize(horizontal: false, vertical: true))
}
```
Update `ThemeCard` (if its body still calls these) to pass `name: name, scale: scale, showEffects: showEffects`.

- [ ] **Step 2: Write `FoundationAppPage`.** Create the file:
```swift
import SwiftUI
import Palette
import PaletteKit

struct FoundationAppPage: View {
    let item: SidebarItem        // .foundation or .app only
    let themeName: String
    let showEffects: Bool

    var body: some View {
        let name = themeName == "all" ? "dracula" : themeName
        let spec = paletteFor(name)
        let p = resolve(spec)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch item {
                case .foundation(.palette):
                    Text("Theme palette preview").font(sysFont(12, weight: .semibold)).foregroundColor(Color(nsColor: p.foreground))
                    themeChipGrid                                   // the retired 36-chip swatch wall, preserved (spec §4.2.1/§8)
                    paletteFoundations(spec: spec, p: p, name: name, scale: 1.0, showEffects: showEffects)
                case .foundation(.icons):
                    MockIcons(p: p)
                case .app(let a):
                    appCaption(a, p: p)
                    appMock(a, p: p, name: name)
                default: EmptyView()
                }
            }.padding(18)
        }
    }

    private var themeChipGrid: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Gallery.switchable, id: \.self) { ThemeChip(name: $0, label: $0, selected: false) {} }
        }
    }
    @ViewBuilder private func appMock(_ a: KitFamily, p: ResolvedPalette, name: String) -> some View {
        switch a {
        case .facet: MockTree(p: p)
        case .wand:  MockWandLauncher(p: p)
        case .perch: MockPerchOverlay(p: p, themeName: name, showEffects: showEffects)
        case .halo:  MockHalo(p: p, themeName: name, showEffects: showEffects)
        case .glance: MockGlancePopover(p: p)
        default: EmptyView()
        }
    }
}
```
(`Gallery.switchable` is referenced from Gallery's own file only if this struct lives in Gallery.swift; since it's a new file, widen `switchable` to `static let` (internal) in this task, OR pass the theme-name list in. Choose: widen `switchable` to internal — a one-word change, no behavior change.)

- [ ] **Step 3: Wire `detailPage`.** Replace the `.foundation`/`.app` placeholder arms with `FoundationAppPage(item: selection, themeName: selectedTheme, showEffects: showEffects)`.

- [ ] **Step 4: Build.** `swift build` — Expected: clean.

- [ ] **Step 5: Live-verify.** Launch prism; select **Palette** (36-chip swatch grid + swatch/type/token specimens render), **Icons** (icon grid), and each app (facet/wand/perch/halo/glance; perch/halo animate when Effects on). `family = "facet"` deep-link opens facet. Non-activating captures.

- [ ] **Step 6: Commit.**
```bash
git add Sources/prism/FoundationAppPage.swift Sources/prism/Gallery.swift
git commit -m ":sparkles: feat(prism): bespoke foundation/app pages + preserved 36-chip palette preview"
```

---

## Task 8: MockList cell decomposition (compact Overview + full Specimens)

Scope: **MockList only** (the flagship; the whole reason for the task). Additional tall mocks are Task 11. Preserves MockList's multi-column grid for the full view; per-cell rendering unchanged.

**Files:** Modify `Sources/prism/ListShowcase.swift` (`MockList` L177-360); Modify `Sources/prism/WidgetPage.swift`/`Gallery.swift` (pass `cells:`).
**Interfaces:** Produces `MockList.cellViews(p:) -> [(String, AnyView)]`.

- [ ] **Step 1: Expose MockList's cells (grid preserved).** Refactor `MockList` so each specimen cell is an element of `func cellViews(p: ResolvedPalette) -> [(String, AnyView)]` (extract the inline `cell(...)` bodies; each cell's rendering byte-identical). Keep `MockList.body` rendering the SAME layout by grouping cells into its existing rows-of-2-3 (`LazyVGrid`/the current HStack rows) so the full view is unchanged. The leading description `Text` (L162 area) moves to the page header context, NOT a cell (it is not a specimen).

- [ ] **Step 2: Supply `cells` from Gallery for ThemedList.** In `detailPage`'s `.widget` arm, pass `cells:` only for names that expose them:
```swift
cells: name == "ThemedList" ? { p in MockList.cellViews(p: p) } : nil,
```

- [ ] **Step 3: (WidgetPage already consumes `cells`.)** Overview renders `cells.prefix(2)`, Specimens renders all `cells` (Task 6 Step 2 `overviewBody`/`specimensBody`). Confirm the Specimens layout matches MockList's grid (wrap the cells in the same 2-3-column arrangement inside `specimensBody` if a plain VStack drifts from today's look — mirror MockList's row grouping).

- [ ] **Step 4: Build.** `swift build` — Expected: clean.

- [ ] **Step 5: Live-verify (drift check).** Launch prism on `widget = "ThemedList"`: Overview shows ~1–2 cells (compact, one viewport); `show-all = true` (or the Specimens tab) shows all ~12 in the SAME grid as today. Diff a Specimens screenshot against a pre-Task-8 capture — per-cell rendering identical, grid layout preserved. Non-activating capture.

- [ ] **Step 6: Commit.**
```bash
git add Sources/prism/ListShowcase.swift Sources/prism/WidgetPage.swift Sources/prism/Gallery.swift
git commit -m ":sparkles: feat(prism): compact Overview + full Specimens via MockList cell decomposition"
```

---

## Task 9: All-themes tiling + deep-link end-to-end + capture verification

**Files:** Modify `Sources/prism/Gallery.swift` (`.widget` arm: `selectedTheme == "all"` tiling — kept IN Gallery so `switchable`/`mock(for:)` stay in-file).
**Interfaces:** Consumes `Gallery.switchable`, `mock(for:)`, `isAnimatableTheme`.

- [ ] **Step 1: Tile across themes when "All".** In the `.widget` arm, branch on `selectedTheme == "all"`:
```swift
case .widget(let name) where selectedTheme == "all":
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320 * uiScale), spacing: 16)], spacing: 16) {
            ForEach(Gallery.switchable, id: \.self) { theme in
                let base = resolve(paletteFor(theme))
                VStack(alignment: .leading, spacing: 6) {
                    Text(theme).font(sysFont(9, weight: .semibold, design: .monospaced)).foregroundColor(Color(nsColor: base.muted))
                    if showEffects, isAnimatableTheme(theme) {
                        TimelineView(.animation(minimumInterval: 1.0/30.0)) { t in
                            mock(for: name, p: base.animated(forTheme: theme, at: CGFloat(t.date.timeIntervalSinceReferenceDate / effectCycleSeconds)), themeName: theme, showEffects: showEffects)
                        }
                    } else { mock(for: name, p: base, themeName: theme, showEffects: showEffects) }
                }
            }
        }.padding(18)
    }
```
(One mock per theme — not the full cell grid — so live-animation load ≤ today's "all". A decomposed widget could tile just its representative cell later; the whole mock is the safe v1 fallback.)

- [ ] **Step 2: Confirm deep-link seeding end-to-end.** Verify `config.widget`/`config.family` seed selection (Task 5 Step 2), and `config.section`/`config.showAll` seed WidgetPage + fire the initial `scrollTo` (Task 6). Unknown `widget=` already falls back via `?? sidebarItem(forFamily:) ?? .widget(firstWidgetName)` — no blank page.

- [ ] **Step 3: Build + full test.** `swift build` then `scripts/test.sh` — Expected: build clean, all prismTests PASS.

- [ ] **Step 4: Capture verification (spec §4.8 acceptance matrix).** For each, launch with `PRISM_CONFIG` then `screencapture -l<winid>` (no osascript activation):
  - `widget="ThemedList"`, `theme="dracula"`, `section="specimens"` → opens on the full Specimens grid, zero clicks;
  - `widget="ThemedList"`, `section="api"` → opens scrolled to API (round-trips — the case-insensitive fix);
  - `widget="ThemedList"`, `theme="all"` → tiled grid captures cleanly, content on-window;
  - `family="facet"` → facet page.

- [ ] **Step 5: Commit.**
```bash
git add Sources/prism/Gallery.swift
git commit -m ":sparkles: feat(prism): all-themes tiling + deterministic capture deep-link"
```

---

## Task 10: Copy-ref recipes for the remaining catalog widgets (22)

Author the paste-ready recipe for every entry except ThemedList (done Task 3). Count: 24 catalog entries − MarkdownView (excluded) − ThemedList = **22**. ~16 are real SwiftUI widgets; ~6 are **pure/effects atoms** (`ThemedTransition`, `ParticleBurst`, `SplatterShape`, `TrailGeometry`, `PixelSprite`, `WindowShell`) whose `consumes` says "pure functions / free-function factories, no view" — these take the atom branch.

**Files:** Modify `Sources/prism/KitCatalog.swift`; Modify `Tests/prismTests/PrismLogicTests.swift`.

- [ ] **Step 1: Per-widget procedure (repeat for each of the 22).** For entry `X`:
  1. Open `X`'s public type. **Widget branch:** the SwiftUI front in `Sources/ThemeKitUI/` (default) — read its real `public init`; set `defaultType`, `imports`, `initSnippet` (smallest compilable call), `cellType`/`cellInit` if it has cells, `sourcePath`, `appkitEscape` (the AppKit type, or ""). **Atom branch** (set `isAtom: true`, leave `defaultType: ""`): read the free function / value type in `Motion`/`Effects`/`PixelArt`/`ThemeKit`; set `imports` (e.g. `import Motion`) + `initSnippet` = the closed-form call, `sourcePath`.
  2. Cross-check the `Mock<X>`/`*Showcase.swift` usage for the minimal working call.
  3. `swift build` (values are docs, but must be accurate — the current `consumes`/`keyAPI` are stale post-#17b; derive from source).
  (Optional accelerator: fan out one subagent per entry that reads its signature and returns the filled fields; assemble + compile.)

- [ ] **Step 2: Completeness gate test (branch-aware).** Add:
```swift
func testEveryRecipeFilled() {
    let atoms: Set<String> = ["ThemedTransition","ParticleBurst","SplatterShape","TrailGeometry","PixelSprite","WindowShell"]
    for c in kitCatalog where c.name != "MarkdownView" {
        XCTAssertFalse(c.imports.isEmpty, "\(c.name) missing imports")
        XCTAssertFalse(c.initSnippet.isEmpty, "\(c.name) missing initSnippet")
        if !atoms.contains(c.name) && !c.isAtom {
            XCTAssertFalse(c.defaultType.isEmpty, "\(c.name) (widget) missing SwiftUI defaultType")
        }
    }
}
```

- [ ] **Step 3: Build + full test.** `swift build` then `scripts/test.sh` — Expected: PASS (gate enforces every recipe filled).

- [ ] **Step 4: Final live sweep.** Spot-check 4-5 widget pages + copy-ref pastes across two themes; confirm search, sidebar toggle, Overview/Specimens, All-tiling, keyboard nav still work. Non-activating captures for the PR.

- [ ] **Step 5: Commit.**
```bash
git add Sources/prism/KitCatalog.swift Tests/prismTests/PrismLogicTests.swift
git commit -m ":sparkles: feat(prism): paste-ready copy-ref recipes for all catalog widgets"
```

---

## Task 11 (follow-up): decompose additional tall mocks

Only if any non-MockList mock is still taller than a viewport in Overview. Bounded, per-mock.

**Files:** Modify the specific `Sources/prism/*Showcase.swift`.

- [ ] **Step 1: Enumerate the set from source.** Launch prism, open each widget page, note which Overview still overflows a viewport (candidates: `MockMenu`, `MockThumbnailGrid`, `MockIcons`, `MockButtonGroup`). Record the exact set in the commit body. If none overflow, close the task as "not needed" with that note.

- [ ] **Step 2: For each mock in the set (repeat):** apply the Task 8 procedure — extract `cellViews(p:)`, keep `body` layout identical, pass `cells:` from Gallery's `.widget` arm for that name, `swift build`, live-verify Overview compact + Specimens unchanged, commit `:sparkles: feat(prism): decompose Mock<X> cells`.

---

## Self-review notes

- **Spec coverage:** nav A1 → T5-7; theme default-single + All tiling → T1+T9; Overview/anchors/Show-all → T6+T8; pragmatic decomposition → T8 (+T11); copy-ref restructure + recipes → T3+T10 (atom branch for the 6 non-widget specimens); deep-link widget/**family**/theme/section/showAll + fallback → T1+T5+T6+T9; reachability display-safe + PRISM_WINDOW_H preserved → T1; AppKit purity + in-content chrome → Global Constraints + T5; SidebarItem registry + ThemedGrid + MarkdownView → T4; foundation/app page + threading + **36-chip preview preserved** → T7; §4.8 capture-first incl. section= initial scroll + api round-trip → T6+T9; keyboard-nav @FocusState + live-only verify → T5; render-map drift guard → T4.
- **Section model:** 3 sections (Overview | Specimens | API) — a documented simplification of the spec's illustrative 4 labels (mocks don't split variant vs state cells).
- **Known execution risks (documented, not blockers):** `@testable import prism` vs `@main` (T2 fallback); `NavigationSplitView` column widths vs `920*uiScale` content (tune T5 Step 9); the `sidebar-simple` slug may need vendoring (T5 Step 4).
