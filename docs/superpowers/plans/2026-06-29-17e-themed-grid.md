# #17e Themed Thumbnail Grid — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a general, content-agnostic, 100% SwiftUI-native themed thumbnail grid (`ThemedGridView` + default `ThemedThumbnailCell`) to `ThemeKitUI`, backed by a pure `GridCore` target, with a prism showcase — usable by facet grid/rail and any picker.

**Architecture:** Three layers mirroring `ListCore`/`ThemedList`: (1) pure `GridCore` (Foundation/Sendable, CI-tested layout + 2D-nav math); (2) `ThemeKitUI` SwiftUI views that own themed chrome + selection seam + keyboard/activation; (3) a prism `MockThumbnailGrid` showcase wired across all themes. DnD and rail carousel/hero are explicitly OUT (see design spec §3.2/§11).

**Tech Stack:** Swift, SwiftUI (`LazyVGrid`/`LazyHGrid`, `onMoveCommand`), SwiftPM. Design spec: [`docs/superpowers/specs/2026-06-29-17e-themed-grid-design.md`](../specs/2026-06-29-17e-themed-grid-design.md).

## Global Constraints

- **macOS floor = 13** (`Package.swift` `platforms: [.macOS(.v13)]`). Use only APIs available on macOS 13, EXCEPT optional enhancements gated with `if #available(macOS 14, *)` (e.g. `onKeyPress`). NEVER raise the floor in this work.
- **100% SwiftUI-native. ZERO AppKit in the new component** — no `NSViewRepresentable`, no AppKit widgets, not even the existing AppKit-backed `ThemedSkeletonView` (it hosts an `NSView`). The skeleton/loading state is a SwiftUI-native shimmer. `ThemeKitUI`'s residual AppKit must stay at the 2 floors (IME editor + window shell) unchanged (AppKit policy, CLAUDE.md).
- **Local gate = `swift build`** (compiles on CommandLineTools). `swift test` does NOT run locally (CLT has no XCTest); **XCTest targets compile + run ONLY in CI** (full Xcode). Therefore: write tests test-first as discipline, but the red→green transition is observed in CI, not locally. Locally verify the library compiles with `swift build`.
- **Theming: canonical `ResolvedPalette` roles only** — `background · foreground · muted · tertiary · primary · secondary · border · hover · selection · error`. Do NOT invent role names. Focus/active affordance → `primary`.
- **Tokens** (module `Palette`): `Space` (xxs=2, xs=4, sm=6, md=8, lg=12, xl=16), `Radius` (xs=2, sm=4, md=6, lg=8), `Elevation` (`.dp2`…`.dp12`) resolved via `palette.shadow(_:)` (PaletteKit). Use tokens for gap/padding/corner/elevation; exact picks tuned later in prism.
- **prism showcase is mandatory** for every widget (CLAUDE.md): a `Mock…(p:)` wired into the gallery, live across all themes. prism stays a pure consumer (`import ThemeKitUI`, no in-tree copies).
- **Versioning:** additive library change ⇒ minor bump + `v`-prefixed tag at merge. Current `v1.32.0` → **next `v1.33.0`**. Commits: gitmoji + Conventional Commits.
- **Tracking:** furrow `t-99za` (already in-progress). The implementation PR body MUST carry the footer:
  `SetStatus-task: https://github.com/akira-toriyama/projects/blob/main/.furrow/bodies/t-99za.md done`
  (merge auto-closes the task — do NOT manually push a status change).

---

### Task 1: Pure `GridCore` target + layout/nav math + CI tests

**Files:**
- Modify: `Package.swift` (add product, target, test target; add `GridCore` to `ThemeKitUI` deps — wiring for later tasks)
- Create: `Sources/GridCore/GridCore.swift`
- Test: `Tests/GridCoreTests/GridMathTests.swift`

**Interfaces:**
- Produces (used by Task 4/5):
  - `func gridColumns(availableWidth: CGFloat, minCellWidth: CGFloat, gap: CGFloat, max maxColumns: Int) -> Int`
  - `func gridCellSize(availableWidth: CGFloat, columns: Int, gap: CGFloat, aspectRatio: CGFloat?) -> CGSize`
  - `func nextGridIndex(from index: Int, dx: Int, dy: Int, count: Int, columns: Int, wrap: Bool) -> Int`
  - `func reconcileGridSelection<ID: Hashable>(_ selection: Set<ID>, existing ids: Set<ID>) -> Set<ID>`

- [ ] **Step 1: Add the `GridCore` product + target + test target, and wire it into ThemeKitUI**

