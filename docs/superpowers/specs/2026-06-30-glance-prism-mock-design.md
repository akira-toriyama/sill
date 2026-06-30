# glance prism app-mock — design (2026-06-30)

Task: **t-yc68** (sill: prism app-mock 再構築 — Phase B 適用の前段), glance arm.
Depends on already-shipped sill parts: **#17f MarkdownKit / MarkdownKitUI (PR #93)**
+ **#17i WindowShell (PR #88, t-dsqb)**.

## Goal

Rebuild glance's signature markdown-viewer chrome (a non-activating, borderless
rounded HUD panel that floats at the cursor and renders the selected text's GFM
markdown, scrollable, on a fixed dark preset) in the prism visual bench out of the
**real** `MarkdownKitUI.MarkdownView`, and confirm it composes across ALL catalog
themes — a cheap de-risk before glance's real application, mirroring the shipped
perch arm. prism imports no app View, so the scene is mirrored by eye (zero drift).
glance pins ONE dark theme (catppuccin-mocha) in production; the bench's payoff is
proving the same chrome themes generically on every catalog theme.

## Coverage finding (why this is cheap)

A code-level audit (glance `MarkdownRenderer.swift` / `ViewerPanel.swift` /
`GlanceLayoutManager.swift` ↔ sill `MarkdownKitUI` + `ThemeKit/WindowShell.swift`),
adversarially verified, found glance's viewer is **already feature-complete** on
the merged parts:

- **`MarkdownView` renders glance's ENTIRE GFM surface**: headings h1–h6 (+ h1/h2
  GitHub underline), bold/italic/strikethrough, inline code, links (clickable),
  image placeholder (`[image: alt]`), inline-HTML / HTML-block passthrough, fenced
  code blocks (lang label + a `MarkdownHighlighter` injection hook), blockquote
  (left bar, recursive/nested, tertiary ink), unordered / ordered / GFM task lists
  (nested), GFM tables (per-column alignment, header fill), thematic break — most
  matching glance's draw intent. (file:line pairs in the workflow coverage map.)
- **Theming is generic**: every glance role color collapses onto the canonical
  sill roles + `surface(.inset)` (= `ink(.subtle of foreground)`), so the renderer
  re-themes per palette with no glance-specific wiring.
- **WindowShell covers the floor**: `makeWindowShell` (HUD / titled / borderless
  nonactivating panel) + `ShellFade` (alpha fade) + `sizeShellToContent`
  (top-left-anchored auto-size + clamp) + `ShellDismissMonitor` (local Esc +
  outside-click) — glance's real panel shape.

The remaining differences are rendering-**technique** fidelity and app-essential
behaviour, not missing features.

## Gaps (verified)

1. **Table column sizing & ruling fidelity** — *real-gap, the strongest "true gap"
   (the perch-#17k analogue)*. glance uses a real `NSTextTable`: content-driven
   (CJK-safe) column widths, a 1.2 pt outer frame distinct from 0.5 pt inner cell
   hairlines (collapsed borders → only the frame reads dark), 8 pt cell padding.
   `MarkdownTableView` is a `LazyVGrid` with equal-`flexible` columns, a uniform
   0.5 pt stroke on every cell (no outer/inner weight), 6 pt padding, and **no
   horizontal scroll** for wide tables. Owner = **a new sill MarkdownKitUI task**
   (content-based column sizing + outer-frame weight + horizontal scroll is
   non-trivial LazyVGrid work; out of scope for this arm). Evidence: glance
   `MarkdownRenderer.swift:532-623`; sill `MarkdownTableView.swift:10-13,74,76`.

2. **Inline-code rounded pill vs flat fill** — *real-gap, needs a look call*.
   glance draws each inline-code run as a rounded pill (cornerRadius 4, −3 inset)
   via an `NSLayoutManager.fillBackgroundRectArray` override. `MarkdownKitUI` uses a
   **flat** `surface(.inset)` `backgroundColor` + U+200A hairspace padding (a
   deliberate substitute — SwiftUI `AttributedString` has no rounded run-background).
   Reproducing glance's pill needs an `NSLayoutManager` subclass over an NSTextView
   backend, which the **AppKit 使用可ポリシー (床2個)** forbids. So the flat fill is
   most likely the intended SwiftUI-native form; the alternative (a pure-SwiftUI
   rounded-run renderer that breaks text into a custom `Layout` of Text+RoundedRect
   pills) is real work and loses native text flow/selection. **Decision needed
   (look call): accept the flat fill as final, or invest in a SwiftUI rounded run.**
   Evidence: glance `GlanceLayoutManager.swift:10-39`; sill `InlineStyling.swift:30-39`.

3. **`forceDarkAqua` appearance pin** — *cosmetic, tiny shell-glue candidate*. glance
   sets `panel.appearance = .darkAqua` when `palette.forceDarkAqua`, so the system
   text-selection / find-bar / scroller chrome stays dark. The field exists on
   `ResolvedPalette` but `makeWindowShell` never reads it. Moving a tiny
   `forceDarkAqua → panel.appearance` convenience into `WindowShell` is a legit,
   not-yet-built follow-up. Evidence: glance `ViewerPanel.swift:143-145`; sill
   `WindowShell.swift:133-149`, `PaletteKit.swift:59`.

4. **`ShellDismissMonitor` keyboard/button parity** — *cosmetic, verifier-surfaced*.
   glance's local key monitor also dismisses on **⌘W** (the macOS close convention)
   and its outside-click monitor matches `.otherMouseDown` too; sill's
   `ShellDismissMonitor` handles only Esc and `.left/.rightMouseDown`. A small,
   safe add to the sill monitor. Evidence: glance `ViewerPanel.swift:297-314,291`;
   sill `WindowShell.swift:310-318`.

5. **No vertical scroll wrapper** — *by design, consumer's job*. `MarkdownView` is a
   bare stack; glance wraps its viewer in an `NSScrollView` and auto-sizes 80..600
   then scrolls. The consumer supplies the `ScrollView` for the overflow case. The
   mock sizes the panel to content (the common short-selection case).

6. **Block-spacing rhythm** — *cosmetic, NOT a simple knob (verifier-corrected)*.
   glance's vertical rhythm is per-block-type and font-size-relative (heading
   `paragraphSpacing` scales with size; code/hr have their own); `MarkdownView` uses
   a single uniform `blockSpacing`. Matching glance's exact rhythm would need new
   `MarkdownStyle` API, not just tuning the existing scalar. Low-stakes; defer.

