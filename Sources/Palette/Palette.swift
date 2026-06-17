// Palette — the pure, Sendable, AppKit-free theme layer.
//
// A `ThemeSpec` is a value-type description of a theme: hex colors as
// `UInt32` (0xRRGGBB), a `FontKind` enum, and OPTIONAL overrides of the
// derived trio (border / hover / selection) + secondary. PaletteKit
// turns a `ThemeSpec` into resolved `NSColor`s with the derive recipe.
//
// Role names follow a Tailwind-style semantic vocabulary
// (background / foreground / muted / primary / secondary / …) so the
// shared theme contract reads the same across the app family.
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

// MARK: - BackgroundMode

/// How a theme's background + base inks are sourced. Replaces the old
/// `background == nil && usesSystemPrimary` resolve gate with an explicit
/// mode so the real cases are distinct — and a case the old gate could
/// not express (concrete fill BUT live OS inks) becomes representable.
///
///   * `.vibrancy`      — no opaque fill (`background == nil`); an
///     `NSVisualEffectView` shows through and the base inks come from the
///     OS (label / secondaryLabel / controlAccent). The `system` preset.
///   * `.fixed`         — a concrete authored `background` with static
///     authored inks. Every editor preset (terminal / dracula / …).
///   * `.systemDynamic` — a concrete authored `background` BUT live OS
///     inks (label / controlAccent), non-adaptive. perch's translucent
///     system pill (a fixed dark fill whose accent tracks the OS) is the
///     witness; unexpressible under the `background == nil` gate.
public enum BackgroundMode: Sendable, Hashable, CaseIterable {
    case vibrancy, fixed, systemDynamic
}

// MARK: - System sentinels

/// `primary == systemPrimarySentinel` (0) means "use the OS
/// `controlAccentColor`" — resolved in PaletteKit, kept out of the pure
/// spec. No real theme uses pure black as a primary accent, so 0 is safe
/// as a sentinel.
public let systemPrimarySentinel: UInt32 = 0

/// Default error/destructive hue when a theme doesn't override it.
public let defaultErrorHex: UInt32 = 0xEF4444

// MARK: - ThemeSpec

/// One theme, described purely. Theme authors set the FOUR required hues
/// (background / foreground / muted / primary) + font plus optional
/// knobs; PaletteKit derives border / hover / selection / secondary /
/// tertiary from background-luminance + primary unless the matching
/// override is set.
///
/// `background == nil` means "fall through to system vibrancy" (the
/// `system` preset). `primary == systemPrimarySentinel` (0) means
/// "OS control-accent". `backgroundAlpha == nil` means opaque.
public struct ThemeSpec: Sendable, Hashable {
    /// `nil` = vibrancy fall-through (no opaque fill).
    public var background: HexColor?
    /// Primary text ink.
    public var foreground: HexColor
    /// Secondary text / comments / line numbers.
    public var muted: HexColor
    /// Signature accent. `rgb == systemPrimarySentinel` (0) ⇒ OS control-accent.
    public var primary: HexColor
    /// Destructive / error hue.
    public var error: HexColor
    public var font: FontKind

    /// Optional secondary accent. `nil` ⇒ PaletteKit derives a
    /// complementary hue from `primary`.
    public var secondary: HexColor?
    /// Optional override of the derived divider/hairline.
    public var border: HexColor?
    /// Optional override of the derived hover fill.
    public var hover: HexColor?
    /// Optional override of the derived selection fill.
    public var selection: HexColor?
    /// Optional panel-background alpha (`nil` ⇒ opaque). Lets perch's
    /// translucent pill and facet's opaque panel share one spec.
    public var backgroundAlpha: Double?

    /// How `background` + base inks are sourced. Defaults from
    /// `background`: `.vibrancy` when nil, else `.fixed`. Set
    /// `.systemDynamic` for a concrete fill that still wants live OS inks
    /// (perch's system pill).
    public var backgroundMode: BackgroundMode
    /// Optional third text tier (least-emphasis captions). `nil` ⇒
    /// PaletteKit derives `foreground @ 0.55` (or `.tertiaryLabelColor`
    /// when the inks are OS-dynamic).
    public var tertiary: HexColor?

