# wand prism-mock PR1 — ThemedMenu N-level cascade + wand vertical mock — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lift `ThemedMenu`'s one-level cascade cap to arbitrary depth (N-level), and rebuild wand's default `.list` launcher-tome in prism from the real kit so it themes across every catalog theme.

**Architecture:** N-level needs no rewrite — `ThemedMenu`'s child-chain already recurses (`activeLeaf` / `teardownAsChild` / `clickIsInside` / `.submenu` placement). Two `parentMenu == nil` guards block descent and `validateOpenChild()` re-anchors only the direct child; relax the guards + recurse the re-anchor. The wand mock is a new `WandShowcase.swift` composing a real `ThemedTextFieldView` + inline `ThemedListView`s (a deterministic 2-level cascade still, since the real menu's floating panels can't be screenshotted) beside a `ThemedMenuTriggerView` that opens the real N-level menu live.

**Tech Stack:** Swift, AppKit (`@MainActor`), SwiftUI (prism bench), SwiftPM. No new dependencies.

## Global Constraints

- **Local gate is `swift build` only.** The maintainer's machine is CommandLineTools-only (no Xcode) → `import XCTest` cannot run locally. Every task's local check is `swift build`; the XCTest in Task 1 is authored here and **runs in CI** (`.github/workflows/build.yml`, full Xcode). Do NOT claim a test passed locally — the local "test-fails / test-passes" steps below are CI-gated, verified locally only insofar as they compile.
- **UI is proven LIVE in prism**, not off an unrun test (Task 3).
- Commits: **gitmoji + Conventional Commits** (`commit-lint`-enforced), e.g. `:sparkles: feat(ThemeKit): …`. End each commit body with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Canonical role fields only: `background · foreground · muted · tertiary · primary · secondary · border · hover · selection · error`.
- **AppKit floor policy**: N-level = more instances of the existing floor-#2 popup shell — **no new AppKit floor**. If any step reaches for AppKit beyond that, halt and 要相談.
- Work is in the existing isolated worktree off clean `origin/main` (`branch worktree-wand-prism-mock`); the design spec is `docs/superpowers/specs/2026-07-01-wand-prism-mock-design.md`.
- Library change ⇒ **minor bump + a `v`-prefixed tag** at merge. Current `git tag` tip is **v1.40.0** → this ships **v1.41.0**.
- PR footer (non-blocking): `SetStatus-task: https://github.com/akira-toriyama/projects/blob/main/.furrow/bodies/t-yc68.md in-progress`.

## File Structure

- `Sources/ThemeKit/ThemedMenu.swift` (modify) — the controller. Relax 2 guards, recurse `validateOpenChild()`, refresh the cap docs. **`PopupPanel.swift` is NOT touched** (`.submenu` placement already works per level).
- `Tests/ThemeKitTests/ThemedMenuTests.swift` (modify) — replace the one-level-cap test with depth-N cascade tests.
- `Sources/prism/WandShowcase.swift` (create) — `MockWandLauncher` + its inline row/menu data.
- `Sources/prism/Specimens.swift` (modify) — delete the hand-drawn `MockTome`.
- `Sources/prism/Gallery.swift` (modify) — repoint `case .wand:`.
- `Sources/prism/KitCatalog.swift` (modify) — update the `ThemedMenu` catalog entry + wand `AppChrome`.

---

### Task 1: N-level cascade in ThemedMenu

