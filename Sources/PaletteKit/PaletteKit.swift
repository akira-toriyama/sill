// PaletteKit — the AppKit resolver. The ONLY sill target that imports
// AppKit. Turns a pure `ThemeSpec` into a `ResolvedPalette` of
// `NSColor`s, applying the DERIVE RECIPE for any field the spec left
// nil. Also provides the `@MainActor` module-level `pal` var (facet's
// invariant), the `uiFont` factory (incl. `.menu`), the derive
// accessors (`tertiary` field, `ink`, `onPrimary`), and `blendThrough`.
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
/// background for vibrancy). This is what views read via `pal`.
/// `@MainActor` because `NSColor` isn't `Sendable` under Swift 6 strict
/// concurrency.
@MainActor
public struct ResolvedPalette {
    public let background: NSColor?
    public let foreground: NSColor
    public let muted: NSColor
    /// Third (least-emphasis) text tier. Resolved from `spec.tertiary`,
    /// else derived (`foreground @ 0.55`, or `.tertiaryLabelColor` for
    /// OS-ink themes). A promoted first-class field — read it as
    /// `pal.tertiary` like the other roles.
    public let tertiary: NSColor
    public let primary: NSColor
    public let secondary: NSColor
    public let border: NSColor
    public let hover: NSColor
    public let selection: NSColor
    public let error: NSColor
    public let font: FontKind
    /// `backgroundAlpha` from the spec (nil ⇒ opaque) — the panel/pill knob.
    public let backgroundAlpha: CGFloat?
    /// Rendering hints for the `system` preset (vibrancy). Not part of
    /// the pure spec — pure logic shouldn't know about NSVisualEffect.
    public let vibrancyMaterial: NSVisualEffectView.Material?
    public let forceDarkAqua: Bool

    public init(
        background: NSColor?, foreground: NSColor, muted: NSColor, tertiary: NSColor,
        primary: NSColor, secondary: NSColor, border: NSColor,
        hover: NSColor, selection: NSColor, error: NSColor,
        font: FontKind, backgroundAlpha: CGFloat?,
        vibrancyMaterial: NSVisualEffectView.Material?,
        forceDarkAqua: Bool
    ) {
        self.background = background; self.foreground = foreground; self.muted = muted
        self.tertiary = tertiary
        self.primary = primary; self.secondary = secondary
        self.border = border; self.hover = hover
        self.selection = selection; self.error = error; self.font = font
        self.backgroundAlpha = backgroundAlpha
        self.vibrancyMaterial = vibrancyMaterial
        self.forceDarkAqua = forceDarkAqua
    }
}

// MARK: - Derived accessors (shared defaults; apps override per surface)

public extension ResolvedPalette {
    /// Which base ink an `ink(_:of:)` tint is rooted on.
    enum InkRoot { case foreground, muted, primary }

    /// A named alpha tier for the dominant per-surface-tint pattern. A
    /// SHARED DEFAULT, not a complete solution: an app with finer needs
    /// (facet's ~21 distinct stops) still tints at the draw site; `ink`
    /// only de-dups the common 4-tier case.
    enum InkTier {
        case faint, subtle, wash, strong
        public var alpha: CGFloat {
            switch self {
            case .faint:  return 0.06
            case .subtle: return 0.16
            case .wash:   return 0.30
            case .strong: return 0.55
            }
        }
    }

    /// An alpha-over tint of a base ink at a named tier. Alpha-over ONLY —
    /// base+delta (perch) and blend-toward-white (facet) stay app-local.
    func ink(_ tier: InkTier, of root: InkRoot = .foreground) -> NSColor {
        let base: NSColor
        switch root {
        case .foreground: base = foreground
        case .muted:      base = muted
        case .primary:    base = primary
        }
        return base.withAlphaComponent(tier.alpha)
    }

    /// Foreground (black/white) that best contrasts the OPAQUE primary —
    /// for text / icons drawn ON a primary fill. Rooted on the opaque
    /// primary, NOT the selection wash. Opt-in.
    func onPrimary(_ alpha: CGFloat = 1) -> NSColor {
        bestContrast(on: primary).withAlphaComponent(alpha)
    }

