# #17b Milestone 2 — SwiftUI-native `ThemedListView` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the SwiftUI-native, generic `ThemedListView<ID>` in `ThemeKitUI` — the new *canonical* themed list/tree — replacing the 37-line `NSViewRepresentable` bridge, reproducing the AppKit `ThemedList`'s theming 1:1, and adding the net-new features the spec calls for (multi-select, animated collapse, SwiftUI-overlay drag ghost, standalone `.onKeyPress` keyboard).

**Architecture:** 3 layers, 1 brain (per design spec §1). `ListCore` (pure, generic, already shipped in M1) is the shared brain. The new `ThemedListView<ID>` (SwiftUI, `@MainActor`) draws hand-built themed rows from `ResolvedPalette` roles, projecting its image-bearing `ListItem<ID>` down to `ListCore.ListRow<ID>` so every selection/collapse/DnD decision routes through the already-tested pure functions. The AppKit `ThemedList` (2365 lines) and its 83-test suite stay **fully intact** — M2 is purely additive (new files + prism re-expression). AppKit widget retirement is M5; Combo/Menu popup re-hosting is M3/M4.

**Tech Stack:** Swift 6.3 / macOS 26 floor, SwiftUI + AppKit (`@MainActor`), `ScrollView { LazyVStack(pinnedViews: .sectionHeaders) }`, `ListCore` pure generic functions, `ResolvedPalette` role colors, XCTest (CI-only) + prism live-visual gate.

## Global Constraints