    public init(
        background: HexColor?,
        foreground: HexColor,
        muted: HexColor,
        primary: HexColor,
        font: FontKind,
        error: HexColor = HexColor(defaultErrorHex),
        secondary: HexColor? = nil,
        border: HexColor? = nil,
        hover: HexColor? = nil,
        selection: HexColor? = nil,
        backgroundAlpha: Double? = nil,
        backgroundMode: BackgroundMode? = nil,
        tertiary: HexColor? = nil
    ) {
        self.background = background
        self.foreground = foreground
        self.muted = muted
        self.primary = primary
        self.font = font
        self.error = error
        self.secondary = secondary
        self.border = border
        self.hover = hover
        self.selection = selection
        self.backgroundAlpha = backgroundAlpha
        self.backgroundMode = backgroundMode ?? (background == nil ? .vibrancy : .fixed)
        self.tertiary = tertiary
    }

    /// True when `primary` is the OS-control-accent sentinel.
    public var usesSystemPrimary: Bool { primary.rgb == systemPrimarySentinel }
    /// True when base inks should come from the OS rather than the spec
    /// (`.vibrancy` or `.systemDynamic`). Drives PaletteKit's resolve gate.
    public var usesSystemColors: Bool { backgroundMode != .fixed }
    /// True when `background` is treated as light by the derive recipe.
    /// `nil` background (vibrancy) is treated as dark.
    public var isLight: Bool { (background?.luminance ?? 0) > 0.5 }
}

// MARK: - Canonical presets
//
// The Phase V curated catalog: a curated set of user-facing color themes
// + the structural `system` preset. LEAN: a dark preset only stores border /
// hover / selection / tertiary when it DEVIATES from the derive recipe.
// The dark editor presets store NONE of the trio — PaletteKit derives the
// exact values (neutral@0.10 / neutral@0.05 / primary@0.18) from their
// dark background. Light / special presets store the trio explicitly
// (the dark-ink recipe would derive invisible white-alpha on a light bg).
//
// `system` is special: background nil (vibrancy), primary sentinel 0,
// font menu.

extension ThemeSpec {

    // --- Favorites / special ------------------------------------------

    /// terminal — classic phosphor green-on-near-black. Vivid green
    /// primary, warm amber secondary, soft green-tinted foreground.
    /// (Merges the old `hacker` preset; the old Tokyo-Night `terminal`
    /// is retired — Tokyo Night now lives in `tokyo-hack`.)
    public static let terminal = ThemeSpec(
        background: HexColor(0x050805), foreground: HexColor(0x9BFEDA),
        muted: HexColor(0x3E7D5C), primary: HexColor(0x33FF66), font: .mono,
        error: HexColor(0xFF3B3B),
        secondary: HexColor(0xFFB000))

    /// chomp — arcade Pac-Man look (pellet yellow on a black maze, neon-
    /// blue walls, ghost-red error). A CROSS-APP playful theme: facet's
    /// tree, halo's border ring, and wand's gesture trail all adopt
    /// `theme = chomp`, each drawing its OWN signature motion over this
    /// shared palette + the matching `EffectSpec.chomp` animated border
    /// (the motion drawing stays app-side; sill owns identity + colour).
    /// A dark theme, so hover derives normally; border (wall-blue) and
    /// selection (pellet) are explicit because the arcade identity needs
    /// those exact hues.
    public static let chomp = ThemeSpec(
        background: HexColor(0x000000), foreground: HexColor(0xFFEA00),
        muted: HexColor(0xB39C1A), primary: HexColor(0xFFEA00), font: .mono,
        error: HexColor(0xFF0000),
        secondary: HexColor(0x2121FF),
        border: HexColor(0x2121FF, 0.55),
        selection: HexColor(0xFFEA00, 0.18))

    /// rainbow — loud max-saturation set. White on near-black violet;
    /// high-contrast neutrals (white@0.14 / 0.07) + selection primary@0.22,
    /// all of which deviate from the recipe ⇒ explicit. Owns the loud
    /// full-spectrum neon slot.
    public static let rainbow = ThemeSpec(
        background: HexColor(0x0D0B14), foreground: HexColor(0xFFFFFF),
        muted: HexColor(0x8C84B0), primary: HexColor(0xFF2D95), font: .rounded,
        secondary: HexColor(0x2BE0FF),
        border: HexColor(0xFFFFFF, 0.14),
        hover: HexColor(0xFFFFFF, 0.07),
        selection: HexColor(0xFF2D95, 0.22))

