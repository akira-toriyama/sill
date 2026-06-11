# sill — design doc (Palette / PaletteKit / Effects)

`sill` is the shared theming foundation for the swift app family
(**facet · wand · perch · halo · glance**; chord is headless). It exists
for one reason — the **north star**:

> 「wand を作る時に『facet の theme 真似て』を二度と言いたくない
> (halo でも同じ事を言うから)」 = 共有 lib が在る理由 = **同じ事を二度言わないため**。

This is the first module of plan **atelier** (lib = `sill`, dev workbench
= `bench`). Status: **shipped into facet (#189) + perch (#108) on tag
`0.1.0`. `ThemeSpec v2` (Phase T) implemented on branch `feat/theme-spec-v2`
toward `0.2.0`; builds + 34-check runtime smoke ALL PASS.** See
§4b for the v2 locked decisions.

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
└─ Effects      dynamic atom (COLOR-only)   depends on Palette
     EffectSpec · borderEffectFor · blendThrough · animatedPalette
     (AppKit parts behind #if canImport. motion stays app-side — no protocol)
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

**v2 (Phase T, 2026-06-11)** = the 0.1.0 shape **+ `bgMode` + `tertiary`,
zero removals** (the first-pass "demote dim/font to derived" was a baseline
misread — 16 presets author distinct `dim` hues — and was reversed).

```swift
public struct ThemeSpec: Sendable, Hashable {
    public var bg: HexColor?     // nil = vibrancy fall-through
    public var text: HexColor    // REQUIRED
    public var dim: HexColor     // REQUIRED, non-derived (16 presets author it)
    public var accent: HexColor  // rgb == 0 ⇒ OS control-accent (sentinel)
    public var error: HexColor   // defaulted 0xEF4444 (perch miss == wand no-match)
    public var font: FontKind    // REQUIRED — system | mono | rounded | menu

    public var accent2: HexColor?    // nil ⇒ derived complement
    public var divider: HexColor?    // nil ⇒ derived neutral @ 0.10
    public var hoverFill: HexColor?  // nil ⇒ derived neutral @ 0.05
    public var selFill: HexColor?    // nil ⇒ derived accent @ 0.18
    public var bgAlpha: Double?      // nil ⇒ opaque (perch pill vs facet panel)
    public var bgMode: BgMode        // NEW — vibrancy | fixed | systemDynamic
    public var tertiary: HexColor?   // NEW — nil ⇒ derived text@0.55 / OS tertiary
}
```

13 stored fields. Colors are a pure `HexColor { rgb: UInt32; alpha: Double }`
value type (no CoreGraphics → portable + Sendable). `FontKind` adds `.menu`
(wand's native menu typeface). `bgMode` defaults from `bg` (nil → `.vibrancy`,
else `.fixed`); **`.systemDynamic`** is the new case = a concrete fill with
live OS inks (perch's system pill) — the case the old `bg == nil` gate could
not express.

### The derive recipe (PaletteKit) — reproduces facet exactly

Verified at runtime against all facet presets (34-check smoke ALL PASS):

```
inks source  = bgMode == .fixed            →  authored spec inks
             = .vibrancy / .systemDynamic  →  OS inks (label / controlAccent)
neutral ink  = (bg luminance < 0.5  →  white  :  black)   // nil bg = dark
divider      = override ?? neutral @ 0.10
hoverFill    = override ?? neutral @ 0.05
selFill      = override ?? accent  @ 0.18   // static AND animated (unified)
accent2      = override ?? complement(accent)            // grey for sat < 0.05
tertiary     = override ?? (OS .tertiaryLabelColor / text @ 0.55)   // now a FIELD
```

The resolve **gate keys on `bgMode`** (not `bg == nil && usesSystemAccent`).
`tertiary` is a first-class resolved field (`pal.tertiary`), promoted from
the old method. `selFill` is **unified to 0.18 across the static and animated
paths** (the animator previously hardcoded 0.22, shifting facet's selected
row when animation engaged); rainbow's authored `accent@0.22` is preserved.

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

sill owns **identity + colour** (`ThemeSpec.chomp` + `EffectSpec.chomp`);
each app owns the **motion drawing** for its surface.

> **Phase A (hygiene, 2026-06-11):** the speculative `EffectRegistry` +
> `ThemeMotion` protocol were **removed** — every app had 0 consumers
> (rule-of-three not met; `ThemeMotion`'s color-frame model didn't even fit
> wand's chomp, which is Pac-Man *geometry*). Phase T confirmed the rule:
> the `accent` (static) ⊻ `EffectSpec.steady` (active) relationship is a
> **mode selector** the render layer applies, and **motion stays 100%
> app-side** (wand Effect+Intensity, chomp Pac-Man, perch transforms,
> glance fade) — sill's Effects is **color-only**. The renderer / Pac-Man
> mouth / splatoon splat were always app-side; sill now ships no motion
> abstraction at all until a second consumer earns one.

---

## 4. Locked decisions (the grill)

| # | decision |
|---|---|
| ① layer | **2-module split** `Palette`(pure) + `PaletteKit`(AppKit), + `Effects` |
| ② fields | **lean core + derive** (author writes ~6-7, Kit derives the rest) |
| ③ native | facet `system` preset is the shared native look; `vibrancyMaterial` / `forceDarkAqua` are PaletteKit **resolve hints** (rendering detail, not colour) |
| ④ chomp | **Q4-A**: shared palette + `EffectSpec` in catalog; motion app-side (registry / `ThemeMotion` **removed** in Phase A — 0 consumers) |
| Q1 | **facet hex is canonical** for drifted house themes (terminal/cute/hacker/vapor/cyber/kawaii); **bg may differ per app** (perch pill vs facet panel). No per-app override seam. |

Authority (Tommy, 2026-06-10): 0-base / refactor / breaking / rename — all OK.

---

## 4b. ThemeSpec v2 — Phase T locked decisions (grill, 2026-06-11)

A schema-first redesign across all 5 visual apps (18-agent survey →
synthesize → critique → grounded re-read → harden → 3-lens verify).
Verdict: **shape SOUND**; the only fidelity blocker (selFill 0.18/0.22) is
fixed here. The central tension — *lean semantic roles + app role→surface
map* vs *surface-specific in the schema* — resolved **lean + a hybrid
extension model**.

| GQ | decision |
|---|---|
| 1 dim | **keep REQUIRED, non-derived** (16 presets author distinct dim hues; demoting is a breaking recolor) |
| 2 alpha | per-surface alpha = `ink(tier, of: root)` as a **shared DEFAULT, explicitly partial** — covers the common 4-tier case; facet's ~21 stops / glance clusters / wand mode-conditioned stay app-local |
| 3 bgMode | **3-case** `{vibrancy, fixed, systemDynamic}` + resolve gate redesigned to key on `bgMode` (unifies with the `bgOverride:` param) |
| 4 onAccent | **two** accessors — `onAccent` (text/icon) + `onAccentStroke` (hairline @0.4), both rooted on the **opaque accent**; opt-in |
| 5 parser | pure **`parseColorToken`** (named + `#rgb`/`#rrggbb`/`#rrggbbaa`), opt-in; `HexColor` value type unchanged |
| 6 effect | `accent` (static) ⊻ `EffectSpec.steady` (active) = **mode selector**, documented; motion app-side |
| 7 codeTheme | glance's Highlightr theme = **opaque pass-through** on a glance-LOCAL extension + a bg-strip contract; sill never models syntax tokens |
| 8 selFill | **unify to 0.18** (static = animated); preserve authored overrides (**rainbow `accent@0.22`**) |
| 9 font | **`FontKind` only** — weight / size / heading-ramp stay app-local layout, not themed |
| 10 wand state | wand's match/no-match surface swap stays **app-local** (single-app; defer a "stateful role pair" concept) |

### New surface (v2)

- **`ThemeSpec`**: `+ bgMode: BgMode`, `+ tertiary: HexColor?`,
  `+ usesSystemColors`.
- **pure `Palette`** (link-safe for PerchCore): `parseColorToken`,
  `suggestedPillAlpha(luminance:)`, `HexColor.bestForeground`,
  `lightFillLuminanceThreshold`.
- **`ResolvedPalette`** (AppKit): `tertiary` (now a stored field),
  `ink(_:of:)` with `InkTier{faint,subtle,wash,strong}` ×
  `InkRoot{text,dim,accent}`, `onAccent(_:)`, `onAccentStroke`.

### Extension model (the hybrid)

Surface-specific paint is carried by **app-local config structs that EMBED
a `ThemeSpec`** + add typed fields (perch `pillAlphaTable`/`missOverride`;
wand color tokens + motion; glance `codeTheme`/fonts/fills; halo
`EffectSpec` + geometry). **No per-app fields enter sill.** `ink()` de-dups
the common alpha case only.

### Implementation constraints (carry into the migrations)

1. **PerchCore links `Palette` only** → contrast/derive VALUE logic lives in
   pure Palette (`bestForeground` + `lightFillLuminanceThreshold`) so perch's
   reimplementation can't drift from PaletteKit's NSColor path.
2. The `bgMode` gate redesign must decide **material ownership** without
   starting to make facet honor `pal.vibrancyMaterial` (the call-site
   `.sidebar` must keep winning) — else facet's panel material regresses.
3. `ink()` is **alpha-over only**; perch's base+delta and facet's
   blend-toward-white stay app-local (no sill helper yet).

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
- **wand**: `CastThemePalette` / `TomeThemePalette` (String) → `ThemeSpec`
  (deriving hex from the shared spec via `parseColorToken`); chomp/splatoon
  stay wand-local **motion** over the shared `ThemeSpec.chomp` +
  `EffectSpec.chomp` (no `ThemeMotion` — removed Phase A); `.menu` font +
  the `tertiary` field cover the native launcher tiers.
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

v2 (Phase T) residual risks — carried, not blocking:

- **`ink()` is a partial answer**, not a cure: it de-dups the common 4-tier
  alpha case only; facet's ~21 stops, glance's clusters, and wand's
  mode-conditioned alphas keep deriving at the draw site. The shared lib
  **reduces** alpha divergence, it doesn't eliminate it.
- **`.systemDynamic` consumer-through-`resolve()`**: perch (its motivating
  case) hand-rolls `resolvePalette` and links `Palette` only, so it reads
  the field directly rather than through `resolve()`. The gate branch is
  implemented + smoke-verified, but a concrete `resolve()`-path consumer
  (facet/glance, once migrated) should be confirmed; also unify with the
  existing `bgOverride:` param so the two mechanisms don't overlap.
- **system-preset material is doubly-specified** (resolve emits
  `.underWindowBackground`; facet's PanelHost hardcodes `.sidebar`). The
  bgMode work kept the call-site owner — do **not** start making facet honor
  `pal.vibrancyMaterial` or the panel material regresses.
- **derive primitives**: `ink()` is alpha-over only; perch's base+delta and
  facet's blend-toward-white are different operations, still app-local.

---

## 7. Verification status

- `swift build` — ✅ clean (Palette · PaletteKit · Effects, no warnings).
- runtime smoke check — ✅ ALL PASS (derive recipe reproduces facet's
  exact values; system / bg-override / chomp / registry all correct).
- XCTest suites (`Tests/…`) — written defensively; run in **CI** (CLT has
  no XCTest locally, same as facet).
