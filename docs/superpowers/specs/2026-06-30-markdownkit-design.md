# MarkdownKit — SwiftUI-native GFM markdown renderer (sill #17f)

- **Date**: 2026-06-30
- **Status**: design approved (brainstorming), pre-implementation
- **Task**: furrow `t-vyt6` / ROADMAP #17f — PREREQ for glance Phase B (#22)
- **Version target**: minor bump + matching `v`-tag, decided at merge time. (Latest *published* tag is `v1.38.0`, but #91/#92 are merged-but-untagged on `origin/main` — re-check `git tag` and verify the version isn't already claimed before tagging.)
- **Base**: branch off clean `origin/main` (≥ #91 `surface(.inset)` / #92). Worktree-isolated per the concurrent-work hazard.

## 1. Goal & context

Build a **SwiftUI-native GFM markdown renderer** as a reusable sill module, so glance (and any future app) renders markdown with sill theming instead of hand-drawing it. This is the **prereq for glance Phase B** (#22): glance today renders markdown in a pure-AppKit `MarkdownRenderer` (`NSAttributedString` in an `NSTextView`, with `NSTextTable` fakes for code/quote/table backgrounds and Highlightr for syntax colors). MarkdownKit replaces that with a SwiftUI-native renderer that satisfies sill's **AppKit 使用可ポリシー** (AppKit allowed only for the IME field-editor core + the non-activating window shell; a markdown renderer is neither, so it must be 100% SwiftUI — no `NSTextView`/`NSAttributedString`-backed rendering, GFM tables via `LazyVGrid`).

**Consumer reality**: today the only consumer is glance (rule-of-three not yet met); this build is explicitly approved as the glance Phase B prerequisite, and is built **general/best-first** (per the build-best-then-migrate principle) so facet/wand can adopt it later. glance's current renderer is the **design reference** — it defines the feature coverage and the role→color mapping to reproduce — not a byte-for-byte target (visuals are re-designed SwiftUI-native).

## 2. Confirmed decisions (brainstorming)

| # | Decision | Choice |
|---|---|---|
| 1 | **v1 feature scope** | **Full GFM** (parity with glance's coverage) |
| 2 | **inline code rendering** | **Flat tinted background + hairspace padding**, kept inside a single `Text(AttributedString)` → preserves native wrapping + drag-selection. No rounded pill (SwiftUI `Text` run-background can't round; a true pill needs a custom flow `Layout` that degrades selection — deferred). |
| 3 | **syntax highlighting** | **Injectable hook protocol**; v1 ships **plain themed monospaced** (no built-in highlighter). Keeps sill JS-free (Highlightr is JavaScriptCore + `NSAttributedString` → violates the AppKit-floor policy). glance can inject an app-side adapter; a future native Swift highlighter can plug in here. |
| 4 | **module structure** | Two layers: pure **`MarkdownKit`** (parse → model) + **`MarkdownKitUI`** (SwiftUI render), mirroring ThemeKit/ThemeKitUI. |
| 5 | **theming** | Canonical `ResolvedPalette` roles only (no new role names). |
| 6 | **heading sizes** | MarkdownKit defines its own ramp (sill `TypeRole` maxes at 13pt, no heading token). |
| 7 | **selection** | Per-block `.textSelection(.enabled)` (SwiftUI's native ceiling; whole-document continuous selection is impossible without an AppKit text view = policy violation). |

## 3. Architecture — two modules

Mirrors sill's pure/AppKit dependency-graph split (the split is enforced by the dependency graph, not a flag).

```
MarkdownKit      (pure)     deps: [Markdown]            — swift-markdown only; zero AppKit, Sendable
   │  parseMarkdown(String) -> [MarkdownBlock]
   ▼
MarkdownKitUI    (SwiftUI)  deps: [MarkdownKit, PaletteKit, Palette, ThemeKit]
      MarkdownView: View    — renders [MarkdownBlock] + ResolvedPalette + MarkdownStyle
```

- **`MarkdownKit`** (pure): the only dependency is `apple/swift-markdown`. Parses source → a `Sendable` block model whose inline content is a Foundation `AttributedString` carrying **semantic intents only** (no colors). Links zero AppKit, so a non-UI consumer never pulls SwiftUI/AppKit.
- **`MarkdownKitUI`** (SwiftUI): renders the model. Depends on `PaletteKit`/`Palette` (for `ResolvedPalette` role colors + `surface(.inset)`) and `ThemeKit` (for `phosphorImage` — task-list checkboxes).

### Package.swift wiring

- New external dep: `.package(url: "https://github.com/apple/swift-markdown.git", …)` — Apache-2.0, wraps the cmark-gfm C lib, pure Swift; compiles on CommandLineTools (so `swift build` — the local gate — works). Pin conservatively, mirroring the SwiftDraw `< 0.25.0` CLT-safety precedent; choose a `.upToNextMinor` pin on a verified-building version.
- New targets:
  - `.target(name: "MarkdownKit", dependencies: [.product(name: "Markdown", package: "swift-markdown")])`
  - `.target(name: "MarkdownKitUI", dependencies: ["MarkdownKit", "PaletteKit", "Palette", "ThemeKit"])`
- New products: `.library(name: "MarkdownKit", …)`, `.library(name: "MarkdownKitUI", …)`.
- `prism` executable target gains `"MarkdownKit", "MarkdownKitUI"` deps.
- Platform floor unchanged: `macOS(.v13)`.

## 4. Parse layer — `MarkdownKit`

Walk swift-markdown's `Document` with a `MarkupVisitor`/`MarkupWalker` and emit:

```swift
public enum MarkdownBlock: Sendable, Equatable {
    case heading(level: Int, content: AttributedString)   // level 1...6 (clamped)
    case paragraph(AttributedString)
    case codeBlock(language: String?, code: String)       // raw; highlighting happens at render time
    case blockquote([MarkdownBlock])                      // nested children recurse
    case list(MarkdownList)
    case table(MarkdownTable)
    case thematicBreak
    case htmlBlock(String)                                // raw HTML passed through, rendered monospaced (glance parity)
    case image(source: String, alt: String)              // v1: stub text, no fetch
}

public struct MarkdownList: Sendable, Equatable {
    public var ordered: Bool
    public var start: Int                                 // ordered start index (1 default)
    public var items: [MarkdownListItem]
}
public struct MarkdownListItem: Sendable, Equatable {
    public enum Checkbox: Sendable, Equatable { case checked, unchecked }
    public var checkbox: Checkbox?                        // nil ⇒ plain bullet/number
    public var blocks: [MarkdownBlock]                    // nested lists/paragraphs recurse here
}
public struct MarkdownTable: Sendable, Equatable {
    public enum Alignment: Sendable, Equatable { case left, center, right, none }
    public var columns: [Alignment]
    public var header: [AttributedString]
    public var rows: [[AttributedString]]
}

public func parseMarkdown(_ source: String) -> [MarkdownBlock]
```

**Inline mapping** — the inline AST (`Text`/`Strong`/`Emphasis`/`Strikethrough`/`InlineCode`/`Link`/`SoftBreak`/`LineBreak`) is flattened into one `AttributedString` per paragraph/heading/cell, using Foundation attributes:
- `Strong` → `inlinePresentationIntent = .stronglyEmphasized`
- `Emphasis` → `.emphasized`
- `Strikethrough` (GFM) → `.strikethrough`
- `InlineCode` → `.code`
- `Link` → `.link = URL(string: destination)` (+ `.code` etc. compose)
- `SoftBreak` → space; `LineBreak` → newline

Colors and fonts are **not** baked here — the render layer maps these intents to role colors + fonts. This keeps each paragraph a single `Text(AttributedString)` (native selection/wrapping) and keeps the model palette-free + Sendable.

## 5. Render layer — `MarkdownKitUI`

```swift
public struct MarkdownView: View {
    public var palette: ResolvedPalette
    public var blocks: [MarkdownBlock]                    // or an init that takes source: String and parses
    public var style: MarkdownStyle = .default
    public var highlighter: MarkdownHighlighter? = nil
    public var body: some View { … }                     // VStack(alignment: .leading) over blocks; .textSelection(.enabled)
}
```

Pure SwiftUI (modeled on `ThemedPillView`): `palette` is a stored property; role colors bridge at each use site via `Color(nsColor: palette.<role>)` (the existing repo convention — no shared bridge helper added).

### Per-block rendering (all `Text` + shapes; zero `NSView`)

| Block | SwiftUI structure |
|---|---|
| heading | `Text(attr).font(headingFont(level))` + top padding; **h1/h2** get a trailing `Rectangle().frame(height:1).foregroundStyle(border)` GitHub-style section rule |
| paragraph | `Text(attr).fixedSize(horizontal:false, vertical:true)` |
| code block | `Text(rendered).font(.system(.body, design:.monospaced))` → `.padding(10).background(RoundedRectangle(cornerRadius: style.codeCornerRadius).fill(surface(.inset))).overlay(stroke(border))`; long lines wrap in `ScrollView(.horizontal)`; optional language label small in a corner |
| blockquote | `HStack(spacing:8){ Rectangle().fill(primary).frame(width:3); VStack{ recurse children } }` (left bar = Rectangle, not an AppKit widget); nested quotes recurse |
| list | per item `HStack(alignment:.firstTextBaseline){ marker.frame(width: markerWidth, alignment:.trailing); VStack{ item.blocks } }`; nested lists add leading padding |
| task list | marker swapped for Phosphor `check-square` / `square` via `phosphorImage` (template-tinted to `foreground`) |
| table | `LazyVGrid` (below) |
| hr | `Rectangle().fill(border).frame(height:1).padding(.vertical,4)` |
| html block | monospaced `Text`, `tertiary` (glance parity — no interpretation) |
| image | v1 stub: `Text("[image: \(alt)]")` in `muted` |

**inline code** (decision #2): inside the paragraph `Text`, the `.code` run gets a flat `surface(.inset)` background + hairspace padding + monospaced font. Flat (no corner radius), single `Text`, native selection retained.

### GFM table — `LazyVGrid`

- Columns: v1 = `Array(repeating: GridItem(.flexible(), spacing: 0), count: columnCount)` (equal width). Per-cell alignment from `MarkdownTable.Alignment` → `.leading/.center/.trailing` on both `frame(alignment:)` and `.multilineTextAlignment`.
- Cell: `cellText.frame(maxWidth:.infinity, alignment:).padding(6).overlay(Rectangle().stroke(border, lineWidth: 0.5))` — adjacent strokes form the inner grid.
- Outer shape: wrap the grid with `.overlay(RoundedRectangle(cornerRadius: style.tableCornerRadius).stroke(border)).clipShape(RoundedRectangle(cornerRadius: style.tableCornerRadius))`.
- Header row: first `columnCount` cells get `.fontWeight(.semibold)` + `.background(surface(.inset))`.
- **v1 limitation (documented)**: equal-width columns do **not** auto-fit content width (CJK-wide cells included). Content-measured columns (PreferenceKey + GeometryReader two-pass) are **v2**. Wide tables overflow into a horizontal `ScrollView`.

### Theming — canonical roles only

| Element | Role |
|---|---|
| body / heading / list / code text | `foreground` |
| link | `primary` (underline + `.tint(primary)`) |
| inline-code bg / code-block bg / table-header bg | `surface(.inset)` (= ink `.subtle`, PR #91) |
| blockquote left bar | `primary`; blockquote body text | `tertiary` |
| table border / cell hairline / hr / h1·h2 rule | `border` |

### `MarkdownStyle` (typography only — colors come from the palette)

```swift
public struct MarkdownStyle: Sendable {
    public var baseFontSize: CGFloat = 13
    public var headingScales: [CGFloat] = [1.75, 1.45, 1.25, 1.12, 1.05, 1.0]  // h1..h6 × base (glance parity)
    public var blockSpacing: CGFloat = 8
    public var listIndent: CGFloat = 18
    public var codeCornerRadius: CGFloat = 8
    public var tableCornerRadius: CGFloat = 6
    public static let `default` = MarkdownStyle()
}
```
(glance's dead `codeBlockIndent` / `blockquoteIndent` fields are **not** carried over.)

### Highlighter hook (decision #3)

```swift
public protocol MarkdownHighlighter: Sendable {
    /// Return styled runs for a code block, or nil to fall back to plain themed monospaced.
    func highlight(_ code: String, language: String?) -> AttributedString?
}
```
`MarkdownView.highlighter` defaults to `nil` ⇒ plain themed monospaced. sill ships no built-in highlighter in v1; glance may inject an app-side adapter; a future native Swift highlighter plugs in here.

## 6. v1 scope boundaries

**In v1 (full-GFM parity):** headings 1–6 (h1/h2 rule), paragraphs, bold/italic/strikethrough, inline code (flat + padding), links, code blocks (plain themed mono + chrome + language label), blockquotes (nested), ordered/unordered/**task** lists, nested lists, **GFM tables** (equal-width + alignment + rounded frame), thematic break, raw HTML (monospaced passthrough), images (stub).

**Out of v1 (with un-defer triggers noted):**
1. Built-in syntax highlighting — hook only (un-defer: a native Swift highlighter, or glance ships an adapter).
2. Content-measured table columns / CJK auto-fit (un-defer: a table where equal-width visibly breaks).
3. True rounded inline-code pill via custom flow `Layout` (un-defer: a taste call to accept selection degradation).
4. Real image loading (`AsyncImage`) (un-defer: an app needs inline images in a persistent — not transient — surface).
5. Footnotes.
6. Whole-document continuous text selection (SwiftUI cannot deliver without an AppKit text view = policy violation requiring 相談).

## 7. prism showcase

- New `Sources/prism/MarkdownShowcase.swift`: replace the existing **static** `MockMarkdown` (in `Specimens.swift`) with a `MockMarkdown(p:)` that renders the **real** `MarkdownView` over a fixed fixture document exercising every element. Remove the old static mock.
- Register: add `WidgetSection(kitComponent("MarkdownView"), p:) { MockMarkdown(p:) }` under the `.glance` family in `Gallery.swift`, and a `KitComponent("MarkdownView", module: "MarkdownKitUI", …)` entry in `KitCatalog.swift`.
- Verify **live in prism across all themes** (the visual bench is the real gate; per house policy `swift test` doesn't run on the CLT-only maintainer machine). Check neon/dark + light themes for table breakage, contrast, code-block legibility.

## 8. Testing

- `Tests/MarkdownKitTests/` (XCTest): parse-layer focused — `md → expected [MarkdownBlock]` and inline run attributes (emphasis/strong/strikethrough/code/link URL/checkbox/column alignment). Port + extend glance's `MarkdownRendererTests` assertions. Runs in CI (`swift test` needs full Xcode); locally the gate is `swift build`.
- Render layer: correctness proven **live in prism** (no off-screen SwiftUI snapshot infra in sill today).

## 9. Implementation notes

- Work in a worktree off clean `origin/main` (already includes #91 `surface(.inset)` / #92).
- Build sequence suggestion: (1) Package.swift + empty targets compile; (2) parse layer + XCTest; (3) render layer block-by-block, building against prism for live feedback; (4) prism showcase swap; (5) full live theme sweep.
- Commit style: gitmoji + Conventional Commits, `:sparkles: feat(MarkdownKit,MarkdownKitUI,prism): …`. PR footer `SetStatus-task: …/bodies/t-vyt6.md <lane>`.