    // --- Neon-on-black candidates (proposals) -------------------------
    // High-visibility neon primary/secondary on a near-pure-black base,
    // in the terminal/chomp family. Dark presets: only bg/fg/muted/primary/
    // secondary/error stored; the border/hover/selection trio derives.

    /// Aurora Flux — neon emerald-mint + electric violet on void black
    /// (Night Owl / Aura lineage; Tailwind emerald→teal + purple/fuchsia).
    public static let auroraFlux = ThemeSpec(
        background: HexColor(0x03070A), foreground: HexColor(0xCDFBEF),
        muted: HexColor(0x4E6F69), primary: HexColor(0x1EFFB0), font: .mono,
        error: HexColor(0xFF456B),
        secondary: HexColor(0xCE5BFF))

    /// Acidwave — fuchsia magenta + jade emerald (Tailwind 400s), rounded
    /// (SynthWave '84 / Aura).
    public static let acidwave = ThemeSpec(
        background: HexColor(0x06030A), foreground: HexColor(0xE8DDF5),
        muted: HexColor(0x7A6B8F), primary: HexColor(0xE879F9), font: .rounded,
        error: HexColor(0xFB4D6A),
        secondary: HexColor(0x34D399))

    /// Neon Noir — cyberpunk electric cyan + hot magenta on true black
    /// (Cyberpunk 2077 / Bluloco; Tailwind cyan-400).
    public static let neonNoir = ThemeSpec(
        background: HexColor(0x04060A), foreground: HexColor(0xD6FBFF),
        muted: HexColor(0x4A6E7A), primary: HexColor(0x22D3EE), font: .mono,
        error: HexColor(0xFF3355),
        secondary: HexColor(0xFF2EC4))

    /// Outrun — SynthWave violet-magenta + sunset coral, rounded
    /// (SynthWave '84 / Outrun sun-gradient).
    public static let outrun = ThemeSpec(
        background: HexColor(0x040208), foreground: HexColor(0xF2E9FF),
        muted: HexColor(0x7A5C9E), primary: HexColor(0xC724FF), font: .rounded,
        error: HexColor(0xFF3B6B),
        secondary: HexColor(0xFF7847))

    /// Blacklight — UV proton-violet + acid-lime hazard pair on void black
    /// (SynthWave '84 / Andromeda; Tailwind violet + lime-400).
    public static let blacklight = ThemeSpec(
        background: HexColor(0x030206), foreground: HexColor(0xF3E8FF),
        muted: HexColor(0x6B5B95), primary: HexColor(0xBD3FFF), font: .mono,
        error: HexColor(0xFF2D55),
        secondary: HexColor(0xCCFF00))

    // --- Pitch-black cyberpunk quartet (neon-noir lineage) ------------
    // The same high-visibility neon-on-black recipe as neon-noir, but on a
    // PURE #000000 base (no blue/violet hint) for the loudest contrast.
    // Dark presets: bg/fg/muted/primary/secondary/error only; trio derives.

    /// Synthwave — neon-noir's two colours with the lead flipped: HOT
    /// MAGENTA primary + electric-cyan secondary on pitch black (Hotline
    /// Miami / SynthWave '84). Keeps neon-noir's visibility, new identity.
    public static let synthwave = ThemeSpec(
        background: HexColor(0x000000), foreground: HexColor(0xFFE3FA),
        muted: HexColor(0x7E5577), primary: HexColor(0xFF2EC4), font: .mono,
        error: HexColor(0xFF3355),
        secondary: HexColor(0x22D3EE))

    /// Ghostwire — neon-noir's direct successor: electric-cyan primary + hot
    /// magenta secondary, but on pitch black with the cyan pushed brighter
    /// (Ghostwire: Tokyo). neon-noir, blacker and louder.
    public static let ghostwire = ThemeSpec(
        background: HexColor(0x000000), foreground: HexColor(0xD6FBFF),
        muted: HexColor(0x466A78), primary: HexColor(0x00E5FF), font: .mono,
        error: HexColor(0xFF3355),
        secondary: HexColor(0xFF2EC4))

