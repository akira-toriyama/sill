# #17b Milestone 1 — ListCore Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grow the pure `ListCore` module with the row model, multi-select, section-collapse, and the drag/sticky geometry cores (moved out of the AppKit `ThemedList`), so later milestones' SwiftUI `ThemedListView` and the Combo/Menu hosts share one tested brain — without changing any visible behavior.

**Architecture:** `ListCore` stays Foundation-only + Sendable; it gains a pure generic `ListRow<ID>` row model, pure multi-select / collapse resolvers, and the relocated drag-target / chunk / sticky-header geometry (rewritten as pure functions taking explicit `[ListRow]` + `[RowGeom]` parameters). The AppKit `ThemedList` (slated for deletion in Milestone 5) keeps compiling unchanged: its private DnD/sticky methods become thin forwarders that build the parameter arrays from the widget's internal state and call into `ListCore`, and `String` typealiases re-vend the now-generic DnD vocabulary under their old unqualified names. New behavior is locked by `ListCoreTests` (XCTest, CI); the existing `ThemedListTests` keep passing through the forwarders.

**Tech Stack:** Swift 6 / SwiftPM. `ListCore` = Foundation (+ CoreGraphics behind `#if`). Tests = XCTest. The maintainer's machine is CLT-only (no Xcode) → **`swift build` is the local gate; `swift test` runs only in CI** (`.github/workflows/build.yml`, full Xcode). Treat every "run test" step as: locally confirm it COMPILES via `swift build`; the assertion pass/fail is observed in CI (or on a full-Xcode machine).

## Global Constraints