In `Package.swift`, add to `products` (after the `ListCore` library line):
```swift
        .library(name: "GridCore", targets: ["GridCore"]),
```
Add to `targets` (after the `ListCore` target block), copying the pure-leaf idiom:
```swift
        // Pure, Sendable, AppKit-free GRID math — adaptive column count,
        // aspect-fit cell sizing, 2D roving-cursor navigation (ragged last row),
        // and selection reconciliation. The headless core behind ThemeKitUI's
        // native `ThemedGridView` (#17e); a pure leaf alongside Palette/ListCore:
        // zero AppKit, zero Palette (only CGSize/CGFloat behind a CoreGraphics
        // gate). The future `GridDnD.swift` (macOS-26 milestone) lands here.
        .target(name: "GridCore"),
```
Change the `ThemeKitUI` target's dependencies to include `"GridCore"`:
```swift
        .target(name: "ThemeKitUI",
                dependencies: ["ThemeKit", "PaletteKit", "Palette", "Effects", "Motion", "PixelArt", "GridCore"]),
```
(Note `"Palette"` is ALSO added here — Task 2+ name `Space`/`Radius`/`Elevation` from the `Palette` module directly.)
Add to the test targets list (after `ListCoreTests`):
```swift
        .testTarget(name: "GridCoreTests", dependencies: ["GridCore"]),
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/GridCoreTests/GridMathTests.swift`:
```swift
import XCTest
@testable import GridCore

final class GridMathTests: XCTestCase {

    // gridColumns — adaptive count
    func testColumnsBasic() {
        // 3*100 + 2*10 = 320 fits in 320; a 4th needs 430 > 320.
        XCTAssertEqual(gridColumns(availableWidth: 320, minCellWidth: 100, gap: 10, max: 99), 3)
    }
    func testColumnsClampedToMax() {
        XCTAssertEqual(gridColumns(availableWidth: 10_000, minCellWidth: 100, gap: 10, max: 5), 5)
    }
    func testColumnsNeverZero() {
        XCTAssertEqual(gridColumns(availableWidth: 10, minCellWidth: 100, gap: 10, max: 5), 1)
    }

    // gridCellSize — aspect-fit
    func testCellWidthFromColumns() {
        // (300 - 2*10) / 3 = 93.333…
        let s = gridCellSize(availableWidth: 300, columns: 3, gap: 10, aspectRatio: nil)
        XCTAssertEqual(s.width, 280.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(s.height, 280.0 / 3.0, accuracy: 0.001)   // nil ⇒ square
    }
    func testCellHeightFromAspect() {
        // aspectRatio = width/height = 2 ⇒ height = width/2
        let s = gridCellSize(availableWidth: 210, columns: 2, gap: 10, aspectRatio: 2)
        XCTAssertEqual(s.width, 100, accuracy: 0.001)
        XCTAssertEqual(s.height, 50, accuracy: 0.001)
    }

    // nextGridIndex — 2D nav over a 3-col grid of 7 items (rows: [0,1,2][3,4,5][6])
    func testMoveRight() {
        XCTAssertEqual(nextGridIndex(from: 0, dx: 1, dy: 0, count: 7, columns: 3, wrap: false), 1)
    }
    func testMoveDown() {
        XCTAssertEqual(nextGridIndex(from: 1, dx: 0, dy: 1, count: 7, columns: 3, wrap: false), 4)
    }
    func testMoveDownIntoRaggedLastRowSnaps() {
        // from index 4 (row1,col1) down → row2,col1 = index 7 which is past count(7) → snap to 6
        XCTAssertEqual(nextGridIndex(from: 4, dx: 0, dy: 1, count: 7, columns: 3, wrap: false), 6)
    }
    func testNoWrapClampsAtEdge() {
        XCTAssertEqual(nextGridIndex(from: 2, dx: 1, dy: 0, count: 7, columns: 3, wrap: false), 2)
    }
    func testWrapHorizontal() {
        XCTAssertEqual(nextGridIndex(from: 2, dx: 1, dy: 0, count: 7, columns: 3, wrap: true), 0)
    }

    // reconcileGridSelection — drop vanished ids
    func testReconcileDropsMissing() {
        XCTAssertEqual(reconcileGridSelection(Set(["a", "b", "z"]), existing: Set(["a", "b", "c"])),
                       Set(["a", "b"]))
    }
}
```

- [ ] **Step 3: Write the implementation**

