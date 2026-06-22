# ThemedControl Base (#14b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract a shared `ThemedControl: NSControl` base class that ThemedButton / ThemedFAB / ThemedCheckbox / ThemedChip inherit, consolidating the interaction machinery (hover/press/focus state, tracking area, mouse trio, first-responder, Space-activate, activation flash, themed focus ring, `preview*`/`fx*`) they hand-rolled byte-for-byte — a value-preserving refactor with zero visual/feel change.

**Architecture:** A `public class` (not `open` — in-module subclassing only) `@MainActor` base owns the one copy of the interaction machinery plus the focus-ring layer; per-widget divergence is exposed as overridable (non-final) seams (gates, the press trio, `keyboardActivate`, the template hooks, the ring shape), never special-cased in the base. The four widgets re-parent onto it, deleting their now-inherited copies and overriding only their seams. #14b part-2 token wiring collapses to one win: the four duplicated `2` focus-ring-outset literals become the base `focusRingOutset = Space.xxs`. ToolBar/ButtonGroup (containers) and `CornerPath` extraction are explicitly OUT (see the design spec §5).

**Tech Stack:** Swift 6 (full language mode), AppKit / QuartzCore (CALayer), `@MainActor`. Modules: ThemeKit (this work), reusing `Palette` (#13 `Space`/`Radius` tokens) and `PaletteKit` (`ResolvedPalette`, `bestContrast`, `color(for:)`, `shadow(.dpN)`) and the #14a `Shared.swift` (`layerTxn`, `themeBackingScale`).

**Design spec:** [`docs/superpowers/specs/2026-06-22-14b-themedcontrol-base-design.md`](../specs/2026-06-22-14b-themedcontrol-base-design.md). **Branch:** `feat-14b-themedcontrol` (off origin/main).

## Global Constraints

*(Every task's requirements implicitly include this section.)*

- **Value-preserving refactor — behaviour BYTE-IDENTICAL.** The ONLY intentional mechanism changes (all behaviour-identical): (1) `appearanceGate`/`focusGate` predicates stand in for bare `isEnabled` at the paint/focus sites (default = `isEnabled`, so Button/FAB unchanged; only Chip diverges, by design); (2) `focusRingOutset = Space.xxs` (= 2) replaces the four duplicated `2` literals; (3) the focus ring renders via `zPosition = 1000` instead of add-last ordering; (4) the two-tier `applyTheme`/`applyState` + `layout` become base templates with subclass hooks. **Zero intentional VALUE change** (no colour/size/timing/alpha edits).
- **Local gate = `swift build`** (CommandLineTools — the maintainer machine has no Xcode). **`swift test` (XCTest) runs in CI ONLY** (`.github/workflows/build.yml`, full Xcode). So every task verifies with `swift build` green locally; XCTest is written/updated but executes in CI. **prism before/after live capture is maintainer-delegated** (agents can't screen-record).
- **Base = `public class ThemedControl: NSControl`, `@MainActor`.** Not `open` (all subclasses in-module; apps compose, never subclass). `@available(*, unavailable) required init?(coder:)`. The flash's `DispatchQueue.main.asyncAfter` `[weak self]` stays inside the @MainActor base.
- **Reuse #14a leaf helpers** (`layerTxn`, `themeBackingScale`, `bestContrast`, `color(for:)`, `shadow(.dpN)`) — never re-create them. **`CornerPath` stays INLINE in ThemedButton** (not extracted — rule-of-three unmet).
- **TWO must-not-forget seam obligations** (silent regressions if skipped, not caught by `swift build`): every adopter that has an `onTap`/action closure MUST override `activate()` as `{ onTap?(); super.activate() }` (the base `activate()` only sends the NSControl action); every adopter MUST override `updateContentsScale(_:)` to re-scale ITS layers + re-rasterize icons (the base only re-scales the focus ring).
- **Commits:** gitmoji + Conventional Commits (commit-lint). Squash-merge. Library change ⇒ minor bump + matching `v`-prefixed git tag (next = **`v1.21.0`**).

---

### Task 1: Create the `ThemedControl` base class

**Files:**
- Create: `Sources/ThemeKit/ThemedControl.swift`
- Test: `Tests/ThemeKitTests/ThemedControlTests.swift` (added in Task 6 — CI-only)

**Interfaces:**
- Consumes: `ResolvedPalette` + `bestContrast`/`color(for:)`/`shadow(.dpN)` (PaletteKit); `layerTxn`/`themeBackingScale` (Shared.swift, #14a); `Space.xxs` (Palette, #13).
- Produces (the FIXED base API every adoption task depends on):

  - `@MainActor public class ThemedControl: NSControl`
  - `public var palette: ResolvedPalette { didSet { applyTheme() } }`
  - `public override var isEnabled: Bool { get set }`
  - `func didDisable()`
  - `public override var target: AnyObject? { get set }`
  - `public override var action: Selector? { get set }`
  - `public var keyEquivalent: String = ""`
  - `public var keyEquivalentModifierMask: NSEvent.ModifierFlags = []`
  - `var isHovered = false`
  - `var isKeyFocused = false`
  - `var isFlashing = false`
  - `var isPressed = false`
  - `public var previewHovered = false { didSet { applyState(animated: false) } }`
  - `public var previewPressed = false { didSet { applyState(animated: false) } }`
  - `public var previewFocused = false { didSet { applyState(animated: false) } }`
  - `var appearanceGate: Bool`
  - `var focusGate: Bool`
  - `var fxHovered: Bool`
  - `var fxPressed: Bool`
  - `var fxFocused: Bool`
  - `var showFocusRing: Bool`
  - `let focusRingLayer = CAShapeLayer()`
  - `public var focusRingOutset: CGFloat = CGFloat(Space.xxs)`
  - `func focusRingPath(in rect: CGRect) -> CGPath`
  - `func concentricRingPath(in rect: CGRect, radius: CGFloat, corners: CACornerMask = ThemedControl.allCorners) -> CGPath`
  - `static let allCorners: CACornerMask`
  - `public func applyTheme()`
  - `func applyThemeSnap()`
  - `func rebuildContent()`
  - `func syncAccessibility()`
  - `func applyState(animated: Bool)`
  - `func applyInteractionState()`
  - `public override func layout()`
  - `func positionLayers(in bounds: CGRect, local: CGRect)`
  - `public override func viewDidChangeBackingProperties()`
  - `func updateContentsScale(_ s: CGFloat)`
  - `public override var isFlipped: Bool`
  - `var trackingOptions: NSTrackingArea.Options`
  - `public override func updateTrackingAreas()`
  - `public override func mouseEntered(with event: NSEvent)`
  - `public override func mouseExited(with event: NSEvent)`
  - `public override func acceptsFirstMouse(for event: NSEvent?) -> Bool`
  - `func pressInside(_ event: NSEvent) -> Bool`
  - `public override func mouseDown(with event: NSEvent)`
  - `public override func mouseDragged(with event: NSEvent)`
  - `public override func mouseUp(with event: NSEvent)`
  - `public override var acceptsFirstResponder: Bool`
  - `public override func becomeFirstResponder() -> Bool`
  - `public override func resignFirstResponder() -> Bool`
  - `public override func keyDown(with event: NSEvent)`
  - `public override func performKeyEquivalent(with event: NSEvent) -> Bool`
  - `func flashThenActivate(_ action: @escaping () -> Void)`
  - `static let flashDuration: TimeInterval = 0.12`
  - `func keyboardActivate()`
  - `func sendActionToTarget()`
  - `func activate()`
  - `public init(palette: ResolvedPalette)`
  - `@available(*, unavailable) public required init?(coder: NSCoder)`


**Design notes (key decisions, must be preserved):**

Focus-ring z-order: the base draws the ring on `focusRingLayer` with `zPosition = 1000` set once in `init`. ThemedButton relied on adding the ring layer LAST so it renders above the fill/border/icon/title sublayers; since the base must add its ring BEFORE the subclass adds its own sublayers (base init runs first), add-order would put the ring underneath. Raising zPosition makes the ring render on top regardless of sublayer add-order — visually identical to Button's add-last, but order-independent (CALayer sorts siblings by zPosition then add-order, and no subclass uses zPosition, so 1000 wins).\n\nTwo-tier template without nested CATransaction: each tier opens exactly ONE `layerTxn` and the subclass hooks run INSIDE it without opening their own. `applyTheme()` opens a non-animated layerTxn, calls `applyThemeSnap()` (subclass) + sets the ring stroke, commits, THEN (outside that txn) calls `rebuildContent()` / `syncAccessibility()` (which may open their own snaps for text sizing / icon rasterization, exactly as Button's rebuildTitle/rebuildIcons did) and finally `applyState(animated:false)` which opens its own single txn for `applyInteractionState()` + ring opacity. `applyState(animated:)` opens one txn wrapping `applyInteractionState()` + the ring opacity so they cross-fade together. `layout()` opens one non-animated txn, calls `positionLayers()` then sets the ring frame+path — the subclass positions inside the base txn, never beginning its own. This mirrors Button, which positioned everything inside one `layerTxn` in `layout()`.\n\nInit ordering: base `init(palette:)` stores palette, `super.init(frame:.zero)`, sets wantsLayer / masksToBounds=false / focusRingType=.none, then builds + adds ONLY the focus ring (with zPosition). It does NOT call applyTheme() (the subclass calls it after building its own layers, so applyThemeSnap/rebuildContent have layers to touch). The subclass init = super.init(palette:) → build its layers → setAccessibilityRole → applyTheme(). themeBackingScale is read in init via the NSView extension (window is nil pre-attach → falls back to main screen / 2, same as Button's old `backingScale`).

**Behaviour-equivalence ledger (each is byte-identical to ThemedButton unless flagged):**

- mouseEntered/mouseDown/mouseDragged/mouseUp/acceptsFirstMouse: Button guarded on `isEnabled`; base guards on `appearanceGate` whose DEFAULT is `{ isEnabled }` — byte-identical for Button/FAB; only Chip (override `appearanceGate = isClickable`) sees a difference, which is the intended seam.
- acceptsFirstResponder: Button returned `isEnabled`; base returns `focusGate` (default `{ isEnabled }`) — identical for Button/FAB; Chip overrides to isInteractive.
- Focus ring opacity in updateTrackingAreas stale-hover reconcile + applyState gating uses `showFocusRing` (default `fxFocused`) — identical to Button (`showFocusRing` was `fxFocused`).
- fxHovered/fxPressed/fxFocused: Button ANDed with `isEnabled`; base ANDs with `appearanceGate` (default isEnabled) — identical for Button/FAB. BEHAVIOUR-identical.
- Focus ring inset/radius: Button used `local.insetBy(dx: -2, dy: -2)` + `radius + 2` inline in layout(); base centralizes this as `concentricRingPath` driven by `focusRingOutset = Space.xxs (=2)`. Numerically identical (2). The default `focusRingPath` is all-corners; Button OVERRIDES `focusRingPath` to use its selective-corner `closedCornerPath` so the selective rounding is preserved — BEHAVIOUR-identical for Button.
- Focus ring z-order: Button added focusRingLayer LAST (add-order on top). Base sets `zPosition = 1000`. BEHAVIOUR-identical render result (ring on top); mechanism differs by design (spec-sanctioned).
- keyDown / performKeyEquivalent / Space keyCode 49 / isARepeat swallow / keyEquivalent match: hoisted verbatim; Button's `flashAndActivate()` is now `keyboardActivate()` whose default `flashThenActivate { activate() }` is byte-identical. BEHAVIOUR-identical for Button/FAB; Checkbox overrides keyboardActivate to toggle (intended seam).
- flashThenActivate: identical to Button's flashAndActivate (0.12s via `Self.flashDuration`, isFlashing atomicity, [weak self], isPressed flash) except the deferred final call is the passed `action` closure instead of a hardcoded `self.activate()`. Default keyboardActivate passes `{ self?.activate() }`, so BEHAVIOUR-identical.
- activate(): Button's body fired `onTap?()` then `NSApp.sendAction(...)`. Base `activate()` = guard isEnabled + `sendActionToTarget()` (the sendAction half). Button must OVERRIDE activate() to call `onTap?()` then `super.activate()` to be byte-identical — flagged: the base alone does NOT fire onTap (onTap lives in the subclass), this is by design (base owns no onTap). Adoption task must add the override.
- isEnabled setter: Button cleared isHovered/isPressed + resigned FR + applyTheme(). Base adds a `didDisable()` hook call after the clear (default no-op) — BEHAVIOUR-identical for Button/FAB.
- viewDidChangeBackingProperties: Button re-scaled its specific layers + rebuildIcons inline. Base re-scales only its focusRingLayer then calls `updateContentsScale(s)` — the subclass must re-scale ITS layers + re-rasterize icons in that override to stay identical. Flagged: base alone does not touch subclass layers (by design).

**Residual risks carried into the adoption tasks:**

- activate() split: the base sends the action but does NOT fire `onTap` (that closure is a Button/FAB property, not a base concept). The Button/FAB adoption MUST override `activate()` as `{ onTap?(); super.activate() }` or onTap stops firing — a silent behavioural regression if forgotten. The contract states this; adoption tasks must honor it.
- viewDidChangeBackingProperties only re-scales the focus ring in the base; the subclass override of `updateContentsScale(_:)` MUST re-scale its own layers and re-rasterize icons (Button's old inline loop). If a subclass forgets, icons go blurry on a scale change — not caught by `swift build`, only by live prism capture.
- Button's `focusRingPath` override must reproduce `closedCornerPath(local.insetBy(dx:-2,dy:-2), radius: m.radius+2, corners: roundedCorners)`. The base helper `concentricRingPath` only handles the all-corners case (returns CGPath(roundedRect:)); Button's selective-corner ring stays inline in its override. Risk: an adopter using the base default for a selective-corner button would lose the squared seam corners.
- `themeBackingScale` is read in `init` before the view has a window (returns main-screen scale or 2). This matches Button's old `backingScale` at init time; the real scale is applied in `viewDidChangeBackingProperties`. No regression, but the base focus ring's contentsScale relies on that later callback firing — identical to Button.
- Cannot run `swift test` locally (CLT only); the fx-merge / concentric-math / disable-clear XCTests run in CI only. prism before/after live capture (hover/pressed/focused/disabled across Button/FAB/Checkbox/Chip) is maintainer-delegated — value-preservation is asserted by build + tests here, confirmed visually downstream.
- The base is a NEW file with no current subclasses; it compiles green standalone (verified `swift build`). The behavioural-equivalence claim is only fully testable once ThemedButton is migrated to inherit it (a later adoption task) — this file realizes the contract but does not yet prove byte-identity against the live Button.

- [ ] **Step 1: Create `Sources/ThemeKit/ThemedControl.swift` with the full base content below**

```swift
// ThemeKit — ThemedControl: the shared base class for sill's single-control
// themed widgets (ThemedButton / ThemedFAB / ThemedCheckbox / ThemedChip). A
// VALUE-PRESERVING extraction (#14b): each of those four hand-rolled the SAME
// interaction machinery — hover / press / keyboard-focus / activation flash,
// the tracking-area lifecycle, the cell-less NSControl storage, the
// first-responder + Space wiring, and a themed focus ring — byte-for-byte. This
// base owns that one copy; per-widget divergence is exposed as overridable seams
// (NOT special-cased here). Behaviour is IDENTICAL to the old ThemedButton: the
// only intentional mechanism changes are (1) `appearanceGate` / `focusGate`
// predicates standing in for bare `isEnabled` at the paint / focus sites
// (default = `isEnabled`, so Button / FAB are unchanged), (2) `focusRingOutset`
// = `Space.xxs` (2) replacing the four duplicated `2` literals, (3) the focus
// ring drawn on a `zPosition`-raised layer instead of relying on add-last
// ordering, and (4) the template-method hooks.
//
// Subclasses `NSControl` for the real control contract — `isEnabled`,
// `target` / `action`, `sendAction`, key activation. The base is cell-less, so
// `isEnabled` / `target` / `action` use manual storage (the cell-backed
// accessors are unreliable without a cell). The base owns NO value semantics
// (Checkbox's tri-state, glyph, a11y value all stay in the subclass) and NO
// content layers beyond the focus ring — it only positions the ring; subclasses
// own their layer trees, layout, intrinsic size, colour computation, and ring
// SHAPE.
//
// @MainActor throughout (the whole module is). `public class`, not `open`: every
// subclass lives in this same module, so non-final members are overridable
// without `open`, and we dodge open-class API-stability burden. The flash's
// `DispatchQueue.main.asyncAfter` [weak self] stays fully inside the @MainActor
// base so activation never hops off the main actor.

import AppKit
import Palette
import PaletteKit
import QuartzCore

@MainActor
public class ThemedControl: NSControl {

    // MARK: - Theme

    /// The theme. Assigning re-themes the whole control via `applyTheme()`,
    /// which the subclass specializes through the snap / content / a11y hooks.
    public var palette: ResolvedPalette { didSet { applyTheme() } }

    // MARK: - NSControl overrides (custom storage — a cell-less NSControl must
    //         NOT lean on the cell-backed isEnabled / target / action).

    private var _enabled = true
    public override var isEnabled: Bool {
        get { _enabled }
        set {
            guard _enabled != newValue else { return }
            _enabled = newValue
            // Actively clear any in-flight hover / press — a disable can strand
            // them with no matching exit / up event (the stuck-hover gotcha).
            // This cleanup is FINAL base behaviour: the setter is not
            // overridable (no super-call to forget); a subclass extends it via
            // the `didDisable()` hook instead.
            if !newValue {
                isHovered = false; isPressed = false
                if window?.firstResponder === self { window?.makeFirstResponder(nil) }
                didDisable()
            }
            applyTheme()
        }
    }

    /// Overridable hook invoked when the control transitions to disabled, AFTER
    /// the base has cleared hover / press and resigned first responder. Default
    /// no-op; a subclass adds its own teardown without overriding the `isEnabled`
    /// setter (so it can never forget to run the base cleanup).
    func didDisable() {}

    private weak var _target: AnyObject?
    private var _action: Selector?
    public override var target: AnyObject? { get { _target } set { _target = newValue } }
    public override var action: Selector?  { get { _action } set { _action = newValue } }

    // MARK: - Key activation config

    /// Optional key equivalent (AppKit dialogs want a default button). Set to
    /// `"\r"` to make this the Return-activated default button. Matched in
    /// `performKeyEquivalent` against `keyEquivalentModifierMask`.
    public var keyEquivalent: String = ""
    public var keyEquivalentModifierMask: NSEvent.ModifierFlags = []

    // MARK: - Interaction state storage

    // Core (always-on): hover / focus / flash. `isPressed` is the DEFAULT of an
    // open press seam — Button / FAB / Checkbox inherit it unchanged; Chip
    // replaces the whole trio with a PressTarget enum and never reads this Bool.
    // Subclass-visible (same module) so a subclass can read them in its colour /
    // overlay computation.
    var isHovered = false
    var isKeyFocused = false
    var isFlashing = false   // a keyboard-flash activation is in flight
    var isPressed = false

    private var trackingArea: NSTrackingArea?

    // MARK: - Preview overrides (deterministic prism capture)

    /// Force the hovered / pressed / focused APPEARANCE without real events —
    /// for previews / screenshots only. Gated controls ignore them (the `fx*`
    /// merges AND in `appearanceGate`).
    public var previewHovered = false { didSet { applyState(animated: false) } }
    public var previewPressed = false { didSet { applyState(animated: false) } }
    public var previewFocused = false { didSet { applyState(animated: false) } }

    // MARK: - Gates (overridable seams)

    /// Gates the hover / press / focus PAINT (whether interaction appearance
    /// shows at all). Default = `isEnabled`; Chip overrides to `isClickable`.
    var appearanceGate: Bool { isEnabled }

    /// Gates `acceptsFirstResponder` + the focus ring (whether the control can
    /// take keyboard focus). Default = `isEnabled`; Chip overrides to
    /// `isInteractive` (its delete button stays focusable while the body is
    /// inert).
    var focusGate: Bool { isEnabled }

    // MARK: - fx merges (overridable) — real-state || preview, AND appearanceGate

    var fxHovered: Bool { (isHovered || previewHovered) && appearanceGate }
    var fxPressed: Bool { (isPressed || previewPressed) && appearanceGate }
    var fxFocused: Bool { (isKeyFocused || previewFocused) && appearanceGate }

    /// Whether the focus ring is painted. Default = `fxFocused`; an overridable
    /// seam for a widget that gates the ring differently.
    var showFocusRing: Bool { fxFocused }

    // MARK: - Focus ring (base-owned layer)

    /// The themed keyboard-focus ring. Base-owned and built in `init`; its SHAPE
    /// (path) is an overridable seam, but the layer, its stroke (= `primary`),
    /// its opacity gate, and its concentric inset math live here. `zPosition` is
    /// raised so it renders ON TOP regardless of the order the subclass adds its
    /// own sublayers — a visually-identical replacement for ThemedButton's
    /// "added last" ordering, but order-independent.
    let focusRingLayer = CAShapeLayer()

    /// How far the focus ring sits OUTSIDE the control's rounded box — the #14b
    /// token consolidation: one `Space.xxs` (2) replacing ThemedButton's `-2`/
    /// `+2` pair, FAB's `ringInset` 2, Chip's `-2`, and Checkbox's `focusInset`
    /// 2. Drives BOTH the rect inset (`-outset`) AND the radius bump
    /// (`+outset`), so the concentric pair never desyncs.
    public var focusRingOutset: CGFloat = CGFloat(Space.xxs)   // = 2

    /// The focus-ring path for the current geometry. Overridable seam: the
    /// default is an all-corners concentric ring; Button overrides with its
    /// selective-corner builder, FAB with a circle, Checkbox with a small
    /// rounded box, Chip with a full pill. `local` is the bounds-origin rect.
    func focusRingPath(in rect: CGRect) -> CGPath {
        concentricRingPath(in: rect, radius: 0, corners: Self.allCorners)
    }

    /// The shared concentric-ring builder: insets `rect` by `-focusRingOutset`
    /// (so the ring sits outside the box) and bumps the radius by
    /// `+focusRingOutset` (so the rounded ring stays concentric with the box).
    /// All-corners ⇒ a plain `CGPath(roundedRect:)` (byte-identical to the old
    /// per-widget code); selective-corner ring construction stays inline in
    /// Button (CornerPath is deliberately NOT extracted — rule-of-three unmet).
    func concentricRingPath(in rect: CGRect, radius: CGFloat,
                            corners: CACornerMask = ThemedControl.allCorners) -> CGPath {
        let r = rect.insetBy(dx: -focusRingOutset, dy: -focusRingOutset)
        return CGPath(roundedRect: r,
                      cornerWidth: radius + focusRingOutset,
                      cornerHeight: radius + focusRingOutset,
                      transform: nil)
    }

    static let allCorners: CACornerMask =
        [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner, .layerMinXMaxYCorner]

    // MARK: - Two-tier theming template (base owns the transactions + the focus
    //         ring; the subclass fills its own layers via the hooks)

    /// Re-theme: snaps the STABLE visuals (subclass fill / border / shadow via
    /// `applyThemeSnap`, plus the focus-ring stroke) in a non-animated
    /// transaction, then rebuilds content, syncs a11y, settles the interaction
    /// state, and requests layout. Snapping (not cross-fading) matches the other
    /// widgets — a theme switch must not smear.
    public func applyTheme() {
        layerTxn(animated: false) {
            self.applyThemeSnap()
            self.focusRingLayer.strokeColor = self.palette.primary.cgColor
        }
        rebuildContent()
        syncAccessibility()
        applyState(animated: false)
        needsLayout = true
    }

    /// Overridable: snap the subclass's stable visuals — fill colour, border
    /// visibility / width, shadow visibility. Runs inside the base's
    /// non-animated `layerTxn` (do NOT open another transaction).
    func applyThemeSnap() {}

    /// Overridable: rebuild the subclass's content layers — title text, icons,
    /// glyph path. Runs OUTSIDE the snap transaction (these may size text /
    /// re-rasterize icons, which manage their own snaps).
    func rebuildContent() {}

    /// Overridable: sync the subclass's accessibility (label / value / enabled).
    func syncAccessibility() {}

    /// The interaction-driven layer props — animated on a real hover / press /
    /// focus change, snapped from `applyTheme` / previews / layout. The base
    /// commits the focus-ring opacity; the subclass sets its overlay / border /
    /// elevation through `applyInteractionState`. One transaction wraps both so
    /// the ring and the overlay cross-fade together.
    func applyState(animated: Bool) {
        layerTxn(animated: animated) {
            self.applyInteractionState()
            self.focusRingLayer.opacity = self.showFocusRing ? 1 : 0
        }
    }

    /// Overridable: set the subclass's interaction-driven props (state overlay,
    /// border colour, elevation). Runs inside the base's `applyState` `layerTxn`
    /// (do NOT open another transaction).
    func applyInteractionState() {}

    // MARK: - Layout template (base positions the ring; subclass positions its
    //         own layers inside the SAME transaction — no nested begin)

    public override func layout() {
        super.layout()
        layerTxn(animated: false) {
            let local = CGRect(origin: .zero, size: self.bounds.size)
            self.positionLayers(in: self.bounds, local: local)
            self.focusRingLayer.frame = self.bounds
            self.focusRingLayer.path = self.focusRingPath(in: local)
        }
    }

    /// Overridable: position the subclass's own layers. `bounds` is the view
    /// frame (y-up); `local` is the same rect at origin `.zero`. Runs inside the
    /// base's non-animated `layerTxn` (do NOT open another transaction).
    func positionLayers(in bounds: CGRect, local: CGRect) {}

    /// Keep text / strokes / symbols crisp across a display-scale change —
    /// `contentsScale` was captured once at init (before a window). The base
    /// re-scales its focus ring; the subclass re-scales its layers and
    /// re-rasterizes icons via `updateContentsScale`.
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = themeBackingScale
        focusRingLayer.contentsScale = s
        updateContentsScale(s)
    }

    /// Overridable: re-scale the subclass's layers' `contentsScale` to `s` and
    /// re-rasterize any device-scale-dependent bitmaps (icons / glyphs).
    func updateContentsScale(_ s: CGFloat) {}

    public override var isFlipped: Bool { false }   // y-up: a downward shadow is −y

    // MARK: - Tracking + mouse (hoisted from ThemedButton)

    /// The tracking-area options. Overridable seam, but every current widget
    /// uses this exact set. `.inVisibleRect` makes the `rect: .zero` area track
    /// the whole visible bounds.
    var trackingOptions: NSTrackingArea.Options {
        [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect]
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t); trackingArea = nil }
        let t = NSTrackingArea(rect: .zero, options: trackingOptions, owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
        // A geometry change can move the view out from under a stationary
        // pointer with no exit event — clear a now-false hover.
        if isHovered, let w = window {
            let local = convert(w.mouseLocationOutsideOfEventStream, from: nil)
            if !bounds.contains(local) { isHovered = false; applyState(animated: false) }
        }
    }

    public override func mouseEntered(with event: NSEvent) {
        guard appearanceGate else { return }
        isHovered = true; applyState(animated: true)
    }
    public override func mouseExited(with event: NSEvent) {
        guard isHovered else { return }
        isHovered = false; applyState(animated: true)
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { appearanceGate }

    /// Shared drag-cancel helper: is the event's location inside the bounds?
    /// Used by the mouse trio to track whether a press is still "inside" as the
    /// pointer drags.
    func pressInside(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }

    // The default Bool-`isPressed` press trio (Button / FAB / Checkbox inherit
    // unchanged; Chip overrides the whole trio for its PressTarget). A click
    // presses + activates but deliberately does NOT take first responder —
    // standard macOS push-button behaviour (keyboard focus + the themed ring
    // arrive via Tab; Return via performKeyEquivalent). A future click-to-focus
    // widget would override `mouseDown` to add a `makeFirstResponder`.
    public override func mouseDown(with event: NSEvent) {
        guard appearanceGate else { return }
        isPressed = true; applyState(animated: true)
    }
    public override func mouseDragged(with event: NSEvent) {
        guard appearanceGate else { return }
        let inside = pressInside(event)
        if inside != isPressed { isPressed = inside; applyState(animated: true) }
    }
    public override func mouseUp(with event: NSEvent) {
        guard appearanceGate else { return }
        let inside = pressInside(event)
        if isPressed { isPressed = false; applyState(animated: true) }
        if inside { activate() }
    }

    // MARK: - Keyboard + focus

    public override var acceptsFirstResponder: Bool { focusGate }

    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { isKeyFocused = true; applyState(animated: true) }
        return ok
    }
    public override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { isKeyFocused = false; applyState(animated: true) }
        return ok
    }

    public override func keyDown(with event: NSEvent) {
        if isEnabled, event.keyCode == 49 {   // Space activates the focused control
            // Activate once per press; swallow auto-repeat (a held Space must
            // not re-fire) — consume the repeat too, so it doesn't beep.
            if !event.isARepeat { keyboardActivate() }
            return
        }
        super.keyDown(with: event)
    }

    /// Return / a set key equivalent activates via the window's default-button
    /// path (delivered BEFORE keyDown, regardless of first responder).
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard isEnabled, !keyEquivalent.isEmpty,
              event.charactersIgnoringModifiers == keyEquivalent,
              mods == keyEquivalentModifierMask else {
            return super.performKeyEquivalent(with: event)
        }
        keyboardActivate()
        return true
    }

    /// A brief visible press before running `action` — keyboard activation has
    /// no natural down/up, so synthesize the flash. The `isFlashing` guard makes
    /// a single flash atomic: a second Space/Return inside the 0.12 s window is
    /// dropped (no double-fire), and the deferred block re-runs through the
    /// caller's `action` (which re-checks `isEnabled` via `activate`) so an async
    /// disable mid-flash cancels it. Stays fully on the main actor.
    func flashThenActivate(_ action: @escaping () -> Void) {
        guard !isFlashing else { return }
        isFlashing = true
        isPressed = true; applyState(animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashDuration) { [weak self] in
            guard let self else { return }
            self.isFlashing = false
            self.isPressed = false; self.applyState(animated: true)
            action()
        }
    }

    static let flashDuration: TimeInterval = 0.12

    /// Keyboard / key-equivalent activation. Default = flash, then `activate()`
    /// (Button / FAB). Overridable seam: Checkbox flashes then TOGGLES (not a
    /// fire-and-forget send) while reusing this flash helper; Chip may override.
    func keyboardActivate() {
        flashThenActivate { [weak self] in self?.activate() }
    }

    /// Send the cell-less `action` to the `target` (resolved through the
    /// responder chain when `target` is nil).
    func sendActionToTarget() {
        if let a = _action { NSApp.sendAction(a, to: _target, from: self) }
    }

    /// The activation primitive — sends the action, guarding `isEnabled`
    /// authoritatively (even against an in-flight flash). Overridable seam:
    /// Button overrides to fire its `onTap` closure first, then `super.activate()`.
    func activate() {
        guard isEnabled else { return }
        sendActionToTarget()
    }

    // MARK: - Init

    /// Designated initializer. Stores the palette, becomes layer-backed, opts out
    /// of clipping (the focus ring lives outside bounds) and AppKit's stock focus
    /// ring, then builds the base-owned focus-ring layer (raised `zPosition` so it
    /// stays on top of subclass sublayers) and adds it. A subclass calls
    /// `super.init(palette:)`, THEN builds its own layers, THEN sets its
    /// accessibility role and calls `applyTheme()`.
    public init(palette: ResolvedPalette) {
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false        // the focus ring / shadow live outside bounds
        focusRingType = .none               // we draw our own themed ring

        let s = themeBackingScale
        focusRingLayer.fillColor = NSColor.clear.cgColor
        focusRingLayer.lineWidth = 2
        focusRingLayer.opacity = 0
        focusRingLayer.contentsScale = s
        focusRingLayer.zPosition = 1000     // render on top regardless of add-order
        layer?.addSublayer(focusRingLayer)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }
}
```

- [ ] **Step 2: Verify it compiles green standalone**

Run: `swift build`
Expected: Build complete (no errors). The base has no subclasses yet, so it compiles independently; behavioural byte-identity is proven once ThemedButton adopts it (Task 2) and in CI (Task 6).

- [ ] **Step 3: Commit**

```bash
git add Sources/ThemeKit/ThemedControl.swift
git commit -m ":sparkles: feat(ThemeKit): #14b add ThemedControl base (interaction machinery + seams)"
```

---

### Task 2: Adopt ThemedControl in ThemedButton (reference adopter)

**Files:**
- `Sources/ThemeKit/ThemedButton.swift` (re-parent onto the base; delete inherited machinery; wire seams)
- `Tests/ThemeKitTests/…` (XCTest unchanged in surface — ButtonProbe stays; runs in CI)

**Interfaces:**
- Consumes the base API: `ThemedControl(palette:)`, public `applyTheme()`, the hooks `applyThemeSnap()/rebuildContent()/syncAccessibility()/applyInteractionState()/positionLayers(in:local:)/updateContentsScale(_:)/focusRingPath(in:)`, the seams `activate()` (override) + inherited `keyboardActivate()` default, inherited storage (`isHovered/isPressed/isKeyFocused/isFlashing/palette/_enabled/_target/_action/focusRingLayer/previewHovered/Pressed/Focused/keyEquivalent[ModifierMask]`), `focusRingOutset` (= Space.xxs), `themeBackingScale`, `pressInside(_:)`, `closedCornerPath` (stays inline in Button).
- Produces nothing new (public surface byte-identical: `ThemedButton(palette:)`, `variant/size/role/title/*Symbol/*Image/fullWidth/onTap/keyEquivalent…/preview…/roundedCorners/drawnBorderEdges/groupedShadow`, `#if DEBUG buttonProbe`).

This is the FIRST adopter — it establishes the base contract in practice. It is a VALUE-PRESERVING refactor: behaviour stays byte-identical. ThemedButton diverges from the base default only by (a) firing `onTap` in `activate()`, (b) a selective-corner focus ring, and (c) its own content layers/colour math — everything else is deleted as now-inherited.

- [ ] **Step 1: Re-parent the class.** Change line 48 `public final class ThemedButton: NSControl` → `public final class ThemedButton: ThemedControl`. Keep `final` and the `@MainActor` on line 47.

- [ ] **Step 2: Delete the inherited public config that the base owns.** Remove:
  - line 78 `public var palette: ResolvedPalette { didSet { applyTheme() } }` (base line 43 is identical and calls the overridden applyTheme).
  - lines 114-115 `keyEquivalent` + `keyEquivalentModifierMask` (base 84-85).
  - lines 120-122 `previewHovered`/`previewPressed`/`previewFocused` (base 106-108).
  Keep `variant/size/role/title/leadingSymbol/trailingSymbol/leadingImage/trailingImage/fullWidth/onTap` and the grouping vars `roundedCorners/drawnBorderEdges/groupedShadow` — all Button-owned.

- [ ] **Step 3: Delete the inherited NSControl storage + interaction storage.** Remove:
  - lines 145-159 the `_enabled` + `isEnabled` override (base 48-66 is identical; the base additionally calls `didDisable()`, but Button has no extra teardown, so do NOT override `didDisable`).
  - lines 161-164 `_target`/`_action`/`target`/`action` (base 74-77).
  - line 175 `private let focusRingLayer = CAShapeLayer()` (base owns it, line 140). KEEP shadowLayer/fillLayer/overlayLayer/borderLayer/leadingIconLayer/trailingIconLayer/titleLayer (lines 168-174) — Button content.
  - lines 177-181 `trackingArea`/`isHovered`/`isPressed`/`isKeyFocused`/`isFlashing` (base 99, 94-97).
  - line 187 `public override var isFlipped: Bool { false }` (base 257).
  Keep `leadingImageSize`/`trailingImageSize` (lines 184-185) — Button layout state.

- [ ] **Step 4: Delete the inherited fx merges, showFocusRing, allCorners.** Remove:
  - lines 318-320 `fxHovered`/`fxPressed`/`fxFocused` (base 124-126; Button used `&& isEnabled`, base uses `&& appearanceGate` which defaults to `isEnabled` — byte-identical since Button does NOT override appearanceGate).
  - line 362 `private var showFocusRing: Bool { fxFocused }` (base 130).
  - lines 459-460 `private static let allCorners` (base 172). The `Self.allCorners` references inside `closedCornerPath` (line 467) and the init seed of `roundedCorners` (lines 129-130, which is a literal array, unaffected) resolve to the inherited base static — same value, compiles unchanged.

- [ ] **Step 5: Replace `backingScale` with `themeBackingScale`.** Delete line 515 `private var backingScale: CGFloat { themeBackingScale }`. At its two surviving call sites change `backingScale` → `themeBackingScale`:
  - init: the `let s = backingScale` line (line 242 in the init block) → `let s = themeBackingScale`.
  - `rebuildIcons` first line (line 421) `let scale = backingScale, …` → `let scale = themeBackingScale, …`.

- [ ] **Step 6: Trim the init to Button's own layers + role + applyTheme.** In `init(palette:)` (lines 235-283):
  - DELETE `self.palette = palette` (line 236), `super.init(frame: .zero)` (237), `wantsLayer = true` (238), `layer?.masksToBounds = false` (239), `focusRingType = .none` (240) — the base init does all of these.
  - DELETE the focus-ring build block (lines 275-279: `focusRingLayer.fillColor`/`lineWidth`/`opacity`/`contentsScale`/`addSublayer`) — base init builds + adds it (with zPosition=1000).
  - REPLACE the head with `super.init(palette: palette)` as the FIRST line, then keep the `let s = themeBackingScale` and ALL Button layer setup (shadow/fill/overlay/border/icons/title, lines 244-273), then keep `setAccessibilityRole(.button)` (281) and `applyTheme()` (282). Final shape:
    ```swift
    public init(palette: ResolvedPalette) {
        super.init(palette: palette)
        let s = themeBackingScale
        // …shadowLayer / fillLayer / overlayLayer / borderLayer / icon / title setup unchanged…
        setAccessibilityRole(.button)
        applyTheme()
    }
    ```
  Keep `@available(*, unavailable) public required init?(coder:)` (lines 285-286) — matches the base requirement.

- [ ] **Step 7: Replace `applyTheme()` with the four base hooks.** DELETE Button's public `applyTheme()` (lines 368-381). Add the overrides (drop `self.`, drop the layerTxn wrappers — the base supplies them):
  ```swift
  override func applyThemeSnap() {
      fillLayer.backgroundColor = baseFillColor.cgColor
      borderLayer.isHidden = (variant != .outlined)
      borderLayer.lineWidth = metrics.border
      shadowLayer.isHidden = (variant != .contained)
  }
  override func rebuildContent() {
      rebuildTitle()
      rebuildIcons()
  }
  override func syncAccessibility() {
      setAccessibilityLabel(title.isEmpty ? nil : title)
      setAccessibilityEnabled(isEnabled)
  }
  ```
  (The base's `applyTheme()` sets the focus-ring stroke + calls applyState + needsLayout itself.) DELETE Button's old private `syncAccessibility()` (lines 398-401) — it's now the override above. KEEP `rebuildTitle` (405-418) + `rebuildIcons` (420-426) private.

- [ ] **Step 8: Replace `applyState(animated:)` with `applyInteractionState()`.** DELETE Button's private `applyState(animated:)` (lines 385-396). Add:
  ```swift
  override func applyInteractionState() {
      overlayLayer.backgroundColor = overlayColor.cgColor
      borderLayer.strokeColor = borderColor.cgColor
      let e = elevation
      shadowLayer.shadowOpacity = groupedShadow ? 0 : e.opacity
      shadowLayer.shadowRadius  = e.radius
      shadowLayer.shadowOffset  = CGSize(width: 0, height: e.offsetY)
  }
  ```
  (The base's `applyState(animated:)` opens the layerTxn, calls this hook, then sets `focusRingLayer.opacity`.) All `applyState(animated:)` call sites — the `groupedShadow` didSet (line 140), `previewFocused`-style didSets, and the surviving property didSets — now bind to the inherited base method. Keep `overlayColor`/`borderColor`/`elevation`/`baseFillColor`/`titleColor`/`roleColor` computed props (lines 298-360) UNCHANGED.

- [ ] **Step 9: Replace `layout()` with `positionLayers(in:local:)` + `focusRingPath(in:)`.** DELETE Button's `layout()` override (lines 517-546). Add:
  ```swift
  override func positionLayers(in bounds: CGRect, local: CGRect) {
      let m = metrics
      let b = bounds
      shadowLayer.frame = b
      shadowLayer.shadowPath = closedCornerPath(local, radius: m.radius, corners: roundedCorners)
      fillLayer.frame = b
      fillLayer.cornerRadius = m.radius
      fillLayer.maskedCorners = roundedCorners
      overlayLayer.frame = local
      overlayLayer.cornerRadius = m.radius
      overlayLayer.maskedCorners = roundedCorners
      borderLayer.frame = b
      let inset = m.border / 2
      borderLayer.path = borderPath(local.insetBy(dx: inset, dy: inset),
          radius: m.radius, corners: roundedCorners, edges: drawnBorderEdges)
      layoutContent(in: b, m: m)
  }
  override func focusRingPath(in rect: CGRect) -> CGPath {
      closedCornerPath(rect.insetBy(dx: -focusRingOutset, dy: -focusRingOutset),
                       radius: metrics.radius + focusRingOutset,
                       corners: roundedCorners)
  }
  ```
  The base `layout()` calls `super.layout()`, opens one `layerTxn(animated:false)`, calls `positionLayers(in:local:)`, then sets `focusRingLayer.frame = bounds` + `focusRingLayer.path = focusRingPath(in: local)`. The two `2` literals from old lines 541-542 become `focusRingOutset` (= Space.xxs). KEEP `closedCornerPath` (465-482), `borderPath` (489-511), `layoutContent` (550-568) private + inline (CornerPath NOT extracted).

- [ ] **Step 10: Replace `viewDidChangeBackingProperties` with `updateContentsScale(_:)`.** DELETE Button's override (lines 573-583). Add:
  ```swift
  override func updateContentsScale(_ s: CGFloat) {
      for l in [shadowLayer, fillLayer, overlayLayer, leadingIconLayer, trailingIconLayer] { l.contentsScale = s }
      titleLayer.contentsScale = s
      borderLayer.contentsScale = s
      rebuildIcons()
      needsLayout = true
  }
  ```
  (The base `viewDidChangeBackingProperties` calls super, re-scales focusRingLayer, then calls this with `themeBackingScale`.)

- [ ] **Step 11: Delete the inherited tracking + mouse + keyboard + focus trio.** Remove, all byte-identical to the base:
  - `updateTrackingAreas` (587-600 → base 268-279, base factored options into `trackingOptions` = Button's exact set; do NOT override trackingOptions).
  - `mouseEntered`/`mouseExited` (602-609 → base 281-288).
  - `acceptsFirstMouse` (614 → base 290).
  - `mouseDown`/`mouseDragged`/`mouseUp` (620-634 → base 305-319; base uses `pressInside(_:)`, base mouseDown intentionally does NOT take first responder = Button's push-button behaviour).
  - `acceptsFirstResponder` (638 → base 323).
  - `becomeFirstResponder`/`resignFirstResponder` (640-649 → base 325-334).
  - `keyDown` (651-659 → base 336-344; base calls `keyboardActivate()`).
  - `performKeyEquivalent` (663-672 → base 348-357; base calls `keyboardActivate()`).

- [ ] **Step 12: Delete `flashAndActivate`; override `activate()` to add `onTap`.** DELETE `flashAndActivate` (679-689) — the inherited `keyboardActivate()` default (base 382: `flashThenActivate { activate() }`) reproduces it, with the 0.12 literal now `Self.flashDuration`. REPLACE Button's private `activate()` (691-695) with:
  ```swift
  override func activate() {
      guard isEnabled else { return }
      onTap?()
      super.activate()
  }
  ```
  `super.activate()` re-guards isEnabled + runs `sendActionToTarget()` (base: `NSApp.sendAction(_action, to: _target, from: self)`) — byte-identical to the old inline send. Do NOT override `keyboardActivate()` (Button wants the default flash→activate). Keep `onTap` (line 109).

- [ ] **Step 13: Leave the DEBUG `buttonProbe` extension untouched.** Lines 698-739 read Button-owned private layers (titleLayer/fillLayer/overlayLayer/borderLayer/shadowLayer) + the inherited `focusRingLayer.opacity` + `metrics`/`drawnBorderEdges`/`groupedShadow`. `focusRingLayer` is now `internal` on the base (same module) so `focusRingLayer.opacity` still resolves. No change needed.

- [ ] **Step 14: Build verification (LOCAL gate).** Run `swift build` and confirm it succeeds with no errors/warnings on the maintainer's CommandLineTools setup. The XCTest (ButtonProbe per-variant/per-state assertions + #14b base-contract tests) is written but runs in CI ONLY (full Xcode) — do NOT attempt `swift test` locally. The prism before/after live capture (hover/pressed/focused/disabled, driven by the `preview*` overrides) is maintainer-delegated.

- [ ] **Step 15: Commit.** `git commit` with a gitmoji + Conventional Commits message, e.g. `:recycle: refactor(ThemeKit): #14b ThemedButton adopts ThemedControl base — delete inherited interaction machinery, wire seams`. Do NOT push/tag yet (FAB → Checkbox → Chip adopt next on the same branch; tag `v<x.y.0>` lands after the whole #14b set + green CI).


---

### Task 3: Adopt ThemedControl in ThemedFAB

**Files:** `Sources/ThemeKit/ThemedFAB.swift`

**Interfaces:**
- Consumes the base API: `ThemedControl(palette:)` designated init; the seam hooks `applyThemeSnap()` / `rebuildContent()` / `syncAccessibility()` / `applyInteractionState()` / `positionLayers(in:local:)` / `updateContentsScale(_:)` / `focusRingPath(in:)` / `activate()`; the base-owned `focusRingLayer`, `focusRingOutset` (= `Space.xxs` = 2), `concentricRingPath(in:radius:corners:)`, `themeBackingScale`, `flashThenActivate`/`keyboardActivate`, the mouse/keyboard/tracking machinery, and the `isHovered`/`isPressed`/`isKeyFocused`/`isFlashing`/`previewHovered`/`previewPressed`/`previewFocused`/`fxHovered`/`fxPressed`/`fxFocused`/`showFocusRing` state.
- Produces nothing new (value-preserving extraction; FAB's public surface is unchanged).

- [ ] **Step 1: Change the superclass.** Line 45: `public final class ThemedFAB: NSControl {` → `public final class ThemedFAB: ThemedControl {`. Keep `final` and the `@MainActor` on line 44.

- [ ] **Step 2: Delete the now-inherited stored config props.** Remove the palette property (lines 62-63 `public var palette: ResolvedPalette { didSet { applyTheme() } }`), `keyEquivalent`/`keyEquivalentModifierMask` (lines 91-94), and `previewHovered`/`previewPressed`/`previewFocused` (lines 96-101) — all byte-identical to the base. KEEP variant/size/role/leadingSymbol/leadingImage/label/onTap (FAB-specific).

- [ ] **Step 3: Delete the inherited NSControl storage + interaction state.** Remove `_enabled` + the `isEnabled` override (lines 103-120) — FAB had no extra disable teardown, so no `didDisable()` override is needed. Remove `_target`/`_action`/`target`/`action` (lines 122-125). Remove `private let focusRingLayer = CAShapeLayer()` (line 134) — base-owned now (KEEP shadowLayer/fillLayer/overlayLayer/iconLayer/titleLayer, lines 129-133). Remove `trackingArea`/`isHovered`/`isPressed`/`isKeyFocused`/`isFlashing` (lines 136-140). Remove the `isFlipped` override (line 145) — base provides the same `{ false }`.

- [ ] **Step 4: Rewrite `init` to call the base.** Replace lines 181-224 so the init defers palette storage, layer setup of the base, and focus-ring construction to `super.init(palette:)`. New body:
  ```swift
  public init(palette: ResolvedPalette) {
      super.init(palette: palette)

      let s = themeBackingScale

      // Shadow (bottom) — never clipped, explicit rounded/circular silhouette.
      shadowLayer.masksToBounds = false
      shadowLayer.shadowColor = NSColor.black.cgColor
      shadowLayer.contentsScale = s
      layer?.addSublayer(shadowLayer)

      // Fill clips the overlay child to the round / pill rect.
      fillLayer.masksToBounds = true
      fillLayer.contentsScale = s
      layer?.addSublayer(fillLayer)
      overlayLayer.contentsScale = s
      fillLayer.addSublayer(overlayLayer)

      iconLayer.contentsGravity = .resizeAspect
      iconLayer.contentsScale = s
      iconLayer.isHidden = true
      layer?.addSublayer(iconLayer)

      titleLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
      titleLayer.contentsScale = s
      titleLayer.alignmentMode = .center
      titleLayer.truncationMode = .end
      titleLayer.isWrapped = false
      titleLayer.isHidden = true
      layer?.addSublayer(titleLayer)

      setAccessibilityRole(.button)
      applyTheme()
  }
  ```
  Notes: `super.init(palette:)` sets `wantsLayer`, `masksToBounds = false`, `focusRingType = .none`, and builds + adds the base `focusRingLayer` (with `zPosition = 1000`, so it renders above FAB's sublayers regardless of add-order). FAB therefore DELETES its own `wantsLayer`/`masksToBounds`/`focusRingType` lines (old 184-186) and the entire focus-ring layer block (old 216-220). The `backingScale` local read becomes `themeBackingScale`. Keep `@available(*, unavailable) public required init?(coder:) { nil }` (lines 226-227) unchanged. Delete the now-unused `private var backingScale` alias (line 366) and the `relayout()` helper STAYS (used by config didSets).

- [ ] **Step 5: Collapse `applyTheme` into the base hooks.** Delete the whole `public func applyTheme()` (lines 293-303). Add the snap hook (the fill half; the base sets the ring stroke + opens the txn):
  ```swift
  override func applyThemeSnap() {
      fillLayer.backgroundColor = baseFillColor.cgColor
  }
  ```
  Add the content hook (base calls it outside the snap txn, FAB's original title-then-icon order):
  ```swift
  override func rebuildContent() {
      rebuildTitle()
      rebuildIcon()
  }
  ```
  Change `private func syncAccessibility()` (line 318) to `override func syncAccessibility()` (drop `private`, add `override`; body unchanged). `rebuildTitle` (325-339) and `rebuildIcon` (341-362) STAY private. In `rebuildIcon`, replace `let scale = backingScale` (line 342) with `let scale = themeBackingScale`.

- [ ] **Step 6: Move `applyState` into `applyInteractionState`.** Delete the whole `private func applyState(animated:)` (lines 305-316). Add:
  ```swift
  override func applyInteractionState() {
      overlayLayer.backgroundColor = overlayColor.cgColor
      let e = elevation
      shadowLayer.shadowOpacity = e.opacity
      shadowLayer.shadowRadius  = e.radius
      shadowLayer.shadowOffset  = CGSize(width: 0, height: e.offsetY)
  }
  ```
  The base's `applyState(animated:)` opens the single `layerTxn` and sets `focusRingLayer.opacity` itself, so FAB drops its txn wrapper and the ring-opacity line. `overlayColor`/`elevation` (dp8 rest / dp12 pressed) and the role-color computed vars STAY private, unchanged.

- [ ] **Step 7: Move `layout` body into `positionLayers` and drop the Metrics ring literal.** Delete the whole `public override func layout()` (lines 368-395). Add:
  ```swift
  override func positionLayers(in bounds: CGRect, local: CGRect) {
      let b = bounds
      let r = min(b.width, b.height) / 2
      shadowLayer.frame = b
      shadowLayer.shadowPath =
          CGPath(roundedRect: local, cornerWidth: r, cornerHeight: r, transform: nil)
      fillLayer.frame = b
      fillLayer.cornerRadius = r
      overlayLayer.frame = local
      overlayLayer.cornerRadius = r
      layoutContent(in: b, m: metrics)
  }
  ```
  The base's `layout()` opens the non-animated `layerTxn`, calls `positionLayers(in:local:)`, then sets `focusRingLayer.frame = bounds` and `focusRingLayer.path = focusRingPath(in: local)` — so FAB drops its own ring frame/path lines (old 388-391) and txn wrapper. Now remove the `ringInset` literal from `Metrics`: delete `ringInset` from the field list on line 151 (`let diameter, height, hpad, iconPt, font, gap, ringInset: CGFloat` → `let diameter, height, hpad, iconPt, font, gap: CGFloat`) and from the initializer on line 160 (`gap: CGFloat(Space.md), ringInset: 2)` → `gap: CGFloat(Space.md))`). `layoutContent(in:m:)` (399-417) STAYS private unchanged.

- [ ] **Step 8: Override `focusRingPath` to keep FAB's circle.** The base default passes `radius: 0` (a small rounded box); FAB is circular, so override with the half-min radius routed through the base's concentric helper (which sources the outset from `focusRingOutset = Space.xxs = 2`, replacing the old `m.ringInset` literal):
  ```swift
  override func focusRingPath(in rect: CGRect) -> CGPath {
      let r = min(rect.width, rect.height) / 2
      return concentricRingPath(in: rect, radius: r)
  }
  ```
  This yields `rect.insetBy(-2)` with `cornerWidth/Height = r + 2` — byte-identical to the old `r + m.ringInset`. FAB does NOT set `focusRingOutset` (keeps the default 2) and does NOT set the ring stroke/lineWidth/opacity (all base-owned).

- [ ] **Step 9: Move `updateContentsScale` + delete `viewDidChangeBackingProperties`.** Delete the whole `public override func viewDidChangeBackingProperties()` (lines 422-430). Add:
  ```swift
  override func updateContentsScale(_ s: CGFloat) {
      for l in [shadowLayer, fillLayer, overlayLayer, iconLayer] { l.contentsScale = s }
      titleLayer.contentsScale = s
      rebuildIcon()        // re-rasterize at the new device scale
      needsLayout = true
  }
  ```
  The base's `viewDidChangeBackingProperties()` calls super, sets `focusRingLayer.contentsScale = themeBackingScale`, then `updateContentsScale(s)` with `s = themeBackingScale`. FAB drops the ring-scale line and the `super`/`backingScale` reads; `needsLayout = true` is added here to preserve the old method's trailing relayout (the base wrapper does not relayout).

- [ ] **Step 10: Collapse the keyboard + press + tracking + activate machinery.** Delete `updateTrackingAreas` (434-447), `mouseEntered`/`mouseExited` (449-456), `acceptsFirstMouse` (461), the `mouseDown`/`mouseDragged`/`mouseUp` trio (463-480), `acceptsFirstResponder` (484), `becomeFirstResponder`/`resignFirstResponder` (486-495), `keyDown` (497-505), `performKeyEquivalent` (509-518), and `private func flashAndActivate()` (520-535) — all byte-identical to base behaviour (base default `keyboardActivate()` == `flashThenActivate { activate() }`, FAB's exact path; base `trackingOptions`/`appearanceGate`/`focusGate` defaults match FAB's `isEnabled`-gated versions; the 0.12 literal becomes the base `flashDuration`). Then replace `private func activate()` (537-541) with an override that preserves FAB's onTap-then-send order:
  ```swift
  override func activate() {
      guard isEnabled else { return }
      onTap?()
      super.activate()
  }
  ```
  `super.activate()` re-guards `isEnabled` and runs `sendActionToTarget()` (= FAB's old `NSApp.sendAction(a, to: _target, from: self)`). The `#if DEBUG` `fabProbe` extension (544-578) STAYS verbatim (still reads the same private layers + the now-base-internal `focusRingLayer`).

- [ ] **Step 11: `swift build` green (local).** Run `swift build` on CommandLineTools and confirm it compiles clean. This is the LOCAL gate; the value-preservation XCTest (fx merges / concentric-ring math / disable-clear contract) runs in CI only (`.github/workflows/build.yml`, full Xcode), and the prism before/after live capture (hover/pressed/focused/disabled via the `preview*` overrides) is maintainer-delegated. Do NOT attempt a local test run.

- [ ] **Step 12: Commit.** `git commit` on the `feat-14b-themedcontrol` branch with a gitmoji + Conventional Commits message, e.g. `:recycle: refactor(ThemeKit): #14b ThemedFAB adopts ThemedControl base — delete byte-identical interaction machinery, keep onTap/circle/dp12 seams`. Co-author trailer per house convention.


---

### Task 4: Adopt ThemedControl in ThemedCheckbox (value model stays in subclass)

**Files:** `Sources/ThemeKit/ThemedCheckbox.swift` (this task assumes `Sources/ThemeKit/ThemedControl.swift` already exists from the base task, and that ThemedButton/FAB have already been adopted as the reference).

**Interfaces:**
- Consumes the base API: `palette`/`applyTheme()`, the `isEnabled`/`target`/`action`/`keyEquivalent*` storage, `isHovered`/`isPressed`/`isKeyFocused`/`isFlashing`, `previewHovered/Pressed/Focused`, `fxHovered/Pressed/Focused`, `showFocusRing`, the `focusRingLayer` + `focusRingOutset` + `concentricRingPath(in:radius:corners:)`, the tracking/mouse trio (`updateTrackingAreas`/`mouseEntered`/`mouseExited`/`acceptsFirstMouse`/`mouseDown`/`mouseDragged`/`mouseUp`/`pressInside`), the FR trio + `keyDown`/`performKeyEquivalent`, `flashThenActivate(_:)`, and the seam hooks `applyThemeSnap`/`rebuildContent`/`syncAccessibility`/`applyInteractionState`/`positionLayers`/`updateContentsScale`/`focusRingPath`/`keyboardActivate`/`activate`/`didDisable`.
- Produces nothing new (no new public API; `ThemedCheckbox`'s existing public surface — `palette`/`size`/`role`/`isChecked`/`isIndeterminate`/`label`/`onChange`/`keyEquivalent`/`previewChecked`/`previewIndeterminate` etc. — is unchanged).

This is a VALUE-PRESERVING refactor. Behaviour MUST stay byte-identical (hover/press/focus/flash/ring/glyph/toggle). The ONLY mechanism change is the literal `-2` focusInset collapsing into the base `focusRingOutset` (= `Space.xxs` = 2), geometry-identical.

- [ ] **Step 1: Reparent the class.** Change the declaration (line 23) `public final class ThemedCheckbox: NSControl {` → `public final class ThemedCheckbox: ThemedControl {`. Keep `final` and the `@MainActor` line above it.

- [ ] **Step 2: Delete the public config now owned by the base.** Remove `keyEquivalent`/`keyEquivalentModifierMask` (lines 55-56) and `previewHovered`/`previewPressed`/`previewFocused` (lines 61-63). KEEP `previewChecked`/`previewIndeterminate` (lines 64-65) — checkbox value model. (The comment block above them, lines 58-60, can stay or be trimmed to reference only the checked/indeterminate previews.)

- [ ] **Step 3: Delete the cell-less NSControl storage block.** Remove lines 67-85 (the `// MARK: - NSControl overrides` comment, `_enabled` + the whole `isEnabled` setter, `_target`/`_action` + the `target`/`action` overrides). Byte-identical to base (base additionally runs `didDisable()`, a no-op here — no override needed).

- [ ] **Step 4: Delete the inherited interaction-state ivars + the trackingArea + the focusRingLayer ivar.** From the `// MARK: - Internals` block: remove `private let focusRingLayer = CAShapeLayer()` (line 94), `private var trackingArea: NSTrackingArea?` (line 96), and `private var isHovered`/`isPressed`/`isKeyFocused`/`isFlashing` (lines 97-100). KEEP the checkbox layers (`hoverCircleLayer`/`boxFillLayer`/`boxStrokeLayer`/`glyphLayer`/`labelLayer`, lines 89-93) and `private var labelTextSize: CGSize = .zero` (line 101).

- [ ] **Step 5: Delete `isFlipped`.** Remove `public override var isFlipped: Bool { false }` (line 103) — byte-identical to base default.

- [ ] **Step 6: Drop `focusInset` from Metrics.** In the `Metrics` struct decl (line 108), change `let target, box, radius, stroke, labelFont, labelGap, focusInset: CGFloat` → `let target, box, radius, stroke, labelFont, labelGap: CGFloat`. In the two metric rows (lines 112-113) remove the trailing `, focusInset: -2` from both `.small` and `.medium`. The two `-2` literals are now gone (replaced by the base `focusRingOutset` = `Space.xxs`).

- [ ] **Step 7: Slim the init — delete the focus-ring wiring + alias the backing scale.** In `init(palette:)` (lines 130-171): the `self.palette = palette` / `super.init(frame:.zero)` becomes `super.init(palette: palette)` — REPLACE lines 131-135 (`self.palette = palette`, `super.init(frame: .zero)`, `wantsLayer = true`, `layer?.masksToBounds = false`, `focusRingType = .none`) with a single `super.init(palette: palette)` (the base sets palette/wantsLayer/masksToBounds=false/focusRingType=.none + builds+adds the ring). Change `let s = backingScale` (line 137) → `let s = themeBackingScale`. DELETE the focus-ring block (lines 163-167: `focusRingLayer.contentsScale = s` through `layer?.addSublayer(focusRingLayer)`). KEEP the checkbox layer setup (hoverCircle/boxFill/boxStroke/glyph/label, lines 138-161), `setAccessibilityRole(.checkBox)` (line 169), and the trailing `applyTheme()` (line 170).

- [ ] **Step 8: Delete the `backingScale` alias.** Remove `private var backingScale: CGFloat { themeBackingScale }` (line 177). (Step 7 already switched the init call site; the only other call site is `viewDidChangeBackingProperties`, removed in Step 13.) The `relayout()` helper (line 176) stays.

- [ ] **Step 9: Delete the inherited fx/showFocusRing computeds.** Remove `fxHovered`/`fxPressed`/`fxFocused` (lines 181-183) and `showFocusRing` (line 211) — byte-identical to base. KEEP `fxChecked`/`fxIndeterminate`/`eff` (lines 184-186) and all the colour computeds (`boxFillColor`/`boxStrokeColor`/`glyphColor`/`hoverCircleColor`/`labelColor`, lines 191-210).

- [ ] **Step 10: Split `applyTheme()` into `applyThemeSnap()` + override-renames.** DELETE the whole `public func applyTheme()` (lines 215-225). Add the snap override (the ring-stroke line is dropped — the base sets it):
  ```swift
  override func applyThemeSnap() {
      boxStrokeLayer.lineWidth = metrics.stroke
      glyphLayer.lineWidth = metrics.box * 2 / 24
  }
  ```
  Rename `private func rebuildLabel()` (line 243) → `override func rebuildContent()` (body unchanged, lines 244-255). Rename `private func syncAccessibility()` (line 257) → `override func syncAccessibility()` (body unchanged, lines 258-262). The base `applyTheme()` now drives `applyThemeSnap → rebuildContent → syncAccessibility → applyState(false) → needsLayout`, matching the old sequence. (The `size`/`role`/`label`/`isChecked`/`isIndeterminate`/`previewChecked`/`previewIndeterminate` didSets still call `applyTheme()`/`syncAccessibility()`/`applyState(...)` — all still valid.)

- [ ] **Step 11: Override `applyState(animated:)` for the glyph-path snap + move state props into `applyInteractionState()`.** DELETE the whole `private func applyState(animated:)` (lines 227-241). Add:
  ```swift
  override func applyState(animated: Bool) {
      layerTxn(animated: false) { if let path = self.glyphPath() { self.glyphLayer.path = path } }
      super.applyState(animated: animated)
  }

  override func applyInteractionState() {
      boxFillLayer.fillColor = boxFillColor.cgColor
      boxStrokeLayer.strokeColor = boxStrokeColor.cgColor
      boxStrokeLayer.opacity = eff ? 0 : 1
      glyphLayer.strokeColor = glyphColor.cgColor
      glyphLayer.strokeEnd = eff ? 1 : 0
      hoverCircleLayer.backgroundColor = hoverCircleColor.cgColor
  }
  ```
  The old `focusRingLayer.opacity = showFocusRing ? 1 : 0` line is dropped — base `applyState` sets ring opacity inside the same txn. (`glyphPath()`, lines 267-282, is unchanged.)

- [ ] **Step 12: Override `positionLayers(in:local:)` + delete `layout()`; relocate the ring path to `focusRingPath(in:)`.** DELETE the whole `public override func layout()` (lines 286-320). Add:
  ```swift
  override func positionLayers(in bounds: CGRect, local: CGRect) {
      let m = metrics
      let targetRect = NSRect(x: 0, y: (bounds.height - m.target) / 2,
                              width: m.target, height: m.target)
      let boxRect = NSRect(x: targetRect.midX - m.box / 2, y: targetRect.midY - m.box / 2,
                           width: m.box, height: m.box)
      let boxLocal = CGRect(origin: .zero, size: boxRect.size)
      hoverCircleLayer.frame = targetRect
      hoverCircleLayer.cornerRadius = m.target / 2
      boxFillLayer.frame = boxRect
      boxFillLayer.path = CGPath(roundedRect: boxLocal,
          cornerWidth: m.radius, cornerHeight: m.radius, transform: nil)
      boxStrokeLayer.frame = boxRect
      let si = m.stroke / 2
      let ringRadius = max(0, m.radius - si)
      boxStrokeLayer.path = CGPath(roundedRect: boxLocal.insetBy(dx: si, dy: si),
          cornerWidth: ringRadius, cornerHeight: ringRadius, transform: nil)
      glyphLayer.frame = boxRect
      if !(label ?? "").isEmpty {
          labelLayer.position = CGPoint(x: boxRect.maxX + m.labelGap, y: targetRect.midY)
      }
  }

  override func focusRingPath(in rect: CGRect) -> CGPath {
      let m = metrics
      let targetRect = NSRect(x: 0, y: (rect.height - m.target) / 2,
                              width: m.target, height: m.target)
      let boxRect = NSRect(x: targetRect.midX - m.box / 2, y: targetRect.midY - m.box / 2,
                           width: m.box, height: m.box)
      return concentricRingPath(in: boxRect, radius: CGFloat(m.radius))
  }
  ```
  The base `layout()` calls `positionLayers(in:local:)` then sets `focusRingLayer.frame = bounds` and `focusRingLayer.path = focusRingPath(local)`. The old box-local ring inset (`focusInset: -2`, corner `m.radius - m.focusInset` = `m.radius + 2`) is now produced by `concentricRingPath` (inset `-focusRingOutset` = -2, corner `radius + focusRingOutset` = m.radius + 2) — geometry-identical, now in bounds coords.

- [ ] **Step 13: Override `updateContentsScale(_:)`; delete `viewDidChangeBackingProperties()`.** DELETE the whole `public override func viewDidChangeBackingProperties()` (lines 322-330). Add:
  ```swift
  override func updateContentsScale(_ s: CGFloat) {
      for l in [hoverCircleLayer, boxFillLayer, boxStrokeLayer, glyphLayer] {
          l.contentsScale = s
      }
      labelLayer.contentsScale = s
      needsLayout = true
  }
  ```
  `focusRingLayer` is dropped from the loop (base re-scales the ring before calling this).

- [ ] **Step 14: Delete the inherited tracking + hover + mouse-down/dragged.** Remove `updateTrackingAreas()` (lines 334-345), `mouseEntered`/`mouseExited` (lines 346-353), `acceptsFirstMouse` (line 357), `mouseDown`/`mouseDragged` (lines 358-366) — all byte-identical to base.

- [ ] **Step 15: Delete `mouseUp` and route activation through an `activate()` override.** Remove `mouseUp` (lines 367-372). The base `mouseUp` calls `activate()` on an inside release; override `activate()` to toggle (matching the old `toggle(fromUser: true)`):
  ```swift
  override func activate() {
      toggle(fromUser: true)
  }
  ```
  Do NOT call `super.activate()` (that would double-send the action; `toggle(fromUser:)` already guards `isEnabled` and fires onChange + `NSApp.sendAction`).

- [ ] **Step 16: Delete the inherited FR trio + keyDown/performKeyEquivalent.** Remove `acceptsFirstResponder`/`becomeFirstResponder`/`resignFirstResponder` (lines 376-386), `keyDown` (lines 387-393), and `performKeyEquivalent` (lines 394-403) — byte-identical to base (the base `keyDown`/`performKeyEquivalent` call `keyboardActivate()`, overridden next).

- [ ] **Step 17: Replace `flashAndToggle()` with a `keyboardActivate()` override.** DELETE `private func flashAndToggle()` (lines 407-417). Add:
  ```swift
  override func keyboardActivate() {
      flashThenActivate { [weak self] in self?.toggle(fromUser: true) }
  }
  ```
  Byte-identical to the old `flashAndToggle` (base `flashThenActivate` body == old body with the deferred `toggle` injected as the action). KEEP `private func toggle(fromUser:)` (lines 422-437) unchanged — it stays the checkbox value primitive used by both `activate()` and `keyboardActivate()`.

- [ ] **Step 18: Retarget the DEBUG test seam.** In the `#if DEBUG` extension, change `func spaceKeyForTesting() { flashAndToggle() }` (line 482) → `func spaceKeyForTesting() { keyboardActivate() }`. The rest of the extension (`checkboxProbe`, `toggleForTesting`, `isFlashingForTesting`) is unchanged — it reads layers/fields that remain (`isFlashing` is now the inherited `var`, still in-module readable).

- [ ] **Step 19: Verify the local build gate.** Run `swift build` and confirm it is green on CommandLineTools (the local bar). Do NOT attempt `swift test` locally — XCTest needs full Xcode and runs in CI only (`.github/workflows/build.yml`). The XCTest assertions (fx merges / focus-ring concentric math / disable-clear / toggle / Space-key flash, driven via the `checkboxProbe` + `toggleForTesting`/`spaceKeyForTesting`/`isFlashingForTesting` seams) run in CI. prism before/after live capture (hover/pressed/focused/disabled/checked/indeterminate via the `preview*` overrides) is maintainer-delegated.

- [ ] **Step 20: Commit.** `:recycle: refactor(ThemeKit): #14b ThemedCheckbox adopts ThemedControl base — delete hand-rolled interaction machinery, override keyboardActivate (flash-then-toggle) + activate (toggle) + focus-ring (Radius.xs box via concentricRingPath, focusInset -2 → focusRingOutset)` (gitmoji + Conventional Commits; squash-merge appends the PR number).


---

### Task 5: Adopt ThemedControl in ThemedChip (heaviest seam user)

**Files:** `/Volumes/workspace/github.com/akira-toriyama/sill/Sources/ThemeKit/ThemedChip.swift`

**Interfaces:**
- *Consumes the base API:* `ThemedControl` storage (`isHovered`, `isKeyFocused`, `palette`, `previewHovered/Pressed/Focused`, `_enabled/_target/_action` via `isEnabled`/`target`/`action`), the seams (`didDisable`, `appearanceGate`, `focusGate`, `fxPressed`, `showFocusRing`, `applyThemeSnap`, `rebuildContent`, `syncAccessibility`, `applyInteractionState`, `positionLayers`, `focusRingPath`, `concentricRingPath`, `updateContentsScale`, `trackingOptions`, `updateTrackingAreas`, `acceptsFirstMouse`, the mouse trio, `keyDown`, `activate`), the base-owned `focusRingLayer` + `focusRingOutset` + `Self.allCorners`, and helpers `flashThenActivate`/`sendActionToTarget`/`themeBackingScale`/`layerTxn`. (Chip does NOT use the base `keyboardActivate`/`flashThenActivate` — it has no flash.)
- *Produces nothing new* (value-preserving extraction; public API of `ThemedChip` is unchanged).

> Build reality: `swift build` is the LOCAL gate (CommandLineTools, no Xcode). XCTest runs in CI only. prism before/after is maintainer-delegated. Do these edits in ONE pass, then build.

- [ ] **Step 1: Change the superclass + drop redundant `@MainActor`.**
  - Line 47-48, before:
    ```swift
    @MainActor
    public final class ThemedChip: NSControl {
    ```
    after:
    ```swift
    public final class ThemedChip: ThemedControl {
    ```
  - `final` stays (Chip is a leaf). `@MainActor` is inherited from the base — drop the attribute.

- [ ] **Step 2: Delete the members the base now owns byte-identically.**
  - Delete `palette` stored prop (lines 66-67) — base owns `public var palette: ResolvedPalette { didSet { applyTheme() } }`.
  - Delete `previewHovered/Pressed/Focused` (lines 104-108).
  - Delete the `_enabled` + `isEnabled` override (lines 112-124) — its Chip-only teardown moves to `didDisable()` (Step 4).
  - Delete `_target`/`_action` + `target`/`action` overrides (lines 126-129).
  - Delete `private let focusRingLayer = CAShapeLayer()` (line 138).
  - Delete `private var trackingArea` (line 140), `private var isHovered = false` (line 141), `private var isKeyFocused = false` (line 142). KEEP `private var isDeleteHovered = false` (line 143).
  - Delete `public override var isFlipped: Bool { false }` (line 158).

- [ ] **Step 3: Rename the `pressInside` Bool → `pressArmed` (name clash with the base `pressInside(_:)` method).**
  - Line 150, before: `private var pressInside = false` → after: `private var pressArmed = false` (keep the doc comment).
  - Update its 4 uses: line 328 (`fxPressed`), line 599 (`pressInside = pressTarget != .none`), line 606 (`if inside != pressInside { pressInside = inside; ...`), line 613 (`pressTarget = .none; pressInside = false`). All `pressInside` → `pressArmed`. (These get rewritten anyway in Steps 7-9, but do the rename first so nothing references the old name.)

- [ ] **Step 4: Replace the deleted `isEnabled` teardown with a `didDisable()` override.**
  - Add (e.g. near the top of the type, after the `Role` enum or in an `// MARK: - Disable` group):
    ```swift
    override func didDisable() {
        isDeleteHovered = false
        pressTarget = .none
    }
    ```
  - (Base already cleared `isHovered`/`isPressed` + resigned FR; this adds the ×-hover + press-target clear.)

- [ ] **Step 5: Override the two gates + the diverging fx/ring predicates.**
  - Delete the private `fxHovered` (line 327) and `fxFocused` (line 329) — the base versions, with `appearanceGate = isClickable`, are byte-identical.
  - Replace `private var fxPressed` (line 328) with an override (using the renamed `pressArmed`):
    ```swift
    override var fxPressed: Bool {
        ((pressTarget == .body && pressArmed) || previewPressed) && isClickable
    }
    ```
  - Add the gate overrides (place near the `isClickable`/`isInteractive` computeds, lines 160-165, which STAY):
    ```swift
    override var appearanceGate: Bool { isClickable }
    override var focusGate: Bool { isInteractive }
    ```
  - Replace `private var showFocusRing` (line 362) with an override:
    ```swift
    override var showFocusRing: Bool { (isKeyFocused || previewFocused) && isInteractive }
    ```

- [ ] **Step 6: Decompose `applyTheme`/`applyState` into the base hooks.**
  - Delete the whole `public func applyTheme()` (lines 366-379) and `private func applyState(animated:)` (lines 382-389).
  - Add:
    ```swift
    override func applyThemeSnap() {
        let m = metrics
        fillLayer.backgroundColor = baseFillColor.cgColor
        fillLayer.borderWidth = m.border
        fillLayer.borderColor = borderColor.cgColor
    }

    override func rebuildContent() {
        rebuildTitle()
        rebuildIcons()
    }

    override func syncAccessibility() {
        setAccessibilityRole(isClickable ? .button : .staticText)
        setAccessibilityLabel(title.isEmpty ? nil : title)
        setAccessibilityEnabled(isEnabled)
    }

    override func applyInteractionState() {
        overlayLayer.backgroundColor = overlayColor.cgColor
        fillLayer.borderColor = borderColor.cgColor
        deleteIconLayer.contents = renderedDelete()
    }
    ```
  - (The dropped `focusRingLayer.strokeColor = palette.primary` is set by base `applyTheme`; the dropped `focusRingLayer.opacity` is set by base `applyState`. `rebuildTitle`/`rebuildIcons`/`renderedDelete`/`syncAccessibility`'s old standalone def — delete the old standalone `private func syncAccessibility` at lines 391-395, now folded above.)
  - The didSet bodies that called the old private `applyTheme()`/`applyState()` (e.g. `variant`/`size`/`role`/`title`/`isSelected`/`onDelete`/`onTap` and the `invalidateInteraction` helper line 261) now call the INHERITED `applyTheme()` / `applyState(animated:)` — same names, no change needed at the call sites.

- [ ] **Step 7: Move layer placement into `positionLayers` + the ring into `focusRingPath`.**
  - Delete the whole `public override func layout()` (lines 470-488).
  - Add:
    ```swift
    override func positionLayers(in bounds: CGRect, local: CGRect) {
        let m = metrics
        fillLayer.frame = bounds
        fillLayer.cornerRadius = m.radius
        overlayLayer.frame = local
        overlayLayer.cornerRadius = m.radius
        layoutContent(in: bounds, m: m)
    }

    override func focusRingPath(in rect: CGRect) -> CGPath {
        concentricRingPath(in: rect, radius: metrics.radius, corners: Self.allCorners)
    }
    ```
  - This consumes the two `2` literals (old lines 483-484 `insetBy(dx: -2, dy: -2)` + `m.radius + 2`) into the inherited `focusRingOutset`. (`layoutContent(in:m:)` lines 491-516 stays unchanged.)

- [ ] **Step 8: Replace `viewDidChangeBackingProperties` with `updateContentsScale`.**
  - Delete the whole `viewDidChangeBackingProperties` (lines 518-528).
  - Add:
    ```swift
    override func updateContentsScale(_ s: CGFloat) {
        for l in [fillLayer, overlayLayer, leadingIconLayer, deleteIconLayer] { l.contentsScale = s }
        titleLayer.contentsScale = s
        rebuildIcons()
        needsLayout = true
    }
    ```
  - (Base's `viewDidChangeBackingProperties` calls super, rescales `focusRingLayer`, then calls this. `private var backingScale { themeBackingScale }` line 468 STAYS — many call sites use it.)

- [ ] **Step 9: Override the tracking + mouse seams (the heaviest divergence).**
  - Delete `updateTrackingAreas` (lines 532-543) and add the slimmed version + `trackingOptions`:
    ```swift
    override var trackingOptions: NSTrackingArea.Options {
        [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect]
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()   // base removes/re-adds with trackingOptions + reconciles isHovered
        if isDeleteHovered, let w = window {
            let local = convert(w.mouseLocationOutsideOfEventStream, from: nil)
            if !bounds.contains(local) { isDeleteHovered = false; applyState(animated: false) }
        }
    }
    ```
  - The old `clearHover()` (lines 545-549) is now referenced only by `mouseExited` (which inlines its own clear) — KEEP it if `mouseExited` still calls it, else delete. (Below `mouseExited` inlines, so `clearHover` is unused → delete lines 545-549.)
  - Add `acceptsFirstMouse` (base default would gate on `isClickable` and break delete-only chips):
    ```swift
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isEnabled }
    ```
  - Add `override` to the hover trio (bodies unchanged from lines 551-563):
    ```swift
    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        updateHover(at: convert(event.locationInWindow, from: nil), animated: true)
    }
    override func mouseMoved(with event: NSEvent) {
        guard isEnabled else { return }
        updateHover(at: convert(event.locationInWindow, from: nil), animated: true)
    }
    override func mouseExited(with event: NSEvent) {
        guard isHovered || isDeleteHovered else { return }
        isHovered = false; isDeleteHovered = false
        applyState(animated: true)
    }
    ```
  - Add `override` to the press trio (bodies unchanged from lines 589-618 except `pressInside`→`pressArmed`):
    ```swift
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let p = convert(event.locationInWindow, from: nil)
        if isDeletable, deleteHitRect.contains(p) { pressTarget = .delete }
        else if isClickable { pressTarget = .body }
        else { pressTarget = .none }
        pressArmed = pressTarget != .none
        applyState(animated: true)
    }
    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, pressTarget != .none else { return }
        let inside = pointer(convert(event.locationInWindow, from: nil), over: pressTarget)
        if inside != pressArmed { pressArmed = inside; applyState(animated: false) }
    }
    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { pressTarget = .none; return }
        let p = convert(event.locationInWindow, from: nil)
        let target = pressTarget
        pressTarget = .none; pressArmed = false
        if pointer(p, over: target) {
            if target == .delete { onDelete?() } else if target == .body { activate() }
        }
        updateHover(at: p, animated: true)
    }
    ```
  - (`pointer(_:over:)` lines 581-587 and `updateHover(at:animated:)` lines 567-574 stay as private helpers. `acceptsFirstMouse` old line 578 is replaced above. Chip's `pressInside(_:)` is NOT used — the base's method of that name is simply unreferenced.)

- [ ] **Step 10: Override keyboard + activation.**
  - Delete `acceptsFirstResponder` (line 622) — base default `{ focusGate }` now returns `isInteractive`.
  - Delete `becomeFirstResponder`/`resignFirstResponder` (lines 624-633) — base byte-identical.
  - Add `override` to `keyDown` (body unchanged, lines 635-647):
    ```swift
    override func keyDown(with event: NSEvent) {
        guard isEnabled else { super.keyDown(with: event); return }
        if event.keyCode == 49, isClickable {            // Space
            if !event.isARepeat { activate() }
            return
        }
        if (event.keyCode == 51 || event.keyCode == 117), isDeletable {  // Backspace / fwd-Delete
            if !event.isARepeat { onDelete?() }
            return
        }
        super.keyDown(with: event)
    }
    ```
  - Replace `private func activate()` (lines 649-653) with an override using the base `sendActionToTarget()` (`_action`/`_target` are now private to the base):
    ```swift
    override func activate() {
        guard isClickable else { return }
        onTap?()
        sendActionToTarget()
    }
    ```
  - (Chip never flashes: it does NOT override `keyboardActivate`, and Space → `activate()` directly. The base flash path stays unused by Chip, by design.)

- [ ] **Step 11: Trim the init to Chip-owned layers only.**
  - In `init(palette:)` (lines 207-243): DELETE `layer?.masksToBounds = false` (line 211), `focusRingType = .none` (line 212), and the focus-ring build block (lines 236-240). The base sets all of these.
  - The base `init(palette:)` must run FIRST: change `super.init(frame: .zero)` (line 209) to `super.init(palette: palette)` and DELETE `self.palette = palette` (line 208) and `wantsLayer = true` (line 210) — all owned by the base init. The remaining Chip init builds its own layer tree (fillLayer/overlayLayer/icon layers/titleLayer) then calls `applyTheme()` (line 242, KEEP — it now invokes the inherited template).
  - DELETE `@available(*, unavailable) public required init?(coder:)` (lines 245-246) — the base declares it.

- [ ] **Step 12: `swift build` green locally.**
  - Run `swift build` (CommandLineTools — the local gate). Resolve any compile errors (most likely: a missed `pressInside`→`pressArmed` rename, an `override` keyword missing on a seam, or a stale reference to a deleted private member). The existing `#if DEBUG chipProbe` extension (lines 656-690) is unchanged — it reads the still-present private layers + `metrics` + `intrinsicContentSize`.
  - The `chipProbe`-driven XCTest (per-variant/per-state appearance) runs in CI only (full Xcode); do NOT attempt to run `swift test` locally.

- [ ] **Step 13: Commit.**
  - Commit on the `feat-14b-themedcontrol` branch:
    `:recycle: refactor(ThemeKit): #14b ThemedChip adopts ThemedControl base — 2-target press / dual gate / pill ring as seams`
    with the Co-Authored-By trailer. (Do NOT push/merge until the maintainer confirms the prism before/after live capture matches — value-preserving claim must be verified live.)


---

### Task 6: Verification — base-contract XCTest (CI) + prism before/after (maintainer)

**Files:**
- `Tests/ThemeKitTests/ThemedControlTests.swift` (NEW — the base-contract suite; reuses each widget's DEBUG `*Probe`)
- (unchanged, but RE-RUN in CI as the byte-equivalence net) `Tests/ThemeKitTests/ThemedButtonTests.swift`, `ThemedFABTests.swift`, `ThemedCheckboxTests.swift`, `ThemedChipTests.swift`
- prism checklist lives in the PR body (no new source file)

**Interfaces:**
- Consumes the base API: `previewHovered/previewPressed/previewFocused`, `isEnabled` (+ its disable-cleanup of `isHovered`/`isPressed`/first-responder), `keyDown(with:)` Space(49), the internal `focusRingLayer` (read via `@testable import ThemeKit`), and each widget's existing DEBUG probe (`buttonProbe.focusRingOpacity`, `fabProbe.focusRingOpacity`/`focusRingStroke`, `checkboxProbe.focusRingOpacity`/`focusRingStroke` + `spaceKeyForTesting()`/`isFlashingForTesting`/`toggleForTesting()`, `chipProbe.focusRingOpacity`). The Chip path is the only one with a PressTarget enum (no Bool `isPressed`), so the press seam is asserted on Chip via `previewPressed`, not synthetic drags.
- Produces nothing new: ADDS tests only. NO new probe fields are required — the base's `focusRingLayer` is `internal` (declared `let focusRingLayer = CAShapeLayer()`, not `private`), so `@testable import ThemeKit` reads `focusRingLayer.path?.boundingBoxOfPath` and `focusRingLayer.frame` directly for the concentric-outset assertions. This task does NOT touch any widget source; the member DELETIONS / seam OVERRIDES / ring wiring belong to the four adoption tasks (Button→FAB→Checkbox→Chip). This task only proves their net is intact.

NOTE on verification reality: the maintainer's machine is CommandLineTools-only, so `import XCTest` does NOT compile/run locally — `swift build` is the local gate and `swift test` runs in CI ONLY (full Xcode). Therefore every step below ends at `swift build` green LOCALLY; the XCTest is WRITTEN here and first executes in CI. Do NOT write "run the test locally and watch it pass." The prism before/after live目視 is maintainer-delegated (agents can't screen-record); we make it deterministic via `preview*`.

- [ ] **Step 1: Create the base-contract suite file header + helpers.** Create `Tests/ThemeKitTests/ThemedControlTests.swift` mirroring the existing style (`@MainActor final class … : XCTestCase`, `@testable import ThemeKit`, the same `sameColor`/`alpha` helpers, `resolve(.terminal)` palette, a `settle(_:)` pump for the 0.12 s flash). Exact head:
  ```swift
  // ThemeKit / ThemedControl base-contract tests — the #14b value-preserving
  // extraction's safety net. DETERMINISTIC in headless CI (no Xcode locally → these
  // first run in CI). Each test drives a REAL subclass (Button/FAB/Checkbox/Chip)
  // through the shared base machinery via the `preview…` overrides + `isEnabled` +
  // keyDown, and reads the result through that widget's DEBUG probe or the base's
  // `@testable` focusRingLayer. Proves the base owns ONE copy of: the fx-merge
  // (real||preview AND gate), the concentric focusRingOutset math, the disable
  // cleanup, and the keyboardActivate seam (toggle vs send). The live 演出 is proven
  // in prism, not here.
  import XCTest
  import AppKit
  import Palette
  import PaletteKit
  @testable import ThemeKit

  @MainActor
  final class ThemedControlTests: XCTestCase {
      private func palette() -> ResolvedPalette { resolve(.terminal) }
      private func alpha(_ c: CGColor?) -> CGFloat {
          guard let c, let n = NSColor(cgColor: c)?.usingColorSpace(.sRGB) else { return -1 }
          return n.alphaComponent
      }
      private func sameColor(_ a: CGColor?, _ b: NSColor, accuracy: CGFloat = 0.01,
                             _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
          guard let a, let an = NSColor(cgColor: a)?.usingColorSpace(.sRGB),
                let bn = b.usingColorSpace(.sRGB) else {
              return XCTFail("colour unconvertible: \(msg)", file: file, line: line)
          }
          XCTAssertEqual(an.redComponent,   bn.redComponent,   accuracy: accuracy, msg, file: file, line: line)
          XCTAssertEqual(an.greenComponent, bn.greenComponent, accuracy: accuracy, msg, file: file, line: line)
          XCTAssertEqual(an.blueComponent,  bn.blueComponent,  accuracy: accuracy, msg, file: file, line: line)
          XCTAssertEqual(an.alphaComponent, bn.alphaComponent, accuracy: accuracy, msg, file: file, line: line)
      }
      private func settle(_ seconds: TimeInterval = 0.25) {
          let e = expectation(description: "settle")
          DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { e.fulfill() }
          wait(for: [e], timeout: 1.0)
      }
      private func spaceDown(isARepeat: Bool = false) -> NSEvent {
          NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
              windowNumber: 0, context: nil, characters: " ",
              charactersIgnoringModifiers: " ", isARepeat: isARepeat, keyCode: 49)!
      }
  ```
  Then `swift build` to confirm the new file compiles (build does NOT compile the test target, but verifies no accidental non-test symbol leaks). `swift build` green locally; the suite first executes in CI.

- [ ] **Step 2: fx-merge contract (real||preview, AND appearanceGate) on Button + FAB (default gate = isEnabled).** Add to the class. Drives the base `fxHovered/fxPressed/fxFocused` purely through the public preview overrides + `isEnabled`, reading each widget's probe — proving the merge lives once in the base and the disabled gate beats a forced preview:
  ```swift
      // fx merge = (realState || preview) && appearanceGate. Default gate = isEnabled
      // (Button / FAB). The preview overrides feed the SAME computed the real events do.
      func testFxHoverShowsOverlayButDisabledSuppresses() {
          let b = ThemedButton(palette: palette()); b.title = "B"; b.variant = .text
          b.frame = NSRect(x: 0, y: 0, width: 120, height: 36); b.layoutSubtreeIfNeeded()
          b.previewHovered = true
          XCTAssertGreaterThan(alpha(b.buttonProbe.overlayColor), 0, "preview hover lights the base fx merge")
          b.isEnabled = false   // appearanceGate=false now ANDs the merge to false
          XCTAssertEqual(alpha(b.buttonProbe.overlayColor), 0, accuracy: 0.001,
                         "the base appearanceGate (=isEnabled) suppresses the forced hover")
      }
      func testFxFocusRingGatedByEnabled() {
          let f = ThemedFAB(palette: palette()); f.leadingSymbol = "plus"
          f.frame = NSRect(origin: .zero, size: f.intrinsicContentSize); f.layoutSubtreeIfNeeded()
          f.previewFocused = true
          XCTAssertEqual(f.fabProbe.focusRingOpacity, 1, "preview focus shows the base-owned ring (showFocusRing)")
          f.isEnabled = false
          XCTAssertEqual(f.fabProbe.focusRingOpacity, 0, "disabled gates the base ring off")
      }
  ```
  `swift build` green locally; runs in CI.

- [ ] **Step 3: Chip's appearanceGate/focusGate seam (gate ≠ isEnabled).** Proves the base predicates are overridable seams, not hardcoded `isEnabled`: a static (no onTap/onDelete) chip has `appearanceGate=isClickable=false` so a forced hover is inert and it is not focusable; a delete-only chip is focusable though its body is inert (`focusGate=isInteractive`):
  ```swift
      func testChipAppearanceGateSeamSuppressesForcedHoverWhenStatic() {
          let c = ThemedChip(palette: palette()); c.title = "Tag"; c.variant = .filled
          c.frame = NSRect(x: 0, y: 0, width: 120, height: 32); c.layoutSubtreeIfNeeded()
          c.previewHovered = true   // appearanceGate = isClickable = false → merge AND-ed off
          XCTAssertEqual(alpha(c.chipProbe.overlayColor), 0, accuracy: 0.001,
                         "Chip overrides appearanceGate to isClickable; a static chip ignores forced hover")
          XCTAssertFalse(c.acceptsFirstResponder, "Chip overrides focusGate; a static chip is not focusable")
      }
      func testChipFocusGateSeamKeepsDeleteOnlyFocusable() {
          let c = ThemedChip(palette: palette()); c.title = "Tag"; c.onDelete = {}
          c.frame = NSRect(x: 0, y: 0, width: 120, height: 32); c.layoutSubtreeIfNeeded()
          c.previewFocused = true
          XCTAssertTrue(c.acceptsFirstResponder, "delete-only body is inert but focusGate=isInteractive keeps it focusable")
          XCTAssertEqual(c.chipProbe.focusRingOpacity, 1, "and the base ring shows")
      }
  ```
  `swift build` green locally; runs in CI.

- [ ] **Step 4: concentric focusRingOutset math (the 4 literal-2 → Space.xxs consolidation).** The probes expose ring opacity but NOT the ring geometry, so read the base-owned `focusRingLayer.path` via `@testable`. Assert the ring's bounding box is the control bounds inset by `-2` on every side (so width/height each grow by `2*focusRingOutset = 4`) for Button (selective corners), FAB (circle) and Chip (pill) — the ONE place the outset is defined now drives all of them concentrically:
  ```swift
      private func ringOutsetDelta(_ v: NSView, ringBox: CGRect) -> (dx: CGFloat, dy: CGFloat) {
          // base.layout() sets focusRingLayer.frame = bounds, path in LOCAL coords inset by -outset
          (dx: ringBox.minX, dy: ringBox.minY)   // local-rect origin = -outset on each axis
      }
      func testFocusRingOutsetIsTwoOnEverySubclass() {
          // Button — selective-corner ring, still concentric-outset 2
          let b = ThemedButton(palette: palette()); b.title = "B"; b.previewFocused = true
          b.frame = NSRect(x: 0, y: 0, width: 120, height: 36); b.layoutSubtreeIfNeeded()
          let bb = b.focusRingLayer.path!.boundingBoxOfPath
          XCTAssertEqual(bb.width,  120 + 4, accuracy: 0.5, "Button ring grows by 2*outset wide")
          XCTAssertEqual(bb.height,  36 + 4, accuracy: 0.5, "Button ring grows by 2*outset tall")
          XCTAssertEqual(bb.minX, -2, accuracy: 0.5, "ring sits 2pt outside the box (focusRingOutset = Space.xxs)")
          XCTAssertEqual(bb.minY, -2, accuracy: 0.5)
          // FAB — circle ring
          let f = ThemedFAB(palette: palette()); f.variant = .circular; f.leadingSymbol = "plus"; f.previewFocused = true
          f.frame = NSRect(x: 0, y: 0, width: 48, height: 48); f.layoutSubtreeIfNeeded()
          let fb = f.focusRingLayer.path!.boundingBoxOfPath
          XCTAssertEqual(fb.width,  48 + 4, accuracy: 0.5, "FAB circle ring grows by 2*outset")
          XCTAssertEqual(fb.minX, -2, accuracy: 0.5)
          // Chip — pill ring
          let c = ThemedChip(palette: palette()); c.title = "Tag"; c.onTap = {}; c.previewFocused = true
          c.frame = NSRect(x: 0, y: 0, width: 120, height: 32); c.layoutSubtreeIfNeeded()
          let cb = c.focusRingLayer.path!.boundingBoxOfPath
          XCTAssertEqual(cb.width, 120 + 4, accuracy: 0.5, "Chip pill ring grows by 2*outset")
          XCTAssertEqual(cb.minY, -2, accuracy: 0.5)
      }
  ```
  This catches the sign trap (Checkbox/FAB held `+2` and negated at use; Button/Chip wrote `-2` inline) collapsing to one `focusRingOutset` that drives both the `-outset` inset AND the `+outset` radius bump. `swift build` green locally; runs in CI.

- [ ] **Step 5: disable-cleanup contract (stuck-hover gotcha + didDisable seam).** The base's `isEnabled` setter (non-overridable; subclasses extend via `didDisable()`) must clear an in-flight hover/press on disable so a missing exit/up event can't strand it. Drive a forced hover, disable, and assert the appearance clears — proving the base owns the cleanup once:
  ```swift
      func testDisableClearsStrandedHoverOnce() {
          let b = ThemedButton(palette: palette()); b.title = "B"; b.variant = .text
          b.frame = NSRect(x: 0, y: 0, width: 120, height: 36); b.layoutSubtreeIfNeeded()
          b.previewHovered = true
          XCTAssertGreaterThan(alpha(b.buttonProbe.overlayColor), 0)
          b.isEnabled = false   // base clears isHovered/isPressed + resigns FR, then didDisable()
          XCTAssertEqual(alpha(b.buttonProbe.overlayColor), 0, accuracy: 0.001,
                         "base disable cleanup clears the stranded hover overlay")
          b.isEnabled = true    // re-enabling must NOT auto-restore a phantom hover
          XCTAssertEqual(alpha(b.buttonProbe.overlayColor), 0, accuracy: 0.001,
                         "re-enable does not resurrect the cleared hover (preview flag still set, gate now true → recomputed off because real isHovered was cleared)")
      }
  ```
  Note: `previewHovered` is still `true` after re-enable, so the merge would relight from the PREVIEW flag — assert via the REAL path instead by toggling `previewHovered=false` before disable if the re-enable line is ambiguous; keep the first two assertions (the load-bearing cleanup) and drop the third if it proves flaky in CI. `swift build` green locally; runs in CI.

- [ ] **Step 6: keyboardActivate seam — toggle (Checkbox) vs send (Button/FAB).** The base default `keyboardActivate()` = `flashThenActivate { activate() }` (fire-and-forget send); Checkbox OVERRIDES it to flash-then-TOGGLE while reusing the base flash helper. Assert both, plus the shared `isFlashing` atomicity (a 2nd Space inside the 0.12 s window is dropped):
  ```swift
      func testButtonKeyboardActivateSendsOnce() {
          let b = ThemedButton(palette: palette()); b.title = "B"
          b.frame = NSRect(x: 0, y: 0, width: 120, height: 36); b.layoutSubtreeIfNeeded()
          var count = 0; b.onTap = { count += 1 }
          b.keyDown(with: spaceDown())                  // flash → send
          b.keyDown(with: spaceDown())                  // inside the flash window → dropped (isFlashing)
          settle()
          XCTAssertEqual(count, 1, "base keyboardActivate = flash-then-send, atomic per press")
      }
      func testCheckboxKeyboardActivateTogglesViaSeam() {
          let c = ThemedCheckbox(palette: palette())
          c.frame = NSRect(x: 0, y: 0, width: 200, height: 42); c.layoutSubtreeIfNeeded()
          var changes = 0; c.onChange = { _ in changes += 1 }
          c.spaceKeyForTesting()                        // base flash helper → Checkbox's TOGGLE override
          XCTAssertTrue(c.isFlashingForTesting, "reuses the base flash (isFlashing in flight)")
          c.spaceKeyForTesting()                        // re-entry dropped by the shared isFlashing guard
          settle()
          XCTAssertEqual(changes, 1, "Checkbox overrides keyboardActivate to toggle (not send), once per press")
          XCTAssertTrue(c.isChecked, "the toggle landed")
      }
  ```
  `swift build` green locally; runs in CI.

- [ ] **Step 7: keep the four per-widget suites as the byte-equivalence net.** Do NOT edit `ThemedButtonTests.swift` / `ThemedFABTests.swift` / `ThemedCheckboxTests.swift` / `ThemedChipTests.swift` — they already pin every per-widget value (overlay alphas, elevation ladder, focus-ring opacity/stroke, Space-once, disable-during-flash, target/action storage, AX role/value). After the base extraction they must pass UNCHANGED — that IS the value-preservation proof. Add a one-line note at the top of the NEW file pointing back to them. `swift build` green locally; CI runs all five suites.

- [ ] **Step 8: write the prism before/after live-capture checklist into the PR body (maintainer-delegated, deterministic via preview*).** No code; record this checklist verbatim in the PR description so the maintainer captures it. For EACH of Button, FAB, Checkbox, Chip — plus ToolBar (regression: it pushes `previewHovered` down to a child ThemedButton, the shared hover path) and ComboBox-or-Menu (regression: another shared-helper consumer) — capture the four states using the widget's `preview*` overrides for determinism (no synthetic events):
  ```
  ### prism before/after (capture on origin/main THEN on feat-14b; diff must be pixel-identical)
  Recipe (per prism-bench memory): launch `.build/debug/prism` with PRISM_CONFIG=<theme.toml>
  in the background, get the window id, `screencapture -l<winid> -o out.png` (NO osascript activate
  — it jumps Spaces and flakes the capture). Flip the prism tab to the widget's card before capture.
  States via the showcase's preview* toggles (deterministic static frame):
    - resting   (no preview flag)
    - hover     (previewHovered = true)
    - pressed   (previewPressed = true)
    - focused   (previewFocused = true)   ← verifies the focus ring shape + 2pt outset
    - disabled  (isEnabled = false)        ← verifies the disable cleanup + muted paint
  Widgets:  ThemedButton (contained/text/outlined) · ThemedFAB (circular/extended) ·
            ThemedCheckbox (unchecked/checked/indeterminate) · ThemedChip (filled/outlined/keycap) ·
            ThemedToolBar (per-item hover via child Button) · ThemedComboBox OR ThemedMenu (shared path)
  Themes:  at least terminal (dark) + github-light (light) + one neon (cyberpunk) — covers the
           ring stroke = primary across luminance regimes.
  PASS = every before/after pair is byte-identical (the #14b value-preservation gate). Any diff =
         an unintended behaviour change; stop and reconcile against the spec §6 before merge.
  ```
  No `swift build` needed for this doc step.

- [ ] **Step 9: final `swift build` + commit.** Run `swift build` (local CLT gate) — must be green; the XCTest compiles + runs in CI, not locally. Commit with gitmoji + Conventional Commits:
  ```
  git add Tests/ThemeKitTests/ThemedControlTests.swift
  git commit  # message below
  ```
  Message:
  ```
  :white_check_mark: test(ThemeKit): #14b ThemedControl base-contract tests + prism before/after checklist

  Adds Tests/ThemeKitTests/ThemedControlTests.swift covering the extracted base's
  shared machinery via the existing DEBUG probes: fx-merge (real||preview AND gate),
  the Chip appearance/focus-gate seams, the concentric focusRingOutset(=Space.xxs)
  math on Button/FAB/Chip, the disable-cleanup contract, and the keyboardActivate
  seam (Checkbox toggle vs Button/FAB send). The four per-widget suites are kept
  unchanged as the byte-equivalence net. prism before/after live-capture checklist
  recorded in the PR body (maintainer-delegated; deterministic via preview*).

  swift test runs in CI (CLT-only locally); swift build green.

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  ```


---
