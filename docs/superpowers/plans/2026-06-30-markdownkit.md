# MarkdownKit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a SwiftUI-native GFM markdown renderer as two sill modules (pure `MarkdownKit` parser + SwiftUI `MarkdownKitUI` renderer), shown live in prism — the prereq for glance Phase B (#22).

**Architecture:** A pure `MarkdownKit` walks `apple/swift-markdown`'s AST into a `Sendable`, palette-free `[MarkdownBlock]` model (inline runs carried as a Foundation `AttributedString` with semantic `InlinePresentationIntent`s only). A SwiftUI `MarkdownKitUI` renders that model into a `VStack` of per-block views, mapping intents + block chrome onto canonical `ResolvedPalette` roles. Tables are `LazyVGrid`; blockquote bars / hr are `Rectangle`; code/header fills are `surface(.inset)`. No `NSTextView`/`NSAttributedString` rendering anywhere.

**Tech Stack:** Swift, SwiftUI (macOS 13+), `apple/swift-markdown` (cmark-gfm), sill `Palette`/`PaletteKit`/`ThemeKit`, prism bench.

## Global Constraints

- **Local build gate is `swift build`** (CommandLineTools-only machine). `swift test` needs full Xcode and runs in **CI only** — so every "run the test" step means: it executes in CI; locally confirm the test file + sources **compile** with `swift build`. Render correctness is proven **live in prism**, not by unit tests.
- **AppKit policy**: 100% SwiftUI. AppKit is allowed only for the IME field-editor core + the non-activating window shell — a markdown renderer is neither. No `NSTextView`/`NSAttributedString`-backed rendering; GFM tables MUST be `LazyVGrid`; inline-code/hr/blockquote are SwiftUI run-styling/shapes, never AppKit widgets.
- **Theming**: canonical `ResolvedPalette` roles ONLY — `background · foreground · muted · tertiary · primary · secondary · border · hover · selection · error` + `surface(.raised/.inset)` + `ink(_:of:)`. Never invent role names. Bridge to SwiftUI per-site with `Color(nsColor: palette.<role>)` (repo convention; no shared helper).
- **Platform floor**: `macOS(.v13)` — unchanged. New SwiftUI API must be available at macOS 13.
- **swift-markdown pin**: mirror glance (`from: "0.4.0"`); if a future version breaks the CLT build, pin down like the SwiftDraw `< 0.25.0` precedent.
- **No new role names, no Effects dep, no animation in v1.** Module deps exactly: `MarkdownKit → [Markdown]`; `MarkdownKitUI → [MarkdownKit, PaletteKit, Palette, ThemeKit]`; `prism += [MarkdownKit, MarkdownKitUI]`.
- **Commits**: gitmoji + Conventional Commits, e.g. `:sparkles: feat(MarkdownKit): …`. Frequent, one per task. End commit messages with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Branch/worktree**: already on `worktree-markdownkit` off clean `origin/main` (includes #91 `surface(.inset)` / #92).

---

## File Structure

**Create:**
- `Sources/MarkdownKit/MarkdownBlock.swift` — the `Sendable` model: `MarkdownBlock`, `MarkdownList`, `MarkdownListItem`, `MarkdownTable`.
- `Sources/MarkdownKit/MarkdownParser.swift` — `parseMarkdown(_:)` + the block walk.
- `Sources/MarkdownKit/InlineAttributed.swift` — inline AST → `AttributedString` (intents only).
- `Sources/MarkdownKitUI/MarkdownStyle.swift` — typography knobs.
- `Sources/MarkdownKitUI/MarkdownHighlighter.swift` — the injectable highlighter protocol.
- `Sources/MarkdownKitUI/InlineStyling.swift` — semantic `AttributedString` → themed SwiftUI `AttributedString` (role colors/fonts, inline-code flat bg + hairspace).
- `Sources/MarkdownKitUI/MarkdownView.swift` — top-level `View` + block dispatch + simple blocks (heading/paragraph/hr/html/image).
- `Sources/MarkdownKitUI/CodeBlockView.swift` — code block chrome + plain/highlighted body.
- `Sources/MarkdownKitUI/BlockquoteView.swift` — left-bar quote, recursive.
- `Sources/MarkdownKitUI/MarkdownListView.swift` — ordered/unordered/task/nested.
- `Sources/MarkdownKitUI/MarkdownTableView.swift` — `LazyVGrid` GFM table.
- `Sources/prism/MarkdownShowcase.swift` — `MockMarkdown(p:)` rendering the real `MarkdownView`.
- `Tests/MarkdownKitTests/MarkdownParserTests.swift` — parse-layer XCTest.

**Modify:**
- `Package.swift` — add swift-markdown dep, two targets, two products, test target, prism deps.
- `Sources/prism/Specimens.swift` — remove the old static `MockMarkdown`.
- `Sources/prism/Gallery.swift` — register the real markdown section under `.glance`.
- `Sources/prism/KitCatalog.swift` — add the `MarkdownView` catalog entry.

---

## Task 1: Package scaffolding + swift-markdown resolves on CLT

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MarkdownKit/MarkdownKit.swift` (temporary import smoke file)
- Create: `Sources/MarkdownKitUI/MarkdownKitUI.swift` (temporary import smoke file)

**Interfaces:**
- Produces: targets `MarkdownKit`, `MarkdownKitUI` and products of the same name; the `Markdown` product (swift-markdown) is available to `MarkdownKit`.

- [ ] **Step 1: Add the swift-markdown dependency.** In `Package.swift`, in the `dependencies:` array of the `Package(...)`, add (mirroring glance):

```swift
.package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
```

- [ ] **Step 2: Declare the two products.** In the `products:` array add:

```swift
.library(name: "MarkdownKit", targets: ["MarkdownKit"]),
.library(name: "MarkdownKitUI", targets: ["MarkdownKitUI"]),
```

- [ ] **Step 3: Declare the two targets.** In `targets:`, add before the `prism` executable target:

```swift
.target(
    name: "MarkdownKit",
    dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
.target(
    name: "MarkdownKitUI",
    dependencies: ["MarkdownKit", "PaletteKit", "Palette", "ThemeKit"]),
.testTarget(
    name: "MarkdownKitTests",
    dependencies: ["MarkdownKit"]),
```

- [ ] **Step 4: Add prism deps.** In the `prism` executableTarget `dependencies:` array, append `"MarkdownKit", "MarkdownKitUI"`.

- [ ] **Step 5: Create the smoke files.**

`Sources/MarkdownKit/MarkdownKit.swift`:
```swift
import Markdown

// Smoke check that swift-markdown links on CommandLineTools. Removed in Task 3.
enum MarkdownKitBuildSmoke { static let ok = Document(parsing: "# hi").childCount >= 0 }
```

`Sources/MarkdownKitUI/MarkdownKitUI.swift`:
```swift
import SwiftUI
import MarkdownKit
import PaletteKit

// Smoke check. Removed in Task 9.
enum MarkdownKitUIBuildSmoke { static let ok = true }
```

- [ ] **Step 6: Resolve + build (the local gate).**

Run: `swift package resolve`
Expected: resolves `swift-markdown` with no error.

Run: `swift build`
Expected: build SUCCEEDS on CommandLineTools. If swift-markdown fails to build on CLT, pin it down (try `.upToNextMinor(from: "0.4.0")`, then a specific known-good tag) and note it in the spec's pin line.

- [ ] **Step 7: Commit.**

```bash
git add Package.swift Package.resolved Sources/MarkdownKit Sources/MarkdownKitUI
git commit -m ":sparkles: feat(MarkdownKit,MarkdownKitUI): scaffold modules + swift-markdown dep

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: The block model

**Files:**
- Create: `Sources/MarkdownKit/MarkdownBlock.swift`

**Interfaces:**
- Produces: `enum MarkdownBlock`, `struct MarkdownList`, `struct MarkdownListItem` (+ `.Checkbox`), `struct MarkdownTable` (+ `.Alignment`). All `public`, `Sendable`, `Equatable`. These are consumed by every later task.

- [ ] **Step 1: Write the model.**

```swift
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
```

- [ ] **Step 2: Build.**

Run: `swift build`
Expected: SUCCEEDS.

- [ ] **Step 3: Commit.**

```bash
git add Sources/MarkdownKit/MarkdownBlock.swift
git commit -m ":sparkles: feat(MarkdownKit): block model (MarkdownBlock/List/Table)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Inline → AttributedString (intents only)

**Files:**
- Create: `Sources/MarkdownKit/InlineAttributed.swift`
- Test: `Tests/MarkdownKitTests/MarkdownParserTests.swift`

**Interfaces:**
- Consumes: nothing (swift-markdown only).
- Produces: `func inlineAttributed(_ container: Markup) -> AttributedString` (internal) — flattens a block's inline children into one `AttributedString` carrying `inlinePresentationIntent` (`.stronglyEmphasized`/`.emphasized`/`.strikethrough`/`.code`) and `.link` (URL). No colors.

- [ ] **Step 1: Write the failing test.** In `Tests/MarkdownKitTests/MarkdownParserTests.swift`:

```swift
import XCTest
import Markdown
@testable import MarkdownKit

final class MarkdownParserTests: XCTestCase {

    // Helper: parse one paragraph and return its inline AttributedString.
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
}
```

- [ ] **Step 2: Run the test (CI) / confirm it compiles (local).**

Run (CI or full-Xcode machine): `swift test --filter MarkdownParserTests` → Expected: FAIL ("cannot find 'inlineAttributed'").
Run (local CLT gate): `swift build` → currently FAILS to compile the test target (symbol missing) — that is the red state.

- [ ] **Step 3: Implement `inlineAttributed`.** In `Sources/MarkdownKit/InlineAttributed.swift`:

```swift
import Foundation
import Markdown

/// Flatten a block's inline children into one AttributedString carrying
/// semantic intents (no colors). Colors/fonts are applied by MarkdownKitUI.
func inlineAttributed(_ container: Markup) -> AttributedString {
    var out = AttributedString()
    for child in container.children { out.append(inlineRun(child, intents: [], link: nil)) }
    return out
}

private func inlineRun(_ markup: Markup,
                       intents: InlinePresentationIntent,
                       link: URL?) -> AttributedString {
    switch markup {
    case let text as Markdown.Text:
        return styledLeaf(text.string, intents: intents, link: link)
    case is SoftBreak:
        return styledLeaf(" ", intents: intents, link: link)
    case is LineBreak:
        return styledLeaf("\n", intents: intents, link: link)
    case let code as InlineCode:
        return styledLeaf(code.code, intents: intents.union(.code), link: link)
    case let html as InlineHTML:
        return styledLeaf(html.rawHTML, intents: intents, link: link)
    case let img as Markdown.Image:
        // inline image alt as plain text (v1 stub; block images handled in parser)
        return styledLeaf(img.plainText.isEmpty ? "image" : img.plainText, intents: intents, link: link)
    case let strong as Strong:
        return recurse(strong, intents: intents.union(.stronglyEmphasized), link: link)
    case let em as Emphasis:
        return recurse(em, intents: intents.union(.emphasized), link: link)
    case let strike as Strikethrough:
        return recurse(strike, intents: intents.union(.strikethrough), link: link)
    case let a as Markdown.Link:
        return recurse(a, intents: intents, link: URL(string: a.destination ?? "") ?? link)
    default:
        return recurse(markup, intents: intents, link: link)
    }
}

private func recurse(_ markup: Markup,
                     intents: InlinePresentationIntent,
                     link: URL?) -> AttributedString {
    var out = AttributedString()
    for child in markup.children { out.append(inlineRun(child, intents: intents, link: link)) }
    return out
}

private func styledLeaf(_ s: String,
                        intents: InlinePresentationIntent,
                        link: URL?) -> AttributedString {
    var run = AttributedString(s)
    if !intents.isEmpty { run.inlinePresentationIntent = intents }
    if let link { run.link = link }
    return run
}
```

- [ ] **Step 4: Run the test (CI) / build (local).**

Run (CI): `swift test --filter MarkdownParserTests` → Expected: PASS.
Run (local): `swift build` → Expected: SUCCEEDS (test target compiles).

- [ ] **Step 5: Commit.**

```bash
git add Sources/MarkdownKit/InlineAttributed.swift Tests/MarkdownKitTests
git commit -m ":sparkles: feat(MarkdownKit): inline AST -> AttributedString intents

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Block parser — headings, paragraphs, hr, html, image

**Files:**
- Create: `Sources/MarkdownKit/MarkdownParser.swift`
- Delete the temporary `Sources/MarkdownKit/MarkdownKit.swift` smoke file.
- Test: extend `Tests/MarkdownKitTests/MarkdownParserTests.swift`

**Interfaces:**
- Consumes: `inlineAttributed(_:)` (Task 3), the model (Task 2).
- Produces: `public func parseMarkdown(_ source: String) -> [MarkdownBlock]` and an internal `func blocks(from children: MarkupChildren) -> [MarkdownBlock]` used recursively by later block tasks.

- [ ] **Step 1: Write the failing tests.** Append:

```swift
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
```

- [ ] **Step 2: Run (CI) / build (local).** Expected RED: `swift test` FAIL ("cannot find 'parseMarkdown'"); `swift build` fails compiling tests.

- [ ] **Step 3: Implement the parser core.** In `Sources/MarkdownKit/MarkdownParser.swift`:

```swift
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
        if let only = p.children.first as? Markdown.Image, p.childCount == 1 {
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
```

> Tasks 5–7 implement `list(from:ordered:start:)` and `tableBlock(from:)`; `block(from:)` already references them so those tasks only add the helper functions (no edit here).

- [ ] **Step 4: Stub the not-yet-implemented helpers** so this task compiles in isolation. Add at the bottom of `MarkdownParser.swift` (replaced in Tasks 5–7):

```swift
// TEMP stubs (Tasks 5–7 replace these). Kept so Task 4 compiles + tests run.
func list(from list: ListItemContainer, ordered: Bool, start: Int) -> MarkdownList {
    MarkdownList(ordered: ordered, start: start, items: [])
}
func tableBlock(from table: Markdown.Table) -> MarkdownBlock { .table(MarkdownTable(columns: [], header: [], rows: [])) }
```

- [ ] **Step 5: Delete the smoke file.** `rm Sources/MarkdownKit/MarkdownKit.swift`

- [ ] **Step 6: Run (CI) / build (local).** Expected: `swift test --filter MarkdownParserTests` PASS for the new tests; `swift build` SUCCEEDS.

- [ ] **Step 7: Commit.**

```bash
git add Sources/MarkdownKit Tests/MarkdownKitTests
git rm --cached --ignore-unmatch Sources/MarkdownKit/MarkdownKit.swift
git commit -m ":sparkles: feat(MarkdownKit): block parser (heading/para/hr/html/image)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Parser — code blocks

**Files:**
- Modify: `Sources/MarkdownKit/MarkdownParser.swift` (already handled in `block(from:)`)
- Test: extend `MarkdownParserTests`

> `block(from:)` already maps `CodeBlock` (Task 4). This task only ADDS tests pinning the language + trailing-newline behavior. If they pass against Task 4's code, no source change is needed.

- [ ] **Step 1: Write the tests.**

```swift
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
```

- [ ] **Step 2: Run (CI) / build (local).** Expected: PASS (no source change). If a test fails, adjust the `CodeBlock` mapping in `block(from:)` to satisfy it.

- [ ] **Step 3: Commit.**

```bash
git add Tests/MarkdownKitTests
git commit -m ":white_check_mark: test(MarkdownKit): code-block language + trailing-newline

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Parser — lists (ordered/unordered/task/nested)

**Files:**
- Modify: `Sources/MarkdownKit/MarkdownParser.swift` (replace the `list(from:)` stub)
- Test: extend `MarkdownParserTests`

**Interfaces:**
- Produces: `func list(from container: ListItemContainer, ordered: Bool, start: Int) -> MarkdownList` (real implementation).

- [ ] **Step 1: Write the failing tests.**

```swift
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
```

- [ ] **Step 2: Run (CI) / build (local).** Expected RED (stub returns empty items).

- [ ] **Step 3: Replace the `list(from:)` stub.**

```swift
func list(from container: ListItemContainer, ordered: Bool, start: Int) -> MarkdownList {
    let items = container.listItems.map { item -> MarkdownListItem in
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
```

> `ListItemContainer` is the protocol both `UnorderedList` and `OrderedList` conform to; `.listItems` yields `ListItem`s; `ListItem.checkbox` is `Checkbox?` (`.checked`/`.unchecked`); `ListItem.children` are its block children (nested lists recurse through `blocks(from:)`).

- [ ] **Step 4: Run (CI) / build (local).** Expected: PASS; `swift build` SUCCEEDS.

- [ ] **Step 5: Commit.**

```bash
git add Sources/MarkdownKit Tests/MarkdownKitTests
git commit -m ":sparkles: feat(MarkdownKit): list parsing (ordered/task/nested)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Parser — blockquote + GFM table

**Files:**
- Modify: `Sources/MarkdownKit/MarkdownParser.swift` (replace the `tableBlock(from:)` stub; blockquote already handled)
- Test: extend `MarkdownParserTests`

**Interfaces:**
- Produces: `func tableBlock(from table: Markdown.Table) -> MarkdownBlock` (real).

- [ ] **Step 1: Write the failing tests.**

```swift
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
```

- [ ] **Step 2: Run (CI) / build (local).** Expected RED (table stub returns empty).

- [ ] **Step 3: Replace the `tableBlock(from:)` stub.**

```swift
func tableBlock(from table: Markdown.Table) -> MarkdownBlock {
    let columns: [MarkdownTable.Alignment] = table.columnAlignments.map {
        switch $0 {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .none: return MarkdownTable.Alignment.none
        }
    }
    let header = table.head.cells.map { inlineAttributed($0) }
    let rows = table.body.rows.map { row in row.cells.map { inlineAttributed($0) } }
    return .table(MarkdownTable(columns: columns, header: header, rows: rows))
}
```

> `Markdown.Table.columnAlignments` is `[Table.ColumnAlignment?]`; `table.head` is `Table.Head` with `.cells` (`Table.Cell`); `table.body.rows` are `Table.Row` with `.cells`. Each cell's inline children flatten via `inlineAttributed`.

- [ ] **Step 4: Run (CI) / build (local).** Expected: PASS; `swift build` SUCCEEDS. The parser layer is now feature-complete.

- [ ] **Step 5: Commit.**

```bash
git add Sources/MarkdownKit Tests/MarkdownKitTests
git commit -m ":sparkles: feat(MarkdownKit): blockquote + GFM table parsing

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: MarkdownStyle + MarkdownHighlighter

**Files:**
- Create: `Sources/MarkdownKitUI/MarkdownStyle.swift`
- Create: `Sources/MarkdownKitUI/MarkdownHighlighter.swift`
- Delete the temp `Sources/MarkdownKitUI/MarkdownKitUI.swift` smoke file.

**Interfaces:**
- Produces: `struct MarkdownStyle` (with `.default`), `protocol MarkdownHighlighter`.

- [ ] **Step 1: Write `MarkdownStyle`.**

```swift
import CoreGraphics

public struct MarkdownStyle: Sendable {
    public var baseFontSize: CGFloat
    public var headingScales: [CGFloat]   // h1..h6 multipliers of baseFontSize
    public var blockSpacing: CGFloat
    public var listIndent: CGFloat
    public var codeCornerRadius: CGFloat
    public var tableCornerRadius: CGFloat

    public init(baseFontSize: CGFloat = 13,
                headingScales: [CGFloat] = [1.75, 1.45, 1.25, 1.12, 1.05, 1.0],
                blockSpacing: CGFloat = 8,
                listIndent: CGFloat = 18,
                codeCornerRadius: CGFloat = 8,
                tableCornerRadius: CGFloat = 6) {
        self.baseFontSize = baseFontSize
        self.headingScales = headingScales
        self.blockSpacing = blockSpacing
        self.listIndent = listIndent
        self.codeCornerRadius = codeCornerRadius
        self.tableCornerRadius = tableCornerRadius
    }

    public static let `default` = MarkdownStyle()

    /// Point size for an h1...h6 heading.
    public func headingSize(_ level: Int) -> CGFloat {
        let i = min(max(level, 1), headingScales.count) - 1
        return baseFontSize * headingScales[i]
    }
}
```

- [ ] **Step 2: Write `MarkdownHighlighter`.**

```swift
import Foundation

/// Inject to color code blocks; return nil to fall back to plain themed monospaced.
public protocol MarkdownHighlighter: Sendable {
    func highlight(_ code: String, language: String?) -> AttributedString?
}
```

- [ ] **Step 3: Delete the smoke file.** `rm Sources/MarkdownKitUI/MarkdownKitUI.swift`

- [ ] **Step 4: Build.**

Run: `swift build`
Expected: SUCCEEDS.

- [ ] **Step 5: Commit.**

```bash
git add Sources/MarkdownKitUI
git rm --cached --ignore-unmatch Sources/MarkdownKitUI/MarkdownKitUI.swift
git commit -m ":sparkles: feat(MarkdownKitUI): MarkdownStyle + highlighter protocol

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: Inline styling — semantic AttributedString → themed SwiftUI runs

**Files:**
- Create: `Sources/MarkdownKitUI/InlineStyling.swift`

**Interfaces:**
- Consumes: `MarkdownStyle`, `ResolvedPalette`.
- Produces: `func themedInline(_ source: AttributedString, palette: ResolvedPalette, style: MarkdownStyle, baseFont: Font, textColor: Color) -> AttributedString` — maps each run's `inlinePresentationIntent`/`.link` onto SwiftUI `.font`/`.foregroundColor`/`.backgroundColor`/`.underlineStyle`, with inline-code given a flat `surface(.inset)` background + hairspace padding + monospaced font. `textColor` is the non-link run color (callers pass `foreground`, or `tertiary` inside a blockquote — `ResolvedPalette` is immutable `let`, so the color is threaded, not mutated). Returned `AttributedString` is fed straight into `Text(_:)`.

- [ ] **Step 1: Implement.** Render correctness is verified in prism (Task 15+); there is no SwiftUI unit test. Write:

```swift
import SwiftUI
import PaletteKit

private let hairspace = "\u{200A}"   // thin padding around inline code

func themedInline(_ source: AttributedString,
                  palette: ResolvedPalette,
                  style: MarkdownStyle,
                  baseFont: Font,
                  textColor: Color) -> AttributedString {
    var result = AttributedString()
    for run in source.runs {
        var slice = AttributedString(source[run.range])
        let intent = run.inlinePresentationIntent ?? []
        let isCode = intent.contains(.code)

        // font: monospaced for code, else weight/italic from emphasis
        var font = isCode ? Font.system(size: style.baseFontSize, design: .monospaced) : baseFont
        if intent.contains(.stronglyEmphasized) { font = font.weight(.bold) }
        if intent.contains(.emphasized) { font = font.italic() }
        slice.font = font

        // color: link → primary, else the threaded textColor (foreground / tertiary-in-quote)
        slice.foregroundColor = run.link != nil ? Color(nsColor: palette.primary) : textColor
        if run.link != nil { slice.underlineStyle = .single }
        if intent.contains(.strikethrough) { slice.strikethroughStyle = .single }
        slice.inlinePresentationIntent = nil   // translated to explicit attrs; prevent SwiftUI double-styling

        if isCode {
            slice.backgroundColor = Color(nsColor: palette.surface(.inset))
            // hairspace padding so the flat fill has breathing room (no rounded run bg in SwiftUI)
            var pad = AttributedString(hairspace)
            pad.font = font
            pad.backgroundColor = Color(nsColor: palette.surface(.inset))
            result.append(pad); result.append(slice); result.append(pad)
        } else {
            result.append(slice)
        }
    }
    return result
}
```

- [ ] **Step 2: Build.**

Run: `swift build`
Expected: SUCCEEDS. (If `slice.font`/`.foregroundColor` need the SwiftUI attribute scope, they resolve because `import SwiftUI` brings `AttributeScopes.SwiftUIAttributes`.)

- [ ] **Step 3: Commit.**

```bash
git add Sources/MarkdownKitUI/InlineStyling.swift
git commit -m ":sparkles: feat(MarkdownKitUI): themed inline run styling (code/link/emphasis)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: MarkdownView shell + simple blocks (heading/paragraph/hr/html/image)

**Files:**
- Create: `Sources/MarkdownKitUI/MarkdownView.swift`

**Interfaces:**
- Consumes: model, `themedInline`, `MarkdownStyle`, `MarkdownHighlighter`.
- Produces: `public struct MarkdownView: View`; an internal `@ViewBuilder func blockView(_ block: MarkdownBlock) -> some View` that Tasks 11–14 extend (they add views consumed via `CodeBlockView`/`BlockquoteView`/`MarkdownListView`/`MarkdownTableView`).

- [ ] **Step 1: Implement the shell.** Code-block/blockquote/list/table cases call views built in later tasks; reference them now and stub them at the bottom (replaced in Tasks 11–14).

```swift
import SwiftUI
import MarkdownKit
import PaletteKit

public struct MarkdownView: View {
    public var palette: ResolvedPalette
    public var blocks: [MarkdownBlock]
    public var style: MarkdownStyle
    public var highlighter: MarkdownHighlighter?
    public var textColor: Color?   // nil ⇒ palette.foreground; set to tertiary inside a blockquote

    public init(palette: ResolvedPalette,
                blocks: [MarkdownBlock],
                style: MarkdownStyle = .default,
                highlighter: MarkdownHighlighter? = nil,
                textColor: Color? = nil) {
        self.palette = palette; self.blocks = blocks
        self.style = style; self.highlighter = highlighter; self.textColor = textColor
    }

    public init(palette: ResolvedPalette,
                source: String,
                style: MarkdownStyle = .default,
                highlighter: MarkdownHighlighter? = nil,
                textColor: Color? = nil) {
        self.init(palette: palette, blocks: parseMarkdown(source), style: style,
                  highlighter: highlighter, textColor: textColor)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    private var bodyFont: Font {
        Font.system(size: style.baseFontSize)   // v1: system family; FontKind threading is a later refinement
    }
    private var effectiveTextColor: Color { textColor ?? Color(nsColor: palette.foreground) }

    @ViewBuilder
    func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, content):
            Text(themedInline(content, palette: palette, style: style,
                              baseFont: .system(size: style.headingSize(level)).weight(.bold),
                              textColor: effectiveTextColor))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .overlay(alignment: .bottom) {
                    if level <= 2 {
                        Rectangle().fill(Color(nsColor: palette.border)).frame(height: 1)
                            .offset(y: 4)
                    }
                }
        case let .paragraph(text):
            Text(themedInline(text, palette: palette, style: style, baseFont: bodyFont,
                              textColor: effectiveTextColor))
                .fixedSize(horizontal: false, vertical: true)
        case .thematicBreak:
            Rectangle().fill(Color(nsColor: palette.border)).frame(height: 1).padding(.vertical, 4)
        case let .htmlBlock(html):
            Text(html)
                .font(.system(size: style.baseFontSize, design: .monospaced))
                .foregroundColor(Color(nsColor: palette.tertiary))
                .fixedSize(horizontal: false, vertical: true)
        case let .image(_, alt):
            Text("[image: \(alt)]").foregroundColor(Color(nsColor: palette.muted))
        case let .codeBlock(language, code):
            CodeBlockView(palette: palette, style: style, language: language, code: code, highlighter: highlighter)
        case let .blockquote(children):
            BlockquoteView(palette: palette, style: style, blocks: children, highlighter: highlighter)
        case let .list(list):
            MarkdownListView(palette: palette, style: style, list: list, highlighter: highlighter)
        case let .table(table):
            MarkdownTableView(palette: palette, style: style, table: table)
        }
    }
}
```

> **Font-family note:** `palette.font` is a `FontKind` (system/mono/rounded/menu). v1 uses `.system`; threading `FontKind` into body/heading fonts (rounded/menu families) is a refinement — keep `bodyFont` as `.system(size:)` for v1 and leave a `// TODO(v1.x): map palette.font FontKind` only if you wire it; do NOT leave it unwired-but-claimed. (For this plan: ship `.system`; no TODO.)

- [ ] **Step 2: Add temporary stubs** for the four block views so this task compiles before Tasks 11–14. Create `Sources/MarkdownKitUI/_BlockStubs.swift`:

```swift
import SwiftUI
import MarkdownKit
import PaletteKit

// TEMP — replaced by Tasks 11–14. Each becomes its own file; delete the matching stub there.
struct CodeBlockView: View {
    var palette: ResolvedPalette; var style: MarkdownStyle
    var language: String?; var code: String; var highlighter: MarkdownHighlighter?
    var body: some View { Text(code) }
}
struct BlockquoteView: View {
    var palette: ResolvedPalette; var style: MarkdownStyle
    var blocks: [MarkdownBlock]; var highlighter: MarkdownHighlighter?
    var body: some View { Text("quote") }
}
struct MarkdownListView: View {
    var palette: ResolvedPalette; var style: MarkdownStyle
    var list: MarkdownList; var highlighter: MarkdownHighlighter?
    var body: some View { Text("list") }
}
struct MarkdownTableView: View {
    var palette: ResolvedPalette; var style: MarkdownStyle; var table: MarkdownTable
    var body: some View { Text("table") }
}
```

- [ ] **Step 3: Build.**

Run: `swift build`
Expected: SUCCEEDS.

- [ ] **Step 4: Commit.**

```bash
git add Sources/MarkdownKitUI
git commit -m ":sparkles: feat(MarkdownKitUI): MarkdownView shell + simple blocks

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 11: CodeBlockView

**Files:**
- Create: `Sources/MarkdownKitUI/CodeBlockView.swift`
- Modify: `Sources/MarkdownKitUI/_BlockStubs.swift` (remove the `CodeBlockView` stub)

**Interfaces:**
- Consumes: `MarkdownStyle`, `MarkdownHighlighter`, `ResolvedPalette`.
- Produces: `struct CodeBlockView: View` (same stored properties as the stub).

- [ ] **Step 1: Implement.**

```swift
import SwiftUI
import MarkdownKit
import PaletteKit

struct CodeBlockView: View {
    var palette: ResolvedPalette
    var style: MarkdownStyle
    var language: String?
    var code: String
    var highlighter: MarkdownHighlighter?

    private var monoFont: Font { .system(size: style.baseFontSize, design: .monospaced) }

    private var rendered: AttributedString {
        if let highlighter, let hl = highlighter.highlight(code, language: language) { return hl }
        var plain = AttributedString(code)
        plain.font = monoFont
        plain.foregroundColor = Color(nsColor: palette.foreground)
        return plain
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.system(size: style.baseFontSize * 0.78, design: .monospaced))
                    .foregroundColor(Color(nsColor: palette.tertiary))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(rendered).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: style.codeCornerRadius)
            .fill(Color(nsColor: palette.surface(.inset))))
        .overlay(RoundedRectangle(cornerRadius: style.codeCornerRadius)
            .stroke(Color(nsColor: palette.border), lineWidth: 0.5))
    }
}
```

- [ ] **Step 2: Remove the `CodeBlockView` stub** from `_BlockStubs.swift`.

- [ ] **Step 3: Build.** Run: `swift build` → Expected: SUCCEEDS (no duplicate `CodeBlockView`).

- [ ] **Step 4: Commit.**

```bash
git add Sources/MarkdownKitUI
git commit -m ":sparkles: feat(MarkdownKitUI): CodeBlockView (themed chrome + highlighter hook)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 12: BlockquoteView

