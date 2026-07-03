// ThemeKitUI — SwiftUI-native animated surface border (#17d).
//
// The family's ONE themed surface outline: a `Shape` stroked in the theme's
// `primary` (static, calm default), or — given an `EffectSpec` with effects ON —
// the LIVE rim: a glowing, breathing, colour-cycling neon / rainbow / chomp
// stroke. Every app outlines its signature surface (facet's tree panel / grid /
// rail, wand's launcher 枠, halo's ring, a card) and used to hand-draw that
// stroke; this is the ONE shared part (rule-of-three).
//
// SwiftUI-NATIVE (#17d). This REPLACES the #17a AppKit path — the AppKit
// `ThemeKit.ThemedBorder` (a 30 Hz `Timer` + two `CAShapeLayer`s) wrapped by the
// `NSViewRepresentable` bridge `ThemedBorderView`. Same remediation as #17h/#17c:
// the DRAW moves to a SwiftUI `Canvas` driven by `TimelineView(.animation)`, with
// the two-stop neon bloom rebuilt from Canvas `.shadow` filters — so `ThemeKitUI`
// keeps AppKit only at the 2 floors. The PURE engine (`Effects.resolveBorder` &
// friends) is unchanged and reused verbatim; this view is just its SwiftUI front.
// Design: docs/superpowers/specs/2026-06-29-17d-animated-border-design.md
//
// GENERAL by design (mirrors `ThemedBackdropView`): the stroked mask is any
// `Shape` (default a continuous rounded rect), so wand's r=8 枠, facet's r=12
// tree panel, a square grid/rail edge, and a circular ring all use the same part.
// Apps pass their corner radius / shape; prism shows the same pixels in every
// theme. Re-themes by reassigning `palette`.
//
// CLOCK: live = `TimelineView(.animation)` with a birth-relative reference-date
// `@State var start` (the SAME `f(now)` the apps drive `resolveBorder` with),
// matching `LinePetsView` / `ParticleBurstView`. The `Canvas` closure is a PURE
// derivation of `now` — NO `@State` is written during render. Static (no effect /
// master off), `previewFrozen`, and reduce-motion render a single static `Canvas`
// (no running clock); reduce-motion rests on the effect's steady hue (phase 0).

import SwiftUI
import AppKit
import PaletteKit
import Effects

/// Glow under the live effect rim. `.none` = a flat stroke; `.bloom` = the
/// two-stop neon-tube halo scaled by the breathing width (the static `primary`
/// border never glows, whichever is set).
public enum AnimatedBorderGlow: Sendable { case none, bloom }

/// A themed surface border: a `Shape` stroked in `palette.primary` (static) or
/// lit by an `EffectSpec` as a glowing / breathing / cycling rim.
public struct AnimatedBorderView<S: Shape>: View {
    public var palette: ResolvedPalette
    /// The effect to animate, or `nil` for a static `primary` stroke. Resolve it
    /// from a theme name via `borderEffectFor(_:)` (Effects).
    public var effect: EffectSpec?
    /// Master switch: `false` rests to the static `primary` stroke even with an
    /// effect set (派手好き ON / 静か OFF) — the same flag a host passes to
    /// `ResolvedPalette.animated(forTheme:at:enabled:)` so the theme rests together.
    public var effectsEnabled: Bool
    /// The stroked mask. Default = a continuous rounded rect (r = 10).
    public var shape: S
    /// Resting / minimum stroke width.
    public var lineWidth: CGFloat
    /// Maximum breathing width. `nil` ⇒ `lineWidth × 2.5` (breathes); pass a value
    /// `== lineWidth` for a fixed-width stroke (no breathing, e.g. wand / perch).
    public var breathTo: CGFloat?
    /// Seconds for one full colour cycle (wand uses 4).
    public var cycleSeconds: Double
    /// Glow style for the LIVE rim. The static stroke never glows.
    public var glow: AnimatedBorderGlow
    /// Bump this to roll a focus / workspace-switch blink burst (facet). The burst
    /// is rolled INTERNALLY from the effect's flash palette on the view's OWN clock,
    /// so its epoch matches the sample epoch (a host-supplied `FlashState` rolled in
    /// `CACurrentMediaTime` would mismatch the reference-date Timeline clock).
    public var flashToken: Int
    /// Hold the live cycle at a FIXED phase WITHOUT a running clock — previews /
    /// screenshots (a moving border captures non-deterministically).
    public var previewFrozen: Bool
    /// The phase held when `previewFrozen` (a recognizable mid-cycle colour).
    public var previewPhase: CGFloat

    public init(palette: ResolvedPalette,
                effect: EffectSpec? = nil,
                effectsEnabled: Bool = true,
                in shape: S = RoundedRectangle(cornerRadius: 10, style: .continuous),
                lineWidth: CGFloat = 1.5,
                breathTo: CGFloat? = nil,
                cycleSeconds: Double = 5,
                glow: AnimatedBorderGlow = .bloom,
                flashToken: Int = 0,
                previewFrozen: Bool = false,
                previewPhase: CGFloat = 0.35) {
        self.palette = palette
        self.effect = effect
        self.effectsEnabled = effectsEnabled
        self.shape = shape
        self.lineWidth = lineWidth
        self.breathTo = breathTo
        self.cycleSeconds = cycleSeconds
        self.glow = glow
        self.flashToken = flashToken
        self.previewFrozen = previewFrozen
        self.previewPhase = previewPhase
    }

