# prism shell redesign — single-widget focus (t-ftqa)

**Date:** 2026-07-03
**Task:** [t-ftqa](https://github.com/akira-toriyama/projects/blob/main/.furrow/bodies/t-ftqa.md)
**Status:** design approved (nav model + 6 decisions); revised after an adversarial spec review — ready for implementation plan
**Approach:** A1 (of A1/A2/A3) — Storybook/MUI searchable-sidebar split-view

> This spec was hardened against a 22-finding adversarial review (2 blockers). The two
> load-bearing corrections: **(1)** SwiftUI `.toolbar` / default `.searchable` render into a
> *window NSToolbar* which prism's bare-`NSHostingView` bootstrap does not have, so both would
> silently vanish — the shell therefore uses an **in-content top bar** + `.searchable(placement:.sidebar)`;
> **(2)** the sidebar is driven by an explicit **`SidebarItem` registry**, not by grouping
> `kitCatalog` (which is drifted: 23 catalog entries vs 29 rendered mocks).

---

## 1. Problem

prism shows **too much at once**, so reaching a target widget/cell is slow (trigger:
wanting to watch `ThemedListView` live — collapse / drag / multi-select — during #17b M2,
user: 「画面の情報多くてわからない」). From the shell audit:

- The finest a config can pre-select is a whole **family**, not one widget — to reach
  `ThemedList` you land on the entire `Collection` family (List + Menu + Grid stacked)
  and scroll. ([Gallery.swift:363-366](../../../Sources/prism/Gallery.swift#L363), no per-widget selector.)
- Default launch is the densest screen: `theme = "all"` stacks **35 same-family cards**
  in one `LazyVStack`. ([Prism.swift:53](../../../Sources/prism/Prism.swift#L53) default `"all"`; the shipped `prism.toml` also sets `theme = "all"`; [Gallery.swift:68-82](../../../Sources/prism/Gallery.swift#L68).)
- The one widget wanted (`ThemedList`) is the **tallest** mock — `MockList` alone
  ([ListShowcase.swift:177-360](../../../Sources/prism/ListShowcase.swift#L177)) exceeds a screen.
- The pinned header is a big fixed band: title + Effects toggle, a **36-chip** wrapping
  theme wall, then **two tab rows** (8 Kit + 5 Apps), never scrolls away. ([Gallery.swift:92-126](../../../Sources/prism/Gallery.swift#L92).)
- Lower cells become **unreachable**: the outer `VStack` pins `minHeight: 600*uiScale`
  ([Gallery.swift:86](../../../Sources/prism/Gallery.swift#L86)) while the window can open taller
  than the display and sets **no `contentMinSize`** ([Prism.swift:26-38](../../../Sources/prism/Prism.swift#L26)),
  so when the window is shorter than the pinned content the tail overflows below the window and
  even max scroll can't bring it into view.

Second concern (「ついで」): **`copy ref` scope is too broad** — a spec dump (~24 bullets /
~600 words for `ThemedList`) with **no import line, no compilable init, no cell example**, and
its `consumes`/`keyAPI` text is **stale** (still describes the pre-#17b `NSViewRepresentable`
list, contradicting the now SwiftUI-native `ThemedListView`). ([KitCatalog.swift:45-50](../../../Sources/prism/KitCatalog.swift#L45), entry at ~:395.)

## 2. Goal & non-goals

**Goal:** redesign prism's **shell / chrome / information-design / navigation / visibility**
to MUI-quality readability so "I want to see THIS widget in THIS state" is reached fastest.

**Non-goals (do NOT change):**
- **Widget rendering** — every previewed widget (`ThemedListView`, `ThemedButton`, …) draws
  pixel-for-pixel as today. *Clarification:* prism's **specimen scaffolding** — how each `Mock*`
  view *arranges* its cells — IS refactored so a page can show an Overview subset then "Show all"
  the rest (§4.2). Each individual cell still renders identically; only prism's arrangement changes.
- The **AppKit floors** — the 3 allowed floors live *inside* the widgets; the **shell stays
  pure SwiftUI** (CLAUDE.md「AppKit 使用可ポリシー」). No new AppKit widget/chrome in the shell.
- No **feature bloat** — findability + readability only.

## 3. Decisions (resolved with user, 2026-07-03)

| # | Decision |
|---|---|
| Nav model | **A1** — split-view: searchable widget sidebar → one-widget detail page. |
| Theme axis | Default = **single theme**; **"All"** kept as an option (detail tiles the one widget across all themes). |
| Many-cell default | Page opens on **representative 1–2 cell Overview**; segmented **Overview \| Variants \| States \| API** anchors; **"Show all"** reveals the full cell grid. |
| Live prop controls | **Skip v1 → icebox.** Rely on the widgets' existing `preview*` state overrides. |
| copy ref | **Restructure** `KitComponent` (structured fields) + split `referenceText` into an **agent-optimized paste-ready core** + a collapsed full-API appendix. |
| Deep-link | Add `widget=` (implies family) + keep `theme=` (and `family=` for foundation/app pages). `section=` / `state=` → **icebox.** |

## 4. Design

### 4.1 Layout — split-view (pure SwiftUI, in-content chrome)

- **Host**: switch the bootstrap to `window.contentViewController = NSHostingController(rootView: Gallery(config:))`
  ([Prism.swift:38](../../../Sources/prism/Prism.swift#L38)) — a ~2-line change, still pure-SwiftUI
  content, no new AppKit widget. `NSHostingController` is the supported path for robust
  first-responder / command routing (needed for keyboard ↑/↓ selection and search focus) and
  plays correctly with the new `contentMinSize` (§4.5).
- **In-content top bar** (NOT window `.toolbar` — see §4.7): an `HStack` pinned as a
  `safeAreaInset(edge: .top)` (or the top row of the split-view content) carrying the **theme
  `Picker`** (`All` + 35 canonical names) and the **`EffectToggle`** (moved from the old title
  row). Living in the content view, it is guaranteed to render. Optionally a sidebar
  collapse toggle here (below).
- **Sidebar** — a `List(selection:)` of an explicit **`SidebarItem` registry** (§4.1.1),
  grouped into `Section`s: the Kit families (Palette, Icons, Text, Action, Feedback, Collection,
  Motion, Particles) + an **Apps** section (facet/wand/perch/halo/glance). `.searchable(text:placement:.sidebar)`
  renders the search field **at the top of the sidebar (in-content)** and filters items by
  **name + module + MUI kind** (e.g. "autocomplete" → `ThemedComboBox`). Keyboard ↑/↓ moves the
  `List` selection (see §6 focus note). The selected item's group auto-expands.
- **Detail** — the selected item's page: the **widget page** (§4.2) for widget items, or the
  **bespoke foundation/app page** (§4.2.1) for Palette/Icons/app items, rendered in the top-bar
  theme.
- **Sidebar collapse**: NavigationSplitView's automatic collapse button is itself a *window
  toolbar* item and will be absent here; add an explicit in-content toggle in the top bar
  driving `NavigationSplitView(columnVisibility:)` bound to `@State NavigationSplitViewVisibility`
  (or accept drag-resize-only and state so). v1: an in-content toggle.

#### 4.1.1 `SidebarItem` registry (single source of truth)

`kitCatalog` alone **cannot** drive the sidebar and is already drifted — 23 catalog entries but
**29 rendered mocks**: `ThemedGrid` and `MockIcons` have no catalog entry (`kitComponent()`
returns an empty `.text` stub, [KitCatalog.swift:576](../../../Sources/prism/KitCatalog.swift#L576));
`MarkdownView` IS cataloged (family `.glance`) but has **no standalone mock** (it only renders
inside `MockGlancePopover`); the 5 app mocks (`MockTree`/`MockWandLauncher`/…) aren't cataloged.

Introduce one hand-maintained model as the single source:

```swift
enum SidebarItem: Identifiable {
    case foundation(Foundation)          // .palette (SwatchRow/TypeScale/Token/LiveEffect), .icons (MockIcons)
    case widget(KitComponent)            // a cataloged ThemeKit(UI) widget → widget page (§4.2)
    case app(KitFamily)                  // .facet/.wand/.perch/.halo/.glance → bespoke page (§4.2.1)
}
```

- Each `widget` case must have a real `KitComponent` **and** a concrete `Mock*` binding — so
  add the missing catalog entries (`ThemedGrid`, and decide `MarkdownView`: give it its own
  `MockMarkdownView` page **or** keep it only under the glance app entry, not both).
- `foundation`/`app` cases carry their own display metadata (name/kind) so **search reaches them
  too** (not just `KitComponent` fields).
- Selection state is a `SidebarItem.ID`, not a `KitComponent` (which can't represent
  foundation/app items).

### 4.2 Widget page skeleton (MUI rhythm)

```
┌ header: <name>   MUI <kind> · <family>              [copy ref] ┐
│ segmented:  [ Overview | Variants | States | API ]            │
│ ── Overview (default) ──  representative 1–2 cells (compact)   │
│ ── Variants ──   (anchored)                                   │
│ ── States ──     (anchored)   [ Show all ▸ ]  full cell grid  │
│ ── API ──        (anchored)   key API / variants list         │
└───────────────────────────────────────────────────────────────┘
```

- Segmented control jumps between **anchored sections** via `ScrollViewReader.scrollTo` — a
  specific state is **one click**, not a 900pt scroll.
- **Overview default = representative cells only**, so a tall widget like `ThemedList` fits a
  viewport on open. **"Show all"** expands the full grid — prism's differentiator over MUI.
- **Cell decomposition (scope)**: the current `Mock*` views are *monolithic* (e.g. `MockList`
  builds ~12 cells inline through a private `cell(_:content:)` helper, [ListShowcase.swift:177-360](../../../Sources/prism/ListShowcase.swift#L177)),
  so there is no external handle to render "just the representative cell". Each of the **29
  mocks** must be refactored to expose its specimen cells as an addressable list (each cell an
  identifiable sub-view). This is prism-specimen-scaffolding work (widget draw unchanged, §2).
  **Representative rule** (avoids an editorial bottleneck): default to **cell index 0–1**; a
  widget may override which indices are "Overview" via a small per-mock annotation.
- Deterministic `previewHovered/Pressed/Focused` overrides keep each state a stable screenshot.
- The page renderer is factored out of `ThemeCard`'s `widgetFamily` switch
  ([Gallery.swift:339-390](../../../Sources/prism/Gallery.swift#L339)) into a `WidgetPage(component:mock:…)` view.

#### 4.2.1 Foundation / app page (bespoke template)

Palette/Icons foundations and the 5 app mocks are **not** `KitComponent`s and don't fit the
segmented widget skeleton. Define a second, simpler page template: a **caption/blurb + the mock**,
**no segmented control, no copy-ref**. The app arm must thread the extra inputs the app mocks
need — `MockPerchOverlay(p:themeName:showEffects:)`, `MockHalo(…showEffects:)`
([Gallery.swift:382-388](../../../Sources/prism/Gallery.swift#L382)) — plus the existing
`appCaption` blurb ([Gallery.swift:398-414](../../../Sources/prism/Gallery.swift#L398)). Palette
foundations keep `SwatchRow`/`TypeScaleSpecimen`/`TokenSpecimen`/`LiveEffectStrip` (this is also
where the retired 36-chip color preview is preserved, §8).

### 4.3 Theme axis

- Default = **single theme** view (1 widget × 1 theme = minimum density; the findability win).
- **`PrismConfig.theme` default changes off `"all"`** to a concrete single theme (proposal:
  `"dracula"`), and the shipped `prism.toml` is updated to match. If a user *explicitly* sets
  `theme = "all"`, that is **honored** (they asked for the survey) — the default just isn't `all`.
- **"All"** choice → the detail pane **tiles the one widget's Overview representative cell
  (not the full grid) across all 35 themes**, each tile keeping its own
  `TimelineView(.animation, 1/30)` when `showEffects && isAnimatableTheme` (as today,
  [Gallery.swift:284-290](../../../Sources/prism/Gallery.swift#L284)). Because it tiles one light
  cell per theme (not a family stack), the live-animation load is **≤ today's "all"**.

### 4.4 copy ref — agent-optimized paste-ready core

Audience = **Claude Code receiving the paste** (the existing [`CopyRefButton`](../../../Sources/prism/Gallery.swift#L456)
help already says "paste it to another agent"). Optimize so a pasted block can be **judged and
used at a glance**:

- **Labeled, machine-readable skeleton** an agent keys on: `TYPE TO USE:` / `IMPORTS:` /
  `MINIMAL:` / `CELL:` / `SOURCE:` / `ADVANCED →`.
- **Self-contained & compilable** — no external lookup to instantiate.
- **Default (SwiftUI) vs escape hatch (AppKit) stated with zero ambiguity.**
- **One-line source pointer** (file path) so the agent can deterministically read more.

`KitComponent` ([KitCatalog.swift:39-51](../../../Sources/prism/KitCatalog.swift#L39)) gains
structured fields — `defaultType`, `imports: [String]`, `initSnippet`, `cellType` + `cellInit`,
`sourcePath`, `appkitEscape` — and `referenceText` splits into a **~15-line paste-ready core** +
a collapsed **full-API appendix** (the 24-bullet surface moves under `ADVANCED →`).

**This is content re-derivation, not a reformat**: the current `consumes`/`keyAPI` for entries
like `ThemedList` are **stale** (pre-#17b). So each of the **23 catalog entries** must have its
recipe **authored against the CURRENT public signature and compiled** before landing (a real
per-widget content stream, not a mechanical pass). Corrected exemplar (verified against
[ThemedListView.swift:55-77](../../../Sources/ThemeKitUI/ThemedListView.swift#L55) +
[ListStyle.swift:19-39](../../../Sources/ThemeKitUI/ListStyle.swift#L19) +
[ListItem.swift:13-39](../../../Sources/ThemeKitUI/ListItem.swift#L13)):

```
ThemedList — themed list / menu (sill · ThemeKitUI widget)
TYPE TO USE (SwiftUI): ThemedListView<ID>
IMPORTS:
  import ThemeKitUI   // ThemedListView, ListItem
  import ThemeKit     // Badge, TrailingAccessory (list accessory types)
  import PaletteKit   // ResolvedPalette + resolve(_:)
MINIMAL:
  let palette = resolve(themeSpec)              // @MainActor; themeSpec: ThemeSpec
  var style = ThemedListStyle()                 // selectionMode defaults to .single
  ThemedListView(
      items: [ ListItem(id: "inbox",   primary: "Inbox"),
               ListItem(id: "starred", primary: "Starred", secondary: "3 unread") ],
      style: style,
      palette: palette,
      onActivate: { id in open(id) })           // id IS the ListItem.id (click/Enter)
CELL: ListItem(id:primary:) — only id + primary required (image/secondary/badges/trailing/tint/kind default).
SOURCE: ThemeKitUI/ThemedListView.swift  ·  ADVANCED (opt-in): collapse, multi-select, keyboard, drag/reorder → full API.
```

Note `ListItem` is the generic `ThemeKitUI.ListItem<ID>` (what `ThemedListView` consumes), **not**
the AppKit `ThemeKit.ListItem` — importing both makes a bare `ListItem(...)` ambiguous, so the
recipe attributes `ListItem` to `ThemeKitUI` and keeps only `Badge`/`TrailingAccessory` under `ThemeKit`.

### 4.5 Reachability (root-cause fix, display-safe)

1. The **detail column owns a single `ScrollView`** governing all vertical overflow; delete the
   outer non-scrolling `minHeight: 600*uiScale` pin ([Gallery.swift:86](../../../Sources/prism/Gallery.swift#L86)).
2. Set **`window.contentMinSize`** ([Prism.swift:26-38](../../../Sources/prism/Prism.swift#L26)) with a
   **display-safe height**: `height = min(600*uiScale, visibleFrame.height − margin)` so the
   minimum content floor **never exceeds the display** (a flat `600*uiScale` = 900pt would exceed
   a 1440×900 laptop's ~837pt usable height and re-strand the tail).
3. **Clamp the opening height** to the display: `winH = min(820*uiScale, visibleFrame.height)`
   at [Prism.swift:31](../../../Sources/prism/Prism.swift#L31).

Because one widget page (or one anchored section) fits a viewport, the tail-overflow can't recur.

### 4.6 Deep-link config

Extend `PrismConfig` ([Prism.swift:51-87](../../../Sources/prism/Prism.swift#L51)) with
`var widget: String = ""` + a `case "widget":` parse arm (mirrors the existing `family` case).
Value = a `KitComponent.name`, case-insensitive; since each `KitComponent` carries its `.family`,
**`widget` implies the family**. Gallery seeds the `SidebarItem` selection to that widget.

- **Validate** `widget=` against real catalog names; on a miss, **fall back** to the family/first
  item (do **not** open the empty `.text` stub `kitComponent()` returns for an unknown name).
- **Keep `family=`** — it (not `widget=`) is how a deep-link targets a **foundation/app** page
  (Palette/Icons/facet/… are `KitFamily`/foundation values, not `KitComponent.name`s).
- `widget = "ThemedList"` + `theme = "dracula"` opens directly on one (widget × theme) page.
- `section=` / `state=` are **icebox** (anchors still allow manual reach).

### 4.7 AppKit compliance & the hosting constraint

The navigation/page chrome — split-view, `Section`/`DisclosureGroup`, `Picker`/`Menu`,
`ScrollViewReader`, `LazyVGrid`, the sidebar `List`, and the in-content search field — is **all
genuinely pure SwiftUI**, and the 3 AppKit floors stay inside the previewed widgets. **But** the
hosting constraint must be recorded so implementation doesn't drift into AppKit:

- On macOS, **window-chrome placements** — `.toolbar`, *default* `.searchable`, and
  NavigationSplitView's auto collapse button — install into a **window `NSToolbar`**, which
  prism's bare-`NSHostingView` bootstrap **does not have**, so they render **nothing**.
- Therefore the shell uses an **in-content top bar**, **`.searchable(placement:.sidebar)`**, and
  an **in-content collapse toggle** — all in the content view, all pure SwiftUI.
- **Explicit non-goals** (would breach the pure-SwiftUI-shell invariant → 要相談 if ever wanted):
  do **not** attach an AppKit `NSToolbar` to the window; do **not** add `NSHostingView.sceneBridgingOptions = [.toolbars]`
  merely to fake a titlebar toolbar; do **not** drop an AppKit `ThemedTextField` into the shell
  search (the search is ASCII widget-name/module/kind filtering — floor #1 IME field-editor is
  irrelevant here and must not be added).
- The only `Prism.swift` host changes are within the accepted bucket: `NSHostingController`,
  `contentMinSize`, opening-height clamp.

## 5. Files touched

| File | Change |
|---|---|
| [Sources/prism/Gallery.swift](../../../Sources/prism/Gallery.swift) | **Major** — replace header `VStack` + `FlowLayout` + tab rows with the split-view (in-content top bar + `.searchable(.sidebar)` sidebar of `SidebarItem`s + detail); add the `SidebarItem` registry (§4.1.1) + selection state; factor `WidgetPage` and the bespoke foundation/app page out of `ThemeCard`'s `widgetFamily` switch; Overview/segmented/anchors/"Show all"; in-content collapse toggle. |
| [Sources/prism/Prism.swift](../../../Sources/prism/Prism.swift) | `NSHostingController` host; add `PrismConfig.widget` + parse arm; **change `theme` default off `"all"`**; set display-safe `contentMinSize`; clamp opening height to `visibleFrame`. |
| `prism.toml` (shipped) | Update `theme = "all"` → the new single-theme default. |
| [Sources/prism/KitCatalog.swift](../../../Sources/prism/KitCatalog.swift) | Add structured `KitComponent` fields; split `referenceText` into paste-ready core + full-API appendix; add missing catalog entries (`ThemedGrid`, decide `MarkdownView`); **re-derive + compile** the recipe for each of the **23** entries against current signatures. |
| `Sources/prism/*Showcase.swift`, `Specimens.swift` | Refactor each of the **29** `Mock*` views to **expose their specimen cells** as an addressable list (for Overview subset + "Show all"). Widget draw unchanged; only prism's arrangement changes. Add `MockMarkdownView` if `MarkdownView` gets its own page. |

## 6. Verification

Not a green-test claim — **prove live in prism** (CLAUDE.md + [[judge-ui-via-real-app]]):
`swift build`, then launch `.build/debug/prism` (prism-bench recipe) and eyeball:

- **the in-content top bar + sidebar search field actually RENDER** (regression guard against
  the `.toolbar`/`.searchable` window-toolbar trap — do not treat "it compiled" as proof);
- sidebar search finds a widget by name **and** by MUI kind; foundation/app items are reachable;
- selecting a row shows exactly ONE page; foundation/app items show the bespoke page;
- Overview is compact; segmented anchors jump; **"Show all"** expands the full grid;
- theme Picker switches a single theme; **"All"** tiles the one widget across themes (live effects intact);
- lower cells reachable at small window heights, **including on a ≤900pt-usable display** (the
  display-safe `contentMinSize`);
- **copy ref** pastes the ~15-line agent-ready core (imports + compilable init + source pointer);
- `PRISM_CONFIG` with `widget="ThemedList"` + `theme="dracula"` opens straight onto that page;
  an unknown `widget=` falls back (no blank page).
- **Keyboard ↑/↓ selection is a LIVE/manual step** (window activated) with `@FocusState` routing
  so arrows target the `List` while the search field is a separate focus target — this is
  **separate** from the non-activating screenshot recipe (which never makes the window key).

Also `scripts/test.sh` for the logic layers (shell is UI — tests won't prove render).

## 7. Icebox (explicitly deferred, not built)

- **Live prop-editing inspector** (Storybook Controls addon) — the main bloat vector.
- **`section=` / `state=` deep-link keys** for scripted per-state captures.

## 8. Risks / watch-items

- **Sidebar vs. content width**: tune split-view min widths so the sidebar doesn't starve the
  `920*uiScale`-min content.
- **Lost tinted 36-chip color preview** (doubled as an at-a-glance palette swatch) — preserved
  inside the **Palette foundations** page (§4.2.1).
- **Focus contention**: `.searchable` can capture initial focus; `@FocusState` must route ↑/↓ to
  the `List` (§6).
- **`uiScale = 1.5`** inflates density/window size; the display-safe `contentMinSize` (§4.5.2)
  guards the worst case, but revisit whether the split-view wants a lower effective scale (leave
  `uiScale` alone to avoid touching widget metrics).
- **Catalog drift is a standing hazard**: once `SidebarItem` is the single source, adding a mock
  without a registry entry should be caught (a debug assert that every rendered mock has an item).