**Files:**
- Create: `Sources/MarkdownKitUI/BlockquoteView.swift`
- Modify: `Sources/MarkdownKitUI/_BlockStubs.swift` (remove the `BlockquoteView` stub)

**Interfaces:**
- Consumes: `MarkdownView` (re-enters the dispatch by rendering children through a nested `MarkdownView` with `textColor: tertiary`). The left bar is a `Rectangle`.
- Produces: `struct BlockquoteView: View`.

- [ ] **Step 1: Implement.** `ResolvedPalette` is immutable (`let` fields), so quote-body recolor is threaded via `MarkdownView.textColor`, not a palette copy:

```swift
import SwiftUI
import MarkdownKit
import PaletteKit

struct BlockquoteView: View {
    var palette: ResolvedPalette
    var style: MarkdownStyle
    var blocks: [MarkdownBlock]
    var highlighter: MarkdownHighlighter?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(Color(nsColor: palette.primary))
                .frame(width: 3)
            MarkdownView(palette: palette, blocks: blocks, style: style,
                         highlighter: highlighter,
                         textColor: Color(nsColor: palette.tertiary))
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
```

- [ ] **Step 2: Remove the `BlockquoteView` stub** from `_BlockStubs.swift`.

- [ ] **Step 3: Build.** Run: `swift build` → Expected: SUCCEEDS.