Create `Sources/GridCore/GridCore.swift`:
```swift
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// GridCore — Foundation-only, Sendable, AppKit-free pure math behind ThemeKitUI's
// native `ThemedGridView` (#17e). No type named `GridCore` (module==type
// collision); the surface is top-level free functions, like ListCore/Motion.

/// Adaptive column count: the most cells of width ≥ `minCellWidth` (separated by
/// `gap`) that fit in `availableWidth`, clamped to `1...maxColumns`.
public func gridColumns(availableWidth: CGFloat, minCellWidth: CGFloat,
                        gap: CGFloat, max maxColumns: Int) -> Int {
    guard availableWidth > 0, minCellWidth > 0, maxColumns > 0 else { return 1 }
    // n cells fit when n*minCellWidth + (n-1)*gap ≤ availableWidth
    //   ⇒ n ≤ (availableWidth + gap) / (minCellWidth + gap)
    let raw = Int((availableWidth + gap) / (minCellWidth + gap))
    return Swift.min(Swift.max(raw, 1), maxColumns)
}

/// One cell's size given `columns`. `aspectRatio` = width/height (nil ⇒ square).
public func gridCellSize(availableWidth: CGFloat, columns: Int,
                         gap: CGFloat, aspectRatio: CGFloat?) -> CGSize {
    let cols = Swift.max(columns, 1)
    let totalGap = gap * CGFloat(cols - 1)
    let w = Swift.max((availableWidth - totalGap) / CGFloat(cols), 0)
    let h = (aspectRatio.map { $0 > 0 ? w / $0 : w }) ?? w
    return CGSize(width: w, height: h)
}

/// Next focused index after a (dx,dy) move over a row-major grid of `count`
/// items in `columns`. `wrap` wraps at edges; a move into the ragged last row
/// past the final item snaps back to the last real index.
public func nextGridIndex(from index: Int, dx: Int, dy: Int,
                          count: Int, columns: Int, wrap: Bool) -> Int {
    guard count > 0 else { return index }
    let cols = Swift.max(columns, 1)
    let i = Swift.min(Swift.max(index, 0), count - 1)
    let rows = (count + cols - 1) / cols
    var row = i / cols
    var col = i % cols
    if dx != 0 {
        col += dx
        if col < 0 { col = wrap ? cols - 1 : 0 }
        if col >= cols { col = wrap ? 0 : cols - 1 }
    }
    if dy != 0 {
        row += dy
        if row < 0 { row = wrap ? rows - 1 : 0 }
        if row >= rows { row = wrap ? 0 : rows - 1 }
    }
    let target = row * cols + col
    return target >= count ? count - 1 : target   // ragged last-row snap
}

/// Drop selected ids no longer present (reconcile a persisted selection).
public func reconcileGridSelection<ID: Hashable>(_ selection: Set<ID>,
                                                  existing ids: Set<ID>) -> Set<ID> {
    selection.intersection(ids)
}
```

- [ ] **Step 4: Build locally (library gate)**

Run: `swift build`
Expected: builds with no errors. (The `GridCoreTests` target compiles + runs only in CI; CLT has no XCTest.)

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/GridCore/GridCore.swift Tests/GridCoreTests/GridMathTests.swift
git commit -m ":sparkles: feat(GridCore): #17e pure grid math — columns/cellSize/2D-nav/reconcile (t-99za)"
```

---

### Task 2: `GridLayout` + `GridCellState` value types

**Files:**
- Create: `Sources/ThemeKitUI/GridLayout.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (used by Task 3/4/5):
  - `public enum GridLayout: Sendable { case fixed(columns: Int); case adaptive(minCellWidth: CGFloat) }`
  - `public struct GridCellState: Sendable { public let isSelected, isHovered, isFocused: Bool; public init(isSelected: Bool, isHovered: Bool, isFocused: Bool) }`

- [ ] **Step 1: Write the file**

Create `Sources/ThemeKitUI/GridLayout.swift`:
```swift
import CoreGraphics

// Value types for `ThemedGridView` (#17e). Pure/Sendable so a consumer can build
// them off the main actor and pass them in.

/// How the grid distributes cells across the cross-axis.
public enum GridLayout: Sendable {
    /// A fixed number of equal-width columns (rows for a horizontal axis).
    case fixed(columns: Int)
    /// As many columns as fit, each at least `minCellWidth` wide.
    case adaptive(minCellWidth: CGFloat)
}

/// The render state of one cell, handed to the cell builder so it can add its
/// own emphasis on top of the chrome `ThemedGridView` already draws.
public struct GridCellState: Sendable {
    public let isSelected: Bool
    public let isHovered: Bool
    public let isFocused: Bool
    public init(isSelected: Bool, isHovered: Bool, isFocused: Bool) {
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.isFocused = isFocused
    }
}
```

