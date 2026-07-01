# wand prism app-mock + ThemedMenu N-level / horizontal — design (2026-07-01)

Task: **t-yc68** (sill: prism app-mock 再構築 — Phase B 適用の前段), wand arm.
Depends on already-shipped sill parts: **#17i WindowShell (PR #88, t-dsqb)** — the
floor-#2 popup shell `ThemedMenu` already sits on.

**Deviation from the perch/glance arms (deliberate).** perch consumed a
pre-shipped widget (#17g ThemedPill), glance a pre-shipped widget (#17f
MarkdownKit); each arm just *composed* the shipped part and named residual gaps.
wand is different: the coverage finding is that **`ThemedMenu` is not yet
sufficient** to represent wand's launcher, so this arm **builds two general menu
capabilities into `ThemedMenu` first** (N-level cascade + horizontal
presentation), then proves them in the wand mock. This is the **"ThemedMenu
N段(wand)"** build item from the t-yc68 body's build order — i.e. the arm's
de-risk payoff is the widget extension itself, not just the mock.

## Goal

Rebuild wand's signature **launcher-tome** chrome (a non-activating, cascading
command launcher) in the prism visual bench out of the **real** `ThemedMenu`,
extended to the two things wand's launcher needs that `ThemedMenu` lacks —
**arbitrary-depth (N-level) cascade** and **horizontal (toolbar /
labeled-toolbar) presentation** — and confirm it composes across ALL catalog
themes. A cheap de-risk before wand's real application, mirroring the shipped
perch/glance arms. prism imports no app View, so the scene is mirrored by eye
(zero drift). wand ships 7 themes in production; the bench's payoff is proving the
same launcher chrome themes generically on every catalog theme.

## Coverage finding (inverted — what's missing)

An investigation (wand `LauncherPanel.swift` / `Launcher.swift` ↔ sill
`ThemeKit/ThemedMenu.swift` / `ListCore/MenuLogic.swift` /
`ThemeKitUI/ThemedMenuTriggerView.swift`), adversarially verified:

- **wand's launcher is a bespoke panel-tree launcher**, not an `NSMenu`: it builds
  an immutable tree from a flat item list via `PanelTree.build()` walking each
  item's `group: [String]` path, and opens each level as a separate
  non-activating `NSPanel` on hover. Depth is bounded only by the group nesting.
  Evidence: wand `LauncherPanel.swift:225-283`, `:1192-1237`.
- **`ThemedMenu` today is a healthy foundation but under-powered for this**: pure
  key routing is factored to `ListCore/MenuLogic.swift` (Sendable intents); the
  popup shell is the shared floor-#2 `PopupPanel`; the one-child cascade
  machinery already exists (`openSubmenu` creates a child `ThemedMenu` + a
  `parentMenu` weak-ref; `activeLeaf()` recurses to the deepest open menu for key
  routing; the root owns the single key/mouse monitor, children install none).
  BUT it is **capped at ONE cascade level** — an explicit `parentMenu == nil`
  guard makes grandchildren dead — **static arrays only** (no async / deferred
  provider), and **vertical drop-down only** (no horizontal / labeled / section).
  Evidence: sill `ThemedMenu.swift:59-63` (one-level doc), `:467` (the
  `parentMenu == nil` guard) + `:173` (the single `child: ThemedMenu?` property —
  the real structural cap), `:476-487` (`openSubmenu` reads `mi.submenu` directly),
  `:534-535` (`activeLeaf` recursion already present), `:276-292` (only vertical
  present entry points).

So — unlike perch/glance — a *minimal* wand mock built on today's `ThemedMenu`
(one level, vertical) could not represent wand's cascade/toolbar signature at all;
the mock is only meaningful once the two capabilities exist. That drove the scope
decision below.

## Boundary (user-approved 2026-07-01)

sill gains the two **general** menu capabilities; wand-specific machinery stays
app-side.

- **sill builds**: ① N-level cascade (lift the one-level cap) · ② horizontal
  (`.toolbar` / `.labeledToolbar`) presentation. Both are generic menu features
  (every menu system / MUI `<Menu>` has them), not wand-specific hacks.