7. **FontKind not threaded** — *cosmetic, sill-side refinement*. `MarkdownKitUI`
   hardcodes `Font.system`; glance also uses system font, so no divergence today.

## App-essential (stays in glance)

Cursor-anchored placement (`--at` as Cocoa top-left, screen-center fallback,
`clampToScreen` on all 4 edges); cross-app **global** click-outside dismiss +
one-shot dismiss→`NSApp.terminate` lifecycle; the 0.14 s fade duration constant;
the **Highlightr** concrete adapter (atom-one-dark, `--theme`, `--no-highlight`) —
the protocol hook is sill's, the JS/JSCore impl stays in glance; ⌘F find bar
(TextKit-1 affordance); the CLI grammar (`--hud / --sticky / --font-size / …`).

## Decision

Per the perch precedent (ship the covered range, name the one/few true gaps as
follow-ups): **ship `MockGlancePopover` now** (it proves chrome + full-element
render fidelity across every theme), record the gaps as separate sill tasks, and
surface the **inline-code flat-vs-rounded** look call to the maintainer. The
**table fidelity** gap is the strongest true gap — the glance analogue of perch's
#17k — and becomes its own sill MarkdownKitUI task.

## What we build

- **New file** `Sources/prism/GlanceShowcase.swift` housing
  `struct MockGlancePopover { let p: ResolvedPalette }` (+ a bench-only
  `StubSwiftHighlighter`), following the app-flavored showcase precedent
  `PerchShowcase.swift` / `HaloShowcase.swift`.
- **Replace + delete** the bare `MockMarkdown` (`MarkdownShowcase.swift`, a frame
  with no chrome). Repoint `case .glance:` (`Gallery.swift:388`) to
  `MockGlancePopover(p: p)`. (`MarkdownView`'s KitCatalog entry is already filed
  `family: .glance`, so markdown is glance's tab content by design — no Kit tab.)

### Scene composition (`MockGlancePopover`)

A faux text **selection** strip (faint bars + one `selection`-tinted run) over a
**floating HUD panel** (the `MockWindowShell` "shell surface" recipe: theme
`background` fill, rounded 10, `.shadow(0.30, r10, y5)`, a `panelStroke` outline),
offset below the selection so it reads as a cursor popover. Inside, the **real**
`MarkdownView(palette: p, source: doc, style: MarkdownStyle(baseFontSize: 16),
highlighter:)`, sized to content (mirrors glance's auto-size). The fixture is a
representative GFM doc broadened past the old specimen to also exercise the
previously-unverified paths: **h3–h6**, an **image** placeholder, **inline-HTML /
HTML-block** passthrough, a **swift fence** (the injected-highlighter path, via a
palette-driven `StubSwiftHighlighter` that proves an injected `AttributedString`
flows through `CodeBlockView` and re-themes), and a **plain fence** (the
nil-highlighter themed-mono default). ThemeCard supplies `p` across all themes; on
an animatable theme its 30 Hz `TimelineView` drives `p`, so the prose re-themes
live with the rest of the bench.

## Out of scope (explicit, follow-up)

- Table content-sizing / outer-frame weight / horizontal scroll → **new sill
  MarkdownKitUI task** (the strongest true gap).
- Inline-code rounded run → **maintainer look call** (flat SwiftUI-native vs a
  SwiftUI rounded-run renderer); a custom NSLayoutManager is ruled out by 床2個.
- `forceDarkAqua` shell glue + `ShellDismissMonitor` ⌘W/aux-button parity → small
  WindowShell follow-ups.
- FontKind threading in `MarkdownKitUI` (already a flagged v1 stub).
- glance's CLI / lifecycle / cursor anchoring / cross-app dismiss / fade timing /
  find bar / the Highlightr concrete adapter → **app-essential, stays in glance**.
