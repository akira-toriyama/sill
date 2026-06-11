// Palette — the pure, Sendable, AppKit-free theme layer.
//
// A `ThemeSpec` is a value-type description of a theme: hex colors as
// `UInt32` (0xRRGGBB), a `FontKind` enum, and OPTIONAL overrides of the
// derived trio (divider / hoverFill / selFill) + accent2. PaletteKit
// turns a `ThemeSpec` into resolved `NSColor`s with the derive recipe.
//
// This module imports nothing platform-specific, so a consumer that
// only wants the spec (CLI validation, tests, a non-AppKit renderer)
// links zero AppKit.
//
// IMPORTANT naming: the primary public type is `ThemeSpec`, NOT
// `Palette`. The module is named `Palette`; keeping the type distinct
// avoids the `Palette.Palette` / umbrella-typealias problem
// swift-collections hits with `DequeModule.Deque`.

import Foundation   // for `Double`, `floor`; NO AppKit / CoreGraphics.

// MARK: - Hex color

/// An sRGB color stored as `0xRRGGBB` plus an alpha in `0...1`. Pure
/// value type so the spec stays `Sendable` without AppKit. PaletteKit
/// materializes it to an `NSColor`.
public struct HexColor: Sendable, Hashable {
    /// `0xRRGGBB`. The high byte is ignored.
    public var rgb: UInt32
    /// `0...1`. Defaults to opaque.
    public var alpha: Double

    public init(_ rgb: UInt32, _ alpha: Double = 1) {
        self.rgb = rgb & 0xFF_FFFF
        self.alpha = alpha
    }

    public var r: Double { Double((rgb >> 16) & 0xFF) / 255 }
    public var g: Double { Double((rgb >> 8) & 0xFF) / 255 }
    public var b: Double { Double(rgb & 0xFF) / 255 }

    /// Perceived luminance (Rec. 601 weights), `0...1`. Drives the
    /// dark-vs-light branch of the derive recipe.
    public var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }

    /// A copy at a new alpha.
    public func withAlpha(_ a: Double) -> HexColor { HexColor(rgb, a) }
}

// MARK: - FontKind

/// Which font family a theme draws with. `.menu` is the system UI font
/// at the standard control size — used by the `system` preset so it
/// matches native menus.
public enum FontKind: Sendable, Hashable, CaseIterable {
    case system, mono, rounded, menu
}

// MARK: - BgMode

/// How a theme's background + base inks are sourced. Replaces the old
/// `bg == nil && usesSystemAccent` resolve gate with an explicit mode so
/// the real cases are distinct — and a case the old gate could not
/// express (concrete fill BUT live OS inks) becomes representable.
///
///   * `.vibrancy`      — no opaque fill (`bg == nil`); an
///     `NSVisualEffectView` shows through and the base inks come from the
///     OS (label / secondaryLabel / controlAccent). The `system` preset.
///   * `.fixed`         — a concrete authored `bg` with static authored
///     inks. Every editor preset (terminal / nord / dracula / …).
///   * `.systemDynamic` — a concrete authored `bg` BUT live OS inks
///     (label / controlAccent), non-adaptive. perch's translucent system
///     pill (a fixed dark fill whose accent tracks the OS) is the witness;
///     unexpressible under the `bg == nil` gate.
public enum BgMode: Sendable, Hashable, CaseIterable {
    case vibrancy, fixed, systemDynamic
}

// MARK: - System sentinels

/// `accent == systemAccentSentinel` (0) means "use the OS
/// `controlAccentColor`" — resolved in PaletteKit, kept out of the pure
/// spec. No real theme uses pure black as an accent, so 0 is safe as a
/// sentinel.
public let systemAccentSentinel: UInt32 = 0

/// Default error/destructive hue when a theme doesn't override it.
public let defaultErrorHex: UInt32 = 0xEF4444

// MARK: - ThemeSpec

/// One theme, described purely. Theme authors set the SIX required hues
/// (bg / text / dim / accent / error / font) plus optional knobs;
/// PaletteKit derives divider / hoverFill / selFill / accent2 / tertiary
/// from bg-luminance + accent unless the matching override is set.
///
/// `bg == nil` means "fall through to system vibrancy" (the `system`
/// preset). `accent == systemAccentSentinel` (0) means
/// "OS control-accent". `bgAlpha == nil` means opaque.
public struct ThemeSpec: Sendable, Hashable {
    /// `nil` = vibrancy fall-through (no opaque fill).
    public var bg: HexColor?
    public var text: HexColor
    public var dim: HexColor
    /// `rgb == systemAccentSentinel` (0) ⇒ OS control-accent.
    public var accent: HexColor
    /// Destructive / error hue.
    public var error: HexColor
    public var font: FontKind

