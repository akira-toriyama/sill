# #17b M4 — ThemedMenu on the SwiftUI ThemedListView (menu host + submenu cascade)

**Date:** 2026-07-03  **Depends on:** M1 (ListCore) · M2 (ThemedListView) · M3 (ListController /
HostingListView / ThemedComboBox move) — all shipped. **Spec:** `docs/superpowers/specs/2026-06-23-17b-themedlist-swiftui-design.md` §6 milestone 4.
**Task:** projects `t-sb4c`.

## Goal

Retire the AppKit `ThemedList` from `ThemedMenu`, the way M3 did for `ThemedComboBox`:
move `ThemedMenu` **ThemeKit → ThemeKitUI** and host its vertical rows in a
`HostingListView<String>` driven by a `ListController<String>` over the SwiftUI-native
`ThemedListView` — instead of `container.addSubview(ThemedList)`. The horizontal
(`.toolbar`/`.labeledToolbar`) presentation keeps composing the real AppKit
`ThemedToolBar` unchanged. After M4 the ONLY thing still hosting the AppKit `ThemedList`
is nothing — M5 deletes `ThemedList.swift`.

The move follows the M3 fork resolution (Option A): the SwiftUI widget front
(`ThemeKitUI`) is the load-bearing wrap edge over the AppKit floors (`ThemeKit`), so a
transient popup widget that hosts the SwiftUI list belongs in `ThemeKitUI`, importing
`ThemeKit` for its floors (`PopupPanel`/`placePopup`/`PopupFade`/`PopupGlue`/
`removeMonitorSafely` + `ThemedToolBar` + `phosphorImage` + shared `TrailingAccessory`/
`ListTint`). The reverse edge would cycle.

## What already covers the menu (verified reading M2/M3)

`ThemedListRow` (M2) already renders EVERYTHING the menu draws: `.solidAccent` highlight
(`onAccent` → opaque `primary` fill + `onPrimary` ink), section headers, separators,
leading template image (checkmark/icon), trailing `.chevron` + `.shortcut` lozenge,
`.error` destructive tint bar, disabled `tertiary`, `axChecked`. `ListController` (M3)
already vends `moveHighlight`/`activateHighlight`/`clearHighlight`/`highlightedID`/
`clearHighlight`, `row(at:)`, `setHover`, `rowRects`. `HostingListView` (M3) already does
the non-key `mouseUp` sync commit + tracking-area hover. **prism's `MockMenu` /
`MockWandLauncher` inline mocks already use `ThemedListView`**, and the live triggers use
`ThemedMenuTriggerView` (ThemeKitUI). So the render/interaction layer is done; M4 is
wiring + the two measurement gaps + AX.

## Gaps M4 fills

1. **Measurement on `ListController`** (menu-only; combo used fixed row-height × count):
   `contentHeight()`, `fittingWidth(maxWidth:palette:)`, `rowRectOnScreen(_:)`.
2. **Per-row AX vending** in `ThemedListRow`, gated by `style.vendsRowAXElements`
   (combo left it false; the menu sets it true). Real SwiftUI AX for VoiceOver + a
   data-derived probe for CI.

---

## Task 1 — `ListController` measurement (TDD, `Tests/ThemeKitUITests/ListControllerTests.swift`)

Add to `ListController<ID>`:

- `weak var hostView: NSView?` — set to `self` by `HostingListView.init` (both refs weak;
  no cycle). Used only for the viewport→screen conversion.
- `private func rowHeight(_ item:) -> CGFloat` — the M2/AppKit rule, from
  `ListMetrics.forDensity(style.density)`: separator→`separatorBand`,
  header→(`subtitle == nil ? header1 : header2`), row→(`secondary == nil ? singleRow :
  twoLineRow`).
- `func contentHeight() -> CGFloat` — sum of `rowHeight` over `items` (empty → one
  `singleRow`, matching AppKit's synthetic empty row). Pure; **CI-tested here** (deviates
  from spec §5's "pure ListCore" only in file location — the sibling `fittingWidth` needs
  `NSFont`, so both live on the @MainActor controller; `ListCoreTests` stays font-free).