- [ ] **Step 4: Commit.**

```bash
git add Sources/MarkdownKitUI
git commit -m ":sparkles: feat(MarkdownKitUI): BlockquoteView (left bar, nested)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 13: MarkdownListView (ordered/unordered/task/nested)

**Files:**
- Create: `Sources/MarkdownKitUI/MarkdownListView.swift`
- Modify: `Sources/MarkdownKitUI/_BlockStubs.swift` (remove the `MarkdownListView` stub)

**Interfaces:**
- Consumes: `MarkdownList`, `phosphorImage(_:pt:weight:)` (ThemeKit, confirmed signature: first arg UNLABELED, `weight` defaults to `.regular`, `@MainActor`, returns `NSImage?`) for task checkboxes.
- Produces: `struct MarkdownListView: View`.

- [ ] **Step 1: Vendor the two Phosphor slugs.** `check-square` and `square` are NOT yet in `Sources/ThemeKit/Resources/Phosphor/regular/` (only `squares-four` exists). Add both SVGs following `Sources/ThemeKit/Resources/README.md` (the documented one-step add: drop the Phosphor `regular` SVG into `Phosphor/regular/`). The ☑/☐ Unicode fallback below keeps the build green if you defer this, but v1 ships the Phosphor markers per the approved design.

- [ ] **Step 2: Implement.** Markers: ordered = `"\(start+i)."`, unordered = `"•"`, task = a Phosphor `check-square`/`square` image (☑/☐ fallback if the image is nil). Children render via a nested `MarkdownView`.

```swift
import SwiftUI
import MarkdownKit
import PaletteKit
import ThemeKit

