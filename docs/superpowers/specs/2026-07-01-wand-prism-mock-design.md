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

## Phasing (decided 2026-07-01)

Split into two PRs (writing-plans' "separate plans per subsystem" + this spec's
split fallback), because a deep read of `ThemedMenu` showed the two capabilities
are very different sizes:

- **PR1 — N-level cascade + wand vertical mock** (the first plan). N-level is a
  small, high-confidence change: the existing `activeLeaf()` / `teardownAsChild()`
  / `clickIsInside()` / `.submenu` placement already recurse; only two
  `parentMenu == nil` guards (`ThemedMenu.swift:446`, `:467`) + one
  `validateOpenChild()` recursion + doc updates are needed. It covers wand's
  DEFAULT `.list` launcher — enough for a faithful wand mock.
- **PR2 — horizontal presentation** (`.toolbar` / `.labeledToolbar`) — **✅ DONE
  (2026-07-01)**. Originally scoped as "a new horizontal layout inside `ThemedMenu`",
  but a build-time investigation found sill ALREADY ships the right widget: the
  **`ThemedToolBar`** (icon-only / icon+label bar) was built with the exact
  launcher affordances this needs — `trackingMode = .nonActivatingPanel` hover +
  `frameOnScreen(ofItem:)` / `onItemHover`, whose header comment literally cites
  "anchor a child panel below a folder button" *for wand's tome*. So PR2
  **COMPOSES** it (see "PR2 as-built" below) instead of re-drawing a horizontal
  layout — far more reuse, `ThemedList` untouched, and no new AppKit. The ② design
  below is the intent; the as-built section records the (better) realization.

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

### Static card + live trigger (the two-tier bench pattern — mechanism corrected)

A `ThemedMenu` is a floating child-window controller, so its open panels can NOT
appear in prism's main-window `screencapture` (`MenuShowcase.swift:1-13`). The
deterministic per-theme card is therefore built from **inline `ThemedListView`s**
configured exactly as `ThemedMenu` hosts them (the existing `MockMenu` recipe,
`MenuShowcase.swift:86-102`): to depict an **open cascade**, compose a root
`ThemedListView` + a second `ThemedListView` offset to its right, each with a
`previewHighlight` row — a faithful still of a 2-level cascade that re-themes
across every palette. The **real** extended `ThemedMenu` (N-level live) is proven
beside it via a **live trigger** (`ThemedMenuTriggerView`: click → real cascade
panels; hover / ↑↓ / → / ← / Esc). The `previewOpen` / `previewHighlight` seam
stays **test/live-only** — it drives XCTest and the live trigger, and is NOT the
screenshot path (so no seam change is needed just for the card).

## What we build

**PR1 (this plan) — N-level cascade + wand vertical mock:**

- **`ThemeKit/ThemedMenu.swift`** — relax the two `parentMenu == nil` guards
  (`:446` in `handleHover`, `:467` in `openSubmenu`) so a child may open its own
  child at any depth; recurse `validateOpenChild()` (`:513-524`) so descendants
  re-anchor when an ancestor reframes/scrolls; refresh the one-level-cap docs
  (`:59-62`, `:167-171`). The `.submenu` placement (`PopupPanel.swift:211-226`),
  `activeLeaf()`, `teardownAsChild()`, `clickIsInside()` already recurse — no
  change. **`PopupPanel.swift` is untouched in PR1.**
