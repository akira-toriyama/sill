# 17b Milestone 5 — RETIRE the AppKit `ThemedList` (final; the `v<x.y.0>` tag lands here)

**Goal:** Delete the AppKit `ThemedList` (2365 lines) + its 83-test suite, move the last
two popup files (`ThemedTooltip`, `PopupPanel`) up into `ThemeKitUI`, and revert the
popup machinery M3/M4 made `public` (for the module edge) back to `internal`. After M4
nothing hosts the AppKit widget — M5 is pure removal + relocation, **render-neutral by
design** (no drawing code changes; the SwiftUI `ThemedListView` shipped 1:1 in M2).

Spec §7 milestone 5: *"`ThemedList.swift` + `ThemedListTests.swift` 削除・AppKit
forwarder seam と ThemedScroller install site 2箇所を除去・不要なら String typealias
を落とす"* — the forwarder seams (`_resolveDropTarget` etc.), the two
`ThemedScroller()` install sites ([ThemedList.swift:454,457]), and the String drag
typealiases ([ThemedList.swift:39-42], used nowhere else — verified) are all INSIDE
the deleted file. Task-body additions: rescue `TrailingAccessory`/`ListTint`/`Badge`,
move `PopupPanel.swift` → ThemeKitUI + re-internalize, keep `ThemedScroller.swift`
(facet consumes it directly).

## Verified premises (2026-07-05 survey)

- Production `ThemedList(` instantiations: **zero** (only `ThemedListTests.swift`).
- `Badge`/`BadgeRole`/`ListTint`/`TrailingAccessory` consumers: ThemeKitUI (7 files)
  + prism (3 files) + ThemeKitUITests — **zero remaining in ThemeKit or ThemeKitTests**
  → their post-retire home is **ThemeKitUI** (the vocabulary lives with `ListItem<ID>`;
  ThemeKit keeping them would be vestigial coupling).
- Popup-primitive consumers: `ThemedTooltip` (ThemeKit — **moves too**, sanctioned by
  the task body "menu/tooltip 移設後"), combo/menu (ThemeKitUI), `WindowShell`
  (ThemeKit — shares ONLY `removeMonitorSafely`), `ThemedList` (dies). prism/KitCatalog
  mentions are doc strings. `Tests/ThemeKitTests` uses **no** popup symbol;
  `ThemedMenuTests` reaches `PopupCorner` via `@testable import ThemeKitUI`.
- Pre-M3 (`5cfb9fd`) the ENTIRE `PopupPanel.swift` surface was internal → everything
  M3/M4 publicised goes back internal; no Popup* type appears in any public signature
  of combo/menu/tooltip (grep-verified) so nothing must stay public.
- `PopupFade.transact` calls ThemeKit-internal `layerTxn` ([Shared.swift:20]);
  `ThemedTransition` is **Motion** (public; ThemeKitUI already depends on Motion).
- prism `ListShowcase`/`MenuShowcase` already render the SwiftUI widgets (M2/M4);
  `KitCatalog`'s "ThemedList" card still describes the AppKit NSView + the retired
  NSViewRepresentable bridge — stale, must be rewritten against the real
  `ThemedListView` API. (`Specimens.swift`'s apparent `Badge` hits were a local
  `hasBadge` variable — no import change needed; compile-verified.)

## Tasks

1. **M5a — rescue + delete.**
   - New `Sources/ThemeKitUI/ListAccessories.swift`: `Badge`, `BadgeRole`, `ListTint`,
     `TrailingAccessory` moved byte-identical from `ThemedList.swift` (public, as today).
   - Delete `Sources/ThemeKit/ThemedList.swift` + `Tests/ThemeKitTests/ThemedListTests.swift`.
   - `Sources/prism/ListShowcase.swift`: `import ListCore` (the `DropTarget` String
     typealias died with the widget; the generic infers `String` from its arguments).
   - Gate: `swift build` + `scripts/test.sh` (expect 809 − 83 = 726 tests, 0 fail).