    /// Optional secondary accent. `nil` ⇒ PaletteKit derives a
    /// complementary hue from `accent`.
    public var accent2: HexColor?
    /// Optional override of the derived divider.
    public var divider: HexColor?
    /// Optional override of the derived hover fill.
    public var hoverFill: HexColor?
    /// Optional override of the derived selection fill.
    public var selFill: HexColor?
    /// Optional panel-background alpha (`nil` ⇒ opaque). Lets perch's
    /// translucent pill and facet's opaque panel share one spec.
    public var bgAlpha: Double?

    /// How `bg` + base inks are sourced. Defaults from `bg`: `.vibrancy`
    /// when `bg == nil`, else `.fixed`. Set `.systemDynamic` for a
    /// concrete fill that still wants live OS inks (perch's system pill).
    public var bgMode: BgMode
    /// Optional third text tier (least-emphasis captions). `nil` ⇒
    /// PaletteKit derives `text @ 0.55` (or `.tertiaryLabelColor` when the
    /// inks are OS-dynamic).
    public var tertiary: HexColor?

    public init(
        bg: HexColor?,
        text: HexColor,
        dim: HexColor,
        accent: HexColor,
        font: FontKind,
        error: HexColor = HexColor(defaultErrorHex),
        accent2: HexColor? = nil,
        divider: HexColor? = nil,
        hoverFill: HexColor? = nil,
        selFill: HexColor? = nil,
        bgAlpha: Double? = nil,
        bgMode: BgMode? = nil,
        tertiary: HexColor? = nil
    ) {
        self.bg = bg
        self.text = text
        self.dim = dim
        self.accent = accent
        self.font = font
        self.error = error
        self.accent2 = accent2
        self.divider = divider
        self.hoverFill = hoverFill
        self.selFill = selFill
        self.bgAlpha = bgAlpha
        self.bgMode = bgMode ?? (bg == nil ? .vibrancy : .fixed)
        self.tertiary = tertiary
    }

    /// True when `accent` is the OS-control-accent sentinel.
    public var usesSystemAccent: Bool { accent.rgb == systemAccentSentinel }
    /// True when base inks should come from the OS rather than the spec
    /// (`.vibrancy` or `.systemDynamic`). Drives PaletteKit's resolve gate.
    public var usesSystemColors: Bool { bgMode != .fixed }
    /// True when `bg` is treated as light by the derive recipe.
    /// `nil` bg (vibrancy) is treated as dark.
    public var isLight: Bool { (bg?.luminance ?? 0) > 0.5 }
}

// MARK: - Canonical presets
//
// Ported from facet's 22 presets with facet-AUTHORITATIVE hex for
// accent / text / dim / font. LEAN: a preset only stores divider /
// hoverFill / selFill / accent2 when it DEVIATES from the derive recipe
// (light themes, monochrome, system, rainbow). The 16 dark editor
// presets store NONE of the trio — PaletteKit derives the exact facet
// values (white@0.10 / white@0.05 / accent@0.18) from their dark bg.
//
// `system` is special: bg nil (vibrancy), accent sentinel 0, font menu.

extension ThemeSpec {

    // --- Dark editor presets (recipe-derived trio) -------------------

    /// Tokyo-Night-ish default. Green primary, purple secondary, mono.
    public static let terminal = ThemeSpec(
        bg: HexColor(0x0E0F14), text: HexColor(0xC0CAF5),
        dim: HexColor(0x6B7394), accent: HexColor(0x9ECE6A), font: .mono,
        accent2: HexColor(0xBB9AF7))

    /// Nord — cool polar-night blue-grey. Frost-cyan / aurora-sand.
    public static let nord = ThemeSpec(
        bg: HexColor(0x2E3440), text: HexColor(0xECEFF4),
        dim: HexColor(0x7B88A1), accent: HexColor(0x88C0D0), font: .mono,
        accent2: HexColor(0xEBCB8B))

    /// Dracula — vivid dark. Purple / green.
    public static let dracula = ThemeSpec(
        bg: HexColor(0x282A36), text: HexColor(0xF8F8F2),
        dim: HexColor(0x6272A4), accent: HexColor(0xBD93F9), font: .mono,
        accent2: HexColor(0x50FA7B))

    /// Gruvbox — retro warm dark. Orange / aqua.
    public static let gruvbox = ThemeSpec(
        bg: HexColor(0x282828), text: HexColor(0xEBDBB2),
        dim: HexColor(0x928374), accent: HexColor(0xFE8019), font: .mono,
        accent2: HexColor(0x8EC07C))

