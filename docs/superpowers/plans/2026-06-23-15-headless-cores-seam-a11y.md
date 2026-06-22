# #15 — Headless Pure Cores + controlled/uncontrolled Seam + a11y — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract Foundation-only pure cores from ThemedList/ComboBox/Menu into a new `ListCore` module (widgets delegate as byte-identical thin wrappers), codify the existing controlled/uncontrolled seam with firing setters, and fill the systemic a11y gap (zero `NSAccessibility.post` today) at P0/P1.

**Architecture:** New pure leaf module `ListCore` (zero deps, `import Foundation`, CG behind `#if canImport(CoreGraphics)`) holding selection resolution, roving-highlight math, ComboBox filter/reconcile, and Menu keycode→intent. ThemeKit gains a `ListCore` dependency; each widget's internal logic delegates to the core while keeping its public API and behavior **byte-identical** (the safety property, proven the same way as #14a/#14b). The seam and a11y work is additive (new firing setters + new AX notifications), invisible to existing callers and to prism visuals.

**Tech Stack:** Swift 6, SwiftPM, AppKit (`@MainActor` widgets), XCTest (runs in CI / full Xcode only — see Global Constraints).

## Global Constraints

- **`swift build` is the ONLY local gate** — the maintainer's machine is CommandLineTools-only (no Xcode, **no XCTest.framework**). `swift test` does NOT run locally for any target (verified 2026-06-23: `xcrun --find xctest` fails). All XCTest (new `ListCoreTests` included) runs **in CI (full Xcode)**. Therefore each task's local red/green is via the **compiler**: a test referencing a not-yet-written function makes `swift build` fail (red); implementing it makes `swift build` pass (green); CI confirms the assertions.
- **Byte-identical refactor** — Tasks 1–5 must NOT change any widget's public API or runtime behavior. The extracted pure function must be a verbatim lift of the current inline logic. Existing `ThemeKitTests` are the regression net (CI).
- **NSImage is non-Sendable** — `ListItem.image: NSImage?` and `Badge.symbol: NSImage?` mean `ListItem` CANNOT cross into `ListCore`. Every core signature takes an index/id + a selectability/label projection the AppKit side computes. NEVER pass `ListItem` into the core.
- **Module name ≠ primary type** — module is `ListCore`; do NOT create an `enum ListCore` namespace (Module.Module collision, the trap Palette/ThemeSpec dodges). Use top-level free functions (`resolveSelection`, `nextHighlight`, `comboFilter`, …) exactly like Motion (`lerp`, `spring`) and Gesture.
- **Commits:** gitmoji + Conventional Commits, subject in English; if a body is added, append a `---（和訳）` section (per the repo CLAUDE.md). Squash-merge appends `(#N)`.
- **Branch:** all work on `15-headless-cores-seam-a11y` (already cut from origin/main; spec + this plan committed there). Implementation should run in an **isolated git worktree off origin/main** ([[parallel-work-hazard]] — concurrent maintainer + 2nd session). **Re-confirm every file:line below in the worktree** — line numbers are a 2026-06-23 snapshot and local main can be stale.
- **a11y (Task 7) is NOT byte-identical** — it changes the accessibility tree (additively). It needs **maintainer VoiceOver verification** (agents cannot drive VO; prism cannot show it) — same maintainer-verify gate as [[chomp-push-gate]].
- Library change ⇒ **minor version bump + a `v`-prefixed tag** at merge; confirm the version isn't already claimed before tagging.

---

## File Structure

**New module `Sources/ListCore/`** (one file per concern, all `import Foundation`):
- `ListSelection.swift` — `resolveSelection` (selection resolution).
- `Highlight.swift` — `nextHighlight` (roving-highlight step).
- `ComboLogic.swift` — `comboFilter` + `reconcileSelection` (ComboBox-specific pure logic).
- `MenuLogic.swift` — `MenuKeyIntent` + `menuKeyIntent(keyCode:)` (Menu key routing).

**New tests `Tests/ListCoreTests/`** (XCTest, AppKit-free, CI-run):
- `ListSelectionTests.swift`, `HighlightTests.swift`, `ComboLogicTests.swift`, `MenuLogicTests.swift`.

**Modified (delegate to core / add seam / add a11y):**
- `Package.swift` — add `ListCore` library + target + test target; add `ListCore` to ThemeKit deps.
- `Sources/ThemeKit/ThemedList.swift` — `setSelection` → `resolveSelection`; `moveHighlight` → `nextHighlight`; selection a11y post.
- `Sources/ThemeKit/ThemedComboBox.swift` — `defaultFilter`/`optionsChanged` → core; `commitSelection` firing door; commit a11y.
- `Sources/ThemeKit/ThemedMenu.swift` — `handleKeyDown` → `menuKeyIntent`.
- `Sources/ThemeKit/ThemedCheckbox.swift` — `setChecked(_:notifying:)` firing door; toggle a11y post.
- `Sources/ThemeKit/ThemedTextField.swift` — `setText(_:notifying:)` firing door (generalize `clearText`).
- `Sources/ThemeKit/ThemedChip.swift`, `ThemedButtonGroup.swift` — a11y value + post.
- `Sources/ThemeKit/Shared.swift` — `postAXValueChanged()` helper.
- `docs/DESIGN.md` — extend `### Adding a widget`.

