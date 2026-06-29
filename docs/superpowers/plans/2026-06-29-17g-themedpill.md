# ThemedPill (#17g) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `ThemedPillView` — a pure-SwiftUI display/indicator pill (5 shapes, two-color typed-prefix label, idle/matched/miss states, frost, drop shadow, corner badge) that absorbs perch's universal hint-pill, with a prism showcase live across all themes.

**Architecture:** New `Sources/ThemeKitUI/ThemedPillView.swift` — a `View` (NOT an `NSViewRepresentable`; no new AppKit). The pill SURFACE composes the existing `ThemedBackdropView<S: Shape>`; frost = SwiftUI `.ultraThinMaterial`; drop shadow = native `.shadow`; shapes = `Capsule`/`RoundedRectangle`/`Circle`/custom `TagShape` type-erased via `AnyShape` (macOS 13+). Pure label/shape/state logic lives in an `enum PillLogic` (the XCTest surface). `ThemedChip` is untouched (interactive token stays its job).

**Tech Stack:** Swift / SwiftUI / SwiftPM. macOS 13 floor. ThemeKitUI module. New `ThemeKitUITests` target.

**Spec:** [docs/superpowers/specs/2026-06-29-17g-themedpill-design.md](../specs/2026-06-29-17g-themedpill-design.md)

## Global Constraints