- [ ] **Step 2: Build locally**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/ThemeKitUI/GridLayout.swift
git commit -m ":sparkles: feat(ThemeKitUI): #17e GridLayout + GridCellState value types (t-99za)"
```

---

### Task 3: `ThemedThumbnailCell` default cell + SwiftUI-native shimmer

**Files:**
- Create: `Sources/ThemeKitUI/ThemedThumbnailCell.swift`

**Interfaces:**
- Consumes: `ResolvedPalette` (PaletteKit), `Palette.Radius`.
- Produces (used by Task 5/6):
  - `public struct ThemedThumbnailCell: View { public init(image: NSImage?, label: String? = nil, palette: ResolvedPalette) }`

- [ ] **Step 1: Write the file**

Create `Sources/ThemeKitUI/ThemedThumbnailCell.swift`:
```swift
import SwiftUI
import PaletteKit
import Palette

// ThemeKitUI — the DEFAULT cell content for `ThemedGridView` (#17e). 100% SwiftUI
// native: an image scaled to fill, or a SwiftUI shimmer while it loads, with an
// optional bottom-scrim label. Cell CHROME (selection ring / hover veil / focus
// ring / corner / elevation) is owned by `ThemedGridView`, NOT here.

public struct ThemedThumbnailCell: View {
    private let image: NSImage?
    private let label: String?
    private let palette: ResolvedPalette

    public init(image: NSImage?, label: String? = nil, palette: ResolvedPalette) {
        self.image = image
        self.label = label
        self.palette = palette
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                ShimmerPlaceholder(palette: palette)
            }
            if let label, !label.isEmpty {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(nsColor: palette.foreground))
                    .lineLimit(1)
                    .padding(.horizontal, CGFloat(Space.xs))
                    .padding(.vertical, CGFloat(Space.xxs))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(colors: [.clear,
                                                (palette.background.map { Color(nsColor: $0) } ?? .black).opacity(0.55)],
                                       startPoint: .top, endPoint: .bottom)
                    )
            }
        }
        .clipped()
    }
}

/// A SwiftUI-native loading shimmer (NO AppKit). A muted fill with a soft
/// highlight band sweeping across — replaces the AppKit-backed ThemedSkeletonView
/// so the grid stays AppKit-zero (#17e AppKit policy).
struct ShimmerPlaceholder: View {
    let palette: ResolvedPalette
    @State private var travel: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color(nsColor: palette.muted).opacity(0.18))
                .overlay(
                    LinearGradient(
                        colors: [.clear,
                                 Color(nsColor: palette.foreground).opacity(0.12),
                                 .clear],
                        startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: travel * geo.size.width)
                )
                .clipped()
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        travel = 1.3
                    }
                }
        }
    }
}
```

- [ ] **Step 2: Build locally**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/ThemeKitUI/ThemedThumbnailCell.swift
git commit -m ":sparkles: feat(ThemeKitUI): #17e ThemedThumbnailCell + SwiftUI-native shimmer (t-99za)"
```

---

### Task 4: `ThemedGridView` — layout, themed chrome, selection seam, keyboard, activation

**Files:**
- Create: `Sources/ThemeKitUI/ThemedGridView.swift`

**Interfaces:**
- Consumes: `GridLayout`, `GridCellState` (Task 2); `gridColumns`/`nextGridIndex` (Task 1, `import GridCore`); `ResolvedPalette` + `palette.shadow(_:)` (PaletteKit); `Space`/`Radius`/`Elevation` (`import Palette`).
- Produces (used by Task 5/6):
  - `public struct ThemedGridView<Data, ID, Cell>: View where Data: RandomAccessCollection, ID: Hashable, Cell: View` with the init signature below.

- [ ] **Step 1: Write the file**

