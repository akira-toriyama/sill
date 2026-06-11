# sill — design doc (Palette / PaletteKit / Effects)

`sill` is the shared theming foundation for the swift app family
(**facet · wand · perch · halo · glance**; chord is headless). It exists
for one reason — the **north star**:

> 「wand を作る時に『facet の theme 真似て』を二度と言いたくない
> (halo でも同じ事を言うから)」 = 共有 lib が在る理由 = **同じ事を二度言わないため**。

This is the first module of plan **atelier** (lib = `sill`, dev workbench
= `bench`). Status: **shipped into facet (#189) + perch (#108) on tag
`0.1.0`. `ThemeSpec v2` (Phase T) shipped on `0.2.0`. Phase V (value
redesign) — role names renamed to a Tailwind-style vocabulary +
catalog 0-base rebuilt to 12 blessed themes — on branch
`feat/phase-v-catalog`; `swift build` clean.** See §4b for the Phase T
decisions and **§4c for the Phase V rename + catalog**.

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
| facet | Palette + PaletteKit + Effects | View (`pal.foreground`…) |
| perch | Palette (Core) + PaletteKit + Effects (Adapter) | the split it already invented |
| wand | Palette + PaletteKit + Effects | adapter |
| halo | Palette + Effects (+ PaletteKit if it adds chrome) | the ring |
| glance | PaletteKit (background/foreground/primary now; Effects later) | panel |

*(sill role names shown; each app's view call sites adopt them at migration —
until then an un-migrated app pinned to `0.1.0` keeps the old `pal.text`/`pal.accent` spelling.)*
| chord | — | headless, zero need |

**Why not one module / monorepo:** see plan-atelier. Pure↔AppKit must be
separable (perch); `1 repo = 1 version` is SwiftPM's grain.

---

## 2. ThemeSpec — the static palette (lean core + derive)

The pure spec. Authors set **4 required hues + font**; PaletteKit derives
the rest.

**Role names follow a Tailwind-style semantic vocabulary** (Phase V,
2026-06-11): `background / foreground / muted / primary / secondary /
border / hover / selection / backgroundAlpha / backgroundMode`. The shape
is the Phase T v2 shape with **zero structural change — names only**.

```swift
public struct ThemeSpec: Sendable, Hashable {
    public var background: HexColor?  // nil = vibrancy fall-through
    public var foreground: HexColor   // REQUIRED — primary text ink
    public var muted: HexColor        // REQUIRED — secondary text / comments
    public var primary: HexColor      // REQUIRED — signature accent (rgb 0 ⇒ OS)
    public var error: HexColor        // defaulted 0xEF4444 (perch miss == wand no-match)
    public var font: FontKind         // REQUIRED — system | mono | rounded | menu

    public var secondary: HexColor?       // nil ⇒ derived complement
    public var border: HexColor?          // nil ⇒ derived neutral @ 0.10
    public var hover: HexColor?           // nil ⇒ derived neutral @ 0.05
    public var selection: HexColor?       // nil ⇒ derived primary @ 0.18
    public var backgroundAlpha: Double?   // nil ⇒ opaque (perch pill vs facet panel)
    public var backgroundMode: BackgroundMode  // vibrancy | fixed | systemDynamic
    public var tertiary: HexColor?        // nil ⇒ derived foreground@0.55 / OS tertiary
}
```

13 stored fields. Colors are a pure `HexColor { rgb: UInt32; alpha: Double }`
value type (no CoreGraphics → portable + Sendable). `FontKind` adds `.menu`
(wand's native menu typeface). `backgroundMode` defaults from `background`
(nil → `.vibrancy`, else `.fixed`); **`.systemDynamic`** is a concrete fill
with live OS inks (perch's system pill) — the case the old
`background == nil` gate could not express.

### The derive recipe (PaletteKit)

```
inks source  = backgroundMode == .fixed         →  authored spec inks
             = .vibrancy / .systemDynamic        →  OS inks (label / controlAccent)
neutral ink  = (background luminance < 0.5 → white : black)   // nil bg = dark
border       = override ?? neutral  @ 0.10
hover        = override ?? neutral  @ 0.05
selection    = override ?? primary  @ 0.18   // static AND animated (unified)
secondary    = override ?? complement(primary)           // grey for sat < 0.05
tertiary     = override ?? (OS .tertiaryLabelColor / foreground @ 0.55)
```

The resolve **gate keys on `backgroundMode`** (not
`background == nil && usesSystemPrimary`). `tertiary` is a first-class
resolved field (`pal.tertiary`). `selection` is **unified to 0.18 across the
static and animated paths**; rainbow's authored `primary@0.22` is preserved.

The Phase V catalog (§4c) is **lean**:

- **8 dark editor presets store NO trio** — derived from their dark bg
  (terminal/cobalt2/shades-of-purple/tokyo-hack/github-dark/dracula/
  catppuccin-mocha/gruvbox).
- **chomp** stores `border` + `selection` (arcade hues), `hover` derives.
- **rainbow / github-light / catppuccin-latte** store the full trio
  (light/special — the dark-ink recipe would derive wrong).
- **system** resolves dynamic OS colors (special-cased in `resolve`).

`pal` stays a short `@MainActor` module-level var (facet's invariant) —
owned by PaletteKit as a `ResolvedPalette`. The role **fields are renamed**
(Phase V), so migrating apps update view call sites (`pal.text` →
`pal.foreground`, `pal.accent` → `pal.primary`, …) at migration time; apps
pinned to `0.1.0` are untouched until they bump.

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

*(role names shown below are the Phase V names — see §4c. Phase T shipped
these under the older `bg/text/dim/accent` spelling.)*

- **`ThemeSpec`**: `+ backgroundMode: BackgroundMode`, `+ tertiary: HexColor?`,
  `+ usesSystemColors`.
- **pure `Palette`** (link-safe for PerchCore): `parseColorToken`,
  `suggestedPillAlpha(luminance:)`, `HexColor.bestForeground`,
  `lightFillLuminanceThreshold`.
- **`ResolvedPalette`** (AppKit): `tertiary` (now a stored field),
  `ink(_:of:)` with `InkTier{faint,subtle,wash,strong}` ×
  `InkRoot{foreground,muted,primary}`, `onPrimary(_:)`, `onPrimaryStroke`.

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

## 4c. Phase V — role rename + catalog rebuild (grill complete, 2026-06-11)

A 0-base value redesign: rename the roles to a Tailwind-style semantic
vocabulary, then rebuild the catalog — retiring the drifted/duplicate
presets (the 17 listed below) — down to **12 blessed themes + `system`**
(web-researched + 4-axis adversarially verified, Tommy-blessed).
Structural shape unchanged — names + values only.

### Role rename (Q1/Q2 — locked)

| old (Phase T) | new (Phase V) | | old | new |
|---|---|---|---|---|
| `bg` | `background` | | `accent2` | `secondary` |
| `text` | `foreground` | | `divider` | `border` |
| `dim` | `muted` | | `hoverFill` | `hover` |
| `accent` | `primary` | | `selFill` | `selection` |
| `error` | `error` (kept) | | `bgAlpha` | `backgroundAlpha` |
| `font` | `font` (kept) | | `bgMode` | `backgroundMode` |
| `tertiary` | `tertiary` (kept) | | `BgMode` | `BackgroundMode` |

Accessors follow: `onAccent`→`onPrimary`, `onAccentStroke`→`onPrimaryStroke`,
`InkRoot{text,dim,accent}`→`{foreground,muted,primary}`,
`usesSystemAccent`→`usesSystemPrimary`,
`systemAccentSentinel`→`systemPrimarySentinel`. The module var **`pal`
keeps its name** (facet invariant); only its fields rename.

### The 12-theme catalog (+ system)

| theme | axis | bg | fg | primary | secondary |
|---|---|---|---|---|---|
| terminal | favorite (green-on-black; merges old `hacker`) | `050805` | `9BFEDA` | `33FF66` | `FFB000` |
| chomp | favorite (arcade; +EffectSpec.chomp) | `000000` | `FFEA00` | `FFEA00` | `2121FF` |
| rainbow | favorite (loud dynamic) | `0D0B14` | `FFFFFF` | `FF2D95` | `2BE0FF` |
| cobalt2 | ref | `193549` | `FFFFFF` | `FFC600` | `0088FF` |
| shades-of-purple | ref | `2D2B55` | `FFFFFF` | `FAD000` | `9EFFFF` |
| tokyo-hack | ref (Tokyo-Night lineage) | `18173E` | `FFFFFF` | `E84B3C` | `F08DF0` |
| github-dark | popular | `0D1117` | `E6EDF3` | `2F81F7` | `3FB950` |
| dracula | popular | `282A36` | `F8F8F2` | `BD93F9` | `FF79C6` |
| catppuccin-mocha | distinctive | `1E1E2E` | `CDD6F4` | `CBA6F7` | `89B4FA` |
| gruvbox | distinctive | `282828` | `EBDBB2` | `FE8019` | `8EC07C` |
| github-light | light | `FFFFFF` | `1F2328` | `0969DA` | `8250DF` |
| catppuccin-latte | light | `EFF1F5` | `4C4F69` | `8839EF` | `209FB5` |
| **system** | structural | vibrancy | OS | OS accent | systemPurple |

Retired in the 0-base cut: the old Tokyo-Night `terminal`, `hacker` (merged
into the green `terminal`), `nord`, `rosepine`, `everforest`, `solarized`,
`onedark`, `monokai`, `monotone`, `neon`, `cyber`, `vapor`, `cute`, `paper`,
`kawaii`, `mono-light`, `mono-dark` (each a near-dup of a stronger keeper or
a utility preset not needed in a tight set; revive individually if wanted).
**EffectSpec border catalog is a separate axis** (neon/cyber/vapor/kawaii
survive there as `[border] effect` values even though cut as themes).

Still deferred (block 2c, not in this pass): `Intensity` shared enum (Q9),
`canonical(_:)`/`suggest(_:)` validation helpers (Q10), `TypeScale` font-size
scale (Q7 — held until rule-of-three).

---

## 5. Per-app migration (next phase, not done yet)

- **facet** (biggest): delete `FacetView/Palette.swift` preset bodies +
  `BorderEffect.swift`; depend on the 3 modules; `paletteFor` now returns
  `ThemeSpec`; `pal` moves to PaletteKit (`ResolvedPalette`). **Phase V
  renames the role fields**, so view call sites update at this step
  (`pal.text`→`pal.foreground`, `pal.accent`→`pal.primary`, …) — the one
  spot that touches "hundreds of lines" per facet's CLAUDE.md note. `uiFont`
  / `borderEffectFor` / `blendThrough` / `animatedPalette` come from sill.
  Also resolve the FacetCore name-list + `animatableThemes` Set duplication
  against sill (Q8/Q10).
- **perch**: `ThemePalette` → `ThemeSpec` (already pure UInt32 in Core);
  `ResolvedPalette` → `PaletteKit.resolve`. `missHex` → `error`,
  `pillBgAlpha` → `backgroundAlpha`; perch `system` fork folds into
  `.fixed` + `primary = 0` (Q6).
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
  backgroundMode work kept the call-site owner — do **not** start making
  facet honor `pal.vibrancyMaterial` or the panel material regresses.
- **derive primitives**: `ink()` is alpha-over only; perch's base+delta and
  facet's blend-toward-white are different operations, still app-local.

---

## 7. Verification status

- `swift build` — ✅ clean (Palette · PaletteKit · Effects, no warnings).
- runtime smoke check — ✅ ALL PASS (derive recipe reproduces facet's
  exact values; system / bg-override / chomp / registry all correct).
- XCTest suites (`Tests/…`) — written defensively; run in **CI** (CLT has
  no XCTest locally, same as facet).