---

## Task 1: Create the `ListCore` module + wiring

**Files:**
- Create: `Sources/ListCore/ListCore.swift`
- Create: `Tests/ListCoreTests/SanityTests.swift`
- Modify: `Package.swift` (products ~line 40, targets ~line 87, ThemeKit deps ~line 129, testTargets ~line 158)

**Interfaces:**
- Produces: the `ListCore` module (empty but buildable); a `coreVersionMarker` constant so the test target links.

- [ ] **Step 1: Create the module file**

`Sources/ListCore/ListCore.swift`:
```swift
import Foundation

// ListCore — Foundation-only, Sendable, AppKit-free pure logic backing the
// stateful ThemeKit widgets (List → ComboBox/Menu). No type is named `ListCore`
// (module==type collision); the surface is top-level free functions, like Motion.
// CG conveniences, if any, go behind `#if canImport(CoreGraphics)`.

/// Internal build marker so a fresh test target has a symbol to import. Replaced
/// by real surface in later tasks; harmless to keep.
public let listCoreLinked = true
```

- [ ] **Step 2: Wire Package.swift — product**

Add after the `Gesture` library (`.library(name: "Gesture", targets: ["Gesture"]),`):
```swift
        .library(name: "ListCore", targets: ["ListCore"]),
```

- [ ] **Step 3: Wire Package.swift — target**

Add after the `.target(name: "Gesture"),` block:
```swift
        // Pure, Sendable, AppKit-free HEADLESS CORE for the stateful widgets —
        // selection resolution, roving-highlight math, ComboBox filter/reconcile,
        // Menu keycode→intent. ThemedList/ComboBox/Menu delegate to it as
        // byte-identical thin wrappers; #16/#17 SwiftUI will share the same core.
        // A pure leaf alongside Palette/Gesture/Motion: zero AppKit, zero Palette.
        .target(name: "ListCore"),
```

- [ ] **Step 4: Wire Package.swift — ThemeKit dependency**

Change the ThemeKit target dependency array (currently `["PaletteKit", "Palette", "Motion", .product(name: "SwiftDraw", …)]`) to add `"ListCore"`:
```swift
        .target(name: "ThemeKit",
                dependencies: ["PaletteKit", "Palette", "Motion", "ListCore",
                               .product(name: "SwiftDraw", package: "SwiftDraw")],
                exclude: ["Resources/README.md"],
                resources: [.copy("Resources/Phosphor"),
                            .copy("Resources/SimpleIcons")]),
```

- [ ] **Step 5: Wire Package.swift — test target**

Add after `.testTarget(name: "GestureTests", dependencies: ["Gesture"]),`:
```swift
        .testTarget(name: "ListCoreTests", dependencies: ["ListCore"]),
```

- [ ] **Step 6: Create a sanity test (proves the target links + imports)**

`Tests/ListCoreTests/SanityTests.swift`:
```swift
import XCTest
@testable import ListCore

final class SanityTests: XCTestCase {
    func testModuleLinks() {
        XCTAssertTrue(listCoreLinked)
    }
}
```

- [ ] **Step 7: Build**

Run: `swift build`
Expected: PASS (new module compiles; ThemeKit still builds with the added dep). Test assertions run in CI.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/ListCore Tests/ListCoreTests
git commit -m ":sparkles: feat(ListCore): new pure module skeleton + Package wiring"
```

---

## Task 2: `resolveSelection` (pure) + delegate `ThemedList.setSelection`

**Files:**
- Create: `Sources/ListCore/ListSelection.swift`
- Create: `Tests/ListCoreTests/ListSelectionTests.swift`
- Modify: `Sources/ThemeKit/ThemedList.swift` (`setSelection`, ~line 787)

**Interfaces:**
- Produces: `func resolveSelection(proposed:current:isSelectable:) -> (resolved: String?, didChange: Bool)`
- Consumes (ThemedList): `_selectedID`, `items`, `isSelectable(_:)`.

> Note: `ThemedList.setSelection` does NOT guard `selectionMode` (the `.none` guard lives in `selectRow` line ~874 and `effectiveSelectionIndex` line ~766). So the pure resolver mirrors the resolution at lines 788–790 only — NO mode param (keeps it byte-identical; `selectionMode` stays a `ThemedList` public enum, unmoved).

- [ ] **Step 1: Write the failing test**