- `func fittingWidth(maxWidth:palette:) -> CGFloat` — port of
  `ThemedList.fittingWidth` (:799-833): per non-separator row, `textX` (leading slot +
  indent, header disclosure gutter) + measured primary width (1-line headers measured
  with `headerKern` — but menu headers are the `.uppercased()` 1-line kind; reproduce the
  kern) + `max` with secondary/subtitle + trailing cluster (`.chevron`→`chevronPt`,
  `.shortcut`→`NSString.size(font: .shortcut) + shortcutHPad·2`, badges) + `budgetMargin`
  + `trailingInset`; `min(maxWidth, ceil(max))`. Fonts from `palette.uiFont(...)`.
- `func rowRectOnScreen(_ id:) -> CGRect?` — **synchronous** (submenu anchoring + tests
  call it right after `open()`, before SwiftUI reports `rowRects`): use `rowRects[id]` when
  present (live, scroll-aware) else a `pureRowRect(id)` computed from `rowHeight` sums
  (viewport space, top-left, scroll 0). Then convert through `hostView`: if
  `!host.isFlipped` flip y (`bounds.height - vp.maxY`, mirroring
  `HostingListView.viewportPoint`), `host.convert(_, to: nil)`, `window.convertToScreen`.

Wire `HostingListView.init`: `controller.hostView = self`.

Tests: `contentHeight` for mixed rows/headers/separators/compact-vs-comfortable;
`fittingWidth` monotonic with label length + accounts for shortcut/chevron + clamps to max;
`rowRectOnScreen` returns nil without a window, and (with a windowed host) row 1's rect
sits below row 0's by `rowHeight(0)` in the pure path.

## Task 2 — `ThemedListRow` per-row AX (`Sources/ThemeKitUI/ThemedListRow.swift`)

When `style.vendsRowAXElements` and the row is a selectable `.row`:
`.accessibilityElement(children: .combine)`, `.accessibilityLabel(item.axChecked ?
"\(item.primary), checked" : item.primary)`, `.accessibilityAddTraits(.isButton)`.
Headers/separators/disabled rows: no element (leave default). Default (`false`) path
unchanged (combo/standalone). Prove VoiceOver LIVE in prism; CI asserts the label list via
the menu probe (Task 3).

## Task 3 — Migrate `ThemedMenu` ThemeKit → ThemeKitUI (`git mv`, then rewire)

`git mv Sources/ThemeKit/ThemedMenu.swift Sources/ThemeKitUI/ThemedMenu.swift`. Imports:
drop nothing structural — `import AppKit, QuartzCore, Palette, PaletteKit, ListCore` +
add `import ThemeKit` (PopupPanel/placePopup/PopupFade/PopupGlue/removeMonitorSafely/
PopupCorner/PopupPlacementResult/ThemedToolBar/phosphorImage/TrailingAccessory/ListTint).
`ListController`/`HostingListView`/`HostedThemedList`/`ThemedListStyle`/`Density`/`ListItem`
are now same-module.

Replace `private let list: ThemedList` with the M3 trio (mirror `ThemedComboBox`):
`private let controller = ListController<String>()`, `private var hosting:
HostingListView<String>!`, driven via a value-typed `HostedThemedList`. Then translate,
call-for-call:

| AppKit `list.…` | new |
|---|---|
| `list.palette = …` / `list.surfaceColor = …` | `controller.style.surfaceColor = menuSurface` + `rehostList()` (rebuild `hosting.rootView` with the new palette, like combo's `rehostList`) |
| `list.density`, `.selectionMode`, `.hoverStyle`, `.highlightFollowsHover`, `.wrapsHighlight`, `.vendsRowAXElements`, `.managesFirstResponder` | `controller.style.…` (a `menuListStyle()` builder: `.none`, `.solidAccent`, hover-drives-highlight, wrap, `vendsRowAXElements = true`, `hosted = true`, density) |
| `list.onActivate` / `.onHover` | `controller.onActivate` / `.onHover` |
| `list.items = items.map(...)` | `controller.items = items.map(...)` (same `ThemeKitUI.ListItem` mapping) |
| `list.moveHighlight`, `.highlightedID`, `.activateHighlight`, `.clearHighlight` | `controller.…` (all exist) |
| `list.previewHighlight = id` | set `controller.highlight = id` (vertical preview seam) |
| `list.rowRectOnScreen(for:)` | `controller.rowRectOnScreen(_:)` (Task 1) |
| `list.fittingWidth(maxWidth:)` / `list.contentHeight` | `controller.fittingWidth(maxWidth:palette:)` / `controller.contentHeight()` |
| `list.removeFromSuperview()` / `container.addSubview(list)` | `hosting.removeFromSuperview()` / `container.addSubview(hosting)` (build `hosting` in `ensurePanel`, like combo) |
| `list.frame = …` (reframe) | `hosting.frame = …` |
| `list.listProbe.rowCount` (probe) | `controller.items.count` |
| `list._axChildren()` (probe) | derive `axMenuItemLabels` from `items` (kind `.item` & enabled → `title` + `", checked"` when `isChecked`) |

Inline `layerTxn` (it's ThemeKit-internal) as `CATransaction.begin();
setDisableActions(true); …; commit()` — matching `ThemedComboBox.applyListTheme`.
`density`'s type becomes `Density` (ThemeKitUI). Test seams: `_list` removed; add
`_controller` (drive nav/probe). `_toolbar`/`_child`/`_activate`/`_openSubmenu`/
`_closeChild`/`_handleKey` unchanged. Keep the whole submenu cascade / key monitor /
mouse monitor / glue / Grow / horizontal-toolbar machinery byte-identical — only the row
HOST changes.

## Task 4 — Migrate `ThemedMenuTests` ThemeKit → ThemeKitUI

`git mv Tests/ThemeKitTests/ThemedMenuTests.swift Tests/ThemeKitUITests/ThemedMenuTests.swift`,
`@testable import ThemeKit` → `ThemeKitUI`. Rewrites:
- `m._list.listProbe.rowCount` → `m._controller.items.count`; `m._list.items[i]` →
  `m._controller.items[i]`; `m._list.moveHighlight`/`.activateHighlight`/`.activateRow` →
  `m._controller.moveHighlight`/`.activateHighlight` (+ a `controller`-level activate-by-id).
- The two `_axChildren()` tests (`testCheckedRowAXLabelCarriesMarker`,
  `testAXVendsMenuItemsAndPressActivates`): assert `m.menuProbe.axMenuItemLabels`
  (`["Apple"]`, `["Show Sidebar, checked", "Show Toolbar"]`) + that `_activate(id)` runs the
  action (the "AXPress activates" intent). Drop the AppKit-element role/press mechanics
  (SwiftUI AX isn't headless-assertable; proven live in prism).
- Everything else (open/dismiss/monitors, keyDown routing, placement corner, submenu
  cascade N-level, horizontal bar) is host-agnostic → unchanged but for the accessor names.

## Task 5 — prism + build/test/gate

- `KitCatalog.swift:430` `module: "ThemeKit"` → `"ThemeKitUI"`; refresh the `consumes`/
  `MockMenu`/`MockWandLauncher` stale "hosts a ThemedList" comments to "SwiftUI
  ThemedListView". No functional prism change (mocks already on `ThemedListView`).
- `swift build` (CLT quick bar) + `scripts/test.sh` (full XCTest, Xcode 26) green.
- **prism live maintainer gate** (menu is a child window — not in a static shot): open the
  live trigger, verify across ≥3 themes: `.solidAccent` highlight look, ⌘-shortcut lozenge,
  checkmark row, destructive row, disabled row; hover/→ opens the submenu cascade anchored
  beside its parent row; ←/Esc close one level; ↑↓/Enter keyboard; horizontal `.toolbar`/
  `.labeledToolbar` bar + folder-opens-below. VoiceOver reads the rows as menu items.

## Ship

Milestone (not the final tag — M2..M4 stay untagged; `v<x.y.0>` lands at M5 retire). Per
`[[ci-green-merge-ok]]` the green PR self-merges; per `[[chomp-push-gate]]` re-confirm the
live gate before merging (M4 crosses no *irreversible* AppKit deletion — that's M5 — but it
does cross a live-verification gate, so confirm "sill で確認済み？" once). PR footer:
`SetStatus-task: …/t-sb4c.md in-progress`.