**Files:**
- Modify: `Sources/ThemeKit/ThemedMenu.swift`
- Test: `Tests/ThemeKitTests/ThemedMenuTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: no API change — `ThemedMenu.MenuItem.submenu: [MenuItem]` now cascades to arbitrary depth at runtime (a submenu row's child may open its own child). The DEBUG seams `_openSubmenu(_:)`, `_child`, `_closeChild()`, `menuProbe.{childOpen,childRowID,childRowCount,childHighlightedID,leafIsChild,isOpen}` are unchanged and now reach grandchildren via `m._child?._child`.

- [ ] **Step 1: Replace the one-level-cap test with depth-N cascade tests**

In `Tests/ThemeKitTests/ThemedMenuTests.swift`, DELETE `testOneLevelCapOpensNoGrandchild()` (currently lines 419–432) and add, in the "Submenu cascade" region:

```swift
    // MARK: - Submenu cascade (N-level)

    /// A two-level cascade: More → Deep → G1/G2.
    private func deepCascadeItems() -> [ThemedMenu.MenuItem] {
        [.init(id: "more", title: "More", submenu: [
            .init(id: "deep", title: "Deep", submenu: [
                .init(id: "g1", title: "G1"),
                .init(id: "g2", title: "G2"),
            ]),
        ])]
    }

    func testChildOpensGrandchild() {
        let (m, anchor) = anchoredMenu(deepCascadeItems())
        m.present(from: anchor)
        m._openSubmenu("more")
        XCTAssertTrue(m.menuProbe.childOpen, "the level-1 child opens")
        m._child?._openSubmenu("deep")           // open a grandchild from the child
        XCTAssertTrue(m._child?.menuProbe.childOpen ?? false, "a child now opens its grandchild (N-level)")
        XCTAssertEqual(m._child?._child?.menuProbe.childRowCount, 2, "the grandchild hosts Deep's rows")
        m.dismiss(animated: false)
    }

    func testDismissTearsDownWholeDeepChain() {
        let (m, anchor) = anchoredMenu(deepCascadeItems())
        m.present(from: anchor)
        m._openSubmenu("more")
        m._child?._openSubmenu("deep")
        XCTAssertTrue(m._child?.menuProbe.childOpen ?? false, "grandchild open before dismiss")
        m.dismiss(animated: false)
        XCTAssertFalse(m.menuProbe.isOpen, "root closed")
        XCTAssertFalse(m.menuProbe.childOpen, "child closed (children-first teardown)")
    }

    func testEscClosesDeepChainOneLevelAtATime() {
        let (m, anchor) = anchoredMenu(deepCascadeItems())
        m.present(from: anchor)
        m._openSubmenu("more")
        m._child?._openSubmenu("deep")
        XCTAssertTrue(m._child?.menuProbe.childOpen ?? false, "grandchild open")
        XCTAssertNil(m._handleKey(keyDown(53)), "Esc swallowed")
        XCTAssertFalse(m._child?.menuProbe.childOpen ?? true, "first Esc closes the deepest (grandchild) level")
        XCTAssertTrue(m.menuProbe.childOpen, "the level-1 child stays open")
        XCTAssertNil(m._handleKey(keyDown(53)))
        XCTAssertFalse(m.menuProbe.childOpen, "second Esc closes the child level")
        XCTAssertTrue(m.menuProbe.isOpen, "the root stays open")
        XCTAssertNil(m._handleKey(keyDown(53)))
        XCTAssertFalse(m.menuProbe.isOpen, "third Esc dismisses the root")
    }

    func testCloseChildTearsDownDeeperLevels() {
        // The mechanism a hover-onto-a-non-submenu-row uses: closeChild() must
        // recursively collapse EVERY deeper level, not just the direct child.
        let (m, anchor) = anchoredMenu(deepCascadeItems())
        m.present(from: anchor)
        m._openSubmenu("more")
        m._child?._openSubmenu("deep")
        XCTAssertTrue(m._child?.menuProbe.childOpen ?? false, "grandchild open")
        m._closeChild()                          // collapse from the root
        XCTAssertFalse(m.menuProbe.childOpen, "the whole open chain collapses (child + grandchild)")
        m.dismiss(animated: false)
    }