2. **M5b — ThemedTooltip moves up.**
   - `git mv Sources/ThemeKit/ThemedTooltip.swift Sources/ThemeKitUI/` (public API
     unchanged; `import Motion` already satisfied by the target's deps).
   - `git mv Tests/ThemeKitTests/ThemedTooltipTests.swift Tests/ThemeKitUITests/` +
     swap `@testable import ThemeKit` → `@testable import ThemeKitUI` (DEBUG
     `tooltipProbe` + internal `Side` travel with the file).
   - Gate: build + tests (same 726).

3. **M5c — PopupPanel moves up + re-internalize.**
   - `git mv Sources/ThemeKit/PopupPanel.swift Sources/ThemeKitUI/`; strip `public`
     from EVERY symbol (`PopupPanel`, `themedPopupPanel`, `PopupSide`, `PopupCorner`,
     `PopupPlacement`, `PopupPlacementResult`, `placePopup`, `clampPopupOrigin`,
     `popupPanelSize`, `popupOriginFor`, `PopupFade`, `PopupGlue`,
     `removeMonitorSafely`) — back to the pre-M3 internal shape.
   - Add an internal `layerTxn` to ThemeKitUI (lives in the moved `PopupPanel.swift`,
     same doc + body as ThemeKit's) for `PopupFade.transact`; swap the byte-equivalent
     inline snap blocks (`ThemedComboBox.swift:276-280`, `ThemedMenu.swift:479-483`)
     to it — the menu's Grow transaction (910-921) stays custom (it sets duration +
     easing + a CABasicAnimation inside one transaction; not the helper's shape).
   - `WindowShell.swift` keeps compiling: add an internal `removeMonitorSafely` copy
     to ThemeKit `Shared.swift` (the one primitive the shell shares, per its header).
   - Gate: build + tests + `grep -c public Sources/ThemeKitUI/PopupPanel.swift` → 0.

4. **M5d — prism truth pass + stale-marker sweep.**
   - `KitCatalog`: rewrite the "ThemedList" card as **`ThemedListView` (ThemeKitUI)**
     against the REAL public API (read `ThemedListView.swift`/`ListStyle.swift` first);
     fix `ThemedMenu` card's "`ThemedList.Density`" → `Density`; `Gallery.swift`
     `kitComponent("ThemedList")` follows the rename.
   - Comment truth: `ThemedScroller.swift` (install-site sentence → facet-direct),
     `ThemedComboBox.swift:211,216` (metrics notes → `ListMetrics`), `ListItem.swift`
     header ("coexists until M5" / "Reuses ThemeKit's Badge"), `ListStyle.swift:8`,
     `ThemedListView.swift:9`, `ListItemProjectionTests.swift` header. prism's
     `ThemeKitUI.ListItem` qualifiers stay (still correct, now optional).

5. **Gates + ship.**
   - `swift build` (CLT) + `scripts/test.sh` full green.
   - prism static sweep (render-neutral proof): terminal / github-light / dracula /
     synthwave — list + menu + combo + tooltip cards vs main. Launch OUR build's PID
     (the parallel t-ftqa session may hold its own prism window — match winid by PID,
     never by name), no osascript activation.
   - `docs/ROADMAP.md` #17b → 完了 record; PR footer
     `SetStatus-task: https://github.com/akira-toriyama/projects/blob/main/.furrow/bodies/t-sb4c.md done`.
   - **⏸ IRREVERSIBLE GATE (per spec §7 + [[chomp-push-gate]]): confirm with the user
     ONCE before the squash-merge** (AppKit deletion crosses the live-verification
     gate). Then merge, tag (propose **v2.1.0** — house "library change ⇒ minor";
     in-repo consumers only, apps consume none of ThemeKit/ThemeKitUI), flip the
     t-sb4c furrow body to done.

## Risks

- **Hidden compile-time consumer of a moved symbol** → every step gated by the full
  local suite; the compiler enumerates stragglers.
- **prism window collision with the parallel t-ftqa session** → PID-scoped winid,
  no activation (memory: prism-bench / experiment-approval-vm).
- **`@MainActor` drift on moved decls** — files move verbatim; `layerTxn` copy keeps
  its `@MainActor` annotation; no isolation changes.
