// PaletteKit — the AppKit resolver. The ONLY sill target that imports
// AppKit. Turns a pure `ThemeSpec` into a `ResolvedPalette` of
// `NSColor`s, applying the DERIVE RECIPE for any field the spec left
// nil. Also provides the `@MainActor` module-level `pal` var (facet's
// invariant), the `uiFont` factory (incl. `.menu`), `tertiary()`, and
// `blendThrough`.
//
// Layer rule: a consumer that wants only the pure spec depends on
// `Palette` and never links this module → never links AppKit.

import AppKit
import Palette

// MARK: - NSColor from HexColor

public extension NSColor {
    /// Build an sRGB `NSColor` from a `0xRRGGBB` hex + alpha.
    convenience init(hex: UInt32, _ a: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green:   CGFloat((hex >> 8)  & 0xFF) / 255,
                  blue:    CGFloat( hex        & 0xFF) / 255,
                  alpha:   a)
    }

    /// Build from a pure `HexColor` value.
    convenience init(_ c: HexColor) {
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.alpha)
    }
}

// MARK: - ResolvedPalette

/// A fully-resolved theme: every field is a concrete `NSColor` (or nil
/// bg for vibrancy). This is what views read via `pal`. `@MainActor`
/// because `NSColor` isn't `Sendable` under Swift 6 strict concurrency.
@MainActor
public struct ResolvedPalette {
    public let bg: NSColor?
    public let text: NSColor
    public let dim: NSColor
    public let accent: NSColor
    public let accent2: NSColor
    public let divider: NSColor
    public let hoverFill: NSColor
    public let selFill: NSColor
    public let error: NSColor
    public let font: FontKind
    /// `bgAlpha` from the spec (nil ⇒ opaque) — the panel/pill knob.
    public let bgAlpha: CGFloat?
    /// Rendering hints for the `system` preset (vibrancy). Not part of
    /// the pure spec — pure logic shouldn't know about NSVisualEffect.
    public let vibrancyMaterial: NSVisualEffectView.Material?
    public let forceDarkAqua: Bool

    public init(
        bg: NSColor?, text: NSColor, dim: NSColor, accent: NSColor,
        accent2: NSColor, divider: NSColor, hoverFill: NSColor,
        selFill: NSColor, error: NSColor, font: FontKind,
        bgAlpha: CGFloat?,
        vibrancyMaterial: NSVisualEffectView.Material?,
        forceDarkAqua: Bool
    ) {
        self.bg = bg; self.text = text; self.dim = dim
        self.accent = accent; self.accent2 = accent2
        self.divider = divider; self.hoverFill = hoverFill
        self.selFill = selFill; self.error = error; self.font = font
        self.bgAlpha = bgAlpha
        self.vibrancyMaterial = vibrancyMaterial
        self.forceDarkAqua = forceDarkAqua
    }

    /// A faded variant of `text` for least-emphasis captions — the
    /// shared "tertiary" tier between `text` and `dim`.
    public func tertiary(_ alpha: CGFloat = 0.55) -> NSColor {
        text.withAlphaComponent(alpha)
    }
}

// MARK: - Derive recipe