- **Local gate = `swift build`** (CommandLineTools only). `swift test` / `import XCTest` does NOT run locally — XCTest is **CI-only** (`.github/workflows/build.yml`). So: author tests for CI, but locally gate every task on `swift build`, and prove UI LIVE in prism.
- **AppKit policy**: ThemedPill is pure SwiftUI. Add ZERO `NSViewRepresentable` / `NSView` / `NSShadow`. AppKit floor stays at 2 (IME edit-core + window shell). Do not widen.
- **Theming**: canonical `ResolvedPalette` roles ONLY (`background foreground muted tertiary primary secondary border hover selection error` + `backgroundAlpha backgroundMode`). Never invent role names. Accent affordance = `primary`.
- **Commits**: gitmoji + Conventional Commits, English subject. `feat(ThemeKitUI): …` for the widget; `feat(prism): …` for the showcase. End every commit body with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Isolation**: all work in worktree `feat-17g-themedpill` (branched off `origin/main` @ #17e).
- **Deferred (do NOT build here)**: neon/hue-cycle effect border (→ #17k), DisplayLink→Combine clock + cascade/radial menu placement (separate t-kjcr parts), perch motion choreography (app-side essential — ThemedPill only passes `transform`/`opacity` through).

---

### Task 1: Pure logic (`PillLogic`) + enums + test target

**Files:**
- Create: `Sources/ThemeKitUI/ThemedPillView.swift` (enums + `PillLogic` + struct shell with two-color label body)
- Modify: `Package.swift:195` (add `ThemeKitUITests` target after the `ThemeKitTests` line)
- Test: `Tests/ThemeKitUITests/PillLogicTests.swift`

**Interfaces:**
- Produces: `ThemedPillView.Shape { pill, square, circle, underline, tag }`, `ThemedPillView.State { idle, matched, miss }`, and `enum PillLogic` with `splitLabel(_:typedCount:) -> (prefix:String, suffix:String)`, `isCircleEligible(_:) -> Bool`, `resolvedShape(_:label:) -> ThemedPillView.Shape`, `prefixUsesError(_:) -> Bool`. Also the full `ThemedPillView` value type (init + stored props) consumed by Task 2/3.

- [ ] **Step 1: Write the failing test**

`Tests/ThemeKitUITests/PillLogicTests.swift`:
```swift
import XCTest
@testable import ThemeKitUI

final class PillLogicTests: XCTestCase {
    func test_splitLabel_clampsAndSplits() {
        XCTAssertEqual(PillLogic.splitLabel("ABC", typedCount: 0).prefix, "")
        XCTAssertEqual(PillLogic.splitLabel("ABC", typedCount: 0).suffix, "ABC")
        XCTAssertEqual(PillLogic.splitLabel("ABC", typedCount: 1).prefix, "A")
        XCTAssertEqual(PillLogic.splitLabel("ABC", typedCount: 1).suffix, "BC")
        XCTAssertEqual(PillLogic.splitLabel("ABC", typedCount: 3).suffix, "")
        XCTAssertEqual(PillLogic.splitLabel("ABC", typedCount: 9).prefix, "ABC")  // clamp high
        XCTAssertEqual(PillLogic.splitLabel("ABC", typedCount: -2).prefix, "")    // clamp low
        XCTAssertEqual(PillLogic.splitLabel("", typedCount: 1).prefix, "")        // empty
    }

    func test_circleEligibility_singleGlyphOnly() {
        XCTAssertTrue(PillLogic.isCircleEligible("A"))
        XCTAssertTrue(PillLogic.isCircleEligible(""))
        XCTAssertFalse(PillLogic.isCircleEligible("AB"))
    }

    func test_resolvedShape_circleFallsBackToPillWhenMultiChar() {
        XCTAssertEqual(PillLogic.resolvedShape(.circle, label: "A"), .circle)
        XCTAssertEqual(PillLogic.resolvedShape(.circle, label: "AB"), .pill)
        XCTAssertEqual(PillLogic.resolvedShape(.tag, label: "AB"), .tag)        // others unchanged
        XCTAssertEqual(PillLogic.resolvedShape(.underline, label: "AB"), .underline)
    }

    func test_prefixUsesError_onlyOnMiss() {
        XCTAssertTrue(PillLogic.prefixUsesError(.miss))
        XCTAssertFalse(PillLogic.prefixUsesError(.idle))
        XCTAssertFalse(PillLogic.prefixUsesError(.matched))
    }
}
```

- [ ] **Step 2: Verify it fails (CI-gated locally)**

Run: `swift build` — Expected: FAIL (`PillLogic` / `ThemedPillView` undefined). (`swift test` is CI-only; the build failure is the local RED signal that the symbols don't exist yet.)

- [ ] **Step 3: Add the test target to `Package.swift`**

After line 195 (`.testTarget(name: "ThemeKitTests", …)`) insert:
```swift
        .testTarget(name: "ThemeKitUITests", dependencies: ["ThemeKitUI", "PaletteKit", "Palette"]),
```

- [ ] **Step 4: Write the minimal implementation**

`Sources/ThemeKitUI/ThemedPillView.swift`:
```swift
import SwiftUI
import AppKit
import Palette
import PaletteKit

// MARK: - Pure logic (deterministic XCTest surface; no SwiftUI/AppKit)

/// Palette-free, SwiftUI-free helpers for ThemedPill. The whole point is that
/// these are unit-testable in CI without a window or a resolved palette.
enum PillLogic {
    /// Split `label` into a typed prefix (first `typedCount` chars, clamped to
    /// `0...count`) and the remaining suffix.
    static func splitLabel(_ label: String, typedCount: Int) -> (prefix: String, suffix: String) {
        let n = max(0, min(typedCount, label.count))
        let cut = label.index(label.startIndex, offsetBy: n)
        return (String(label[label.startIndex..<cut]), String(label[cut...]))
    }

    /// A `.circle` pill is only drawn as a circle for a single glyph (perch parity).
    static func isCircleEligible(_ label: String) -> Bool { label.count <= 1 }

    /// `.circle` degrades to `.pill` for multi-glyph labels; every other shape is
    /// returned unchanged.
    static func resolvedShape(_ requested: ThemedPillView.Shape,
                              label: String) -> ThemedPillView.Shape {
        (requested == .circle && !isCircleEligible(label)) ? .pill : requested
    }

    /// The typed prefix is drawn in the error colour on a miss, else the accent.
    static func prefixUsesError(_ state: ThemedPillView.State) -> Bool { state == .miss }
}

// MARK: - ThemedPillView (display / indicator pill; pure SwiftUI)

public struct ThemedPillView: View {
    public enum Shape: Equatable, Sendable { case pill, square, circle, underline, tag }
    public enum State: Equatable, Sendable { case idle, matched, miss }

    public var palette: ResolvedPalette
    public var label: String
    public var shape: Shape
    public var state: State
    public var typedCount: Int
    public var badge: String?
    public var accent: Color?
    public var surfaceAlpha: Double?
    public var frosted: Bool
    public var elevated: Bool
    public var transform: CGAffineTransform
    public var opacity: Double

    public init(palette: ResolvedPalette,
                label: String,
                shape: Shape = .pill,
                state: State = .idle,
                typedCount: Int = 0,
                badge: String? = nil,
                accent: Color? = nil,
                surfaceAlpha: Double? = nil,
                frosted: Bool = false,
                elevated: Bool = true,
                transform: CGAffineTransform = .identity,
                opacity: Double = 1) {
        self.palette = palette
        self.label = label
        self.shape = shape
        self.state = state
        self.typedCount = typedCount
        self.badge = badge
        self.accent = accent
        self.surfaceAlpha = surfaceAlpha
        self.frosted = frosted
        self.elevated = elevated
        self.transform = transform
        self.opacity = opacity
    }

    // Colours (canonical roles only)
    private var accentColor: Color { accent ?? Color(nsColor: palette.primary) }
    private var foreground: Color { Color(nsColor: palette.foreground) }
    private var errorColor: Color { Color(nsColor: palette.error) }
    private var prefixColor: Color { PillLogic.prefixUsesError(state) ? errorColor : accentColor }
    private var labelFont: Font { Font(palette.uiFont(.body) as CTFont).weight(.semibold) }

    /// Two-color typed-prefix label: first `typedCount` chars in `prefixColor`,
    /// the rest in `foreground`.
    private var labelView: some View {
        let parts = PillLogic.splitLabel(label, typedCount: typedCount)
        return (Text(parts.prefix).foregroundColor(prefixColor)
                + Text(parts.suffix).foregroundColor(foreground))
            .font(labelFont)
            .lineLimit(1)
            .fixedSize()
    }

    // Task 1 body = just the label. Task 2 composes the surface/border/effects.
    public var body: some View {
        labelView.padding(.horizontal, 10).padding(.vertical, 4)
    }
}
```

- [ ] **Step 5: Verify it builds**

Run: `swift build` — Expected: PASS (compiles clean). (CI will run `PillLogicTests`; the four tests are pure and must pass there.)

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/ThemeKitUI/ThemedPillView.swift Tests/ThemeKitUITests/PillLogicTests.swift
git commit -m ":sparkles: feat(ThemeKitUI): #17g ThemedPill — pure label/shape/state logic + two-color label scaffold (t-kjcr)"
```
(append the Co-Authored-By trailer)

---

### Task 2: ThemedPillView rendering — surface, shapes, states, frost, shadow, badge

**Files:**
- Modify: `Sources/ThemeKitUI/ThemedPillView.swift` (replace the Task-1 stub `body`; add `TagShape`, `PillShadow`)

**Interfaces:**
- Consumes: Task 1's `PillLogic`, the enums, the stored props, `labelView`. `ThemedBackdropView(palette:in:fill:)` from `ThemedBackdropView.swift:50` with `BackdropFill.scrim(opacity:)`.
- Produces: a fully rendered pill. `TagShape: Shape` (rounded rect + left triangle).

- [ ] **Step 1: Replace the `body` + add helpers**

In `ThemedPillView.swift`, replace the Task-1 `public var body` with:
```swift
    private var kind: Shape { PillLogic.resolvedShape(shape, label: label) }

    private var pillShape: AnyShape {
        switch kind {
        case .pill:      return AnyShape(Capsule())
        case .square:    return AnyShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
        case .circle:    return AnyShape(Circle())
        case .tag:       return AnyShape(TagShape())
        case .underline: return AnyShape(Rectangle())   // never drawn as a surface
        }
    }

    public var body: some View {
        content
            .compositingGroup()
            .modifier(PillShadow(palette: palette, enabled: elevated && kind != .underline))
            .transformEffect(transform)
            .opacity(opacity)
    }

    @ViewBuilder
    private var content: some View {
        if kind == .underline { underlineContent } else { filledContent }
    }

    /// Filled/bordered shapes: scrim surface (+ optional Material frost) under the
    /// two-color label, a state-driven border, and an optional corner badge.
    private var filledContent: some View {
        labelView
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                ZStack {
                    if frosted { pillShape.fill(.ultraThinMaterial) }
                    ThemedBackdropView(palette: palette, in: pillShape,
                                       fill: .scrim(opacity: surfaceAlpha ?? 1))
                }
            }
            .overlay { borderOverlay }
            .overlay(alignment: .topTrailing) { badgeView }
    }

    /// Underline: no surface/border — a 2pt accent bar under the label.
    private var underlineContent: some View {
        labelView
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(state == .miss ? errorColor : accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 4)
            }
            .overlay(alignment: .topTrailing) { badgeView }
    }

    /// Tri-state border. matched = accent stroke + a native glow shadow on the
    /// stroke (fill unchanged); miss = error stroke; idle = accent hairline.
    @ViewBuilder
    private var borderOverlay: some View {
        switch state {
        case .idle:
            pillShape.stroke(accentColor.opacity(0.55), lineWidth: 1)
        case .matched:
            pillShape.stroke(accentColor, lineWidth: 2)
                .shadow(color: accentColor.opacity(0.5), radius: 7)
        case .miss:
            pillShape.stroke(errorColor, lineWidth: 2)
        }
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge {
            Text(badge)
                .font(Font(palette.uiFont(.caption) as CTFont).weight(.semibold))
                .foregroundColor(accentColor)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .offset(x: 4, y: -4)
        }
    }
```

- [ ] **Step 2: Add `PillShadow` + `TagShape` at file end**

```swift
// MARK: - Themed drop shadow (Elevation.dp2 token)

private struct PillShadow: ViewModifier {
    let palette: ResolvedPalette
    let enabled: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            let s = palette.shadow(.dp2)   // (opacity: Float, radius: CGFloat, offsetY: CGFloat)
            content.shadow(color: .black.opacity(Double(s.opacity)),
                           radius: s.radius, x: 0, y: s.offsetY)
        } else {
            content
        }
    }
}