    /// The hairline-stroke axis of `onPrimary` (the contrast ink @ 0.4) —
    /// for outlines on a primary fill. A second, distinct axis from the
    /// text foreground.
    var onPrimaryStroke: NSColor { onPrimary(0.4) }

    /// Foreground (black/white) that best contrasts the OPAQUE secondary —
    /// for text / icons drawn ON a secondary fill (e.g. a secondary FAB).
    /// The secondary mirror of `onPrimary`: rooted on the opaque
    /// secondary, NOT a wash. Opt-in.
    func onSecondary(_ alpha: CGFloat = 1) -> NSColor {
        bestContrast(on: secondary).withAlphaComponent(alpha)
    }

    /// The hairline-stroke axis of `onSecondary` (the contrast ink @ 0.4) —
    /// for outlines on a secondary fill. Mirrors `onPrimaryStroke`.
    var onSecondaryStroke: NSColor { onSecondary(0.4) }

    /// Black or white, whichever best contrasts `c` used as a fill. Reuses
    /// the pure `prefersBlackForeground` (WCAG contrast-ratio crossover) so
    /// the resolved-`NSColor` path (incl. OS controlAccent, whose hex the
    /// pure layer can't see) can't drift from a Palette-only consumer.
    /// Public so widgets drawing ink on an arbitrary fill (a contained
    /// Button, an error Chip, a Tooltip) share this single crossover
    /// instead of each re-deriving it.
    func bestContrast(on c: NSColor) -> NSColor {
        let s = c.usingColorSpace(.sRGB) ?? c
        let L = wcagRelativeLuminance(r: Double(s.redComponent),
                                      g: Double(s.greenComponent),
                                      b: Double(s.blueComponent))
        return prefersBlackForeground(fillRelLuminance: L) ? .black : .white
    }
}

// MARK: - Control role

/// The role a themed control is tinted by — the single vocabulary the widgets
/// map their own public `Role` enums onto, so the role → colour selection lives
/// in ONE place (`color(for:)`) instead of a byte-identical switch per widget.
public enum ControlRole: Sendable, Hashable, CaseIterable {
    case neutral, primary, secondary, error
}

@MainActor
public extension ResolvedPalette {
    /// The fill for a control role: `neutral` ⇒ `foreground`, else the matching
    /// role field. A widget keeps its own (possibly narrower / wider) public
    /// `Role` enum and translates to this; non-role arms (surface, transparent,
    /// custom, washes) stay at the call site.
    func color(for role: ControlRole) -> NSColor {
        switch role {
        case .neutral:   return foreground
        case .primary:   return primary
        case .secondary: return secondary
        case .error:     return error
        }
    }
}

// MARK: - Derive recipe