/// Resolve a pure `ThemeSpec` into `NSColor`s, deriving any nil field.
///
/// DERIVE RECIPE (matches facet's 16 dark editor presets exactly, and
/// supplies sane light-theme equivalents when a light spec omits the
/// trio):
///   * accent  → spec.accent, OR `controlAccentColor` when the
///     sentinel (0) is set (the `system` preset).
///   * accent2 → spec.accent2 if set, else the accent's hue rotated
///     +180° (complement) at the accent's saturation/brightness.
///   * neutral base = white on a dark bg, black on a light bg (the
///     `isLight` branch). `nil` bg (vibrancy) is treated as dark.
///   * divider   → override, else neutral@0.10.
///   * hoverFill → override, else neutral@0.05.
///   * selFill   → override, else accent@0.18.
///   * tertiary  → text@0.55 (via ResolvedPalette.tertiary()).
///
/// `system` is special-cased: bg nil, dynamic system colors for
/// text/dim/divider/hover/sel, vibrancy + dark-aqua hints emitted.
///
/// `bgOverride` lets an app substitute its own panel/pill bg (perch's
/// translucent pill vs facet's opaque panel) while keeping the
/// canonical accent/text/dim/font. `material` / `forceDark` override
/// the system-preset rendering hints when supplied.
@MainActor
public func resolve(
    _ spec: ThemeSpec,
    bgOverride: HexColor? = nil,
    material: NSVisualEffectView.Material? = nil,
    forceDark: Bool? = nil
) -> ResolvedPalette {

    // --- system preset: dynamic colors + vibrancy ---
    if spec.bg == nil && spec.usesSystemAccent {
        let bg = bgOverride.map { NSColor($0) }   // usually nil → vibrancy
        return ResolvedPalette(
            bg: bg,
            text: .labelColor,
            dim: .secondaryLabelColor,
            accent: .controlAccentColor,
            accent2: .systemPurple,
            divider: NSColor.labelColor.withAlphaComponent(0.22),
            hoverFill: NSColor.secondaryLabelColor.withAlphaComponent(0.12),
            selFill: NSColor.controlAccentColor.withAlphaComponent(0.22),
            error: NSColor(spec.error),
            font: spec.font,
            bgAlpha: spec.bgAlpha.map { CGFloat($0) },
            vibrancyMaterial: material ?? .underWindowBackground,
            forceDarkAqua: forceDark ?? false)
    }

    // --- concrete spec: apply derive recipe ---
    let accentNS: NSColor = spec.usesSystemAccent
        ? .controlAccentColor
        : NSColor(spec.accent)

    let accent2NS: NSColor = spec.accent2.map { NSColor($0) }
        ?? complement(of: accentNS)

    // Neutral base for derived divider / hover. White on dark, black on
    // light. nil bg counts as dark (vibrancy overlay reads dark).
    let neutral: NSColor = spec.isLight ? .black : .white

    let dividerNS: NSColor = spec.divider.map { NSColor($0) }
        ?? neutral.withAlphaComponent(0.10)
    let hoverNS: NSColor = spec.hoverFill.map { NSColor($0) }
        ?? neutral.withAlphaComponent(0.05)
    let selNS: NSColor = spec.selFill.map { NSColor($0) }
        ?? accentNS.withAlphaComponent(0.18)

    let bgHex = bgOverride ?? spec.bg
    let bgNS: NSColor? = bgHex.map { NSColor($0) }

    return ResolvedPalette(
        bg: bgNS,
        text: NSColor(spec.text),
        dim: NSColor(spec.dim),
        accent: accentNS,
        accent2: accent2NS,
        divider: dividerNS,
        hoverFill: hoverNS,
        selFill: selNS,
        error: NSColor(spec.error),
        font: spec.font,
        bgAlpha: spec.bgAlpha.map { CGFloat($0) },
        vibrancyMaterial: material,
        forceDarkAqua: forceDark ?? false)
}

/// Complement of a color: hue + 0.5 (wrapping), same saturation /
/// brightness. Used when a spec omits `accent2`.
@MainActor
private func complement(of c: NSColor) -> NSColor {
    let s = c.usingColorSpace(.sRGB) ?? c
    var h: CGFloat = 0, sat: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
    s.getHue(&h, saturation: &sat, brightness: &br, alpha: &a)
    // Greyscale accent (sat≈0, e.g. mono / monotone) has no meaningful
    // complement — return a slightly lighter grey instead of a hue flip.
    if sat < 0.05 {
        return NSColor(white: min(1, br * 0.7 + 0.15), alpha: a)
    }
    return NSColor(hue: (h + 0.5).truncatingRemainder(dividingBy: 1),
                   saturation: sat, brightness: br, alpha: a)
}

// MARK: - Module-level `pal`

/// Current resolved theme. facet's invariant: a short `@MainActor`
/// module-level var read as `pal.text` etc. at hundreds of view-side
/// call sites. PaletteKit owns it (the View layer no longer defines it).
/// Seeded from the `terminal` preset.
@MainActor
public var pal: ResolvedPalette = resolve(.terminal)

/// Replace the current theme. Call once at startup (and on `--reload`)
/// after resolving the chosen spec.
@MainActor
public func setPalette(_ p: ResolvedPalette) { pal = p }

/// Convenience: resolve a name + optional bg override and install it.
@MainActor
public func setPalette(named name: String, bgOverride: HexColor? = nil) {
    pal = resolve(paletteFor(name), bgOverride: bgOverride)
}

// MARK: - Fonts

/// Theme-aware font factory honoring `pal.font`. `.menu` is the system
/// UI font (matches native menus); `.mono` / `.rounded` / `.system` as
/// in facet.
@MainActor
public func uiFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    switch pal.font {
    case .mono:
        return .monospacedSystemFont(ofSize: size, weight: weight)
    case .rounded:
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: d, size: size) ?? base
        }
        return base
    case .menu:
        // The system UI font at the requested size; menus use the
        // standard system font, so this is `.systemFont` with the
        // menu-appropriate weight default applied by the caller.
        return NSFont.menuFont(ofSize: size)
    case .system:
        return .systemFont(ofSize: size, weight: weight)
    }
}

// MARK: - blendThrough (re-exported for AppKit callers)

/// Smoothly loop through `colors` by `phase` (0…1), blending
/// consecutive entries. The NSColor form of the shared cycle primitive
/// (the pure UInt32 form lives in `Effects`). Used by border / theme
/// cycles that already hold `NSColor`s.
@MainActor
public func blendThrough(_ colors: [NSColor], at phase: CGFloat) -> NSColor {
    let n = colors.count
    guard n > 1 else { return colors.first ?? .white }
    let p = phase - floor(phase)
    let scaled = p * CGFloat(n)
    let i = Int(scaled) % n
    let t = scaled - floor(scaled)
    return colors[i].blended(withFraction: t, of: colors[(i + 1) % n]) ?? colors[i]
}