    /// Catppuccin Mocha — soft pastel dark. Mauve / green.
    public static let catppuccin = ThemeSpec(
        bg: HexColor(0x1E1E2E), text: HexColor(0xCDD6F4),
        dim: HexColor(0x7F849C), accent: HexColor(0xCBA6F7), font: .mono,
        accent2: HexColor(0xA6E3A1))

    /// Rosé Pine — muted aubergine dark. Iris / rose.
    public static let rosepine = ThemeSpec(
        bg: HexColor(0x191724), text: HexColor(0xE0DEF4),
        dim: HexColor(0x908CAA), accent: HexColor(0xC4A7E7), font: .mono,
        accent2: HexColor(0xEBBCBA))

    /// Everforest — soft forest dark. Green / orange.
    public static let everforest = ThemeSpec(
        bg: HexColor(0x2D353B), text: HexColor(0xD3C6AA),
        dim: HexColor(0x859289), accent: HexColor(0xA7C080), font: .mono,
        accent2: HexColor(0xE69875))

    /// Solarized Dark — classic teal-base. Blue / orange.
    public static let solarized = ThemeSpec(
        bg: HexColor(0x002B36), text: HexColor(0x93A1A1),
        dim: HexColor(0x586E75), accent: HexColor(0x268BD2), font: .mono,
        accent2: HexColor(0xCB4B16))

    /// One Dark — Atom's signature dark. Blue / yellow.
    public static let onedark = ThemeSpec(
        bg: HexColor(0x282C34), text: HexColor(0xABB2BF),
        dim: HexColor(0x5C6370), accent: HexColor(0x61AFEF), font: .mono,
        accent2: HexColor(0xE5C07B))

    /// Monokai — high-energy dark. Lime / magenta.
    public static let monokai = ThemeSpec(
        bg: HexColor(0x272822), text: HexColor(0xF8F8F2),
        dim: HexColor(0x75715E), accent: HexColor(0xA6E22E), font: .mono,
        accent2: HexColor(0xF92672))

    /// Hacker — green-on-black terminal. Neon-green / amber.
    public static let hacker = ThemeSpec(
        bg: HexColor(0x0A0F0A), text: HexColor(0xCFE0CF),
        dim: HexColor(0x5F715F), accent: HexColor(0x33FF66), font: .mono,
        accent2: HexColor(0xFFC857))

    /// モノトーン — soft graphite greyscale, system font.
    public static let monotone = ThemeSpec(
        bg: HexColor(0x1E1E1E), text: HexColor(0xC8C8C8),
        dim: HexColor(0x7A7A7A), accent: HexColor(0xB0B0B0), font: .system,
        accent2: HexColor(0x888888))

    /// Neon — electric cyan on blue-black; hot-magenta secondary.
    public static let neon = ThemeSpec(
        bg: HexColor(0x0A0A14), text: HexColor(0xC0CAF5),
        dim: HexColor(0x6B7394), accent: HexColor(0x00E5FF), font: .mono,
        accent2: HexColor(0xFF2EC4))

    /// Cyber — aqua/teal on teal-black; hot-pink secondary.
    public static let cyber = ThemeSpec(
        bg: HexColor(0x001410), text: HexColor(0xC8F0E4),
        dim: HexColor(0x5F8076), accent: HexColor(0x00FFD0), font: .mono,
        accent2: HexColor(0xFF3DCE))

    /// Vapor — synthwave pink on purple-black; electric-cyan secondary.
    public static let vapor = ThemeSpec(
        bg: HexColor(0x1A0E26), text: HexColor(0xEAD9F5),
        dim: HexColor(0x8A6FA6), accent: HexColor(0xFF6AD5), font: .mono,
        accent2: HexColor(0x05D9E8))

    // --- Light / special presets (explicit trio) ---------------------

    /// Soft pastel cute. Pink primary, peach secondary, accent-tinted
    /// neutrals, rounded. Light ⇒ trio is explicit (recipe would derive
    /// dark-theme white-alpha, wrong on a light bg).
    public static let cute = ThemeSpec(
        bg: HexColor(0xFFF1F6), text: HexColor(0x6B5566),
        dim: HexColor(0xB892A6), accent: HexColor(0xF2789F), font: .rounded,
        accent2: HexColor(0xFFB48F),
        divider: HexColor(0xF2789F, 0.22),
        hoverFill: HexColor(0xF2789F, 0.10),
        selFill: HexColor(0xF2789F, 0.20))

