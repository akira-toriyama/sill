# sill — design doc (Palette / PaletteKit / Effects)

`sill` is the shared theming foundation for the swift app family
(**facet · wand · perch · halo · glance**; chord is headless). It exists
for one reason — the **north star**:

> 「wand を作る時に『facet の theme 真似て』を二度と言いたくない
> (halo でも同じ事を言うから)」 = 共有 lib が在る理由 = **同じ事を二度言わないため**。

This is the first module of plan **atelier** (lib = `sill`, dev workbench
= `bench`). Status: **design + working skeleton, builds + smoke-verified
locally; not yet wired into any app, not pushed.**

---

## 1. Architecture — 3 modules, one repo, one version

swift-collections layout: each public module is BOTH a target and its own
library product, shipped under one git tag. The pure / AppKit split is
enforced by the **dependency graph**, not a flag.

```
sill (1 repo · 1 version)
├─ Palette      pure · Sendable · NO AppKit          ← any *Core can import
│    HexColor · FontKind · ThemeSpec · presets · paletteFor · names
│
├─ PaletteKit   AppKit · @MainActor   depends on Palette
│    NSColor(hex:) · resolve(ThemeSpec)->ResolvedPalette · pal · uiFont
│
└─ Effects      dynamic atom         depends on Palette
     EffectSpec · borderEffectFor · EffectRegistry · blendThrough
     · animatedPalette · ThemeMotion   (AppKit parts behind #if canImport)
```

A consumer that adds only the `Palette` product **transitively links zero
AppKit** — that is what lets perch's pure `PerchCore` use the spec.

| app | imports | from layer |
|---|---|---|
| facet | Palette + PaletteKit + Effects | View (`pal.text`…) |
| perch | Palette (Core) + PaletteKit + Effects (Adapter) | the split it already invented |
| wand | Palette + PaletteKit + Effects | adapter |
| halo | Palette + Effects (+ PaletteKit if it adds chrome) | the ring |
| glance | PaletteKit (bg/text/accent now; Effects later) | panel |
| chord | — | headless, zero need |

**Why not one module / monorepo:** see plan-atelier. Pure↔AppKit must be
separable (perch); `1 repo = 1 version` is SwiftPM's grain.

---

## 2. ThemeSpec — the static palette (lean core + derive)

The pure spec. Authors set **~6-7 fields**; PaletteKit derives the rest.

```swift
public struct ThemeSpec: Sendable, Hashable {
    public var bg: HexColor?     // nil = native vibrancy
    public var text: HexColor
    public var dim: HexColor
    public var accent: HexColor  // rgb == 0 ⇒ OS control-accent (sentinel)
    public var error: HexColor   // default 0xEF4444 (perch miss == wand no-match)
    public var font: FontKind    // system | mono | rounded | menu

    public var accent2: HexColor?    // nil ⇒ derived complement
    public var divider: HexColor?    // nil ⇒ derived (see recipe)
    public var hoverFill: HexColor?  // nil ⇒ derived
    public var selFill: HexColor?    // nil ⇒ derived
    public var bgAlpha: Double?      // nil ⇒ opaque (perch pill vs facet panel)
}
```