    /// Birth time — READ only inside the render closure so the live clock is
    /// birth-relative (the reference-date epoch the flash roll also stamps in).
    @State private var start = Date()
    /// The pre-rolled focus/WS-switch blink, rolled on `flashToken` change.
    @State private var flash: FlashState?
    /// reduce-motion rests the rim on its steady hue (no running clock).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The live effect rim runs only for an enabled effect, not frozen, not
    /// reduce-motion. Everything else is a single static frame.
    private var isLive: Bool {
        effect != nil && effectsEnabled && !previewFrozen && !reduceMotion
    }

    /// The fattest breathing width — the upper bound `resolveBorder` breathes to
    /// (the lower bound is `lineWidth`).
    private var maxBreath: CGFloat { max(lineWidth, breathTo ?? lineWidth * 2.5) }

    public var body: some View {
        content.onChange(of: flashToken) { rollFlashBurst() }
    }

    @ViewBuilder
    private var content: some View {
        if isLive {
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    paint(into: &ctx, size: size,
                          now: timeline.date.timeIntervalSince(start))
                }
            }
        } else {
            // Static: frozen → the chosen phase; else steady (phase 0).
            Canvas { ctx, size in
                paint(into: &ctx, size: size,
                      now: previewFrozen ? Double(previewPhase) * cycleSeconds : 0)
            }
        }
    }

    // MARK: - Flash

    /// Roll a fresh blink burst from the effect's flash palette, stamped on the
    /// view's own clock so the sample epoch matches.
    private func rollFlashBurst() {
        guard let fx = effect, effectsEnabled, !fx.flash.isEmpty else { flash = nil; return }
        flash = rollFlash(fx.flash, now: Date().timeIntervalSince(start))
    }

    // MARK: - Render (a pure f(now) — no @State write here)

    private func paint(into ctx: inout GraphicsContext, size: CGSize, now: Double) {
        let bounds = CGRect(origin: .zero, size: size)
        // Inset by half the RESTING width so the stroke sits flush inside the
        // surface edge without clipping (a fat breath's slight overflow is masked
        // by the bloom, or absent when breathing is off). Kept small so a
        // fixed-radius rounded-rect mask stays ~concentric with the surface.
        let inset = lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return }
        let path = shape.path(in: rect)

        let frame = resolveBorder(
            spec: effectsEnabled ? effect : nil,   // master off ⇒ static primary
            baseWidth: Double(lineWidth),
            minWidth: Double(lineWidth),
            maxWidth: Double(maxBreath),
            cycleSeconds: cycleSeconds,
            cycleColors: true,
            now: now,
            flash: effectsEnabled ? flash : nil)

        let color = swiftUIColor(frame.color)
        let w = CGFloat(frame.width)

        // The static `primary` stroke (`.off`) never glows; the live rim glows
        // when `.bloom`. Two-stop neon tube + a crisp centerline, both the stroke
        // colour, scaled by the breathing width (the retired AppKit
        // AnimatedCardBorder look, rebuilt in Canvas).
        guard glow == .bloom, frame.color != .off else {
            ctx.stroke(path, with: .color(color), lineWidth: w)
            return
        }
        // Wide soft wash (behind) + tight bright halo, each a stroke that casts
        // its own scoped shadow.
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: color.opacity(0.45), radius: w * 4.8))
            layer.stroke(path, with: .color(color), lineWidth: w)
        }
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: color.opacity(0.85), radius: w * 2.2))
            layer.stroke(path, with: .color(color), lineWidth: w)
        }
        // The crisp bright centerline on top (no shadow filter), free of glow
        // bleed — the AppKit strokeLayer's own sharp stroke.
        ctx.stroke(path, with: .color(color), lineWidth: w)
    }

    /// Materialize a resolved `BorderColor` into a SwiftUI `Color`. `.rainbowHue`
    /// goes through the CALIBRATED `NSColor(hue:…)` space the apps (facet/halo/
    /// perch) use — pre-converting to sRGB would shift the rainbow's gamut
    /// (Effects.swift:289-292). `.off` is the palette-side fallback.
    private func swiftUIColor(_ bc: BorderColor) -> Color {
        switch bc {
        case .off:
            return Color(nsColor: palette.primary)
        case .rgb(let r, let g, let b):
            return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
        case .rainbowHue(let h):
            return Color(nsColor: NSColor(hue: h, saturation: 0.9, brightness: 1, alpha: 1))
        }
    }
}

public extension View {
    /// Overlay an ``AnimatedBorderView`` rim on this view (DRY ergonomic for
    /// `.overlay(AnimatedBorderView(...))`).
    func animatedBorder<S: Shape>(
        _ palette: ResolvedPalette,
        effect: EffectSpec? = nil,
        effectsEnabled: Bool = true,
        in shape: S = RoundedRectangle(cornerRadius: 10, style: .continuous),
        lineWidth: CGFloat = 1.5,
        breathTo: CGFloat? = nil,
        cycleSeconds: Double = 5,
        glow: AnimatedBorderGlow = .bloom,
        flashToken: Int = 0,
        previewFrozen: Bool = false,
        previewPhase: CGFloat = 0.35
    ) -> some View {
        overlay(AnimatedBorderView(
            palette: palette, effect: effect, effectsEnabled: effectsEnabled,
            in: shape, lineWidth: lineWidth, breathTo: breathTo,
            cycleSeconds: cycleSeconds, glow: glow, flashToken: flashToken,
            previewFrozen: previewFrozen, previewPhase: previewPhase))
    }
}