    /// Cyberpunk — the franchise's signature acid-yellow primary + electric
    /// cyan secondary on pitch black (Cyberpunk 2077). The acid (green-
    /// leaning) yellow keeps it distinct from chomp's pure pellet yellow.
    public static let cyberpunk = ThemeSpec(
        background: HexColor(0x000000), foreground: HexColor(0xF3F7E2),
        muted: HexColor(0x6E7A4A), primary: HexColor(0xFCEE0A), font: .mono,
        error: HexColor(0xFF3344),
        secondary: HexColor(0x00E5FF))

    /// Tron — electric-azure primary + neon-orange secondary on pitch black
    /// (Tron / Blade Runner night). The only blue-primary / orange-secondary
    /// pair in the catalog — maximally differentiated from the rest.
    public static let tron = ThemeSpec(
        background: HexColor(0x000000), foreground: HexColor(0xDCEFFF),
        muted: HexColor(0x4F6A82), primary: HexColor(0x12A5FF), font: .mono,
        error: HexColor(0xFF3355),
        secondary: HexColor(0xFF6A1A))

    // --- Animated neon family (theme + EffectSpec pairs) --------------
    // The second wave of `chomp`'s "playful animated themes" family (DESIGN
    // §3): each is a pure-#000000 neon theme that ALSO ships a matching
    // `EffectSpec.<name>` so `theme = <name>` animates (still's card glows +
    // cycles; apps cycle the accent via `animatedPalette`). Hues were chosen
    // to fill the catalog's gaps — the cool space (cyan/violet/magenta/green)
    // was crowded, so this family leans WARM (the sparse end) plus one
    // mystical indigo. Dark presets: bg/fg/muted/primary/secondary/error
    // only; the border/hover/selection trio derives from the black base.

    /// voltage — high-voltage electric storm: an arc-cyan core discharging
    /// through violet, white lightning in the flash. Cooler/whiter-flashing
    /// than the saturated catalog cyans (its identity is the white strobe).
    public static let voltage = ThemeSpec(
        background: HexColor(0x000000), foreground: HexColor(0xE6FAFF),
        muted: HexColor(0x3E6E82), primary: HexColor(0x18D7FF), font: .mono,
        error: HexColor(0xFF3355),
        secondary: HexColor(0xB86BFF))

    /// toxic — radioactive hazmat rave: a toxic-lime lead (the only catalog
    /// theme to LEAD with lime) crossed with ultraviolet. Pulses through the
    /// green spectrum.
    public static let toxic = ThemeSpec(
        background: HexColor(0x000000), foreground: HexColor(0xECFFD6),
        muted: HexColor(0x5A7A2E), primary: HexColor(0x9EFF00), font: .mono,
        error: HexColor(0xFF3355),
        secondary: HexColor(0xB14BFF))

    /// ember — molten forge: incandescent orange + gold, the catalog's first
    /// WARM-lead neon. Flickers like forge-fire.
    public static let ember = ThemeSpec(
        background: HexColor(0x000000), foreground: HexColor(0xFFE9D6),
        muted: HexColor(0x8A5A2E), primary: HexColor(0xFF7A1A), font: .mono,
        error: HexColor(0xFF2D55),
        secondary: HexColor(0xFFC400))

    /// solar-veil — sunset afterglow (nature): a ROSE-CORAL primary — a hue
    /// no other theme leads with — bleeding into apricot. Rounded for a soft
    /// dusk feel. Distinct from ember (orange) by the pink-shifted lead.
    public static let solarVeil = ThemeSpec(
        background: HexColor(0x000000), foreground: HexColor(0xFFEDE4),
        muted: HexColor(0xA86B5E), primary: HexColor(0xFF5C7A), font: .rounded,
        error: HexColor(0xFF2D55),
        secondary: HexColor(0xFFB44A))

