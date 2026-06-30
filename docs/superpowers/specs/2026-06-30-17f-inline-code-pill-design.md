# sill #17f — MarkdownKitUI rounded inline-code pill (SwiftUI `TextRenderer`)

Date: 2026-06-30 · Task: [t-xt11] (spun from the glance prism-mock arm of [t-yc68], PR sill#95)

## Problem

`MarkdownKitUI` renders an inline-code run as a **flat** `surface(.inset)`
background with U+200A hairspace padding inside a single `Text(AttributedString)`
([InlineStyling.swift:30-39](../../../Sources/MarkdownKitUI/InlineStyling.swift)).
SwiftUI's `AttributedString.backgroundColor` run attribute can only paint a square
fill — so inline code reads as a hard-edged rectangle, not the rounded pill the
glance reference draws (cornerRadius 4 via an `NSLayoutManager.fillBackgroundRectArray`
override). Reproducing glance's pill with `NSLayoutManager` would re-introduce an
`NSTextView` backend, which the **AppKit 床2個 policy forbids** (the only sanctioned
AppKit floors are the IME field editor and the non-activating panel shell).

The MarkdownKit design spec (`2026-06-30-markdownkit-design.md`, future item #3)
deferred the pill as "needs a custom flow `Layout` that degrades selection." **This
spec supersedes that deferral**: the `TextRenderer` protocol draws the pill natively
with **no** selection or wrapping degradation.

## Goal (done-when)

- Inline code renders as a rounded pill (cornerRadius 4) on **macOS 15+** in
  `MarkdownView`; the existing flat `surface(.inset)` + hairspace fill stays the
  **macOS 13/14 fallback**, byte-unchanged.
- The prism glance/markdown showcase shows the rounded pill across themes (verified
  live, per the prism-only bench convention).
- Selection and line-wrapping across an inline-code span stay **native** (one
  selectable text block; a wrapped span shows one pill per line fragment).
- Zero new AppKit (床2個-safe).

## Current rendering (what changes)

`themedInline(_:palette:style:baseFont:textColor:)` flattens each paragraph/heading/
table-cell into one `AttributedString`, translating Foundation
`inlinePresentationIntent` into explicit attributes. For a `.code` run today it sets
`slice.backgroundColor = surface(.inset)` and wraps the run in hairspace pad runs
(also background-filled) so the square fill has horizontal breathing room. It is
consumed at **three sites**, all `Text(themedInline(...))`:

- [MarkdownView.swift:48](../../../Sources/MarkdownKitUI/MarkdownView.swift) — heading
- [MarkdownView.swift:60](../../../Sources/MarkdownKitUI/MarkdownView.swift) — paragraph
- [MarkdownTableView.swift:70](../../../Sources/MarkdownKitUI/MarkdownTableView.swift) — table cell

(lists and blockquotes route their inline content through the `.paragraph` case, so
these three sites cover every inline-code occurrence.)

## Approach

### 1. The renderer — `InlineCodeBackground: TextRenderer` (macOS 15+)

A new `@available(macOS 15, *)` type in `MarkdownKitUI`:

```
struct InlineCodeBackground: TextRenderer {
    var fill: Color        // surface(.inset), bridged at the call site
    var radius: CGFloat = 4
    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            for run in line where run is a code run {
                let rect = run.typographicBounds.rect            // per-line-fragment
                ctx.fill(Path(roundedRect: rect.insetBy(...), cornerRadius: radius), with: .color(fill))
            }
            ctx.draw(line)                                       // glyphs on top
        }
    }
}
```

Filling per **run × line fragment** is exactly glance's `fillBackgroundRectArray`
semantics: a code span that wraps gets one rounded rect per line, glyphs drawn after
so the fill sits behind. A small symmetric horizontal inset replaces the U+200A
hairspace hack on this path.

### 2. Marking code runs so the renderer can find them

The renderer must identify code runs from `Text.Layout`. Two implementation shapes,
to be settled by what compiles cleanly under `swift build`:

- **(A) Custom attribute on the existing `AttributedString`** — keep
  `themedInline → AttributedString`; tag `.code` runs with a custom marker and read
  it off `Text.Run` in the renderer. Lowest blast radius (call sites only add a
  `.textRenderer(...)` modifier).
- **(B) Concatenated `Text` fragments + `.customAttribute`** — the documented WWDC24
  path: `themedInline` returns a `Text` built by `+`-joining per-run fragments, with
  `.customAttribute(CodeRun())` on code fragments. Call sites change from
  `Text(themedInline(...))` to `themedInline(...)`.

**Decision rule:** try (A) first; if a custom `AttributedString` attribute does not
surface in `Text.Layout.Run`, fall back to (B). Either way the marker is internal to
`MarkdownKitUI`; the public `themedInline` signature change (if (B)) stays within the
module.

### 3. Gating + fallback

`@available(macOS 15, *)` selects the renderer path, which **drops** the hairspace
pad + flat `backgroundColor` for code runs (the pill supplies the fill). On macOS
13/14 the code path is **unchanged** — today's flat `surface(.inset)` + hairspace.
Once the family floor bump [t-tbar] lands, the `@available` split is removed and the
renderer becomes unconditional.

### 4. Apply at all three inline sites

Wrap each of the three `Text(themedInline(...))` call sites with the renderer
(macOS 15+) so inline code is rounded in headings, paragraphs, list items,
blockquotes, and table cells alike.

### 5. Fill look

Match glance: flat `surface(.inset)`, cornerRadius 4, **no border**. sill ships many
themes (glance only validated neon-noir + github-light), so verify the pill across
the full prism catalog and add a hairline `palette.border` stroke **only if** a busy
animated-neon theme reads weak. Decide that empirically in prism, not up front.

## Non-goals (線引き)

- No change to the macOS 13/14 flat path.
- No `NSTextView` / `NSLayoutManager` / any new AppKit.
- No code-**block** change (this is inline `.code` only; fenced blocks keep
  `CodeBlockView`).
- glance's own app-side renderer is not touched here; this is the sill-native
  general version that a future glance Phase-B rebuild would adopt.

## Verification

- `swift build` is the local gate (CLT-only host; no `swift test` locally).
- Parse-layer XCTest is unaffected (this is a render-layer change); existing
  `MarkdownKitTests` continue to run in CI.
- **Live in prism** (the binding gate for UI): launch the glance/markdown showcase,
  confirm the rounded pill in **neon-noir (dark + animated)** and **github-light**,
  sweep a few neon themes (e.g. biolume/midas/spectre) for fill contrast, and confirm
  a wrapped inline-code span (a) shows one pill per line and (b) still selects as one
  contiguous span.

## Risks

- **`TextRenderer` run-attribute surfacing (A vs B).** Mitigated by the (A)→(B)
  fallback; (B) is the documented path and definitely compiles.
- **CLT SDK has `TextRenderer`.** It is SwiftUI (macOS 15 SDK); `@available`-gated
  code compiles under the host CLT. Runtime path runs on the host (macOS ≥ 15) so
  prism exercises the real renderer.
- **Per-line inset tuning.** The symmetric inset replacing the hairspace needs a
  visual pass in prism so pills don't collide on tight wraps; tune live.