struct MarkdownListView: View {
    var palette: ResolvedPalette
    var style: MarkdownStyle
    var list: MarkdownList
    var highlighter: MarkdownHighlighter?

    var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing / 2) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    marker(for: item, index: i)
                        .frame(width: style.listIndent, alignment: .trailing)
                    MarkdownView(palette: palette, blocks: item.blocks, style: style, highlighter: highlighter)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(for item: MarkdownListItem, index i: Int) -> some View {
        if let checkbox = item.checkbox {
            let slug = checkbox == .checked ? "check-square" : "square"
            if let img = phosphorImage(slug, pt: style.baseFontSize) {
                Image(nsImage: img)
                    .renderingMode(.template)
                    .foregroundColor(Color(nsColor: palette.foreground))
            } else {
                Text(checkbox == .checked ? "☑" : "☐").foregroundColor(Color(nsColor: palette.foreground))
            }
        } else if list.ordered {
            Text("\(list.start + i).")
                .font(.system(size: style.baseFontSize))
                .foregroundColor(Color(nsColor: palette.foreground))
        } else {
            Text("•")
                .font(.system(size: style.baseFontSize))
                .foregroundColor(Color(nsColor: palette.foreground))
        }
    }
}
```

> `phosphorImage` is `@MainActor` and returns `NSImage?`; call it from the View body (already `@MainActor`). It loads from `Phosphor/<weight>/`, so the slugs from Step 1 must be in `Phosphor/regular/`.

- [ ] **Step 3: Remove the `MarkdownListView` stub** from `_BlockStubs.swift`.

- [ ] **Step 4: Build.** Run: `swift build` → Expected: SUCCEEDS.

- [ ] **Step 5: Commit.**

```bash
git add Sources/MarkdownKitUI Sources/ThemeKit/Resources
git commit -m ":sparkles: feat(MarkdownKitUI): MarkdownListView (ordered/task/nested + Phosphor)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 14: MarkdownTableView (LazyVGrid)