    /// molten-vein — fresh lava (nature): a hot RED-orange incandescence
    /// (near-red, distinct from ember's amber-orange) veined with sulfur
    /// chartreuse-gold — a red→sulfur heat gradient no warm theme owns.
    public static let moltenVein = ThemeSpec(
        background: HexColor(0x000000), foreground: HexColor(0xFFEDDA),
        muted: HexColor(0x8C4A2E), primary: HexColor(0xFF3D14), font: .mono,
        error: HexColor(0xFF1744),
        secondary: HexColor(0xE5E219))

    /// coin-op — arcade cabinet (retro game): siren-scarlet + electric CRT
    /// blue, a marquee/police-light pairing on pure black, with a white
    /// strobe in the flash. The catalog's first RED-lead theme.
    public static let coinOp = ThemeSpec(
        background: HexColor(0x000000), foreground: HexColor(0xFFF2EC),
        muted: HexColor(0xA14A3E), primary: HexColor(0xFF2A1A), font: .mono,
        error: HexColor(0xFF3D6E),
        secondary: HexColor(0x1565FF))

    /// arcane — mystical spellcraft (magic): a deep indigo-violet plasma
    /// crowned with rune-gold — the bluest/deepest of the violet cluster
    /// (clear of blacklight/outrun's magenta-violets), and violet+gold is a
    /// pairing no catalog theme has. Rounded for a soft ritual glow.
    public static let arcane = ThemeSpec(
        background: HexColor(0x000000), foreground: HexColor(0xF0E9FF),
        muted: HexColor(0x6A5AB0), primary: HexColor(0x7B3FF2), font: .rounded,
        error: HexColor(0xFF4D6D),
        secondary: HexColor(0xFFC83D))

    // --- Reference themes (Tommy-linked) ------------------------------

    /// Cobalt2 (Wes Bos) — deep cobalt-blue, signature bright gold.
    public static let cobalt2 = ThemeSpec(
        background: HexColor(0x193549), foreground: HexColor(0xFFFFFF),
        muted: HexColor(0xAAAAAA), primary: HexColor(0xFFC600), font: .mono,
        error: HexColor(0xFF5C57),
        secondary: HexColor(0x0088FF))

    /// Shades of Purple (ahmadawais) — purple-indigo, golden-yellow accent.
    public static let shadesOfPurple = ThemeSpec(
        background: HexColor(0x2D2B55), foreground: HexColor(0xFFFFFF),
        muted: HexColor(0xA599E9), primary: HexColor(0xFAD000), font: .mono,
        error: HexColor(0xEC3A37),
        secondary: HexColor(0x9EFFFF))

    /// Tokyo Hack (ajshortt) — midnight-indigo, red-orange chrome. The
    /// catalog's Tokyo-Night lineage (old `terminal` retired).
    public static let tokyoHack = ThemeSpec(
        background: HexColor(0x18173E), foreground: HexColor(0xFFFFFF),
        muted: HexColor(0x6470B0), primary: HexColor(0xE84B3C), font: .mono,
        error: HexColor(0xFA6771),
        secondary: HexColor(0xF08DF0))

    // --- Popular ------------------------------------------------------

    /// GitHub Dark — the most-installed theme. Link-blue, success-green.
    public static let githubDark = ThemeSpec(
        background: HexColor(0x0D1117), foreground: HexColor(0xE6EDF3),
        muted: HexColor(0x8B949E), primary: HexColor(0x2F81F7), font: .mono,
        error: HexColor(0xF85149),
        secondary: HexColor(0x3FB950))

    /// Dracula — vivid dark. Signature purple, brand-iconic pink secondary.
    public static let dracula = ThemeSpec(
        background: HexColor(0x282A36), foreground: HexColor(0xF8F8F2),
        muted: HexColor(0x6272A4), primary: HexColor(0xBD93F9), font: .mono,
        error: HexColor(0xFF5555),
        secondary: HexColor(0xFF79C6))

    /// Catppuccin Mocha — soft pastel dark. Mauve primary, pastel-blue
    /// secondary; muted deepened to widen the gap from dracula.
    public static let catppuccinMocha = ThemeSpec(
        background: HexColor(0x1E1E2E), foreground: HexColor(0xCDD6F4),
        muted: HexColor(0x6C7086), primary: HexColor(0xCBA6F7), font: .mono,
        error: HexColor(0xF38BA8),
        secondary: HexColor(0x89B4FA))