- **macOS floor stays `.macOS(.v13)` for this milestone — DO NOT bump to macOS 26 yet.** Milestone 1 is pure Foundation/CoreGraphics, macOS-13-compatible, and runs on the current CLT (SDK 15.5). The macOS-26 floor bump + toolchain upgrade is Milestone 0, required only before Milestone 2 (the SwiftUI view). Keeping the floor at 13 here means M1 builds locally today.
- **`ListCore` is Foundation-only + Sendable.** No `import AppKit`, no `NSImage`, no `NSView`. CoreGraphics-typed code (`CGFloat`/`CGRect`) goes behind `#if canImport(CoreGraphics)` (existing house convention, `Sources/ListCore/ListCore.swift:6`).
- **All new ListCore types are generic over `ID: Hashable & Sendable`.** The AppKit widget is `String`-keyed, so `ThemeKit` adds `String` typealiases (`typealias DropTarget = ListCore.DropTarget<String>`, etc.) to keep its call sites unchanged.
- **No behavior change.** This milestone is a pure refactor/extraction. The existing `ThemedListTests` (via forwarders) are the regression oracle and must stay green; new `ListCoreTests` lock the extracted pure functions.
- **Commits:** gitmoji + Conventional Commits (`commit-lint`), English subject & body, e.g. `:recycle: refactor(ListCore): …`. `refactor`/`test`/`chore` ⇒ no version bump (no tag this milestone; the version bump + tag land at the #17b retire milestone).
- **Selectable definition (canonical):** a row is selectable iff `!isHeader && !isSeparator && !isDisabled`. A collapsible header is togglable iff `isHeader && !isDisabled && headerCollapsed != nil`. These mirror `ThemedList`'s `ListItem` derived flags (`Sources/ThemeKit/ThemedList.swift:133-141`).

---

## File Structure

**New files (all in `Sources/ListCore/`):**
- `ListRow.swift` — generic `RowKind` + `ListRow<ID>` value model + derived flags. The pure shadow of `ThemeKit`'s `ListItem`.
- `MultiSelection.swift` — `SelectMods` OptionSet + `resolveClick` / `extendByKey` / `selectAll` / `rangeIDs`.
- `SectionCollapse.swift` — `toggleSection` / `flattenVisible`.
- `ListDnD.swift` — `DragMode` / `DropPlacement<ID>` / `DragContext<ID>` / `DropTarget<ID>` vocabulary (moved from `ThemeKit`) + `RowGeom` + the pure geometry fns `rowIndex` / `resolveDropTarget` / `dragCandidates` / `chunkMemberIDs` (+ private helpers `validatedTarget` / `isTrivialSelfDrop` / `isInsideChunk` / `nextRowID`).
- `StickyHeader.swift` — `stickyHeader(atVisibleTop:headerIndices:yOffsets:heights:)`.

**New test files (all in `Tests/ListCoreTests/`):**
- `ListRowTests.swift`, `MultiSelectionTests.swift`, `SectionCollapseTests.swift`, `ListDnDTests.swift`, `StickyHeaderTests.swift`.

**Modified files (`Sources/ThemeKit/ThemedList.swift`):**
- Delete the DnD vocabulary definitions (`:155-197`); add `String` typealiases.
- Rewrite the private geometry methods (`resolveDropTarget` `:1783`, `validatedTarget` `:1817`, `isTrivialSelfDrop` `:1829`, `isInsideChunk` `:1846`, `dragCandidates` `:1870`, `chunkMemberIDs` `:1913`, `stickyHeader` `:1083`) as forwarders into `ListCore`, plus a private `asRow`/`rowGeom` projection. The test seams (`_resolveDropTarget` `:2460`, `_dragCandidates` `:2469`, `_chunkMemberIDs` `:2471`, `_stickyHeader` `:2423`, `_isInsideChunk` `:2474`, `dragProbe` `:2453`) are untouched — they keep calling the (now-forwarding) private methods.

**Deferred to later milestones (NOT in M1):** `Measurement.swift` (`contentHeight` is pure but only the popup hosts need it → Milestone 3; `fittingWidth` measures text with `NSFont` and is **not** pure, so it stays in the view layer). The `image`-bearing `ListItem` + its `asRow` projection as a PUBLIC type lives in `ThemeKitUI` and is built in Milestone 2; M1's `asRow` projection is a private helper inside the AppKit widget only.

---

### Task 1: `ListRow<ID>` pure row model

**Files:**
- Create: `Sources/ListCore/ListRow.swift`
- Test: `Tests/ListCoreTests/ListRowTests.swift`

**Interfaces:**
- Consumes: nothing (pure leaf).
- Produces: `RowKind` (enum: `.row` / `.sectionHeader(subtitle:collapsed:)` / `.separator`); `ListRow<ID: Hashable & Sendable>` with stored `id: ID`, `kind: RowKind`, `isDisabled: Bool`, `indentLevel: Int`, and derived `isHeader` / `isSeparator` / `headerSubtitle: String?` / `headerCollapsed: Bool?` / `isCollapsibleHeader: Bool` / `isSelectable: Bool`. Used by Tasks 3, 4 and (later) Milestone 2's `ListItem.asRow`.

- [ ] **Step 1: Write the failing test**

`Tests/ListCoreTests/ListRowTests.swift`:
```swift
import XCTest
@testable import ListCore

final class ListRowTests: XCTestCase {
    func testDerivedFlags() {
        let row = ListRow(id: "r", kind: .row)
        XCTAssertTrue(row.isSelectable)
        XCTAssertFalse(row.isHeader); XCTAssertFalse(row.isSeparator)

        let sep = ListRow(id: "s", kind: .separator)
        XCTAssertTrue(sep.isSeparator); XCTAssertFalse(sep.isSelectable)

        let plainHeader = ListRow(id: "h", kind: .sectionHeader(subtitle: "sub", collapsed: nil))
        XCTAssertTrue(plainHeader.isHeader)
        XCTAssertEqual(plainHeader.headerSubtitle, "sub")
        XCTAssertNil(plainHeader.headerCollapsed)
        XCTAssertFalse(plainHeader.isCollapsibleHeader, "collapsed: nil ⇒ not togglable")
        XCTAssertFalse(plainHeader.isSelectable, "a header is never selectable")

        let collapsible = ListRow(id: "h2", kind: .sectionHeader(collapsed: false))
        XCTAssertTrue(collapsible.isCollapsibleHeader)
        XCTAssertEqual(collapsible.headerCollapsed, false)

        let disabledRow = ListRow(id: "d", kind: .row, isDisabled: true)
        XCTAssertFalse(disabledRow.isSelectable, "disabled ⇒ not selectable")
        let disabledHeader = ListRow(id: "dh", kind: .sectionHeader(collapsed: true), isDisabled: true)
        XCTAssertFalse(disabledHeader.isCollapsibleHeader, "disabled ⇒ not togglable")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift build` (local gate) then in CI: `swift test --filter ListRowTests`
Expected: compile FAIL — `cannot find 'ListRow' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/ListCore/ListRow.swift`:
```swift
import Foundation

/// The kind of a list row — the pure shadow of `ThemeKit.ListItem.Kind`. Carries no
/// `ID` (a header/separator's identity lives on `ListRow.id`).
public enum RowKind: Equatable, Sendable {
    case row
    /// A group label (1-line, or 2-line with `subtitle`). `collapsed`: `nil` ⇒ plain
    /// non-interactive header; `false` ⇒ collapsible + expanded (▾); `true` ⇒ collapsed (▸).
    case sectionHeader(subtitle: String? = nil, collapsed: Bool? = nil)
    /// A non-interactive thin rule between groups; skipped by nav / hover / activation.
    case separator
}

/// The pure, Sendable shadow of a `ThemedList` row used by every `ListCore` resolver,
/// so the cores never link an `NSImage`. `ThemeKit`/`ThemeKitUI`'s image-bearing item
/// projects to this via `asRow`. Generic over `ID` (the AppKit widget is `String`-keyed).
public struct ListRow<ID: Hashable & Sendable>: Hashable, Sendable {
    public let id: ID
    public let kind: RowKind
    public let isDisabled: Bool
    /// Visual nesting depth (0 = top level). The kit only uses it to know tree shape;
    /// the host owns which rows are children.
    public let indentLevel: Int

    public init(id: ID, kind: RowKind = .row, isDisabled: Bool = false, indentLevel: Int = 0) {
        self.id = id; self.kind = kind; self.isDisabled = isDisabled; self.indentLevel = indentLevel
    }

    public var isHeader: Bool { if case .sectionHeader = kind { return true }; return false }
    public var isSeparator: Bool { if case .separator = kind { return true }; return false }
    public var headerSubtitle: String? { if case let .sectionHeader(s, _) = kind { return s }; return nil }
    public var headerCollapsed: Bool? { if case let .sectionHeader(_, c) = kind { return c }; return nil }
    /// A header the user can toggle: collapsible (its `collapsed` flag is non-nil) and not disabled.
    public var isCollapsibleHeader: Bool { isHeader && !isDisabled && headerCollapsed != nil }
    /// Eligible for selection / roving highlight: an enabled, non-header, non-separator row.
    public var isSelectable: Bool { !isHeader && !isSeparator && !isDisabled }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift build`; CI: `swift test --filter ListRowTests`
Expected: build OK; tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ListCore/ListRow.swift Tests/ListCoreTests/ListRowTests.swift
git commit -m ":sparkles: feat(ListCore): add pure generic ListRow row model"
```

---

### Task 2: Multi-select resolvers

**Files:**
- Create: `Sources/ListCore/MultiSelection.swift`
- Test: `Tests/ListCoreTests/MultiSelectionTests.swift`

**Interfaces:**
- Consumes: `nextHighlight` (existing, `Sources/ListCore/Highlight.swift:7`).
- Produces: `SelectMods` (OptionSet `{ .command, .shift }`); `resolveClick(id:current:anchor:mods:selectable:) -> (selection: Set<ID>, anchor: ID?)`; `extendByKey(current:anchor:focus:delta:selectable:shiftHeld:wraps:) -> (selection: Set<ID>, anchor: ID?, focus: ID?)`; `selectAll(selectable:) -> Set<ID>`; `rangeIDs(from:to:in:) -> [ID]`. `selectable` is always the ordered list of selectable ids (caller filters out headers/separators/disabled). Used by Milestone 2's standalone list.

- [ ] **Step 1: Write the failing test**

`Tests/ListCoreTests/MultiSelectionTests.swift`:
```swift
import XCTest
@testable import ListCore

final class MultiSelectionTests: XCTestCase {
    let sel = ["a", "b", "c", "d"]   // ordered selectable ids (headers/separators pre-filtered by caller)

    func testPlainClickReplaces() {
        let r = resolveClick(id: "c", current: ["a", "b"], anchor: "a", mods: [], selectable: sel)
        XCTAssertEqual(r.selection, ["c"]); XCTAssertEqual(r.anchor, "c")
    }
    func testCommandTogglesAndMovesAnchor() {
        let add = resolveClick(id: "c", current: ["a"], anchor: "a", mods: .command, selectable: sel)
        XCTAssertEqual(add.selection, ["a", "c"]); XCTAssertEqual(add.anchor, "c")
        let remove = resolveClick(id: "a", current: ["a", "c"], anchor: "c", mods: .command, selectable: sel)
        XCTAssertEqual(remove.selection, ["c"], "cmd-click an already-selected id removes it")
    }
    func testShiftSelectsAnchorRangeInclusive() {
        let r = resolveClick(id: "d", current: ["b"], anchor: "b", mods: .shift, selectable: sel)
        XCTAssertEqual(r.selection, ["b", "c", "d"]); XCTAssertEqual(r.anchor, "b", "shift keeps the anchor")
    }
    func testShiftWithNoAnchorFallsBackToSingle() {
        let r = resolveClick(id: "c", current: [], anchor: nil, mods: .shift, selectable: sel)
        XCTAssertEqual(r.selection, ["c"]); XCTAssertEqual(r.anchor, "c")
    }
    func testRangeIDsOrderIndependent() {
        XCTAssertEqual(rangeIDs(from: "d", to: "b", in: sel), ["b", "c", "d"])
        XCTAssertEqual(rangeIDs(from: "b", to: "b", in: sel), ["b"])
        XCTAssertEqual(rangeIDs(from: "x", to: "b", in: sel), [], "an unknown endpoint ⇒ empty")
    }
    func testExtendByKeyGrowsFromAnchor() {
        let r = extendByKey(current: ["b"], anchor: "b", focus: "b", delta: 1,
                            selectable: sel, shiftHeld: true, wraps: false)
        XCTAssertEqual(r.focus, "c"); XCTAssertEqual(r.selection, ["b", "c"]); XCTAssertEqual(r.anchor, "b")
    }
    func testExtendByKeyNoShiftMovesFocusAndCollapsesSelection() {
        let r = extendByKey(current: ["b", "c"], anchor: "b", focus: "c", delta: 1,
                            selectable: sel, shiftHeld: false, wraps: false)
        XCTAssertEqual(r.focus, "d"); XCTAssertEqual(r.selection, ["d"]); XCTAssertEqual(r.anchor, "d")
    }
    func testSelectAll() { XCTAssertEqual(selectAll(selectable: sel), Set(sel)) }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift build`; CI: `swift test --filter MultiSelectionTests`
Expected: compile FAIL — `cannot find 'resolveClick' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/ListCore/MultiSelection.swift`:
```swift
import Foundation

/// Pure modifier flags for a multi-select click — NOT `NSEvent.ModifierFlags` (the host
/// maps the platform flags onto this). `.command` toggles one row; `.shift` selects the
/// anchor→clicked range.
public struct SelectMods: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = SelectMods(rawValue: 1 << 0)
    public static let shift   = SelectMods(rawValue: 1 << 1)
}

/// The inclusive id range between two endpoints in the ordered `selectable` list,
/// order-independent. Empty if either endpoint is absent.
public func rangeIDs<ID: Hashable>(from: ID, to: ID, in selectable: [ID]) -> [ID] {
    guard let a = selectable.firstIndex(of: from), let b = selectable.firstIndex(of: to) else { return [] }
    let lo = min(a, b), hi = max(a, b)
    return Array(selectable[lo...hi])
}

/// Resolve a row click into the new multi-selection + anchor, mirroring Finder/MUI:
///  * plain    — replace the selection with `{id}`, anchor = `id`.
///  * `.command` — toggle `id` in/out; anchor = `id`.
///  * `.shift`  — select the inclusive anchor→`id` range (anchor unchanged); with no
///                anchor it degrades to a plain click.
/// `selectable` is the ordered selectable-only id list (caller filters headers/separators/disabled).
public func resolveClick<ID: Hashable>(id: ID, current: Set<ID>, anchor: ID?,
                                       mods: SelectMods, selectable: [ID]) -> (selection: Set<ID>, anchor: ID?) {
    guard selectable.contains(id) else { return (current, anchor) }
    if mods.contains(.shift), let anchor, selectable.contains(anchor) {
        return (Set(rangeIDs(from: anchor, to: id, in: selectable)), anchor)
    }
    if mods.contains(.command) {
        var next = current
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        return (next, id)
    }
    return ([id], id)
}

/// Keyboard move of the focus row by `delta` over `selectable` (reusing `nextHighlight`):
/// with `shiftHeld` the selection grows to the inclusive anchor→focus range; without it
/// the focus moves and the selection collapses to the new focus (anchor follows).
public func extendByKey<ID: Hashable>(current: Set<ID>, anchor: ID?, focus: ID?, delta: Int,
                                      selectable: [ID], shiftHeld: Bool, wraps: Bool)
    -> (selection: Set<ID>, anchor: ID?, focus: ID?) {
    let curIdx = focus.flatMap { selectable.firstIndex(of: $0) }
    guard let nextIdx = nextHighlight(current: curIdx, delta: delta,
                                      selectableIndices: Array(selectable.indices), wraps: wraps) else {
        return (current, anchor, focus)
    }
    let newFocus = selectable[nextIdx]
    if shiftHeld {
        let a = anchor ?? focus ?? newFocus
        return (Set(rangeIDs(from: a, to: newFocus, in: selectable)), a, newFocus)
    }
    return ([newFocus], newFocus, newFocus)
}

/// Select every selectable row (⌘A).
public func selectAll<ID: Hashable>(selectable: [ID]) -> Set<ID> { Set(selectable) }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift build`; CI: `swift test --filter MultiSelectionTests`
Expected: build OK; tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ListCore/MultiSelection.swift Tests/ListCoreTests/MultiSelectionTests.swift
git commit -m ":sparkles: feat(ListCore): add pure multi-select resolvers (anchor/shift/cmd range)"
```

---

### Task 3: Section-collapse helpers

**Files:**
- Create: `Sources/ListCore/SectionCollapse.swift`
- Test: `Tests/ListCoreTests/SectionCollapseTests.swift`

**Interfaces:**
- Consumes: `ListRow<ID>` (Task 1).
- Produces: `toggleSection(_:in:) -> Set<ID>`; `flattenVisible(rows:collapsed:) -> [ListRow<ID>]` — the single source of "visible rows" for both the renderer (Milestone 2) and the DnD/chunk cores. A collapsed section drops every row after its header up to (not including) the next header.

- [ ] **Step 1: Write the failing test**

`Tests/ListCoreTests/SectionCollapseTests.swift`:
```swift
import XCTest
@testable import ListCore

final class SectionCollapseTests: XCTestCase {
    func rows() -> [ListRow<String>] {[
        ListRow(id: "A", kind: .sectionHeader(collapsed: false)),
        ListRow(id: "a1"), ListRow(id: "a2"),
        ListRow(id: "B", kind: .sectionHeader(collapsed: false)),
        ListRow(id: "b1"),
    ]}
    func testToggleAddsAndRemoves() {
        XCTAssertEqual(toggleSection("A", in: []), ["A"])
        XCTAssertEqual(toggleSection("A", in: ["A"]), [])
    }
    func testFlattenDropsCollapsedSectionBodyKeepingItsHeader() {
        let visible = flattenVisible(rows: rows(), collapsed: ["A"]).map(\.id)
        XCTAssertEqual(visible, ["A", "B", "b1"], "A's header stays; a1/a2 hidden; B intact")
    }
    func testFlattenAllExpandedIsIdentity() {
        XCTAssertEqual(flattenVisible(rows: rows(), collapsed: []).map(\.id), ["A", "a1", "a2", "B", "b1"])
    }
    func testCollapsingBothSectionsLeavesHeadersOnly() {
        XCTAssertEqual(flattenVisible(rows: rows(), collapsed: ["A", "B"]).map(\.id), ["A", "B"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift build`; CI: `swift test --filter SectionCollapseTests`
Expected: compile FAIL — `cannot find 'toggleSection' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/ListCore/SectionCollapse.swift`:
```swift
import Foundation

/// Toggle a section header's collapsed state in the host-owned `collapsed` set.
public func toggleSection<ID: Hashable>(_ id: ID, in collapsed: Set<ID>) -> Set<ID> {
    var next = collapsed
    if next.contains(id) { next.remove(id) } else { next.insert(id) }
    return next
}

/// The visible rows given a host-owned `collapsed` set: a collapsed header keeps the
/// header itself but drops every row after it up to (not including) the next header.
/// The single source of "visible" for the renderer AND the DnD/chunk/sticky cores, so
/// they never disagree about which rows exist.
public func flattenVisible<ID: Hashable>(rows: [ListRow<ID>], collapsed: Set<ID>) -> [ListRow<ID>] {
    var out: [ListRow<ID>] = []
    var skipping = false
    for row in rows {
        if row.isHeader {
            out.append(row)
            skipping = collapsed.contains(row.id)
        } else if !skipping {
            out.append(row)
        }
    }
    return out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift build`; CI: `swift test --filter SectionCollapseTests`
Expected: build OK; tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ListCore/SectionCollapse.swift Tests/ListCoreTests/SectionCollapseTests.swift
git commit -m ":sparkles: feat(ListCore): add pure section collapse/flatten helpers"
```

---

### Task 4: Move the DnD vocabulary + drop-target / chunk geometry into ListCore

**Files:**
- Create: `Sources/ListCore/ListDnD.swift`
- Modify: `Sources/ThemeKit/ThemedList.swift` (delete vocab `:155-197`; add typealiases; rewrite `:1783-1922` as forwarders + add a private projection)
- Test: `Tests/ListCoreTests/ListDnDTests.swift`

**Interfaces:**
- Consumes: `ListRow<ID>` (Task 1).
- Produces: `DragMode` (unchanged enum); `DropPlacement<ID>` (`.onto(id:)`/`.between(beforeID:)`); `DragContext<ID>`; `DropTarget<ID>`; `RowGeom` (`yOffset`/`height`); `rowIndex(atDocY:geom:) -> Int?`; `resolveDropTarget(atDocY:source:rows:geom:mode:chunkIDs:validate:) -> DropTarget<ID>?`; `dragCandidates(source:rows:mode:chunkIDs:validate:) -> [DropTarget<ID>]`; `chunkMemberIDs(forHeader:rows:) -> [ID]`. Used by Milestone 2 (drag) and the AppKit forwarders.

- [ ] **Step 1: Write the failing test**

`Tests/ListCoreTests/ListDnDTests.swift` — port the docY-based oracle from `ThemedListTests.swift:484-539` (`testReorderBetweenZoneModel`, `testSeparatorIsNotADropTarget`, the `.both` zone cases) and the chunk oracle (`:660-682`, `:720-733`), now driving the pure fns with explicit `[ListRow]` + `[RowGeom]` (comfortable density = 30pt rows, matching the AppKit fixtures the originals use):
```swift
import XCTest
@testable import ListCore

final class ListDnDTests: XCTestCase {
    // 4 single rows a,b,c,d at 30pt each ⇒ yOffsets 0,30,60,90.
    let rows: [ListRow<String>] = ["a","b","c","d"].map { ListRow(id: $0) }
    let geom: [RowGeom] = (0..<4).map { RowGeom(yOffset: CGFloat($0)*30, height: 30) }
    let yes: (DragContext<String>, DropTarget<String>) -> Bool = { _,_ in true }

    func testBothZoneModel() {
        // source "a": top-quarter ⇒ between-before, middle ⇒ onto, bottom-quarter ⇒ between-after
        XCTAssertEqual(resolveDropTarget(atDocY: 62, source: "a", rows: rows, geom: geom,
                                         mode: .both, chunkIDs: [], validate: yes)?.placement,
                       .between(beforeID: "c"))
        XCTAssertEqual(resolveDropTarget(atDocY: 75, source: "a", rows: rows, geom: geom,
                                         mode: .both, chunkIDs: [], validate: yes)?.placement,
                       .onto(id: "c"))
        XCTAssertEqual(resolveDropTarget(atDocY: 88, source: "a", rows: rows, geom: geom,
                                         mode: .both, chunkIDs: [], validate: yes)?.placement,
                       .between(beforeID: "d"))
    }
    func testTrivialSelfDropRejected() {
        XCTAssertNil(resolveDropTarget(atDocY: 5, source: "a", rows: rows, geom: geom,
                                       mode: .both, chunkIDs: [], validate: yes), "onto self ⇒ nil")
    }
    func testOutOfBounds() {
        XCTAssertEqual(resolveDropTarget(atDocY: -5, source: "c", rows: rows, geom: geom,
                                         mode: .reorderBetween, chunkIDs: [], validate: yes)?.placement,
                       .between(beforeID: "a"))
        XCTAssertEqual(resolveDropTarget(atDocY: 999, source: "a", rows: rows, geom: geom,
                                         mode: .reorderBetween, chunkIDs: [], validate: yes)?.placement,
                       .between(beforeID: nil))
        XCTAssertNil(resolveDropTarget(atDocY: -5, source: "a", rows: rows, geom: geom,
                                       mode: .dropOnto, chunkIDs: [], validate: yes))
    }
    func testValidatorVeto() {
        let vetoB: (DragContext<String>, DropTarget<String>) -> Bool = { _, t in t.placement != .onto(id: "b") }
        XCTAssertNil(resolveDropTarget(atDocY: 45, source: "a", rows: rows, geom: geom,
                                       mode: .dropOnto, chunkIDs: [], validate: vetoB))
    }
    func testChunkGather() {
        let secRows: [ListRow<String>] = [
            ListRow(id: "A", kind: .sectionHeader()), ListRow(id: "a1"), ListRow(id: "a2"),
            ListRow(id: "B", kind: .sectionHeader()), ListRow(id: "b1"),
        ]
        XCTAssertEqual(chunkMemberIDs(forHeader: "A", rows: secRows), ["A", "a1", "a2"])
        XCTAssertEqual(chunkMemberIDs(forHeader: "a1", rows: secRows), [], "non-header ⇒ empty")
    }
    func testChunkAimsAtSectionGapsOnly() {
        let secRows: [ListRow<String>] = [
            ListRow(id: "A", kind: .sectionHeader()), ListRow(id: "a1"),
            ListRow(id: "B", kind: .sectionHeader()), ListRow(id: "b1"),
        ]
        let cands = dragCandidates(source: "A", rows: secRows, mode: .both,
                                   chunkIDs: ["A", "a1"], validate: yes).map(\.placement)
        XCTAssertEqual(cands, [.between(beforeID: "B"), .between(beforeID: nil)],
                       "a chunk lift aims at section gaps + the end gap only")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift build`; CI: `swift test --filter ListDnDTests`
Expected: compile FAIL — `cannot find 'resolveDropTarget' in scope` / `cannot find 'RowGeom'`.

- [ ] **Step 3: Write minimal implementation**

`Sources/ListCore/ListDnD.swift` — the moved vocabulary (generic) + the geometry as pure fns. Bodies are the AppKit logic from `ThemedList.swift:1783-1922` with substitutions: `items`→`rows`, `items[i].id`→`rows[i].id`, `items[i].isSeparator`→`rows[i].isSeparator`, `rowIndex(atDocY:)`→`rowIndex(atDocY:geom:)`, `rowRect(i)`→`geom[i]`, `dragChunkIDs`→`chunkIDs`, `rowLayout.headerIndices`→derived from `rows`, `dropTargetValidator?(…) ?? true`→`validate(…)`.
```swift
import Foundation

// MARK: - DnD vocabulary (moved from ThemeKit.ThemedList; generic over ID)

/// What kinds of drop a draggable list resolves: `.dropOnto` (onto a row), `.reorderBetween`
/// (insertion line), `.both` (the kit picks onto vs between by the pointer's row fraction).
public enum DragMode: Equatable, Sendable { case dropOnto, reorderBetween, both }

/// WHERE a drag would land. `.onto(id:)` ⇒ onto that row; `.between(beforeID:)` ⇒ the gap
/// before `beforeID` (`nil` ⇒ after the last row, the end gap).
public enum DropPlacement<ID: Hashable & Sendable>: Equatable, Sendable {
    case onto(id: ID)
    case between(beforeID: ID?)
}

/// The thing being dragged: the lifted row + every id that moves with it (`[sourceID]`
/// for a single row, `[header, …children]` for a chunk; never empty).
public struct DragContext<ID: Hashable & Sendable>: Equatable, Sendable {
    public let sourceID: ID
    public let memberIDs: [ID]
    public init(sourceID: ID, memberIDs: [ID]) { self.sourceID = sourceID; self.memberIDs = memberIDs }
}

/// A resolved drop target handed to the validator / onDrop.
public struct DropTarget<ID: Hashable & Sendable>: Equatable, Sendable {
    public let placement: DropPlacement<ID>
    public init(placement: DropPlacement<ID>) { self.placement = placement }
}

#if canImport(CoreGraphics)
import CoreGraphics

/// One row's vertical layout in the flipped document space (the only geometry the
/// drop resolver reads). Built by the view from its row layout.
public struct RowGeom: Equatable, Sendable {
    public let yOffset: CGFloat
    public let height: CGFloat
    public init(yOffset: CGFloat, height: CGFloat) { self.yOffset = yOffset; self.height = height }
}

/// The row index containing `docY`, or nil if past the last row.
public func rowIndex(atDocY docY: CGFloat, geom: [RowGeom]) -> Int? {
    geom.firstIndex { docY >= $0.yOffset && docY < $0.yOffset + $0.height }
}

private func nextRowID<ID>(after i: Int, in rows: [ListRow<ID>]) -> ID? {
    let n = i + 1
    return rows.indices.contains(n) ? rows[n].id : nil
}

private func indexOf<ID: Hashable>(_ id: ID, in rows: [ListRow<ID>]) -> Int? {
    rows.firstIndex { $0.id == id }
}

private func isTrivialSelfDrop<ID: Hashable>(_ placement: DropPlacement<ID>, _ source: ID,
                                             rows: [ListRow<ID>]) -> Bool {
    switch placement {
    case .onto(let id): return id == source
    case .between(let beforeID):
        guard let si = indexOf(source, in: rows) else { return false }
        return beforeID == source || beforeID == nextRowID(after: si, in: rows)
    }
}

private func isInsideChunk<ID: Hashable>(_ placement: DropPlacement<ID>, source: ID,
                                         rows: [ListRow<ID>], chunkIDs: [ID]) -> Bool {
    guard !chunkIDs.isEmpty else { return false }
    let members = Set(chunkIDs)
    switch placement {
    case .onto(let id): return members.contains(id)
    case .between(let beforeID):
        if let beforeID, members.contains(beforeID) { return true }
        guard let lastID = chunkIDs.last, let li = indexOf(lastID, in: rows) else { return false }
        var j = li + 1
        while j < rows.count, rows[j].isSeparator { j += 1 }
        let boundaryID: ID? = j < rows.count ? rows[j].id : nil
        return beforeID == nextRowID(after: li, in: rows) || beforeID == boundaryID
    }
}

private func validatedTarget<ID: Hashable>(_ placement: DropPlacement<ID>, _ source: ID,
                                           rows: [ListRow<ID>], chunkIDs: [ID],
                                           validate: (DragContext<ID>, DropTarget<ID>) -> Bool) -> DropTarget<ID>? {
    guard !isTrivialSelfDrop(placement, source, rows: rows) else { return nil }
    guard !isInsideChunk(placement, source: source, rows: rows, chunkIDs: chunkIDs) else { return nil }
    if case let .onto(id) = placement, let i = indexOf(id, in: rows), rows[i].isSeparator { return nil }
    let target = DropTarget(placement: placement)
    let ctx = DragContext(sourceID: source, memberIDs: chunkIDs.isEmpty ? [source] : chunkIDs)
    guard validate(ctx, target) else { return nil }
    return target
}

/// The validated drop target a pointer at `docY` resolves to (pure). A non-empty `chunkIDs`
/// forces `.reorderBetween` (a chunk reorders to a gap, never onto a row).
public func resolveDropTarget<ID: Hashable>(atDocY docY: CGFloat, source: ID,
                                            rows: [ListRow<ID>], geom: [RowGeom],
                                            mode requestedMode: DragMode, chunkIDs: [ID],
                                            validate: (DragContext<ID>, DropTarget<ID>) -> Bool) -> DropTarget<ID>? {
    guard !rows.isEmpty else { return nil }
    let mode: DragMode = chunkIDs.isEmpty ? requestedMode : .reorderBetween
    if docY < 0 {
        return mode == .dropOnto ? nil : validatedTarget(.between(beforeID: rows[0].id), source, rows: rows, chunkIDs: chunkIDs, validate: validate)
    }
    guard let i = rowIndex(atDocY: docY, geom: geom) else {
        return mode == .dropOnto ? nil : validatedTarget(.between(beforeID: nil), source, rows: rows, chunkIDs: chunkIDs, validate: validate)
    }
    if rows[i].isSeparator { return nil }
    let minY = geom[i].yOffset, h = geom[i].height
    let frac = h > 0 ? (docY - minY) / h : 0.5
    switch mode {
    case .dropOnto:
        return validatedTarget(.onto(id: rows[i].id), source, rows: rows, chunkIDs: chunkIDs, validate: validate)
    case .reorderBetween:
        return validatedTarget(.between(beforeID: frac < 0.5 ? rows[i].id : nextRowID(after: i, in: rows)), source, rows: rows, chunkIDs: chunkIDs, validate: validate)
    case .both:
        if frac < 0.25 { return validatedTarget(.between(beforeID: rows[i].id), source, rows: rows, chunkIDs: chunkIDs, validate: validate) }
        if frac > 0.75 { return validatedTarget(.between(beforeID: nextRowID(after: i, in: rows)), source, rows: rows, chunkIDs: chunkIDs, validate: validate) }
        return validatedTarget(.onto(id: rows[i].id), source, rows: rows, chunkIDs: chunkIDs, validate: validate)
            ?? validatedTarget(.between(beforeID: rows[i].id), source, rows: rows, chunkIDs: chunkIDs, validate: validate)
    }
}

/// The ordered, validated keyboard candidates for `source` + `mode`. A chunk lift aims at
/// section-header gaps + the end gap only (whole-section reorder); else onto/between per mode.
public func dragCandidates<ID: Hashable>(source: ID, rows: [ListRow<ID>], mode: DragMode,
                                         chunkIDs: [ID],
                                         validate: (DragContext<ID>, DropTarget<ID>) -> Bool) -> [DropTarget<ID>] {
    var out: [DropTarget<ID>] = []
    if !chunkIDs.isEmpty {
        for h in rows.indices where rows[h].isHeader {
            if let t = validatedTarget(.between(beforeID: rows[h].id), source, rows: rows, chunkIDs: chunkIDs, validate: validate) { out.append(t) }
        }
        if let t = validatedTarget(.between(beforeID: nil), source, rows: rows, chunkIDs: chunkIDs, validate: validate) { out.append(t) }
        return out
    }
    for row in rows where !row.isSeparator {
        switch mode {
        case .dropOnto:
            if let t = validatedTarget(.onto(id: row.id), source, rows: rows, chunkIDs: chunkIDs, validate: validate) { out.append(t) }
        case .reorderBetween:
            if let t = validatedTarget(.between(beforeID: row.id), source, rows: rows, chunkIDs: chunkIDs, validate: validate) { out.append(t) }
        case .both:
            if let t = validatedTarget(.between(beforeID: row.id), source, rows: rows, chunkIDs: chunkIDs, validate: validate) { out.append(t) }
            if let t = validatedTarget(.onto(id: row.id), source, rows: rows, chunkIDs: chunkIDs, validate: validate) { out.append(t) }
        }
    }
    if mode != .dropOnto, let t = validatedTarget(.between(beforeID: nil), source, rows: rows, chunkIDs: chunkIDs, validate: validate) { out.append(t) }
    return out
}

/// The ids that move as a unit when the section HEADER `id` is lifted: the header + every
/// row beneath up to (not including) the next header; separators skipped; non-header ⇒ [].
public func chunkMemberIDs<ID: Hashable>(forHeader id: ID, rows: [ListRow<ID>]) -> [ID] {
    guard let start = indexOf(id, in: rows), rows[start].isHeader else { return [] }
    var out = [rows[start].id]
    var i = start + 1
    while i < rows.count, !rows[i].isHeader {
        if !rows[i].isSeparator { out.append(rows[i].id) }
        i += 1
    }
    return out
}
#endif
```

- [ ] **Step 4: Run test to verify it passes (ListCore side)**

Run: `swift build`; CI: `swift test --filter ListDnDTests`
Expected: build OK; tests PASS.

- [ ] **Step 5: Rewire the AppKit widget to forward (keeps `ThemedListTests` green)**

In `Sources/ThemeKit/ThemedList.swift`:

(a) DELETE the vocabulary definitions at `:155-197` (`DragMode`, `DropPlacement`, `DragContext`, `DropTarget`) and ADD, near the top of the file (after `import ListCore`), the `String` typealiases so every existing reference resolves unchanged:
```swift
// DnD vocabulary now lives in ListCore (generic); the AppKit widget is String-keyed.
typealias DragMode = ListCore.DragMode
typealias DropPlacement = ListCore.DropPlacement<String>
typealias DragContext = ListCore.DragContext<String>
typealias DropTarget = ListCore.DropTarget<String>
```

(b) ADD a private projection from the widget's state to the pure cores (place near `recomputeLayout`):
```swift
/// The pure-core shadow of the current `items` (drops the NSImage etc.).
private var coreRows: [ListRow<String>] {
    items.map { ListRow(id: $0.id, kind: $0.kind.coreKind, isDisabled: $0.isDisabled, indentLevel: $0.indentLevel) }
}
/// The per-row vertical geometry the drop resolver needs, from the cached row layout.
private var coreGeom: [RowGeom] {
    rowLayout.yOffsets.indices.map { RowGeom(yOffset: rowLayout.yOffsets[$0], height: rowLayout.heights[$0]) }
}
```
and ADD the `Kind → RowKind` bridge as an extension in the same file:
```swift
private extension ListItem.Kind {
    var coreKind: RowKind {
        switch self {
        case .row: return .row
        case let .sectionHeader(s, c): return .sectionHeader(subtitle: s, collapsed: c)
        case .separator: return .separator
        }
    }
}
```

(c) REPLACE the bodies of the private methods at `:1783` (`resolveDropTarget`), `:1870` (`dragCandidates`), `:1913` (`chunkMemberIDs`) with forwarders, and DELETE the now-unused private helpers `validatedTarget` `:1817`, `isTrivialSelfDrop` `:1829`, `isInsideChunk` `:1846`, `nextRowID` `:1900` (their logic now lives in `ListCore`). Note: the `_isInsideChunk` test seam (`:2474`) must keep working — re-point it at the ListCore helper by exposing a tiny internal wrapper (see below):
```swift
fileprivate func resolveDropTarget(atDocY docY: CGFloat, source: String) -> DropTarget? {
    let mode: DragMode = dragChunkIDs.isEmpty ? dragMode : .reorderBetween
    return ListCore.resolveDropTarget(atDocY: docY, source: source, rows: coreRows, geom: coreGeom,
                                      mode: mode, chunkIDs: dragChunkIDs,
                                      validate: { [weak self] ctx, t in self?.dropTargetValidator?(ctx, t) ?? true })
}
private func dragCandidates() -> [DropTarget] {
    guard let source = drag?.sourceID else { return [] }
    return ListCore.dragCandidates(source: source, rows: coreRows, mode: dragMode, chunkIDs: dragChunkIDs,
                                   validate: { [weak self] ctx, t in self?.dropTargetValidator?(ctx, t) ?? true })
}
private func chunkMemberIDs(forHeader id: String) -> [String] {
    ListCore.chunkMemberIDs(forHeader: id, rows: coreRows)
}
```
For the `_isInsideChunk` seam (`:2474`), replace its body with a direct ListCore call (the helper is private in ListCore, so expose the check through `resolveDropTarget`'s path instead — simplest: keep a thin internal `isInsideChunk` in the widget that calls a NEW `public` ListCore overload, OR drop the seam if no test needs it after the port). **Verify which tests call `_isInsideChunk`** with `grep -n _isInsideChunk Tests/ThemeKitTests/ThemedListTests.swift`; if used, add a `public func isInsideChunk<ID>(_:source:rows:chunkIDs:) -> Bool` to `ListCore/ListDnD.swift` and forward to it. (Note: `resolveDropTarget` already exercises the chunk-internal rejection, so prefer testing through it; only expose the helper if an existing test depends on the seam directly.)

- [ ] **Step 6: Run full build + existing widget tests (regression oracle)**

Run: `swift build`; CI: `swift test --filter ThemedListTests` AND `swift test --filter ListDnDTests`
Expected: build OK; BOTH suites PASS (the widget's drag tests prove the forwarders preserve behavior; the ListCore tests lock the pure fns).

- [ ] **Step 7: Commit**

```bash
git add Sources/ListCore/ListDnD.swift Tests/ListCoreTests/ListDnDTests.swift Sources/ThemeKit/ThemedList.swift
git commit -m ":recycle: refactor(ListCore): move drag-target + chunk geometry out of AppKit ThemedList"
```

---

### Task 5: Move the sticky-header geometry into ListCore

**Files:**
- Create: `Sources/ListCore/StickyHeader.swift`
- Modify: `Sources/ThemeKit/ThemedList.swift` (rewrite `stickyHeader` `:1083` as a forwarder)
- Test: `Tests/ListCoreTests/StickyHeaderTests.swift`

**Interfaces:**
- Consumes: nothing (operates on raw `[Int]`/`[CGFloat]`).
- Produces: `stickyHeader(atVisibleTop:headerIndices:yOffsets:heights:) -> (index: Int, drawY: CGFloat)?`.

- [ ] **Step 1: Write the failing test**

`Tests/ListCoreTests/StickyHeaderTests.swift` — port `ThemedListTests.swift:134-149` (pin + hand-off + none-above), with explicit arrays (two headers A@0 h=40, B@110 h=40; rows fill the gaps):
```swift
import XCTest
@testable import ListCore
#if canImport(CoreGraphics)
import CoreGraphics

final class StickyHeaderTests: XCTestCase {
    // headers at indices 0 and 3; A: y0 h40, then rows, B: y110 h40.
    let headerIndices = [0, 3]
    let yOffsets: [CGFloat] = [0, 40, 75, 110]
    let heights: [CGFloat] = [40, 35, 35, 40]

    func testPinAndHandoff() {
        XCTAssertEqual(stickyHeader(atVisibleTop: 0, headerIndices: headerIndices, yOffsets: yOffsets, heights: heights)?.index, 0)
        let pushed = stickyHeader(atVisibleTop: 75, headerIndices: headerIndices, yOffsets: yOffsets, heights: heights)
        XCTAssertEqual(pushed?.index, 0, "A is still active until B's top reaches it")
        XCTAssertEqual(pushed?.drawY, 110 - 40, "B (top 110) pushes A up: drawY = nextTop - headerHeight")
        XCTAssertEqual(stickyHeader(atVisibleTop: 110, headerIndices: headerIndices, yOffsets: yOffsets, heights: heights)?.index, 3, "past B's top, B takes over")
    }
    func testNoneAbove() {
        XCTAssertNil(stickyHeader(atVisibleTop: -5, headerIndices: headerIndices, yOffsets: yOffsets, heights: heights))
    }
}
#endif
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift build`; CI: `swift test --filter StickyHeaderTests`
Expected: compile FAIL — `cannot find 'stickyHeader' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/ListCore/StickyHeader.swift` — body is `ThemedList.swift:1083-1092` with the `rowLayout.*` reads replaced by parameters:
```swift
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics

/// The pinned section header for a given visible-top scroll offset (pure). Returns the
/// active header's index and the y at which to draw it: normally `bandTop`, but pushed
/// up (`nextTop - headerHeight`, may go above `bandTop`) when the next header is within
/// one header-height — the hand-off. nil ⇒ no header at/above the top.
public func stickyHeader(atVisibleTop bandTop: CGFloat, headerIndices: [Int],
                         yOffsets: [CGFloat], heights: [CGFloat]) -> (index: Int, drawY: CGFloat)? {
    guard let active = headerIndices.last(where: { yOffsets[$0] <= bandTop }) else { return nil }
    let hH = heights[active]
    var drawY = bandTop
    if let next = headerIndices.first(where: { yOffsets[$0] > yOffsets[active] }) {
        let nextTop = yOffsets[next]
        if nextTop - bandTop < hH { drawY = nextTop - hH }
    }
    return (active, drawY)
}
#endif
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift build`; CI: `swift test --filter StickyHeaderTests`
Expected: build OK; tests PASS.

- [ ] **Step 5: Rewire the widget's `stickyHeader` to forward**

In `Sources/ThemeKit/ThemedList.swift`, replace the body at `:1083`:
```swift
func stickyHeader(atVisibleTop bandTop: CGFloat) -> (index: Int, drawY: CGFloat)? {
    ListCore.stickyHeader(atVisibleTop: bandTop, headerIndices: rowLayout.headerIndices,
                          yOffsets: rowLayout.yOffsets, heights: rowLayout.heights)
}
```
(The `_stickyHeader(atScrollY:)` test seam at `:2423` calls this and is unchanged.)

- [ ] **Step 6: Run build + the widget sticky tests (regression oracle)**

Run: `swift build`; CI: `swift test --filter ThemedListTests` AND `swift test --filter StickyHeaderTests`
Expected: build OK; `testStickyHeaderPinAndHandoff`, `testNoStickyHeaderWhenNoneAbove`, `testStickyHeaderKeepsCollapsibleHeaderPinnable` and the new tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/ListCore/StickyHeader.swift Tests/ListCoreTests/StickyHeaderTests.swift Sources/ThemeKit/ThemedList.swift
git commit -m ":recycle: refactor(ListCore): move sticky-header geometry out of AppKit ThemedList"
```

---

## Self-Review

**1. Spec coverage (against `2026-06-23-17b-themedlist-swiftui-design.md` §5 "ListCore additions"):**
- pure row model `ListRow` → Task 1 ✓
- multi-select resolvers (resolveClick/extendByKey/selectAll/rangeIDs + SelectMods) → Task 2 ✓
- collapse helpers (toggleSection/flattenVisible) → Task 3 ✓
- DnD geometry move (DragMode/DropPlacement/DragContext/DropTarget + resolveDropTarget/dragCandidates/chunkMemberIDs + helpers) → Task 4 ✓
- sticky header move → Task 5 ✓
- measurement (`contentHeight`/`fittingWidth`) → **intentionally deferred to Milestone 3** (only the popup hosts need it; `fittingWidth` measures text via NSFont so it is NOT pure and stays in the view layer). Noted in File Structure + as a spec correction in the milestone notes. ✓ (gap is deliberate + documented)
- keep AppKit forwarders + String typealiases so the widget compiles unchanged + existing tests stay green → Tasks 4–5 Steps 5–6 ✓

**2. Placeholder scan:** No "TBD"/"TODO"/"handle edge cases". The one conditional ("if a test calls `_isInsideChunk`, expose a public overload") is a verify-then-act instruction with the exact grep + both branches specified — not a placeholder.

**3. Type consistency:** `ListRow<ID>` / `RowKind` / `RowGeom` / `DropTarget<ID>` / `DropPlacement<ID>` / `DragContext<ID>` / `DragMode` / `SelectMods` are used identically across Tasks 1–5. `resolveDropTarget`/`dragCandidates`/`chunkMemberIDs`/`stickyHeader` signatures in the forwarders (Task 4/5 Step 5) match the definitions (Task 4/5 Step 3). `coreKind` bridge maps `ListItem.Kind` → `RowKind` consistently.

---

## Execution Handoff

This plan is **ready to write now** but **blocked on nothing** — Milestone 1 runs on the current CLT toolchain (macOS 13 floor, SDK 15.5); the macOS-26 toolchain upgrade is only needed before Milestone 2. Execution options when ready:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks (REQUIRED SUB-SKILL: superpowers:subagent-driven-development).
2. **Inline Execution** — execute in-session with checkpoints (REQUIRED SUB-SKILL: superpowers:executing-plans).

Milestones 2–5 (SwiftUI `ThemedListView`, popup host migration, AppKit retire) get their own plans authored against the macOS 26 SDK + live prism gate once the toolchain is upgraded.