Create `Sources/ThemeKitUI/ThemedGridView.swift`:
```swift
import SwiftUI
import PaletteKit
import Palette
import GridCore

// ThemeKitUI — a general, content-agnostic, 100% SwiftUI-native themed grid (#17e).
// Owns: responsive layout (LazyVGrid/LazyHGrid in a ScrollView), themed chrome
// (rest/hover/selected/focused), controlled/uncontrolled selection seam, 2D
// keyboard navigation (onMoveCommand), and activation (double-click / Return on
// macOS 14+). The cell CONTENT is supplied by the consumer via @ViewBuilder.
// NO AppKit. DnD + carousel/hero are out of scope (see design spec §3.2/§11).

@MainActor
public struct ThemedGridView<Data, ID, Cell>: View
where Data: RandomAccessCollection, ID: Hashable, Cell: View {

    private let data: Data
    private let idKey: KeyPath<Data.Element, ID>
    private let layout: GridLayout
    private let axis: Axis
    private let aspectRatio: CGFloat?
    private let palette: ResolvedPalette
    private let onActivate: ((ID) -> Void)?
    private let cellBuilder: (Data.Element, GridCellState) -> Cell
    private let selectionBinding: Binding<Set<ID>>?

    @State private var internalSelection: Set<ID> = []
    @State private var cursor: ID?
    @State private var hovered: ID?
    @State private var resolvedColumns: Int = 1
    @FocusState private var isFocused: Bool

    // Tokens (tuned later in prism).
    private let gap = CGFloat(Space.md)        // 8
    private let pad = CGFloat(Space.md)        // 8
    private let corner = CGFloat(Radius.lg)    // 8
    private let focusOutset = CGFloat(Space.xxs)  // 2

    public init(_ data: Data,
                id: KeyPath<Data.Element, ID>,
                selection: Binding<Set<ID>>? = nil,
                layout: GridLayout = .adaptive(minCellWidth: 160),
                axis: Axis = .vertical,
                aspectRatio: CGFloat? = nil,
                palette: ResolvedPalette,
                onActivate: ((ID) -> Void)? = nil,
                @ViewBuilder cell: @escaping (Data.Element, GridCellState) -> Cell) {
        self.data = data
        self.idKey = id
        self.selectionBinding = selection
        self.layout = layout
        self.axis = axis
        self.aspectRatio = aspectRatio
        self.palette = palette
        self.onActivate = onActivate
        self.cellBuilder = cell
    }

    private var selection: Binding<Set<ID>> { selectionBinding ?? $internalSelection }
    private var elements: [Data.Element] { Array(data) }
    private var ids: [ID] { elements.map { $0[keyPath: idKey] } }

    private var gridItems: [GridItem] {
        switch layout {
        case .fixed(let n):
            return Array(repeating: GridItem(.flexible(), spacing: gap),
                         count: Swift.max(n, 1))
        case .adaptive(let minW):
            return [GridItem(.adaptive(minimum: minW), spacing: gap)]
        }
    }

    public var body: some View {
        GeometryReader { geo in
            ScrollView(axis == .vertical ? .vertical : .horizontal) {
                gridBody
                    .padding(pad)
            }
            .focusable()
            .focused($isFocused)
            .onMoveCommand { move($0) }
            .onAppear { recomputeColumns(width: crossWidth(geo)) }
            .onChange(of: geo.size) { _ in recomputeColumns(width: crossWidth(geo)) }
        }
    }

    @ViewBuilder
    private var gridBody: some View {
        if axis == .vertical {
            LazyVGrid(columns: gridItems, spacing: gap) { cells }
        } else {
            LazyHGrid(rows: gridItems, spacing: gap) { cells }
        }
    }

    @ViewBuilder
    private var cells: some View {
        ForEach(elements, id: idKey) { element in
            chrome(for: element)
        }
    }

    @ViewBuilder
    private func chrome(for element: Data.Element) -> some View {
        let id = element[keyPath: idKey]
        let isSel = selection.wrappedValue.contains(id)
        let isCur = isFocused && cursor == id
        let isHov = hovered == id
        let state = GridCellState(isSelected: isSel, isHovered: isHov, isFocused: isCur)

        cellBuilder(element, state)
            .modifier(AspectModifier(ratio: aspectRatio))
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(fillColor(selected: isSel, hovered: isHov))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(strokeColor(selected: isSel, hovered: isHov),
                                  lineWidth: isSel ? 2 : 1)
            )
            .overlay(focusRing(isCur))
            .shadow(color: shadowColor(selected: isSel, hovered: isHov),
                    radius: (isSel || isHov) ? 4 : 0, x: 0, y: (isSel || isHov) ? 2 : 0)
            .contentShape(Rectangle())
            .onHover { inside in hovered = inside ? id : (hovered == id ? nil : hovered) }
            .gesture(TapGesture(count: 2).onEnded { onActivate?(id) })
            .onTapGesture { selectOnly(id); cursor = id; isFocused = true }
            .gesture(TapGesture().modifiers(.command).onEnded { toggle(id); cursor = id })
    }

    @ViewBuilder
    private func focusRing(_ on: Bool) -> some View {
        if on {
            RoundedRectangle(cornerRadius: corner + focusOutset, style: .continuous)
                .strokeBorder(Color(nsColor: palette.primary), lineWidth: 2)
                .padding(-focusOutset)
        }
    }

    // MARK: colours (canonical roles)
    private func fillColor(selected: Bool, hovered: Bool) -> Color {
        if selected { return Color(nsColor: palette.selection).opacity(0.30) }
        if hovered  { return Color(nsColor: palette.hover).opacity(0.22) }
        return Color(nsColor: palette.muted).opacity(0.08)
    }
    private func strokeColor(selected: Bool, hovered: Bool) -> Color {
        if selected { return Color(nsColor: palette.primary).opacity(0.70) }
        if hovered  { return Color(nsColor: palette.foreground).opacity(0.45) }
        return Color(nsColor: palette.border).opacity(0.50)
    }
    private func shadowColor(selected: Bool, hovered: Bool) -> Color {
        guard selected || hovered else { return .clear }
        let sh = palette.shadow(.dp2)
        return Color(nsColor: palette.foreground).opacity(sh.opacity)
    }

    // MARK: selection
    private func selectOnly(_ id: ID) { selection.wrappedValue = [id] }
    private func toggle(_ id: ID) {
        if selection.wrappedValue.contains(id) { selection.wrappedValue.remove(id) }
        else { selection.wrappedValue.insert(id) }
    }

    // MARK: keyboard
    private func crossWidth(_ geo: GeometryProxy) -> CGFloat {
        (axis == .vertical ? geo.size.width : geo.size.height) - pad * 2
    }
    private func recomputeColumns(width: CGFloat) {
        switch layout {
        case .fixed(let n): resolvedColumns = Swift.max(n, 1)
        case .adaptive(let minW):
            resolvedColumns = gridColumns(availableWidth: width, minCellWidth: minW,
                                          gap: gap, max: Swift.max(ids.count, 1))
        }
    }
    private func move(_ direction: MoveCommandDirection) {
        guard !ids.isEmpty else { return }
        let current = cursor.flatMap { ids.firstIndex(of: $0) } ?? 0
        let (dx, dy): (Int, Int)
        switch direction {
        case .left:  (dx, dy) = (-1, 0)
        case .right: (dx, dy) = (1, 0)
        case .up:    (dx, dy) = (0, -1)
        case .down:  (dx, dy) = (0, 1)
        @unknown default: (dx, dy) = (0, 0)
        }
        let next = nextGridIndex(from: current, dx: dx, dy: dy,
                                 count: ids.count, columns: resolvedColumns, wrap: false)
        cursor = ids[next]
        selectOnly(ids[next])
    }
}

/// Applies a fixed width/height ratio to a cell when requested; a no-op otherwise.
private struct AspectModifier: ViewModifier {
    let ratio: CGFloat?
    func body(content: Content) -> some View {
        if let ratio { content.aspectRatio(ratio, contentMode: .fit) }
        else { content }
    }
}
```