    /// Gruvbox — retro warm dark. Orange primary, aqua secondary.
    public static let gruvbox = ThemeSpec(
        background: HexColor(0x282828), foreground: HexColor(0xEBDBB2),
        muted: HexColor(0x928374), primary: HexColor(0xFE8019), font: .mono,
        secondary: HexColor(0x8EC07C))

    // --- Light --------------------------------------------------------

    /// GitHub Light — clean daytime white. Link-blue / purple, ink-alpha
    /// neutrals (explicit because the dark recipe derives wrong on light).
    public static let githubLight = ThemeSpec(
        background: HexColor(0xFFFFFF), foreground: HexColor(0x1F2328),
        muted: HexColor(0x6E7781), primary: HexColor(0x0969DA), font: .system,
        error: HexColor(0xCF222E),
        secondary: HexColor(0x8250DF),
        border: HexColor(0x1F2328, 0.10),
        hover: HexColor(0x1F2328, 0.05),
        selection: HexColor(0x0969DA, 0.18))

    /// Catppuccin Latte — warm-grey lavender light. Purple primary, teal
    /// secondary; explicit trio (light theme).
    public static let catppuccinLatte = ThemeSpec(
        background: HexColor(0xEFF1F5), foreground: HexColor(0x4C4F69),
        muted: HexColor(0x8C8FA1), primary: HexColor(0x8839EF), font: .mono,
        error: HexColor(0xD20F39),
        secondary: HexColor(0x209FB5),
        border: HexColor(0x4C4F69, 0.10),
        hover: HexColor(0x4C4F69, 0.05),
        selection: HexColor(0x8839EF, 0.18))

    // --- Structural ---------------------------------------------------

    /// Native vibrancy + dynamic system colors. background nil (vibrancy),
    /// primary sentinel 0 (OS control-accent), font menu. The trio is
    /// resolved against system colors in PaletteKit (it can't be a hex
    /// here), so it stays nil and PaletteKit special-cases `system`.
    public static let system = ThemeSpec(
        background: nil, foreground: HexColor(0x000000), muted: HexColor(0x000000),
        primary: HexColor(systemPrimarySentinel), font: .menu)
}

// MARK: - Name resolution

/// Single source of truth for the catalog: ordered (name, spec) pairs.
/// `canonicalThemeNames` and `paletteFor` both derive from this table, so
/// adding a theme is ONE edit (the old layout needed the static, the
/// `paletteFor` switch, AND the name array kept in sync by hand — sill's
/// own little hand-copy, now retired). Order is the user-facing catalog
/// order (favorites → reference → popular → light → structural).
private let themeCatalog: [(name: String, spec: ThemeSpec)] = [
    ("terminal", .terminal), ("chomp", .chomp), ("rainbow", .rainbow),
    ("aurora-flux", .auroraFlux), ("acidwave", .acidwave),
    ("neon-noir", .neonNoir), ("outrun", .outrun), ("blacklight", .blacklight),
    ("synthwave", .synthwave), ("ghostwire", .ghostwire),
    ("cyberpunk", .cyberpunk), ("tron", .tron),
    ("voltage", .voltage), ("toxic", .toxic), ("ember", .ember),
    ("solar-veil", .solarVeil), ("molten-vein", .moltenVein),
    ("coin-op", .coinOp), ("arcane", .arcane),
    ("cobalt2", .cobalt2), ("shades-of-purple", .shadesOfPurple),
    ("tokyo-hack", .tokyoHack),
    ("github-dark", .githubDark), ("dracula", .dracula),
    ("catppuccin-mocha", .catppuccinMocha), ("gruvbox", .gruvbox),
    ("github-light", .githubLight), ("catppuccin-latte", .catppuccinLatte),
    ("system", .system),
]

/// Canonical theme names accepted by `--theme=`. Single source of truth
/// so a CLI can reject typos. Includes the `random` meta-name.
public let canonicalThemeNames: [String] = themeCatalog.map(\.name) + ["random"]

