// Effects — the shared DYNAMIC theming atom for facet + halo + wand +
// perch. STATIC palettes live in `Palette`/`PaletteKit`; the
// time-varying parts (border flash, theme hue-rotation, rainbow cycle)
// live here, cleanly separated.
//
// Two tiers, mirroring the rest of sill:
//   * `EffectSpec` — pure, Sendable, UInt32 hex (steady + flash[] +
//     cycles). No AppKit. The shared description halo/facet both
//     validate + persist against.
//   * `AnimatedEffect` (AppKit, macOS) — turns an `EffectSpec` + a
//     `ThemeSpec` + a phase into a `ResolvedPalette`-shaped animated
//     output. Gated by `#if canImport(AppKit)` so the spec stays
//     cross-platform.

import Palette

#if canImport(AppKit)
import AppKit
#endif

// MARK: - EffectSpec (pure)

/// One dynamic border/theme effect: a resting hue plus the palette its
/// flash blinks through, and whether it slowly rotates the steady hue
/// (rainbow). Pure `UInt32` hex so the spec is `Sendable` with no
/// AppKit. The analog of facet's `BorderEffect`, halo's `BorderEffect`,
/// reconciled into ONE shared type.
public struct EffectSpec: Sendable, Hashable {
    /// Resting border color, `0xRRGGBB`.
    public let steady: UInt32
    /// Palette the WS-switch flash blinks through, `0xRRGGBB` each.
    public let flash: [UInt32]
    /// Slowly rotate `steady` through the spectrum (rainbow only).
    public let cycles: Bool

    public init(steady: UInt32, flash: [UInt32], cycles: Bool = false) {
        self.steady = steady
        self.flash = flash
        self.cycles = cycles
    }
}

// MARK: - Canonical effect palettes
//
// Reconciled from facet's BorderEffect.swift (authoritative for the
// flash sequences) and halo's BorderEffect. Where they diverged we keep
// facet's, noted inline:
//   * neon / cyber / vapor / kawaii / rainbow flash arrays = facet's
//     verbatim. halo's earlier kawaii used 5 hues; facet's 6-hue
//     KAWAII set is the canonical one here (superset, same family).
//   * steady hues = facet's (Tokyo-Night blue for neon, etc.). halo
//     drew steady from the theme accent at runtime; sill keeps facet's
//     fixed steady so the effect reads identically with theme = off.
// Divergence to watch: halo treats `steady` as advisory (it may use the
// live focus color); see migrationNotes.

extension EffectSpec {
    /// Neon — Tokyo-Night blue at rest; electric neon flashes.
    public static let neon = EffectSpec(
        steady: 0x7AA2F7,
        flash: [0x00E5FF, 0xFF00FF, 0x39FF14, 0xFE019A, 0x04D9FF, 0xBC13FE])

    /// Cyber — teal/aqua matrix feel.
    public static let cyber = EffectSpec(
        steady: 0x00FFD0,
        flash: [0x00FFD0, 0x00E5FF, 0x39FF14, 0x14FFEC, 0x00FF9C, 0x0AFFFF])

    /// Vapor — synthwave pink → purple → cyan.
    public static let vapor = EffectSpec(
        steady: 0xFF6AD5,
        flash: [0xFF6AD5, 0xC774E8, 0xAD8CFF, 0x8795E8, 0x94D0FF, 0xFF71CE])

    /// Kawaii — soft pastels.
    public static let kawaii = EffectSpec(
        steady: 0xFFB3D9,
        flash: [0xFFB3D9, 0xD9B3FF, 0xB3FFD9, 0xFFE0B3, 0xB3E0FF, 0xFFC6E0])

    /// Rainbow — full spectrum; `cycles` rotates the resting hue.
    public static let rainbow = EffectSpec(
        steady: 0xFF3B30,
        flash: [0xFF0000, 0xFF7F00, 0xFFFF00, 0x00FF00,
                0x00FFFF, 0x0000FF, 0x8B00FF],
        cycles: true)

    /// Chomp — arcade maze: neon-blue walls at rest, blinking through
    /// pellet-yellow + ghost-red. The shared animated border for the
    /// cross-app `chomp` theme (facet tree / halo ring / wand trail each
    /// layer their own `ThemeMotion` over this). Not a `cycles` effect —
    /// it blinks a FIXED arcade palette rather than rotating the spectrum.
    public static let chomp = EffectSpec(
        steady: 0x2121FF,
        flash: [0xFFEA00, 0x2121FF, 0xFF0000, 0x2121FF])
}

