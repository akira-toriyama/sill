# sill — glossary

The vocabulary sill's code, its doc comments and its task bodies use as terms of
art. It exists to stop the user and Claude Code from meaning two different things
by one word. sill is a *shared* base, so almost every expensive misunderstanding
here is a pair that is easy to collapse and costly to collapse — *spec* vs
*resolved*, *themable role* vs *derived accessor*, *floor* vs *debt*, *gate* vs
*ratchet*, *on main* vs *released* — and in each entry the **distinction is the
content**. An entry that only restated the name would be worth nothing.

**Ordering: grouped by area, not alphabetical.** Nearly every term is meaningful
only next to its neighbours: *ThemeSpec → resolve → ResolvedPalette → role →
derived accessor* is one chain, and alphabetical order would shred it. Each term
appears in **bold** exactly once, so Ctrl-F on the word is as good as an index.

Each entry ends with where it lives: a file and a *symbol*, never a line number
(line numbers rot; this file was written at `0340a06`). Paths are from the
repository root. Its neighbours in `docs/` are [`DESIGN.md`](DESIGN.md) (the
architecture) and [`ROADMAP.md`](ROADMAP.md) (the numbered work items); the
policies it summarises are stated in full in [`../CLAUDE.md`](../CLAUDE.md).
Where an entry quotes a figure ("16 of 34 presets", "16 constructs, 14 DEBT"),
it is the measurement **recorded in the tree** at that symbol, not one re-run
while writing this glossary.

Maintaining it: a term is added or renamed in the **same PR** as the code change
that introduces or renames it, and when a cited symbol disappears its entry goes
with it. A glossary that documents a name the tree no longer has is worse than a
missing entry, because it is the one place a reader trusts not to be stale.

**Contents**

