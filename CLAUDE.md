# sill — agent & contributor guide

Shared theming + UI foundation for the swift app family
(**facet · wand · perch · halo · glance**; chord is headless). One repo, many
modules, ONE version — the swift-collections layout. Full design, decisions, and
per-app migration plan: [docs/DESIGN.md](docs/DESIGN.md).

## Build / test (READ THIS FIRST)

```sh
swift build          # fast compile check — works on CommandLineTools
scripts/test.sh      # full XCTest suite — runs LOCALLY via an installed Xcode
```

**Both are local gates now — run them before every commit.** `swift build` is the
quick CLT compile bar; `scripts/test.sh` runs the whole XCTest suite by pointing
`DEVELOPER_DIR` at an installed Xcode (auto-detected) and building into an isolated
`.build-xcode/` so the Swift-6.3 test artifacts never clobber the CLT `.build/`
that `swift build` uses. CI (`.github/workflows/build.yml`) runs the same tests.

> A plain `swift test` still fails on a CLT-only shell (no XCTest linkage) — use
> `scripts/test.sh`, or `DEVELOPER_DIR=…/Xcode.app/Contents/Developer swift test`.
> With no Xcode installed at all, tests fall back to CI only.

**`swift test` catches logic, NOT SwiftUI render** — XCTest exercises the pure/logic
layers but does not prove a widget actually draws (e.g. #17f's GFM table: parser
tests passed while the body rows rendered blank, caught only in prism). So still:

- **prove UI behavior LIVE in `prism`** — don't claim a widget works off a green
  test alone.
- prism capture recipe (windows jump Spaces under the tiling WM): launch
  `.build/debug/prism` with `PRISM_CONFIG=…toml`, get the window id, then
  `screencapture -l<winid> -o out.png` **without** `osascript`-activating (that
  jumps Spaces and flakes the capture). For hover/pressed/popup/animation states,
  use the widget's `preview…` overrides so a static screenshot is deterministic.

## Modules (bare nouns, no `Sill` prefix; `Sources/<Name>/`)