`Tests/ListCoreTests/ListSelectionTests.swift`:
```swift
import XCTest
@testable import ListCore

final class ListSelectionTests: XCTestCase {
    // Treat "a", "b" as present+selectable; "x" as absent/non-selectable.
    private func sel(_ id: String) -> Bool { id == "a" || id == "b" }

    func testKeepsSelectableProposed() {
        let r = resolveSelection(proposed: "a", current: nil, isSelectable: sel)
        XCTAssertEqual(r.resolved, "a"); XCTAssertTrue(r.didChange)
    }
    func testRejectsNonSelectable() {
        let r = resolveSelection(proposed: "x", current: nil, isSelectable: sel)
        XCTAssertNil(r.resolved); XCTAssertFalse(r.didChange)
    }
    func testNilProposedClears() {
        let r = resolveSelection(proposed: nil, current: "a", isSelectable: sel)
        XCTAssertNil(r.resolved); XCTAssertTrue(r.didChange)
    }
    func testNoChangeWhenSame() {
        let r = resolveSelection(proposed: "a", current: "a", isSelectable: sel)
        XCTAssertEqual(r.resolved, "a"); XCTAssertFalse(r.didChange)
    }
}
```

- [ ] **Step 2: Build to verify it fails (compiler red)**

Run: `swift build`
Expected: FAIL — `cannot find 'resolveSelection' in scope`.

- [ ] **Step 3: Write the pure implementation**

`Sources/ListCore/ListSelection.swift`:
```swift
import Foundation

/// Resolve a proposed selection id to a committed one, mirroring
/// `ThemedList.setSelection`'s resolution: keep `proposed` iff it is a present,
/// selectable row (the caller encodes "present AND selectable" in `isSelectable`);
/// otherwise nil. `didChange` is `resolved != current`. Pure / Foundation-only.
public func resolveSelection(proposed: String?, current: String?,
                             isSelectable: (String) -> Bool) -> (resolved: String?, didChange: Bool) {
    let resolved = proposed.flatMap { isSelectable($0) ? $0 : nil }
    return (resolved, resolved != current)
}
```

- [ ] **Step 4: Build to verify it passes**

Run: `swift build`
Expected: PASS.

- [ ] **Step 5: Delegate `ThemedList.setSelection` to the core**

In `Sources/ThemeKit/ThemedList.swift`, add `import ListCore` at the top (with the other imports), then replace the resolution head of `setSelection` (currently lines ~787–793):
```swift
    private func setSelection(_ id: String?, fire: Bool) {
        let old = _selectedID
        let (resolved, didChange) = ListCore.resolveSelection(
            proposed: id, current: old,
            isSelectable: { rid in self.items.contains { $0.id == rid && self.isSelectable($0) } })
        guard didChange else { if fire { onSelectionChange?(resolved) }; return }
        _selectedID = resolved
        invalidateRows([indexOf(old), indexOf(resolved)])
        if let i = indexOf(resolved) { scrollRowVisible(i, position: .nearest) }
        if fire { onSelectionChange?(resolved) }
    }
```
(Behavior is identical: same resolved value, same `didChange` guard, same invalidate/scroll/fire. `ListCore.resolveSelection` is fully-qualified for readability; a bare `resolveSelection(…)` also works.)

- [ ] **Step 6: Build**

Run: `swift build`
Expected: PASS. (CI: `ListSelectionTests` + existing `ThemeKitTests` selection tests both green.)

- [ ] **Step 7: Commit**

```bash
git add Sources/ListCore/ListSelection.swift Tests/ListCoreTests/ListSelectionTests.swift Sources/ThemeKit/ThemedList.swift
git commit -m ":recycle: refactor(ListCore/ThemeKit): resolveSelection — ThemedList delegates selection resolution"
```

---

## Task 3: `nextHighlight` (pure) + delegate `ThemedList.moveHighlight`

**Files:**
- Create: `Sources/ListCore/Highlight.swift`
- Create: `Tests/ListCoreTests/HighlightTests.swift`
- Modify: `Sources/ThemeKit/ThemedList.swift` (`moveHighlight`, ~line 1004)

**Interfaces:**
- Produces: `func nextHighlight(current:delta:selectableIndices:wraps:) -> Int?`
- Consumes (ThemedList): `highlightedIndex`, `items`, `isSelectable(_:)`, `wrapsHighlight`, `isDragging`, `isActionRowActive`, `setHighlight(_:)`, `scrollRowVisible(_:position:)`.

- [ ] **Step 1: Write the failing test**

`Tests/ListCoreTests/HighlightTests.swift` (integer math → binary-exact, no float-boundary trap):
```swift
import XCTest
@testable import ListCore

final class HighlightTests: XCTestCase {
    let sel = [0, 2, 3]   // index 1 is non-selectable (header/disabled)

    func testEmptyReturnsNil() {
        XCTAssertNil(nextHighlight(current: nil, delta: 1, selectableIndices: [], wraps: true))
    }
    func testNoCurrentForwardPicksFirst() {
        XCTAssertEqual(nextHighlight(current: nil, delta: 1, selectableIndices: sel, wraps: false), 0)
    }
    func testNoCurrentBackwardPicksLast() {
        XCTAssertEqual(nextHighlight(current: nil, delta: -1, selectableIndices: sel, wraps: false), 3)
    }
    func testForwardSkipsNonSelectable() {
        XCTAssertEqual(nextHighlight(current: 0, delta: 1, selectableIndices: sel, wraps: false), 2)
    }
    func testClampAtEnd() {
        XCTAssertEqual(nextHighlight(current: 3, delta: 1, selectableIndices: sel, wraps: false), 3)
    }
    func testWrapPastEnd() {
        XCTAssertEqual(nextHighlight(current: 3, delta: 1, selectableIndices: sel, wraps: true), 0)
    }
    func testWrapPastStart() {
        XCTAssertEqual(nextHighlight(current: 0, delta: -1, selectableIndices: sel, wraps: true), 3)
    }
}
```