// MARK: - Tag shape: rounded rect + left-pointing triangle (one path)

struct TagShape: Shape {
    var radius: CGFloat = 10
    var notch: CGFloat = 6        // how far the point pokes left of the body
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let body = CGRect(x: rect.minX + notch, y: rect.minY,
                          width: max(0, rect.width - notch), height: rect.height)
        p.addRoundedRect(in: body, cornerSize: CGSize(width: radius, height: radius))
        var tri = Path()
        tri.move(to: CGPoint(x: body.minX, y: rect.midY - 4))
        tri.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        tri.addLine(to: CGPoint(x: body.minX, y: rect.midY + 4))
        tri.closeSubpath()
        p.addPath(tri)
        return p
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build` — Expected: PASS. If `palette.uiFont(.body)` / `.shadow(.dp2)` complains about actor isolation, mark `public struct ThemedPillView: View` and `PillShadow` `@MainActor` (match the call sites in prism `Gallery.swift`). If `AnyShape` is unavailable, the deployment target is wrong — confirm `platforms: [.macOS(.v13)]` (it is).

- [ ] **Step 4: Commit**

```bash
git add Sources/ThemeKitUI/ThemedPillView.swift
git commit -m ":sparkles: feat(ThemeKitUI): #17g ThemedPill rendering — 5 shapes, tri-state border, frost, drop shadow, corner badge (t-kjcr)"
```
(append the Co-Authored-By trailer)

---

### Task 3: prism showcase — `MockThemedPill` + registration

**Files:**
- Create: `Sources/prism/PillShowcase.swift`
- Modify: `Sources/prism/Gallery.swift:352` (register under `.action`, after the ThemedChip line)
- Modify: `Sources/prism/KitCatalog.swift:197` (add the `ThemedPill` copy-ref entry after the ThemedChip entry)

**Interfaces:**
- Consumes: `ThemedPillView` (Task 1/2), `WidgetSection(_:p:content:)` (`Gallery.swift:426`), `kitComponent(_:)` (`KitCatalog.swift:511`), `sysFont(_:weight:design:)` (`Gallery.swift:22`).

- [ ] **Step 1: Create `MockThemedPill`**

`Sources/prism/PillShowcase.swift`:
```swift
import SwiftUI
import Palette
import PaletteKit
import ThemeKitUI

/// prism showcase for ThemedPill. Named `MockThemedPill` to avoid colliding with
/// the perch app-specimen `MockPill` (Specimens.swift). prism imports ThemeKitUI
/// only — never an app's View.
struct MockThemedPill: View {
    let p: ResolvedPalette