    /// Paper — clean daytime light. Blue / amber, black-alpha neutrals.
    public static let paper = ThemeSpec(
        bg: HexColor(0xFAFAF8), text: HexColor(0x1C1C1E),
        dim: HexColor(0x8A8A8E), accent: HexColor(0x3B82F6), font: .system,
        accent2: HexColor(0xF59E0B),
        divider: HexColor(0x000000, 0.10),
        hoverFill: HexColor(0x000000, 0.04),
        selFill: HexColor(0x3B82F6, 0.14))

    /// Kawaii — candy lavender light. Purple / mint, rounded.
    public static let kawaii = ThemeSpec(
        bg: HexColor(0xFAF0FF), text: HexColor(0x5E5470),
        dim: HexColor(0xA99BC0), accent: HexColor(0xB661E8), font: .rounded,
        accent2: HexColor(0x7DD9C0),
        divider: HexColor(0xB661E8, 0.20),
        hoverFill: HexColor(0xB661E8, 0.10),
        selFill: HexColor(0xB661E8, 0.18))

    /// 白黒 — stark black-on-white, mono. Monochrome ⇒ explicit trio.
    public static let monoLight = ThemeSpec(
        bg: HexColor(0xFFFFFF), text: HexColor(0x111111),
        dim: HexColor(0x8A8A8A), accent: HexColor(0x000000), font: .mono,
        accent2: HexColor(0x555555),
        divider: HexColor(0x000000, 0.14),
        hoverFill: HexColor(0x000000, 0.05),
        selFill: HexColor(0x000000, 0.10))

    /// 黒白 — stark white-on-black (OLED), mono. Monochrome exception:
    /// selFill is white@0.16 (not accent@0.18), so explicit.
    public static let monoDark = ThemeSpec(
        bg: HexColor(0x000000), text: HexColor(0xF5F5F5),
        dim: HexColor(0x777777), accent: HexColor(0xFFFFFF), font: .mono,
        accent2: HexColor(0xAAAAAA),
        divider: HexColor(0xFFFFFF, 0.14),
        hoverFill: HexColor(0xFFFFFF, 0.06),
        selFill: HexColor(0xFFFFFF, 0.16))

    /// Rainbow — loud max-saturation set. White on near-black violet;
    /// high-contrast neutrals (white@0.14 / 0.07) + selFill accent@0.22,
    /// all of which deviate from the recipe ⇒ explicit.
    public static let rainbow = ThemeSpec(
        bg: HexColor(0x0D0B14), text: HexColor(0xFFFFFF),
        dim: HexColor(0x8C84B0), accent: HexColor(0xFF2D95), font: .rounded,
        accent2: HexColor(0x2BE0FF),
        divider: HexColor(0xFFFFFF, 0.14),
        hoverFill: HexColor(0xFFFFFF, 0.07),
        selFill: HexColor(0xFF2D95, 0.22))

    /// Native vibrancy + dynamic system colors. bg nil (vibrancy),
    /// accent sentinel 0 (OS control-accent), font menu. The trio is
    /// resolved against system colors in PaletteKit (it can't be a hex
    /// here), so it stays nil and PaletteKit special-cases `system`.
    public static let system = ThemeSpec(
        bg: nil, text: HexColor(0x000000), dim: HexColor(0x000000),
        accent: HexColor(systemAccentSentinel), font: .menu)

    /// Chomp — arcade Pac-Man look (pellet yellow on a black maze, neon-
    /// blue walls, ghost-red error). A CROSS-APP playful theme: facet's
    /// tree, halo's border ring, and wand's gesture trail all adopt
    /// `theme = chomp`, each drawing its OWN signature motion over this
    /// shared palette + the matching `EffectSpec.chomp` animated border
    /// (the motion drawing stays app-side; sill owns identity + colour).
    /// Light/dark: a dark theme, so
    /// hover derives normally; divider/selFill are explicit (wall-blue +
    /// pellet) because the arcade identity needs those exact hues.
    public static let chomp = ThemeSpec(
        bg: HexColor(0x000000), text: HexColor(0xFFEA00),
        dim: HexColor(0xB39C1A), accent: HexColor(0xFFEA00), font: .mono,
        error: HexColor(0xFF0000),
        accent2: HexColor(0x2121FF),
        divider: HexColor(0x2121FF, 0.55),
        selFill: HexColor(0xFFEA00, 0.18))
}

// MARK: - Name resolution

/// Canonical theme names accepted by `--theme=`. Single source of truth
/// so a CLI can reject typos. Includes the `random` meta-name.
public let canonicalThemeNames: [String] = [
    "terminal", "cute", "system",
    "nord", "dracula", "gruvbox", "catppuccin", "rosepine",
    "everforest", "solarized", "onedark", "monokai", "hacker", "paper",
    "mono-light", "mono-dark", "monotone",
    "neon", "cyber", "vapor", "kawaii", "rainbow",
    "chomp",
    "random",
]