- [ ] **Step 2: Build locally**

Run: `swift build`
Expected: builds with no errors.
(If `TapGesture().modifiers(.command)` fails to resolve on the macOS 13 SDK, wrap that one line in `if #available(macOS 14, *)` and drop cmd-click multi-select on 13 — selection via the `Binding<Set<ID>>` still works programmatically.)

- [ ] **Step 3: Commit**

```bash
git add Sources/ThemeKitUI/ThemedGridView.swift
git commit -m ":sparkles: feat(ThemeKitUI): #17e ThemedGridView — themed grid, selection seam, 2D keyboard nav (t-99za)"
```

---

### Task 5: `ThemedThumbnailGridView` convenience + single-select init

**Files:**
- Create: `Sources/ThemeKitUI/ThemedThumbnailGridView.swift`

**Interfaces:**
- Consumes: `ThemedGridView` (Task 4), `ThemedThumbnailCell` (Task 3), `GridLayout` (Task 2).
- Produces (used by Task 6):
  - `public struct ThumbnailItem: Identifiable, Sendable { public let id: String; public var image: NSImage?; public var label: String?; public init(id: String, image: NSImage?, label: String?) }`
  - `public struct ThemedThumbnailGridView: View` with a `Binding<Set<String>>?` (multi) init AND a `Binding<String?>?` (single) init.

- [ ] **Step 1: Write the file**