- **wand keeps (essential divergence)**: the `PanelTree` group-path builder; the
  **async submenu = live shell exec + template substitution** and the `shell:`
  state predicate; and all **motion** (open/close animations, chomp line-pets,
  animated border cycle) — sill's `Effects` atom is color-only and cannot carry
  motion.
- **deferred (not this arm)**: a *general* async/deferred `submenuProvider` hook.
  The mock fakes wand's async submenu with **static deferred data**; whether sill
  should own a generic provider closure is a rule-of-three call for later.

**Rule-of-three note.** wand is the *first* consumer of N-level + horizontal, and
today the *only* heavy one (facet uses simple drop-downs). Both are standard
menu-system features, and both changes are **additive to an existing widget** (low
breakage risk), so building them now is defensible pre-Phase-B groundwork. If a
2nd consumer never materialises (candidates: facet toolbar menus, a halo submenu),
the split-PR fallback (below) keeps the widget change isolated and revertible.

## Design

### ① N-level cascade — approach A: generalize the existing single-child chain

**Model note (verifier-corrected).** Each `ThemedMenu` holds exactly ONE
`child: ThemedMenu?` (`ThemedMenu.swift:173`), not an array. For a cascade that is
*correct*: only one path is ever open at a time, so N-level = a **recursive
single-child chain** (a child opens its own child, and so on) — NOT multiple
siblings open at one level. So "no model change" is precise in two senses:
`MenuItem.submenu: [MenuItem]` is already recursive data (`:63`), *and* the
single-child controller chain already expresses a cascade. What's missing is only
that the code refuses to descend past depth 1 and does not re-anchor descendants.
Build:

- **Lift the cap**: relax the `parentMenu == nil` guards in `openSubmenu` (`:467`)
  and `handleHover` (`:446`) so a child may open its own child at any depth.
- **Descendant re-anchoring (real work, not free)**: today `validateOpenChild()`
  (`:513-524`) re-places only the DIRECT child from its stored `submenuRowOnScreen`
  rect (set once at open, `:529`); a grandchild has no way to re-anchor when an
  *ancestor* scrolls/reframes. Make `validateOpenChild()` **recurse**
  (`if let c = child { c.validateOpenChild() }`) so every descendant re-places down
  the chain. The per-level `.submenu` placement (`PopupPanel.swift:211-226`,
  right-of-row + left-flip) is already independent per call and needs no change —
  only the recursive re-validation is new.
- **Hover-collapse policy (document + test)**: hovering a non-submenu row at any
  level calls `closeChild()`, which recursively tears down all deeper levels
  (children-first, `:502` + `:312`). That IS the intended cascade collapse; the
  spec makes it explicit and covers it with a test (below), since today it is
  untested (`ThemedMenuTests.swift:419-432` asserts the one-level *cap*, not
  depth-N teardown).
- **Key routing**: `activeLeaf()` (`:534-535`) already recurses to the deepest open
  menu, and only the root installs the key/mouse monitor (children install none) —
  correct as-is at depth N; every key event flows from the root's single monitor.
  The pure `MenuLogic` `.openSubmenu` / `.closeLevel` intents are unchanged (keeps
  the testable seam).
