# sill

Shared theming foundation for the swift app family
(**facet · wand · perch · halo · glance**). One repo, three modules, one
version — the swift-collections layout.

```swift
import Palette      // pure, Sendable, no AppKit — the ThemeSpec + presets
import PaletteKit   // AppKit — resolve(ThemeSpec) -> NSColors, `pal`, fonts
import Effects      // dynamic — EffectSpec, registry, animated themes
```

| module | what | layer |
|---|---|---|
| `Palette` | `HexColor` · `FontKind` · `ThemeSpec` · presets · `paletteFor` | pure (any `*Core`) |
| `PaletteKit` | `resolve` + derive recipe · `pal` · `uiFont` · `NSColor(hex:)` | AppKit / `@MainActor` |
| `Effects` | `EffectSpec` · `EffectRegistry` · `blendThrough` · `ThemeMotion` | dynamic atom |

A consumer that depends on **only `Palette`** links zero AppKit.

See [docs/DESIGN.md](docs/DESIGN.md) for the full design, decisions, and
per-app migration plan.

> Part of plan **atelier** — exists so "facet の theme 真似て" never has to
> be said twice. Status: design + working skeleton (builds, smoke-verified);
> not yet wired into the apps.

## Build

```sh
swift build       # compiles on CommandLineTools
swift test        # needs Xcode (XCTest); runs in CI
```

macOS 13+ · Swift 6.