Colors are a pure `HexColor { rgb: UInt32; alpha: Double }` value type
(no CoreGraphics → maximally portable + Sendable). `FontKind` adds `.menu`
(wand's native menu typeface) to facet's three.

### The derive recipe (PaletteKit) — reproduces facet exactly

Verified at runtime against all facet presets (smoke check ALL PASS):

```
neutral ink  = (bg luminance < 0.5  →  white  :  black)   // nil bg = dark
divider      = override  ?? neutral @ 0.10
hoverFill    = override  ?? neutral @ 0.05
selFill      = override  ?? accent  @ 0.18
accent2      = override  ?? complement(accent)            // hue +180°
tertiary()   = system → .tertiaryLabelColor ; else text @ 0.55
```

- **15 dark editor presets store NO trio** — derived bit-for-bit
  (terminal/nord/dracula/gruvbox/catppuccin/rosepine/everforest/solarized/
  onedark/monokai/hacker/monotone/neon/cyber/vapor).
- **7 store explicit overrides** because they deviate:
  cute · kawaii (accent-tinted, light) · paper · mono-light · mono-dark ·
  rainbow · system (dynamic colors, special-cased in `resolve`).

> ⚠️ The first synthesis proposed `divider = text@0.12 / hover = accent@0.10`.
> A triple-check against the real presets found that wrong — facet uses
> **neutral ink** (white-on-dark / black-on-light) @ 0.10 / 0.05. The recipe
> above is the corrected, verified one.

`pal` stays a short `@MainActor` module-level var (facet's invariant) —
now owned by PaletteKit as a `ResolvedPalette` with the **same field
names**, so view call sites (`pal.text` / `pal.accent` / …) don't change.

---

## 3. Effects — the dynamic atom (static / dynamic cleanly split)

Animated theming (border flash, rainbow hue-rotation, chomp) is a
**separate structure** from the static palette — the plan's mandate.
Verified shareable: facet, halo, and wand cycle colors **byte-identically**
(`blendThrough` + hue rotation, 30 Hz).

```swift
public struct EffectSpec: Sendable, Hashable {   // pure
    public let steady: UInt32
    public let flash: [UInt32]
    public let cycles: Bool      // true = rotate the spectrum (rainbow)
}
// built-ins: neon · cyber · vapor · kawaii · rainbow · chomp
// (facet & halo flash hex reconciled — they already matched; halo was
//  ported from facet)
```

### Q4-A — chomp & the "sibling" family

chomp is **cross-app** (Tommy: facet tree, halo border, wand trail all
adopt `theme = chomp`) and the start of a **family** of playful animated
themes. So:

```
theme = chomp  →  shared:  ThemeSpec.chomp   (arcade palette, in catalog)
                          + EffectSpec.chomp  (animated maze border)
               →  per-app: signature MOTION   (each app draws its own)
                          wand  → Pac-Man cursor trail
                          facet → tree flourish
                          halo  → border-ring motion
```

Two shared mechanisms realize this:

- **`EffectRegistry`** (extensible) — sill ships the built-ins; an app
  `register(name, spec)`s its own sibling at startup without touching
  sill. `spec(for:)` is a superset of `borderEffectFor`.
- **`ThemeMotion`** (thin protocol) — standardizes the shared parts
  (`themeName`, `effect`, a defaulted `frame(at:)` that cycles identically)
  while each app supplies its own **drawing** for its surface. A
  surface-agnostic lib can't know cursor-trails-vs-tree-rows, so sill owns
  identity + colour, the app owns geometry.

The renderer / Pac-Man mouth / splatoon splat stay 100% app-side.

---

## 4. Locked decisions (the grill)

| # | decision |
|---|---|
| ① layer | **2-module split** `Palette`(pure) + `PaletteKit`(AppKit), + `Effects` |
| ② fields | **lean core + derive** (author writes ~6-7, Kit derives the rest) |
| ③ native | facet `system` preset is the shared native look; `vibrancyMaterial` / `forceDarkAqua` are PaletteKit **resolve hints** (rendering detail, not colour) |
| ④ chomp | **Q4-A**: shared palette+EffectSpec in catalog + extensible registry + `ThemeMotion`; motion app-side |
| Q1 | **facet hex is canonical** for drifted house themes (terminal/cute/hacker/vapor/cyber/kawaii); **bg may differ per app** (perch pill vs facet panel). No per-app override seam. |

Authority (Tommy, 2026-06-10): 0-base / refactor / breaking / rename — all OK.

---

## 5. Per-app migration (next phase, not done yet)

- **facet** (biggest): delete `FacetView/Palette.swift` preset bodies +
  `BorderEffect.swift`; depend on the 3 modules; `paletteFor` now returns
  `ThemeSpec`; `pal` moves to PaletteKit (same spelling, `ResolvedPalette`,
  same field names). `uiFont` / `borderEffectFor` / `blendThrough` /
  `animatedPalette` come from sill. View call sites unchanged.
- **perch**: `ThemePalette` → `ThemeSpec` (already pure UInt32 in Core);
  `ResolvedPalette` → `PaletteKit.resolve`. `missHex` → `error`,
  `pillBgAlpha` → `bgAlpha`. Catalog drift → facet hex (Q1).
- **wand**: `CastThemePalette` / `TomeThemePalette` (String) → `ThemeSpec`;
  chomp/splatoon become wand `ThemeMotion`s over shared specs; `.menu`
  font + tertiary helper cover the native launcher tiers.
- **halo**: `BorderEffect` → `Effects.EffectSpec` / `borderEffectFor` /
  `blendThrough` (its 5 effects already match sill's hex).
- **glance**: adopt `PaletteKit` for bg/text/accent; keep `--code-theme`
  (Highlightr) **separate** from a future UI `--theme` (namespace clash:
  `nord`/`monokai` exist in both).

Each step keeps all apps green; any step can stop. Convention cleanup
(rule-of-three / "extract to sill after AHA") lands last.

---

## 6. Open issues

- **system trio** can't be a `HexColor` (dynamic system colors) — special-
  cased inside `resolve`. Fine, but it's the one preset the recipe doesn't
  own.
- **`.menu` font** ignores `weight` (`NSFont.menuFont` has no weight
  variant). facet never used `.menu`, so no regression; revisit if a
  weighted menu font is needed.
- **module/type naming**: pure module is `Palette`, primary type is
  `ThemeSpec` (NOT `Palette`) to avoid the `Palette.Palette` collision.
  Resolved type is `ResolvedPalette`. Rename freely if preferred.
- **chomp visual tuning**: the arcade palette + EffectSpec hex are a first
  pass; tune against the real wand chomp once the motion lands.

---

## 7. Verification status

- `swift build` — ✅ clean (Palette · PaletteKit · Effects, no warnings).
- runtime smoke check — ✅ ALL PASS (derive recipe reproduces facet's
  exact values; system / bg-override / chomp / registry all correct).
- XCTest suites (`Tests/…`) — written defensively; run in **CI** (CLT has
  no XCTest locally, same as facet).
