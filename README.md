# sill

Shared theming foundation for the swift app family
(**facet · wand · perch · halo · glance**). One repo, focused modules, one
version — the swift-collections layout.

```swift
import Palette      // pure, Sendable, no AppKit — the ThemeSpec + presets
import PaletteKit   // AppKit — resolve(ThemeSpec) -> NSColors, `pal`, fonts
import Effects      // dynamic, color-only — EffectSpec, animated themes
```

| module | what | layer |
|---|---|---|
| `Palette` | `HexColor` · `FontKind` · `BackgroundMode` · `ThemeSpec` · presets · `paletteFor` · `parseColorToken` | pure (any `*Core`) |
| `PaletteKit` | `resolve` + derive recipe · `pal` · `ink`/`onPrimary` · `uiFont` · `NSColor(hex:)` | AppKit / `@MainActor` |
| `Effects` | `EffectSpec` · `borderEffectFor` · `blendThrough` · `animatedPalette` | dynamic atom (color-only) |

A consumer that depends on **only `Palette`** links zero AppKit.

The table is the theming core; sill also ships CLI / config helpers + the
shared widget kit (`CLIKit`, `ConfigSchema`, `ThemeKit`) plus the `prism` dev
bench. The full
module set and target wiring is authoritative in [Package.swift](Package.swift)
— this list is orientation, not a contract. See [docs/DESIGN.md](docs/DESIGN.md)
for the full design, decisions, and per-app migration plan.

> Part of plan **atelier** — exists so "facet の theme 真似て" never has to
> be said twice. Status: shipped into facet (#189) + perch (#108) on `0.1.0`;
> `ThemeSpec v2` shipped on `0.2.0`. Phase V (Tailwind-style role names +
> 12-theme catalog rebuild) on branch `feat/phase-v-catalog`.

> **Family TOML lib**: sill's config-schema layer (`ConfigSchema`) decodes
> over [swift-toml-edit](https://github.com/akira-toriyama/swift-toml-edit) —
> the swift app family's one TOML implementation (the `Toml` module · Sill-1 ·
> a Swift `toml_edit`). sill's former in-tree `Toml` moved into that standalone
> repo at `0.11.0`; consumers `import Toml` from there. Design notes:
> atelier [`docs/swift-toml-edit.md`](https://github.com/akira-toriyama/atelier/blob/main/docs/swift-toml-edit.md).

## Build

```sh
swift build          # fast compile check (CommandLineTools)
scripts/test.sh      # XCTest suite — runs locally via an installed Xcode; also in CI
```

macOS 13+ · Swift 6.