**Files:**
- Create: `Sources/MarkdownKitUI/MarkdownTableView.swift`
- Modify: `Sources/MarkdownKitUI/_BlockStubs.swift` (remove the `MarkdownTableView` stub; the file may now be empty — delete it if so)

**Interfaces:**
- Consumes: `MarkdownTable`, `themedInline`.
- Produces: `struct MarkdownTableView: View`.

- [ ] **Step 1: Implement.**

```swift
import SwiftUI
import MarkdownKit
import PaletteKit

struct MarkdownTableView: View {
    var palette: ResolvedPalette
    var style: MarkdownStyle
    var table: MarkdownTable

    private var columnCount: Int { max(table.columns.count, table.header.count) }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: max(columnCount, 1))
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<table.header.count, id: \.self) { c in
                cell(table.header[c], column: c, header: true)
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                ForEach(0..<row.count, id: \.self) { c in
                    cell(row[c], column: c, header: false)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: style.tableCornerRadius)
            .stroke(Color(nsColor: palette.border)))
        .clipShape(RoundedRectangle(cornerRadius: style.tableCornerRadius))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func alignment(_ c: Int) -> Alignment {
        guard c < table.columns.count else { return .leading }
        switch table.columns[c] {
        case .center: return .center
        case .right: return .trailing
        case .left, .none: return .leading
        }
    }
    private func textAlignment(_ c: Int) -> TextAlignment {
        guard c < table.columns.count else { return .leading }
        switch table.columns[c] {
        case .center: return .center
        case .right: return .trailing
        case .left, .none: return .leading
        }
    }

    @ViewBuilder
    private func cell(_ content: AttributedString, column c: Int, header: Bool) -> some View {
        let baseFont = Font.system(size: style.baseFontSize).weight(header ? .semibold : .regular)
        Text(themedInline(content, palette: palette, style: style, baseFont: baseFont,
                          textColor: Color(nsColor: palette.foreground)))
            .multilineTextAlignment(textAlignment(c))
            .frame(maxWidth: .infinity, alignment: alignment(c))
            .padding(6)
            .background(header ? Color(nsColor: palette.surface(.inset)) : Color.clear)
            .overlay(Rectangle().stroke(Color(nsColor: palette.border), lineWidth: 0.5))
    }
}
```

