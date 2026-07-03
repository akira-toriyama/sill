# #17b Milestone 3 — Combo popup hosted on the SwiftUI `ThemedListView` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drive `ThemedComboBox`'s drop-down from the SwiftUI-native `ThemedListView` (M2) instead of the AppKit `ThemedList`, via a new imperative `ListController`, keeping the field first-responder and the synchronous row-click commit intact.

**Architecture:** A `@Observable @MainActor` `ListController<ID>` (ThemeKitUI) owns `items`/`highlight`/`selection` and re-vends the exact imperative contract the combo calls today (`moveHighlight`/`activateHighlight`/`clearHighlight`/`highlightedID`), delegating the math to the pure M1 `ListCore`. The combo hosts a `ThemedListView` (bound to the controller) inside an `NSHostingView` subclass (`HostingListView`, ThemeKit) whose **AppKit `mouseUp`** fires activation on the same runloop tick (the load-bearing commit path SwiftUI taps can't guarantee) and whose tracking area drives hover — the panel chrome (`PopupPanel`/`placePopup`/fade/monitors/filter/dismiss) is byte-for-byte unchanged. The AppKit `ThemedList` stays intact (it still backs `ThemedMenu` until M4, and is deleted only at M5).

**Tech Stack:** Swift 6.3 / SwiftUI + AppKit, macOS 26 floor, `@Observable`, `NSHostingView`, XCTest via `scripts/test.sh` (Xcode-over-CLT), prism visual bench.

## Global Constraints

- **macOS floor = 26** (already shipped, v2.0.0) — no availability gates / fallbacks needed; `@Observable`, `.onKeyPress`, `ScrollViewReader` all unconditional.
- **AppKit stays inside the 3 floors** — this milestone adds AppKit only in ThemeKit's popup-shell (floor #2: the non-activating panel + its `NSHostingView` mouse routing). `ThemeKitUI` stays SwiftUI. Do NOT widen AppKit into `ThemeKitUI`.
- **`ListCore` is pure** (Foundation + `#if canImport(CoreGraphics)`), Sendable, no `NSImage`/AppKit. The controller lives in `ThemeKitUI`, not `ListCore`.
- **Measurement (`contentHeight`/`fittingWidth`/`rowRectOnScreen`) is DEFERRED to M4** — the combo sizes its panel by uniform row count (`filtered.count × rowHeight`), never by content measurement (verified: `ThemedComboBox.swift` has zero `contentHeight`/`fittingWidth` calls). Only `ThemedMenu` (M4) consumes measurement.
- **No version tag this milestone** — M2..M4 ship untagged; the `v<x.y.0>` tag lands at M5 retire (per spec §7).
- **Commits:** gitmoji + Conventional Commits, e.g. `:sparkles: feat(ThemeKitUI): …`. English subject/body.
- **Two local gates before every commit:** `swift build` (CLT quick bar) and `scripts/test.sh` (full XCTest). New pure/controller logic MUST be CI-tested; the synchronous-commit timing is proven by the **prism live maintainer gate** (Task 5), not a unit test.
- **Retire risk #1 (spec §9):** the synchronous combo commit is proven LIVE in prism in this milestone — it is the precondition that unblocks the M5 AppKit deletion. Per [[chomp-push-gate]], re-confirm "sill で確認済み？" once before the merge that lands this behavior change.

---

## Revision 2026-07-03 — Option A (cycle resolution) ⚠ SUPERSEDES §File-Structure/Task-3/Task-4 module placement

**Blocker found during Task 3:** the spec §1's "ThemeKit depends on ThemeKitUI (new edge)" is a **circular dependency** — `ThemeKitUI → ThemeKit` already exists and is load-bearing (ThemeKitUI's SwiftUI views wrap the AppKit widgets: `ThemedButton` ×28, `ThemedToolBar` ×17, `ThemedList` ×15 refs). SwiftPM forbids the cycle. The spec §1 also said "ThemedComboBox/ThemedMenu stay in ThemeKit," which contradicts both the cycle and the newer **AppKit policy (CLAUDE.md, 2026-06-30): the 3 AppKit floors — IME field-editor, non-key popup shell, selectable rich-text — live in `ThemeKitUI`.** The combo IS floors #1 (field editor) + #2 (popup shell).