Create `Sources/ThemeKitUI/ThemedThumbnailGridView.swift`:
```swift
import SwiftUI
import PaletteKit

// ThemeKitUI — the batteries-included form of `ThemedGridView` (#17e): pass a list
// of {id, image?, label?} and get a themed thumbnail grid with the default
// `ThemedThumbnailCell`. Two inits: multi-select (`Binding<Set<String>>`) and
// single-select (`Binding<String?>`, bridged to a 0/1 set internally).

public struct ThumbnailItem: Identifiable, Sendable {
    public let id: String
    public var image: NSImage?
    public var label: String?
    public init(id: String, image: NSImage?, label: String? = nil) {
        self.id = id; self.image = image; self.label = label
    }
}

public struct ThemedThumbnailGridView: View {
    private let items: [ThumbnailItem]
    private let selection: Binding<Set<String>>?
    private let layout: GridLayout
    private let axis: Axis
    private let aspectRatio: CGFloat?
    private let palette: ResolvedPalette
    private let onActivate: ((String) -> Void)?

    /// Multi-select (or uncontrolled when `selection == nil`).
    public init(_ items: [ThumbnailItem],
                selection: Binding<Set<String>>? = nil,
                layout: GridLayout = .adaptive(minCellWidth: 160),
                axis: Axis = .vertical,
                aspectRatio: CGFloat? = nil,
                palette: ResolvedPalette,
                onActivate: ((String) -> Void)? = nil) {
        self.items = items
        self.selection = selection
        self.layout = layout
        self.axis = axis
        self.aspectRatio = aspectRatio
        self.palette = palette
        self.onActivate = onActivate
    }

    /// Single-select convenience — bridges a `Binding<String?>` to the 0/1 set.
    public init(_ items: [ThumbnailItem],
                selection single: Binding<String?>,
                layout: GridLayout = .adaptive(minCellWidth: 160),
                axis: Axis = .vertical,
                aspectRatio: CGFloat? = nil,
                palette: ResolvedPalette,
                onActivate: ((String) -> Void)? = nil) {
        let bridged = Binding<Set<String>>(
            get: { single.wrappedValue.map { [$0] } ?? [] },
            set: { single.wrappedValue = $0.first }
        )
        self.init(items, selection: bridged, layout: layout, axis: axis,
                  aspectRatio: aspectRatio, palette: palette, onActivate: onActivate)
    }

    public var body: some View {
        ThemedGridView(items, id: \.id, selection: selection,
                       layout: layout, axis: axis, aspectRatio: aspectRatio,
                       palette: palette, onActivate: onActivate) { item, _ in
            ThemedThumbnailCell(image: item.image, label: item.label, palette: palette)
        }
    }
}
```

- [ ] **Step 2: Build locally**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/ThemeKitUI/ThemedThumbnailGridView.swift
git commit -m ":sparkles: feat(ThemeKitUI): #17e ThemedThumbnailGridView convenience (single/multi-select) (t-99za)"
```

---

### Task 6: prism showcase — `MockThumbnailGrid` + gallery wiring

**Files:**
- Create: `Sources/prism/GridShowcase.swift`
- Modify: `Sources/prism/Gallery.swift` (add one line under `case .collection`)

**Interfaces:**
- Consumes: `ThemedThumbnailGridView`, `ThumbnailItem`, `GridLayout` (Tasks 2/5); `ResolvedPalette`; prism's `kitComponent`/`WidgetSection`.
- Produces: `struct MockThumbnailGrid: View` (used by `Gallery.widgetFamily`).

- [ ] **Step 1: Write the showcase**

Create `Sources/prism/GridShowcase.swift`:
```swift
// prism — ThemeKitUI thumbnail-grid bench (#17e). Shows the native `ThemedGridView`
// across states in every theme using DETERMINISTIC dummy thumbnails (solid colour
// swatches drawn into NSImage — ScreenCaptureKit is backstage, never used here).

import SwiftUI
import AppKit
import PaletteKit
import ThemeKitUI

struct MockThumbnailGrid: View {
    let p: ResolvedPalette

    private func swatch(_ nsColor: NSColor, _ size: CGFloat = 120) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        nsColor.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        img.unlockFocus()
        return img
    }

    private var loadedItems: [ThumbnailItem] {
        let roles: [(NSColor, String)] = [
            (p.primary, "primary"), (p.secondary, "secondary"), (p.muted, "muted"),
            (p.tertiary, "tertiary"), (p.border, "border"), (p.foreground, "fg"),
        ]
        return roles.enumerated().map { i, r in
            ThumbnailItem(id: "c\(i)", image: swatch(r.0), label: r.1)
        }
    }

    // A few cells with nil image to show the SwiftUI shimmer.
    private var loadingItems: [ThumbnailItem] {
        (0..<3).map { ThumbnailItem(id: "l\($0)", image: nil, label: "loading") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ThemeKitUI · ThemedGridView — native themed thumbnail grid (#17e)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // Vertical adaptive grid (default).
            ThemedThumbnailGridView(loadedItems + loadingItems,
                                    selection: .constant(["c0"]),   // show a selected cell
                                    layout: .adaptive(minCellWidth: 96),
                                    aspectRatio: 1, palette: p)
                .frame(height: 240)

            Text("horizontal rail strip · fixed-3 grid").font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(nsColor: p.muted))

            // Horizontal rail strip.
            ThemedThumbnailGridView(loadedItems,
                                    layout: .fixed(columns: 1),
                                    axis: .horizontal, aspectRatio: 1, palette: p)
                .frame(height: 110)
        }
    }
}
```

- [ ] **Step 2: Wire it into the gallery**

In `Sources/prism/Gallery.swift`, in `widgetFamily(p:)` under `case .collection:` (after the `ThemedMenu` line), add:
```swift
            WidgetSection(kitComponent("ThemedGrid"), p: p) { MockThumbnailGrid(p: p) }
