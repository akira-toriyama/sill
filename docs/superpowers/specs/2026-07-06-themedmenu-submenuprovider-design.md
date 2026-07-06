# ThemedMenu deferred `submenuProvider` — design (sill t-esdf)

**Task:** [t-esdf] sill: ThemedMenu 汎用 async/deferred submenuProvider hook — wand real launcher 用
**Date:** 2026-07-06 · **Target version:** v3.1.0 → **v3.2.0** (library change = minor + `v`-tag)
**Consumer:** Phase B wand real-apply (t-z91b #20) — not urgent; sill part built ahead per *build-best-then-migrate*.

## Goal

Let a `ThemedMenu` folder row supply its children **lazily / asynchronously** instead of
declaring them all up front. wand's real launcher walks a `PanelTree` and shells out to git to
build a submenu's children on demand; today `ThemedMenu` assumes a fully **static** recursive tree.
Add one generic hook that absorbs that async + loading + cancellation burden into the widget kit,
so every app doesn't hand-roll it.

## Constraint (sill AppKit policy — the hard gate)

This must stay inside the existing **floor #2** (the non-activating panel/popup shell). It adds
**no new AppKit floor**: menu *data* is supplied on the SwiftUI / value side; AppKit remains only
the menu-*draw* core. Floor count stays 3. The design below is a **pure value-side addition** — it
never changes how a panel is shown, only *when* a child's rows are populated.

## Current model (as-is)

`ThemedMenu` ([Sources/ThemeKitUI/ThemedMenu.swift](../../../Sources/ThemeKitUI/ThemedMenu.swift))
is a `@MainActor public final class : NSObject` **controller** — not an `NSView`, and it does
**not** use `NSMenu`. It owns a borderless, non-activating `PopupPanel` (floor #2) hosting a SwiftUI
`ThemedListView` (via `ListController` / hosted list). Submenus are 100% static and eager:

- `MenuItem.submenu: [MenuItem]` (line 84) is the recursive children array.
- `MenuItem.hasSubmenu` (line 75) is the "folder / chevron" flag; init derives it
  `hasSubmenu || !submenu.isEmpty` (line 93), but it can also be passed `true` on a row with an
  **empty** `submenu` — that explicit path is the natural "declares a deferred submenu" affordance
  already in the type.
- The trailing chevron / toolbar caret keys off `mi.hasSubmenu` (lines 326, 346) — the **flag**, not
  array-emptiness, already drives the folder affordance.
- A submenu is its own **full child `ThemedMenu`**, built recursively (N-level) in
  `openSubmenu(rowID:highlightFirst:)` (709). Only the ROOT installs key/mouse monitors; children
  present with `installDismiss:false`. One path open at a time; the root routes keys to the active leaf.
- **The children-source is a single line:** [ThemedMenu.swift:724](../../../Sources/ThemeKitUI/ThemedMenu.swift) `c.items = mi.submenu`.
- Reassigning a live child's `.items` is already a supported self-relayout: the `items` didSet (125)
  runs `rebuildRows()` + `reframe()` + `validateOpenChild()`, so late-arriving async rows resize /
  reposition the open panel **for free**.
- The only behavior closure that crosses the value boundary today is per-item
  `MenuItem.action: (() -> Void)?` (79) — the house precedent for a per-row closure.

## Chosen approach — per-item async closure on `MenuItem` (Approach A)

Rejected alternatives: **B** (a single controller-level provider keyed by item) requires manual
propagation of the provider down each cascade level (footgun) + a new bridge param; **C** (a
synchronous lazy closure) pushes async/loading/caching back onto every app, defeating the point.

**A auto-propagates through the cascade**: a resolved child is just `MenuItem`s that may each carry
their own `submenuProvider`, so there is nothing to thread down the N-level chain, and it mirrors the
existing `MenuItem.action` per-row precedent.

### Public API

On `ThemedMenu.MenuItem`, add one stored field beside `action`:

```swift
public var submenuProvider: (@MainActor () async -> [MenuItem])?
```

- `@MainActor`-isolated, **non-throwing**, **not** `@Sendable`: `MenuItem` holds a non-Sendable
  `NSImage?` and `action` closure and `ThemedMenu` is `@MainActor`, so the provider must stay
  main-actor-isolated and `MenuItem` never crosses a Sendable boundary. Do **not** add `Sendable` /
  `Equatable` to `MenuItem`.
- Added to **both** inits (the designated init at line 90 and the `submenu:` convenience at 99) as
  `submenuProvider: (@MainActor () async -> [MenuItem])? = nil` (default `nil` ⇒ static callers
  untouched).
- `hasSubmenu` derivation (93) becomes `hasSubmenu || !submenu.isEmpty || submenuProvider != nil`,
  so a provider-only row renders a chevron with **no change** to the chevron sites (326/346).

Caller shape:

```swift
MenuItem(id: "branch", title: "Switch Branch", hasSubmenu: true,
         submenuProvider: { await panelTree.branchChildren() })
```

### Behavior at the seam (line 724)

Introduce one predicate and route the five folder-ness gates through it (they currently branch on
array-emptiness and must accept a provider-only row):

```swift
private func hasChildren(_ mi: MenuItem) -> Bool { !mi.submenu.isEmpty || mi.submenuProvider != nil }
```

Gates to unify: `activate()` (667), `handleHover()` (691), `openSubmenu` guard (712),
`validateOpenChild()` (757), `handleKeyDown .openSubmenu` (809). The chevron (326) stays as-is.

Resolve logic in `openSubmenu` (replaces the single line 724):

1. **static array non-empty → `c.items = mi.submenu`** (byte-identical legacy path). *Static wins if
   both static children and a provider are present*, keeping the existing path untouched.
2. **else provider present →** present the child immediately with a single **disabled `"Loading…"`
   row**; capture a per-open **generation token** on the child (mirror the existing `PopupFade`
   `fadeGen` pattern); then

   ```swift
   let gen = c.openGen
   c.itemsTask = Task { @MainActor in
       let kids = await mi.submenuProvider!()
       guard c.isOpen, c.openGen == gen, !Task.isCancelled else { return }
       c.items = kids.isEmpty ? [.disabledRow("No items")] : kids
   }
   ```

   The `items` didSet (125) gives reframe / reposition for free.
3. **Cancellation:** hold the in-flight `Task` on the child; `.cancel()` it in `closeChild()` (732)
   / teardown, so a hover-away / Esc / re-target stops the walk (wand does real git I/O worth
   cancelling), not just discards the result.

### Policies (confirmed)

| Decision | Choice |
|---|---|
| Loading UX | present-then-fill with a disabled `"Loading…"` row |
| Cache | **cache-free** public contract — provider re-invoked on every open (wand gets fresh branches). Internal single-open memo only if re-hover thrash appears; never in the API. |
| Empty `[]` result | disabled `"No items"` row |
| Error | **non-throwing** signature — host maps its own errors to a row |
| static + provider on one row | **static wins if present** (legacy path byte-identical) |

## prism showcase (extend existing — no new scaffolding)

`ThemedMenuView` bridge + `MockMenu(p:)` grid + `ThemeCard` wiring already exist; this extends them.

- **Live:** convert `WandShowcase.swift`'s "Switch Branch" folder from a static `submenu` array to a
  real `submenuProvider` (faux async, e.g. `{ try? await Task.sleep(…); return fauxBranches }`) so
  the live launcher demonstrates **loading → filled**. Optionally add a provider-backed folder to
  `MenuShowcase.swift` so the generic hook is showcased independent of wand.
- **Deterministic still:** the transient `Loading…` state and the resolved state each need a
  reproducible screenshot. Add a **preview override** that forces each state synchronously (mirror
  the existing `previewOpen` / `previewHighlight` / `ListPreview` seam family) — the child window
  can't be screencaptured live anyway (prism-bench note).
- **Per-theme inline grid** cells already draw the submenu result as static rows (forced-lit
  `ListPreview`) and never run the controller, so the grid stays deterministic.
- Document the hook in the `KitCatalog` `ThemedMenu` entry `keyAPI` alongside `MenuItem.submenu`.

## Tests ([Tests/ThemeKitUITests/ThemedMenuTests.swift](../../../Tests/ThemeKitUITests/ThemedMenuTests.swift))

Existing tooling suffices: the deterministic FIFO main-queue `pump()` helper + DEBUG
`menuProbe` (childOpen / childRowID / childRowCount / childHighlightedID) and `_openSubmenu` /
`_child` / `_activate` / `_handleKey` seams. New cases:

- **provider-only = folder:** a `hasSubmenu:true` row with empty `submenu` + a provider reports a
  chevron and is treated as a folder by all five gates.
- **present-then-fill:** open a provider row → child shows the `Loading…` row synchronously →
  `pump()` the async resolve → `childRowCount` flips to the resolved rows.
- **stale-resolve guard:** open a provider child, close / re-target it **before** the awaited resolve,
  `pump()` → the torn-down child is **not** repopulated (generation-token path).
- **cancellation:** the in-flight `Task` is cancelled on `closeChild` / dismiss.
- **empty result:** provider resolving to `[]` shows the `"No items"` row.
- **static-path regression:** the existing ~15 cascade cases stay green unchanged (proves the static
  path is byte-identical).

Provider resolves deterministically via an immediate-return async closure awaited through `pump()` —
no timer.

**Gate:** `scripts/test.sh` (local Xcode — `swift test` is a SwiftUI-render blind spot) **and** prove
the live loading → filled state in prism, per CLAUDE.md.

## Non-blocking note — wand signature

wand's real launcher call site lives in the wand repo (not in the working set). The async / PanelTree
shape is inferred from the task + `WandShowcase`'s "shell-fed submenu" comments. We design a general
zero-arg `(@MainActor () async -> [MenuItem])`; if wand's walk needs a stable identity/context
argument, that is a trivial later addition. Confirm the real signature against wand's source when
Phase B wand lands.

## Out of scope (YAGNI)

- `async throws` provider / kit-rendered error rows (host owns errors).
- Cross-open caching in the public API.
- Any `NSMenu` / `NSMenuDelegate`-style AppKit callback.
- Changes to the horizontal toolbar presentation beyond the shared `hasSubmenu` chevron.