    private let shapes: [(ThemedPillView.Shape, String)] = [
        (.pill, "pill"), (.square, "square"), (.circle, "circle"),
        (.underline, "underline"), (.tag, "tag"),
    ]
    private let states: [(ThemedPillView.State, String)] = [
        (.idle, "idle"), (.matched, "matched"), (.miss, "miss"),
    ]

    private func cap(_ s: String) -> some View {
        Text(s).font(sysFont(8, design: .monospaced))
            .foregroundColor(Color(nsColor: p.tertiary))
            .frame(width: 64, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // shape × state
            ForEach(states, id: \.1) { state, sname in
                HStack(spacing: 10) {
                    cap(sname)
                    ForEach(shapes, id: \.1) { shape, _ in
                        ThemedPillView(palette: p,
                                       label: shape == .circle ? "G" : "GH",
                                       shape: shape, state: state, typedCount: 1)
                    }
                }
            }
            // two-color typed-prefix progression (pill, idle)
            HStack(spacing: 10) {
                cap("typed 0→3")
                ForEach(0..<4, id: \.self) { n in
                    ThemedPillView(palette: p, label: "ABC",
                                   shape: .pill, state: .idle, typedCount: n)
                }
            }
            // frost + badge
            HStack(spacing: 10) {
                cap("frost/badge")
                ThemedPillView(palette: p, label: "F", shape: .pill,
                               surfaceAlpha: 0.3, frosted: true)
                ThemedPillView(palette: p, label: "GH", shape: .pill,
                               state: .matched, badge: "⌘")
                ThemedPillView(palette: p, label: "GH", shape: .tag, badge: "⌥")
            }
        }
        .padding(10)
    }
}
```

- [ ] **Step 2: Register in `Gallery.swift`**

After `Gallery.swift:352` (`WidgetSection(kitComponent("ThemedChip"), p: p) { MockChip(p: p) }`) add:
```swift
            WidgetSection(kitComponent("ThemedPill"), p: p) { MockThemedPill(p: p) }
```

- [ ] **Step 3: Add the catalog entry in `KitCatalog.swift`**

After the `ThemedChip` `KitComponent(…)` entry (ends `KitCatalog.swift:197`, `family: .action),`) insert:
```swift
    KitComponent(
        name: "ThemedPill", module: "ThemeKitUI",
        kind: "Display/indicator pill — perch's universal hint pill in ONE SwiftUI surface (tag/badge/status/search-indicator)",
        summary: "Pure-SwiftUI display pill: 5 shapes, two-color typed-prefix label, idle/matched/miss, frost, drop shadow, corner badge. Non-interactive (use ThemedChip for clickable tokens).",
        consumes: "A SwiftUI View: ThemedPillView(palette:label:…). Composes ThemedBackdropView for the surface; hit-test passes through (host in any SwiftUI hierarchy, e.g. a perch overlay via NSHostingView).",
        keyAPI: [
                 "palette: ResolvedPalette — theme (canonical roles only)",
                 "label: String + typedCount: Int — two-color typed-prefix (first N chars in accent/miss colour, rest in foreground)",
                 "shape: .pill / .square / .circle / .underline / .tag",
                 "state: .idle / .matched / .miss — border/glow per result (fill unchanged on matched, error wash on miss)",
                 "accent: Color? — override palette.primary (perch [overlay].accent); surfaceAlpha: Double? + frosted: Bool — translucency + .ultraThinMaterial",
                 "badge: String? — optional top-right corner badge; elevated: Bool — themed drop shadow; transform/opacity — app-driven motion passthrough",
             ],
        variants: [
                 "shape: pill (capsule) / square (r1) / circle (single-glyph, else pill) / underline (body-less + accent bar) / tag (rounded + left triangle)",
                 "state: idle (accent hairline) / matched (accent stroke + glow, fill unchanged) / miss (error fill + error border + error prefix)",
                 "fill: solid / scrim(surfaceAlpha) / frosted (Material)",
             ],
        family: .action),
