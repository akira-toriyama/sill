# perch prism app-mock — design (2026-06-29)

Task: **t-yc68** (sill: prism app-mock 再構築 — Phase B 適用の前段), perch arm.
Depends on already-shipped sill parts: **#17g ThemedPill (PR #87)** + **#17i WindowShell (PR #88)**.

## Goal

Rebuild perch's signature overlay chrome (the universal "hint pill") in the prism
visual bench out of the **real** `ThemedPillView`, and confirm it composes across
ALL catalog themes — a cheap de-risk before perch's real application. prism imports
no app View, so the scene is mirrored by eye (zero drift).

## Coverage finding (why this is cheap)

A code-level audit (perch `HintPainter.swift` ↔ sill `ThemedPillView.swift`) found
perch's overlay is **already ~fully covered** by the merged parts:

- **ThemedPill renders**: 5 shapes (pill/square/circle/underline/tag), two-color
  typed-prefix label, tri-state (idle/matched/miss), drop shadow, matched glow
  (accent@0.5 blur7 + 2pt stroke), corner badge (perch passes the string),
  transform/opacity passthrough — most matching perch's draw values verbatim.
- **WindowShell renders** the non-activating, focus-free, click-through, all-Spaces
  overlay window (`clickThroughOverlay` recipe) — the real perch window shape.
- **app-essential (stays in perch)**: every motion driver — appear/match/unmatch
  effects, particles, ghost choreography, the ~30 Hz hue-cycle clock. sill provides
  the transform/opacity rail; perch owns the curves.

## The one true sill gap (de-risk payoff)

**Effect border (neon/cyber/vapor/kawaii/rainbow) across all pill shapes** — perch's
animated chrome. ThemedPill v1 has no border-effect arg and the current ThemedBorder
only strokes a roundedRect (can't follow Capsule/TagShape/underline). Owner =
**#17k [t-01ys]** (ThemedBorder arbitrary-path stroke). Deferred out of this mock.

## Decision: ship the covered range now, defer the neon row to #17k

(user-approved 2026-06-29) The mock stages everything covered today; the
neon/effect-border row lands after #17k. This de-risks immediately and identifies
#17k as the clean next part.

## What we build

- **New file** `Sources/prism/PerchShowcase.swift` housing `struct MockPerchOverlay:
  View { let p: ResolvedPalette }` — following the app-flavored showcase precedent
  `HaloShowcase.swift` (and keeping `Specimens.swift` from bloating).
- **Replace + delete** the drawn-by-eye `MockPill` (`Specimens.swift:303`, hand-built
  capsules — NOT the real widget). Repoint `case .perch:` (`Gallery.swift:382`) to
  `MockPerchOverlay(p: p)`. Rationale: hosting the REAL `ThemedPillView` is the whole
  de-risk point; a fake pill beside the real one is drift. Kit-grid coverage already
  lives in `MockThemedPill` under the `.action` tab.

### Scene composition (`MockPerchOverlay`)

`SpecimenBox(title: "perch · overlay", p:)` wrapping a fixed-height faux-desktop
backdrop (an elevated rounded rect + a couple of faint content bars, so the frosted
pills read as floating over UI). Real `ThemedPillView` pills scattered at
element-anchor-like positions (Vimium convention), staging the full covered range:

- a cluster of **idle** pills, different keys, two-color typed-prefix (`typedCount: 1`)
- one **matched** pill (glow) — the active candidate
- 1–2 **ghost** pills — idle look + low `opacity` + small `transform` scale
- a **miss** pill (`state: .miss`)
- a **badge** pill (`badge: "⌘"`)
- an **underline**-shape pill and a **tag**-shape pill (+ a single-glyph **circle**)

Scene pills use perch's frosted-floating look (`frosted: true, surfaceAlpha: 0.3`).
ThemeCard supplies `p` across all themes; on an animatable theme its 30 Hz
`TimelineView` drives `p`, so the matched glow breathes live with zero extra wiring.

## Out of scope (explicit, follow-up)

- neon/effect border row → **#17k [t-01ys]** (then a `borderEffect` knob on ThemedPill).
- particle burst → omitted in the mock (or a few faux `Circle`s); a reusable sill
  particle util is a future rule-of-three decision, not this pass.
- desktop behind-window blur → **not a mock concern** (prism has no real desktop). At
  real application decide: drop per the #17c precedent (cosmetic/toggleable) or, if
  perch insists, a window-shell AppKit floor = 要相談.
- cosmetic deltas (miss = error wash vs full fill swap; pad 12/9 vs 10/4; underline
  idle @0.55 dimming) → keep sill defaults (sill-first consistency); revisit by eye
  only if the live scene looks wrong.

## Verification

- `swift build` green (the local CLT gate).
- **prism live** (the UI gate): flip to the perch (Apps) tab, screencapture the card
  across at least **neon-noir** (dark) + **github-light** (light) + one animatable
  theme (to watch the matched glow breathe). If a light theme renders the frosted
  pills unreadable, that surfaces perch's per-theme alpha policy (app-side) — a real
  de-risk finding, adjust `surfaceAlpha` by eye.
- No new XCTest — pill logic is covered by `PillLogicTests`; this is pure composition.

## Task linkage

- Advances **t-yc68** (perch app-mock). PR footer: `SetStatus-task: …/t-yc68.md`.
- Implemented off clean `origin/main` in an isolated worktree (parallel-work hazard).
- Note: t-kjcr part (b) ThemedPill shipped via #87 with a lane-less footer, so its
  furrow card still reads `backlog` — a board catch-up is separate from this work.