**Resolution (user-approved Option A):** **`ThemedComboBox` moves `ThemeKit → ThemeKitUI`** (its natural home per the AppKit policy). `HostingListView` lives in `ThemeKitUI` too (done, Task 3). ThemeKit keeps the shared popup primitives (`PopupPanel`/`themedPopupPanel`/`placePopup`/`PopupFade`/`PopupGlue` — also used by `ThemedMenu`/`ThemedTooltip`/`WindowShell`, so they can't move without cascading); the moved combo consumes them from ThemeKit (ThemeKitUI→ThemeKit is fine). This sets the pattern for **M4 (menu moves too)** and **M5**.

**Panel-construction sub-decision (Task 4 start):** the primitives combo uses are `internal` to ThemeKit. Two ways for the moved combo to build its panel:
- **(pref) refactor combo onto the PUBLIC `makeWindowShell(_ spec:) -> ShellPanel`** (WindowShell.swift:133, the #17i public shell) — keeps ThemeKit's encapsulation; combo stops using the internal `themedPopupPanel`. Verify `makeWindowShell` covers: non-activating + non-key + interactive (`ignoresMouseEvents=false`) + `.list` AX role + fade + `.anchorWidthBelow` placement + outside-click/Esc dismissal (PopupGlue).
- **(fallback) publicize** `themedPopupPanel`/`PopupPanel`/`placePopup`/`PopupPlacement(Result)`/`PopupFade`/`PopupGlue` and keep the combo's current panel code verbatim. Mechanical, but expands ThemeKit's public surface (partly undoing #17i's encapsulation).
- **`ThemedTextField` is already `public`** with its full combo-facing API (`onMoveDown/onMoveUp/onReturn/onEscape`, `focus(selectingAll:)`, `announceAccessibilityValue`) — the field needs NO publicize work.

**Revised file placement (overrides the list below):** `HostingListView` → `Sources/ThemeKitUI/HostingListView.swift` (done). `HostedThemedList` → `Sources/ThemeKitUI/HostedThemedList.swift` (done, replaces the convenience-init idea — `@Bindable` observation drives re-render, so NO manual `rehostRoot`). Task 4 `Move:` `Sources/ThemeKit/ThemedComboBox.swift` → `Sources/ThemeKitUI/ThemedComboBox.swift`; `Tests/ThemeKitTests/ThemedComboBoxTests.swift` → `Tests/ThemeKitUITests/ThemedComboBoxTests.swift` (+ Package.swift: ThemeKitUITests already deps ThemeKit/ListCore ✓). The `ThemedComboBoxView` SwiftUI bridge is already in ThemeKitUI (now same-module as the widget).

**Status:** Tasks 1-3 shipped (ListController + hosted ThemedListView + HostingListView, all in ThemeKitUI, build+tests green). Next = Task 4 (the move+rewire) then Task 5 (prism live gate).

---

## File Structure

- **`Sources/ThemeKitUI/ListController.swift`** (NEW) — `@Observable @MainActor final class ListController<ID>`. The imperative popup driver: `items`/`highlight`/`selection`/`query`/`noOptionsText`/`previewHighlight`, the `moveHighlight`/`activateHighlight`/`clearHighlight`/`highlightedID` contract (→ `ListCore`), the `onActivate`/`onEmptyAction`/`onHover` callbacks, and the `rowRects: [ID: CGRect]` hit-test map + `row(at:)` resolver the AppKit host reads.
- **`Sources/ThemeKitUI/ThemedListView.swift`** (MODIFY) — add a `controller`-bound convenience init + row-rect reporting (a `PreferenceKey` reduced to `onRowRects`) + a `hosted` style flag that suppresses SwiftUI row activation (so the AppKit `mouseUp` owns the click).
- **`Sources/ThemeKitUI/ListStyle.swift`** (MODIFY) — add `public var hosted: Bool = false` to `ThemedListStyle`.
- **`Sources/ThemeKit/HostingListView.swift`** (NEW) — `final class HostingListView<ID>: NSHostingView<ThemedListView<ID>>`: `acceptsFirstMouse = true`, non-first-responder, `mouseUp` → `controller.row(at:)` → `controller.fireActivate`, tracking-area `mouseMoved`/`mouseExited` → `controller.setHover`.
- **`Sources/ThemeKit/ThemedComboBox.swift`** (MODIFY) — replace the `list: ThemedList!` install + all `list.*` calls with `controller: ListController<String>` + `HostingListView`. Panel chrome / field forwarding / guards / reframe / filter / dismiss unchanged.
- **`Tests/ThemeKitUITests/ListControllerTests.swift`** (NEW) — pure-ish `@MainActor` unit tests for the controller's highlight/selection/empty-action contract.
- **`Tests/ThemeKitTests/ThemedComboBoxTests.swift`** (MODIFY) — re-vend the `listProbe` assertions off the controller (the old ones read the AppKit `ThemedList`).
- **`Sources/prism/*`** — combo showcase cells already exercise `ThemedComboBoxView`; verify live (Task 5). No prism source change expected unless a caption drifts.

---

## Task 1: `ListController<ID>` — the imperative popup driver

**Files:**
- Create: `Sources/ThemeKitUI/ListController.swift`
- Test: `Tests/ThemeKitUITests/ListControllerTests.swift`

**Interfaces:**
- Consumes: `ListCore.nextHighlight(current:Int?, delta:Int, selectableIndices:[Int], wraps:Bool) -> Int?`; `ThemeKitUI.ListItem<ID>` (`.asRow.isSelectable`, `.id`, `.primary`, `.isDisabled`); `ThemedListStyle` (`.wrapsHighlight`).
- Produces (later tasks + the combo rely on these EXACT names, mirroring today's `ThemedList` API):
  - `var items: [ListItem<ID>]`, `var highlight: ID?`, `var selection: Set<ID>`, `var query: String`, `var noOptionsText: String`, `var previewHighlight: ID?`
  - `var emptyActionRow: ((String) -> String?)?`, `var isActionRowActive: Bool` (computed)
  - `func moveHighlight(_ delta: Int)`, `func clearHighlight()`, `func activateHighlight()`, `var highlightedID: ID?`
  - callbacks `var onActivate: (ID) -> Void`, `var onEmptyAction: (String) -> Void`, `var onHover: (ID?) -> Void`
  - `var rowRects: [ID: CGRect]`, `func row(at point: CGPoint) -> ID?`, `func fireActivate(_ id: ID)`, `func setHover(_ id: ID?)`

- [ ] **Step 1: Write the failing test**

`Tests/ThemeKitUITests/ListControllerTests.swift`:

```swift
import XCTest
import ListCore
@testable import ThemeKitUI

@MainActor
final class ListControllerTests: XCTestCase {
    private func opt(_ id: String) -> ListItem<String> { ListItem(id: id, primary: id) }

    func testMoveHighlightWrapsAndSkipsHeaders() {
        let c = ListController<String>()
        c.style.wrapsHighlight = true
        c.items = [ListItem(id: "H", primary: "Head", kind: .sectionHeader()),
                   opt("a"), opt("b")]
        c.moveHighlight(1)                    // no current, delta>0 → first selectable
        XCTAssertEqual(c.highlight, "a")
        c.moveHighlight(1)
        XCTAssertEqual(c.highlight, "b")
        c.moveHighlight(1)                    // wraps past the header back to "a"
        XCTAssertEqual(c.highlight, "a")
    }

    func testActivateHighlightFiresOnActivate() {
        let c = ListController<String>()
        c.items = [opt("a"), opt("b")]
        var fired: String?
        c.onActivate = { fired = $0 }
        c.highlight = "b"
        c.activateHighlight()
        XCTAssertEqual(fired, "b")
    }

    func testEmptyActionRowActivates() {
        let c = ListController<String>()
        c.items = []
        c.query = "xyz"
        c.emptyActionRow = { q in "Create \(q)" }
        XCTAssertTrue(c.isActionRowActive)
        var firedQuery: String?
        c.onEmptyAction = { firedQuery = $0 }
        c.activateHighlight()                 // no highlight, but the action row fires
        XCTAssertEqual(firedQuery, "xyz")
    }

    func testClearHighlightAndReadBack() {
        let c = ListController<String>()
        c.items = [opt("a")]
        c.highlight = "a"
        XCTAssertEqual(c.highlightedID, "a")
        c.clearHighlight()
        XCTAssertNil(c.highlight)
        XCTAssertNil(c.highlightedID)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `scripts/test.sh 2>&1 | pare` — Expected: FAIL (`cannot find 'ListController' in scope`).

- [ ] **Step 3: Write the minimal implementation**

`Sources/ThemeKitUI/ListController.swift`:

```swift
// ThemeKitUI — the imperative driver for a `ThemedListView` hosted in a non-key
// AppKit popup (#17b M3). A non-activating panel's SwiftUI content never becomes
// first responder, so the combo/menu drive the roving highlight from OUTSIDE
// (field key-forwarders / an NSEvent monitor) by mutating this `@Observable`
// controller; the view is the passive renderer of `highlight`/`selection`. Mirrors
// the AppKit `ThemedList`'s imperative surface 1:1 so the hosts translate calls,
// not concepts. Highlight math delegates to the pure M1 `ListCore`.
import SwiftUI
import ListCore

@Observable @MainActor
public final class ListController<ID: Hashable & Sendable> {
    public var items: [ListItem<ID>] = []
    public var highlight: ID?
    public var selection: Set<ID> = []
    public var query: String = ""
    public var noOptionsText: String = "No options"
    /// Deterministic still-capture seam (mirrors `ThemedList.previewHighlight`).
    public var previewHighlight: ID?
    public var style = ThemedListStyle()
    /// When set, an empty `items` offers ONE synthetic actionable row (the combo's
    /// "create ‹query›"). Returns the row's label, or nil to keep the empty state inert.
    public var emptyActionRow: ((String) -> String?)?

    public var onActivate: (ID) -> Void = { _ in }
    public var onEmptyAction: (String) -> Void = { _ in }
    public var onHover: (ID?) -> Void = { _ in }

    /// Per-row frames in the hosting view's coordinate space, reduced from the
    /// SwiftUI view's `PreferenceKey` (Task 2). The AppKit host reads these to
    /// map a `mouseUp`/`mouseMoved` point back to a row id.
    public var rowRects: [ID: CGRect] = [:]

    public init() {}

    /// True when the empty state is an actionable "create" row (combo parity).
    public var isActionRowActive: Bool { items.isEmpty && (emptyActionRow?(query) != nil) }

    private var selectableIndices: [Int] {
        items.indices.filter { items[$0].asRow.isSelectable }
    }

    public func moveHighlight(_ delta: Int) {
        let cur = highlight.flatMap { id in items.firstIndex { $0.id == id } }
        guard let np = nextHighlight(current: cur, delta: delta,
                                     selectableIndices: selectableIndices,
                                     wraps: style.wrapsHighlight) else { highlight = nil; return }
        highlight = items[np].id
    }

    public func clearHighlight() { highlight = nil }

    /// Read-back of the current highlight (nil for a header / no highlight). The
    /// combo checks this to decide whether Return commits a row or just closes.
    public var highlightedID: ID? { highlight }

    /// Commit the highlighted row (→ `onActivate`) or the actionable empty row
    /// (→ `onEmptyAction`), matching `ThemedList.activateHighlight` + combo parity:
    /// the action row fires even with no highlight.
    public func activateHighlight() {
        if isActionRowActive { onEmptyAction(query); return }
        if let id = highlight { onActivate(id) }
    }

    /// AppKit `mouseUp` entry point — the SYNCHRONOUS commit (Task 3). Same-tick.
    public func fireActivate(_ id: ID) { onActivate(id) }

    /// Resolve a point (hosting-view coords) to the row under it, nil if none.
    public func row(at point: CGPoint) -> ID? {
        rowRects.first { $0.value.contains(point) }?.key
    }

    /// AppKit tracking entry point — set the roving highlight from hover (when
    /// `highlightFollowsHover`) + report the hover edge to the host's guard.
    public func setHover(_ id: ID?) {
        if style.highlightFollowsHover, let id { highlight = id }
        onHover(id)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `scripts/test.sh 2>&1 | pare` — Expected: PASS (`ListControllerTests` 4/4).

- [ ] **Step 5: Commit**

```bash
git add Sources/ThemeKitUI/ListController.swift Tests/ThemeKitUITests/ListControllerTests.swift
git commit -m ":sparkles: feat(ThemeKitUI): #17b M3 — ListController<ID> imperative popup driver (delegates highlight to ListCore)"
```

---

## Task 2: Row-rect reporting + `hosted` mode in `ThemedListView`

**Files:**
- Modify: `Sources/ThemeKitUI/ListStyle.swift` (add `hosted` flag)
- Modify: `Sources/ThemeKitUI/ThemedListView.swift` (controller-bound init, row-rect `PreferenceKey`, suppress row activation when `hosted`)

**Interfaces:**
- Consumes: `ListController<ID>` (Task 1) — binds `items`/`highlight`/`selection`, writes `rowRects`.
- Produces: `ThemedListView(controller:style:palette:onActivate:onEmptyAction:onHover:)` convenience init; a `RowRectKey` preference reduced into `controller.rowRects`.

> **SwiftUI-render caveat (house rule):** `swift test` proves logic, NOT SwiftUI drawing. This task has no unit test — its correctness (rects line up with drawn rows; `hosted` suppresses taps) is proven by the combo working live in Task 5. Gate it on `swift build` green + the downstream combo.

- [ ] **Step 1: Add the `hosted` flag**

In `Sources/ThemeKitUI/ListStyle.swift`, add to `ThemedListStyle` (after `highlightFollowsHover`):

```swift
    /// Hosted in a non-key AppKit popup (combo/menu): the SwiftUI rows do NOT own
    /// activation — the host's AppKit `mouseUp` fires the synchronous commit, and
    /// hover comes from an AppKit tracking area. `false` (default) = standalone
    /// (facet inline): rows own tap-select + `.onHover` as in M2.
    public var hosted: Bool = false
```

- [ ] **Step 2: Add the row-rect `PreferenceKey`**

At file scope in `Sources/ThemeKitUI/ThemedListView.swift`:

```swift
/// Collects each visible row's frame (in the list's coordinate space) so a
/// non-key AppKit popup host can hit-test a click/hover back to a row id.
struct RowRectKey<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: CGRect] { [:] }
    static func reduce(value: inout [ID: CGRect], nextValue: () -> [ID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
```

- [ ] **Step 3: Report rects + a hosted-mode activation callback**

Add a `var onRowRects: ([ID: CGRect]) -> Void = { _ in }` stored property + init param. Tag each row's background with its frame in a named coordinate space (`.coordinateSpace(.named("themedList"))` on the scroll content), e.g. inside the row builder:

```swift
.background(GeometryReader { geo in
    Color.clear.preference(key: RowRectKey<ID>.self,
                           value: [item.id: geo.frame(in: .named("themedList"))])
})
```

and collect at the list root:

```swift
.coordinateSpace(.named("themedList"))
.onPreferenceChange(RowRectKey<ID>.self) { onRowRects($0) }
```

When `style.hosted` is true, do NOT attach the row `.onTapGesture`/`.onHover` (the AppKit host owns click + hover); keep them for standalone.

- [ ] **Step 4: Add the controller-bound convenience init**

Append to `ThemedListView` an init that wires the `@Observable` controller's fields as bindings:

```swift
public init(controller: ListController<ID>,
            style: ThemedListStyle,
            palette: ResolvedPalette) {
    self.init(items: controller.items,
              selection: Binding(get: { controller.selection }, set: { controller.selection = $0 }),
              highlight: Binding(get: { controller.previewHighlight ?? controller.highlight },
                                 set: { controller.highlight = $0 }),
              style: style,
              palette: palette,
              onActivate: { controller.fireActivate($0) },
              onHover: { controller.setHover($0) },
              onEmptyAction: { controller.onEmptyAction($0) },
              emptyActionRow: controller.emptyActionRow,
              query: controller.query,
              noOptionsText: controller.noOptionsText,
              onRowRects: { controller.rowRects = $0 })
}
```

- [ ] **Step 5: Verify build + commit**

Run: `swift build 2>&1 | pare --tail 15` — Expected: `Build complete!`

```bash
git add Sources/ThemeKitUI/ListStyle.swift Sources/ThemeKitUI/ThemedListView.swift
git commit -m ":sparkles: feat(ThemeKitUI): #17b M3 — ThemedListView row-rect reporting + hosted mode + controller-bound init"
```

---

## Task 3: `HostingListView` — AppKit `mouseUp` synchronous commit + hover tracking

**Files:**
- Create: `Sources/ThemeKit/HostingListView.swift`

**Interfaces:**
- Consumes: `ThemeKitUI.ListController<ID>` (`row(at:)`, `fireActivate`, `setHover`, `rowRects`), `ThemeKitUI.ThemedListView<ID>` (root view).
- Produces: `final class HostingListView<ID>: NSHostingView<ThemedListView<ID>>` with `init(controller:rootView:)`.

> **Live-gated (spec §9 risk #1):** the same-tick `mouseUp` commit is proven in prism (Task 5), not a unit test. If `mouseUp` does NOT reach this view (SwiftUI content consumes it despite `hosted` mode), FALL BACK to a `NSEvent.addLocalMonitorForEvents(.leftMouseUp)` on the panel that maps the location the same way — note it in the body and re-verify.

- [ ] **Step 1: Write the hosting view**

`Sources/ThemeKit/HostingListView.swift`:

```swift
// ThemeKit — AppKit shell (floor #2: non-key popup + its mouse routing) that hosts
// the SwiftUI `ThemedListView` inside a combo/menu panel (#17b M3). It exists for
// ONE reason SwiftUI can't do in a non-key panel: fire the row-click commit on the
// SAME runloop tick as `mouseUp` (a SwiftUI tap can slip a tick and lose to the
// field editor's async blur reconcile). Hover is driven off a tracking area for the
// same non-key reason. All drawing/theming/data stay in the SwiftUI layer.
import AppKit
import SwiftUI
import ThemeKitUI

@MainActor
public final class HostingListView<ID: Hashable & Sendable>: NSHostingView<ThemedListView<ID>> {
    private weak var controller: ListController<ID>?
    private var tracking: NSTrackingArea?

    public init(controller: ListController<ID>, rootView: ThemedListView<ID>) {
        self.controller = controller
        super.init(rootView: rootView)
    }
    @available(*, unavailable) required init(rootView: ThemedListView<ID>) { fatalError() }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    // The panel is non-key; take the first click without a focus round-trip so the
    // combo's "type, then click a row" never eats the first mouseUp (mirrors
    // ThemedList.acceptsFirstMouse).
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override var acceptsFirstResponder: Bool { false }

    public override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let id = controller?.row(at: p) {
            controller?.fireActivate(id)      // SYNCHRONOUS — same tick as mouseUp
        } else {
            super.mouseUp(with: event)
        }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp],
                                owner: self, userInfo: nil)
        addTrackingArea(ta); tracking = ta
    }

    public override func mouseMoved(with event: NSEvent) {
        controller?.setHover(controller?.row(at: convert(event.locationInWindow, from: nil)))
    }
    public override func mouseExited(with event: NSEvent) { controller?.setHover(nil) }
}
```

- [ ] **Step 2: Verify build + commit**

Run: `swift build 2>&1 | pare --tail 15` — Expected: `Build complete!`

```bash
git add Sources/ThemeKit/HostingListView.swift
git commit -m ":sparkles: feat(ThemeKit): #17b M3 — HostingListView (AppKit mouseUp sync-commit + tracking hover) for popup-hosted ThemedListView"
```

---

## Task 4: Rewire `ThemedComboBox` onto the controller + `HostingListView`

**Files:**
- Modify: `Sources/ThemeKit/ThemedComboBox.swift`
- Modify: `Tests/ThemeKitTests/ThemedComboBoxTests.swift`

**Interfaces:**
- Consumes: `ListController<String>`, `HostingListView<String>`, `ThemedListView<String>`, `ThemedListStyle`.
- Produces: no public API change to `ThemedComboBox` (drop-in backend swap).

- [ ] **Step 1: Swap the stored list for the controller + hosting view**

Replace `private var list: ThemedList!` with:

```swift
    private let controller = ListController<String>()
    private var hosting: HostingListView<String>!
```

- [ ] **Step 2: Rebuild `ensurePanel`'s list install (lines ~546-567)**

Replace the `let l = ThemedList(...)` block through `container.addSubview(l)` with the controller config + hosting view. Map each old setter 1:1:

```swift
    controller.noOptionsText = noOptionsText
    controller.emptyActionRow = { [weak self] q in self?.emptyActionRow?(q) }
    controller.onActivate = { [weak self] id in self?.commitItem(id) }
    controller.onEmptyAction = { [weak self] _ in self?.fireEmptyAction() }
    controller.onHover = { [weak self] id in self?.pointerInPopup = (id != nil) }

    var style = ThemedListStyle()
    style.density = .comfortable
    style.selectionMode = .none              // combo owns the committed pick
    style.hoverStyle = .wash
    style.wrapsHighlight = true
    style.highlightFollowsHover = true
    style.showsDividers = false
    style.reservesLeadingImageColumn = false // option rows flush at leadingInset
    style.surfaceColor = listSurface
    style.hosted = true                      // AppKit mouseUp owns the click + hover
    controller.style = style

    let root = ThemedListView(controller: controller, style: style, palette: palette)
    let h = HostingListView(controller: controller, rootView: root)
    hosting = h
    container.addSubview(h)
```

- [ ] **Step 3: Map `syncList` (lines ~334-342) onto the controller**

```swift
    private func syncList() {
        controller.noOptionsText = noOptionsText
        controller.query = field.stringValue
        controller.items = filtered.map { ListItem(id: $0.id, primary: $0.label, isDisabled: isDisabled($0)) }
        rehostRoot()                    // re-render with the new items (see Step 5)
        syncPreviewHighlight()
    }
```

- [ ] **Step 4: Map `syncPreviewHighlight` + the `handle*` forwarders**

- `syncPreviewHighlight` (lines ~346-354): set `controller.previewHighlight` to `filtered[clamped].id`, or (empty + action active) a sentinel `nil` + let `isActionRowActive` drive, else `nil`. (No `ThemedList.emptyActionID` — the controller keys the action row off `isActionRowActive`.)
- `handleReturn` (line ~396): `if isActionRowActive || controller.highlightedID != nil { controller.activateHighlight() } else { dismissPopup() }`.
- `handleMoveDown`/`handleMoveUp` (410-419): `controller.clearHighlight()` on first open, `controller.moveHighlight(±1)`.
- `handleFocusChange` (373): `controller.clearHighlight()` on `opensOnFocus`.

Replace every remaining `list.` with `controller.` (or `hosting.` for the frame).

- [ ] **Step 5: Re-host on items change + map `reframe`'s list frame (line ~601)**

`NSHostingView` is value-rooted — after mutating `controller.items`/`query`, re-assign the root so SwiftUI re-renders:

```swift
    private func rehostRoot() {
        guard hosting != nil else { return }
        hosting.rootView = ThemedListView(controller: controller, style: controller.style, palette: palette)
    }
```

In `reframe`, replace `list.frame = container.bounds.insetBy(dx: 1, dy: 1)` with `hosting.frame = container.bounds.insetBy(dx: 1, dy: 1)`. The uniform-row sizing (`height = visibleRows × rowHeight + 2`) is unchanged — combo does not measure content.

- [ ] **Step 6: Migrate the combo test probe**

In `Tests/ThemeKitTests/ThemedComboBoxTests.swift`, the `listProbe` (and any `_axChildren`/`emptyActionID` assertions) read the old AppKit `ThemedList`. Re-vend an equivalent probe off the controller: expose a `@testable` accessor on `ThemedComboBox` (e.g. `var _controller: ListController<String> { controller }`) and rewrite each assertion to read `_controller.items`/`.highlightedID`/`.isActionRowActive`. Keep every behavior assertion (row count after filter, highlight after arrow, action-row presence) — do not drop coverage ([[sweep-include-tests]]).

- [ ] **Step 7: Run both gates**

Run: `swift build 2>&1 | pare --tail 15` — Expected: `Build complete!`
Run: `scripts/test.sh 2>&1 | pare` — Expected: full suite PASS (combo tests green on the new backend; ListCore/ThemeKit/ThemeKitUI untouched-count preserved).

- [ ] **Step 8: Commit**

```bash
git add Sources/ThemeKit/ThemedComboBox.swift Tests/ThemeKitTests/ThemedComboBoxTests.swift
git commit -m ":sparkles: feat(ThemeKit): #17b M3 — host ThemedComboBox drop-down on SwiftUI ThemedListView via ListController (AppKit list retired from combo)"
```

---

## Task 5: prism LIVE maintainer gate (the #1 risk) + finalize

**Files:** none (verification) — then furrow body + merge.

> This is the load-bearing gate the whole retire hinges on. A green `scripts/test.sh` does NOT prove the synchronous commit (mouse timing is prism-only, per the house rule). Do NOT claim M3 done off tests alone.

- [ ] **Step 1: Launch prism on the combo showcase** (prism recipe — `PRISM_CONFIG`, winid, `screencapture -l` without osascript activation). Find the `ThemedComboBoxView` cell / field showcase.

- [ ] **Step 2: Prove the load-bearing behaviors LIVE (maintainer eyeball):**
  - **Type, then click a row → commits** (value lands, popup closes, field keeps focus, NO revert) — the #1 sync-commit race.
  - Arrow ↑↓ moves the highlight; Return commits the highlighted row; Esc closes.
  - Hover highlights the row under the pointer (non-key panel hover works).
  - Filter narrows rows as you type; the actionable empty row (if wired) fires.
  - Dismiss on outside-click / Esc / blur.
  - Theme fidelity across a few catalog themes (wash + accent-bar highlight reads on neon).

- [ ] **Step 3: If a behavior regresses**, debug (systematic-debugging). Most likely: `mouseUp` not reaching `HostingListView` → switch to the panel-level `NSEvent` monitor fallback (Task 3 note). Re-verify.

- [ ] **Step 4: Update the furrow body** (`t-sb4c`) — check off M3, record what shipped + that measurement moved to M4, and name the next step (M4 menu host + measurement). `furrow sync` before/after.

- [ ] **Step 5: Merge gate.** Per [[chomp-push-gate]] + [[ci-green-merge-ok]], re-confirm "sill で確認済み？" ONCE (this milestone lands a live-verification-gated behavior change), then open the PR (footer `SetStatus-task: …/t-sb4c.md in-progress`), let CI go green, squash-merge. **No version tag** (tag lands at M5). `--delete-branch` may need a manual finish under the worktree layout.

---

## Self-Review

**Spec coverage (against `2026-06-23-17b-themedlist-swiftui-design.md` §6 + §7 milestone 3):**
- §7-3 "ListController + popup ホスト配線" → Tasks 1-4. ✔
- §6-1 non-key mouse hit-testing + `acceptsFirstMouse` → Task 3 (`acceptsFirstMouse=true`). ✔
- §6-2 synchronous row-click commit (AppKit `mouseUp`) → Task 3 `mouseUp`→`fireActivate`, Task 5 live gate. ✔
- §6-3 hover via NSEvent tracking (not `.onHover`) → Task 3 tracking area + `style.hosted` suppresses SwiftUI `.onHover`. ✔
- §6 combo filter reactive (`syncList` → `controller.items`) → Task 4 Step 3. ✔
- §6 dismissal transparent to swap (monitors/glue/Esc/fade at chrome level) → unchanged, confirmed. ✔
- **Deliberately deferred to M4** (documented in Global Constraints): `fittingWidth`/`contentHeight`/`rowRectOnScreen` (§6-4 submenu sizing/anchoring), `scrollRowVisible`→`ScrollViewReader`. Combo doesn't consume them (verified zero call sites). Menu (M4) does.
- **Out of scope** (later milestones): ThemedMenu host + submenu cascade = M4; AppKit `ThemedList.swift` deletion + `ThemedListTests.swift` = M5.

**Placeholder scan:** no TBD/"handle edge cases"/"similar to". The two intentionally-live-gated items (SwiftUI render in Task 2, `mouseUp` timing in Task 3/5) are called out with their proof path, not hidden.

**Type consistency:** `ListController` method/property names (`moveHighlight`/`activateHighlight`/`clearHighlight`/`highlightedID`/`isActionRowActive`/`row(at:)`/`fireActivate`/`setHover`/`rowRects`) are used identically across Tasks 1-4. `ThemedListStyle.hosted` added in Task 2, consumed in Task 4. `HostingListView(controller:rootView:)` signature matches Task 3 ↔ Task 4 Step 2.