| module | what | layer |
|---|---|---|
| `Palette` | `ThemeSpec` · presets · `HexColor`/`FontKind` — pure, Sendable | pure (any `*Core`) |
| `PaletteKit` | `resolve(ThemeSpec) → ResolvedPalette` · `pal` · `ink`/`onPrimary` · fonts | AppKit / `@MainActor` |
| `Effects` | `EffectSpec` · animated themes — color-only dynamic atom | AppKit (animator) |
| `ConfigSchema` | one `Spec<Root>` decodes config.toml + emits its JSON Schema | pure |
| `CLIKit` | arity-driven argv tokenizer | pure |
| `ListCore` | Foundation-only pure logic behind the stateful list widgets (rows · selection · collapse · DnD geometry); List/ComboBox/Menu wrap it | pure |
| `GridCore` | Foundation-only pure grid math (adaptive column count) behind `ThemedGridView` (#17e) | pure |
| `Motion` | easing curves — pure `Easing` `f(t)→value`, sampled per frame by the app | pure |
| `Gesture` | `L U R D` 4-way stroke-direction recognition (wand parity) | pure |
| `PixelArt` | pure arcade BONUS score-ladder data + deterministic per-cell picker (chomp #12) | pure |
| `ThemeKit` | shared themed **AppKit widgets** (`ThemedTextField`, …) — the AppKit *draw* layer the SwiftUI bridges wrap | AppKit / `@MainActor` |
| `ThemeKitUI` | public **SwiftUI** widgets (`ThemedTextFieldView`, …) — the DEFAULT UI layer; AppKit only for the 3 floors (IME edit-core + window shell + selectable rich-text/markdown, see **AppKit 使用可ポリシー**) | SwiftUI / `@MainActor` |
| `MarkdownKitUI` | selectable **markdown/rich-text** render core (`NSLayoutManager` inline-code pill) — the AppKit floor-3 the SwiftUI front keeps (#17f) | SwiftUI / `@MainActor` |
| `prism` (exe) | the visual bench — renders every catalog theme + the real widgets | AppKit + SwiftUI |

**The pure / AppKit split is enforced by the DEPENDENCY GRAPH, not a flag.**
`Palette` imports nothing platform-specific; a consumer that links only `Palette`
links zero AppKit. AppKit widget modules (`PaletteKit`, `Effects`, `ThemeKit`)
must NEVER be a dependency of a pure `*Core`; apps consume them from their
*View* layer only. Module name ≠ its primary public type (module `ThemeKit`,
type `ThemedTextField` — avoids a Module.Module collision). The public SwiftUI
front is **`ThemeKitUI`** (most widgets an `NSViewRepresentable` wrapping their
`ThemeKit` AppKit widget, but the backdrop/pill/grid parts and effect renderers
are SwiftUI-native); apps consume *that* from their View layer. Standing
direction: confine AppKit to the 3 essential floors (IME field-editor core + the
nonactivating-panel window shell + the selectable rich-text/markdown render core) and
make everything else SwiftUI-native — a migration in progress, not a finished state
(see **AppKit 使用可ポリシー**).

## Theming contract

Widgets are themed by ASSIGNING a `ResolvedPalette` and repainting:

```swift
public var palette: ResolvedPalette { didSet { applyTheme() } }
```

Resolve happens on the AppKit side (`@MainActor`, because `NSColor` isn't
Sendable). Use the canonical role fields only — do NOT invent role names:
`background · foreground · muted · tertiary · primary · secondary · border ·
hover · selection · error` (+ `backgroundAlpha`, `backgroundMode`). Accent
convention: focus/active affordances go `primary`.

`ThemeKit` is the AppKit widget kit (PaletteKit resolves the theme; ThemeKit
draws in it) — and **`ThemeKitUI`** wraps it as the public **SwiftUI** front (the
default front for widgets; AppKit is kept only for the 3 unavoidable floors — the
IME field editor, the non-activating panel/popup shell, and the selectable
rich-text/markdown render core — see **AppKit 使用可ポリシー**).
A widget belongs in sill once ≥2 apps would otherwise hand-draw it
(rule-of-three). Every widget MUST add a `prism` showcase — a `Themed<Widget>View`
SwiftUI bridge in `ThemeKitUI` (today an `NSViewRepresentable` hosting the REAL
AppKit widget) that prism imports + a `Mock<Widget>(p:)` grid wired into
`ThemeCard`, so it appears live across all themes (prism never imports an app's
View → no drift).

## AppKit 使用可ポリシー（確定 2026-06-23・更新 2026-06-30〔床2個→床3個〕 — sill widget kit）

ウィジェット層は **SwiftUI が既定**（`ThemeKitUI` が本物の SwiftUI 部品ライブラリ）。**AppKit は原則禁止** — 許可されるのは SwiftUI で本質的に不可能な次の **3点だけ**で、それ以外で AppKit が要ると感じたら「SwiftUI では不可能」として必ず**相談**する（勝手に AppKit を広げない）。許可される3点:

1. **IME（日本語入力）の根幹** — `NSTextField` の field editor（変換中=marked text の検知＋変換確定前の Enter/Esc/↑↓ の出し分け）。AppKit は**編集コアだけ**・枠/ラベル/アイコン/配色/エラーは SwiftUI。
2. **「前面/フォーカスを奪わず浮く窓」＋「親窓からはみ出す popup」** — `.nonactivatingPanel`。AppKit は**窓の殻だけ**・中身は `NSHostingView` 経由で全て SwiftUI。
3. **選択可能なリッチテキスト描画（markdown 等）** — 連続選択/コピー ＋ inline-code の角丸ピル（`NSLayoutManager.fillBackgroundRectArray`）＋ `NSTextTable` の本物の表/コードブロック/blockquote 罫線。SwiftUI の `Text`/`textRenderer` は `.textSelection` と**排他**で両立不可（2026-06-30 prism で実証）。AppKit は **NSTextView 描画コアだけ**・配色/フォント/位置/データは sill role、窓殻は #17i WindowShell。

それ以外はすべて SwiftUI:

- ドット絵 = `Image(…).interpolation(.none)`（`NSViewRepresentable` blitter にしない）
- 粒子グロー = SwiftUI `Canvas` の `.addFilter(.shadow)`（`NSShadow`/`NSViewRepresentable` にしない・fidelity 問題なら**要相談**）
- blur/vibrancy = SwiftUI `Material`（`.ultraThinMaterial` 等。`NSVisualEffectView` は特定 material が出せない時のみ・**要相談**）
- GFM 表 = 単体表示なら SwiftUI `LazyVGrid`。ただし**選択可能な markdown 本文内の表**は floor #3 の `NSTextTable`（連続選択のため本文ごと NSTextView・2026-06-30 更新。旧「薄 NSTextView backend は不可」を上書き）

この3点を超えて AppKit を足したくなったら必ず**要相談**。帰結: `ThemeKitUI` に残る AppKit は**床3個**（IME 編集コア＋窓の殻＋選択可能リッチテキスト描画）だけ。設計の全文＝[`docs/ROADMAP.md`](docs/ROADMAP.md) #16.5/#17。

## Icons (SVG, since v1.8.0)

All icons are SVG, rendered by **SwiftDraw** (a ThemeKit-only dep, pinned
`< 0.25.0` — 0.25+ needs an Xcode-only `#Preview` plugin that breaks the CLT
build). Load with `phosphorImage(name:pt:weight:)` (Phosphor, MIT — the workhorse
glyphs) or `simpleIconImage(name:pt:)` (Simple Icons, CC0 — brand/app logos);
both return a template `NSImage` the widgets tint. Every widget's `*Symbol:
String?` field now takes a **Phosphor slug** (e.g. `"caret-down"`); the internal
resolvers load it via `phosphorImage` — SF Symbols are GONE from the codebase (the
SF→Phosphor sweep, ROADMAP #2, is complete). Pass a pre-resolved image to
`ThemedButton/FAB.leadingImage` or `ThemedToolBar.ButtonItem.image` (wins over the
matching `*Symbol`; template ⇒ tinted, multi-colour ⇒ raw). **The vendored set in
`Sources/ThemeKit/Resources/` is a CURATED SUBSET, not the full catalogs** — need
a glyph that isn't there? Add it in one step per
[`Resources/README.md`](Sources/ThemeKit/Resources/README.md) (a missing lookup
also prints that pointer in DEBUG).

## Conventions

- Commits: **gitmoji + Conventional Commits** (enforced by `commit-lint`), e.g.
  `:sparkles: feat(ThemeKit): …`. Squash-merge; the PR number `(#N)` is appended
  by GitHub on merge.
- A library change ⇒ **minor version bump + a matching git tag**, `v`-prefixed to
  match the app family (facet ships `v6.0.0`, …): **`v0.33.0`**. SwiftPM strips the
  optional `v`, so `.upToNextMinor` pins resolve unchanged. Pre-1.0, a minor can
  break; consumers pin `.upToNextMinor`. (Tags `0.17.0`…`0.32.0` predate this and
  stay bare — the `v` prefix begins at `v0.33.0`; don't rewrite published tags.)
- TOML is taplo-linted in CI.