/// Map a raw `--theme=…` value to a `ThemeSpec`. Case-insensitive;
/// unknown names fall through to `terminal`. `random` picks a concrete
/// non-system theme each call. Pure — no AppKit.
public func paletteFor(_ raw: String) -> ThemeSpec {
    let s = raw.lowercased()
    if s == "random" {
        let pool = themeCatalog.map(\.name).filter { $0 != "system" }
        return paletteFor(pool.randomElement() ?? "terminal")
    }
    return themeCatalog.first { $0.name == s }?.spec ?? .terminal
}

// MARK: - Pure effect / pet vocabulary
//
// The NAME lists for the dynamic-effect catalog live HERE — not in
// `Effects` — because a no-AppKit Core (FacetCore, WandCore) must be able
// to validate config tokens without linking a module that compiles AppKit
// code on macOS. The `EffectSpec` catalog + animators stay in `Effects`
// (which `@_exported import`s Palette, so Effects-only consumers still
// see these names unqualified).

/// Canonical effect names accepted by `[border] effect` (+ `off` /
/// `random`). Single source of truth so a CLI can reject typos.
public let canonicalEffectNames: [String] = [
    "neon", "cyber", "vapor", "kawaii", "rainbow", "chomp",
    // The animated neon family — each is a theme+EffectSpec pair (like
    // chomp), so its name is ALSO a valid standalone `[border] effect`.
    "voltage", "toxic", "ember", "solar-veil", "molten-vein", "coin-op", "arcane",
    "random", "off",
]

/// One of the small arcade "pets" that walk a surface's outline — a
/// shared decoration across facet's tree, halo's ring, and wand's cast /
/// tome cards. Multiple pets chase each other around the rim in array
/// order (first leads, the rest trail at a fixed gap). Theme-AGNOSTIC:
/// each pet's colours are baked into its silhouette, so it reads the
/// same under any theme. Pure identity — configs persist / validate
/// against it with no AppKit; the drawing (`drawLinePets`) lives in
/// `Effects` behind `#if canImport(AppKit)`.
public enum LinePet: String, Sendable, Hashable, CaseIterable {
    /// Classic yellow chomping wedge.
    case chomp
    /// Red Blinky-style ghost — dome top, two eyes, scalloped skirt.
    case ghost
}

/// Canonical pet names accepted by a `line-pets` config list. Single
/// source of truth so a consumer can drop + report typos.
public let canonicalLinePetNames: [String] = LinePet.allCases.map(\.rawValue)

// MARK: - Validation (pure, opt-in — shared MECHANISM; policy stays app-side)

/// Canonicalize a raw `--theme=` value: the matched canonical name
/// (case-insensitive, trimmed) or `nil` if unknown. The shared mechanism
/// behind both a silent config-clamp (`canonical(x) ?? "terminal"`) and a
/// loud CLI reject (`canonical(x)` nil ⇒ exit + `suggest`). Replaces each
/// app's hand-kept theme-name list so there is one source of truth.
public func canonical(_ raw: String) -> String? {
    let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
    return canonicalThemeNames.contains(s) ? s : nil
}

/// Nearest canonical theme name to a typo'd `raw` (Levenshtein), or `nil`
/// when nothing is plausibly close — a did-you-mean hint for a loud CLI
/// reject. Excludes the `random` meta-name.
public func suggest(_ raw: String) -> String? {
    let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
    guard !s.isEmpty else { return nil }
    var best: String?
    var bestDist = Int.max
    for name in canonicalThemeNames where name != "random" {
        let d = levenshtein(s, name)
        if d < bestDist { bestDist = d; best = name }
    }
    // Only hint when it reads like a typo, not a wildly different string.
    guard bestDist <= max(2, s.count / 2) else { return nil }
    return best
}

/// Classic Levenshtein edit distance (pure). Theme names are short, so the
/// two-row DP is plenty.
func levenshtein(_ lhs: String, _ rhs: String) -> Int {
    let a = Array(lhs), b = Array(rhs)
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var prev = Array(0...b.count)
    var cur = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
        cur[0] = i
        for j in 1...b.count {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        }
        swap(&prev, &cur)
    }
    return prev[b.count]
}

// MARK: - Contrast (shared value logic, pure)

