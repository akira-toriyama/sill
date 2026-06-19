# sill — agent & contributor guide

Shared theming + UI foundation for the swift app family
(**facet · wand · perch · halo · glance**; chord is headless). One repo, many
modules, ONE version — the swift-collections layout. Full design, decisions, and
per-app migration plan: [docs/DESIGN.md](docs/DESIGN.md).

## Build / test (READ THIS FIRST)

```sh
swift build      # the LOCAL bar — compiles on CommandLineTools
swift test       # needs full Xcode (XCTest); does NOT run on a CLT-only setup
```

The maintainer's machine has **CommandLineTools only, no Xcode**, so
`import XCTest` fails for every test target locally. **`swift build` is the local
gate; `swift test` runs in CI** (`.github/workflows/build.yml`, macOS + full
Xcode). Therefore:

- Write XCTest for logic, but **prove UI behavior LIVE in `prism`** — don't claim
  a widget works off an unrun test.
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
| `ThemeKit` | shared themed **AppKit widgets** (`ThemedTextField`, …) | AppKit / `@MainActor` |
| `prism` (exe) | the visual bench — renders every catalog theme + the real widgets | AppKit + SwiftUI |

**The pure / AppKit split is enforced by the DEPENDENCY GRAPH, not a flag.**
`Palette` imports nothing platform-specific; a consumer that links only `Palette`
links zero AppKit. AppKit widget modules (`PaletteKit`, `Effects`, `ThemeKit`)
must NEVER be a dependency of a pure `*Core`; apps consume them from their
*View* layer only. Module name ≠ its primary public type (module `ThemeKit`,
type `ThemedTextField` — avoids a Module.Module collision).

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
draws in it). A widget belongs in sill once ≥2 apps would otherwise hand-draw it
(rule-of-three). Every widget MUST add a `prism` showcase — a
`<Widget>View: NSViewRepresentable` bridge hosting the REAL widget + a
`Mock<Widget>(p:)` grid wired into `ThemeCard`, so it appears live across all
themes (prism never imports an app's View → no drift).

## Icons (SVG, since v1.8.0)

All icons are SVG, rendered by **SwiftDraw** (a ThemeKit-only dep, pinned
`< 0.25.0` — 0.25+ needs an Xcode-only `#Preview` plugin that breaks the CLT
build). Load with `phosphorImage(name:pt:weight:)` (Phosphor, MIT — the workhorse
glyphs) or `simpleIconImage(name:pt:)` (Simple Icons, CC0 — brand/app logos);
both return a template `NSImage` the widgets tint. Pass a pre-resolved image to
`ThemedButton/FAB.leadingImage` or `ThemedToolBar.ButtonItem.image` (wins over the
SF `*Symbol`; template ⇒ tinted, multi-colour ⇒ raw). **The vendored set in
`Sources/ThemeKit/Resources/` is a CURATED SUBSET, not the full catalogs** — need
a glyph that isn't there? Add it in one step per
[`Resources/README.md`](Sources/ThemeKit/Resources/README.md) (a missing lookup
also prints that pointer in DEBUG). The SF→Phosphor name sweep is ROADMAP #2.

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