/// Resolve a pure `ThemeSpec` into `NSColor`s, deriving any nil field.
///
/// DERIVE RECIPE (the dark editor presets author only
/// background/foreground/muted/primary; the trio derives):
///   * primary   → spec.primary, OR `controlAccentColor` when the
///     sentinel (0) is set (the `system` preset).
///   * secondary → spec.secondary if set, else the primary's hue rotated
///     +180° (complement) at the primary's saturation/brightness.
///   * neutral base = white on a dark background, black on a light
///     background (the `isLight` branch). `nil` background (vibrancy) is
///     treated as dark.
///   * border    → override, else neutral@0.10.
///   * hover     → override, else neutral@0.05.
///   * selection → override, else primary@0.18.
///   * tertiary  → spec.tertiary if set, else `.tertiaryLabelColor`
///     (OS-ink themes) / foreground@0.55 — a stored `pal.tertiary` field.
///
/// `system` is special-cased: background nil, dynamic system colors for
/// foreground/muted/border/hover/selection, vibrancy + dark-aqua hints
/// emitted.
///
/// `bgOverride` lets an app substitute its own panel/pill background
/// (perch's translucent pill vs facet's opaque panel) while keeping the
/// canonical primary/foreground/muted/font. `material` / `forceDark`
/// override the system-preset rendering hints when supplied.
@MainActor
public func resolve(
    _ spec: ThemeSpec,
    bgOverride: HexColor? = nil,
    material: NSVisualEffectView.Material? = nil,
    forceDark: Bool? = nil
) -> ResolvedPalette {

    // --- OS-dynamic inks: `.vibrancy` (no fill) or `.systemDynamic`
    //     (concrete fill, live OS inks). Gate keys on backgroundMode, not
    //     on `background == nil`, so a concrete-bg-with-system-inks theme
    //     is now expressible (the case the old gate dropped).
    if spec.usesSystemColors {
        // vibrancy: no opaque fill unless overridden. systemDynamic:
        // the spec's concrete background.
        let bgHex = bgOverride ?? (spec.backgroundMode == .systemDynamic ? spec.background : nil)
        let tertiaryNS = spec.tertiary.map { NSColor($0) } ?? .tertiaryLabelColor
        return ResolvedPalette(
            background: bgHex.map { NSColor($0) },
            foreground: .labelColor,
            muted: .secondaryLabelColor,
            tertiary: tertiaryNS,
            primary: .controlAccentColor,
            secondary: .systemPurple,
            border: NSColor.labelColor.withAlphaComponent(0.22),
            hover: NSColor.secondaryLabelColor.withAlphaComponent(0.12),
            selection: NSColor.controlAccentColor.withAlphaComponent(0.18),
            error: NSColor(spec.error),
            font: spec.font,
            backgroundAlpha: spec.backgroundAlpha.map { CGFloat($0) },
            // Vibrancy needs a material; a concrete systemDynamic fill
            // does not (no NSVisualEffectView). Don't start emitting a
            // material for fixed/systemDynamic — the call site owns it.
            // Default `.menu` — the native CONTEXT-MENU material, so the
            // `system` theme reads as a real macOS menu (matches its
            // `font: .menu`): crisp + legible, light by day / dark by
            // night. A caller can override via `material:`.
            vibrancyMaterial: spec.backgroundMode == .vibrancy ? (material ?? .menu) : material,
            forceDarkAqua: forceDark ?? false)
    }

    // --- .fixed: authored static inks + derive recipe ---
    let primaryNS: NSColor = spec.usesSystemPrimary
        ? .controlAccentColor
        : NSColor(spec.primary)

    let secondaryNS: NSColor = spec.secondary.map { NSColor($0) }
        ?? complement(of: primaryNS)

    // Neutral base for derived border / hover. White on dark, black on
    // light. nil background counts as dark (vibrancy overlay reads dark).
    let neutral: NSColor = spec.isLight ? .black : .white

    let borderNS: NSColor = spec.border.map { NSColor($0) }
        ?? neutral.withAlphaComponent(0.10)
    let hoverNS: NSColor = spec.hover.map { NSColor($0) }
        ?? neutral.withAlphaComponent(0.05)
    let selectionNS: NSColor = spec.selection.map { NSColor($0) }
        ?? primaryNS.withAlphaComponent(0.18)
    let tertiaryNS: NSColor = spec.tertiary.map { NSColor($0) }
        ?? NSColor(spec.foreground).withAlphaComponent(0.55)

    let bgHex = bgOverride ?? spec.background
    let bgNS: NSColor? = bgHex.map { NSColor($0) }

    return ResolvedPalette(
        background: bgNS,
        foreground: NSColor(spec.foreground),
        muted: NSColor(spec.muted),
        tertiary: tertiaryNS,
        primary: primaryNS,
        secondary: secondaryNS,
        border: borderNS,
        hover: hoverNS,
        selection: selectionNS,
        error: NSColor(spec.error),
        font: spec.font,
        backgroundAlpha: spec.backgroundAlpha.map { CGFloat($0) },
        vibrancyMaterial: material,
        forceDarkAqua: forceDark ?? false)
}

/// Complement of a color: hue + 0.5 (wrapping), same saturation /
/// brightness. Used when a spec omits `secondary`.
@MainActor
private func complement(of c: NSColor) -> NSColor {
    let s = c.usingColorSpace(.sRGB) ?? c
    var h: CGFloat = 0, sat: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
    s.getHue(&h, saturation: &sat, brightness: &br, alpha: &a)
    // Greyscale primary (sat≈0, e.g. monochrome) has no meaningful
    // complement — return a slightly lighter grey instead of a hue flip.
    if sat < 0.05 {
        return NSColor(white: min(1, br * 0.7 + 0.15), alpha: a)
    }
    return NSColor(hue: (h + 0.5).truncatingRemainder(dividingBy: 1),
                   saturation: sat, brightness: br, alpha: a)
}