- [ ] **Step 2: Build to verify it fails**

Run: `swift build`
Expected: FAIL — `cannot find 'nextHighlight' in scope`.

- [ ] **Step 3: Write the pure implementation (verbatim lift of lines 1009–1017)**

`Sources/ListCore/Highlight.swift`:
```swift
import Foundation

/// One roving-highlight step over the selectable indices, mirroring the core math
/// of `ThemedList.moveHighlight`: from the current position move by `delta`,
/// wrapping (`((p+delta)%n+n)%n`) or clamping (`min(max(p+delta,0),n-1)`); an empty
/// list → nil; no current → first (delta>0) or last (delta<0). Pure / Foundation-only.
public func nextHighlight(current: Int?, delta: Int,
                          selectableIndices: [Int], wraps: Bool) -> Int? {
    guard !selectableIndices.isEmpty else { return nil }
    if let cur = current, let pos = selectableIndices.firstIndex(of: cur) {
        let n = selectableIndices.count
        let np = wraps ? ((pos + delta) % n + n) % n
                       : min(max(pos + delta, 0), n - 1)
        return selectableIndices[np]
    } else {
        return delta > 0 ? selectableIndices.first! : selectableIndices.last!
    }
}
```

- [ ] **Step 4: Build to verify it passes**

Run: `swift build`
Expected: PASS.

- [ ] **Step 5: Delegate `ThemedList.moveHighlight` to the core**

Replace `moveHighlight` (currently lines ~1004–1020) — keep the AppKit guards (`isDragging`, `isActionRowActive`) caller-side:
```swift
    public func moveHighlight(_ delta: Int) {
        if isDragging { return }               // a lift replaces highlight nav with drop-target aim (decision e)
        if isActionRowActive { setHighlight(0); return }
        let sel = items.indices.filter { isSelectable(items[$0]) }
        guard let target = ListCore.nextHighlight(current: highlightedIndex, delta: delta,
                                                  selectableIndices: sel, wraps: wrapsHighlight) else {
            setHighlight(nil); return
        }
        setHighlight(target)
        scrollRowVisible(target, position: .nearest)
    }
```
(Identical: empty selectable set → `setHighlight(nil)`; otherwise same target index, same `setHighlight` + `scrollRowVisible`.)

- [ ] **Step 6: Build**

Run: `swift build`
Expected: PASS. (CI: `HighlightTests` + existing `_moveHighlight` seam tests in `ThemeKitTests` both green — the old seam tests stay as integration coverage; the new pure tests are added coverage, not a replacement.)

- [ ] **Step 7: Commit**

```bash
git add Sources/ListCore/Highlight.swift Tests/ListCoreTests/HighlightTests.swift Sources/ThemeKit/ThemedList.swift
git commit -m ":recycle: refactor(ListCore/ThemeKit): nextHighlight — ThemedList delegates roving-highlight math"
```

---

## Task 4: ComboBox pure logic (`comboFilter` + `reconcileSelection`) + delegate

**Files:**
- Create: `Sources/ListCore/ComboLogic.swift`
- Create: `Tests/ListCoreTests/ComboLogicTests.swift`
- Modify: `Sources/ThemeKit/ThemedComboBox.swift` (`defaultFilter` ~247, `optionsChanged` ~279)

**Interfaces:**
- Produces:
  - `func comboFilter<Item>(_ options: [Item], query: String, label: (Item) -> String) -> [Item]`
  - `func reconcileSelection(selectedIndex: Int?, committedValue: String, labels: [String]) -> (selectedIndex: Int?, committedValue: String)`
- Consumes (ComboBox): `Item`, `_selectedIndex`, `committedValue`, `options`.

> The combo `Item` is `{ id, label }` (no NSImage), but to keep the core type-agnostic (and certain it never links AppKit) the filter is generic over a `label` projection.

- [ ] **Step 1: Write the failing test**

`Tests/ListCoreTests/ComboLogicTests.swift`:
```swift
import XCTest
@testable import ListCore

private struct Opt { let id: String; let label: String }

final class ComboLogicTests: XCTestCase {
    let opts = [Opt(id: "1", label: "Apple"), Opt(id: "2", label: "Apricot"), Opt(id: "3", label: "Banana")]

    func testEmptyQueryKeepsAll() {
        XCTAssertEqual(comboFilter(opts, query: "", label: { $0.label }).count, 3)
    }
    func testContainsCaseInsensitive() {
        let r = comboFilter(opts, query: "ap", label: { $0.label })
        XCTAssertEqual(r.map { $0.id }, ["1", "2"])
    }
    func testReconcileKeepsIndexWhenInRange() {
        let r = reconcileSelection(selectedIndex: 2, committedValue: "Banana", labels: ["Apple", "Apricot", "Banana"])
        XCTAssertEqual(r.selectedIndex, 2); XCTAssertEqual(r.committedValue, "Banana")
    }
    func testReconcileRefindsByLabel() {
        let r = reconcileSelection(selectedIndex: nil, committedValue: "Banana", labels: ["Banana", "Apple"])
        XCTAssertEqual(r.selectedIndex, 0); XCTAssertEqual(r.committedValue, "Banana")
    }
    func testReconcileKeepsFreeSoloTarget() {
        let r = reconcileSelection(selectedIndex: nil, committedValue: "Cherry", labels: ["Apple"])
        XCTAssertNil(r.selectedIndex); XCTAssertEqual(r.committedValue, "Cherry")
    }
}
```

