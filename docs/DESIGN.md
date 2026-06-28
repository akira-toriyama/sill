# sill — design doc (theming core + widget kit)

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

> **Widget kit + 1.0 (2026-06):** atop the theming core, sill now ships
> **`ThemeKit`** — a 12-widget MUI-style themed AppKit kit (TextField →
> ComboBox · Button · List · Menu · Border …) — plus the **`prism`** visual
> bench. That kit, complete and API-stable, is what takes sill to **1.0**.
> See **§5**.
>
> **Since #16/#17 (2026-06):** the kit's public front is now the **SwiftUI**
> module **`ThemeKitUI`** (shipped `v1.23.0`). Per the **AppKit 使用可ポリシー**
> (CLAUDE.md, 確定 2026-06-23) AppKit is **原則禁止** in that layer — confined to
> two floors (the IME field-editor edit-core + a non-activating window/popup
> shell); `ThemeKit` is the AppKit *draw* tier those SwiftUI bridges wrap. See **§5**.

---

## 1. Architecture — modules, one repo, one version

swift-collections layout: each public module is BOTH a target and its own
library product, shipped under one git tag. The pure / AppKit split is
enforced by the **dependency graph**, not a flag.

```
sill (1 repo · 1 version)
├─ Palette      pure · Sendable · NO AppKit          ← any *Core can import
│    HexColor · FontKind · ThemeSpec · presets · paletteFor · names
│
├─ Effects      dynamic atom (COLOR-only)   depends on Palette
│    EffectSpec · borderEffectFor · blendThrough · animatedPalette
│    (AppKit parts behind #if canImport. motion stays app-side — no protocol)
│
└─ PaletteKit   AppKit · @MainActor   depends on Palette + Effects
     NSColor(hex:) · resolve(ThemeSpec)->ResolvedPalette · pal · uiFont
     ResolvedPalette.animated(forTheme:at:)  ← grafts an Effects AnimatedFrame
       (the live accent) onto a resolved palette; the one PaletteKit→Effects edge
```

