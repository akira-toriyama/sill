# #17d AnimatedBorderView — SwiftUI-native animated surface border

**Status:** design approved (build-best scope, 2026-06-29). Board: `t-6a1b`.
**Template:** PR #83 (#17c `ThemedBackdropView`). **Version:** sill `v1.32.0`.

## What this is

The family's ONE themed surface border — a `Shape` stroked in the theme's
`primary` (static), or lit by an `EffectSpec` as a glowing / breathing /
colour-cycling **rim** (neon / rainbow / chomp) — rebuilt **SwiftUI-native** in
`ThemeKitUI`.

This is NOT a greenfield feature. The animated border already ships as the
**AppKit** `ThemeKit.ThemedBorder` (a 30 Hz `Timer` + two `CAShapeLayer`s) wrapped
by the #17a `NSViewRepresentable` bridge `ThemeKitUI.ThemedBorderView`. #17d is the
same remediation #17h/#17c did: **move the DRAW off AppKit** (`TimelineView(.animation)`
clock + `Canvas` stroke + Canvas `.shadow` glow), so the only AppKit left in
`ThemeKitUI` stays the **2 floors** (IME field-editor + non-activating panel shell).
The pure engine (`Effects.resolveBorder` & friends) is unchanged and reused verbatim.

## Consumers (investigated 2026-06-29, file:line)

| consumer | today | engine | shape / radius | glow | adopts #17d |
|---|---|---|---|---|---|
| **wand 枠** | `LauncherPanel.swift:1031` — `CALayer.borderColor` via `CAKeyframeAnimation` (rainbow 8-stop, 4 s); static themes fixed colour | **own** (not sill) | rounded r=8, w=2 | none | Phase B #20 — also **converges wand onto `resolveBorder`** |
| **facet tree** | `PanelHost.swift` — CALayer 1.5pt | sill `resolveBorder` | rounded r=12 `.continuous` | CALayer shadow | Phase B #18 |
| **facet grid** | `GridView.swift:247` — CALayer | sill `resolveBorder` | **square** | CALayer shadow | Phase B |
| **facet rail** | `RailView.swift:683` — `NSBezierPath` hand-drawn | sill `resolveBorder` | square | hand-drawn 3× halo | Phase B (glow `.none`, composes own) |
| **perch** | `HintPainter.swift:501` — `resolveBorder`+NSShadow | sill `resolveBorder` | pill r=10 | NSShadow | **NO — headless, no SwiftUI surface**; the proven app-side contract reference only |

