# ThemedMenu deferred `submenuProvider` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a `ThemedMenu` folder row supply its children lazily/asynchronously via a per-item `submenuProvider` closure, instead of only a static `submenu` array.

**Architecture:** Pure value-side addition to `ThemedMenu.MenuItem` (Sources/ThemeKitUI). A submenu is already its own floor-#2 child `ThemedMenu`; the only change is *when* the child's rows are populated — the single children-source line in `openSubmenu` splits into "static array wins, else present a `Loading…` row and fill from an awaited provider". The existing `items` didSet gives reframe/reposition for free; a fresh child instance per open + an `isOpen` guard makes stale resolves safe. No AppKit surface changes (floor count stays 3).

**Tech Stack:** Swift 6 / AppKit + SwiftUI, `@MainActor`, unstructured `Task`, XCTest (via `scripts/test.sh` — local Xcode), prism visual bench.

## Global Constraints

- **AppKit policy (hard gate):** stay inside floor #2 (the non-activating panel shell). NO new AppKit floor, NO `NSMenu`/`NSMenuDelegate`. Menu data is value/SwiftUI-side; AppKit draws only. (Verify in self-review.)
- **Concurrency:** the provider is `(@MainActor () async -> [MenuItem])?` — `@MainActor`-isolated, **non-throwing**, **not** `@Sendable`. Do NOT add `Sendable`/`Equatable` to `MenuItem`.
- **Static-wins:** if a row has BOTH a non-empty `submenu` and a `submenuProvider`, the static array is used and the provider is never consulted (legacy path byte-identical).
- **Cache-free:** the provider is re-invoked on every open (no cross-open cache in the API).
- **Test gate:** `swift build` (CLT compile bar) + `scripts/test.sh` (full XCTest via local Xcode — `swift test` on CLT does not link XCTest) + prove loading→filled LIVE in prism. `swift test` is a SwiftUI-render blind spot.
- **Version:** library change ⇒ minor bump + `v`-tag `v3.1.0 → v3.2.0` (tag created after merge; there is no in-repo version file).
- **Commits:** gitmoji + Conventional Commits, e.g. `:sparkles: feat(ThemeKitUI): …`. English subject. End body with the `Co-Authored-By` trailer.

**Key files (verified line anchors, origin/main 4cd457b):**
- `Sources/ThemeKitUI/ThemedMenu.swift` — `MenuItem` struct 70-116 (field 84, inits 89/97/104, `hasSubmenu` derivation 93); state block ~233; `openSubmenu` 709-729 (seam 724); gates 667/691/712/757/809; `teardownAsChild` 743; `invalidate` 523.
- `Tests/ThemeKitUITests/ThemedMenuTests.swift` — `pump()` 71, `anchoredMenu` 30, `cascadeItems` 333, submenu tests 343-437.
- `Sources/prism/WandShowcase.swift` — `wandMenuItems` 53, Switch Branch folder 65-69.
- `Sources/prism/MenuShowcase.swift` — `menuTriggerItems` 56.
- `Sources/prism/KitCatalog.swift` — ThemedMenu entry 686-731 (keyAPI 690, cellInit 728).

---

### Task 1: `MenuItem.submenuProvider` field + inits + chevron derivation

**Files:**
- Modify: `Sources/ThemeKitUI/ThemedMenu.swift:70-116` (MenuItem struct)
- Test: `Tests/ThemeKitUITests/ThemedMenuTests.swift`

**Interfaces:**
- Produces: `ThemedMenu.MenuItem.submenuProvider: (@MainActor () async -> [MenuItem])?`; both public inits gain `submenuProvider: (@MainActor () async -> [MenuItem])? = nil`; `hasSubmenu` is auto-true when a provider is present.

- [ ] **Step 1: Write the failing test**

Add to `ThemedMenuTests.swift` in the "MenuItem → ListItem mapping" section (after `testMappingDetails`, ~line 108):

