# sill #17f — MarkdownKitUI re-architected on NSTextView (selectable + inline-code pill)

Date: 2026-06-30 · Task: [t-xt11] (grew out of the glance prism-mock arm of [t-yc68])
Supersedes: `2026-06-30-17f-inline-code-pill-design.md` (the SwiftUI `TextRenderer`
approach — rejected; see **Rejected alternatives**).

## Why this exists

t-xt11 began as "round the inline-code background." Building it live surfaced a hard
SwiftUI limitation: **`.textSelection(.enabled)` and `.textRenderer` are mutually
exclusive** — selectable text bypasses a custom `TextRenderer`, so the rounded pill
never paints when the markdown is selectable (proven live in prism: removing
`.textSelection` made the pill appear; restoring it erased it). The markdown popover
**must** stay selectable/copyable (maintainer confirmed 2026-06-30), so pure-SwiftUI
cannot deliver pill **and** selection at once.

glance already solves exactly this with AppKit: one `NSTextView` (TextKit 1) gives
native continuous selection, and an `NSLayoutManager.fillBackgroundRectArray`
override rounds the inline-code background into a pill. The maintainer chose to adopt
that approach in sill and **widen the AppKit policy from 床2個 → 床3個** to allow a
selectable rich-text rendering core (see **Rule update**).