- **macOS 26 floor** — `Package.swift` already `.macOS("26.0")` (t-tbar shipped, v2.0.0). No availability gates / fallbacks needed. `@Observable`, `.onKeyPress`, `.pinnedViews`, `ScrollViewReader`, `.onScrollGeometryChange` all unconditionally available.
- **House widget rules** — `public struct` + explicit `public init` (SwiftUI memberwise init is `internal`); **CLT-safe** (NO `#Preview` — breaks the CLT build); deterministic preview seam (`preview` param / frozen idiom); theme only via `ResolvedPalette` role fields (`background · foreground · muted · tertiary · primary · secondary · border · hover · selection · error` + `backgroundAlpha`, `backgroundMode`). Accent affordance = `primary`. Pre-1.0 so breaking API is OK.
- **AppKit-scope policy (床3個)** — widgets are SwiftUI by default; AppKit only for the 3 floors (IME field editor / non-activating panel shell / selectable rich-text). M2 **removes** AppKit surface (the `DragGhost` child window becomes a SwiftUI overlay) and adds **zero** new AppKit. If any element seems to need new AppKit → STOP and 要相談 ([[appkit-scope-is-the-hard-gate]]).
- **Do NOT touch the AppKit `ThemedList` internals.** `Sources/ThemeKit/ThemedList.swift`, its ~15 DEBUG seams, and `ThemedList.emptyActionID` are load-bearing for 83 `ThemedListTests` + `ThemedComboBoxTests` + `ThemedMenuTests` that must stay green through M2 (they're deleted/updated in M4/M5, not M2). No renames, no "cleanup," no moving logic into it.
- **`swift build` (CLT) + `scripts/test.sh` (Xcode XCTest) green before every commit.** SwiftUI *render* is NOT unit-testable — logic/pure seams are TDD'd in XCTest; rendering + animation + interaction are proven **live in prism** (recall #17f: GFM table passed tests but rendered blank; caught only in prism). Every render task ends with an explicit prism gate.
- **Route through ListCore, don't re-implement.** `MultiSelection` (`resolveClick`/`extendByKey`/`selectAll`/`rangeIDs`) and `SectionCollapse` (`toggleSection`/`flattenVisible`) have full ListCore test coverage but **zero current consumer** — M2 is their first. Hand-rolling selection/collapse in the view would leave those tests green but non-protective (silent coverage gap). Same for `resolveDropTarget`/`dragCandidates`/`chunkMemberIDs`/`stickyHeader`/`nextHighlight`.

---

## Reference: the fidelity source of truth

**Render map** — the 1:1 metric table for every visual element (both densities), the per-row draw order, and the exact `ResolvedPalette` role behind each fill, was extracted from `Sources/ThemeKit/ThemedList.swift` and is reproduced in §"Metrics" below. When implementing a decoration, match these numbers exactly and cross-check the cited `ThemedList.swift` line range.

**Design spec:** [`2026-06-23-17b-themedlist-swiftui-design.md`](../specs/2026-06-23-17b-themedlist-swiftui-design.md) (§2 API, §3 rendering, §4 interaction, §5 ListCore additions, §6 popup migration = M3/M4).

### Metrics (both densities — reproduce exactly; source `ThemedList.swift:471-510`)

| constant | comfortable | compact | drives |
|---|---|---|---|
| `singleRow` | 30 | 26 | 1-line row height |
| `twoLineRow` | 46 | 40 | 2-line row height |
| `header1` | 28 | 24 | 1-line header height |
| `header2` | 40 | 40 | 2-line header height (compact NOT shrunk) |
| `leadingInset` | 12 | 10 | left edge of content / image box |
| `trailingInset` | 12 | 10 | right edge of trailing cluster |
| `imageBox` | 24 | 20 | leading image reservation (colour favicon side) |
| `iconGlyph` | 18 | 16 | template glyph side (centred in imageBox) |
| `gapImageToText` | 8 | 6 | image→text gap |
| `twoLineTop` | 8 | 6 | top pad of primary line in a 2-line row |
| `lineGap` | 2 | 2 | gap between the two text lines |
| `accentBar` | 3 | 3 | tint bar + selection accent bar width |
| `roundedRadius` | `Radius.md`=6 | 6 | rounded selection pill + outline ring + onto-ring |
| `roundedHInset` | 3 | 3 | horizontal inset of the rounded selection pill |
| `badgeHeight` | 16 | 14 | badge pill height + custom-accessory height |
| `badgeHPad` | 6 | 6 | badge horizontal text padding |
| `badgeSymbolPt` | 11 | 11 | badge leading-symbol box |
| `badgeGap` | 4 | 4 | gap between adjacent badges |
| `chevronPt` | 11 | 10 | chevron glyph box + width |
| `shortcutHeight` | 16 | 14 | shortcut lozenge height |
| `shortcutHPad` | 5 | 5 | shortcut horizontal padding |
| `shortcutRadius` | `Radius.sm`=4 | 4 | shortcut lozenge corner radius |
| `clusterGap` | 6 | 6 | gap between non-badge trailing pieces / grip reserve |
| `budgetMargin` | 8 | 8 | extra margin between text budget and trailing cluster |
| `separatorBand` | 9 | 7 | separator row height (hairline centred) |
| `indentStep` | 16 | 14 | per-indent-level horizontal shift |
| `disclosurePt` | 11 | 10 | disclosure triangle glyph box |
| `disclosureGap` | 5 | 5 | gap after disclosure triangle |
| `textXOrigin` (computed) | 12+24+8=**44** | 10+20+6=**36** | text x when image column reserved |
| `disclosureGutter` (computed) | 11+5=**16** | 10+5=**15** | header title left-shift when collapsible |

Fonts (`Palette.TypeRole`, family follows `palette.uiFont(role)`): `.body` 13/regular (primary), `.secondaryBody` 11/medium (2nd line, mono-forced when `secondaryMono`), `.caption` 11/regular (2-line-header subtitle), `.sectionHeader` 11/semibold (1-line header, **uppercased, kern 0.5**), `.sectionTitle` 13/medium (2-line-header title), `.badge` 10/medium, `.shortcut` 10/medium. `Radius`: xs=2 · sm=4 · md=6 · lg=8 · xl=12.

**Per-row draw order** (`ThemedList.swift:1145-1222`): 1 zebra (full-bleed) → 2 tint bar (x=0, w=3) → 3 selection/highlight fill → 4 hover veil → 5 outline ring → 6 leading image → 7 text stack → 8 trailing cluster (right-to-left) → 9 divider. **Full-bleed vs indent:** zebra / tint bar / selection+hover fill / header punch fill are **x=0, full width** (NOT indented — MUI tree model, `:1151`); only *content* (image/text/disclosure) indents by `indentLevel * indentStep`.

Key fills (all solid, no CIFilter/CALayer/blend): zebra = `palette.hover @ 0.4` (opaque surface only, parity resets per section); tint bar = `resolvedTint(item.tint)` (`.primary/.secondary/.error/.custom(hex)`); selection wash = `palette.selection` (default primary@0.18) + 3pt `primary` bar (bar omitted when `roundedSelection`, the pill IS the affordance); `solidAccent` = opaque `palette.primary` fill, text→`onPrimary`; hover veil = `palette.hover` over the same pill/rect path; outline ring = `primary` stroke, `insetBy(1.5,1.5)`, `lineWidth 1.5`, radius md; dividers/separators/header-underline = `palette.border` 1pt; badge fill = role@0.16 wash, ink = full role color (onAccent → `onPrimary(0.18)`/`onPrimary(1)`); shortcut lozenge = `border` stroke + `muted` text; chevron = `tertiary`; disclosure caret = `muted` (**2-glyph swap today → M2 replaces with 1 caret + `.rotationEffect`**); reorder grip = `tertiary` 2×3 dots (headers only). Template image = `.renderingMode(.template).foregroundColor(...)` (= AppKit `.sourceAtop` tint, `isTemplate == true`, tint `foreground` or `onPrimary(1)` onAccent); colour favicon (`isTemplate == false`) draws as-is (no knockout).

---

## File Structure

**New files (all `Sources/ThemeKitUI/`):**
- `ListItem.swift` — generic `public struct ListItem<ID: Hashable & Sendable>` (image-bearing row model, owned here — carries `NSImage` so it can't live in pure `ListCore`), its nested `Kind`, `var asRow: ListCore.ListRow<ID>` projection, and static `visibleRows`/`selectableIDs` helpers. Reuses ThemeKit's `Badge`/`TrailingAccessory`/`ListTint`/`BadgeRole` value types (ThemeKitUI already depends on ThemeKit).
- `ListStyle.swift` — `public struct ListStyle` config value type + the `Density`/`SelectionMode`/`HoverStyle`/`HighlightStyle` enums (fresh, module-level in ThemeKitUI — NOT reused from ThemeKit's `ThemedList`-nested ones, which die at M5) + `ListMetrics` (the density-keyed constants above, pure).
- `ThemedListView.swift` — **replaces** the 37-line bridge. `public struct ThemedListView<ID>: View` + `public init` + `ListPreview<ID>` frozen seam. Composes the row/decoration/section subviews.
- `ThemedListRow.swift` — the per-row SwiftUI subview (text stack, leading image, trailing cluster, background decorations). Split from `ThemedListView.swift` so each file holds one focused responsibility.
- `ThemedListDrag.swift` — the drag gesture + drop-affordance overlays + SwiftUI overlay ghost (Stage M2c). Separate file: drag is opt-in and self-contained.

**Modified files:**
- `Sources/prism/ListShowcase.swift` — re-express all 11 cells against the new API + qualify `ThemeKitUI.ListItem`.
- `Sources/prism/MenuShowcase.swift` — re-express the inline list mock (the live `ThemedMenuTriggerView` trigger stays on AppKit `ThemedMenu` until M4).
- `Tests/ThemeKitUITests/` — add `ListItemProjectionTests.swift`, `ListStyleMetricsTests.swift`, `ListSelectionRoutingTests.swift` (headless, ListCore-backed; SwiftUI render stays prism-only).

**Untouched (must stay green):** `Sources/ThemeKit/ThemedList.swift` + all its tests; `ThemedComboBox`/`ThemedMenu` + tests; `Sources/ListCore/*` (consumed as-is — measurement functions are M3, not needed for M2's self-sizing `ScrollView`).

### Naming-collision decision (deliberate, temporary)
`ListItem` will exist in **both** `ThemeKit` (String-keyed, AppKit widget's) and `ThemeKitUI` (generic, new). prism imports both → the bare name is ambiguous, so prism qualifies **`ThemeKitUI.ListItem`** in the list/menu showcases. The shared value types (`Badge`, `TrailingAccessory`, `ListTint`, `BadgeRole`) are defined only in ThemeKit → stay unqualified. This friction is intentional and vanishes at M5 when `ThemeKit.ListItem` is deleted. (Rejected alt: renaming the new type — the spec mandates `ListItem<ID>`; a temporary qualifier is cheaper than a rename churn.)

---

## Staging

M2 is large, so it ships in **3 stages**, each independently `swift build` + `scripts/test.sh` + prism green (a shippable, reviewable increment per [[ci-green-merge-ok]]):

- **M2a (Tasks 1–9): rendering + single-select + hover.** The new view draws every theme 1:1 (static), single-select, hover, zebra, dividers, badges, indent, section headers + sticky. Re-express the non-drag/non-collapse cells (1,2,3,9,10,11 + menu mock). **Ship.**
- **M2b (Tasks 10–12): animated collapse + multi-select + standalone keyboard.** Net-new `.multiple` mode, caret rotation + row-diff animation, `.onKeyPress` nav. **Ship.**
- **M2c (Tasks 13–16): drag/reorder + SwiftUI-overlay ghost.** DragGesture, drop affordances, overlay ghost (replaces the AppKit child window), keyboard drag. Re-express drag cells (4,5,6,7). **Ship = M2 complete → tag deferred to M5.**

**Irreversibility note:** none of M2 crosses the prism-live *gate* that blocks M3 (combo sync commit) / M5 (AppKit delete). M2 is additive and reversible (the AppKit widget stays), so [[ci-green-merge-ok]] applies per stage. Still run the prism gate each stage — it's the only proof the SwiftUI render is correct.

---

## STAGE M2a — rendering + single-select + hover

### Task 1: Generic `ListItem<ID>` + `asRow` projection + visibility helpers

**Files:**
- Create: `Sources/ThemeKitUI/ListItem.swift`
- Test: `Tests/ThemeKitUITests/ListItemProjectionTests.swift`

**Interfaces:**
- Consumes: `ListCore.ListRow`, `ListCore.RowKind`, `ListCore.flattenVisible`, `ListCore.SelectMods` (generic, shipped M1); ThemeKit `Badge`, `TrailingAccessory`, `ListTint` (value types).
- Produces: `public struct ListItem<ID: Hashable & Sendable>` with fields `id, image: NSImage?, primary, secondary, secondaryMono, badges: [Badge], trailing: TrailingAccessory, tint: ListTint, kind: Kind, isDisabled, indentLevel, axChecked`; nested `public enum Kind { case row; case sectionHeader(subtitle: String? = nil, collapsed: Bool? = nil); case separator }`; `var asRow: ListRow<ID>`; `static func visibleRows(_ items: [ListItem<ID>], collapsed: Set<ID>) -> [ListItem<ID>]`; `static func selectableIDs(_ items: [ListItem<ID>]) -> [ID]`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import ThemeKit          // Badge, TrailingAccessory, ListTint
@testable import ThemeKitUI

final class ListItemProjectionTests: XCTestCase {
    private func item(_ id: String, kind: ListItem<String>.Kind = .row,
                      disabled: Bool = false, indent: Int = 0) -> ListItem<String> {
        ListItem(id: id, primary: id, kind: kind, isDisabled: disabled, indentLevel: indent)
    }

    func testAsRowMapsKindDisabledIndent() {
        let header = item("h", kind: .sectionHeader(subtitle: "2", collapsed: true), indent: 1)
        XCTAssertEqual(header.asRow.id, "h")
        XCTAssertTrue(header.asRow.isHeader)
        XCTAssertEqual(header.asRow.headerCollapsed, true)
        XCTAssertTrue(header.asRow.isCollapsibleHeader)
        XCTAssertEqual(header.asRow.indentLevel, 1)

        let disabledRow = item("d", disabled: true)
        XCTAssertFalse(disabledRow.asRow.isSelectable)      // disabled ⇒ not selectable

        let sep = item("s", kind: .separator)
        XCTAssertTrue(sep.asRow.isSeparator)
        XCTAssertFalse(sep.asRow.isSelectable)
    }

    func testSelectableIDsFiltersHeadersSeparatorsDisabled() {
        let items = [item("h", kind: .sectionHeader()), item("a"),
                     item("b", disabled: true), item("s", kind: .separator), item("c")]
        XCTAssertEqual(ListItem.selectableIDs(items), ["a", "c"])
    }

    func testVisibleRowsDropsCollapsedBodies() {
        // collapsed header "h" keeps the header, drops rows until the next header
        let items = [item("h", kind: .sectionHeader(collapsed: true)), item("a"), item("b"),
                     item("h2", kind: .sectionHeader()), item("c")]
        let visible = ListItem.visibleRows(items, collapsed: ["h"]).map(\.id)
        XCTAssertEqual(visible, ["h", "h2", "c"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/test.sh` (or `DEVELOPER_DIR=…/Xcode.app/Contents/Developer swift test --filter ListItemProjectionTests`)
Expected: FAIL — `ListItem` / `ThemeKitUITests` target members not found.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ThemeKitUI/ListItem.swift
import AppKit
import ThemeKit          // Badge, TrailingAccessory, ListTint, BadgeRole
import ListCore

/// The render-bearing row model owned by ThemeKitUI (carries NSImage, so it can't
/// live in the pure/Sendable `ListCore`). Projects to `ListCore.ListRow` — the
/// pure shadow every selection/collapse/DnD core reasons over.
public struct ListItem<ID: Hashable & Sendable> {
    public enum Kind: Equatable {
        case row
        case sectionHeader(subtitle: String? = nil, collapsed: Bool? = nil)
        case separator
    }

    public let id: ID
    public var image: NSImage?
    public var primary: String
    public var secondary: String?
    public var secondaryMono: Bool
    public var badges: [Badge]
    public var trailing: TrailingAccessory
    public var tint: ListTint
    public var kind: Kind
    public var isDisabled: Bool
    public var indentLevel: Int
    public var axChecked: Bool

    public init(id: ID, image: NSImage? = nil, primary: String,
                secondary: String? = nil, secondaryMono: Bool = false,
                badges: [Badge] = [], trailing: TrailingAccessory = .none,
                tint: ListTint = .none, kind: Kind = .row, isDisabled: Bool = false,
                indentLevel: Int = 0, axChecked: Bool = false) {
        self.id = id; self.image = image; self.primary = primary
        self.secondary = secondary; self.secondaryMono = secondaryMono
        self.badges = badges; self.trailing = trailing; self.tint = tint
        self.kind = kind; self.isDisabled = isDisabled
        self.indentLevel = indentLevel; self.axChecked = axChecked
    }

    /// Pure shadow — the cores never see NSImage.
    public var asRow: ListRow<ID> {
        let rowKind: RowKind
        switch kind {
        case .row:                              rowKind = .row
        case let .sectionHeader(subtitle, collapsed):
                                                rowKind = .sectionHeader(subtitle: subtitle, collapsed: collapsed)
        case .separator:                        rowKind = .separator
        }
        return ListRow(id: id, kind: rowKind, isDisabled: isDisabled, indentLevel: indentLevel)
    }

    /// The rows the renderer + every core see as "visible" — collapsed sections drop
    /// their bodies. Delegates to the single canonical `ListCore.flattenVisible`.
    public static func visibleRows(_ items: [ListItem<ID>], collapsed: Set<ID>) -> [ListItem<ID>] {
        let visibleIDs = Set(flattenVisible(rows: items.map(\.asRow), collapsed: collapsed).map(\.id))
        return items.filter { visibleIDs.contains($0.id) }
    }

    /// Selectable id order (headers / separators / disabled excluded) — the ordered
    /// domain every MultiSelection / nextHighlight call operates on.
    public static func selectableIDs(_ items: [ListItem<ID>]) -> [ID] {
        items.filter { $0.asRow.isSelectable }.map(\.id)
    }
}
```

Add the test target to `Package.swift` if not present: `ThemeKitUITests` already exists (`PillLogicTests`) with deps `["ThemeKitUI", "PaletteKit", "Palette"]` — add `"ThemeKit"` and `"ListCore"` to its deps so the test can import `Badge`/`ListCore`.

- [ ] **Step 4: Run test to verify it passes**

Run: `scripts/test.sh` (filter `ListItemProjectionTests`)
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ThemeKitUI/ListItem.swift Tests/ThemeKitUITests/ListItemProjectionTests.swift Package.swift
git commit -m ":sparkles: feat(ThemeKitUI): #17b M2 — generic ListItem<ID> + asRow projection + visibility helpers"
```

### Task 2: `ListStyle` config + `ListMetrics` density constants + enums

**Files:**
- Create: `Sources/ThemeKitUI/ListStyle.swift`
- Test: `Tests/ThemeKitUITests/ListStyleMetricsTests.swift`

**Interfaces:**
- Consumes: `ListCore.DragMode`.
- Produces: `public enum Density { case comfortable, compact }`, `public enum SelectionMode { case none, single, multiple }`, `public enum HoverStyle { case wash, solidAccent }`, `public enum HighlightStyle { case fill, outline }`; `public struct ListStyle` (all config fields, defaulted); `public struct ListMetrics` with `static func forDensity(_:) -> ListMetrics` returning the exact constants above; consumed by `ThemedListView`/`ThemedListRow`.

- [ ] **Step 1: Write the failing test** — pin the fidelity numbers so a later "cleanup" can't silently drift them.

```swift
import XCTest
import ListCore
@testable import ThemeKitUI

final class ListStyleMetricsTests: XCTestCase {
    func testComfortableMetrics() {
        let m = ListMetrics.forDensity(.comfortable)
        XCTAssertEqual(m.singleRow, 30);  XCTAssertEqual(m.twoLineRow, 46)
        XCTAssertEqual(m.header1, 28);    XCTAssertEqual(m.header2, 40)
        XCTAssertEqual(m.leadingInset, 12); XCTAssertEqual(m.imageBox, 24)
        XCTAssertEqual(m.iconGlyph, 18);  XCTAssertEqual(m.indentStep, 16)
        XCTAssertEqual(m.separatorBand, 9)
        XCTAssertEqual(m.textXOrigin, 44)          // 12 + 24 + 8
        XCTAssertEqual(m.disclosureGutter, 16)     // 11 + 5
    }
    func testCompactMetrics() {
        let m = ListMetrics.forDensity(.compact)
        XCTAssertEqual(m.singleRow, 26);  XCTAssertEqual(m.twoLineRow, 40)
        XCTAssertEqual(m.header1, 24);    XCTAssertEqual(m.header2, 40)   // header2 NOT shrunk
        XCTAssertEqual(m.leadingInset, 10); XCTAssertEqual(m.imageBox, 20)
        XCTAssertEqual(m.indentStep, 14); XCTAssertEqual(m.separatorBand, 7)
        XCTAssertEqual(m.textXOrigin, 36)          // 10 + 20 + 6
        XCTAssertEqual(m.disclosureGutter, 15)     // 10 + 5
    }
    func testDefaultStyle() {
        let s = ListStyle()
        XCTAssertEqual(s.density, .comfortable)
        XCTAssertEqual(s.selectionMode, .single)
        XCTAssertFalse(s.draggable)
        XCTAssertTrue(s.reservesLeadingImageColumn)
        XCTAssertEqual(s.backgroundAlpha, 1)
    }
}
```

- [ ] **Step 2: Run to verify fail** — `scripts/test.sh` (filter `ListStyleMetricsTests`) → FAIL (types missing).

- [ ] **Step 3: Implement** `Sources/ThemeKitUI/ListStyle.swift`:

```swift
import AppKit
import ListCore

public enum Density: Equatable { case comfortable, compact }
public enum SelectionMode: Equatable { case none, single, multiple }   // .multiple NEW (M2b)
public enum HoverStyle: Equatable { case wash, solidAccent }
public enum HighlightStyle: Equatable { case fill, outline }

public struct ListStyle {
    public var density: Density = .comfortable
    public var selectionMode: SelectionMode = .single
    public var hoverStyle: HoverStyle = .wash
    public var highlightStyle: HighlightStyle = .fill
    public var roundedSelection: Bool = false
    public var showsDividers: Bool = false
    public var zebra: Bool = false                     // was `alternatingRowBackground`
    public var horizontalContentScroll: Bool = false
    public var reservesLeadingImageColumn: Bool = true
    public var wrapsHighlight: Bool = false
    public var highlightFollowsHover: Bool = false
    public var vendsRowAXElements: Bool = false
    public var surfaceColor: NSColor? = nil
    public var backgroundAlpha: CGFloat = 1            // parity-PLUS (design ⑤)
    // drag config (M2c)
    public var draggable: Bool = false
    public var dragMode: DragMode = .both
    public var showsReorderGrip: Bool = true

    public init() {}
}

public struct ListMetrics {
    public let singleRow, twoLineRow, header1, header2: CGFloat
    public let leadingInset, trailingInset, imageBox, iconGlyph, gapImageToText: CGFloat
    public let twoLineTop, lineGap, accentBar, roundedHInset: CGFloat
    public let badgeHeight, badgeHPad, badgeSymbolPt, badgeGap: CGFloat
    public let chevronPt, shortcutHeight, shortcutHPad, clusterGap, budgetMargin: CGFloat
    public let separatorBand, indentStep, disclosurePt, disclosureGap: CGFloat
    public var roundedRadius: CGFloat { 6 }            // Radius.md
    public var shortcutRadius: CGFloat { 4 }           // Radius.sm
    public var textXOrigin: CGFloat { leadingInset + imageBox + gapImageToText }
    public var disclosureGutter: CGFloat { disclosurePt + disclosureGap }

    public static func forDensity(_ d: Density) -> ListMetrics {
        switch d {
        case .comfortable:
            return ListMetrics(singleRow: 30, twoLineRow: 46, header1: 28, header2: 40,
                leadingInset: 12, trailingInset: 12, imageBox: 24, iconGlyph: 18, gapImageToText: 8,
                twoLineTop: 8, lineGap: 2, accentBar: 3, roundedHInset: 3,
                badgeHeight: 16, badgeHPad: 6, badgeSymbolPt: 11, badgeGap: 4,
                chevronPt: 11, shortcutHeight: 16, shortcutHPad: 5, clusterGap: 6, budgetMargin: 8,
                separatorBand: 9, indentStep: 16, disclosurePt: 11, disclosureGap: 5)
        case .compact:
            return ListMetrics(singleRow: 26, twoLineRow: 40, header1: 24, header2: 40,
                leadingInset: 10, trailingInset: 10, imageBox: 20, iconGlyph: 16, gapImageToText: 6,
                twoLineTop: 6, lineGap: 2, accentBar: 3, roundedHInset: 3,
                badgeHeight: 14, badgeHPad: 6, badgeSymbolPt: 11, badgeGap: 4,
                chevronPt: 10, shortcutHeight: 14, shortcutHPad: 5, clusterGap: 6, budgetMargin: 8,
                separatorBand: 7, indentStep: 14, disclosurePt: 10, disclosureGap: 5)
        }
    }
}
```

- [ ] **Step 4: Run to verify pass** — `scripts/test.sh` (filter `ListStyleMetricsTests`) → PASS.
- [ ] **Step 5: Commit** — `:sparkles: feat(ThemeKitUI): #17b M2 — ListStyle config + ListMetrics density constants`.

### Task 3: `ThemedListView<ID>` shell + text-only rows (replace the bridge, prove it draws)

> Prove-it-draws step first (the #17f lesson: a green build ≠ visible rows). Wire ONE prism cell and screenshot before adding any decoration.

**Files:**
- Create: `Sources/ThemeKitUI/ThemedListView.swift` (replaces the 37-line bridge — delete the old body), `Sources/ThemeKitUI/ThemedListRow.swift`
- Modify: `Sources/prism/ListShowcase.swift` (cell 3 "dense" only, temporarily, to smoke-test)

**Interfaces:**
- Consumes: `ListItem<ID>`, `ListStyle`, `ListMetrics`, `ResolvedPalette`, `ListItem.visibleRows`.
- Produces: `public struct ThemedListView<ID: Hashable & Sendable>: View` with `public init(items:selection:expanded:highlight:style:palette:onActivate:onSelectionChange:onToggleSection:onHover:onDrop:onEmptyAction:emptyActionRow:query:noOptionsText:preview:)` (all but `items`/`palette` defaulted); `public struct ListPreview<ID: Hashable & Sendable>` (frozen `selection: Set<ID>`, `highlight: ID?`, `scrollX/scrollY: CGFloat?`, `dragSource: ID?`, `dropTarget: DropTarget<ID>?`, `dragChunk: [ID]?`, all defaulted nil/empty).

- [ ] **Step 1: Implement the view shell** (no failing-test step — SwiftUI render is prism-gated, not XCTest-gated; the pure seams it calls are already tested in Tasks 1–2). Full initial body:

```swift
// Sources/ThemeKitUI/ThemedListView.swift  (REPLACES the 37-line NSViewRepresentable bridge)
import SwiftUI
import AppKit
import PaletteKit
import ThemeKit          // shared value types (Badge/TrailingAccessory/ListTint); NOT the AppKit widget
import ListCore

public struct ListPreview<ID: Hashable & Sendable> {
    public var selection: Set<ID>
    public var highlight: ID?
    public var scrollX: CGFloat?
    public var scrollY: CGFloat?
    public var dragSource: ID?
    public var dropTarget: DropTarget<ID>?
    public var dragChunk: [ID]?
    public init(selection: Set<ID> = [], highlight: ID? = nil, scrollX: CGFloat? = nil,
                scrollY: CGFloat? = nil, dragSource: ID? = nil,
                dropTarget: DropTarget<ID>? = nil, dragChunk: [ID]? = nil) {
        self.selection = selection; self.highlight = highlight
        self.scrollX = scrollX; self.scrollY = scrollY; self.dragSource = dragSource
        self.dropTarget = dropTarget; self.dragChunk = dragChunk
    }
}

public struct ThemedListView<ID: Hashable & Sendable>: View {
    let items: [ListItem<ID>]
    @Binding var selection: Set<ID>
    @Binding var expanded: Set<ID>        // collapsed-section set (id ∈ set ⇒ collapsed)
    @Binding var highlight: ID?
    let style: ListStyle
    let palette: ResolvedPalette
    var onActivate: (ID) -> Void
    var onSelectionChange: (Set<ID>) -> Void
    var onToggleSection: (ID) -> Void
    var onHover: (ID?) -> Void
    var onDrop: (DragContext<ID>, DropTarget<ID>) -> Void
    var onEmptyAction: (String) -> Void
    var emptyActionRow: ((String) -> String?)?
    var query: String
    var noOptionsText: String
    var preview: ListPreview<ID>?

    public init(items: [ListItem<ID>],
                selection: Binding<Set<ID>> = .constant([]),
                expanded: Binding<Set<ID>> = .constant([]),
                highlight: Binding<ID?> = .constant(nil),
                style: ListStyle = ListStyle(),
                palette: ResolvedPalette,
                onActivate: @escaping (ID) -> Void = { _ in },
                onSelectionChange: @escaping (Set<ID>) -> Void = { _ in },
                onToggleSection: @escaping (ID) -> Void = { _ in },
                onHover: @escaping (ID?) -> Void = { _ in },
                onDrop: @escaping (DragContext<ID>, DropTarget<ID>) -> Void = { _, _ in },
                onEmptyAction: @escaping (String) -> Void = { _ in },
                emptyActionRow: ((String) -> String?)? = nil,
                query: String = "", noOptionsText: String = "No options",
                preview: ListPreview<ID>? = nil) {
        self.items = items; self._selection = selection; self._expanded = expanded
        self._highlight = highlight; self.style = style; self.palette = palette
        self.onActivate = onActivate; self.onSelectionChange = onSelectionChange
        self.onToggleSection = onToggleSection; self.onHover = onHover; self.onDrop = onDrop
        self.onEmptyAction = onEmptyAction; self.emptyActionRow = emptyActionRow
        self.query = query; self.noOptionsText = noOptionsText; self.preview = preview
    }

    private var metrics: ListMetrics { .forDensity(style.density) }
    private var visible: [ListItem<ID>] { ListItem.visibleRows(items, collapsed: effectiveExpanded) }
    // preview freezes state for a deterministic static shot; else use the live bindings
    private var effectiveExpanded: Set<ID> { expanded }
    private var effectiveSelection: Set<ID> { preview?.selection ?? selection }
    private var effectiveHighlight: ID? { preview?.highlight ?? highlight }

    public var body: some View {
        ScrollView([style.horizontalContentScroll ? [.horizontal, .vertical] : .vertical].reduce(into: Axis.Set()) { $0.formUnion($1) }) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(visible, id: \.id) { item in
                    ThemedListRow(item: item, metrics: metrics, style: style, palette: palette,
                                  isSelected: effectiveSelection.contains(item.id),
                                  isHighlighted: effectiveHighlight == item.id)
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(surfaceBackground)
    }

    @ViewBuilder private var surfaceBackground: some View {
        let surface = style.surfaceColor ?? palette.background
        if let surface, surface.alphaComponent >= 1 {
            Color(nsColor: surface)
        } else {
            Color.clear          // vibrancy / translucent — host's material shows through
        }
    }
}
```

> Section-header pinning (`Section { }` with `pinnedViews`) is wired in Task 7; for this smoke step rows render flat.

```swift
// Sources/ThemeKitUI/ThemedListRow.swift  (text-only for Task 3; decorations added Tasks 4-6)
import SwiftUI
import AppKit
import PaletteKit
import ThemeKit
import ListCore

struct ThemedListRow<ID: Hashable & Sendable>: View {
    let item: ListItem<ID>
    let metrics: ListMetrics
    let style: ListStyle
    let palette: ResolvedPalette
    let isSelected: Bool
    let isHighlighted: Bool

    private var rowHeight: CGFloat {
        switch item.kind {
        case .separator: return metrics.separatorBand
        case .sectionHeader(let sub, _): return sub == nil ? metrics.header1 : metrics.header2
        case .row: return item.secondary == nil ? metrics.singleRow : metrics.twoLineRow
        }
    }
    private var contentLeadingX: CGFloat {
        let base = style.reservesLeadingImageColumn ? metrics.textXOrigin : metrics.leadingInset
        return base + CGFloat(max(0, item.indentLevel)) * metrics.indentStep
    }

    var body: some View {
        // TEXT-ONLY placeholder — decorations land in Tasks 4-7.
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: metrics.lineGap) {
                Text(item.primary)
                    .font(Font(palette.uiFont(.body)))
                    .foregroundColor(Color(nsColor: palette.foreground))
                if let secondary = item.secondary {
                    Text(secondary)
                        .font(Font(palette.uiFont(item.secondaryMono ? .secondaryBody : .secondaryBody)))
                        .foregroundColor(Color(nsColor: palette.muted))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, contentLeadingX)
        .padding(.trailing, metrics.trailingInset)
        .frame(height: rowHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 2: Temporarily wire prism cell 3** to the new API (constant bindings + preview) to smoke-test — full cell-3 re-expression lands in Task 9, this is just proof-of-draw:

```swift
// ListShowcase.swift cell 3 — TEMP smoke wiring
cell("dense · compact · menu-style") {
    ThemedListView(items: denseItems(),
                   style: { var s = ListStyle(); s.density = .compact; return s }(),
                   palette: p,
                   preview: ListPreview(highlight: "copy"))
        .frame(width: 220, height: 188)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: p.border), lineWidth: 1))
}
```
(`denseItems()` return type becomes `[ThemeKitUI.ListItem<String>]` — see Task 9 for the full prism migration; for the smoke test, qualify this one builder.)

- [ ] **Step 3: Build + prism live proof**

Run: `swift build` → green. Then launch prism per the bench recipe ([[prism-bench]]): `.build/debug/prism` with `PRISM_CONFIG`, flip to the List tab, `screencapture -l<winid>` cell 3.
Expected: the dense list draws its 6 rows of primary text at the right heights (compact 26pt). **If rows are blank → STOP and debug the ScrollView/LazyVStack/frame before proceeding** (the #17f failure mode).

- [ ] **Step 4: Commit** — `:sparkles: feat(ThemeKitUI): #17b M2 — ThemedListView<ID> shell + text-only rows (replaces bridge)`.

### Task 4: Row background decorations — surface/zebra/selection/hover/outline

**Files:** Modify `Sources/ThemeKitUI/ThemedListRow.swift` (add a `.background` decoration layer behind the content).

**Interfaces:** Consumes `ListMetrics`, `ListStyle`, `ResolvedPalette` roles, `isSelected`/`isHighlighted`/`isHovered`. Produces the full-bleed decoration stack matching the draw order (zebra → tint bar → selection fill+bar/pill → hover veil → outline ring).

- [ ] **Step 1: Implement** the decoration `.background`. Key points (match Metrics + roles exactly):
  - Zebra: only when `style.zebra && surface opaque && !isSelected && zebraParity(item)`; fill `Color(nsColor: palette.hover.withAlphaComponent(0.4))`, full-bleed (x=0..width). Parity = ordinal among `.row`s, **resetting to 0 at each header** — compute a `[ID: Bool]` parity map in `ThemedListView` (mirror `ThemedList.swift:670-682`) and pass the bool in.
  - Tint bar: `Rectangle().frame(width: metrics.accentBar)` at leading x=0, color `resolvedTint(item.tint, palette:)` (helper: `.none→.clear/.primary→palette.primary/.secondary→palette.secondary/.error→palette.error/.custom(hex)→Color(hex)`), suppressed under `solidAccent` selection.
  - Selection: `selectionShape` = `style.roundedSelection ? RoundedRectangle(cornerRadius: metrics.roundedRadius).inset(by: … dx:roundedHInset) : Rectangle()`. Fill `palette.selection` (or opaque `palette.primary` when `hoverStyle == .solidAccent`); when NOT rounded, also draw the 3pt `primary` accent bar at x=0.
  - Hover veil: when `hoverStyle == .wash && isHovered && isSelected`, fill `palette.hover` over the same `selectionShape`.
  - Outline ring: when `isHighlighted && style.highlightStyle == .outline`, `selectionShape.inset(1.5).stroke(palette.primary, lineWidth: 1.5)`, no fill.
  - Full-bleed: all of the above ignore `contentLeadingX` (x=0, full width). Text color flips to `Color(nsColor: palette.onPrimary(1))` when `solidAccent` selection; `tertiary` when disabled.

- [ ] **Step 2: Build + prism gate** — `swift build` green. prism cells (smoke via cell 3 + manually add a selected/hover row): verify selection wash + 3pt bar, rounded pill (cell 2 style), zebra (cell 10 style), outline ring (cell 9 style), solidAccent opaque fill + onPrimary ink. Screenshot 2-3 themes; eyeball against the AppKit cell rendering of the same data (open both benches side by side if needed). Expected: pixel-close (sub-pixel text baseline drift allowed).
- [ ] **Step 3: Commit** — `:sparkles: feat(ThemeKitUI): #17b M2 — row background decorations (zebra/tint/selection/hover/outline)`.

### Task 5: Leading image column (template tint + colour favicon) + indent

**Files:** Modify `Sources/ThemeKitUI/ThemedListRow.swift`.

- [ ] **Step 1: Implement** the leading image. When `style.reservesLeadingImageColumn` and `item.image != nil`: an image box of side `metrics.imageBox` at `x = metrics.leadingInset + indent`; the image drawn aspect-fit at `side = image.isTemplate ? metrics.iconGlyph : metrics.imageBox`, centred. Template (`isTemplate == true`): `Image(nsImage:).renderingMode(.template).foregroundColor(Color(nsColor: onAccent ? palette.onPrimary(1) : palette.foreground))` (SwiftUI's template render = the AppKit `.sourceAtop` knockout tint). Colour favicon (`isTemplate == false`): `Image(nsImage:).renderingMode(.original)` — draws as-is, NO knockout. `.interpolation(.high)` for favicons. Content (image + text) indents; decorations already don't (Task 4).
- [ ] **Step 2: Build + prism gate** — verify cell 1 (facet template glyphs tint to role), cell 2 (colour favicon `s2` reads as a distinct colour on the `solidAccent` primary fill — the no-knockout proof), indent (cell 8 shape: content shifts, selection wash stays full-bleed). Screenshot.
- [ ] **Step 3: Commit** — `:sparkles: feat(ThemeKitUI): #17b M2 — leading image column (template tint / colour favicon) + indent`.

### Task 6: Trailing cluster — badges / shortcut lozenge / chevron / accessory

**Files:** Modify `Sources/ThemeKitUI/ThemedListRow.swift`; may add a `TrailingCluster` subview.

- [ ] **Step 1: Implement** the trailing cluster, laid out right-to-left from `width - trailingInset` (mirror `ThemedList.swift:1397-1439`): rightmost = accessory (`.chevron` = `caret-right` Phosphor at `chevronPt`, tint `tertiary`/`onPrimary(0.55)`; `.shortcut(text)` = lozenge: `border` stroke rounded `shortcutRadius`, height `shortcutHeight`, text `.shortcut` 10/medium in `muted`; `.custom(NSImage)` = aspect-scaled to `badgeHeight`), then badges reversed (each a `Capsule` height `badgeHeight`, fill role@0.16, text `.badge` 10/medium in role ink, optional leading `badgeSymbolPt` template symbol). Gap between two badges = `badgeGap`, else `clusterGap`. The primary-text max width subtracts `clusterWidth + budgetMargin + trailingInset` (use a `GeometryReader` or fixed measured width; `Spacer(minLength:)` keeps the cluster right-aligned). onAccent recolors per the role table.
- [ ] **Step 2: Build + prism gate** — cell 1 (⌘-badges + `min` symbol badge, role colors), cell 2 (shortcut lozenge + chevron), cell 3 (mixed trailing). Verify against AppKit. Screenshot.
- [ ] **Step 3: Commit** — `:sparkles: feat(ThemeKitUI): #17b M2 — trailing cluster (badges/shortcut/chevron/accessory)`.

### Task 7: Dividers/separators + section header + sticky pinning

**Files:** Modify `Sources/ThemeKitUI/ThemedListRow.swift` (header/separator kinds), `Sources/ThemeKitUI/ThemedListView.swift` (wrap sections in `Section { } header: { }` for `.sectionHeaders` pinning).

- [ ] **Step 1: Implement**
  - Separator row: `separatorBand` tall, a 1pt full-bleed `palette.border` hairline centred.
  - Divider (`style.showsDividers`): a 1pt `palette.border` rule at the row's bottom; x=0 full-bleed if the *next* row is a header, else inset to `contentLeadingX`; suppressed above a separator and after the last row. Compute "next row kind" in `ThemedListView` and pass a `dividerInset: CGFloat?` (nil = no divider) into the row.
  - Section header: 1-line = `.uppercased()`, font `.sectionHeader` 11/semibold, `.tracking(0.5)`, color `muted`, + full-bleed 1pt `border` underline; 2-line = title `.sectionTitle` 13/medium `foreground` (top pad 6) + subtitle `.caption` 11/regular `muted`. Opaque "punch" fill = `Color(nsColor: surface)` behind the header (skipped when surface nil/vibrancy) so pinned headers occlude scrolled rows. Disclosure caret handled in Task 10 (collapse) — for now a static caret if `isCollapsibleHeader`.
  - Sticky: restructure `body` to group `visible` into `Section`s keyed by header runs, using `LazyVStack(pinnedViews: [.sectionHeaders])` + `Section { rows } header: { headerRow }`. This gives native pinned-header push-up hand-off (replacing the entire AppKit `postsBoundsChangedNotifications` dance). The pure `ListCore.stickyHeader` math stays available as the fallback per design decision ② if `.pinnedViews` hand-off differs — verify live in Task 7 gate; if it drifts, drive a manual `.overlay` header off `.onScrollGeometryChange` using `stickyHeader(...)`.
- [ ] **Step 2: Build + prism gate** — cell 1 with `previewScrollY = 30` (via `ListPreview(scrollY:)` — see Task 8 for the frozen-scroll seam): the first 2-line header pins and the next one hands it off; header punch occludes scrolled rows; vibrancy theme lets rows show through the pinned header. Screenshot. **This is the sticky-header hand-off gate — the #1 M2a fidelity risk.**
- [ ] **Step 3: Commit** — `:sparkles: feat(ThemeKitUI): #17b M2 — dividers/separators + section header + sticky pinning`.

### Task 8: Single-select + hover + frozen preview seam

**Files:** Modify `Sources/ThemeKitUI/ThemedListView.swift` (gestures + preview-driven scroll), `Sources/ThemeKitUI/ThemedListRow.swift` (`.onHover`).
- Test: `Tests/ThemeKitUITests/ListSelectionRoutingTests.swift`

**Interfaces:** Consumes `ListCore.resolveClick` (single-select = empty `SelectMods`), `ListItem.selectableIDs`. Produces the tap→select, hover→highlight routing + `preview.scrollX/Y` frozen scroll offset.

- [ ] **Step 1: Write the failing test** — pin that single-select routes through `MultiSelection.resolveClick` (so the ListCore green net protects the shipped behavior):

```swift
import XCTest
import ListCore
@testable import ThemeKitUI

final class ListSelectionRoutingTests: XCTestCase {
    func testSingleClickReplacesSelection() {
        // ThemeKitUI helper the view uses: single-select = resolveClick with no mods
        let sel = ThemedListSelect.click(id: "b", current: ["a"], anchor: "a",
                                         mods: [], selectable: ["a", "b", "c"])
        XCTAssertEqual(sel.selection, ["b"])
        XCTAssertEqual(sel.anchor, "b")
    }
    func testDisabledOrHeaderTapIgnored() {
        // a tap on a non-selectable id must be a no-op (id not in `selectable`)
        let sel = ThemedListSelect.click(id: "h", current: ["a"], anchor: "a",
                                         mods: [], selectable: ["a", "b"])
        XCTAssertEqual(sel.selection, ["a"])   // unchanged
    }
}
```

- [ ] **Step 2: Run → FAIL** (`ThemedListSelect` missing).
- [ ] **Step 3: Implement** a thin `enum ThemedListSelect` wrapper in `ThemedListView.swift` (or a small `ListSelectRouting.swift`) that forwards to `ListCore.resolveClick`, guarding non-selectable taps:

```swift
enum ThemedListSelect {
    static func click<ID: Hashable>(id: ID, current: Set<ID>, anchor: ID?,
                                    mods: SelectMods, selectable: [ID]) -> (selection: Set<ID>, anchor: ID?) {
        guard selectable.contains(id) else { return (current, anchor) }   // header/sep/disabled no-op
        return resolveClick(id: id, current: current, anchor: anchor, mods: mods, selectable: selectable)
    }
}
```
Then wire the row tap (`.onTapGesture`) → for `.single`/`.multiple` call `ThemedListSelect.click` (mods empty for single) and write `$selection` + fire `onSelectionChange`; a header tap fires `onToggleSection` (collapse — Task 10). Wire `.onHover { inside in ... }` on each row → update a `@State hovered: ID?`; if `style.highlightFollowsHover` write `$highlight`; fire `onHover`. Wire the frozen scroll: when `preview?.scrollX/Y != nil`, wrap in `ScrollViewReader` and `.onAppear { proxy.scrollTo(...) }` to the offset (or apply a fixed content offset) so static shots are deterministic; when `preview == nil`, normal live scroll.

- [ ] **Step 4: Run → PASS** (`ListSelectionRoutingTests`). `swift build` green.
- [ ] **Step 5: prism gate** — cell 1 `previewSelection` shows the committed row; hover a row live (wand cell) → veil/highlight; frozen `previewScrollY` still pins the header. Screenshot.
- [ ] **Step 6: Commit** — `:sparkles: feat(ThemeKitUI): #17b M2 — single-select + hover routing (via ListCore.resolveClick) + frozen preview seam`.

### Task 9: Re-express prism cells 1,2,3,9,10,11 + menu mock → M2a ships

**Files:** Modify `Sources/prism/ListShowcase.swift` (cells 1,2,3,9,10,11 + data builders return type), `Sources/prism/MenuShowcase.swift` (inline mock).

- [ ] **Step 1: Migrate** each cell from the `configure` closure to the new API. Data builders return `[ThemeKitUI.ListItem<String>]` (qualify `ListItem` — the value types `Badge`/`TrailingAccessory` stay unqualified). Each static cell passes constant bindings + a `ListPreview`. Example (cell 1):

```swift
cell("facet tree · sticky headers · single-select") {
    ThemedListView(items: facetItems(),
                   style: { var s = ListStyle(); s.selectionMode = .single; s.showsDividers = true; return s }(),
                   palette: p,
                   preview: ListPreview(selection: ["w2"], scrollY: 30))
        .frame(width: 320, height: 188)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: p.border), lineWidth: 1))
}
```
Cells: 2 (`selectionMode:.none, hoverStyle:.solidAccent, roundedSelection:true, preview highlight "s2"`), 3 (`density:.compact` + focusable in M2b; `preview highlight "copy"`), 9 (`highlightStyle:.outline, preview selection "w1" + highlight "w2"`), 10 (`zebra:true, selectionMode:.none`, no preview), 11 (`horizontalContentScroll:true, preview selection "1" + scrollX 150`). MenuShowcase inline mock (`selectionMode:.none, hoverStyle:.solidAccent, highlightFollowsHover:true, density:.compact, preview highlight "open"`). **Leave the drag cells (4,5,6,7) on the AppKit `ThemedListView` bridge?** — No: the bridge is being replaced. Temporarily keep cells 4–8 wired to the OLD API is impossible once the bridge is gone. So cells 4,5,6,7,8 are wired to the new API with a **`// TODO(M2b/M2c)`** minimal config (no drag/collapse yet — they'll light up in later stages); update their captions to say "drag: M2c" so prism honestly shows coverage-in-progress ([[workflow-aggregate-sanity-check]]: never silently drop coverage — a caption says what's pending).
- [ ] **Step 2: Build + full prism sweep** — `swift build` + `scripts/test.sh` green (no test regressions — AppKit widget + its 83 tests untouched). Launch prism, sweep ALL catalog themes on the List tab; verify cells 1,2,3,9,10,11 + menu mock render 1:1 vs the AppKit versions across themes (theme fidelity gate — zebra/tint/selection/outline/badge/lozenge/divider/header). Capture representative themes.
- [ ] **Step 3: Commit + STAGE M2a SHIP** — `:sparkles: feat(ThemeKitUI,prism): #17b M2a — SwiftUI-native ThemedListView rendering + single-select (cells 1-3,9-11)`. Per [[ci-green-merge-ok]], M2a may be squash-merged to main once CI green (no tag — tag deferred to M5). Record progress in the t-sb4c furrow body.

---

## STAGE M2b — animated collapse + multi-select + standalone keyboard

### Task 10: Collapsible sections — caret rotation + row-diff animation

**Files:** Modify `ThemedListView.swift` (expanded binding drives `visibleRows` + `withAnimation`), `ThemedListRow.swift` (header caret = 1 rotating glyph).

- [ ] **Step 1: Implement.** Header tap on an `isCollapsibleHeader` → `withAnimation(.easeInOut(duration: 0.2)) { expanded = toggleSection(headerID, in: expanded) }` (via `ListCore.toggleSection`) + fire `onToggleSection`. `visibleRows` already recomputes via `ListCore.flattenVisible(collapsed:)`; wrap the `ForEach` content transitions in `.transition(.opacity.combined(with: .move(edge: .top)))` so collapsed rows animate out/in (the AppKit widget can't — instant `reload()`; this is the M2 improvement). Disclosure caret = a single `caret-down` Phosphor glyph with `.rotationEffect(.degrees(headerCollapsed ? -90 : 0)).animation(.easeInOut, value: headerCollapsed)` (replaces the 2-glyph swap). Whole-header tap toggles (match AppKit — no caret-only hit region).
- [ ] **Step 2: Build + prism gate** — cell 8 (tree): both disclosure states, caret rotates smoothly on toggle, collapsed section's rows animate away, indent + full-bleed selection preserved. **Animation quality gate** ([[animation-is-a-differentiator]]) — verify live, not just a static shot; the caret tween + row reflow must feel native. Screenshot both states.
- [ ] **Step 3: Commit** — `:sparkles: feat(ThemeKitUI): #17b M2 — animated collapsible sections (caret rotation + row-diff, via ListCore)`.

### Task 11: Multi-select (`.multiple`) — the net-new feature

> Premise note: the AppKit widget has **no** multi-select (`SelectionMode = none|single`, `.multiple` was YAGNI'd). This is greenfield, routed entirely through the already-tested `ListCore.MultiSelection`. Additive — Combo/Menu keep `.single`/`.none`.

**Files:** Modify `ThemedListView.swift` (modifier-aware tap + shift-arrow + ⌘A), `Tests/ThemeKitUITests/ListSelectionRoutingTests.swift` (extend).

- [ ] **Step 1: Write the failing tests** — cmd-toggle, shift-range, ⌘A route through ListCore:

```swift
func testCommandTogglesOne() {
    let r = ThemedListSelect.click(id: "b", current: ["a"], anchor: "a",
                                   mods: .command, selectable: ["a", "b", "c"])
    XCTAssertEqual(r.selection, ["a", "b"])
}
func testShiftSelectsRange() {
    let r = ThemedListSelect.click(id: "c", current: ["a"], anchor: "a",
                                   mods: .shift, selectable: ["a", "b", "c"])
    XCTAssertEqual(r.selection, ["a", "b", "c"])
}
func testSelectAll() {
    XCTAssertEqual(ThemedListSelect.all(selectable: ["a", "b"]), ["a", "b"])
}
```

- [ ] **Step 2: Run → FAIL** (`ThemedListSelect.all` missing; `.command`/`.shift` mapping unused).
- [ ] **Step 3: Implement.** Add `static func all` (→ `ListCore.selectAll`). In the view, when `style.selectionMode == .multiple`: read `NSEvent.modifierFlags` (or a `.modifierKeys` environment) at tap → map to `SelectMods` (`.command` if ⌘, `.shift` if ⇧) → `ThemedListSelect.click(...)`. Bind `.onKeyPress` (from Task 12) for ⇧+↑/↓ → `ListCore.extendByKey`, and ⌘A → `ThemedListSelect.all`. `selection: Set<ID>` binding already carries multi. Single/none modes unchanged (mods forced empty).
- [ ] **Step 4: Run → PASS.** `swift build` green.
- [ ] **Step 5: prism gate** — add a NEW cell 12 "multi-select · ⌘/⇧ range" (a flat list, `selectionMode:.multiple`, `preview selection ["a","b","c"]`) so the feature is visible in the bench (net-new coverage — announce it in the caption). Screenshot the multi-selected state across 2 themes.
- [ ] **Step 6: Commit** — `:sparkles: feat(ThemeKitUI,prism): #17b M2 — multi-select (.multiple, ⌘/⇧/⌘A via ListCore) + prism cell`.

### Task 12: Standalone keyboard navigation (`.onKeyPress`)

**Files:** Modify `ThemedListView.swift` (`.focusable()` + `@FocusState` + `.onKeyPress`).

- [ ] **Step 1: Implement.** On the scroll container: `.focusable(style.selectionMode != .none || style.managesFirstResponderEquivalent)` + `@FocusState private var focused: Bool` + a `primary`-stroked focus ring when focused (mirror the AppKit `managesFirstResponder` ring, `Radius.sm`, lineWidth 2). Bind:
  - `.onKeyPress(.upArrow)` / `.onKeyPress(.downArrow)` → move `highlight` via `ListCore.nextHighlight(current: index(of: highlight), delta: ∓1, selectableIndices: …, wraps: style.wrapsHighlight)`, then `ScrollViewReader.scrollTo(newHighlight)`; if ⇧ held and `.multiple`, `extendByKey` instead.
  - `.onKeyPress(.return)` → `onActivate(highlight)` (+ commit selection in single).
  - `.onKeyPress(.escape)` → `highlight = nil`.
  - `.onKeyPress(.space)` → in `.multiple`, toggle `highlight` in selection; else activate.
  These collapse the AppKit `interpretKeyEvents` + `moveUp/moveDown/insertNewline/cancelOperation` responder overrides. The pure `nextHighlight` seam is unchanged.
- [ ] **Step 2: Build + prism gate** — cell 3 (dense, now `.focusable`): click to focus (ring appears), ↑↓ moves the highlight ring, Return activates, Esc clears. Verify live (keyboard interaction can't be a static shot — drive it). Screenshot the focused + highlighted state.
- [ ] **Step 3: Commit + STAGE M2b SHIP** — `:sparkles: feat(ThemeKitUI): #17b M2b — standalone .onKeyPress nav + focus ring (via ListCore.nextHighlight)`. Squash-merge to main when CI green (per [[ci-green-merge-ok]]). Update t-sb4c body.

---

## STAGE M2c — drag/reorder + SwiftUI-overlay ghost

> Design note: the AppKit `DragGhost` was a separate non-activating child window (uncapturable by prism's single-window `screencapture`). The spec (§4) makes the M2 ghost a **SwiftUI `.overlay` View** that follows the drag translation — this **removes** AppKit surface (no child window), is screencaptureable, and stays within the list bounds (standalone lists don't need to escape the window; Combo/Menu lists aren't draggable). This is an AppKit *reduction*, policy-safe ([[appkit-scope-is-the-hard-gate]]). All `ListCore` DnD resolvers (`resolveDropTarget`/`dragCandidates`/`chunkMemberIDs`) are reused unchanged.

### Task 13: Drag gesture + drop affordances (onto ring / between line / section bar / dim)

**Files:** Create `Sources/ThemeKitUI/ThemedListDrag.swift`; modify `ThemedListView.swift` (drag `@State` + affordance overlay), `ThemedListRow.swift` (source-dim + `.gesture`).

**Interfaces:** Consumes `ListCore.resolveDropTarget`, `dragCandidates`, `chunkMemberIDs`, `RowGeom`, `DropTarget`, `DragContext`, `DropPlacement`, `DragMode`. A `[ID: RowGeom]` geometry map is built from `.onScrollGeometryChange`/`GeometryReader` per-row frames (the view now *produces* the geometry `ListCore` consumes).

- [ ] **Step 1: Implement.** Collect per-row `RowGeom(yOffset:height:)` into a `@State geom: [ID: RowGeom]` via a `PreferenceKey` on each row's `.background(GeometryReader { ... })`. A `DragGesture(minimumDistance: 4)` on each `isDragSource` row (draggable && not separator && not disabled; headers ARE liftable): `.onChanged` → seed `dragChunk = chunkMemberIDs(forHeader:)` for a header else `[]`, `setDragTarget(resolveDropTarget(atDocY: pointerDocY, source:, rows: visible.map(\.asRow), geom: orderedGeom, mode: style.dragMode, chunkIDs: dragChunk, validate: dropTargetValidator ?? {_,_ in true}))`; `.onEnded` → if target `onDrop(DragContext(sourceID:memberIDs:), target)`; reset. Drop affordance = a top-level `.overlay` keyed off `dragTarget` (mirror `ThemedList.swift:1872-1911`): `.onto` = rounded `primary` ring (`insetBy(1.5)`, radius md, `lineWidth 2`) + `primary@0.12` fill on the target row (suppressed for chunks); `.between(single)` = 2pt depth-indented `primary` line + a 6×6 insertion dot; `.between(chunk)` = 3pt full-bleed `primary` section bar. Lifted source/chunk rows dim (opacity ~0.4). Preview seams: `preview.dragSource`/`dropTarget`/`dragChunk` force the static affordance when `preview != nil`.
- [ ] **Step 2: Build + prism gate** — cells 4 (`dragMode:.dropOnto`, frozen `dragSource "w3"` + `dropTarget .onto("wsB")` + `scrollY 120`), 5 (`.reorderBetween`, frozen `dragSource "r1"` + `.between("r3")`), 7 (chunk, frozen `dragChunk ["later","l1","l2"]` + `.between("today")`). Verify ring/line/bar/dim match AppKit. Screenshot.
- [ ] **Step 3: Commit** — `:sparkles: feat(ThemeKitUI): #17b M2 — drag gesture + drop affordances (via ListCore resolvers)`.

### Task 14: SwiftUI-overlay drag ghost (replaces the AppKit child window)

**Files:** Modify `Sources/ThemeKitUI/ThemedListDrag.swift`.

- [ ] **Step 1: Implement** a top-level `.overlay` ghost View that renders the lifted row(s) at reduced opacity, offset by the live drag translation (`.offset(x:y:)` from the `DragGesture` translation). For a chunk (count > 1), render a stacked/condensed representation + a "N items" count pill (font 10/semibold, fill `primary`, ink `onPrimary(1)`, height 16, radius 8) at the top-trailing — mirror `ThemedList.swift:1837-1856`. No child window; the ghost lives in the list's own overlay layer.
- [ ] **Step 2: Build + prism gate** — live-drag a row in cell 4/5 and a chunk in cell 6: the ghost now follows the pointer AND is screencaptureable (the old child-window limitation is gone — this is the concrete M2 improvement). Screenshot a live drag (ghost visible). Verify the ghost stays inside the list bounds.
- [ ] **Step 3: Commit** — `:recycle: refactor(ThemeKitUI): #17b M2 — SwiftUI-overlay drag ghost (removes AppKit DragGhost child window)`.

### Task 15: Keyboard drag (lift/aim/commit/cancel)

**Files:** Modify `Sources/ThemeKitUI/ThemedListDrag.swift`, `ThemedListView.swift` (`.onKeyPress` while dragging).

- [ ] **Step 1: Implement.** Reuse `ListCore.dragCandidates` to build the ordered keyboard aim targets. Bind, when `style.draggable` and focused: `.onKeyPress(.space)` → lift `highlight` (or commit if already lifted), `.onKeyPress(.return)` → commit (`onDrop`), `.onKeyPress(.escape)` → cancel, `.onKeyPress(.upArrow/.downArrow)` → step the aim through `dragCandidates` (a chunk aims at header gaps + end gap only). Mirror the `KeyboardDragController` state machine (`ThemedList.swift:1968-2024`) as a small `@Observable` in `ThemedListDrag.swift` — or a plain struct reducer if simpler. Keyboard-drag keys take priority over nav keys while a lift is active (match AppKit `handleDragKey` first-consult).
- [ ] **Step 2: Build + prism gate** — cell 6 (chunk): focus, Space to lift the header+children chunk, ↑↓ to aim at section gaps, Return to drop. Verify live. Screenshot the mid-keyboard-drag aim.
- [ ] **Step 3: Commit** — `:sparkles: feat(ThemeKitUI): #17b M2 — keyboard drag (lift/aim/commit/cancel via ListCore.dragCandidates)`.

### Task 16: Re-express drag prism cells 4,5,6,7 + captions → M2 complete

**Files:** Modify `Sources/prism/ListShowcase.swift` (cells 4,5,6,7 full config + captions), remove the M2b/M2c TODO captions.

- [ ] **Step 1: Finalize** cells 4,5,6,7 with full drag config (`draggable:true` + `dragMode`) and their frozen `preview` seams; restore accurate captions (drop the "M2c pending" notes). Update the top `MockList` description text to reflect the SwiftUI-native rebuild + the now-captureable ghost.
- [ ] **Step 2: Build + FULL prism sweep + full test suite** — `swift build` + `scripts/test.sh` green (AppKit widget + all 83 tests + Combo/Menu tests still green — M2 never touched them). Launch prism, sweep ALL catalog themes across ALL 12 cells: theme fidelity + collapse/drag animation quality + live combo-free interactions. This is the M2 completion gate.
- [ ] **Step 3: Commit + STAGE M2c SHIP = M2 COMPLETE** — `:sparkles: feat(ThemeKitUI,prism): #17b M2c — drag/reorder + overlay ghost + keyboard drag (cells 4-7)`. Squash-merge to main when CI green. **No version tag** (deferred to M5 retire per spec §7). Flip the t-sb4c furrow body: M2 done, M3 (`ListController` + combo popup host) next.

---

## Self-Review (run against the design spec)

**1. Spec coverage** — §2 API → Tasks 1–3,8 (generic `ThemedListView<ID>`, bindings, `ListController` is M3 not M2 ✓). §3 rendering → Tasks 3–7 (surface/zebra/tint/selection/outline/hover/image/trailing/dividers/header/sticky, all metrics in the table). §4 interaction → Tasks 8,10–15 (keyboard/collapse/multi-select/drag/hover). §5 ListCore additions → M2 *consumes* the M1 cores; **measurement `contentHeight`/`fittingWidth` deferred to M3** (only popup sizing needs them; SwiftUI self-sizes) — flagged, not a gap. §6 popup migration → M3/M4 (out of M2 scope ✓). §7 staging → M2 = milestone 2, split into shippable M2a/b/c ✓. §8 verification → prism gate each render task + XCTest for pure seams ✓.

**2. Premise mismatches surfaced** (from the code map, must tell the reviewer): (a) **no multi-select exists** in the AppKit widget — M2's `.multiple` is greenfield, additive, routed through the already-tested `MultiSelection` core (Task 11). (b) **no caret animation / no widget-side `flattenVisible`** — collapse is host-driven + instant `reload()` today; M2 adds the caret tween + row-diff animation as an improvement (Task 10). (c) the current reorder callback is **`onDrop`** (not the spec §2's `onMove`) and the current `ListItem` is **String-keyed** (M2 makes it generic) — the plan uses the real `onDrop`/generic names.

**3. Type consistency** — `ListItem<ID>` (Task 1) ← `visibleRows`/`selectableIDs`/`asRow` used in Tasks 3,8,13; `ListStyle`/`ListMetrics` (Task 2) fields used verbatim in Tasks 3–7; `ThemedListSelect.click`/`.all` (Tasks 8,11) forward to `resolveClick`/`selectAll`; `ListPreview<ID>` (Task 3) seam fields consumed in Tasks 7,8,13. `DragContext`/`DropTarget`/`DropPlacement`/`DragMode`/`RowGeom` are the real `ListCore` generic types (verified signatures). Enums `Density`/`SelectionMode`/`HoverStyle`/`HighlightStyle` are fresh ThemeKitUI module-level types (not the ThemeKit `ThemedList`-nested ones), avoiding the M5-death coupling.

**4. Guardrails** — every stage keeps the AppKit `ThemedList` + its 83 tests + Combo/Menu tests green (M2 is additive; no AppKit-internal edits); `ThemedList.emptyActionID` untouched; new AppKit surface = **negative** (Task 14 removes the child window); ListCore is consumed, never re-implemented; each render change is prism-gated live (the #17f blank-render guard).