- [ ] **Step 2: Remove the `MarkdownTableView` stub** (delete `_BlockStubs.swift` if now empty).

- [ ] **Step 3: Build.** Run: `swift build` → Expected: SUCCEEDS. `MarkdownKitUI` is now feature-complete.

- [ ] **Step 4: Commit.**

```bash
git add Sources/MarkdownKitUI
git commit -m ":sparkles: feat(MarkdownKitUI): MarkdownTableView (LazyVGrid GFM table)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 15: prism showcase — replace the static MockMarkdown with the real renderer

**Files:**
- Create: `Sources/prism/MarkdownShowcase.swift`
- Modify: `Sources/prism/Specimens.swift` (remove the old static `MockMarkdown`, lines ~372–402)
- Modify: `Sources/prism/Gallery.swift` (register under `.glance`)
- Modify: `Sources/prism/KitCatalog.swift` (add a `MarkdownView` entry)

**Interfaces:**
- Consumes: `MarkdownView`, `ResolvedPalette`.
- Produces: `struct MockMarkdown: View` (init `MockMarkdown(p:)`).

- [ ] **Step 1: Read the current wiring** to match the exact patterns:
  - `Sources/prism/Specimens.swift` around the existing `MockMarkdown` (≈ lines 372–402) — note the surrounding `SpecimenBox`/section helper it uses.
  - `Sources/prism/Gallery.swift` — find the `case .glance:` (or the family switch) and the `WidgetSection(kitComponent("…"), p: p) { Mock…(p: p) }` shape.
  - `Sources/prism/KitCatalog.swift` — find a `KitComponent(...)` entry to mirror.

- [ ] **Step 2: Create `MarkdownShowcase.swift`** with a fixture exercising every element:

```swift
import SwiftUI
import PaletteKit
import MarkdownKitUI