- [ ] **Step 2: Build to verify it fails**

Run: `swift build`
Expected: FAIL — `cannot find 'comboFilter' in scope`.

- [ ] **Step 3: Write the pure implementation**

`Sources/ListCore/ComboLogic.swift`:
```swift
import Foundation

/// MUI-style default ComboBox filter: an empty query keeps all; otherwise a
/// case/diacritic-insensitive substring match on the projected label. Generic over
/// `Item` via a `label` projection so the core never links a widget's NSImage.
public func comboFilter<Item>(_ options: [Item], query: String, label: (Item) -> String) -> [Item] {
    guard !query.isEmpty else { return options }
    return options.filter { label($0).localizedStandardContains(query) }
}

/// Reconcile a committed ComboBox selection across an options reload (an index into
/// the old list is meaningless): keep the index if still in range; else re-find by
/// the committed label; else clear the index but KEEP `committedValue` (so a freeSolo
/// revert target survives). Mirrors `ThemedComboBox.optionsChanged`. Pure.
public func reconcileSelection(selectedIndex: Int?, committedValue: String,
                               labels: [String]) -> (selectedIndex: Int?, committedValue: String) {
    if let idx = selectedIndex, labels.indices.contains(idx) {
        return (idx, labels[idx])
    } else if !committedValue.isEmpty, let again = labels.firstIndex(of: committedValue) {
        return (again, committedValue)
    } else {
        return (nil, committedValue)
    }
}
```

- [ ] **Step 4: Build to verify it passes**

Run: `swift build`
Expected: PASS.

- [ ] **Step 5: Delegate ComboBox to the core**

In `Sources/ThemeKit/ThemedComboBox.swift`, add `import ListCore`. Replace `defaultFilter` (lines ~247–250):
```swift
    nonisolated static func defaultFilter(_ options: [Item], _ query: String) -> [Item] {
        comboFilter(options, query: query, label: { $0.label })
    }
```
Replace the reconcile head of `optionsChanged` (lines ~279–291) — keep `refilter()` / `if isOpen { … }` tail:
```swift
    private func optionsChanged() {
        let r = reconcileSelection(selectedIndex: _selectedIndex,
                                   committedValue: committedValue,
                                   labels: options.map { $0.label })
        _selectedIndex = r.selectedIndex
        committedValue = r.committedValue
        refilter()
        if isOpen { syncList(); reframe() }
    }
```
(Identical resolution: same three branches, same freeSolo-survives behavior.)

- [ ] **Step 6: Build**

Run: `swift build`
Expected: PASS. (CI: `ComboLogicTests` + existing ComboBox tests green.)

- [ ] **Step 7: Commit**

```bash
git add Sources/ListCore/ComboLogic.swift Tests/ListCoreTests/ComboLogicTests.swift Sources/ThemeKit/ThemedComboBox.swift
git commit -m ":recycle: refactor(ListCore/ThemeKit): comboFilter + reconcileSelection — ComboBox delegates"
```

---

## Task 5: Menu key routing (`menuKeyIntent`) + delegate `handleKeyDown`

**Files:**
- Create: `Sources/ListCore/MenuLogic.swift`
- Create: `Tests/ListCoreTests/MenuLogicTests.swift`
- Modify: `Sources/ThemeKit/ThemedMenu.swift` (`handleKeyDown`, ~line 553)

**Interfaces:**
- Produces: `enum MenuKeyIntent` + `func menuKeyIntent(keyCode: UInt16) -> MenuKeyIntent`
- Consumes (Menu): `ev.keyCode`, and the existing AppKit-side conditionals (submenu presence, `parentMenu`, `dismiss()`).

- [ ] **Step 1: Write the failing test**

`Tests/ListCoreTests/MenuLogicTests.swift`:
```swift
import XCTest
@testable import ListCore

final class MenuLogicTests: XCTestCase {
    func testArrows() {
        XCTAssertEqual(menuKeyIntent(keyCode: 125), .moveDown)
        XCTAssertEqual(menuKeyIntent(keyCode: 126), .moveUp)
        XCTAssertEqual(menuKeyIntent(keyCode: 124), .openSubmenu)
        XCTAssertEqual(menuKeyIntent(keyCode: 123), .closeLevel)
    }
    func testActivateKeys() {
        for k: UInt16 in [36, 76, 49] { XCTAssertEqual(menuKeyIntent(keyCode: k), .activate) }
    }
    func testEscTabDefault() {
        XCTAssertEqual(menuKeyIntent(keyCode: 53), .escapeLevel)
        XCTAssertEqual(menuKeyIntent(keyCode: 48), .dismissTab)
        XCTAssertEqual(menuKeyIntent(keyCode: 99), .passThrough)
    }
}
```