/// WCAG 2.x relative luminance of an sRGB channel triple (each `0...1`),
/// gamma-decoded. Distinct from `HexColor.luminance` (a cheap Rec.601
/// approximation that drives the light/dark THEME branch); the
/// foreground-contrast choice needs the perceptually-correct curve to
/// pick the legible ink.
public func wcagRelativeLuminance(r: Double, g: Double, b: Double) -> Double {
    func lin(_ c: Double) -> Double {
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

/// True when BLACK text contrasts a fill of WCAG relative luminance `L`
/// at least as well as white — the actual contrast-ratio crossover
/// (≈ L 0.18), NOT a perceptual-midpoint guess. A binary luminance
/// threshold (the old 0.6 cut) left mid-luminance fills (L≈0.35–0.50)
/// with white text at only ~2:1; this picks the higher-contrast ink.
/// Shared so PaletteKit's NSColor `onPrimary` and the pure
/// `HexColor.bestForeground` can't drift apart.
public func prefersBlackForeground(fillRelLuminance L: Double) -> Bool {
    let contrastBlack = (L + 0.05) / 0.05
    let contrastWhite = 1.05 / (L + 0.05)
    return contrastBlack >= contrastWhite
}

public extension HexColor {
    /// Black or white — whichever best contrasts THIS color used as a
    /// fill, by WCAG contrast ratio. The pure half of `onPrimary`;
    /// PaletteKit reuses the same logic for the resolved-`NSColor`
    /// (incl. OS controlAccent) case so they can't drift.
    var bestForeground: HexColor {
        prefersBlackForeground(fillRelLuminance: wcagRelativeLuminance(r: r, g: g, b: b))
            ? HexColor(0x000000) : HexColor(0xFFFFFF)
    }
}

// MARK: - Color-token parsing (pure, opt-in)

/// Parse a config-edge color token into a `HexColor`, or `nil` if it
/// isn't a recognized literal. Accepts a small named-color set plus
/// `#rgb` / `#rrggbb` / `#rrggbbaa` (the leading `#` optional). Opt-in:
/// an app wanting a stricter grammar (halo's 6-digit-only) keeps its own
/// parser; this lets wand dedup its token grammar. Semantic tokens like
/// `primary` / `system` are NOT handled here — they are app-level
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
/// `background` luminance — darker themes get a more opaque pill. Opt-in:
/// perch MAY call this instead of hand-maintaining its per-preset table;
/// it is NOT applied by the derive recipe (a nil `backgroundAlpha` still
/// means opaque).
public func suggestedPillAlpha(luminance: Double) -> Double {
    let a = 0.92 - luminance * 0.55      // dark ≈ 0.92 … light ≈ 0.37
    return min(0.92, max(0.30, a))
}

// MARK: - EffectIntensity (pure, shared)

/// How strongly a dynamic effect renders — a magnitude multiplier the
/// consuming app applies to spatial dimensions (scale / distance /
/// vibration amplitude) and particle birth-rate, NOT to duration. The
/// four-tier vocabulary (`subtle` 0.6× … `wild` 2.5×) was hand-copied
/// identically in wand (`Intensity`) and perch (`EffectIntensity`); the
/// rule-of-three trigger (halo is the third effects consumer) earned the
/// promotion to one shared enum.
///
/// Lives in `Palette` — not `Effects` — because it is a pure `Sendable`
/// `Double` knob with no AppKit, so a `Palette`-only consumer (perch)
/// can adopt it without linking `Effects`. (The `Double` multiplier
/// keeps the module CoreGraphics-free; callers wanting `CGFloat` wrap at
/// the use site.)
public enum EffectIntensity: String, Sendable, Hashable, CaseIterable {
    case subtle
    case normal
    case bold
    case wild

    /// Magnitude scale applied to an effect's spatial dimensions and
    /// particle counts. `1.0` = the authored baseline.
    public var multiplier: Double {
        switch self {
        case .subtle: return 0.6
        case .normal: return 1.0
        case .bold:   return 1.6
        case .wild:   return 2.5
        }
    }

    /// Parse a config token (case-insensitive, trimmed) into an
    /// `EffectIntensity`, or `nil` if unrecognized so the caller can
    /// clamp + log per its own policy.
    public static func parse(_ raw: String) -> EffectIntensity? {
        EffectIntensity(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
    }
}