- Chose A over a from-scratch tree-model rewrite (approach B: a `MenuNode` tree +
  one panel-stack controller, à la wand's `PanelTree`/`PanelController`): A is a
  focused change to a working widget and reuses the child-chain + `activeLeaf` +
  recursive teardown that already exist. B is recorded as a future candidate if
  cascade ever grows heavy.

### ② Horizontal presentation — a mode on the same widget

Add a presentation mode (do **not** fork a second widget): `.vertical` (default)
/ `.toolbar` (icon-only) / `.labeledToolbar` (icon + label). Mirrors wand's
`LauncherLayout` (`Launcher.swift:181-213`). Build:

- The **root** panel lays rows in a horizontal stack for `.toolbar` /
  `.labeledToolbar`; **submenu children stay `.vertical`** (matches wand — a child
  is always `.list`, hardcoded in `openChild` at `LauncherPanel.swift:1207-1209`;
  the root's own layout switch is `:353-371`).
- **Placement flip**: a horizontal root's folder child opens **below** the hovered
  row, not right-of it (wand `LauncherPanel.swift:538-558`) — add a
  `PopupPlacement` case for "below-anchor when the parent is horizontal".
- **Metrics flip** for horizontal (width grows with items up to a max-width, then
  clamp / horizontal scroll); `.toolbar` = icon-only buttons with the label as a
  tooltip, `.labeledToolbar` = icon+label pill rows.

### Preview seam (deterministic across-theme cards)

`ThemedMenu` exposes `previewOpen` / `previewHighlight` for tests (the static
`MenuShowcase` inline-renders a `ThemedList` for the look). Extend the seam so the
static prism card can force (a) a cascade opened to depth ≥ 2 and (b) a horizontal
layout — so `ThemeCard` renders N-level + horizontal **deterministically** for a
screenshot (the investigation's "Preview Seam Expansion" gap). A **live trigger**
(the real `ThemedMenu` opening on click) sits beside the static card for real
interaction / key-routing verification — the perch/glance two-tier pattern.

## What we build

- **`ThemeKit/ThemedMenu.swift`** — lift the one-level cap (N-level cascade); add
  the presentation mode (`.vertical` / `.toolbar` / `.labeledToolbar`); extend the
  preview seam (force cascade depth + horizontal).
- **`ThemeKit/PopupPanel.swift`** — parent-chain submenu placement at depth N;
  below-anchor placement for a horizontal parent.
- **`ListCore/MenuLogic.swift`** — the pure intents already cover cascade
  navigation; add XCTest for N-level intent routing if any new pure logic lands.
- **`ThemeKitUI/ThemedMenuTriggerView.swift`** — expose the presentation mode (and,
  if cheap, a nested-items builder) on the SwiftUI bridge.
- **New file `Sources/prism/WandShowcase.swift`** housing
  `struct MockWandLauncher: View { let p: ResolvedPalette }` (following
  `PerchShowcase.swift` / `GlanceShowcase.swift`). **Replace + delete** the
  hand-drawn `MockTome` (`Specimens.swift:305`, real query field + hand-drawn
  rows). Repoint `case .wand:` (`Gallery.swift:379`) to `MockWandLauncher`.
  Rationale: hosting the REAL extended `ThemedMenu` is the whole de-risk point; a
  fake tome beside the real one is drift (the perch `MockPill` / glance
  `MockMarkdown` precedent).
- **`Sources/prism/KitCatalog.swift`** — update the `ThemedMenu` entry
  (`:430-431`) to note N-level cascade + horizontal modes; refresh the wand
  `AppChrome` (`:596-599`) if the mock now exercises `ThemedMenu`.

### Scene composition (`MockWandLauncher`)

A non-activating **launcher tome** (the `MockWindowShell` "shell surface" recipe:
theme `background` fill, rounded, drop shadow, a `panelStroke` outline) containing:

- the **real** `ThemedTextFieldView` query field (already real in `MockTome` —
  keep it) — the launcher's `open…` box;
- the **real (extended)** `ThemedMenu` rendering the command rows: an app-launch
  result row (real `appIcon`), a couple of action rows (Phosphor glyphs), a
  **folder that cascades ≥ 2 levels** (proving N-level), and a "Switch
  Branch"-style folder whose children are **static deferred data** (faux git
  branches — representing wand's async submenu without a shell);
- a **second specimen** staging the `.toolbar` / `.labeledToolbar` horizontal
  variant (icon-only + icon+label rows, with a child opening below).

`ThemeCard` supplies `p` across all themes; on an animatable theme its 30 Hz
`TimelineView` (`Gallery.swift:282-293`) drives `p`, so selection/accent re-theme
live with the rest of the bench.

## App-essential (stays in wand)

The `PanelTree` group-path tree builder; the async submenu = live shell exec (500
ms budget) + `{line}` template substitution (`LauncherPanel.swift:695-717`) and
the `shell:` state predicate; open/close animations (`.fade` / `.pop`,
`:976-1016`); chomp line-pets (60 fps orbit, `:1073-1086`); the animated border
cycle (`:1031-1063`); the non-activating panel lifecycle + global Esc /
outside-click monitors (`:1247-1268`). sill provides the static structure, row
mechanics, theming, and the popup shell; wand owns data supply + motion.

## Out of scope

### True gaps this arm leaves behind (rule-of-three candidates)

- **General async/deferred `submenuProvider` hook** (`(MenuItem) -> [MenuItem]` or
  async) — **THE residual gap** (the wand analogue of perch's #17k / glance's table
  task). This arm fakes it with static deferred data; generalise to a sill hook
  when a 2nd consumer appears. wand's shell/template impl stays app-side regardless.
- **Approach-B tree-model rewrite** (`MenuNode` + panel-stack controller) — only if
  the per-level `ThemedMenu` chain proves too heavy at depth.

### Future polish (cosmetic / additive)

- Icon animation (bounce / pulse on hover; macOS 14+ `NSImage` symbol effects).
- Rich menu-item props (secondary text, badges, indent-level) — `ThemedList` has
  them; `MenuItem` doesn't expose them.
- N-level depth cap (UX) — decide whether depth is unbounded or capped.
- SwiftUI-native menu bridge — retire the `NSView` `ThemedList` content for a
  SwiftUI body (a floor-#2 → SwiftUI migration, #17b-adjacent).
- Section / labeled grouping metadata beyond `header` / `separator`.
- Toolbar many-item wrap / grid + horizontal-scroll polish.

### AppKit scope

N-level = more instances of the *existing* floor-#2 popup shell; horizontal =
layout inside that same panel (its content is the existing `NSView` `ThemedList`,
already floor-#2). **No new AppKit floor is added** — the current count "床3個" is
unchanged by this arm. **Halt and 要相談** (the standing hard gate) if any build
step needs AppKit beyond floor-#2, e.g.: (1) placement needs constraints/geometry
outside the panel; (2) the horizontal layout can't be done within the existing
`ThemedList`/panel and reaches for new AppKit machinery; (3) the presentation mode
needs AppKit-level dispatch. All are expected to stay within floor-#2 — never widen
silently.

## Verification

- **`swift build`** green (the local CLT gate — the only local gate; no Xcode here).
- **`swift test`** in CI — the pure `MenuLogic`, plus NEW XCTest for the depth
  extension (augmenting `ThemedMenuTests.swift:419-432`, which currently asserts
  the one-level cap): (a) a depth ≥ 2 cascade opens once the guard is lifted;
  (b) closing the root dismisses the whole chain; (c) Esc closes one level at a
  time; (d) hovering a non-submenu ancestor row collapses all deeper levels.
- **prism live** (the UI gate): flip to the **wand (Apps)** tab; `screencapture`
  the card across at least **neon-noir** (dark) + **github-light** (light) + one
  **animatable** theme; confirm the **N-level cascade** and the **horizontal
  variant** read across themes (deterministic via the extended preview seam) and
  open a **live-trigger** menu to confirm real cascade open/dismiss + key routing.
  Capture recipe: launch `.build/debug/prism` with `PRISM_CONFIG=…`, get the
  window id, `screencapture -l<winid> -o out.png` (no `osascript` activation).

## Task linkage

- Advances **t-yc68** (wand app-mock) AND ships the **"ThemedMenu N段(wand)"**
  build item. PR footer: `SetStatus-task: …/t-yc68.md in-progress`.
- Implemented off clean `origin/main` in an isolated worktree (parallel-work
  hazard).
- If the `ThemedMenu` extension proves too large for one clean PR, split during
  build: a **ThemedMenu N-level / horizontal** PR (widget + its prism showcase) +
  a thin **wand-mock repoint** PR — the #17g→perch, #17f→glance precedent (widget
  first, mock consumes it). Default is one arm/PR; decide by size at build time.