- [ ] **Step 2: Build to verify it fails**

Run: `swift build`
Expected: FAIL — `cannot find 'menuKeyIntent' in scope`.

- [ ] **Step 3: Write the pure implementation**

`Sources/ListCore/MenuLogic.swift`:
```swift
import Foundation

/// The pure intent a menu derives from a key code. AppKit-side conditionals
/// (does the highlighted row have a submenu? is there a parent level?) and the
/// side effects (open/close/dismiss/activate) stay in `ThemedMenu.handleKeyDown`.
public enum MenuKeyIntent: Sendable, Equatable {
    case moveDown, moveUp, openSubmenu, closeLevel, activate, escapeLevel, dismissTab, passThrough
}

/// Map a macOS virtual key code to a menu intent (mirrors the switch in
/// `ThemedMenu.handleKeyDown`). Pure / Foundation-only.
public func menuKeyIntent(keyCode: UInt16) -> MenuKeyIntent {
    switch keyCode {
    case 125: return .moveDown      // ↓
    case 126: return .moveUp        // ↑
    case 124: return .openSubmenu   // →
    case 123: return .closeLevel    // ←
    case 36, 76, 49: return .activate   // ⏎ / keypad ⏎ / Space
    case 53: return .escapeLevel    // Esc
    case 48: return .dismissTab     // Tab
    default: return .passThrough
    }
}
```

- [ ] **Step 4: Build to verify it passes**

Run: `swift build`
Expected: PASS.

- [ ] **Step 5: Delegate `handleKeyDown` to the core**

In `Sources/ThemeKit/ThemedMenu.swift`, add `import ListCore`. Replace the `switch ev.keyCode` body (lines ~558–578) with a switch over the pure intent — the conditional logic and side effects are unchanged:
```swift
        switch menuKeyIntent(keyCode: ev.keyCode) {
        case .moveDown: leaf.list.moveHighlight(1);  return nil
        case .moveUp:   leaf.list.moveHighlight(-1); return nil
        case .openSubmenu:
            if let id = leaf.list.highlightedID,
               leaf.items.first(where: { $0.id == id })?.submenu.isEmpty == false {
                leaf.openSubmenu(rowID: id, highlightFirst: true)
                return nil
            }
            return ev                                        // no submenu on this row → host keeps → (IME safe)
        case .closeLevel:
            guard let parent = leaf.parentMenu else { return ev }
            parent.closeChild()
            return nil
        case .activate: leaf.list.activateHighlight(); return nil
        case .escapeLevel:
            if let parent = leaf.parentMenu { parent.closeChild() } else { dismiss() }
            return nil
        case .dismissTab: dismiss(); return ev
        case .passThrough: return ev
        }
```
(Identical: every prior `case` maps to exactly one intent with the same body; `default` → `.passThrough` → `return ev`.)

- [ ] **Step 6: Build**

Run: `swift build`
Expected: PASS. (CI: `MenuLogicTests` + existing Menu tests green.)

- [ ] **Step 7: Commit**

```bash
git add Sources/ListCore/MenuLogic.swift Tests/ListCoreTests/MenuLogicTests.swift Sources/ThemeKit/ThemedMenu.swift
git commit -m ":recycle: refactor(ListCore/ThemeKit): menuKeyIntent — ThemedMenu delegates key routing"
```

---

## Task 6: controlled/uncontrolled seam — firing setters

**Files:**
- Modify: `Sources/ThemeKit/ThemedCheckbox.swift` (add `setChecked`, near `toggle` ~280)
- Modify: `Sources/ThemeKit/ThemedComboBox.swift` (add `commitSelection`, near `commitItem` ~435)
- Modify: `Sources/ThemeKit/ThemedTextField.swift` (add `setText`, generalize `clearText` ~122)

**Interfaces:**
- Produces (public firing doors, mirroring `List.selectRow` vs `selectedID=`):
  - `ThemedCheckbox.setChecked(_ checked: Bool, notifying: Bool)`
  - `ThemedComboBox.commitSelection(_ index: Int?)`
  - `ThemedTextField.setText(_ text: String, notifying: Bool)`

> No XCTest red/green via compiler here (these are widget-level, AppKit, CI-only). Verification is `swift build` + the byte-identical reasoning below; CI exercises them through existing widget tests, and Task 7 adds a11y posts at these same sites.

- [ ] **Step 1: Checkbox — add `setChecked(_:notifying:)`**