This is therefore not a small inline tweak but a **re-architecture of MarkdownKitUI's
render layer** from SwiftUI (`Text`/`VStack`, #17f / PR #93) to an `NSTextView`-backed
renderer ported from glance. MarkdownKitUI has **no app consumer yet** (prism-only —
apps link only sill's pure engine), so it can be redesigned freely with no back-compat
obligation ([[build-best-then-migrate]]).

## Goal (done-when)

- `MarkdownView(palette:source:highlighter:)` renders GFM into a **selectable,
  copyable** `NSTextView`, with inline code drawn as a rounded pill (cornerRadius 4).
- Drag-select across the whole document (including across inline code and into
  tables) works natively; ⌘C copies; ⌘F find bar works.
- Tables, code blocks, and blockquotes render with real `NSTextTable` rules/fills
  (CJK-safe columns), matching glance.
- Themed entirely by `ResolvedPalette` roles (no glance-specific fixed preset); every
  prism catalog theme re-themes by reassigning the palette.
- No macOS-15 gate and no floor bump: TextKit 1 works on the current macOS floor
  (13+).
- The prism glance/markdown showcase shows the live pill + selection across themes.

## Architecture

Three ported units land in `MarkdownKitUI`, plus a thin SwiftUI bridge:

### 1. `MarkdownRenderer` — GFM AST → `NSAttributedString` (ported from glance)

A `MarkupVisitor` (swift-markdown — already a sill dep) that flattens the whole
document into ONE `NSMutableAttributedString`. Ported near-verbatim from glance's
[MarkdownRenderer.swift](../../../../glance/Sources/GlanceAdapterMacOS/MarkdownRenderer.swift)
(proven; handles the `NSTextTable` intricacies for code blocks, blockquotes, and GFM
tables that a hand-rewrite would re-derive). Element mapping is unchanged from glance:

- inline: text / strong / emphasis / strikethrough / **inline code (`.backgroundColor`
  attr → pill)** / link / image-stub / inline-HTML passthrough
- block: paragraph / heading (h1–h6, h1·h2 underline) / **code block (1-cell
  `NSTextTable`, language label, syntax highlight)** / **blockquote (1-cell
  `NSTextTable`, left bar)** / lists (ordered/unordered/task, `headIndent`) / thematic
  break / HTML-block passthrough / **GFM table (`NSTextTable`, real borders)**

Two glance couplings are swapped for sill seams:

- **Colors** come from a `Style` whose fields are `ResolvedPalette` roles + `ink` tiers
  (glance's `rendererStyle` recipe, [ViewerPanel.swift:236-254](../../../../glance/Sources/GlanceAdapterMacOS/ViewerPanel.swift#L236-L254)):
  `foreground · tertiary · primary · border`, `inlineCodeBackground = ink(.wash, of:
  .foreground)`, `codeBlockBackground / tableHeaderBackground / headingUnderline =
  ink(.subtle, of: .foreground)`, `tableOuterBorder = ink(.wash, of: .foreground)`,
  `blockquoteBar = ink(.strong, of: .foreground)`.
- **Syntax highlighting** uses sill's pluggable `MarkdownHighlighter` protocol (returns
  `AttributedString?`), NOT glance's hard Highlightr dependency. The renderer bridges
  the result via `NSAttributedString(highlighted)` and applies glance's post-process
  (strip the highlighter's own `.backgroundColor`, unify to the mono font at
  `baseFontSize` while keeping bold/italic traits). `nil` ⇒ plain themed mono. **No
  Highlightr dependency is added to sill**; glance keeps its Highlightr-backed
  implementation, prism injects a stub.

### 2. `InlineCodePillLayoutManager` — the pill (ported from `GlanceLayoutManager`)

`NSLayoutManager` subclass overriding `fillBackgroundRectArray` to draw
`.backgroundColor` ranges (= inline code) as an `NSBezierPath(roundedRect:)` pill
(cornerRadius 4, horizontalInset −3). Tables/code blocks/blockquotes paint via
`paragraphStyle.textBlocks` (a separate path), so they stay rectangular — only inline
code rounds. Verbatim port + rename.

### 3. `MarkdownTextView` — the `NSViewRepresentable` host

Wraps the TextKit 1 stack from glance's [ViewerPanel.swift:177-208](../../../../glance/Sources/GlanceAdapterMacOS/ViewerPanel.swift#L177-L208):
`NSTextStorage` → `InlineCodePillLayoutManager` → `NSTextContainer`
(`widthTracksTextView`) → `NSTextView` inside an `NSScrollView`. Config:
`isEditable=false · isSelectable=true · drawsBackground=false · usesFindBar=true ·
textContainerInset`. `updateNSView` re-renders + re-applies on palette/source change
(the theming contract: reassign palette → rebuild attributed string). The window/panel
shell, positioning, fade, and dismiss are **NOT** ported — those are app-side (sill
#17i WindowShell). This host is content-only, embeddable in any SwiftUI hierarchy.

### 4. `MarkdownView` — the public SwiftUI front (unchanged call site)

`MarkdownView(palette:source:style:highlighter:textColor:)` keeps its signature but
its body becomes `MarkdownTextView(...)` instead of the SwiftUI `VStack`. Consumers
(prism today) change minimally. `MarkdownStyle` carries the typography constants
(baseFontSize, lineSpacing, indents, paragraphSpacing, headingScales) that map into
`MarkdownRenderer.Style`.

## Retired vs reused

- **Retired** (replaced by the NSAttributedString renderer): `MarkdownView`'s SwiftUI
  block rendering, `BlockquoteView`, `CodeBlockView`, `MarkdownListView`,
  `MarkdownTableView`, `InlineStyling` (incl. the abandoned `TextRenderer` work on this
  branch).
- **Reused**: `MarkdownHighlighter` protocol; `MarkdownStyle` (extended for the new
  typography fields); swift-markdown dep; `PaletteKit`/`Palette` role colors;
  `ResolvedPalette.ink(_:of:)` tiers.
- **Parse layer decision**: the new renderer parses swift-markdown directly (glance's
  `Document(parsing:)` + visitor). sill's pure `MarkdownKit` model (`MarkdownBlock`,
  `InlineAttributed`, `MarkdownParser`) becomes unused once the SwiftUI views are
  retired. **Decision: retire `MarkdownBlock` + its `MarkdownKitTests`** (no consumer;
  keeping a second parse path that nothing reads is worse than removing it). If a pure
  non-UI markdown model is ever needed, re-introduce it then ([[build-best-then-migrate]]).
  MarkdownKit (pure target) is removed or emptied accordingly — confirm during impl
  whether the target is dropped or kept as a thin re-export.

## Rule update (床2個 → 床3個)

**`sill/CLAUDE.md` — "AppKit 使用可ポリシー"** gains a third allowed floor:

> 3. **選択可能なリッチテキスト描画（markdown 等）** — 連続選択/コピー + inline-code
>    の角丸ピル（`NSLayoutManager.fillBackgroundRectArray`）+ `NSTextTable` の本物の
>    表/コードブロック罫線。SwiftUI の `Text`/`textRenderer` は `.textSelection` と
>    **排他**で両立不可（2026-06-30 prism で実証）。AppKit は **NSTextView 描画コア
>    だけ**・配色/フォント/位置/データは sill role、窓殻は #17i WindowShell。

The existing line **「GFM 表 = SwiftUI `LazyVGrid`（薄 `NSTextView` backend は不可
＝IME/窓 以外の AppKit）」** is rewritten — the GFM table now lives inside the floor-3
`NSTextView` via `NSTextTable`. The closing "床2個" tallies become "床3個".

**`docs/ROADMAP.md`** #16.5/#17 AppKit-policy record gets the same third floor + the
2026-06-30 rationale (TextRenderer ⊥ textSelection; glance's NSTextView path adopted).

## Verification

- `swift build` = local gate (CLT-only host).
- XCTest: parse-layer tests retire with `MarkdownBlock`; add (CI-only) coverage for the
  role→`Style` mapping if it carries logic worth pinning. The render is visual.
- **Live in prism** (binding gate): glance/markdown showcase across **neon-noir
  (dark/animated)** + **github-light** + a neon sweep — confirm (1) the inline-code
  **pill**, (2) **drag-select + ⌘C** across the doc incl. inline code, (3) tables /
  code blocks / blockquotes render with real rules, (4) every theme re-themes.

## Rejected alternatives

- **① SwiftUI `TextRenderer` pill** (the superseded spec): pill works, but
  `.textSelection` disables the renderer → no pill when selectable. Proven live
  (red=every-run / green=code-run diagnostic visible only with selection OFF). Fails
  the selection requirement. Also needed macOS 15 + a future floor bump.
- **② Keep the flat square + selection** (status quo): selectable but no pill;
  abandons the maintainer's high-quality-pill goal.
- **NSViewRepresentable per prose paragraph (hybrid)**: keeps SwiftUI block chrome but
  selection breaks at block boundaries (each NSTextView selects independently) — worse
  UX than glance's single-textview continuous selection.

## Risks

- **Port surface is large (~700 lines).** Mitigated: near-verbatim from proven glance
  code; only the color + highlighter seams change.
- **AttributedString → NSAttributedString highlighter bridge** fidelity (font/color
  round-trip). Verify a highlighted code block in prism.
- **MarkdownStyle widening** ripples to prism call sites — small, contained.
- **Retiring MarkdownKit (pure)** — confirm nothing else imports it before removal
  (grep shows prism + tests only).

## Rollout (multi-session)

1. Rule update (CLAUDE.md + ROADMAP) — lands first so the floor-3 work is sanctioned.
2. Port `MarkdownRenderer` + `InlineCodePillLayoutManager` into MarkdownKitUI,
   role-mapped; keep `MarkdownHighlighter`.
3. `MarkdownTextView` representable + rewire `MarkdownView`; retire SwiftUI views +
   MarkdownBlock.
4. prism showcase + KitCatalog entry update; `swift build`; prism live verify.