Three more modules ride the same one-version tag: **`ThemeKit`** — the AppKit
**widget kit** (themed MUI-style parts; depends on `PaletteKit` + `Palette`,
consumed from an app's View layer only, NEVER a `*Core` dependency) — plus the
two pure siblings **`CLIKit`** (argv tokenizer) and **`ConfigSchema`**
(`Spec<Root>` → config decode + JSON-Schema), and the **`prism`** dev bench.
The widget kit is **§5**; the authoritative target wiring is
[Package.swift](../Package.swift).

A consumer that adds only the `Palette` product **transitively links zero
AppKit** — that is what lets perch's pure `PerchCore` use the spec.

| app | imports | from layer |
|---|---|---|
| facet | Palette + PaletteKit + Effects | View (`pal.foreground`…) |
| perch | Palette (Core) + PaletteKit + Effects (Adapter) | the split it already invented |
| wand | Palette + PaletteKit + Effects | adapter |
| halo | Palette + Effects (+ PaletteKit if it adds chrome) | the ring |
| glance | PaletteKit (background/foreground/primary now; Effects later) | panel |
| chord | — | headless, zero need |

*(sill role names shown; each app's view call sites adopt them at migration —
until then an un-migrated app pinned to `0.1.0` keeps the old `pal.text`/`pal.accent` spelling.)*

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

### 1.0 — the kit earns the shared motion (AnimatedBorderView)

Phase A removed the motion abstraction because **no second consumer existed**.
By 1.0 one does — sill's own **widget kit**. The border flash / breathe /
colour-cycle that facet · halo · wand · glance each hand-drew is now ONE part,
**`AnimatedBorderView`** (ThemeKitUI, SwiftUI-native since #17d), and the live accent trio is
**`ResolvedPalette.animated(forTheme:at:)`** (PaletteKit). The rule-of-three,
finally met, promoted the shared *colour* motion INTO sill. This does **not**
walk back the §3 / Q4-A mandate — it sharpens it:

- **Effects stays colour-only.** `animatedPalette(theme:at:)` still returns only
  the time-varying accent atoms (primary / secondary / selection), and
  `resolveBorder(…)` is a per-frame `f(now)` yielding a stroke colour + width.
  There is still **no motion-*geometry* protocol** — Pac-Man's mouth, facet's
  tree flourish, the splatoon splat stay 100% app-side, each app drawing its own.
- **What moved in is the *application* of that colour motion**, not a new
  abstraction. `AnimatedBorderView` owns its SwiftUI `TimelineView(.animation)`
  clock (resting on the steady hue under reduce-motion); `ResolvedPalette.animated` grafts
  the accent frame onto an otherwise-steady palette so a widget's whole
  appearance cycles, not just its rim. PaletteKit owns this composition (the one
  acyclic **`PaletteKit → Effects`** edge) precisely because Effects must NOT
  know `ResolvedPalette` — halo still links Effects alone.
- **One master switch.** `AnimatedBorderView.effectsEnabled` and
  `animated(forTheme:at:enabled:)` take the SAME `enabled` flag (派手好き ON /
  静か OFF), so a host reads ONE preference and the whole theme — border rim +
  widget accents — animates or rests together. `Effects.isAnimatableTheme(_:)`
  is the authority on which themes cycle.

So §4b-GQ6 still holds — `primary` (static) ⊻ `EffectSpec.steady` (active) is a
**mode selector the render layer applies** — but for the shared cases that render
layer is now a sill **widget** rather than each app's bespoke code.

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
| 9 font | **`FontKind` (family) is the only *themed* axis.** Since #8 the kit's sizes/weights are a FIXED internal `TypeScale` (`TypeRole`) — centralised + MUI-grounded but NOT themable (never on `ThemeSpec`/config); an app's heading-ramp beyond the kit stays app-local. See §5 "The type scale". |
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

### The theme catalog (+ system)

| theme | axis | bg | fg | primary | secondary |
|---|---|---|---|---|---|
| terminal | favorite (green-on-black; merges old `hacker`) | `050805` | `9BFEDA` | `33FF66` | `FFB000` |
| chomp | favorite (arcade; +EffectSpec.chomp) | `000000` | `FFEA00` | `FFEA00` | `2121FF` |
| rainbow | favorite (loud dynamic) | `0D0B14` | `FFFFFF` | `FF2D95` | `2BE0FF` |
| aurora-flux | neon-on-black (emerald+violet) | `03070A` | `CDFBEF` | `1EFFB0` | `CE5BFF` |
| acidwave | neon-on-black (fuchsia+jade) | `06030A` | `E8DDF5` | `E879F9` | `34D399` |
| neon-noir | neon-on-black (cyan+magenta) | `04060A` | `D6FBFF` | `22D3EE` | `FF2EC4` |
| outrun | neon-on-black (violet+coral) | `040208` | `F2E9FF` | `C724FF` | `FF7847` |
| blacklight | neon-on-black (violet+lime) | `030206` | `F3E8FF` | `BD3FFF` | `CCFF00` |
| synthwave | pitch-black cyberpunk (magenta+cyan) | `000000` | `FFE3FA` | `FF2EC4` | `22D3EE` |
| ghostwire | pitch-black cyberpunk (cyan+magenta; neon-noir successor) | `000000` | `D6FBFF` | `00E5FF` | `FF2EC4` |
| cyberpunk | pitch-black cyberpunk (acid-yellow+cyan) | `000000` | `F3F7E2` | `FCEE0A` | `00E5FF` |
| tron | pitch-black cyberpunk (azure+orange) | `000000` | `DCEFFF` | `12A5FF` | `FF6A1A` |
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
`canonical(_:)`/`suggest(_:)` validation helpers (Q10). *(`TypeScale` (Q7) was
held until rule-of-three — **shipped in #8** as the fixed internal `TypeRole`,
the ten copy-pasted `themedFont` helpers being the trigger; see §5.)*

**Post-Phase-V growth (0.24–0.25):** the blessed-12 set above is the Phase-V
*base*; the catalog has since grown to **32 themes + `system`** (33 entries).
Added — the **animated-neon family** `voltage` · `toxic` · `ember` ·
`solar-veil` · `molten-vein` · `coin-op` · `arcane` (0.24.0), each a `ThemeSpec`
preset PAIRED with an animatable `EffectSpec` (these — with `rainbow` / `chomp` —
are exactly the themes `Effects.isAnimatableTheme(_:)` returns true for), and the
**muted black-based family** `dusk` · `clay` · `gemstone` · `graphite` (0.25.0,
static). The live authority is `Palette.themeCatalog` / `canonicalThemeNames`,
not this Phase-V table; `prism` iterates the full set.

---

## 5. The widget kit — ThemeKit (the parts) + prism (the bench)

The same north star, one layer up: *「facet の field 真似て」「wand の menu 真似て」
を二度と言わない*. Where §2–§3 share the **theme** (colours + motion), `ThemeKit`
shares the **widgets** that wear it — the MUI-style AppKit parts the apps were
each hand-drawing (facet's tree-filter / tag-rename fields + popup menus, wand's
tome list, …). This is the work that takes sill to **1.0**.

### Where it sits

`ThemeKit` is the AppKit widget tier: it depends on `PaletteKit` (which resolves
the theme) + `Palette`, and draws in the resolved roles. Like PaletteKit it is
consumed from an app's **View** layer only and is **never** a dependency of a
pure `*Core`. The module is `ThemeKit`; its primary types are `ThemedTextField`,
… — module ≠ type, avoiding a `ThemeKit.ThemeKit` collision (the same rule as
`Palette` / `ThemeSpec`).

**(#16/#17 update.)** The View layer now consumes the SwiftUI module
**`ThemeKitUI`** (each widget an `NSViewRepresentable` wrapping these `ThemeKit`
widgets); `ThemeKit` is the AppKit *draw* layer beneath it. Per the **AppKit
使用可ポリシー** (確定 2026-06-23) AppKit is **原則禁止** — permitted only for two
floors: the IME field-editor edit-core and the `.nonactivatingPanel` window/popup
shell; everything else is SwiftUI-native, and anything beyond the two floors is
要相談.

### The contract (one rule, enforced by shape)

Every widget is themed by **assigning a `ResolvedPalette` and repainting** — no
theme flags, no app `NSColor`s reaching in:

```swift
public var palette: ResolvedPalette { didSet { applyTheme() } }   // re-themes the whole widget
```

A widget consumes only the **canonical role fields** (`background · foreground ·
muted · tertiary · primary · secondary · border · hover · selection · error`,
plus `backgroundAlpha` and the rendering hints), with the family accent
convention — **focus / active affordances go `primary`**. Where a host hands in
app data it passes **pre-resolved atoms** (an `NSImage`, a role enum, a closure
for the 実処理), never an app `NSColor` or a raw `NSView` — so the component owns
*render + interaction + theming* and the host owns *data + behaviour*. These are
GENERAL React-style components; facet / wand are study cases, **not** coupling
targets.

### Two embedding shapes

| shape | what | widgets |
|---|---|---|
| **embed** | a bare `NSView` / `NSControl` you `addSubview` + configure; owns its intrinsic size, is itself screencapturable | TextField · Button · ButtonGroup · Checkbox · FAB · Divider · Border · Skeleton · **List** |
| **controller** | a retained object owning a borderless **child-window popup** (the host window stays key); add its `.field` / anchor or call `present(…)`, retain for its lifetime | ComboBox · Menu · Tooltip |

The child-window popups share **one factory** (the 0.28 `PopupPanel` refactor):
a borderless **non-key** panel so the host window keeps key + IME focus, instead
of ComboBox / Menu / Tooltip each reinventing that seam. This non-key panel is
**floor (2)** of the **AppKit 使用可ポリシー** (2026-06-23) — one of the only two
sanctioned AppKit uses (the window shell that floats without stealing key/IME
focus and can exceed the parent window). The shell is the sanctioned part; per
policy the panel's *contents* migrate to SwiftUI via `NSHostingView` (today they
are AppKit views — `ThemedList` / the tooltip bubble).

### The catalog — 12 widgets, 4 families

`prism`'s `KitCatalog.swift` is the **single source of truth**: each entry
carries the part's MUI analog, embed/controller shape, key API, and variants.
The gallery's per-widget **"copy ref"** button serialises one entry to the
clipboard (so another agent can FIND + USE the part), and this section reads the
same array. The families are the gallery's tabs:

| family | widgets (MUI analog) |
|---|---|
| **Text** | `ThemedTextField` ⟨TextField⟩ · `ThemedComboBox` ⟨Autocomplete⟩ |
| **Action** | `ThemedButton` ⟨Button⟩ · `ThemedButtonGroup` ⟨ButtonGroup⟩ · `ThemedCheckbox` ⟨Checkbox⟩ · `ThemedFAB` ⟨Fab⟩ |
| **Feedback** | `ThemedDivider` ⟨Divider⟩ · `AnimatedBorderView` ⟨surface rim⟩ · `ThemedSkeleton` ⟨Skeleton⟩ · `ThemedTooltip` ⟨Tooltip⟩ |
| **Collection** | `ThemedList` ⟨List⟩ · `ThemedMenu` ⟨Menu⟩ |

`ThemedList` is the shared **row-painter** that both `ThemedComboBox`'s drop-down
and `ThemedMenu`'s panel host (0.31) — mixed-height rows, section headers /
separators, badges, density / selection / hover modes, and either host-driven or
self-managed keyboard nav. So the three collection-ish parts draw from one body.
Its vertical scroller is a **`ThemedScroller`** (a public, reusable `NSScroller`
subclass) — an auto-hiding overlay knob painted `muted` rather than the macOS
grey, so a scrollable surface scrolls in-theme too (1.2). The row glyphs draw
through one `respectFlipped` image primitive (the doc view is `isFlipped`), so a
checkmark / favicon lands upright (1.2).

### Live effects in the kit (the §3 motion, applied)

Two pieces make the dynamic theme (§3) visible *in the kit itself*, gated by ONE
master switch:

- **`AnimatedBorderView`** (ThemeKitUI) — the universal surface rim. No effect (or
  `effectsEnabled = false`) → a static `primary` stroke; an effect + effects ON →
  the live `Effects.resolveBorder` rim (glowing / breathing / colour-cycling),
  drawn SwiftUI-native (#17d) on a `TimelineView(.animation)` clock + a `Canvas`
  two-stop bloom, resting on the steady hue under reduce-motion.
- **`ResolvedPalette.animated(forTheme:at:enabled:)`** (PaletteKit) — grafts the
  live accent trio onto an otherwise-steady palette each frame, so a widget's
  *whole* appearance cycles, not just its border. `prism` drives every widget
  family through it on a `TimelineView`; the static **`.palette`** tab stays
  still for deterministic capture.

`effectsEnabled` is the host's **one preference** (派手好き ON / 静か OFF): the
same flag feeds `AnimatedBorderView.effectsEnabled` AND `animated(…enabled:)`, so
border + widget accents animate or rest *together* (see §3, "the kit earns the
shared motion").

### The type scale (#8 — MUI-grounded, macOS-tuned)

The kit's text sizes + weights are a **FIXED internal scale**, `Palette.TypeRole`
→ `TypeToken(pt, weight)`, resolved to an `NSFont` by `ResolvedPalette.uiFont(_:)`
in PaletteKit. It replaced ten copy-pasted per-widget `themedFont` helpers — the
rule-of-three trigger (Q7's deferred `TypeScale`, now earned). Two wins beyond
tidiness: those helpers branched only `.mono` vs system and **silently dropped
`.rounded`/`.menu`**, so the six rounded catalog themes had been rendering plain
system; routing every widget through the one resolver fixes that. And the
readability nits the audit flagged become *role values*, not scattered literals.

**Grounded by ROLE, not by pixel.** MUI is web (px, 16px base); macOS is native
(pt, 13pt body). You map the *role*, then pick the macOS-native point size — and
take MUI's portable lesson: lift small supporting text with **weight** (its
subtitle2/button are 500), not by stacking size + muted colour + regular weight.

| `TypeRole` | sill | MUI analog (px/wt) | macOS analog | used by |
|---|---|---|---|---|
| `body` | 13 / regular | body1 16/400 | body 13 | list title · field input · chip |
| `secondaryBody` | **11 / medium** | body2 14/400 → subtitle2 500 | smallSystemFontSize 11 | list 2nd line · field helper/error |
| `caption` | 11 / regular | caption 12/400 | caption1 11 | divider label · header subtitle |
| `sectionHeader` | 11 / semibold | overline (emph) | grouped header | list 1-line section header |
| `sectionTitle` | 13 / medium | subtitle2 14/500 | body emph | list 2-line header title |
| `badge` | **10 / medium** | caption emph | labelFontSize 10 | list badge (was 9 compact) |
| `shortcut` | 10 / medium | — | keycap 10 | list keycap / shortcut |
| `tooltip` | 11 / medium | caption emph | — | tooltip |

The two **readability fixes** are `secondaryBody` 11→*medium* (was regular; lands
on the mono-URL branch too via one shared token) and the compact `badge` **9→10**
(9pt sat below `labelFontSize` and every MUI floor). Control-size-scaled labels
(button 13/14/15, checkbox 14/16, toolbar 14/13, FAB 13/14) keep their **size** in
the widget's `Metrics` — that's legitimate control-size layout, MUI-faithful (its
button variant scales pt by size) — and route only **weight + family** through the
resolver. `ThemedTextField.floatSize` (11) is the float-label shrink ratio + notch
width, *not* a text size; the helper line was decoupled onto `.secondaryBody`.

### Adding a widget (rule-of-three + the prism mandate)

A part earns its place in sill once **≥2 apps would otherwise hand-draw it**.
Every widget MUST ship a `prism` showcase — a `<Widget>View: NSViewRepresentable`
bridge hosting the REAL widget plus a `Mock<Widget>` grid wired into the family
gallery, so it renders live across every catalog theme (the full
`Palette.themeCatalog` — 32 + `system`, see §4c). `prism` **never imports
an app's View**, so the bench can't drift toward one app's needs. And because the
maintainer's machine is **CommandLineTools-only (no XCTest)**, logic is
unit-tested but **UI behaviour is proven live in `prism`** — every widget exposes
`preview…` overrides (`previewHovered` / `previewFocused` / `previewOpen` /
`previewFrozen` / …) that force a deterministic state for a static screenshot.

A new widget MUST also satisfy:

- **Accessibility contract:** set `role`, `label`, `value` (if stateful), and an
  `enabled` state that reflects `isEnabled`; and `postAXValueChanged()` (Shared.swift)
  at each **committed** value/selection change — never on a transient highlight/hover
  or per keystroke (that floods VoiceOver). Decorative parts (Border/Divider/Skeleton/
  Scroller) are exempt.
- **controlled/uncontrolled seam (two doors):** the plain property assignment is
  SILENT; a parallel firing setter (`selectRow` / `setChecked(_:notifying:)` /
  `commitSelection` / `setText(_:notifying:)`) notifies. The host drives a controlled
  component by re-assigning the value from inside the callback. Do NOT introduce a
  `@Binding`-style wrapper (it breaks plain-property callers).
- **Pure core for complex state:** if the widget owns non-trivial selection/highlight/
  filter logic, put that logic in `ListCore` (Foundation-only, Sendable, AppKit-free)
  with XCTest, and keep the AppKit widget a thin wrapper — both today's AppKit widget
  and tomorrow's SwiftUI view (#16/#17) share one tested core. Note: SwiftUI is
  now the DEFAULT front (the `ThemeKitUI` module, #16); a new widget adds AppKit
  only for the two essential floors — the IME field-editor edit-core and the
  non-activating window/popup shell — and flags anything beyond those as **要相談**
  (see CLAUDE.md **AppKit 使用可ポリシー** / docs/ROADMAP.md #16.5/#17).

### Versioning at 1.0

1.0 marks the widget kit **complete and its API stable**. Pre-1.0 a minor could
break and consumers pinned `.upToNextMinor`; from 1.0 the kit follows standard
semver. The next consumer-facing step is the **facet / wand redesign** adopting
`ThemedList` + `ThemedMenu` (the parts built last, for exactly that) — a separate
round, app-side.

---

## 6. Per-app migration (next phase, not done yet)

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

## 7. Open issues

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

## 8. Verification status

- `swift build` — ✅ clean (Palette · PaletteKit · Effects, no warnings).
- runtime smoke check — ✅ ALL PASS (derive recipe reproduces facet's
  exact values; system / bg-override / chomp / registry all correct).
- XCTest suites (`Tests/…`) — written defensively; run in **CI** (CLT has
  no XCTest locally, same as facet).
- widget kit (`ThemeKit` + the public SwiftUI `ThemeKitUI`) + `prism` — `swift build` ✅ clean; widget LOGIC in
  XCTest (CI), but **UI behaviour proven live in `prism`** across every catalog
  theme, since the CLT-only machine has no XCTest (see §5). Each widget ships
  `preview…` seams so a static screenshot captures a deterministic state. The
  `ThemeKitUI` bridges are byte-equivalent SwiftUI wraps proven live in prism,
  with AppKit confined to the two essential floors (IME field-editor core + the
  non-activating panel/popup shell) per the **AppKit 使用可ポリシー**.