/// Canonical effect names accepted by `[border] effect` (+ `off` /
/// `random`). Single source of truth so a CLI can reject typos.
public let canonicalEffectNames: [String] = [
    "neon", "cyber", "vapor", "kawaii", "rainbow", "chomp", "random", "off",
]

/// Map a BUILT-IN effect name to its `EffectSpec`, or `nil` for "off" /
/// unknown. Pure — `UInt32` hex, no AppKit. `random` picks a concrete
/// built-in each call (matches facet). For app-registered effects use
/// `EffectRegistry.shared.spec(for:)`, which is a superset of this.
public func borderEffectFor(_ name: String) -> EffectSpec? {
    switch name.lowercased() {
    case "neon":    return .neon
    case "cyber":   return .cyber
    case "vapor":   return .vapor
    case "kawaii":  return .kawaii
    case "rainbow": return .rainbow
    case "chomp":   return .chomp
    case "random":
        let pool: [EffectSpec] = [.neon, .cyber, .vapor, .kawaii, .rainbow, .chomp]
        return pool.randomElement()
    default:        return nil   // "off" or unknown
    }
}

// MARK: - Extensible effect registry

/// A mutable, app-extensible registry mapping effect NAMES to specs.
/// sill ships the built-ins (neon/cyber/vapor/kawaii/rainbow/chomp); an
/// app registers its OWN at startup — a chomp sibling, a wand-private
/// effect — via `register`, without modifying sill. Lookups fall back to
/// the built-ins, so `spec(for:)` is a superset of `borderEffectFor`.
/// This is the "extensible registry" half of the Q4-A decision (the
/// per-surface motion is `ThemeMotion`).
///
/// `@MainActor` because apps register/read it from their main-thread
/// startup; the stored `EffectSpec`s are themselves `Sendable`. No
/// AppKit — a headless consumer can register + look up specs too.
@MainActor
public final class EffectRegistry {
    public static let shared = EffectRegistry()
    private var custom: [String: EffectSpec] = [:]
    private init() {}

    /// Register (or override) an effect by name (lowercased).
    public func register(_ name: String, _ spec: EffectSpec) {
        custom[name.lowercased()] = spec
    }

    /// Look up an effect: custom registrations first, then the built-ins.
    /// `nil` for "off" / unknown.
    public func spec(for name: String) -> EffectSpec? {
        custom[name.lowercased()] ?? borderEffectFor(name)
    }

    /// Whether a name resolves to any effect (built-in or registered).
    public func has(_ name: String) -> Bool { spec(for: name) != nil }

    /// All concrete effect names known right now (built-ins + custom),
    /// excluding the `random` / `off` meta-names.
    public var names: [String] {
        let builtin = canonicalEffectNames.filter { $0 != "random" && $0 != "off" }
        return Array(Set(builtin).union(custom.keys)).sorted()
    }
}

// MARK: - Pure blend (UInt32)

/// Smoothly loop through `colors` (each `0xRRGGBB`) by `phase` (0…1),
/// blending consecutive entries in sRGB. The PURE form of the shared
/// cycle primitive — no AppKit, so halo's headless / cross-platform
/// paths can use it. Returns an `(r,g,b)` triple in `0...1`.
public func blendThrough(_ colors: [UInt32], at phase: Double)
    -> (r: Double, g: Double, b: Double) {
    func rgb(_ h: UInt32) -> (Double, Double, Double) {
        (Double((h >> 16) & 0xFF) / 255,
         Double((h >> 8) & 0xFF) / 255,
         Double(h & 0xFF) / 255)
    }
    let n = colors.count
    guard n > 1 else {
        let (r, g, b) = rgb(colors.first ?? 0xFFFFFF); return (r, g, b)
    }
    let p = phase - floor(phase)
    let scaled = p * Double(n)
    let i = Int(scaled) % n
    let t = scaled - floor(scaled)
    let (r0, g0, b0) = rgb(colors[i])
    let (r1, g1, b1) = rgb(colors[(i + 1) % n])
    return (r0 + (r1 - r0) * t,
            g0 + (g1 - g0) * t,
            b0 + (b1 - b0) * t)
}

// MARK: - Animated palette (AppKit)

#if canImport(AppKit)