struct MockMarkdown: View {
    let p: ResolvedPalette

    private static let fixture = """
    # Heading 1
    ## Heading 2

    Body with **bold**, _italic_, ~~struck~~, `inline code`, and a [link](https://example.com).

    > A blockquote
    > > nested deeper

    - bullet one
    - [ ] todo
    - [x] done
        - nested item

    1. first
    2. second

    ```swift
    let greeting = "hello"
    print(greeting)
    ```

    | Left | Center | Right |
    |:-----|:------:|------:|
    | a    | b      | c     |

    ---

    Trailing paragraph.
    """

    var body: some View {
        MarkdownView(palette: p, source: Self.fixture)
            .frame(maxWidth: 360, alignment: .leading)
    }
}
```

- [ ] **Step 3: Remove the old static `MockMarkdown`** from `Specimens.swift` (the hardcoded `Text`/`HStack` version). Ensure no other file references the old symbol (grep `MockMarkdown`).

- [ ] **Step 4: Register in `Gallery.swift`** under the `.glance` family, mirroring the existing `WidgetSection` shape, e.g.:

```swift
case .glance:
    appCaption(.glance, p: p)
    WidgetSection(kitComponent("MarkdownView"), p: p) { MockMarkdown(p: p) }
```

(Match the ACTUAL helper names found in Step 1 — `appCaption`/`kitComponent`/`WidgetSection` may differ; use what the file uses.)

- [ ] **Step 5: Add the catalog entry in `KitCatalog.swift`,** mirroring an existing `KitComponent`:

```swift
KitComponent("MarkdownView", module: "MarkdownKitUI", /* match the other args */)
```

- [ ] **Step 6: Build.** Run: `swift build` → Expected: SUCCEEDS (prism links MarkdownKitUI).

- [ ] **Step 7: Commit.**

```bash
git add Sources/prism
git commit -m ":sparkles: feat(prism): live MarkdownView showcase across all themes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 16: Live verification in prism (the real gate)

