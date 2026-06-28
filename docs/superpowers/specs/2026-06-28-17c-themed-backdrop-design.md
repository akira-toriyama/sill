# #17c ThemedBackdrop — SwiftUI-native themed backdrop surface (no blur)

**Status:** design approved (direction confirmed 2026-06-28). Supersedes the board/ROADMAP
working title "BlurBackdropView" — **blur is dropped** (see investigation below), so the part
is named for what it is: a themed *backdrop surface*.

## Problem & investigation

#17c was scoped as a shared blur/vibrancy backdrop (`.ultraThinMaterial` default; `NSVisualEffectView`
only via 要相談). Grounding the requirement against the real consumers (wand/perch/facet, 6-agent
investigation + adversarial verify, 2026-06-28) found that **all three use `.behindWindow` gaussian
blur** — which SwiftUI `Material` *cannot* reproduce (Material only blurs within-window content). That
would force `NSVisualEffectView` into `ThemeKitUI`, breaking the AppKit 床2個 policy.

But the deeper finding: **behind-window blur is not essential for any consumer.** In every case it is a
toggleable cosmetic knob with an existing solid fallback:

- **wand** — blur is a config knob (default on); off ⇒ solid `black @ 0.8` fill (cards/badge). Legibility
  never depends on blur.
- **perch** — off ⇒ pill opacity `0.30 → 0.75` + accent border + drop shadow; reads fine.
- **facet** — blur affects only the **`system` theme (1 of 32)**; the other 31 are opaque and work.

Verdict (user-confirmed, "僅かな痛みなら統一化の方がいい"): **do not break the policy for cosmetic
frosting.** Replace behind-window blur with a pure-SwiftUI **solid fill or translucent scrim** (the
desktop shows through *dimmed but not blurred* — pure `Color.opacity`, no `NSVisualEffectView`). The one
real loss is facet's `system` theme native-menu frosting (cosmetic).

## Design

A single, general, DRY pure-SwiftUI surface. No AppKit views — **床2個 unchanged.**

```swift
public enum BackdropFill: Sendable, Equatable {
    case auto                      // derive from the palette
    case solid                     // opaque themed fill
    case scrim(opacity: Double)    // translucent tint (desktop shows through DIMMED, not blurred)
    case clear                     // border-only / spacer
}

public struct ThemedBackdropView<S: Shape>: View {
    public var palette: ResolvedPalette
    public var shape: S            // any Shape; default continuous rounded-rect (r=10)
    public var fill: BackdropFill  // default .auto
    public var bordered: Bool      // optional hairline (palette.border)
    public init(palette:, in shape: S = RoundedRectangle(cornerRadius: 10, style: .continuous),
                fill: BackdropFill = .auto, bordered: Bool = false)
}

public extension View {                 // DRY ergonomic
    func themedBackdrop<S: Shape>(_ palette:, in shape: S = …, fill: = .auto, bordered: = false) -> some View
}
```

**Fill resolution (`.auto`, pure `plan(...)` helper — no AppKit):**

| palette state | result |
|---|---|
| `background != nil`, `backgroundAlpha == nil` | opaque solid fill |
| `background != nil`, `backgroundAlpha = a`    | scrim at `a` (panel/pill knob) |
| `background == nil` (vibrancy theme)          | translucent system surface scrim at `backgroundAlpha ?? 0.85` |

Fill colour = `Color(nsColor: palette.background ?? .windowBackgroundColor)`; vibrancy themes (nil
background) fall back to the dynamic system surface. `.solid`/`.scrim`/`.clear` override `.auto`.

**Why general:** the mask is any `Shape` (cards = rounded-rect, pills = `Capsule`, panels = r=12) so one
widget serves wand cards, perch pills, facet panels; fill is palette-driven so it re-themes across all 32
themes; border is opt-in. Apps swap their per-surface `NSVisualEffectView` for `ThemedBackdropView` (or
`.themedBackdrop(p)`) at the back of their `NSHostingView` content.

**Rejected alternatives:** (a) rounded-rect-only (no generic Shape) — less general, user asked 汎用的;
(b) `ViewModifier`-only — can't stand alone as a full-panel backdrop. Chose generic `View` + a convenience
modifier (both).

## Out of scope / follow-ups (暗黙にしない)

- Behind-window gaussian blur: **dropped.** Re-add only if a future consumer proves it essential — then
  per [[investigate-apps-before-rulebreak]] it's a fresh 要相談 with app evidence.
- Vibrancy/`system`-theme `background == nil` is now an anomaly (it existed for `NSVisualEffectView`).
  Resolving it to a concrete translucent surface in PaletteKit is a **separate follow-up** (not #17c); the
  widget handles nil gracefully via the `.windowBackgroundColor` fallback meanwhile.
- Appearance (`forceDarkAqua`) for the nil-background fallback is left to the host window's appearance.

## Verification

- `swift build` green (local CLT gate). ThemeKitUI has no test target by convention; the `plan(...)` fill
  logic is a pure, reviewable static helper (UI proven live in prism, per CLAUDE.md).
- prism: a `MockBackdrop` card in the `feedback` family (KitCatalog entry + `BackdropShowcase` + Gallery
  `WidgetSection`) renders fill modes + shapes + scrim-over-pattern across every theme.
- **prism live maintainer check** (agents can't screen-record) before merge.