```swift
    func testProviderRowAutoSetsChevron() {
        // A provider-only row (no static submenu, hasSubmenu not passed) is still a folder.
        let mi = ThemedMenu.MenuItem(id: "branch", title: "Switch Branch",
                                     submenuProvider: { [.init("main")] })
        XCTAssertTrue(mi.hasSubmenu, "a submenuProvider auto-sets hasSubmenu")

        let m = ThemedMenu(palette: theme())
        m.items = [mi]
        XCTAssertEqual(m._controller.items[0].trailing, .chevron,
                       "a provider-only row maps to a trailing chevron")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/test.sh 2>&1 | pare`
Expected: FAIL to COMPILE — `extra argument 'submenuProvider' in call` (the init has no such parameter yet).

- [ ] **Step 3: Write minimal implementation**

In `ThemedMenu.swift`, add the field after `submenu` (line 84):

```swift
        public var submenu: [MenuItem]
        /// Deferred children. When set (and `submenu` is empty), opening this row
        /// presents the child with a disabled `Loading…` row, then fills it with the
        /// closure's result. Re-invoked on every open (cache-free). `@MainActor`,
        /// non-throwing. Static `submenu` wins if both are present. Consumer: wand's
        /// real launcher (an async PanelTree walk).
        public var submenuProvider: (@MainActor () async -> [MenuItem])?
```

Update the derivation line (93):

```swift
            self.hasSubmenu = hasSubmenu || !submenu.isEmpty || submenuProvider != nil
```

Add the param to the designated init (89-91) and set the stored field (95). The init becomes:

```swift
        public init(id: String, title: String, icon: NSImage? = nil, shortcut: String? = nil,
                    hasSubmenu: Bool = false, isChecked: Bool = false, isEnabled: Bool = true,
                    isDestructive: Bool = false, submenu: [MenuItem] = [],
                    submenuProvider: (@MainActor () async -> [MenuItem])? = nil,
                    action: (() -> Void)? = nil) {
            self.id = id; self.title = title; self.icon = icon; self.shortcut = shortcut
            self.hasSubmenu = hasSubmenu || !submenu.isEmpty || submenuProvider != nil
            self.isChecked = isChecked; self.isEnabled = isEnabled
            self.isDestructive = isDestructive; self.submenu = submenu
            self.submenuProvider = submenuProvider; self.action = action; self.kind = .item
        }
```

Add the param to the convenience init (97-102):

```swift
        public init(_ title: String, icon: NSImage? = nil, shortcut: String? = nil,
                    isEnabled: Bool = true, isDestructive: Bool = false,
                    submenu: [MenuItem] = [],
                    submenuProvider: (@MainActor () async -> [MenuItem])? = nil,
                    action: (() -> Void)? = nil) {
            self.init(id: title, title: title, icon: icon, shortcut: shortcut,
                      isEnabled: isEnabled, isDestructive: isDestructive, submenu: submenu,
                      submenuProvider: submenuProvider, action: action)
        }
```

Set the field in the private separator/header init (104-108) so all stored props are initialized:

```swift
        private init(id: String, title: String, kind: Kind) {
            self.id = id; self.title = title; self.kind = kind
            self.icon = nil; self.shortcut = nil; self.hasSubmenu = false
            self.isChecked = false; self.isEnabled = false; self.isDestructive = false
            self.submenu = []; self.submenuProvider = nil; self.action = nil
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `scripts/test.sh 2>&1 | pare`
Expected: PASS — `testProviderRowAutoSetsChevron` green; all existing tests still green (the new param defaults to nil, so static callers are unaffected).

- [ ] **Step 5: Commit**

```bash
git add Sources/ThemeKitUI/ThemedMenu.swift Tests/ThemeKitUITests/ThemedMenuTests.swift
git commit -m ":sparkles: feat(ThemeKitUI): add MenuItem.submenuProvider field (t-esdf)"
```

---

### Task 2: `hasChildren` predicate — route the five folder-ness gates

**Files:**
- Modify: `Sources/ThemeKitUI/ThemedMenu.swift` (add `hasChildren`; gates 667, 691, 712, 757, 809)
- Test: `Tests/ThemeKitUITests/ThemedMenuTests.swift`

**Interfaces:**
- Consumes: `MenuItem.submenuProvider` (Task 1).
- Produces: `private func hasChildren(_ mi: MenuItem) -> Bool` — the single "does this row open a cascade?" predicate; all five gates route through it, so a provider-only row is treated as a folder by activate / hover / →-key / open / re-anchor.

> After this task the seam still assigns the (empty) static `submenu`, so a provider-only row opens an **empty** child. Task 3 fills it. This task proves the *gates* accept a provider-only row.

- [ ] **Step 1: Write the failing test**

Add to `ThemedMenuTests.swift` in the "Submenu cascade" section (after `testOpenSubmenuShowsChildRows`, ~line 361):

```swift
    func testProviderRowActivatesAsFolder() {
        // Gate coverage: activating a provider-only row opens its child (does NOT
        // run a leaf action), and → on it is swallowed to open the child.
        var leafActionFired = false
        let items: [ThemedMenu.MenuItem] = [
            .init(id: "branch", title: "Switch Branch",
                  submenuProvider: { [.init("main")] }, action: { leafActionFired = true }),
        ]
        let (m, anchor) = anchoredMenu(items)
        m.present(from: anchor)
        m._activate("branch")
        XCTAssertTrue(m.menuProbe.childOpen, "activating a provider row opens the child (folder gate)")
        XCTAssertFalse(leafActionFired, "a provider/folder row's own action is ignored")
        m.dismiss(animated: false)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/test.sh 2>&1 | pare`
Expected: FAIL — `childOpen` is false. `activate` (667) still gates on `!mi.submenu.isEmpty`, which is false for a provider-only row, so it falls through to the leaf branch (dismiss + run action) instead of opening the child.

- [ ] **Step 3: Write minimal implementation**

In `ThemedMenu.swift`, add the predicate just above `activate` (before line 665, in the `// MARK: - Activation` region):

```swift
    /// A row opens a cascade when it has static children OR a deferred provider.
    /// The single source of truth for "is this a folder row?".
    private func hasChildren(_ mi: MenuItem) -> Bool {
        !mi.submenu.isEmpty || mi.submenuProvider != nil
    }
```

Replace each of the five gates:

`activate` (667):
```swift
        if hasChildren(mi) {
```

`handleHover` (691):
```swift
        let isSubmenuRow = items.first(where: { $0.id == id }).map(hasChildren) ?? false
```

`openSubmenu` guard (711-713) — change only the `!mi.submenu.isEmpty` clause:
```swift
        guard isOpen, let host = hostWindow,
              let mi = items.first(where: { $0.id == id }), mi.isEnabled, hasChildren(mi),
              let rowRect = rowRectOnScreen(for: id) else { return }
```

`validateOpenChild` (756-759):
```swift
        guard let vmi = items.first(where: { $0.id == id }), hasChildren(vmi) else {
            closeChild(); return                             // the submenu row is gone / lost its children
        }
```

`handleKeyDown` .openSubmenu (808-809):
```swift
            if let id = leaf.highlightedContentID,
               let kmi = leaf.items.first(where: { $0.id == id }), leaf.hasChildren(kmi) {
```

- [ ] **Step 4: Run test to verify it passes**

Run: `scripts/test.sh 2>&1 | pare`
Expected: PASS — `testProviderRowActivatesAsFolder` green. All existing cascade tests (`testSubmenuChildrenAutoSetChevron`, `testOpenSubmenuShowsChildRows`, `testRightArrowOpensAndLeftClosesSubmenu`, the deep-cascade set 451-521, etc.) stay green — the static `!submenu.isEmpty` cases evaluate identically through `hasChildren`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ThemeKitUI/ThemedMenu.swift Tests/ThemeKitUITests/ThemedMenuTests.swift
git commit -m ":sparkles: feat(ThemeKitUI): route folder gates through hasChildren (t-esdf)"
```

---

### Task 3: `openSubmenu` seam — present-then-fill from the provider

**Files:**
- Modify: `Sources/ThemeKitUI/ThemedMenu.swift` (placeholder rows; `itemsTask` state; `openSubmenu` seam 718-728; cancel in `teardownAsChild` 743 + `invalidate` 523)
- Test: `Tests/ThemeKitUITests/ThemedMenuTests.swift`

**Interfaces:**
- Consumes: `hasChildren` (Task 2), `MenuItem.submenuProvider` (Task 1).
- Produces: opening a provider row shows a single disabled `Loading…` row synchronously, then fills with the awaited result (`No items` disabled row when `[]`); the in-flight fetch is dropped/cancelled if the child is torn down before it resolves.

- [ ] **Step 1: Write the failing tests**

Add to `ThemedMenuTests.swift` in the "Submenu cascade" section:

```swift
    func testProviderPresentThenFill() {
        let items: [ThemedMenu.MenuItem] = [
            .init(id: "branch", title: "Switch Branch",
                  submenuProvider: { [.init(id: "main", title: "main"), .init(id: "dev", title: "develop")] }),
        ]
        let (m, anchor) = anchoredMenu(items)
        m.present(from: anchor)
        m._openSubmenu("branch")
        XCTAssertTrue(m.menuProbe.childOpen, "the child opens immediately")
        XCTAssertEqual(m.menuProbe.childRowCount, 1, "synchronously shows a single Loading… row")
        XCTAssertEqual(m._child?._controller.items.first?.isDisabled, true, "the Loading… row is disabled")
        pump()                                             // let the async provider + assignment run (FIFO)
        XCTAssertEqual(m.menuProbe.childRowCount, 2, "the child fills with the resolved rows")
        XCTAssertEqual(m.menuProbe.childHighlightedID, "main", "highlightFirst lights the first resolved row")
        m.dismiss(animated: false)
    }

    func testProviderEmptyResultShowsNoItemsRow() {
        let items: [ThemedMenu.MenuItem] = [
            .init(id: "branch", title: "Switch Branch", submenuProvider: { [] }),
        ]
        let (m, anchor) = anchoredMenu(items)
        m.present(from: anchor)
        m._openSubmenu("branch")
        pump()
        XCTAssertEqual(m.menuProbe.childRowCount, 1, "an empty result shows a single row")
        XCTAssertEqual(m._child?._controller.items.first?.isDisabled, true, "the No items row is disabled")
        m.dismiss(animated: false)
    }

    func testProviderStaleResolveIsDroppedAfterClose() {
        let items: [ThemedMenu.MenuItem] = [
            .init(id: "branch", title: "Switch Branch",
                  submenuProvider: { [.init("main")] }),
        ]
        let (m, anchor) = anchoredMenu(items)
        m.present(from: anchor)
        m._openSubmenu("branch")
        XCTAssertEqual(m.menuProbe.childRowCount, 1, "loading row shown")
        m._closeChild()                                    // tear the child down BEFORE the async resolves
        XCTAssertFalse(m.menuProbe.childOpen)
        pump()                                             // the awaited result must be dropped, not repopulate
        XCTAssertFalse(m.menuProbe.childOpen, "the torn-down child is not repopulated")
        m.dismiss(animated: false)
    }

    func testStaticChildrenWinOverProvider() {
        var providerConsulted = false
        let items: [ThemedMenu.MenuItem] = [
            .init(id: "more", title: "More",
                  submenu: [.init(id: "s1", title: "Sub 1"), .init(id: "s2", title: "Sub 2")],
                  submenuProvider: { providerConsulted = true; return [.init("P")] }),
        ]
        let (m, anchor) = anchoredMenu(items)
        m.present(from: anchor)
        m._openSubmenu("more")
        XCTAssertEqual(m.menuProbe.childRowCount, 2, "static children render immediately")
        pump()
        XCTAssertFalse(providerConsulted, "the provider is not consulted when static children exist")
        XCTAssertEqual(m.menuProbe.childRowCount, 2, "and the static rows are unchanged")
        m.dismiss(animated: false)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/test.sh 2>&1 | pare`
Expected: FAIL — `testProviderPresentThenFill` shows `childRowCount == 0` (the seam assigns the empty static `submenu`; no Loading row, no fill). The other three fail similarly.

- [ ] **Step 3: Write minimal implementation**

In `ThemedMenu.swift`, add the placeholder-row helpers near the `MenuItem` static helpers or just below the class's other private statics (e.g. beside `checkmark`, referenced at line 325). Computed statics avoid a stored non-Sendable global:

```swift
    // Disabled, non-interactive placeholder rows for a deferred submenu.
    private static var loadingRow: MenuItem { MenuItem(id: "__themedmenu.loading", title: "Loading…", isEnabled: false) }
    private static var emptyRow: MenuItem   { MenuItem(id: "__themedmenu.empty",   title: "No items", isEnabled: false) }
```

Add the in-flight-fetch state beside `fadeGen` (line 233):

```swift
    private var fadeGen = 0
    /// The in-flight deferred-submenu fetch while THIS menu is an open child.
    /// Cancelled on teardown so a hover-away / re-target stops the provider's work.
    private var itemsTask: Task<Void, Never>?
```

Replace the seam body in `openSubmenu` (current lines 718-728, from `closeChild()` through the final `if highlightFirst …`):

```swift
        closeChild()
        let c = ThemedMenu(palette: palette)
        c.parentMenu = self
        c.surfaceColor = surfaceColor
        c.highlightsFirstOnOpen = false
        c.density = density
        child = c
        childRowID = id
        if !mi.submenu.isEmpty {
            c.items = mi.submenu                                 // static children — byte-identical legacy path
            c.presentAsSubmenu(rowRectOnScreen: rowRect, in: host)
            if highlightFirst { c.controller.moveHighlight(1) }
        } else if let provider = mi.submenuProvider {
            c.items = [ThemedMenu.loadingRow]                    // present-then-fill: a disabled placeholder
            c.presentAsSubmenu(rowRectOnScreen: rowRect, in: host)
            c.itemsTask = Task { [weak c] in
                let kids = await provider()
                guard let c, c.isOpen, !Task.isCancelled else { return }   // dropped if torn down / re-targeted
                c.items = kids.isEmpty ? [ThemedMenu.emptyRow] : kids
                if highlightFirst { c.controller.moveHighlight(1) }
            }
        }
```

Cancel the fetch on teardown. In `teardownAsChild` (743), add as the first line:

```swift
    private func teardownAsChild() {
        itemsTask?.cancel(); itemsTask = nil
        closeChild()
        guard isOpen else { return }
        ...
```

In `invalidate` (523), add after `isInvalidated = true`:

```swift
    public func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        itemsTask?.cancel(); itemsTask = nil
        hoverWork?.cancel(); hoverWork = nil
        ...
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/test.sh 2>&1 | pare`
Expected: PASS — the four new tests green; the full ThemedMenu suite (static cascade, deep cascade, horizontal, AX) stays green (`c.items = mi.submenu` path unchanged when a static submenu is present).

- [ ] **Step 5: Commit**

```bash
git add Sources/ThemeKitUI/ThemedMenu.swift Tests/ThemeKitUITests/ThemedMenuTests.swift
git commit -m ":sparkles: feat(ThemeKitUI): present-then-fill deferred submenuProvider (t-esdf)"
```

---

### Task 4: prism showcase + KitCatalog doc

**Files:**
- Modify: `Sources/prism/WandShowcase.swift:65-69` (Switch Branch → provider)
- Modify: `Sources/prism/MenuShowcase.swift:56-73` (a generic provider-backed folder)
- Modify: `Sources/prism/KitCatalog.swift:690-728` (document `submenuProvider`)

**Interfaces:**
- Consumes: `MenuItem.submenuProvider` (Task 1) via the unchanged `ThemedMenuTriggerView(items:)` bridge (no bridge change — the provider rides on each `MenuItem`).

> The per-theme inline-mock grids (`MockMenu`, `MockWandLauncher`) draw submenu results as static `ListPreview` rows and never run the controller, so they stay deterministic and need no change. The live triggers demonstrate the real loading→filled motion (a floating child can't be screencaptured anyway — prism-bench note); we do NOT add a controller preview override (that would widen the AppKit-adjacent seam for no capturable gain).

- [ ] **Step 1: Convert wand's Switch Branch to a real provider**

In `WandShowcase.swift`, replace the static Switch Branch folder (65-69) with a deferred provider that returns the same faux branches after a brief faux-git delay so the live trigger shows loading→filled:

```swift
        ThemedMenu.MenuItem(id: "branch", title: "Switch Branch", icon: wandGlyph("git-branch"),
                            submenuProvider: {
            try? await Task.sleep(for: .milliseconds(400))     // faux `git branch` shell-out
            return [
                ThemedMenu.MenuItem("main",    icon: wandGlyph("git-branch")) {},
                ThemedMenu.MenuItem("develop", icon: wandGlyph("git-branch")) {},
                ThemedMenu.MenuItem("hotfix",  icon: wandGlyph("git-branch")) {},
            ]
        }),
```

- [ ] **Step 2: Add a generic provider folder to the menu showcase**

In `MenuShowcase.swift`, add one provider-backed folder to `menuTriggerItems()` (after the "Open Recent" static folder, ~line 66) so the hook is showcased independent of wand:

```swift
        ThemedMenu.MenuItem(id: "insert", title: "Insert Snippet", icon: menuGlyph("code"),
                            submenuProvider: {
            try? await Task.sleep(for: .milliseconds(300))
            return [
                ThemedMenu.MenuItem("Header", icon: menuGlyph("file")) {},
                ThemedMenu.MenuItem("Footer", icon: menuGlyph("file")) {},
            ]
        }),
```

- [ ] **Step 3: Document the hook in KitCatalog**

In `KitCatalog.swift`, add a `keyAPI` bullet in the ThemedMenu entry immediately after the `MenuItem.submenu` line (693):

```swift
                 "MenuItem.submenuProvider: (@MainActor () async -> [MenuItem])? — DEFERRED children: opening the row shows a disabled Loading… row, then fills from the awaited closure (No items on []); re-invoked per open (cache-free); static submenu wins if both are set; the in-flight fetch is cancelled on close. Consumer: wand's real launcher (async PanelTree walk).",
```

And update the `cellInit` string (728) to include the new parameter:

```swift
        cellInit: "MenuItem(_:icon:shortcut:isEnabled:isDestructive:submenu:submenuProvider:action:) — MenuItem(\"Title\") { } — only the title is required (icon/shortcut/isEnabled/isDestructive/submenu/submenuProvider/action all default; a submenuProvider makes the row a deferred folder; `.separator(id:)`/`.header(_:id:)` build non-interactive rows).",
```

- [ ] **Step 4: Verify prism builds + the demo renders**

Run: `swift build 2>&1 | pare`
Expected: PASS (compiles). Then launch prism and confirm the ThemedMenu / wand card shows the live trigger; hovering "Switch Branch" (wand) or "Insert Snippet" (menu) shows the `Loading…` row then the filled rows. Capture per the prism recipe (winid + `screencapture -l`, no osascript activation). See Task 5 for the live-verify gate.

- [ ] **Step 5: Commit**

```bash
git add Sources/prism/WandShowcase.swift Sources/prism/MenuShowcase.swift Sources/prism/KitCatalog.swift
git commit -m ":sparkles: feat(prism): showcase deferred submenuProvider (t-esdf)"
```

---

### Task 5: Full-suite gate + live prism verify + version

**Files:** none (verification + release).

- [ ] **Step 1: Run the full test suite**

Run: `scripts/test.sh 2>&1 | pare`
Expected: the whole XCTest suite green (all modules), including every `ThemedMenuTests` case.

- [ ] **Step 2: CLT compile bar**

Run: `swift build 2>&1 | pare`
Expected: PASS on CommandLineTools (no Xcode-only API crept in).

- [ ] **Step 3: Prove loading→filled LIVE in prism**

Launch prism (`PRISM_CONFIG` per the bench recipe, run in background), open the ThemedMenu / wand showcase, hover a provider folder, and confirm: chevron present → click/hover → `Loading…` row → resolved rows (with the first highlighted). Screenshot via `screencapture -l<winid> -o out.png` (no osascript). If no display is available, fall back to a launch smoke + note that live verification is pending (per the prism-bench memory).

- [ ] **Step 4: Open the PR**

```bash
git push -u origin worktree-esdf-submenu-provider
gh pr create --title ":sparkles: feat(ThemeKitUI): ThemedMenu deferred submenuProvider (t-esdf)" \
  --body "$(cat <<'EOF'
Adds a per-item `submenuProvider: (@MainActor () async -> [MenuItem])?` to
`ThemedMenu.MenuItem` — a folder row can supply its children lazily/asynchronously
(present-then-fill with a Loading… row; No items on []; cache-free; static wins;
in-flight fetch cancelled on close). Floor-#2-safe: pure value-side addition, no
new AppKit. prism: wand's Switch Branch + a generic menu folder demo the hook.

Design: docs/superpowers/specs/2026-07-06-themedmenu-submenuprovider-design.md
Plan:   docs/superpowers/plans/2026-07-06-themedmenu-submenuprovider.md

SetStatus-task: https://github.com/akira-toriyama/projects/blob/main/.furrow/bodies/t-esdf.md in-progress

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Merge + tag (after CI green; per the CI-green-merge-OK standing OK)**

```bash
gh pr merge --squash
git fetch origin --tags
git tag v3.2.0 origin/main   # after the squash lands on origin/main
git push origin v3.2.0
```

Update the PR footer lane to the task's done lane on merge (the `SetStatus-task:` automation applies it), and confirm the furrow board reflects it.

---

## Self-Review

**1. Spec coverage:**
- API `submenuProvider` on MenuItem → Task 1. ✓
- `hasSubmenu` derivation includes provider → Task 1. ✓
- `hasChildren` predicate + 5 gates → Task 2. ✓
- Seam present-then-fill, Loading…/No items, generation-safe drop, cancellation → Task 3. ✓
- Static-wins → Task 3 (`testStaticChildrenWinOverProvider`). ✓
- @MainActor / non-throwing / non-Sendable → Task 1 signature + Global Constraints. ✓
- prism WandShowcase provider + generic folder + preview note + KitCatalog → Task 4. ✓
- Tests (provider-folder, present-then-fill, stale-resolve, empty, static regression) → Tasks 1-3. ✓
- Gate scripts/test.sh + prism live + swift build → Task 5. ✓
- Version v3.2.0 tag → Task 5. ✓
- wand real-signature note → non-blocking (spec §"Non-blocking note"); a zero-arg closure is shipped, confirmed against wand at Phase B. ✓

**2. Placeholder scan:** no TBD/TODO; every code step shows full code. ✓

**3. Type consistency:** `submenuProvider: (@MainActor () async -> [MenuItem])?` identical in field, both inits, KitCatalog doc, and tests. `hasChildren(_:)`, `loadingRow`/`emptyRow`, `itemsTask` names consistent across Tasks 2-3. `_controller`/`_child`/`_openSubmenu`/`_closeChild`/`_activate`/`menuProbe` match the DEBUG seam (ThemedMenu.swift 1021-1034). ✓

**Note on cancellation test scope:** the explicit `Task.cancel()` (real git I/O hygiene) is verified indirectly by `testProviderStaleResolveIsDroppedAfterClose` (the dropped result is the observable contract); a direct "isCancelled observed inside the provider" assertion is intentionally omitted as non-deterministic (YAGNI).