// MARK: - Module-level `pal`

/// Current resolved theme. facet's invariant: a short `@MainActor`
/// module-level var read as `pal.foreground` etc. at hundreds of
/// view-side call sites. PaletteKit owns it (the View layer no longer
/// defines it). Seeded from the `terminal` preset.
@MainActor
public var pal: ResolvedPalette = resolve(.terminal)

/// Replace the current theme. Call once at startup (and on `--reload`)
/// after resolving the chosen spec.
@MainActor
public func setPalette(_ p: ResolvedPalette) { pal = p }

/// Convenience: resolve a name + optional background override and install it.
@MainActor
public func setPalette(named name: String, bgOverride: HexColor? = nil) {
    pal = resolve(paletteFor(name), bgOverride: bgOverride)
}

// MARK: - Fonts

/// Theme-aware font factory honoring the module-level `pal.font`. A thin
/// shim over `ResolvedPalette.uiFont(_:_:)` kept for `pal`-based callers;
/// widgets resolve against their own `palette` via that extension.
@MainActor
public func uiFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    pal.uiFont(size, weight)
}

// MARK: - Type scale resolution

public extension TypeWeight {
    /// The AppKit weight this tier paints at.
    var nsWeight: NSFont.Weight {
        switch self {
        case .regular:  return .regular
        case .medium:   return .medium
        case .semibold: return .semibold
        }
    }
}

public extension ResolvedPalette {
    /// Theme-aware font for an explicit point size + weight, honoring the
    /// resolved `FontKind`: `.mono`→monospaced, `.rounded`→rounded design,
    /// `.menu`→the native menu font (no weight variant), `.system`→system.
    ///
    /// This is the SINGLE font factory ThemeKit widgets use. It replaces
    /// ten per-widget `themedFont` helpers that branched only `.mono` vs
    /// system and SILENTLY DROPPED `.rounded`/`.menu` — so under the
    /// catalog's six rounded themes (and the menu preset) every widget had
    /// been rendering the wrong family.
    func uiFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        switch font {
        case .mono:
            return .monospacedSystemFont(ofSize: size, weight: weight)
        case .rounded:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            if let d = base.fontDescriptor.withDesign(.rounded) {
                return NSFont(descriptor: d, size: size) ?? base
            }
            return base
        case .menu:
            // The native menu font, which has no weight variant.
            return NSFont.menuFont(ofSize: size)
        case .system:
            return .systemFont(ofSize: size, weight: weight)
        }
    }

    /// Theme-aware font for a fixed `TypeRole` from sill's type scale: the
    /// size + weight come from the role's token, the family from the live
    /// `FontKind`.
    func uiFont(_ role: TypeRole) -> NSFont {
        uiFont(CGFloat(role.token.pt), role.token.weight.nsWeight)
    }
}

// MARK: - Elevation resolution

public extension ResolvedPalette {
    /// CALayer drop-shadow parameters for an `Elevation` level — the AppKit
    /// side of sill's elevation scale, the direct analogue of `uiFont(_ role:)`:
    /// the pure `Double` token lives in `Palette`, the platform-typed wrap
    /// lives here at the resolve boundary.
    ///
    /// Returns `(opacity, radius, offsetY)` ready for `layer.shadowOpacity` /
    /// `.shadowRadius` / `.shadowOffset` — the shadow COLOUR stays the widget's
    /// `NSColor.black.cgColor`, the kit's universal drop-shadow ink. `offsetY`
    /// is ALREADY NEGATED for sill's y-up (`isFlipped == false`) layer space,
    /// where a downward shadow sits at −y, so widgets stop hand-writing the
    /// minus. (Free of `self` today — attached to `ResolvedPalette`, not a
    /// free func, so a future depth-tinted shadow can read the palette.)
    func shadow(_ level: Elevation) -> (opacity: Float, radius: CGFloat, offsetY: CGFloat) {
        let t = level.token
        return (Float(t.opacity), CGFloat(t.blur), CGFloat(-t.dy))
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