Today none of the apps import the sill widget — they call the pure engine and
hand-draw (prism dogfoods the widget). #17d builds the SwiftUI front the Phase B
rebuilds (#18 facet pilot, #20 wand) drop in place of their hand-drawn stroke
(build-best-then-migrate).

## API (`ThemeKitUI`)

Mirrors `ThemedBackdropView<S: Shape>` (generic mask + `.modifier` ergonomic):

```swift
public struct AnimatedBorderView<S: Shape>: View {
    public init(palette: ResolvedPalette,
                effect: EffectSpec? = nil,        // nil ⇒ static primary stroke
                effectsEnabled: Bool = true,      // master 派手ON / 静かOFF
                in shape: S = RoundedRectangle(cornerRadius: 10, style: .continuous),
                lineWidth: CGFloat = 1.5,         // resting / min width
                breathTo: CGFloat? = nil,         // max breath; nil ⇒ lineWidth×2.5; ==lineWidth ⇒ no breath
                cycleSeconds: Double = 5,
                glow: Glow = .bloom,              // .bloom (two-stop neon) / .none (host composes)
                flashToken: Int = 0,              // bump ⇒ roll a focus/WS-switch blink burst
                previewFrozen: Bool = false,      // deterministic capture
                previewPhase: CGFloat = 0.35)
    public enum Glow: Sendable { case none, bloom }
}

public extension View {
    func animatedBorder<S: Shape>(_ palette:…, effect:…, in shape: S = …, …) -> some View // .overlay
}
```

Per-consumer fit: wand 枠 = `in: RoundedRectangle(r:8)`, w=2, `breathTo: 2` (no breath),
`cycleSeconds: 4`, `glow: .none`. facet tree = `in: RoundedRectangle(r:12,.continuous)`,
glow `.bloom`, bumps `flashToken` on WS-switch. facet grid/rail = `in: Rectangle()`;
rail `glow: .none`. Three facet surfaces = three instances ⇒ independent phases.

## Internals (the three fidelity points — delegated to the implementer)

1. **Clock** — `TimelineView(.animation)` with a birth-relative `@State var start = Date()`
   (reference-date epoch), exactly like `LinePetsView`/`ParticleBurstView`. The `Canvas`
   closure is a PURE `f(now)` (no `@State` write in render). Static/`previewFrozen`/
   reduce-motion → a single static `Canvas` (no TimelineView). reduce-motion via
   `@Environment(\.accessibilityReduceMotion)` rests on the effect's steady hue (phase 0).
2. **Two-stop bloom** — replicate the AppKit neon tube in `Canvas`: a wide soft layer
   (`drawLayer { addFilter(.shadow(c·0.45, r=w·4.8)); stroke }`) + a tight bright layer
   (`·0.85, r=w·2.2`) + a crisp core stroke on top. `glow: .none` ⇒ crisp stroke only.
   Static primary (`.off`) never glows.
3. **Rainbow byte-parity** — `.rainbowHue(h)` materializes via
   `Color(nsColor: NSColor(hue: h, saturation: 0.9, brightness: 1, alpha: 1))` — the
   CALIBRATED space facet/halo/perch use; NEVER pre-convert to sRGB (Effects.swift:289-292).
   `.rgb` → `Color(.sRGB,…)`; `.off` → `Color(nsColor: palette.primary)`.

Resolve each frame via the unchanged pure
`resolveBorder(spec: effectsEnabled ? effect : nil, baseWidth: lineWidth,
minWidth: lineWidth, maxWidth: breathTo ?? lineWidth×2.5, cycleSeconds:, cycleColors: true,
now:, flash:)`. **flash** is rolled INTERNALLY on `flashToken` change (via the view's own
clock (`timeIntervalSince(start)`, birth-relative like LinePetsView) so the burst epoch
matches the sample epoch — sidesteps the CACurrentMediaTime vs reference-date mismatch a
host-supplied `FlashState` would hit). Stroke path = the generic
`shape.path(in: bounds.insetBy(lineWidth/2))` — half the RESTING width keeps the stroke flush
without clipping and a fixed-radius rounded-rect mask ~concentric with the surface (a fat
breath's slight overflow is masked by the bloom, or absent when breathing is off).

## Retirement (build-best)

- **Delete** `ThemeKitUI/ThemedBorderView.swift` (the NSViewRepresentable bridge) and
  `ThemeKit/ThemedBorder.swift` (the AppKit widget) + `Tests/ThemeKitTests/ThemedBorderTests.swift`
  (its `borderProbe` coverage; ThemeKitUI keeps no test target by convention — proven LIVE in prism).
- **Rewire prism dogfood** to `AnimatedBorderView`: the Gallery card rim
  (`Gallery.swift:303`), the halo ring (`HaloShowcase.swift:56`), `BorderShowcase.swift`
  (`MockBorder`), the `KitCatalog` entry (→ name `AnimatedBorderView`, module `ThemeKitUI`).
- Update doc-comment mentions of `ThemedBorder` (Palette.swift, AnimatedPalette.swift, Shared.swift).

## Verification

- `swift build` green (local CLT gate). No new XCTest target (ThemeKitUI convention;
  the pure `resolveBorder` logic is already covered by `EffectsTests`).
- **prism LIVE** (maintainer + self-capture): the feedback-tab `MockBorder` + the card
  rim + halo ring across themes — static primary / live rainbow cycle / two-stop bloom /
  effects-off rest — must render and re-theme. (flash burst is API-ready for facet Phase B;
  it is a transient not captured in a still.)
- Adversarial code-review pass before merge.