After `toggle(fromUser:)` in `Sources/ThemeKit/ThemedCheckbox.swift`:
```swift
    /// Programmatic set with an EXPLICIT notify choice — the firing counterpart of
    /// assigning `isChecked` (silent). `notifying: true` fires `onChange` +
    /// target/action exactly like a user toggle; the host may re-drive the value
    /// from inside `onChange` (controlled component). Clears any indeterminate state.
    public func setChecked(_ checked: Bool, notifying: Bool) {
        guard isEnabled else { return }
        isIndeterminate = false
        isChecked = checked            // silent didSet (syncAccessibility + applyState)
        if notifying { onChange?(checked); sendActionToTarget() }
    }
```

- [ ] **Step 2: ComboBox — add `commitSelection(_:)`**

After `commitItem(_:)` in `Sources/ThemeKit/ThemedComboBox.swift` (uses the existing silent internal `setSelection(_ idx: Int?)` + `selectedItem`, firing `onSelect` like `commitItem` but without the popup/focus theatrics that only make sense for a user pick):
```swift
    /// Programmatic commit that FIRES `onSelect` — the firing counterpart of
    /// assigning `selectedIndex` (silent). An out-of-range / nil index clears the
    /// selection and fires `onSelect(nil)`. (User picks still route through
    /// `commitItem`, which also dismisses the popup and re-asserts field focus.)
    public func commitSelection(_ index: Int?) {
        if let index, options.indices.contains(index) {
            setSelection(index)          // silent: sets _selectedIndex + committedValue + field text
            onSelect?(selectedItem)
        } else {
            setSelection(nil)
            onSelect?(nil)
        }
    }
```

- [ ] **Step 3: TextField — add `setText(_:notifying:)`, route `clearText` through it**

In `Sources/ThemeKit/ThemedTextField.swift`, replace `clearText` (line ~122) and add `setText`:
```swift
    /// Programmatic set with an EXPLICIT notify choice — the firing counterpart of
    /// assigning `stringValue` (silent). `notifying: true` fires `onChange` (so a
    /// bound search list refreshes), matching the old `clearText` discipline; the
    /// silent branch mirrors the `stringValue` setter (`syncFloat`).
    public func setText(_ text: String, notifying: Bool) {
        field.stringValue = text
        if notifying { textChanged() } else { syncFloat(animated: false) }
    }

    /// Clear the field AS IF the user deleted all text — fires `onChange("")`.
    public func clearText() { setText("", notifying: true) }
```
(Byte-identical: `setText("", notifying: true)` == the old `field.stringValue = ""; textChanged()`; the silent branch == the public `stringValue` setter.)

- [ ] **Step 4: Build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ThemeKit/ThemedCheckbox.swift Sources/ThemeKit/ThemedComboBox.swift Sources/ThemeKit/ThemedTextField.swift
git commit -m ":sparkles: feat(ThemeKit): controlled/uncontrolled seam — firing setters (setChecked/commitSelection/setText)"
```

---

## Task 7: a11y P0/P1 — post helper + value attrs at committed-change sites

> **MAINTAINER VERIFY GATE:** this task changes the accessibility tree (additively). Agents cannot drive VoiceOver and prism cannot show AX. After `swift build` + CI green, the maintainer verifies with VoiceOver (Checkbox toggle announces, Chip select announces, ComboBox commit announces, List selection announces). Treat an agent "works" claim as unverified until that gate ([[chomp-push-gate]] shape).

**Files:**
- Modify: `Sources/ThemeKit/Shared.swift` (add helper)
- Modify: `ThemedCheckbox.swift`, `ThemedChip.swift`, `ThemedComboBox.swift`, `ThemedList.swift`, `ThemedButtonGroup.swift`

**Interfaces:**
- Produces: `NSView.postAXValueChanged()` (and value-attr fills on stateful widgets).

- [ ] **Step 1: Add the post helper**

In `Sources/ThemeKit/Shared.swift`:
```swift
import AppKit

extension NSView {
    /// Announce a COMMITTED value/selection change to assistive tech (VoiceOver).
    /// Call ONLY at firing-door sites (user-intent / `notifying:` setters) — NEVER
    /// on every transient highlight, hover, or keystroke (that floods VoiceOver).
    func postAXValueChanged() { NSAccessibility.post(element: self, notification: .valueChanged) }
}
```

- [ ] **Step 2: Checkbox — post on committed toggle/set**

In `ThemedCheckbox.toggle(fromUser:)`, inside the `if fromUser { … }` block (after `sendActionToTarget()`), add `postAXValueChanged()`. In `setChecked(_:notifying:)` (Task 6), inside `if notifying { … }`, add `postAXValueChanged()`. (Value attr already set tri-state in `syncAccessibility`.)

- [ ] **Step 3: Chip — value attr + post**

In `ThemedChip`, in its accessibility sync, add `setAccessibilityValue(isSelected ? 1 : 0)` (the Chip exposes `isSelected`). At the user-tap commit site (`onTap`/selection toggle), call `postAXValueChanged()`.

- [ ] **Step 4: ComboBox — value attr on the field + post on commit**

In `ThemedComboBox`, set the field's accessibility value to `selectedItem?.label` when a selection commits. Add `field.postAXValueChanged()` in `commitItem`, `commitFreeText`, `clear`, and `commitSelection` (the committed-change sites). (ComboBox is an `NSObject`; post on `field`, an `NSView`.)

- [ ] **Step 5: List — value attr + post on selection change**

In `ThemedList`, in the firing branch of `setSelection` (the `if fire { onSelectionChange?(resolved) }` site), add `postAXValueChanged()` (List is an `NSView`). Expose the selected row id as the list's accessibility value (`setAccessibilityValue(_selectedID)`), keeping the existing per-row `RowAXElement` labels (promoting the folded `, checked` label to a real row value attr is P2 — OUT of focused scope).

- [ ] **Step 6: ButtonGroup — value attr + post on segment change**

In `ThemedButtonGroup`, set `setAccessibilityValue(selectedIndex)` and call `postAXValueChanged()` at the user-driven segment-change site.

> TextField: the inner `NSTextField` already exposes its value to VoiceOver natively and VO announces typing — do NOT add a per-keystroke post (flood). Only verify the `ThemedTextField` wrapper doesn't shadow the inner field's AX value; if it does, forward it. (Maintainer VO-verifies.)

- [ ] **Step 7: Build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/ThemeKit/Shared.swift Sources/ThemeKit/ThemedCheckbox.swift Sources/ThemeKit/ThemedChip.swift Sources/ThemeKit/ThemedComboBox.swift Sources/ThemeKit/ThemedList.swift Sources/ThemeKit/ThemedButtonGroup.swift
git commit -m ":sparkles: feat(ThemeKit): a11y P0/P1 — NSAccessibility.post helper + value attrs at committed-change sites"
```