1. [Modules and layers](#1-modules-and-layers) — module, product, pure module, AppKit module, Core, layer, dependency rule, front, draw layer, atom, mechanism-only
2. [The theming contract](#2-the-theming-contract) — spec, resolved palette, resolve, derive recipe, role, canonical role field, sentinel, background mode, vibrancy, systemDynamic, process default, ambient theming, prop-drilling, precedence
3. [Derived vocabulary](#3-derived-vocabulary-not-themable) — derived accessor, ink tier, surface tier, state layer, state base, contrast ink, role tint, resting stroke, disabled ink, secondary ink, on-primary, control role
4. [Tokens](#4-tokens) — token, scale, ramp, elevation, type role, transition duration
5. [The catalog](#5-the-catalog) — catalog, preset, fixed preset, member, rawValue, random, paletteFor, tombstone, verdict, effect name, pet, effect spec
6. [The AppKit floors](#6-the-appkit-floors) — floor, floor 1/2/3, edit core, window shell, draw core, debt, 要相談
7. [Gates](#7-gates) — gate, ratchet, set equality, allow-list, both directions, baseline, blind spot, green means
8. [Release and consumers](#8-release-and-consumers) — rule of three, consumer, pin, flag day, on main vs released, rolling draft, publish, fleet
9. [Verification](#9-verification) — bench, showcase, mock, compile bar, local test gate, live proof

---

## 1. Modules and layers

sill is one repository, many modules, ONE version — the swift-collections
layout. The words below distinguish the units that share that version.

**module** — a directory under `Sources/<Name>/` compiled as one SwiftPM target.
Names are bare nouns with **no `Sill` prefix** (`Palette`, not `SillPalette`).
Sixteen exist; fourteen are shipped, `TestSupport` is test-only and `prism` is an
executable. Distinguish from **product** — the `.library(name:…)` entry a
consumer actually writes in its `Package.swift`. The two happen to be 1:1 today,
but they are different things to the API surface: `scripts/api-guard.sh` diffs
the Swift symbols AND the product set separately, because deleting a product
breaks a consumer even when every symbol in it survives. `Package.swift`,
*products*.

**pure module** — a module that imports nothing platform-specific, so a consumer
that links only it links **zero AppKit**: `Palette`, `CLIKit`, `LogKit`,
`ConfigSchema`, `ListCore`, `GridCore`, `Motion`, `Gesture`, `PixelArt`. Distinguish from
**AppKit module** — `PaletteKit`, `Effects`, `ThemeKit` (and the SwiftUI fronts
`ThemeKitUI`, `MarkdownKitUI`, which are `@MainActor` and reach AppKit on the
floors). The split is enforced by the **dependency graph, not a flag or a
comment**: an AppKit module must never appear as a dependency of a pure one, and
the compiler is what says so. `Package.swift`, *targets*.

**Core** — the `*Core` naming suffix for a pure module holding the logic behind a
stateful widget: `ListCore` (rows, selection, collapse, drag geometry),
`GridCore` (adaptive column count). A Core is Foundation-only by construction, so
an app's headless layer (FacetCore, WandCore) can validate and compute against it
without linking a module that compiles AppKit. The widget wraps the Core; the
Core never knows the widget exists. `Sources/ListCore/`, *ListRow*.

**layer** — which of {pure, AppKit, SwiftUI} a module sits in, and therefore
where an app may consume it. Apps consume AppKit/SwiftUI modules from their
*View* layer only; a Core may be consumed anywhere. The table in
[`../CLAUDE.md`](../CLAUDE.md) is the per-module authority. This is the
**dependency rule**: dependencies point from the platform-bound layer inward to
the pure one, never outward.

**front** — `ThemeKitUI`, the public **SwiftUI** widget layer and the DEFAULT
layer an app builds against. Distinguish from **draw layer** — `ThemeKit`, the
AppKit widget kit the front wraps where a floor requires it. Most of the front is
SwiftUI-native (the backdrop, pill, grid and effect renderers have no AppKit at
all); some widgets are an `NSViewRepresentable` hosting the real `ThemeKit`
widget. A module name is deliberately **not** its primary public type — module
`ThemeKit` ships type `ThemedTextField` — because `ThemeKit.ThemeKit` would be a
Module.Module collision. `Sources/ThemeKitUI/`, *ThemedButtonView*.

**atom** — a pure module small enough to have no internal layering, shipped under
the one sill tag alongside the rest: `Palette`, `CLIKit`, `LogKit`,
`ConfigSchema`, `Gesture`, `PixelArt`. The word marks intent, not size: an atom takes no
dependency it could avoid. `Sources/CLIKit/CLIKit.swift`, *header*.

**mechanism-only** — the boundary sill draws for shared code: sill supplies the
MECHANISM, the app keeps the POLICY. `CLIKit` owns no verb vocabulary (the app
supplies the arity table); `ink(_:of:)` is a shared default for the common
four-tier case, not a complete answer (facet still tints at ~21 distinct stops at
the draw site). When a proposal cannot be stated as mechanism, it belongs in the
app. `Sources/CLIKit/CLIKit.swift`, *Arity*.

---

## 2. The theming contract

The chain a colour travels: authored spec → `resolve` → resolved palette →
widget. Every term below names one link, and mixing two of them up is the most
common error in this repo.

**spec** (`ThemeSpec`) — the PURE, `Sendable`, AppKit-free description of a
theme, made of `HexColor`s. It is what a preset authors and what a config file
decodes to. Only five fields are required (`foreground`, `muted`, `primary`,
`error`, `font`, plus optional `background`); the rest — `secondary`, `border`,
`hover`, `selection`, `tertiary` — are optional overrides that DERIVE when unset.
`Sources/Palette/Palette.swift`, *ThemeSpec*.

**resolved palette** (`ResolvedPalette`) — the `NSColor` form a widget actually
paints from. Resolution happens on the AppKit side and is `@MainActor` because
`NSColor` is not `Sendable`. It carries **fourteen** stored fields: the ten roles
below, plus `font`, `backgroundAlpha`, `vibrancyMaterial` and `forceDarkAqua`.
Note what it does NOT carry: `backgroundMode` is a `ThemeSpec` field, an input to
resolution, and has no counterpart on the resolved side — asking for
`palette.backgroundMode` is the single most likely way to mistake the two types
for one. `Sources/PaletteKit/PaletteKit.swift`, *ResolvedPalette*.

**resolve** — the one function that turns a spec into a resolved palette, taking
optional `bgOverride` / `material` / `forceDark` so an app can substitute its own
panel background (perch's translucent pill vs facet's opaque panel) while keeping
the canonical inks. `Sources/PaletteKit/PaletteKit.swift`, *resolve(_:)*.

**derive recipe** — the documented rules `resolve` applies to fill an unset
optional: `secondary` = the primary's hue rotated +180° at its saturation and
brightness; `border` = neutral@0.10; `hover` = neutral@0.05; `selection` =
primary@0.18; `tertiary` = `.tertiaryLabelColor` or foreground@0.55. The neutral
base is white on a dark background, black on a light one, and a nil background
(vibrancy) counts as dark. It is a recipe, not a fallback: the dark editor
presets author only four colours precisely because the rest derive.
`Sources/PaletteKit/PaletteKit.swift`, *resolve(_:) doc comment*.

**role** — one of the ten named colour slots a widget is allowed to paint from:
`background · foreground · muted · tertiary · primary · secondary · border ·
hover · selection · error`. These plus `backgroundAlpha` are the **canonical role
fields**. The rule is *use these, do not invent role names* — a new role costs an
authoring pass across all 35 presets, which is why `success` was cut from the
vocabulary work (measured: no app in the family had success semantics; what
looked like it was emphasis-vs-failure). Accent convention: focus and active
affordances go to `primary`. `Sources/PaletteKit/PaletteKit.swift`,
*ResolvedPalette*.

**sentinel** — `systemPrimarySentinel` (rgb `0`), the reserved `primary` value
meaning "use the OS `controlAccentColor`". A sentinel rather than an optional
because `ThemeSpec.primary` is non-optional by design: every theme has an accent,
and only one theme delegates it. `Sources/Palette/Palette.swift`,
*systemPrimarySentinel*.

**background mode** — the `ThemeSpec` field selecting how the fill and inks come
from the OS: `.fixed` (the spec's own colours), **vibrancy** (no opaque fill;
`background` is nil and a `NSVisualEffectView.Material` is emitted), or
**systemDynamic** (a concrete fill from the spec, with LIVE OS inks —
`.labelColor`, `.secondaryLabelColor`, `.controlAccentColor`). The gate keys on
`backgroundMode`, not on `background == nil`, which is what makes a
concrete-background-with-system-inks theme expressible at all.
`Sources/Palette/Palette.swift`, *BackgroundMode*.

**process default** — `pal`, the mutable process-wide `ResolvedPalette` (starts
at `.terminal`, moved by `setPalette`). It is the LAST resort in the precedence
chain, not the normal path; a real app sets an ambient theme instead.
`Sources/PaletteKit/PaletteKit.swift`, *pal*.

**ambient theming** — the SwiftUI-idiomatic path added in v5: `.sillTheme(_:)`
on an ancestor publishes a palette, and a widget reads it through
`@Environment(\.sillPalette)`. Nests, so an inner `.sillTheme` overrides an outer
one for its subtree. The environment key lives in `PaletteKit` because that is
the common ancestor of `ThemeKitUI` and `MarkdownKitUI`.
`Sources/PaletteKit/PaletteEnvironment.swift`, *sillTheme(_:)*.

**prop-drilling** — the shape ambient theming replaced: `palette:
ResolvedPalette` as a required init argument on every widget, forcing every
intermediate view to forward a palette it does not use (measured before the fix:
61 declarations across 25 files, with exactly ONE `@Environment` in all of
`Sources`). It came from sill's only consumer being `prism`, which renders every
catalog theme side by side and so genuinely wants a per-widget override.
`scripts/theme-env.sh`, *WHY*.

**precedence** — the three-tier order a themed widget resolves its palette by:
explicit argument > nearest ancestor's `.sillTheme` > process default `pal`. The
explicit argument still winning is what made ambient theming additive rather than
a break — and is exactly why it needed a ratchet, since a new widget that forgets
to read the environment fails SILENTLY, just quietly ignoring the app's theme.
`Sources/PaletteKit/PaletteEnvironment.swift`, *sillPalette*.

---

## 3. Derived vocabulary (not themable)

**derived accessor** — a colour computed FROM the roles rather than authored per
theme. The whole category exists to answer "should this be a new role?" with
"no": a derived accessor costs zero authoring across all 35 presets, while a
themable one costs 35 authorings for a trigger no app has fired. Everything in
this section is derived. `Sources/PaletteKit/PaletteKit.swift`, *Derived
accessors*.

**ink tier** — a named alpha stop for tinting a base ink: `faint` 0.06, `subtle`
0.16, `wash` 0.30, `strong` 0.55, applied by `ink(_:of:)` over one of three
`InkRoot`s (foreground, muted, primary). Alpha-over ONLY — base+delta (perch) and
blend-toward-white (facet) stay app-local.
`Sources/PaletteKit/PaletteKit.swift`, *InkTier*.

**surface tier** — a fill layered OVER `background`: `.raised` (a gentle card or
cell lift, `ink(.faint)`) and `.inset` (a recessed well or code block,
`ink(.subtle)`). Built on ink tiers, deliberately NOT a new themable role. It is
a FILL only: text drawn on it is governed by its own text role's contrast, so it
is outside the WCAG sweep. `Sources/PaletteKit/PaletteKit.swift`, *SurfaceTier*.

**state layer** — the interaction state an overlay expresses: `hover`, `pressed`,
`focus`. Distinguish sharply from **state base**, which is what the overlay is
laid ONTO, because the two arms need DIFFERENT alphas and one flat table would be
wrong for both. `Sources/PaletteKit/PaletteKit.swift`, *StateLayer*.

**contrast ink** — the state base for an opaque role FILL (white ink on a blue
button): the overlay is `bestContrast(on:)` of the fill, at 0.08 hover / 0.12
pressed, and `.clear` for focus — a focused contained control shows focus through
its RING and elevation, not by tinting its fill. Distinguish from **role tint**,
the state base for a transparent or surface-coloured control: the overlay is a
wash of the role's own colour, at 0.06 hover / 0.16 pressed / 0.06 focus.
`Sources/PaletteKit/PaletteKit.swift`, *StateBase*.

**resting stroke** — the outline of an OUTLINED control at rest: the role colour
at half strength (`role@0.5`). One of the fifteen sites `stateOverlay` and
friends collapsed. `Sources/PaletteKit/PaletteKit.swift`, *restingStroke(of:)*.

**disabled ink** — `muted`, the ONE answer for disabled text (with
`disabledFill` = `ink(.subtle, of: .muted)` and `disabledStroke` = `border`).
Named here because the kit previously had two answers: `ThemedControl` used
`muted`, `ThemedListRow` used `tertiary`. `tertiary` is a semantic EMPHASIS tier
— the third rank of live text — which disabled is not, so the row was the one
that moved. `Sources/PaletteKit/PaletteKit.swift`, *disabledInk*.

**secondary ink** — `secondaryInk(on:)`: `muted` when it already clears the 3:1
supplementary-text floor on the given OPAQUE fill, else the theme-robust contrast
ink at 0.70. It exists because a selected list row paints a `selection` wash
(primary@0.18) and draws its second line in `muted` on top, and **16 of the 34
fixed presets** land under 3:1 that way (dracula worst at 2.18). Retuning the
selection alpha does not fix it — sweeping 0.18→0.08 still leaves 16→5 failing
while making selection itself harder to see. Pass an OPAQUE fill: flatten the
wash with `flatten(_:over:)` first, or the answer describes a colour nobody sees.
The 0.70 weight is deliberately conservative (0.55 already clears the floor on
every catalog theme, worst 4.37) because an app-supplied surface colour is
outside the sweep. `Sources/PaletteKit/PaletteKit.swift`, *secondaryInk(on:)*.

**on-primary** — `onPrimary(_:)` / `onSecondary(_:)` and their `…Stroke` variants
(the contrast ink at 0.4): the ink for text and icons drawn ON an opaque role
fill. Rooted on the OPAQUE role, never on a wash — that rooting is the whole
distinction from `secondaryInk`, which is rooted on the flattened surface.
`Sources/PaletteKit/PaletteKit.swift`, *onPrimary(_:)*.

**control role** — `ControlRole` (`neutral`, `primary`, `secondary`, `error`),
the single vocabulary each widget maps its own public `Role` enum onto so that
role → colour selection lives in ONE place. `neutral` resolves to `foreground`.
A widget keeps its own possibly-narrower enum and translates; non-role arms
(surface, transparent, custom, washes) stay at the call site.
`Sources/PaletteKit/PaletteKit.swift`, *ControlRole*.

---

## 4. Tokens

**token** — a named constant on a design scale, living in pure `Palette` so a
headless layer can reason about it. Distinguish from a *role*: a role is a
colour that a theme authors, a token is a metric that no theme can change.
`Sources/Palette/Palette.swift`, *ScaleStep*.

**scale** / **ramp** — the ordered set of steps for one metric: `Space`
(2/4/6/8/12/16) and `Radius` (2/4/6/8/12), each a static-let ramp plus a `scale`
array of `ScaleStep` for a bench to render. Off-grid values (1–3px hairlines,
3/5/10/72) are deliberately NOT tokenised. `Sources/Palette/Palette.swift`,
*Space*.

**elevation** — `Elevation` (flat, dp2…dp12) and its `ElevationToken`
(`opacity`, `blur`, `dy`). The token is pure; `ResolvedPalette.shadow(_:)` is the
AppKit-side resolution table, which flips `dy`'s sign for the y-up coordinate
space. `Sources/Palette/Palette.swift`, *Elevation*.

**type role** — `TypeRole`, the semantic text sizes, each yielding a `TypeToken`
(`pt` + `TypeWeight`). MUI-grounded. Named separately from `FontKind`, which
selects the FAMILY (a theme's choice) rather than the size (a token).
`Sources/Palette/Palette.swift`, *TypeRole*.

**transition duration** — `ThemedTransition.Duration`, the shared animation
lengths (`enter` / `exit`) the widgets were retrofitted onto at byte-identical
values, so tokenisation changed no feel. Easing curves are a separate pure
module: `Motion`'s `Easing` is `f(t) → value`, sampled per frame by the app —
sill never owns the clock. `Sources/Motion/ThemedTransition.swift`,
*ThemedTransition*.

---

## 5. The catalog

**catalog** — the built-in theme set. Since #137 it is a TYPE, `enum Theme:
String`, not an array of tuples — because as cases the members are
DECLARATIONS, so cutting one is a reportable API breakage. As strings inside an
array whose signature never changes, a cut was invisible: that is exactly how
`catppuccin-latte` shipped as a MINOR in v1.36.0 and broke wand at its next pin
bump. `Sources/Palette/Palette.swift`, *Theme*.

**preset** — one authored `ThemeSpec` static (`.dracula`, `.gruvbox`, …). Thirty
five exist. **member** — the matching `Theme` case. The two cannot drift: `spec`
is an exhaustive switch, so a new case does not COMPILE until it has an arm —
enforcement by the type checker rather than by a test.
`Sources/Palette/Palette.swift`, *Theme.spec*.

**fixed preset** — the 34 catalog members whose colours are their own, i.e.
everything except `system`. The distinction is load-bearing in every measurement
in this repo: contrast sweeps and byte-equality checks run over the *fixed 34*,
because `system` resolves to live OS inks that no sweep can pin down.
`Sources/Palette/Palette.swift`, *Theme.system*.

**rawValue** — the kebab-case string a user's config and every app's CLI actually
pass (`aurora-flux`, `neon-noir`, `catppuccin-mocha`). It is a SEPARATE break
channel from the case identifier, and the more dangerous one: renaming a rawValue
changes the name in every user config with **no compile error anywhere**, and
`swift package diagnose-api-breaking-changes` reports it clean (measured).
`Tests/PaletteTests/VocabularyTests.swift` is that channel's only guard.

**random** — a meta-name, not a member: accepted by `--theme=` and included in
`canonicalThemeNames`, it picks a concrete non-`system` theme per call. Its
existence is why `canonicalThemeNames` is not simply `Theme.allCases`.
`Sources/Palette/Palette.swift`, *canonicalThemeNames*.

**`paletteFor` vs `Theme.x.spec`** — `paletteFor(_:)` maps an untyped name to a
spec and is FAILABLE (v2): an unknown name returns `nil`, never a made-up
`terminal`. The old total version's fallthrough is what made the latte cut
invisible at runtime, and all three consumer apps had hand-written a loud reject
around it (the rule-of-three that pulled the fix into sill). On `nil` the app
picks the policy — clamp or reject with `suggest` / `retiredTheme`. For a
compile-time identity, skip strings entirely: `Theme.dracula.spec`.
`Sources/Palette/Palette.swift`, *paletteFor(_:)*.

**tombstone** — a `RetiredTheme` in `retiredThemeNames`: the death certificate of
a cut catalog name (`name`, `retiredIn`, `reason`, `tryInstead`). NOT an alias —
`tryInstead` is a hint for an error message and is never auto-resolved, because a
member cut for a quality reason (latte failed the WCAG sweep) has no successor
that means the same thing. A tombstone must never shadow a live name: a member
that returns to the catalog leaves the list (dracula, gruvbox, rainbow and
system all did, so only latte is buried). `suggest(_:)` short-circuits a retired
name to its `tryInstead` instead of a Levenshtein guess.
`Sources/Palette/Palette.swift`, *RetiredTheme*.

**verdict** — a `ThemeNameVerdict`: the classification of one raw theme-name
token through the whole shared decision tree (`classifyThemeName(_:extras:)` —
caller extras → live catalog → tombstone → did-you-mean), as one value:
`.canonical` / `.retired` / `.unknown(suggestion:)`. The tree became vocabulary
because every consumer app had hand-written the same cascade around the
individual primitives (the t-0j0z sweep rewrote it in three repos in one day).
What to DO with a verdict stays app policy — clamp, exit(2), log; sill only says
what the name IS. Satellites: `RetiredTheme.story` (the one authored reject
sentence), `concreteRandomThemeName(extras:)` (the stable `random` roll),
`paletteForCanonical(_:)` (the loud twin of `paletteFor` for pre-validated
names). `Sources/Palette/Palette.swift`, *ThemeNameVerdict*.

**effect name** — a member of `canonicalEffectNames`, the vocabulary accepted by
`[border] effect`. The NAME lists live in pure `Palette`, not in `Effects`,
because a no-AppKit Core must be able to validate a config token without linking
a module that compiles AppKit. Seven of them (`voltage`, `toxic`, `ember`,
`solar-veil`, `molten-vein`, `coin-op`, `arcane`) plus the trio (`biolume`,
`midas`, `spectre`) are theme+effect PAIRS, so each name is simultaneously a
valid theme and a valid effect. `Sources/Palette/Palette.swift`,
*canonicalEffectNames*.

**pet** — a `LinePet` (`chomp`, `ghost`): a small arcade sprite that walks a
surface's outline, shared across facet's tree, halo's ring and wand's cards.
Theme-AGNOSTIC by design — its colours are baked into its silhouette, so it reads
the same under any theme. Pure identity here; the drawing lives in `Effects`.
`Sources/Palette/Palette.swift`, *LinePet*.

**effect spec** — `EffectSpec`, the animated colour-only atom in `Effects`.
`Effects` is the one AppKit module whose subject is animation over time rather
than a widget. `Sources/Effects/Effects.swift`, *EffectSpec*.

> **Known dangling reference.** Two doc comments in `Sources/Palette/Palette.swift`
> say "see `retiredThemeNames`". No such symbol has ever existed — the citations
> shipped with #137 pointing at nothing. The concept they mean is the rawValue
> break channel described above; there is no list of retired names in the tree.

---

## 6. The AppKit floors

**floor** — one of the exactly THREE places SwiftUI genuinely cannot reach, where
AppKit is permitted. The widget layer is SwiftUI by DEFAULT; a floor is a
permission, not a preference. Confirmed 2026-06-23, widened from two to three on
2026-06-30.

- **floor 1**, the **edit core** — `NSTextField`'s field editor: detecting marked
  text and routing Enter/Esc/↑↓ differently while an IME conversion is
  uncommitted. The edit core ONLY; frame, label, icon, colours and error state
  are SwiftUI.
- **floor 2**, the **window shell** — `.nonactivatingPanel`: a window that floats
  without stealing focus, and a popup that escapes its parent window. The shell
  ONLY; the contents go through `NSHostingView` and are SwiftUI.
  `Sources/ThemeKit/WindowShell.swift`, *WindowShellSpec*.
- **floor 3**, the **draw core** — selectable rich text: continuous selection and
  copy, the rounded inline-code pill (`NSLayoutManager.fillBackgroundRectArray`),
  and real `NSTextTable` tables, code blocks and blockquote rules. SwiftUI's
  `Text`/`textRenderer` is mutually exclusive with `.textSelection` (proved in
  prism, 2026-06-30). The `NSTextView` draw core ONLY.
  `Sources/MarkdownKitUI/`, *MarkdownView*.

**IME-adjacent composition** — how a widget whose visible control IS the floor-1
field (today only the combo box) splits across the floors; settled 2026-08-02,
ahead of its migration, because a naive rewrite would step through the floor.
The combo owns NO floor of its own — it composes three layers that each already
have a home:

- the FIELD is a real `ThemedTextField` — **floor 1**. Hosting it in SwiftUI
  goes through the floor-1 file's representable ONLY (`FieldHostProxy` in
  `ThemedTextFieldView.swift`, the adoption seam for a controller-owned field);
  a composite widget never declares its own `NSViewRepresentable` for it.
- the POPUP is `PopupPanel` + the dismiss monitor + `PopupGlue` — **floor 2**,
  untouched.
- the ROWS are the hosted SwiftUI list (`HostedThemedList`) — already native.

The controller's DIRECT references to its field — the synchronous commit's
focus re-assert, the silent committed-label push while the field is first
responder, the AX value announcements — are floor-1-adjacent WIRING and stay
AppKit: a SwiftUI binding push is asynchronous by design (it lands on a later
render) and is suppressed while the field is first responder, either of which
breaks the commit-before-the-next-tick-focus-reconcile discipline the edit
core requires. What floor 1 does NOT cover is view-layer bridging: that is why
`ThemedComboBoxView`'s own representable conformance was **debt**, not floor.
`Sources/ThemeKitUI/ThemedComboBox.swift`, *the synchronous commit*.

**debt** — an AppKit construct in the tree that is NOT justified by a floor, i.e.
awaiting SwiftUI conversion. At booking (2026-07-28) the count was **16
constructs of which 14 were debt**; the 床外し epic booked the last one out on
2026-08-02, leaving **3 constructs, all floors** — `ThemedTextFieldView` (floor
1, whose file also carries the `FieldHostProxy` adoption seam),
`PopupAnchorProxy` (floor-2 plumbing) and `MarkdownTextView` (floor 3). The
number is printed on every green run precisely so nobody reads the green as
"policy met" — from here, any nonzero debt count is a regression.
`scripts/appkit-floor.sh`, *allow-list*.

**要相談** — the standing rule for anything beyond the three floors: ask the user
first, do not widen AppKit unilaterally. It applies to the named near-misses too
— dot art is `Image(…).interpolation(.none)`, particle glow is SwiftUI `Canvas`
with `.addFilter(.shadow)`, blur is `Material` — each of which may use AppKit
only after a conversation about fidelity. [`../CLAUDE.md`](../CLAUDE.md),
*AppKit 使用可ポリシー*.

---

## 7. Gates

**gate** — a check that blocks a merge. sill's are shell scripts rather than
XCTest cases wherever possible, deliberately: a script can be run on a
CommandLineTools-only machine and can be proved in **both directions** locally,
which XCTest here cannot (see §9).

**ratchet** — a gate whose bar MOVES with the tree instead of standing still. The
AppKit and interaction-alpha gates are ratchets; a plain gate says "this stayed
legal", a ratchet says "this got no worse, and the record of how bad it is stays
honest". `scripts/appkit-floor.sh`, *HOW IT RATCHETS*.

**set equality** — how `appkit-floor.sh` ratchets: the allow-list is compared for
SET equality, not "no new entries". So an unregistered AppKit construct fails,
AND a stale entry whose code was deleted also fails. A migration PR therefore has
to delete its own line, and the list can only shrink.
`scripts/appkit-floor.sh`, *allow-list*.

**allow-list** — an explicit exemption list. sill has two, and they mean
different things. `scripts/interaction-alphas.sh`'s four entries are NOT debt:
each is a genuinely different concept that merely shares a number (a drag-and-drop
drop wash, a badge tint, a shimmer stop, a static cell fill), and forcing them
through `stateOverlay` would be wrong. `.api/breakage-allowlist.txt` is for
removals that are provably not breaks; every entry needs its own `# why:` line,
and the file carries a required `rationale:` marker that `api-guard.sh` refuses
to run without — so the list can never silently become a rubber stamp. It is
empty today, which is the correct starting state. `scripts/theme-env.sh` has NO
allow-list at all, so it cannot be bypassed by adding an entry.

**both directions** — the standard for accepting a gate: prove it goes RED on a
violation as well as green on a clean tree. It is not ceremony. Writing
`api-guard.sh` this way caught two of its own `set -e` bugs, and `theme-env.sh`'s
first pattern silently SKIPPED five generic views (`ThemedListView<ID>`) while
reporting "all ambient-aware" — an under-counting gate is worse than no gate,
because it looks like coverage. Hence the companion rule: count what a gate
inspected, do not just read its exit status.

**baseline** — what `api-guard.sh` diffs against: the **merge-base**, not a tag.
sill batches tags, so a tag baseline would make one PR inherit every other PR's
removals. `scripts/api-guard.sh`, *baseline*.

**blind spot** — a break channel a gate provably cannot see. `api-guard.sh`'s is
rawValue strings: the differ sees case IDENTIFIERS, so a rawValue rename reports
clean (measured). Named as a term because a gate's blind spots have to be
written down where its greens are read, or the green is misread as total.

**green means** — the standing caution attached to every ratchet's success line:
green means "the debt did not grow", NOT "the policy is met". `appkit-floor.sh`
prints this on every successful run.

---

## 8. Release and consumers

**rule of three** — the bar for a widget entering sill: ≥2 apps would otherwise
hand-draw it. Suspended while the apps are frozen (a trigger that waits for two
apps never fires when no app is moving), but only for design-system completeness
and internal consistency — not as licence to add anything.
[`ROADMAP.md`](ROADMAP.md).

**consumer** — one of the six apps that depend on sill: facet, wand, perch, halo,
glance (chord is headless). "Consumer" also appears in the narrower API sense —
the party a break would reach — and the two coincide here.

**pin** — a consumer's `.upToNextMinor(from:)` version requirement. Understand
what it does and does not buy: it excludes a new minor AND a new major alike, so
the semver level buys **no automatic protection**. The pin is the safety
mechanism; a major's entire job is to be the signal a human reads when they
hand-bump a pin. That is why a mis-rated removal is so expensive — it is
invisible at exactly the moment someone is looking. [`../CLAUDE.md`](../CLAUDE.md),
*Conventions*.

**flag day** — a coordinated bump of every consumer's pin at once. Because all
six pins are hand-bumped anyway, batching majors into one flag day is cheaper
than dribbling them out.

**on main vs released** — two states that look the same in a green CI run and are
not. A fix merged to `main` reaches NO consumer until a tag exists, because every
consumer resolves by version. This was a real eight-day outage: sill#138's popup
fix sat on main untagged while wand#182 stayed structurally blocked, and nothing
in the repo said so. `.github/workflows/release.yml`, *WHY THIS FILE HAD TO
EXIST*.

**rolling draft** — the single glyph-managed DRAFT GitHub release that a push to
main upserts. glyph walks main's squash commits since the highest `v*` tag,
resolves each to its merged pull request and classifies that PR's individual
pre-squash commits, so a squash-merge cannot lose a per-commit gitmoji type.
Nothing is persisted, so the draft is self-healing. `.github/workflows/release.yml`.

**publish** — the human click that turns the draft into a release AND creates the
git tag. Deliberately manual: the tag is what actually reaches six consumers, so
that step is the intended gate. A workflow run is not a shipment.
`.github/workflows/release.yml`, *WHAT A RELEASE MEANS HERE*.

**fleet** — the family of repositories that share canonical workflows from
`akira-toriyama/.github`, distributed by fleet-sync (hence the `:robot:
chore(fleet)` commits that make up most of sill's log between releases). A change
to a fleet canonical follows its own staged policy and is out of scope for a
sill-local PR.

---

## 9. Verification

**bench** — `prism`, the executable that renders every catalog theme next to
every real widget. It is a CONSUMER of the public modules, never an importer of
an app's View code, so it cannot drift from what an app would see.
`Sources/prism/`, *Gallery*.

**showcase** — the per-widget page a new widget MUST add to the bench (29 of
them): a `Themed<Widget>View` bridge in `ThemeKitUI` that prism imports, plus a
**mock** — a `Mock<Widget>` view taking the palette as `p` — so the widget
appears live across all themes. A mock conforms to `ShowcaseBench` to get the
shared captioned-cell chrome, and its tab is a `KitFamily` case. (Older notes
say mocks are "wired into `ThemeCard`"; that type is RETIRED — its
responsibilities were folded into `FoundationAppPage` and the per-showcase
files.) `Sources/prism/ShowcaseChrome.swift`, *ShowcaseBench*.

**compile bar** — `swift build`: the fast check that works on CommandLineTools.
It proves the tree compiles and nothing else. Distinguish from the **local test
gate** — `scripts/test.sh`, which runs the full XCTest suite by pointing
`DEVELOPER_DIR` at an INSTALLED Xcode and building into an isolated
`.build-xcode/` so Swift-6.3 test artifacts never clobber the CLT `.build/`. On a
machine with no Xcode at all, `scripts/test.sh` and `swift test` both fail and
**there is no local test gate**: CI is then the FIRST execution of any test
written, and a report must say so rather than implying a test passed. Adding
swift-testing as a package dependency does not rescue it — the generated runner
links `_TestingInterop`, which is toolchain-only (measured 2026-07-26).

**live proof** — the standard for claiming a widget works: `swift test` catches
LOGIC, not SwiftUI RENDER. The canonical counter-example is #17f's GFM table,
where the parser tests passed while the body rows rendered blank — caught only in
prism. Hence: prove UI behaviour live in the bench, and do not claim a widget
works off a green test alone. The capture recipe (windows jump Spaces under a
tiling window manager) is to launch `.build/debug/prism` with `PRISM_CONFIG`, get
the window id, and `screencapture -l<winid> -o out.png` WITHOUT
`osascript`-activating, using the widget's `preview…` overrides so a static
screenshot is deterministic. [`../CLAUDE.md`](../CLAUDE.md), *Build / test*.