**Files:** none (verification only).

- [ ] **Step 1: Launch prism on the glance family tab** (per the prism-bench recipe; do NOT `osascript`-activate — it jumps Spaces and flakes capture):

```bash
swift build
PRISM_CONFIG=/path/to/a/config.toml .build/debug/prism &
# get the window id matching "prism", then:
# screencapture -l<winid> -o /tmp/markdown-<theme>.png
```

- [ ] **Step 2: Visually confirm across themes** (at least one dark/animated neon — e.g. neon-noir/biolume — and one light — e.g. github-light):
  - headings 1/2 show the section rule; h3–h6 plain
  - inline `code` has a flat tinted fill with breathing room; **legible** on the theme background
  - code block: rounded `surface(.inset)` fill + border + language label; horizontal scroll on long lines
  - blockquote: left bar in `primary`, body in `tertiary`, nested quote indents
  - lists: bullets, ordered numbers, task ☑/☐ (Phosphor), nested indent
  - table: rounded outer border, inner hairlines, header fill, column alignment (l/c/r) correct, no overflow clipping
  - hr renders as a 1px rule
  - **contrast OK** on every theme (no invisible text on its fill)

- [ ] **Step 3: Fix any visual breakage** found, rebuilding + recapturing until all themes read cleanly. Commit fixes individually with `:lipstick: fix(MarkdownKitUI): …`.

- [ ] **Step 4: Final build + (in CI) full test.**

Run: `swift build` → Expected: SUCCEEDS.
In CI: `swift test` → Expected: all `MarkdownKitTests` PASS.

---

## Task 17: Wrap-up — PR

**Files:** none.

- [ ] **Step 1: Push the branch + open a PR.**

```bash
git push -u origin worktree-markdownkit
gh pr create --title ":sparkles: feat(MarkdownKit,MarkdownKitUI,prism): SwiftUI-native GFM markdown renderer (#17f)" --body "<summary + the SetStatus-task footer>"
```

- [ ] **Step 2: PR body footer (required):**

```
SetStatus-task: https://github.com/akira-toriyama/projects/blob/main/.furrow/bodies/t-vyt6.md in-progress
```

- [ ] **Step 3: When CI is green + clean** (per the standing green→merge OK for self-driven sill PRs): squash-merge, then **tag the new minor `v`-version** — first re-check `git tag` and that the version isn't already claimed (#91/#92 may have tagged in the meantime), then `git tag vX.Y.0 && git push origin vX.Y.0`. Update the furrow board lane via the PR footer (merge → `done`/applicable lane).

---

## Self-Review (completed during planning)

- **Spec coverage:** every spec section maps to a task — module split + Package (T1), model (T2), parse inline+blocks+code+lists+quote+table (T3–T7), Style+highlighter (T8), inline styling (T9), render shell+blocks (T10–T14), prism showcase (T15), live verify (T16), PR/tag (T17). v1 out-of-scope items (highlighting impl, measured columns, true pill, real images, footnotes, doc-wide selection) are intentionally NOT tasked.
- **Placeholder scan:** no "TBD"/"add error handling"-style placeholders. Verified against source during planning: `ResolvedPalette` fields are `let` (immutable) → quote recolor threaded via `MarkdownView.textColor` (not a palette copy); `phosphorImage(_ name:pt:weight:)` signature confirmed (first arg unlabeled, `weight` defaults); `check-square`/`square` slugs are NOT vendored → Task 13 Step 1 adds them (☑/☐ fallback retained). Remaining verify-against-source: the prism helper names (`WidgetSection`/`kitComponent`/`appCaption`/`KitComponent`/`.glance`) — Task 15 Step 1 reads them first, with a concrete fallback.
- **Type consistency:** model names (`MarkdownBlock`/`MarkdownList`/`MarkdownListItem.Checkbox`/`MarkdownTable.Alignment`), `parseMarkdown`, `inlineAttributed`, `themedInline`, the four block-view structs and their stored-property shapes match between definition (T2/T9/T10) and use (T10–T15).
