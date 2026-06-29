# #17k (t-01ys) — ThemedPillView effect-border knob (the perch-deferred slice)

Date: 2026-06-29
Task: `sill` furrow `t-01ys` (#17k)
Status: design approved → implementation

## Why this is narrower than the furrow task body

The `t-01ys` body was written against the **old AppKit `ThemedBorder`** (its line
citations `225-231` / `260-261` match `Sources/ThemeKit/ThemedBorder.swift`, which
now lives **only in the sibling session's worktree**, not on `main`). On `main`,
#17d already shipped the SwiftUI-native replacement **`AnimatedBorderView<S: Shape>`**
(`Sources/ThemeKitUI/AnimatedBorderView.swift`), which already covers most of the
listed #17k items:

| #17k item | status on `main` |
|---|---|
| #2 imperative flash | ✅ `flashToken` + internal `rollFlashBurst()` |
| #3 arbitrary-**Shape** stroke | ✅ already generic `<S: Shape>` (Capsule/Circle/TagShape/…) |
| #4 hue-cycle period | ✅ `cycleSeconds:` parameter |
| #5 outward glow parity (SwiftUI) | ✅ Canvas two-stop `.addFilter(.shadow)` |
| #6 clock | ✅ `TimelineView(.animation)` |
| #1 palette-free base color | ❌ still needs `palette`; serves **halo** (no consumer here) |
| #3 external CALayer/NSBezierPath | ❌ it's a SwiftUI View; serves **facet** rail/panel (no consumer here) |

So the *capability* the perch mock said it waited on — "ThemedBorder can only
stroke a roundedRect" — **is already solved**. The two remaining ❌ items serve
halo/facet, which have **no consumer in the perch direction**, and are split out to
separate future tasks (re-file under #17k follow-ups).

## Scope (approved)

Fill the **perch-mock-deferred** gap only: give pills an animated neon/effect
border across **all 5 shapes** (pill/square/circle/tag/underline) and fill the
deferred prism showcase row. Everything stays **SwiftUI-native**; no AppKit is
added (the `ThemeKitUI` AppKit floor — IME edit core + window shell — is unchanged).

## Approach

Thin overlay that **reuses #17d**: `ThemedPillView` gains a `borderEffect` knob;
when set it overlays an `AnimatedBorderView` stroked along the pill's own
`pillShape` (already `<S: Shape>`-generic, so the four closed shapes "just work").
The underline is special-cased locally (it is a bare bar, not a closed surface).

Rejected alternatives:
- **New `ThemedEffectPill` component** — YAGNI; `AnimatedBorderView(in:)` already is
  the effect rim.
- **Widen `AnimatedBorderView` with an open-path/bar mode** — widens a shared part
  for one shape; underline is handled with a tiny private line `Shape` instead.

## API additions (`ThemedPillView`)

All additive, defaults preserve current behavior (a call with no new args is
byte-identical to today). Flat params, matching `AnimatedBorderView`'s own style.

| param | default | role |
|---|---|---|
| `borderEffect: EffectSpec?` | `nil` | non-nil ⇒ pill carries the animated effect rim; nil ⇒ current tri-state border, unchanged |
| `borderGlow: AnimatedBorderGlow` | `.bloom` | rim glow style (`.none` / `.bloom`) |
| `borderCycleSeconds: Double` | `5` | hue/blend cycle period (exposes #17k item #4 to pills) |
| `flashToken: Int` | `0` | bump to roll a focus/match blink burst (perch drives on state change) |
| `previewFrozen: Bool` | `false` | hold the live cycle at a fixed phase (prism deterministic capture) |
| `previewPhase: CGFloat` | `0.35` | the phase held when `previewFrozen` |

No `effectsEnabled` param — 派手/静か is expressed by the app passing
`borderEffect: enabled ? spec : nil` (keeps the init from ballooning; `borderEffect:
nil` default is already the off state).

## Rendering rules (precedence with the existing tri-state border)

`borderOverlay` is rewritten to:

- `borderEffect != nil && state != .miss` → **effect rim**: `AnimatedBorderView(
  palette:, effect: borderEffect, in: pillShape, glow: borderGlow,
  cycleSeconds: borderCycleSeconds, flashToken:, previewFrozen:, previewPhase:)`.
  The static idle hairline and the matched `.shadow(radius: 7)` are **suppressed**
  (the rim already glows — no double border).
- `.miss` → **always the current error stroke** (red is a semantic signal; the rim
  must not eat it). The error surface wash (`fill(errorColor.opacity(0.20))`) and
  the error-colored prefix are unchanged.
- `borderEffect == nil` → the current `switch state` border, byte-identical.

Net: error semantics fully preserved; idle/matched gain the neon rim.

## Underline = neon bar (chosen)

`underlineContent`'s static `Rectangle().fill(...).frame(height: 2)` bottom overlay
is replaced, when `borderEffect != nil && state != .miss`, by an `AnimatedBorderView`
that strokes a private horizontal-line `Shape` (`HBarShape`) with `lineWidth: 2`.
The bar then cycles the effect color and blooms (a neon underline), reusing the
same engine — no separate fill path. `.miss` and the nil case keep the current
static bar (error on miss).

## prism deliverable

- `Sources/prism/PerchShowcase.swift`: remove the deferral note (lines 1–8) and add
  a **neon/effect-border row** — the 5 shapes (pill/square/circle/tag/underline) in
  one row, each `borderEffect: borderEffectFor(themeName) ?? .neon`, `state: .idle`,
  frosted — so it live-re-themes across every catalog theme. Optionally give the
  existing matched candidate an effect rim to show match=neon.
- `Sources/prism/PillShowcase.swift`: add effect-border variants to `MockThemedPill`.
- `Sources/prism/KitCatalog.swift`: note the new `borderEffect` knob in the
  ThemedPill entry.
- prism imports no app View (no drift): the row is built from the real
  `ThemedPillView` + `borderEffectFor` (Effects), exactly as `BorderShowcase` /
  `Gallery` / `HaloShowcase` already do.

## Known risk + verification plan

SwiftUI `Canvas` may **clip the outward bloom** at its own frame; pills are tightly
sized, so the neon halo could be cut at the pill edge. Plan: first wire the overlay
as-is and verify **LIVE in prism** (capture the perch tab across rainbow / neon /
chomp themes, `previewFrozen` for determinism). If the outward bloom clips
unacceptably, add a minimal **pure-SwiftUI** `bloomPad` to `AnimatedBorderView`
(inset the stroke + grow the canvas so the bloom has room) — no AppKit, so the
床ポリシー hard-gate is not touched. Judge by looks (見た目よければOK).

## Tests

- Pure seam in `PillLogic` (already the deterministic, CI-testable surface): factor
  the rim decision into a pure helper — e.g. `PillLogic.showsEffectRim(state:
  hasEffect:) -> Bool` (true iff `hasEffect && state != .miss`) and, for underline,
  the same gate. Add XCTest in `Tests/ThemeKitUITests` (or wherever `PillLogic` is
  tested) covering: no effect ⇒ no rim; effect + idle/matched ⇒ rim; effect + miss
  ⇒ no rim (error stroke).
- The SwiftUI rendering itself is **not** unit-testable on the CLT-only local setup
  (`swift test` needs Xcode); `swift build` is the local gate and the rim is proven
  **LIVE in prism** per the house rule.
- `AnimatedBorderView`'s own animation/glow/flash is already covered by
  `EffectsTests` (pure `resolveBorder`/`rollFlash`).

## Process

- Library change ⇒ minor bump + tag **`v1.37.0`** (confirmed free; re-check it is
  unclaimed before tagging — sibling session works concurrently).
- Isolated in worktree `worktree-17k-pill-effect-border` off clean `origin/main`;
  do **not** touch the sibling worktrees under `.claude/worktrees/17h-…` (the #17h
  AppKit deletion is their work).
- PR body footer: `SetStatus-task:
  https://github.com/akira-toriyama/projects/blob/main/.furrow/bodies/t-01ys.md
  <lane>` (open ⇒ in-progress; merge ⇒ lane).
- Green + clean CI ⇒ squash-merge + tag (standing autonomy), after the LIVE prism
  proof.