/// Map a raw `--theme=…` value to a `ThemeSpec`. Case-insensitive;
/// unknown names fall through to `terminal`. `random` picks a concrete
/// non-system theme each call (matches facet). Pure — no AppKit.
public func paletteFor(_ raw: String) -> ThemeSpec {
    switch raw.lowercased() {
    case "cute":       return .cute
    case "system":     return .system
    case "nord":       return .nord
    case "dracula":    return .dracula
    case "gruvbox":    return .gruvbox
    case "catppuccin": return .catppuccin
    case "rosepine":   return .rosepine
    case "everforest": return .everforest
    case "solarized":  return .solarized
    case "onedark":    return .onedark
    case "monokai":    return .monokai
    case "hacker":     return .hacker
    case "neon":       return .neon
    case "cyber":      return .cyber
    case "vapor":      return .vapor
    case "kawaii":     return .kawaii
    case "rainbow":    return .rainbow
    case "chomp":      return .chomp
    case "paper":      return .paper
    case "mono-light": return .monoLight
    case "mono-dark":  return .monoDark
    case "monotone":   return .monotone
    case "random":
        let pool = canonicalThemeNames.filter { $0 != "random" && $0 != "system" }
        return paletteFor(pool.randomElement() ?? "terminal")
    default:           return .terminal
    }
}

// MARK: - Contrast (shared value logic, pure)

/// Luminance at/above which a fill reads as "light" and wants a DARK
/// foreground. Single source so PaletteKit's NSColor `onAccent` and a
/// pure (Palette-only) consumer like perch can't drift apart.
public let lightFillLuminanceThreshold: Double = 0.6

public extension HexColor {
    /// Black or white — whichever best contrasts THIS color used as a
    /// fill. The pure half of `onAccent`; PaletteKit reuses the same
    /// threshold for the resolved-`NSColor` (incl. OS controlAccent) case.
    var bestForeground: HexColor {
        luminance >= lightFillLuminanceThreshold ? HexColor(0x000000) : HexColor(0xFFFFFF)
    }
}

// MARK: - Color-token parsing (pure, opt-in)

/// Parse a config-edge color token into a `HexColor`, or `nil` if it
/// isn't a recognized literal. Accepts a small named-color set plus
/// `#rgb` / `#rrggbb` / `#rrggbbaa` (the leading `#` optional). Opt-in:
/// an app wanting a stricter grammar (halo's 6-digit-only) keeps its own
/// parser; this lets wand dedup its token grammar. Semantic tokens like
/// `accent` / `system` are NOT handled here — they are app-level
/// sentinels, not literal colors.
public func parseColorToken(_ raw: String) -> HexColor? {
    let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
    guard !s.isEmpty else { return nil }

    let named: [String: UInt32] = [
        "black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000,
        "green": 0x00FF00, "blue": 0x0000FF, "yellow": 0xFFFF00,
        "orange": 0xFFA500, "purple": 0x800080, "pink": 0xFFC0CB,
        "cyan": 0x00FFFF, "magenta": 0xFF00FF,
        "gray": 0x808080, "grey": 0x808080,
    ]
    if let rgb = named[s] { return HexColor(rgb) }

    var hex = s
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard !hex.isEmpty, hex.allSatisfy({ $0.isHexDigit }) else { return nil }

    switch hex.count {
    case 3:   // #rgb → #rrggbb
        let c = Array(hex)
        guard let v = UInt32(String([c[0], c[0], c[1], c[1], c[2], c[2]]), radix: 16)
        else { return nil }
        return HexColor(v)
    case 6:
        guard let v = UInt32(hex, radix: 16) else { return nil }
        return HexColor(v)
    case 8:   // #rrggbbaa
        guard let v = UInt32(hex, radix: 16) else { return nil }
        return HexColor((v >> 8) & 0xFF_FFFF, Double(v & 0xFF) / 255)
    default:
        return nil
    }
}

// MARK: - Pill alpha suggestion (pure, opt-in)

/// A suggested translucent-pill background alpha for a theme of the given
/// `bg` luminance — darker themes get a more opaque pill. Opt-in: perch
/// MAY call this instead of hand-maintaining its per-preset table; it is
/// NOT applied by the derive recipe (a nil `bgAlpha` still means opaque).
public func suggestedPillAlpha(luminance: Double) -> Double {
    let a = 0.92 - luminance * 0.55      // dark ≈ 0.92 … light ≈ 0.37
    return min(0.92, max(0.30, a))
}