```

- [ ] **Step 3: Build locally**

Run: `swift build`
Expected: builds with no errors (prism target compiles).

- [ ] **Step 4: Commit**

```bash
git add Sources/prism/GridShowcase.swift Sources/prism/Gallery.swift
git commit -m ":sparkles: feat(prism): #17e ThemedGrid showcase across all themes (t-99za)"
```

---

### Task 7: Final verification + PR

**Files:** none (verification + PR).

- [ ] **Step 1: Full clean build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 2: prism live render (maintainer gate — agents cannot screen-record)**

Per [`prism` recipe](../../../CLAUDE.md): launch `.build/debug/prism` with a `PRISM_CONFIG` toml, get the window id, `screencapture -l<winid> -o out.png`. Switch to the **Kit → collection** family tab to see the `ThemedGrid` card. Confirm across ≥3 themes: rest/hover/selected/focused chrome, the SwiftUI shimmer cells, adaptive vs fixed, vertical grid vs horizontal strip. (This is the maintainer's visual sign-off; do not claim the widget works off an unrun render.)

- [ ] **Step 3: Open the PR with the tracker footer**

```bash
git push -u origin feat/17e-themed-grid
gh pr create --title ":sparkles: feat(ThemeKitUI): #17e themed thumbnail Grid — native SwiftUI ThemedGridView + GridCore" --body "$(cat <<'BODY'
#17e — general, 100% SwiftUI-native themed thumbnail grid for ThemeKitUI, backed
by a pure GridCore target, with a prism showcase. DnD and rail carousel/hero are
out of scope (design spec §3.2/§11). Core targets macOS 13; DnD lands at the
macOS-26 milestone alongside #17b.

Design: docs/superpowers/specs/2026-06-29-17e-themed-grid-design.md
Plan: docs/superpowers/plans/2026-06-29-17e-themed-grid.md

- [ ] CI green (swift build + GridCoreTests + lint)
- [ ] prism live (maintainer): rest/hover/selected/focused, shimmer, adaptive/fixed, vertical/horizontal

SetStatus-task: https://github.com/akira-toriyama/projects/blob/main/.furrow/bodies/t-99za.md done
BODY
)"
```

- [ ] **Step 4: After CI green + prism OK — squash-merge + tag**

Per [[ci-green-merge-ok]] (CI green + clean ⇒ squash-merge without re-asking; this is within the #15–#17 blanket OK). On merge the PR footer auto-moves `t-99za` → done. Then tag the new minor:
```bash
git tag v1.33.0 && git push origin v1.33.0
```
Update `docs/ROADMAP.md` #17e to ✅ 完了 (design-record style) if desired.

---

## Self-Review

**1. Spec coverage:**
- §3.1 core (layout/theming/selection/hover/focus/activation/skeleton/content-agnostic/default cell/axis) → Tasks 2–5. ✓
- §3.2 deferred (DnD/carousel) → explicitly out; noted in PR body + GridCore comment (GridDnD布石). ✓
- §4.1 GridCore pure fns → Task 1. ✓
- §4.2 ThemedGridView/GridLayout/GridCellState/ThemedThumbnailCell/ThemedThumbnailGridView → Tasks 2–5. ✓
- §5 cell visuals (role/token table) → Task 4 `fillColor`/`strokeColor`/`focusRing`/`shadowColor` + Task 3 cell. ✓
- §6 prism → Task 6. ✓
- §7 tests → Task 1 (GridCore CI tests); SwiftUI views verified in prism (Task 7). ✓
- §8 versioning v1.33.0 → Task 7. ✓
- §10 open items: GridCore as new target (Task 1 ✓), single-select init (Task 5 ✓), aspectRatio nil = square (Task 1 `gridCellSize` + Task 4 AspectModifier no-op ✓).

**Spec refinement applied:** §3.1/§5/§6 named `ThemedSkeletonView`, but that is AppKit-backed (`NSViewRepresentable`). To honour the AppKit-zero acceptance criterion (§9.4), the cell uses a SwiftUI-native `ShimmerPlaceholder` instead. The design spec is updated to match in the same commit as this plan.

**2. Placeholder scan:** No TBD/TODO; every code step has complete code. ✓

**3. Type consistency:** `gridColumns`/`gridCellSize`/`nextGridIndex`/`reconcileGridSelection` (Task 1) consumed with matching signatures in Task 4. `GridLayout`/`GridCellState` (Task 2) used in Tasks 4/5. `ThumbnailItem`/`ThemedThumbnailGridView` (Task 5) used in Task 6. `ThemedThumbnailCell.init(image:label:palette:)` (Task 3) called in Task 5. ✓