/// A point-in-time animated frame: the spec's accent/accent2 rotated to
/// `phase`, with bg/text/dim held steady so the UI stays usable. Returns
/// resolved `NSColor`s ready to install as the live `pal`. `@MainActor`
/// because `NSColor` isn't `Sendable`.
@MainActor
public struct AnimatedFrame {
    public let accent: NSColor
    public let accent2: NSColor
    /// selFill keyed to the live accent (accent@0.22) for visible motion.
    public let selFill: NSColor
}

/// Cycle a theme to `phase` (0…1). A `cycles` effect (rainbow, and any
/// custom cycling sibling) rotates the accent through the full spectrum;
/// a flash effect (neon/cyber/vapor/kawaii/chomp) cycles through that
/// effect's own flash palette (keeping its identity). Resolves the
/// effect through `EffectRegistry` so app-registered siblings animate
/// too. Returns nil for a non-animatable theme. `accent2` trails half a
/// turn. Generalizes facet's `animatedPalette`.
///
/// Callers blend the result into a fresh `ResolvedPalette` (or assign
/// the three fields onto a copy) — Effects deliberately doesn't depend
/// on PaletteKit, so it returns the animated atoms, not a full
/// `ResolvedPalette`, keeping the layer graph acyclic.
@MainActor
public func animatedPalette(theme name: String, at phase: CGFloat) -> AnimatedFrame? {
    guard let fx = EffectRegistry.shared.spec(for: name) else { return nil }
    let h = phase - floor(phase)
    let h2 = (h + 0.5).truncatingRemainder(dividingBy: 1)

    func ns(_ t: (r: Double, g: Double, b: Double)) -> NSColor {
        NSColor(srgbRed: CGFloat(t.r), green: CGFloat(t.g),
                blue: CGFloat(t.b), alpha: 1)
    }

    let accent: NSColor, accent2: NSColor
    if fx.cycles {
        accent  = NSColor(hue: h,  saturation: 0.95, brightness: 1, alpha: 1)
        accent2 = NSColor(hue: h2, saturation: 0.95, brightness: 1, alpha: 1)
    } else if !fx.flash.isEmpty {
        accent  = ns(blendThrough(fx.flash, at: Double(h)))
        accent2 = ns(blendThrough(fx.flash, at: Double(h2)))
    } else {
        return nil
    }
    return AnimatedFrame(accent: accent, accent2: accent2,
                         selFill: accent.withAlphaComponent(0.22))
}

// MARK: - ThemeMotion (per-surface signature motion)

/// A theme that carries its OWN signature MOTION on an app's surface:
/// wand's Pac-Man cursor trail, facet's tree flourish, halo's border
/// ring. sill standardizes only the SHARED parts — the theme IDENTITY
/// (`themeName`, so `theme = chomp` routes everywhere) and the per-phase
/// animated COLORS (`frame(at:)`, so every app cycles identically off the
/// same `EffectSpec`). The DRAWING stays app-side: each app conforms and
/// renders into its own surface. Intentionally THIN — a surface-agnostic
/// contract can't know about cursor trails vs tree rows, so sill owns
/// identity + colour, the app owns geometry (this is the Q4-A "shared
/// data + registry + motion protocol" boundary).
@MainActor
public protocol ThemeMotion {
    /// The theme name this motion belongs to (e.g. "chomp"). Apps route
    /// `theme = <name>` to the matching motion.
    var themeName: String { get }
    /// The shared effect whose flash/steady this motion cycles.
    var effect: EffectSpec { get }
    /// The animated colours at `phase` (0…1). Defaulted from the shared
    /// `animatedPalette`, so conformers cycle identically for free.
    func frame(at phase: CGFloat) -> AnimatedFrame
}

public extension ThemeMotion {
    func frame(at phase: CGFloat) -> AnimatedFrame {
        if let f = animatedPalette(theme: themeName, at: phase) { return f }
        let steady = effectNSColor(effect.steady)
        return AnimatedFrame(accent: steady, accent2: steady,
                             selFill: steady.withAlphaComponent(0.22))
    }
}

/// `NSColor` from `0xRRGGBB` — internal to Effects so it doesn't depend
/// on PaletteKit (and doesn't clash with PaletteKit's public
/// `NSColor(hex:)` when an app imports both modules).
func effectNSColor(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green:   CGFloat((hex >> 8)  & 0xFF) / 255,
            blue:    CGFloat( hex        & 0xFF) / 255,
            alpha:   a)
}

#endif