---

## Task 8: Extend the "Adding a widget" checklist (DESIGN.md)

**Files:**
- Modify: `docs/DESIGN.md` (`### Adding a widget`, ~line 506)

- [ ] **Step 1: Append the checklist**

After the existing `### Adding a widget` paragraph (which covers rule-of-three + the prism mandate + `preview…`), add:
```markdown

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
  and tomorrow's SwiftUI view (#16/#17) share one tested core.
```

- [ ] **Step 2: Commit**

```bash
git add docs/DESIGN.md
git commit -m ":memo: docs(DESIGN): extend 'Adding a widget' — a11y contract + seam + pure-core checklist"
```

---

## Final verification (whole-branch, before PR)

- [ ] `swift build` green on the branch (local gate).
- [ ] Push; confirm **CI green** — `swift test` (full Xcode): new `ListCoreTests` (selection/highlight/combo/menu) + existing `ThemeKitTests` (byte-identical regression net) + lint all pass. Per [[sweep-include-tests]], the existing `_moveHighlight`/seam tests in `ThemeKitTests` stay and must remain green (they prove the delegation is byte-identical).
- [ ] **Adversarial review** (the #14a/#14b pattern): multiple independent skeptics verify (1) each pure extraction is byte-identical to the prior inline logic, (2) no `ListItem`/NSImage leaked into `ListCore`, (3) the dependency graph stays acyclic and `ListCore` links zero AppKit, (4) a11y posts fire only at committed-change sites (no flood), (5) public APIs of all five widgets are unchanged. Target: confirmed-defect 0.
- [ ] **Maintainer gates (agent cannot do these):** VoiceOver verification of Task 7 (announcements on Checkbox/Chip/ComboBox/List/ButtonGroup commits); a quick prism pass to confirm NO visual/behavioral drift (focused scope is visually invisible).
- [ ] Mark `docs/ROADMAP.md` **#15 着手中: PR #N** when the PR opens; flip to 完了 + **minor `v`-tag** at merge (confirm the version isn't already claimed — [[parallel-work-hazard]]).

---

## Self-Review (against the spec)

- **Spec coverage:** §2 module/graph → Task 1. §3(A) resolveSelection → Task 2. §3(B) nextHighlight → Task 3. §3(C) comboFilter/reconcile → Task 4. §3(D) menuKeyIntent → Task 5. §4 seam firing doors → Task 6. §5 a11y P0/P1 → Task 7. §6 checklist → Task 8. §7 verification → Final verification. §1 OUT items (typeAheadMatch / DnD core / max a11y / `.multiple`) — correctly absent from all tasks.
- **Deviation from spec (noted):** spec §3(A) sketched `resolveSelection(… mode:)` + a `ListSelection.Mode`. The real `ThemedList.setSelection` does NOT guard `selectionMode` (the `.none` guard lives in `selectRow`/`effectiveSelectionIndex`), so the byte-identical core drops the `mode` param and `ListSelection` struct (YAGNI — `ThemedList.SelectionMode` stays a public enum, unmoved). This is a simplification consistent with the byte-identical + YAGNI principles the user approved; no behavior change.
- **Placeholder scan:** no TBD/TODO; every code step shows complete code; the a11y per-widget steps name the exact method/site + the one call to add (the implementer reads the current accessibility code in the worktree — line numbers are snapshots per Global Constraints).
- **Type consistency:** `resolveSelection`/`nextHighlight`/`comboFilter`/`reconcileSelection`/`menuKeyIntent`/`MenuKeyIntent`/`postAXValueChanged`/`setChecked`/`commitSelection`/`setText` are used with identical signatures in their producing task and every consuming site.