- **`Tests/ThemeKitTests/ThemedMenuTests.swift`** — replace the one-level-cap test
  (`:419-432`) with depth-N tests: a depth ≥ 2 cascade opens; root dismiss tears
  the whole chain; Esc closes one level at a time; hovering a non-submenu ancestor
  row collapses deeper levels. (CI-run — XCTest doesn't run on the CLT-only local.)
- **New file `Sources/prism/WandShowcase.swift`** housing
  `struct MockWandLauncher: View { let p: ResolvedPalette }` (following
  `PerchShowcase.swift` / `GlanceShowcase.swift`). **Replace + delete** the
  hand-drawn `MockTome` (`Specimens.swift:305`). Repoint `case .wand:`
  (`Gallery.swift:379`) to `MockWandLauncher`. Rationale: the de-risk is composing
  the REAL kit — inline `ThemedListView`s mirror `ThemedMenu`'s own item→row
  mapping (the `MockMenu` precedent) and the live trigger opens the REAL extended
  `ThemedMenu`; a hand-drawn fake tome would be drift (the perch `MockPill` /
  glance `MockMarkdown` precedent).
- **`Sources/prism/KitCatalog.swift`** — update the `ThemedMenu` entry (`:430-431`)
  from "one-level" to N-level cascade; refresh the wand `AppChrome` (`:596-599`) to
  note the mock now exercises `ThemedMenu`.

**PR2 (follow-up) — horizontal presentation:**

- **`ThemeKit/ThemedMenu.swift`** — add the presentation mode
  (`.vertical` / `.toolbar` / `.labeledToolbar`) + the horizontal row layout.
- **`ThemeKit/PopupPanel.swift`** — below-anchor placement for a horizontal parent.
- **`ThemeKitUI/ThemedMenuTriggerView.swift`** — expose the presentation mode.
- **`WandShowcase.swift`** — add the `.toolbar` / `.labeledToolbar` specimen.

## PR2 as-built (2026-07-01) — COMPOSE `ThemedToolBar`, don't re-draw a layout

The build-time investigation (user-approved deviation, "推奨でOK") replaced "a new
horizontal row layout inside `ThemedMenu`" with **composition of the existing
`ThemedToolBar`** — sill's horizontal app bar, whose `.nonActivatingPanel` hover +
`frameOnScreen(ofItem:)` / `onItemHover` were purpose-built for wand's launcher.
Payoffs: maximal reuse (icon-only / icon+label + hover + AX come free), **`ThemedList`
untouched** (it is vertical to the bone — a horizontal axis would be a large, risky
retrofit), and the spec's "new AppKit machinery → 要相談" halt condition is **avoided**
(pure composition of shipped widgets — no new floor, `床3個` unchanged).

- **`Sources/ListCore/MenuLogic.swift`** — `menuKeyIntent(keyCode:, orientation:)`
  (default `.vertical`): a horizontal leaf flips the axes — ←→ move along the bar,
  ↓ opens the child below, ↑ inert; `.vertical` mapping byte-identical to before.
- **`Sources/ThemeKit/ThemedMenu.swift`** — a `Presentation` (`.vertical` /
  `.toolbar` / `.labeledToolbar`); a horizontal ROOT hosts a `ThemedToolBar`
  (transparent surface, `.nonActivatingPanel`, `.compact`/`.dense` per mode) instead
  of the `ThemedList`; `MenuItem → ThemedToolBar.Item` mapping (icon-only vs
  icon+label + a `caret-down` on labeled folders); orientation-aware content helpers
  (`rowRectOnScreen` / `moveContentHighlight` / `highlightedContentID` /
  `activateContentHighlight` / `clearContentHighlight`); `handleKeyDown` routes by
  the active leaf's `orientation`. **CHILDREN stay vertical** (a menu bar's dropdowns
  are vertical), and a horizontal parent's child drops **BELOW** the bar item —
  reusing the existing `.anchorCorner` drop-down placement, so **`PopupPanel.swift`
  is UNTOUCHED** (the planned "below-anchor case" was unnecessary — a drop-down below
  an anchor already IS `.anchorCorner`).
- **`Sources/ThemeKit/ThemedToolBar.swift`** — one small additive prop:
  `highlightedItem: Int?`, a PERSISTENT keyboard cursor for menu-bar nav (precedence
  in `applyHover`: `previewHoveredItem` capture > `highlightedItem` keyboard > live
  mouse hover) + probe fields. `nil` default ⇒ a plain toolbar is byte-identical.
- **`Sources/ThemeKitUI/ThemedMenuTriggerView.swift`** — exposes `presentation`.
  **`ThemedToolBarView.swift`** — additive `trailingSymbol` on the `.button`
  descriptor (folder caret in the static card).
- **`Sources/prism/WandShowcase.swift`** — Tier 3: a static `.toolbar` icon strip +
  a `.labeledToolbar` bar with a leading folder OPEN (an inline `ThemedListView`
  dropdown beneath it) + two LIVE triggers (`.toolbar` / `.labeledToolbar`) that open
  the REAL horizontal `ThemedMenu`. **`KitCatalog.swift`** — `ThemedMenu` entry +
  wand `AppChrome` note the horizontal modes.
- **Tests** — `ThemedMenuTests` +11 (item→bar mapping, ←→ nav + wrap, ↓ opens the
  vertical child, ⏎ activates + dismisses, click opens a folder, preview-highlight,
  Esc dismiss, child-is-vertical) · `MenuLogicTests` +4 (the orientation flip).
- **Verified**: `swift build` green (CLT); the FULL suite run locally under the
  Xcode 26 toolchain (`DEVELOPER_DIR=…Xcode-26…`) — **787 tests, 0 failures**; prism
  live (the UI gate) — see the Verification section.

### Scene composition (`MockWandLauncher`) — PR1

A non-activating **launcher tome** (the `MockWindowShell` "shell surface" recipe:
theme `background` fill, rounded, drop shadow, a `panelStroke` outline) in two tiers:

- **the tome (static, deterministic)**: the **real** `ThemedTextFieldView` query
  field (already real in `MockTome` — keep it, the `open…` box) above an **inline
  `ThemedListView`** of command rows (an app-launch result via real `appIcon`, a
  couple of Phosphor action rows, a `chevron` "Open in…" folder row, a "Switch
  Branch" folder row). To depict the **open cascade**, a **second inline
  `ThemedListView`** is offset to the right of the folder row, showing that
  folder's children (faux git branches — the static still of wand's async submenu
  result). Both lists carry a `previewHighlight` so the 2-level cascade reads
  deterministically on every theme.
- **the live proof**: a `ThemedMenuTriggerView` beside the tome, whose items
  include a ≥ 2-level submenu, opens the **real extended `ThemedMenu`** — click,
  then hover / ↑↓ / → / ← / Esc to feel a true N-level cascade (which the static
  shot can't hold).

`ThemeCard` supplies `p` across all themes; on an animatable theme its 30 Hz
`TimelineView` (`Gallery.swift:282-293`) drives `p`, so selection/accent re-theme
live with the rest of the bench. The `.toolbar` / `.labeledToolbar` horizontal
specimen is **PR2**.

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
