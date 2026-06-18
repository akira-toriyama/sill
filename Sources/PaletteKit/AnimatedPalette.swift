// PaletteKit — compose an Effects `AnimatedFrame` onto a resolved palette.
//
// `Effects.animatedPalette(theme:at:)` returns only the time-varying ACCENT
// atoms (primary / secondary / selection) for one phase, DELIBERATELY not a
// full `ResolvedPalette`: Effects must not depend on PaletteKit (halo links
// Effects WITHOUT it), so the layer graph stays acyclic. The composition
// therefore lives HERE — the higher AppKit tier that owns `ResolvedPalette` —
// grafting the animated accent onto an otherwise-steady palette so a consumer
// can drive a LIVE theme each frame.
//
// This is the shared helper that was missing: a caller (facet) hand-assigned
// the three fields onto a copy, with no one place that did it. prism now drives
// each widget's palette through it (see the gallery's `TimelineView`); apps
// adopt it from their View layer at their own redraw cadence.
//
// Layer note: this is the one edge that adds PaletteKit → Effects (both are
// AppKit-tier; Effects depends only on Palette, so no cycle). A `Palette`-only
// consumer still links neither AppKit nor Effects.

import AppKit
import Palette
import Effects

public extension ResolvedPalette {
    /// A fresh copy with the ACCENT TRIO — `primary` / `secondary` /
    /// `selection` — replaced by an Effects `AnimatedFrame`'s animated atoms,
    /// while every other role (background / foreground / muted / tertiary /
    /// border / hover / error, plus `font` and the rendering hints) is held
    /// STEADY so the UI stays legible as the accent cycles.
    ///
    /// The frame carries exactly those three fields, and already keys its
    /// `selection` to the live `primary` at the theme's own selection alpha —
    /// so the selected-row wash tracks the cycling accent without jumping the
    /// instant animation engages.
    func applying(_ frame: AnimatedFrame) -> ResolvedPalette {
        ResolvedPalette(
            background: background, foreground: foreground, muted: muted,
            tertiary: tertiary,
            primary: frame.primary, secondary: frame.secondary,
            border: border, hover: hover, selection: frame.selection,
            error: error, font: font, backgroundAlpha: backgroundAlpha,
            vibrancyMaterial: vibrancyMaterial, forceDarkAqua: forceDarkAqua)
    }

    /// Cycle this palette's THEME to `phase` (0…1, wrapping) and graft the
    /// animated accent onto it. Returns `self` UNCHANGED for a non-animatable
    /// theme — only a theme that resolves to a built-in effect cycles (`rainbow`,
    /// `chomp`, and the animated-neon set `voltage` / `toxic` / `ember` /
    /// `solar-veil` / `molten-vein` / `coin-op` / `arcane`); ask
    /// `Effects.isAnimatableTheme(_:)` for the authority. Every other theme keeps
    /// its fixed accent — so a caller can call it every frame without first
    /// branching on whether the theme animates.
    ///
    /// `name` is the resolved THEME name (a `ResolvedPalette` doesn't carry its
    /// own name); pass the same name you resolved the base from. Equivalent to
    /// `Effects.animatedPalette(theme:at:)` followed by `applying(_:)`.
    ///
    /// `enabled` is the master effects switch (派手好き ON / 静か OFF): pass `false`
    /// and the palette rests STATIC regardless of theme — the same flag a host
    /// passes to `ThemedBorder.effectsEnabled`, so the whole theme (widget accents
    /// + border) animates or rests together. A host reads ONE preference and wires
    /// it to both.
    func animated(forTheme name: String, at phase: CGFloat, enabled: Bool = true) -> ResolvedPalette {
        guard enabled, let frame = Effects.animatedPalette(theme: name, at: phase) else { return self }
        return applying(frame)
    }
}