```

- [ ] **Step 2: Run the new tests to confirm they FAIL (CI)**

Run in CI (locally XCTest can't run): `swift test --filter ThemedMenuTests`
Expected: `testChildOpensGrandchild` FAILS — today the child opens no grandchild (the guard). The other three may error on the same cap. (Locally, only confirm the file compiles under `swift build` after Step 3.)

- [ ] **Step 3: Relax the two guards + recurse the re-anchor + refresh docs**

In `Sources/ThemeKit/ThemedMenu.swift`:

(a) `handleHover` — remove the root-only guard (line 446):
```swift
    private func handleHover(_ id: String?) {
        // Each menu drives its OWN child; the cascade chains N deep and only one
        // path is ever open, so there is no cross-level contention.
        hoverWork?.cancel(); hoverWork = nil
```
(delete the old `guard parentMenu == nil else { return }         // only the root drives the cascade` line.)

(b) `openSubmenu` — remove the grandchild cap (line 467):
```swift
    private func openSubmenu(rowID id: String, highlightFirst: Bool) {
        hoverWork?.cancel(); hoverWork = nil
```
(delete the old `guard parentMenu == nil else { return }         // a child opens no grandchild` line.)

(c) `validateOpenChild` — recurse so descendants re-anchor (lines 518–520):
```swift
        if let rect = list.rowRectOnScreen(for: id) {
            c.submenuRowOnScreen = rect
            c.reframe()
            c.validateOpenChild()                            // recurse: re-anchor the whole descendant chain
        } else {
```

(d) Doc refresh — `MenuItem.submenu` (lines 59–62):
```swift
        /// Child rows. Non-empty ⇒ this row opens a cascade: hover / `→` / click
        /// opens a child menu beside the row, and the child's own submenu rows
        /// cascade further (N-level, arbitrary depth). A submenu row's own `action`
        /// is ignored — opening the child IS its activation.
```

(e) Doc refresh — the internals comment (lines 167–171):
```swift
    // Submenu cascade (N-level). A submenu row owns a CHILD ThemedMenu placed beside
    // it, and that child may open its OWN child — the cascade chains to arbitrary
    // depth, but only ONE path is open at a time (each menu has a single `child`).
    // The ROOT owns ALL keyboard / mouse / glue and routes keys to the active leaf,
    // so a child installs none. `parentMenu` marks a child (walk to the root / close
    // one level). `submenuRowOnScreen` is a child's placement anchor (its parent row).
```

(f) Doc refresh — `openSubmenu`'s doc comment (lines 464–465):
```swift
    /// Open (or re-target) the submenu child for parent row `id`, placed beside it.
    /// Runs at any depth (a child opens its own child — the cascade chains). No-op on
    /// a disabled / non-submenu / off-screen row.
```

- [ ] **Step 4: `swift build` (the local gate)**

Run: `swift build`
Expected: `Build complete!` — the guard removals + one recursion line compile clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/ThemeKit/ThemedMenu.swift Tests/ThemeKitTests/ThemedMenuTests.swift
git commit -m ":sparkles: feat(ThemeKit): ThemedMenu N-level submenu cascade — lift the one-level cap (t-yc68)" \
           -m "Relax the two parentMenu==nil guards so a child opens its own child; recurse validateOpenChild so descendants re-anchor. activeLeaf/teardownAsChild/clickIsInside/.submenu placement already recurse. Depth-N XCTest replaces the one-level-cap test." \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: WandShowcase — MockWandLauncher (inline cascade + live trigger)

**Files:**
- Create: `Sources/prism/WandShowcase.swift`
- Modify: `Sources/prism/Specimens.swift` (delete `MockTome`, lines 303–369, and drop its mention in the header comment line 7)
- Modify: `Sources/prism/Gallery.swift:379`
- Modify: `Sources/prism/KitCatalog.swift` (the `ThemedMenu` entry ~line 431; the wand `AppChrome` lines 596–599)

**Interfaces:**
- Consumes: from Task 1, `ThemedMenu.MenuItem.submenu` cascading N-level (used by the live trigger's items). Real kit: `ThemedTextFieldView(palette:placeholder:leading:surface:)`, `ThemedListView(palette:) { list in … }`, `ListItem(id:image:primary:secondary:trailing:tint:kind:)`, `TrailingAccessory.{chevron,shortcut}`, `ThemedMenuTriggerView(palette:items:)`; prism helpers `SpecimenBox(title:p:)`, `phosphorImage(_:pt:)`, `appIcon(_:)`, `uiScale`, `sysFont(_:weight:design:)`, `panelStroke(_:)`.
- Produces: `struct MockWandLauncher: View { let p: ResolvedPalette }` — the `.wand` app-tab body.

- [ ] **Step 1: Create `Sources/prism/WandShowcase.swift`**

```swift
// prism — wand launcher-tome bench. wand's launcher is a bespoke cascading panel
// tree (app-side); this mock rebuilds its DEFAULT `.list` tome from the REAL sill
// kit: a `ThemedTextFieldView` query field + inline `ThemedListView`s (mirroring
// `ThemedMenu`'s item→row mapping) for a static, deterministic 2-level cascade
// still, plus a `ThemedMenuTriggerView` live trigger that opens the REAL N-level
// `ThemedMenu` (the floating panels can't sit in a screenshot). prism never imports
// wand's View — these are mock shapes drawn by the real kit (zero drift).

import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKit
import ThemeKitUI

@MainActor private func wandGlyph(_ name: String, _ pt: CGFloat = 15) -> NSImage? {
    phosphorImage(name, pt: pt)                    // a Phosphor slug → template NSImage
}

// The tome's command rows (mirror ThemedMenu's MenuItem→ListItem mapping). The
// "Switch Branch" folder row is pre-lit (previewHighlight) as if hovered; its
// children render in the offset child list to depict an OPEN cascade.
@MainActor private func tomeRows() -> [ListItem] {
    [
        ListItem(id: "safari", image: appIcon(["com.apple.Safari"]) ?? wandGlyph("compass"),
                 primary: "Safari", secondary: "launch"),
        ListItem(id: "settings", image: wandGlyph("gear"), primary: "System Settings",
                 trailing: .shortcut("⌘,")),
        ListItem(id: "theme", image: wandGlyph("palette"), primary: "Switch theme"),
        ListItem(id: "sep", primary: "", kind: .separator),
        ListItem(id: "openin", image: wandGlyph("folder"), primary: "Open in…", trailing: .chevron),
        ListItem(id: "branch", image: wandGlyph("git-branch"), primary: "Switch Branch", trailing: .chevron),
    ]
}

// The offset child list = the "Switch Branch" folder's async result (faux git
// branches, drawn statically — the still of wand's shell-fed submenu).
@MainActor private func branchRows() -> [ListItem] {
    [
        ListItem(id: "main", image: wandGlyph("git-branch"), primary: "main"),
        ListItem(id: "dev",  image: wandGlyph("git-branch"), primary: "develop"),
        ListItem(id: "feat", image: wandGlyph("git-branch"), primary: "feature/cascade"),
    ]
}

// The live trigger's items — a real ≥2-level cascade (Open in… → Editors → …) so
// clicking proves N-level LIVE (what the static shot can't hold).
@MainActor private func wandMenuItems() -> [ThemedMenu.MenuItem] {
    [
        ThemedMenu.MenuItem("Safari", icon: appIcon(["com.apple.Safari"])) {},
        ThemedMenu.MenuItem("System Settings", icon: wandGlyph("gear"), shortcut: "⌘,") {},
        .separator(),
        ThemedMenu.MenuItem(id: "openin", title: "Open in…", icon: wandGlyph("folder"), submenu: [
            ThemedMenu.MenuItem(id: "editors", title: "Editors", icon: wandGlyph("code"), submenu: [
                ThemedMenu.MenuItem("VS Code", icon: wandGlyph("code")) {},
                ThemedMenu.MenuItem("Xcode",   icon: wandGlyph("hammer")) {},
            ]),
            ThemedMenu.MenuItem("Finder", icon: wandGlyph("folder")) {},
        ]),
        ThemedMenu.MenuItem(id: "branch", title: "Switch Branch", icon: wandGlyph("git-branch"), submenu: [
            ThemedMenu.MenuItem("main",             icon: wandGlyph("git-branch")) {},
            ThemedMenu.MenuItem("develop",          icon: wandGlyph("git-branch")) {},
            ThemedMenu.MenuItem("feature/cascade",  icon: wandGlyph("git-branch")) {},
        ]),
    ]
}

struct MockWandLauncher: View {
    let p: ResolvedPalette

    private var surface: Color { Color(nsColor: p.background ?? .windowBackgroundColor) }

    // Compact rows are 26pt; separators ~7pt. 5 rows + 1 sep + vpad ≈ 145; 3 rows ≈ 86.
    private let tomeListHeight: CGFloat = 145
    private let childListHeight: CGFloat = 86

    var body: some View {
        SpecimenBox(title: "wand · tome", p: p) {
            VStack(alignment: .leading, spacing: 12) {
                Text("wand's launcher tome, rebuilt from the real kit — the query field + inline ThemedLists mirror ThemedMenu's row mapping; the offset child list depicts an OPEN cascade (Switch Branch → faux branches). The live trigger opens the REAL N-level ThemedMenu (Open in… → Editors → VS Code / Xcode). wand's shell-fed submenus + motion stay app-side.")
                    .font(sysFont(9, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(nsColor: p.muted))
                    .fixedSize(horizontal: false, vertical: true)

                // Tier 1 — the static tome + its open cascade (deterministic still).
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 6) {
                        ThemedTextFieldView(palette: p, placeholder: "open…",
                                            leading: "magnifying-glass", surface: p.background)
                            .frame(width: 232, height: 40)
                        menuCard(rows: tomeRows(), lit: "branch", height: tomeListHeight, width: 232)
                    }
                    // The child cascade, offset down to sit beside the "Switch Branch" row.
                    menuCard(rows: branchRows(), lit: "main", height: childListHeight, width: 190)
                        .padding(.top, 46 + tomeListHeight - childListHeight - 26)   // align to the folder row
                }

                // Tier 2 — the live trigger opens the REAL extended ThemedMenu.
                VStack(alignment: .leading, spacing: 6) {
                    Text("live · opens the real N-level menu")
                        .font(sysFont(8, design: .monospaced))
                        .foregroundColor(Color(nsColor: p.tertiary))
                    ThemedMenuTriggerView(palette: p, title: "Actions", items: wandMenuItems())
                        .frame(width: 150, height: 38)
                }
            }
        }
    }

    // A rounded, bordered, shadowed menu surface hosting a real ThemedList in menu
    // config with a lit row — the MockMenu inline-mock recipe.
    @ViewBuilder private func menuCard(rows: [ListItem], lit: String,
                                       height: CGFloat, width: CGFloat) -> some View {
        ThemedListView(palette: p) { list in
            list.items = rows
            list.selectionMode = .none
            list.hoverStyle = .solidAccent
            list.highlightFollowsHover = true
            list.density = .compact
            list.previewHighlight = lit
        }
        .frame(width: width, height: height)
        .padding(.vertical, 4)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: p.border), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 9, y: 4)
    }
}
```

Note: if `git-branch` / `code` / `hammer` / `compass` / `folder` isn't in the vendored Phosphor subset, add it per `Sources/ThemeKit/Resources/README.md` (a missing lookup returns nil + prints that pointer in DEBUG, so the build stays green — the icon just renders empty until added). `gear`, `palette`, `magnifying-glass`, `folder` are already used by the current `MockTome` / `MockMenu`.

- [ ] **Step 2: Delete the hand-drawn `MockTome` + repoint `.wand`**

In `Sources/prism/Specimens.swift`, delete the whole `MockTome` block (`// MARK: - wand tome (launcher)` through the end of the struct, lines ~303–369) and remove `· MockTome (wand)` from the header comment (line 7).

In `Sources/prism/Gallery.swift`, line 379:
```swift
        case .wand:
            appCaption(.wand, p: p)
            MockWandLauncher(p: p)
```

- [ ] **Step 3: Update the KitCatalog copy**

In `Sources/prism/KitCatalog.swift`, the `ThemedMenu` entry (~line 431) — update its `kind` string to reflect N-level:
```swift
        kind: "MUI <Menu> — a themed floating pop-up menu of action rows with N-level submenu cascade",
```
And the wand `AppChrome` (lines 596–599) — add `ThemedMenu` to `uses`:
```swift
    AppChrome(tab: .wand,
        blurb: "gesture daemon — fullscreen trail + non-activating launcher tome",
        uses: "Palette · Effects · CLIKit · ThemedMenu (tome cascade) · line-pets (trail bespoke)",
        themes: "7 themes (chomp · splatoon · neon · vapor · mono · …)"),
```

- [ ] **Step 4: `swift build` (the local gate)**

Run: `swift build`
Expected: `Build complete!` — `MockWandLauncher` compiles and `MockTome` is fully removed (no dangling reference; grep confirms):
Run: `grep -rn "MockTome" Sources/` → expected: no output.

- [ ] **Step 5: Commit**

```bash
git add Sources/prism/WandShowcase.swift Sources/prism/Specimens.swift Sources/prism/Gallery.swift Sources/prism/KitCatalog.swift
git commit -m ":sparkles: feat(prism): wand launcher-tome mock from the real kit — inline cascade + live N-level trigger (t-yc68)" \
           -m "Replace the hand-drawn MockTome with MockWandLauncher: real ThemedTextFieldView + inline ThemedListView cascade (deterministic still) + a ThemedMenuTriggerView that opens the real N-level ThemedMenu. Repoint Gallery .wand; refresh KitCatalog." \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Prove the wand tome LIVE in prism across themes

**Files:** none (verification task — the UI gate; no commit unless a tweak is needed).

**Interfaces:** consumes the built `.build/debug/prism`.

- [ ] **Step 1: Build prism**

Run: `swift build --product prism`
Expected: `Build complete!`

- [ ] **Step 2: Launch prism on the wand tab across themes + capture**

Follow the prism capture recipe (no `osascript` activation — it jumps Spaces and flakes the shot). For each theme in {`neon-noir` (dark/animated), `github-light` (light), one more animatable e.g. `biolume`}:

```bash
# family default tab is .palette — point PRISM_CONFIG at a config that opens the
# wand (Apps) tab + the target theme, launch in the background, grab the window id,
# then screencapture -l<winid> (top-left-origin) WITHOUT activating.
PRISM_CONFIG=/private/tmp/claude-501/.../wand-neon-noir.toml .build/debug/prism &
winid=$(GetWindowID prism --list | ...)      # the prism-bench winid helper
screencapture -l"$winid" -o /private/tmp/.../wand-neon-noir.png
```
Expected: the card shows the tome (query field + command list), the **offset child list beside the "Switch Branch" row** (the open cascade), and the live-trigger button — all re-themed to the palette (selection wash on the lit rows, readable text on light + dark).

- [ ] **Step 3: Eyeball the still + drive the live cascade**

- Confirm across all three shots: text is legible, the lit-row `selection` wash reads, the child list aligns beside its folder row (tune the `.padding(.top, …)` offset + the two list heights in `WandShowcase.swift` if it's off, then rebuild + re-shoot).
- Open the real menu: click the live trigger, hover **Open in… → Editors → VS Code** — confirm a true **3-deep** cascade opens, `→`/`←` walk levels, `Esc` closes one level at a time, and clicking a leaf dismisses the whole chain. (This is the N-level proof the still can't show.)

- [ ] **Step 4: If a visual tweak was needed, commit it**

```bash
git add Sources/prism/WandShowcase.swift
git commit -m ":lipstick: style(prism): tune wand tome cascade offset / list metrics from live capture (t-yc68)" \
           -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Done criteria (PR1)

- `swift build` green locally; CI green (build + `swift test`, incl. the new depth-N tests).
- prism live shows the wand tome + open cascade themed correctly on ≥ dark + light + one animatable theme; the live trigger opens a real 3-deep cascade.
- PR opened off `worktree-wand-prism-mock` with footer `SetStatus-task: …/t-yc68.md in-progress`. On green + clean: squash-merge, tag **v1.41.0**, and the KitCatalog/spec land in sill docs. (PR2 = horizontal presentation, separate plan.)

## Self-Review

**Spec coverage:** PR1 scope from the spec — ① N-level cascade (Task 1), the wand vertical mock via inline `ThemedListView` cascade + live trigger (Task 2), prism live verification (Task 3), KitCatalog/AppChrome refresh (Task 2). Horizontal + presentation-mode + `PopupPanel` below-anchor are explicitly PR2 (out of this plan). The corrected static-card mechanism (inline lists, not screenshotting real panels) is honored. ✓

**Placeholder scan:** no TBD/TODO; every code step shows complete code; the one variable ("phosphor slug may need vendoring") is handled with a concrete fallback + the exact README pointer. The prism launch command is a recipe (the winid helper + config path are environment-specific by nature) — flagged, not hidden. ✓

**Type consistency:** `MockWandLauncher(p:)` matches the `.wand` case call and the `MockPerchOverlay`/`MockGlancePopover` sibling shape; `ListItem(id:image:primary:secondary:trailing:kind:)` matches `ThemedList.swift:127`; `ThemedListView(palette:){list in …}` matches `MenuShowcase.swift:87`; `ThemedMenuTriggerView(palette:title:items:)` matches `ThemedMenuTriggerView.swift:19`; the DEBUG probe fields match `ThemedMenu.swift:727-744`. ✓