```

- [ ] **Step 4: Build**

Run: `swift build` — Expected: PASS (prism target compiles with the new mock + registration).

- [ ] **Step 5: Commit**

```bash
git add Sources/prism/PillShowcase.swift Sources/prism/Gallery.swift Sources/prism/KitCatalog.swift
git commit -m ":sparkles: feat(prism): #17g ThemedPill showcase — MockThemedPill grid in the Action tab (t-kjcr)"
```
(append the Co-Authored-By trailer)

---

### Task 4: prism live verification (the UI gate)

**Files:** none (verification + screenshots only)

- [ ] **Step 1: Build prism**

Run: `swift build` — Expected: PASS. Binary at `.build/debug/prism`.

- [ ] **Step 2: Launch + capture the Action tab across themes**

Per the prism recipe (CLAUDE.md): launch `.build/debug/prism` (with a `PRISM_CONFIG` toml), get the window id, `screencapture -l<winid> -o out.png` WITHOUT osascript-activating. Switch the family tab to the kit `.action` tab. Capture several themes incl. an animatable one.

- [ ] **Step 3: Eyeball checklist (must all hold across themes)**

  - [ ] 5 shapes render correctly: pill=capsule, square=slightly-rounded, circle=single-glyph round, underline=label + 2pt bar (no surface), tag=rounded body + left point.
  - [ ] two-color prefix: typed chars in accent, remaining in foreground; the `typed 0→3` row shows the boundary advancing.
  - [ ] tri-state: idle hairline, matched accent stroke **+ glow with fill unchanged**, miss = error fill + error border + red prefix.
  - [ ] frost cell shows Material blur behind a translucent tint; badge cell shows the corner glyph top-right.
  - [ ] contrast holds on dark AND light themes (no invisible label/border).

- [ ] **Step 4: If a defect is found**, fix in `ThemedPillView.swift` (or the mock), `swift build`, re-capture, amend the relevant commit. Common likely tweaks: shadow `offsetY` sign, scrim opacity for bg-nil themes, tag triangle proportions.

- [ ] **Step 5: Record the result**

Save the verification screenshots under the scratchpad and note in the PR body which themes were checked. (No code commit unless Step 4 changed something.)

---

## Self-Review

**Spec coverage:** 5 shapes ✓ (T2/T4), two-color label ✓ (T1 logic, T2 render, T4 verify), tri-state ✓ (T2/T4), frost ✓ (T2/T4), drop shadow ✓ (T2), corner badge ✓ (T2/T4), motion passthrough ✓ (T2 `transform`/`opacity`), perch token→role bridge ✓ (ResolvedPalette consumed directly; `accent`/`surfaceAlpha` slots in init), prism showcase ✓ (T3), tests ✓ (T1), deferred items excluded ✓ (Global Constraints).

**Type consistency:** `PillLogic.resolvedShape` returns `ThemedPillView.Shape` (used by `kind`); `splitLabel` returns `(prefix:,suffix:)` (used by `labelView`); `ThemedBackdropView(palette:in:fill:)` matches `ThemedBackdropView.swift:50`; `palette.shadow(.dp2)` tuple `(opacity,radius,offsetY)` matches `PaletteKit.swift:398`; `Font(p.uiFont(role) as CTFont)` matches `Gallery.swift:580`; `WidgetSection(kitComponent("…"), p:){ … }` matches `Gallery.swift:352`; `KitComponent` field order matches the ThemedChip entry (`KitCatalog.swift:174-197`).

**Placeholder scan:** none — every step has full code + exact commands.

## Execution Handoff

Inline execution in this session (executing-plans), `swift build` gate after each task, then the prism live gate (Task 4) before PR. PR → `origin/main`; CI green ⇒ squash-merge + next-minor tag (confirm #17e's tag state at merge); PR body carries the `SetStatus-task` footer for t-kjcr.
