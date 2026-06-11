# sill

Shared theming foundation for the swift app family
(**facet · wand · perch · halo · glance**). One repo, three modules, one
version — the swift-collections layout.

```swift
import Palette      // pure, Sendable, no AppKit — the ThemeSpec + presets
import PaletteKit   // AppKit — resolve(ThemeSpec) -> NSColors, `pal`, fonts
import Effects      // dynamic, color-only — EffectSpec, animated themes
```

| module | what | layer |
|---|---|---|
| `Palette` | `HexColor` · `FontKind` · `BgMode` · `ThemeSpec` · presets · `paletteFor` · `parseColorToken` | pure (any `*Core`) |
| `PaletteKit` | `resolve` + derive recipe · `pal` · `ink`/`onAccent` · `uiFont` · `NSColor(hex:)` | AppKit / `@MainActor` |
| `Effects` | `EffectSpec` · `borderEffectFor` · `blendThrough` · `animatedPalette` | dynamic atom (color-only) |

A consumer that depends on **only `Palette`** links zero AppKit.

See [docs/DESIGN.md](docs/DESIGN.md) for the full design, decisions, and
per-app migration plan.

> Part of plan **atelier** — exists so "facet の theme 真似て" never has to
> be said twice. Status: shipped into facet (#189) + perch (#108) on `0.1.0`;
> `ThemeSpec v2` (bgMode + tertiary + derive accessors) on branch
> `feat/theme-spec-v2` toward `0.2.0`.

## Build

```sh
swift build       # compiles on CommandLineTools
swift test        # needs Xcode (XCTest); runs in CI
```

macOS 13+ · Swift 6.
