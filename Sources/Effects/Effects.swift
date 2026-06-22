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

// Re-exported: an Effects-only consumer (halo) sees the pure vocabulary —
// `canonicalEffectNames` / `LinePet` / `canonicalLinePetNames` /
// `EffectIntensity` / `parseColorToken` / `HexColor` — without adding a
// second dependency. Also keeps source compatibility for the name lists
// and `LinePet`, which moved from this module into `Palette` in 0.6.0
// (a no-AppKit Core must validate config tokens without linking Effects).
@_exported import Palette

// #12 Ph2 — the line-pets are now PIXEL sprites: PixelArt supplies the chomp
// mouth wedge + its swap pattern (`mouthHalfRad` / `chompMouthFrames`), Motion
// supplies the discrete `frameStep` sampler that animates the mouth + waddle.
import PixelArt
import Motion

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
    /// cross-app `chomp` theme; facet's tree, halo's ring, and wand's
    /// trail each draw their OWN signature motion over this shared spec.
    /// Not a `cycles` effect — it blinks a FIXED arcade palette rather
    /// than rotating the spectrum.
    public static let chomp = EffectSpec(
        steady: 0x2121FF,
        flash: [0xFFEA00, 0x2121FF, 0xFF0000, 0x2121FF])

    // --- Animated neon family (paired with the same-named ThemeSpec) ---
    // Each animates its catalog theme (still cycles the card border; apps
    // cycle the accent via `animatedPalette`) AND is a standalone
    // `[border] effect` value. None `cycles` — they blink/blend a FIXED
    // neon palette (like neon/cyber/vapor), not rotate the spectrum.

    /// Voltage — arc-cyan at rest; white-lightning strobe through violet.
    public static let voltage = EffectSpec(
        steady: 0x18D7FF,
        flash: [0x18D7FF, 0xFFFFFF, 0xB86BFF, 0x6FE9FF, 0xFFFFFF, 0x2E5BFF])

    /// Toxic — radioactive pulse through the green/lime spectrum.
    public static let toxic = EffectSpec(
        steady: 0x9EFF00,
        flash: [0x9EFF00, 0x00FFA3, 0xCCFF00, 0x39FF14, 0x00FF6E, 0xDFFF1A])

    /// Ember — forge-fire flicker through orange/gold/red.
    public static let ember = EffectSpec(
        steady: 0xFF7A1A,
        flash: [0xFF3D00, 0xFF7A1A, 0xFFC400, 0xFF5E00, 0xFFD45E, 0xFF2200])

    /// Solar-veil — a warm sunset sweep (rose → coral → apricot → rose).
    public static let solarVeil = EffectSpec(
        steady: 0xFF7A5C,
        flash: [0xFF4D6D, 0xFF7A5C, 0xFFA64A, 0xFFD27A, 0xFF6F91])

    /// Molten-vein — cooling-magma ramp from incandescent red to sulfur gold.
    public static let moltenVein = EffectSpec(
        steady: 0xFF3D14,
        flash: [0xFF3D14, 0xFF6A00, 0xE5E219, 0xFFE45C, 0xE01000])

    /// Coin-op — arcade-marquee strobe alternating siren-red / CRT-blue / white.
    public static let coinOp = EffectSpec(
        steady: 0xFF2A1A,
        flash: [0xFF2A1A, 0x1565FF, 0xFF2A1A, 0xFFFFFF, 0x1565FF])

    /// Arcane — a spell-shimmer through indigo-violet and rune-gold.
    public static let arcane = EffectSpec(
        steady: 0x7B3FF2,
        flash: [0x7B3FF2, 0xB58BFF, 0xFFC83D, 0x9D6BFF, 0xFFE27A])
}

// (`canonicalEffectNames` lives in `Palette` since 0.6.0 — pure
// vocabulary a no-AppKit Core can link — and is re-exported here.)

/// Map a BUILT-IN effect name to its `EffectSpec`, or `nil` for "off" /
/// unknown. Pure — `UInt32` hex, no AppKit. `random` picks a concrete
/// built-in each call (matches facet).
public func borderEffectFor(_ name: String) -> EffectSpec? {
    switch name.lowercased() {
    case "neon":    return .neon
    case "cyber":   return .cyber
    case "vapor":   return .vapor
    case "kawaii":  return .kawaii
    case "rainbow": return .rainbow
    case "chomp":   return .chomp
    case "voltage":     return .voltage
    case "toxic":       return .toxic
    case "ember":       return .ember
    case "solar-veil":  return .solarVeil
    case "molten-vein": return .moltenVein
    case "coin-op":     return .coinOp
    case "arcane":      return .arcane
    case "random":
        let pool: [EffectSpec] = [.neon, .cyber, .vapor, .kawaii, .rainbow, .chomp,
                                  .voltage, .toxic, .ember, .solarVeil, .moltenVein,
                                  .coinOp, .arcane]
        return pool.randomElement()
    default:        return nil   // "off" or unknown
    }
}

/// True when a THEME animates — i.e. its name has an entry in the effect
/// catalog (rainbow cycles, chomp flashes). Lets a consumer DERIVE its
/// "animatable themes" set from sill instead of hand-listing it. Pass a
/// resolved THEME name; post-rebuild that is only ever a catalog theme, so
/// `rainbow` / `chomp` are the animatable ones. (Border-effect-only names
/// like `neon` also answer true here, but they never reach this as a theme.)
public func isAnimatableTheme(_ name: String) -> Bool {
    borderEffectFor(name) != nil
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

// MARK: - Border frame (pure resolve)
//
// The shared border ANIMATOR, reconciled from halo's & facet's byte-identical
// `BorderFX.color` / `.width` / `.flash` into ONE clockless resolve — a PURE
// function of wall-clock `now` + a small `FlashState` value, NOT a stateful
// timer-owning class. Mirrors how sill already ships the time-varying border
// as pure `f(phase)` (`blendThrough`, `animatedPalette`): sill keeps its
// no-mutable-animation-state invariant, and the app owns the clock — exactly
// as halo's `RingView` already drives `drawLinePets` off `CACurrentMediaTime()`.
//
// Each consumer (halo's ring, facet's 3 surfaces) keeps its OWN redraw cadence
// (a dumb 30 Hz `needsDisplay` / `apply(to:layer)` heartbeat) and calls
// `resolveBorder` each frame. What stays APP-SIDE on purpose: the redraw timer,
// the NSColor materialization, the "off" fallback color (halo `baseColor` vs
// facet per-surface `pal.primary`), and the glow compositing (halo `NSShadow`
// vs facet `CALayer.shadow` — genuinely different glow models).

/// A focus / WS-switch flash burst, pre-rolled ONCE at the trigger and decayed
/// by wall-clock. The crux of the border unification: the ONLY genuinely
/// stateful piece of the old animator (`flashSeq` + `flashStep`) reduces to
/// this value, so the resolve stays pure. The app stores one `FlashState?`
/// cell and sets it via `rollFlash` on a focus change.
public struct FlashState: Sendable, Equatable {
    /// The pre-rolled blink colors (`0xRRGGBB` each), in play order.
    public let seq: [UInt32]
    /// Wall-clock stamp (`CACurrentMediaTime()`-style seconds) at the roll.
    public let startedAt: Double

    public init(seq: [UInt32], startedAt: Double) {
        self.seq = seq
        self.startedAt = startedAt
    }

    /// The current blink index at `now`, or nil once the burst has settled (or
    /// hasn't started). `hz` is the blink rate — 30 reproduces the old "5 ticks
    /// at 30 Hz ≈ 167 ms" burst. Wall-clock, so a dropped frame no longer
    /// stretches the burst (the one behavior shift from the old frame-counted
    /// `flashStep += 1`; cosmetically identical at a steady cadence).
    public func index(now: Double, hz: Double = 30) -> Int? {
        guard hz > 0 else { return nil }
        let i = Int((now - startedAt) * hz)
        return (i >= 0 && i < seq.count) ? i : nil
    }

    /// True while the burst is mid-flight at `now`. The app's redraw-clock gate
    /// uses this (keep ticking while flashing), as does `resolveBorder`.
    public func isActive(now: Double, hz: Double = 30) -> Bool {
        index(now: now, hz: hz) != nil
    }
}

/// Roll a fresh `count`-blink focus flash through `palette` (`0xRRGGBB` each),
/// stamped at `now`. Each pick is uniform-random with NO consecutive repeat
/// (re-rolled while equal to the previous — guarded on count > 1 so a 1-color
/// palette doesn't spin). Returns nil for an empty palette (the old
/// `guard !flash.isEmpty` no-op: an effect-less border just re-hugs silently).
/// This is halo & facet's `flash()` roll, lifted verbatim — pass `EffectSpec.flash`.
public func rollFlash(_ palette: [UInt32], now: Double, count: Int = 5) -> FlashState? {
    guard !palette.isEmpty else { return nil }
    var idxs: [Int] = []
    var last = -1
    for _ in 0..<count {
        var i = Int.random(in: 0..<palette.count)
        if palette.count > 1 { while i == last { i = Int.random(in: 0..<palette.count) } }
        idxs.append(i); last = i
    }
    return FlashState(seq: idxs.map { palette[$0] }, startedAt: now)
}

/// The resolved border color for one frame. `off` carries no color — the app
/// paints its OWN fallback (halo `baseColor` / facet per-surface `pal.primary`),
/// keeping sill palette-agnostic. `rainbowHue` is returned as a BARE hue (not
/// pre-converted to RGB) so the app materializes it via
/// `NSColor(hue:saturation:0.9:brightness:1:)` EXACTLY as before — that uses the
/// calibrated color space, so pre-converting to sRGB here would shift the
/// rainbow's gamut and break halo's byte-parity.
public enum BorderColor: Sendable, Equatable {
    /// Effect off — the app paints its own fallback color.
    case off
    /// A concrete sRGB color (steady / flash blink / `cycleColors` blend).
    case rgb(r: Double, g: Double, b: Double)
    /// Rainbow: a bare hue `0...1`; the app builds `NSColor(hue:…)` (calibrated).
    case rainbowHue(Double)
}

/// A point-in-time border frame: the resolved color, the current stroke width
/// (breathing + flash pop already applied), and whether a flash is mid-flight
/// (the app uses it to boost its OWN glow). Glow geometry is deliberately NOT
/// here — halo (`NSShadow` blur `max(6, w*4)`, no flash bump) and facet
/// (`CALayer.shadow`, flash-conditional `max(5,w*5)`/`0.95`) are different glow
/// models, so each composes its own from `width` + `flashing`.
public struct BorderFrame: Sendable, Equatable {
    public let color: BorderColor
    public let width: Double
    public let flashing: Bool

    public init(color: BorderColor, width: Double, flashing: Bool) {
        self.color = color
        self.width = width
        self.flashing = flashing
    }
}

/// Resolve the shared border animator for wall-clock `now`. PURE — no timer, no
/// mutable state, no AppKit. Reconciles the (formerly duplicated) halo/facet
/// `BorderFX.color` + `.width`:
///   * width: breathing raised-cosine min↔max over the cycle phase when an
///     effect is active and both bounds are set with max > min, else the fixed
///     `baseWidth`; `+1.5` while flashing.
///   * color: flash blink → rainbow hue → `cycleColors` blend → steady → off
///     (the same 5-way priority as the old `BorderFX.color`).
/// `phase` derives from `now` (`(now / cycleSeconds) mod 1`) instead of an
/// accumulator — frame-rate-independent and stateless (the cycle is phase-offset
/// invariant in appearance, so an absolute clock animates identically). `flash`
/// is the value rolled by `rollFlash`; pass the app's stored cell (nil = none).
public func resolveBorder(
    spec: EffectSpec?,
    baseWidth: Double,
    minWidth: Double?,
    maxWidth: Double?,
    cycleSeconds: Double,
    cycleColors: Bool,
    now: Double,
    flash: FlashState?
) -> BorderFrame {
    let flashIdx = flash?.index(now: now)
    let flashing = flashIdx != nil
    let phase = (now / max(1, cycleSeconds)).truncatingRemainder(dividingBy: 1)

    // Width — breathing needs an active effect + both bounds with max > min.
    var width = baseWidth
    if spec != nil, let lo = minWidth, let hi = maxWidth, hi > lo {
        let pulse = (1 - cos(2 * Double.pi * phase)) / 2
        width = lo + (hi - lo) * pulse
    }
    if flashing { width += 1.5 }

    // Color — same 5-way priority as the old `BorderFX.color`.
    let color: BorderColor
    if let idx = flashIdx, let f = flash {
        let h = HexColor(f.seq[idx]); color = .rgb(r: h.r, g: h.g, b: h.b)
    } else if let fx = spec {
        if fx.cycles {
            color = .rainbowHue(phase)
        } else if cycleColors, !fx.flash.isEmpty {
            let c = blendThrough(fx.flash, at: phase)
            color = .rgb(r: c.r, g: c.g, b: c.b)
        } else {
            let h = HexColor(fx.steady); color = .rgb(r: h.r, g: h.g, b: h.b)
        }
    } else {
        color = .off
    }

    return BorderFrame(color: color, width: width, flashing: flashing)
}

// MARK: - Line-pets (pure identity)
//
// (`LinePet` + `canonicalLinePetNames` live in `Palette` since 0.6.0 —
// pure identity a no-AppKit Core can persist / validate against without
// linking this module — and are re-exported here. The drawing below
// stays Effects-side behind `#if canImport(AppKit)`.)

// MARK: - Animated palette (AppKit)

#if canImport(AppKit)

/// A point-in-time animated frame: the spec's primary/secondary rotated
/// to `phase`, with background/foreground/muted held steady so the UI
/// stays usable. Returns resolved `NSColor`s ready to install as the live
/// `pal`. `@MainActor` because `NSColor` isn't `Sendable`.
@MainActor
public struct AnimatedFrame {
    public let primary: NSColor
    public let secondary: NSColor
    /// selection keyed to the LIVE animated primary, at the theme's own
    /// selection alpha — the authored value (rainbow = 0.22) or the family
    /// default 0.18, matching PaletteKit's static derive so the selected-
    /// row wash doesn't jump when animation engages.
    public let selection: NSColor
}

/// Cycle a theme to `phase` (0…1). A `cycles` effect (rainbow) rotates
/// the accent through the full spectrum; a flash effect
/// (neon/cyber/vapor/kawaii/chomp) cycles through that effect's own
/// flash palette (keeping its identity). Resolves the effect by name
/// through the built-in catalog (`borderEffectFor`). Returns nil for a
/// non-animatable theme. `secondary` trails half a turn. Generalizes
/// facet's `animatedPalette`.
///
/// Callers blend the result into a fresh `ResolvedPalette` (or assign
/// the three fields onto a copy) — Effects deliberately doesn't depend
/// on PaletteKit, so it returns the animated atoms, not a full
/// `ResolvedPalette`, keeping the layer graph acyclic.
@MainActor
public func animatedPalette(theme name: String, at phase: CGFloat) -> AnimatedFrame? {
    guard let fx = borderEffectFor(name) else { return nil }
    let h = phase - floor(phase)
    let h2 = (h + 0.5).truncatingRemainder(dividingBy: 1)

    func ns(_ t: (r: Double, g: Double, b: Double)) -> NSColor {
        NSColor(srgbRed: CGFloat(t.r), green: CGFloat(t.g),
                blue: CGFloat(t.b), alpha: 1)
    }

    let primary: NSColor, secondary: NSColor
    if fx.cycles {
        primary   = NSColor(hue: h,  saturation: 0.95, brightness: 1, alpha: 1)
        secondary = NSColor(hue: h2, saturation: 0.95, brightness: 1, alpha: 1)
    } else if !fx.flash.isEmpty {
        primary   = ns(blendThrough(fx.flash, at: Double(h)))
        secondary = ns(blendThrough(fx.flash, at: Double(h2)))
    } else {
        return nil
    }
    // Honor the theme's AUTHORED selection alpha (rainbow explicitly sets
    // 0.22); otherwise the family default 0.18 — same value PaletteKit's
    // static resolve derives, so the wash doesn't shift 0.18→0.22 the
    // instant the animator engages.
    let selAlpha = paletteFor(name).selection.map { CGFloat($0.alpha) } ?? 0.18
    return AnimatedFrame(primary: primary, secondary: secondary,
                         selection: primary.withAlphaComponent(selAlpha))
}

// MARK: - HexColor → NSColor bridge

public extension NSColor {
    /// Materialize a pure `HexColor` (rgb + alpha) as an sRGB `NSColor`.
    /// Lives HERE — not PaletteKit — so an Effects-only consumer (halo)
    /// can bridge `parseColorToken` output without linking PaletteKit.
    /// Deliberately a DISTINCT signature from PaletteKit's
    /// `NSColor(hex: UInt32)` so importing both modules stays unambiguous.
    convenience init(_ hex: HexColor) {
        self.init(srgbRed: CGFloat(hex.r), green: CGFloat(hex.g),
                  blue: CGFloat(hex.b), alpha: CGFloat(hex.alpha))
    }
}

// MARK: - Line-pets (AppKit drawing)

/// Draw `pets` walking `rect`'s perimeter at wall-clock `now`, scaled by
/// `scale`, chasing each other at `speed` pt/s. The caller owns the view,
/// the redraw timer, and `rect` (in its own coordinate space — the walk
/// is coordinate-agnostic; pass a NON-flipped rect so "top" reads as
/// `maxY`). Generalizes wand's `drawCardLinePets` / `TomePetsView` into
/// ONE shared shape for every surface (facet tree, halo ring, wand cards).
/// Each pet's silhouette colours are baked in (theme-agnostic).
///
/// `chaseGap` is the trailing distance between consecutive pets, in
/// points (already scaled — pass `28 * scale` etc.). `nil` keeps the
/// default `24 * scale` (~2× ghost width); wand's tome card runs a
/// slightly looser 28-pt chase, which this preserves through the dedup.
@MainActor
public func drawLinePets(_ pets: [LinePet], on rect: CGRect,
                         now: CFTimeInterval, scale: CGFloat = 1,
                         speed: CGFloat = 120, chaseGap: CGFloat? = nil) {
    guard rect.width > 0, rect.height > 0, !pets.isEmpty, speed > 0 else { return }
    let perim = 2 * (rect.width + rect.height)
    let leader = CGFloat(now).truncatingRemainder(dividingBy: perim / speed) * speed
    let chaseGap: CGFloat = chaseGap ?? 24 * scale   // ~2× ghost width
    for (i, pet) in pets.enumerated() {
        var pos = leader - CGFloat(i) * chaseGap
        pos = pos.truncatingRemainder(dividingBy: perim)
        if pos < 0 { pos += perim }
        let (px, py, rot) = linePetPosition(on: rect, distance: pos)
        NSGraphicsContext.saveGraphicsState()
        let tx = NSAffineTransform()
        tx.translateX(by: px, yBy: py)
        switch pet {
        case .chomp:
            // Pac-Man TUMBLES with the lap so its mouth opens along travel.
            tx.rotate(byRadians: rot)
            tx.concat()
            drawChompPet(now: now, scale: scale)
        case .ghost:
            // The ghost stays UPRIGHT (#12 Ph3) — it does NOT tumble with the
            // lap (no rotation). Only its eyes track travel, the cardinal gaze
            // picked from the tangent (`+x→right … +y→up`, the y-up rect frame).
            tx.concat()
            let look = GhostLook.facing(dx: Double(cos(rot)), dy: Double(sin(rot)))
            drawGhostPet(now: now, scale: scale, look: look)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Draw a Pac-Man — or, when `valid` is false, a panicking Blinky ghost —
/// walking the ARBITRARY polyline `path` at wall-clock `now`: the #12 Ph3
/// "PathPet", the open-path counterpart to `drawLinePets`' closed perimeter lap.
/// A head cursor advances `speed` pt/s along the arc length (looping at the end);
/// the pet FOLLOWS `faceLag` points behind it (`markAtArcLength(head − faceLag)`,
/// which clamps a negative offset to the start), so the head leads and the face
/// chases — wand's Chomp gap. Orientation comes from the local tangent:
///   * pac TUMBLES (rotates) so its mouth opens along travel — the mouth flaps
///     via `Motion.frameStep`, the same discrete swap the line-pets use;
///   * the ghost stays UPRIGHT — only its eyes swivel to the travel cardinal
///     (`GhostLook.facing`) — and PANICS with a 2-D `dampedSine` buzz (a gesture
///     that matched no rule).
/// `path` is in the caller's space; host in a NON-flipped (y-up) view so "+y up"
/// matches `GhostLook.facing` and the sprites' internal flip (the `drawLinePets`
/// convention). `showGuide` strokes a faint rounded trail so the path reads
/// before the Ph4 pellets/corridor exist. The caller owns the view + redraw
/// clock; `now` is injected (deterministic freeze / XCTest).
@MainActor
public func drawChompPath(_ path: [CGPoint], now: CFTimeInterval, valid: Bool = true,
                          scale: CGFloat = 1, speed: CGFloat = 60,
                          faceLag: CGFloat = 0, showGuide: Bool = true) {
    guard path.count >= 2, speed > 0 else { return }
    let total = polylineLength(path)   // arc length = the loop period (in points)
    guard total > 0 else { return }

    if showGuide {
        let guide = nsBezierPath(roundedCornerPath(path, radius: Double(6 * scale)),
                                 lineWidth: 1.5 * scale)
        NSColor(HexColor(SpriteColor.pupilBlue)).withAlphaComponent(0.22).setStroke()
        guide.stroke()
    }

    // Head marches the arc length and loops; the pet trails it by `faceLag`. The
    // pure cursor math lives in `pathPetCursors` (CI-guardable; a negative `now`
    // wraps forward like `Motion.frameStep`, not into a clamped dead-zone).
    // markAtArcLength then clamps a negative `petDist` to the start (head leads).
    let (headDist, petDist) = pathPetCursors(total: total, speed: Double(speed),
                                             now: Double(now), faceLag: Double(faceLag))

    // The chased head — a small glowing pellet-dot (only when valid + lagging; a
    // mismatch has no target). Makes the faceLag gap legible before pellets (Ph4).
    if valid, faceLag > 0, let head = markAtArcLength(path, distance: headDist) {
        let r: CGFloat = 2.5 * scale
        let yellow = NSColor(HexColor(SpriteColor.pacYellow))
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow(); glow.shadowColor = yellow
        glow.shadowBlurRadius = 4 * scale; glow.shadowOffset = .zero; glow.set()
        yellow.setFill()
        NSBezierPath(ovalIn: CGRect(x: CGFloat(head.point.x) - r, y: CGFloat(head.point.y) - r,
                                    width: 2 * r, height: 2 * r)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    guard let mark = markAtArcLength(path, distance: petDist) else { return }
    let px = CGFloat(mark.point.x), py = CGFloat(mark.point.y)

    NSGraphicsContext.saveGraphicsState()
    let tx = NSAffineTransform()
    if valid {
        // Pac TUMBLES so the mouth (canonical +x) opens along travel.
        tx.translateX(by: px, yBy: py)
        tx.rotate(byRadians: atan2(CGFloat(mark.tangent.y), CGFloat(mark.tangent.x)))
        tx.concat()
        drawChompPet(now: now, scale: scale)
    } else {
        // Ghost stays UPRIGHT (no rotate) and PANICS — a sustained 2-D buzz
        // (co-prime 6/7, decay 0 so it doesn't fade), eyes on the travel cardinal.
        var pp = (Double(now) * pathPetPanicHz).truncatingRemainder(dividingBy: 1)
        if pp < 0 { pp += 1 }   // fold a negative `now` forward (frameStep's convention)
        let amp = 1.6 * scale
        let jx = CGFloat(ThemedTransition.dampedSine(pp, frequency: 6, decay: 0)) * amp
        let jy = CGFloat(ThemedTransition.dampedSine(pp, frequency: 7, decay: 0)) * amp
        tx.translateX(by: px + jx, yBy: py + jy)
        tx.concat()
        drawGhostPet(now: now, scale: scale,
                     look: GhostLook.facing(dx: mark.tangent.x, dy: mark.tangent.y))
    }
    NSGraphicsContext.restoreGraphicsState()
}

/// Panic-buzz cycles/sec for the mismatch ghost in `drawChompPath` — the rate the
/// 2-D `dampedSine` tremble repeats. Named so the prism card and any future
/// corridor read the same shake speed.
private let pathPetPanicHz: Double = 1.5

/// Walk `rect`'s perimeter linearly (top → right → bottom → left) and
/// return the centre + travel-direction rotation at `distance`. Each
/// pet's draw code stays in a canonical "facing-right" frame; the
/// transform supplies the lap-aware orientation.
private func linePetPosition(on r: CGRect, distance t: CGFloat)
    -> (x: CGFloat, y: CGFloat, rot: CGFloat) {
    let topLen = r.width, rightLen = r.height, bottomLen = r.width
    if t < topLen {
        return (r.minX + t, r.maxY, 0)
    } else if t < topLen + rightLen {
        return (r.maxX, r.maxY - (t - topLen), -.pi / 2)
    } else if t < topLen + rightLen + bottomLen {
        return (r.maxX - (t - topLen - rightLen), r.minY, .pi)
    } else {
        return (r.minX, r.minY + (t - topLen - rightLen - bottomLen), .pi / 2)
    }
}

// Pixel line-pet metrics (#12 Ph2) — sized so the unified arcade sprites keep
// the SAME on-screen footprint the smooth pets had (no layout shift for the
// apps that already place line-pets). `scale` multiplies these per surface.
private let chompFaceCells = 13                  // odd ⇒ the mouth wedge centres
private let chompFaceFootprint: CGFloat = 14     // pt @ scale 1 (old smooth Ø)
private let ghostFootprint: CGFloat = 14         // pt @ scale 1 (sprite is 14×14)

/// Yellow PIXEL Pac-Man — the chomp line-pet, unified to the arcade sprite in
/// #12 Ph2 (was a smooth cosine wedge; see `drawChompPetSmooth`, the gate
/// fallback). The mouth SNAPS through `chompMouthFrames` at `chompMouthHz` via
/// `Motion.frameStep` (a discrete swap — the retro feel). The wedge is y-
/// symmetric (opens toward +x = travel, the caller having rotated by the lap
/// tangent), so no flip is needed; just centre it on the transform origin.
/// `@MainActor` (it calls the `@MainActor` `drawPacMan` blitter; the only caller
/// is the `@MainActor` `drawLinePets`).
@MainActor
private func drawChompPet(now: CFTimeInterval, scale: CGFloat) {
    let cell = scale * chompFaceFootprint / CGFloat(chompFaceCells)
    let phase = ThemedTransition.frameStep(now: Double(now), hz: chompMouthHz,
                                           frames: chompMouthFrames)
    let w = CGFloat(chompFaceCells) * cell
    drawPacMan(diameterCells: chompFaceCells, mouthHalfRad: mouthHalfRad(phase: phase),
               cell: cell, at: CGPoint(x: -w / 2, y: -w / 2))
}

/// The pre-#12-Ph2 SMOOTH chomp wedge (cosine mouth on a ~0.25 s cycle). Kept
/// as the verification-gate fallback: if the pixel sprites read poorly at the
/// small line-pet size, flip `drawLinePets`' `.chomp` case back to this. Not
/// called by default.
private func drawChompPetSmooth(now: CFTimeInterval, scale: CGFloat) {
    let r: CGFloat = 7 * scale
    let chompPhase = 0.5 - 0.5 * cos(now * (2 * .pi / 0.25))
    let openRad = chompPhase * (35.0 * .pi / 180.0)
    let yellow = NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
    let p = NSBezierPath()
    p.move(to: .zero)
    p.appendArc(withCenter: .zero, radius: r,
                startAngle: CGFloat(openRad * 180 / .pi),
                endAngle: CGFloat(360 - openRad * 180 / .pi),
                clockwise: false)
    p.close()
    yellow.setFill(); p.fill()
    NSColor.black.withAlphaComponent(0.35).setStroke()
    p.lineWidth = 0.5; p.stroke()
}

/// Red Blinky PIXEL ghost — the chomp line-pet's companion, unified in #12 Ph2
/// and made UPRIGHT + directional in #12 Ph3 (was a smooth bezier dome; see
/// `drawGhostPetSmooth`, the gate fallback). The 2-pose skirt WADDLES via
/// `Motion.frameStep` (poseA⇄poseB at `CanonicalSprite.waddleHz`). The ghost does
/// NOT tumble with the lap — the caller leaves the context UNROTATED and passes
/// `look` (the travel cardinal), so the body stays vertical and only the pupils
/// swivel (`ghostFrames(look:)`). The sprite is FLIPPED so row 0 (the dome) sits
/// at the TOP of the local y-up line-pet frame, then centred on the origin.
/// `@MainActor` (it calls the `@MainActor` `drawPixelSprite` blitter; only caller
/// is `drawLinePets`).
@MainActor
private func drawGhostPet(now: CFTimeInterval, scale: CGFloat, look: GhostLook) {
    let sprite = ThemedTransition.frameStep(now: Double(now), hz: CanonicalSprite.waddleHz,
                                            frames: CanonicalSprite.ghostFrames(look: look))
    let cell = scale * ghostFootprint / CGFloat(sprite.height)
    let w = CGFloat(sprite.width) * cell
    let h = CGFloat(sprite.height) * cell
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: -w / 2, yBy: h / 2)   // top-left of the centred sprite (y-up)
    t.scaleX(by: 1, yBy: -1)               // row 0 → top: rows now grow DOWNWARD
    t.concat()
    drawPixelSprite(sprite, cell: cell, at: .zero)
    NSGraphicsContext.restoreGraphicsState()
}

/// The pre-#12-Ph2 SMOOTH Blinky ghost (bezier dome + 3-wave skirt + eyes along
/// travel). Kept as the verification-gate fallback (flip `drawLinePets`'
/// `.ghost` case back to this if the pixel sprite reads poorly at the small
/// line-pet size). Not called by default.
private func drawGhostPetSmooth(now: CFTimeInterval, scale: CGFloat) {
    let w: CGFloat = 14 * scale
    let h: CGFloat = 16 * scale
    let bob = CGFloat(sin(now * (2 * .pi / 0.4))) * 0.6 * scale
    let halfW = w / 2
    let halfH = h / 2
    let red = NSColor(calibratedRed: 1.0, green: 0.0, blue: 0.10, alpha: 1.0)
    let body = NSBezierPath()
    body.move(to: CGPoint(x: -halfW, y: 0))
    body.appendArc(withCenter: CGPoint(x: 0, y: 0), radius: halfW,
                   startAngle: 180, endAngle: 0, clockwise: false)
    body.line(to: CGPoint(x: halfW, y: -halfH + bob))
    let segments = 3
    let segW = w / CGFloat(segments)
    let waveDepth: CGFloat = 1.5 * scale
    for i in (0..<segments).reversed() {
        let startX = -halfW + CGFloat(i + 1) * segW
        let endX = -halfW + CGFloat(i) * segW
        let midX = (startX + endX) / 2
        body.curve(to: CGPoint(x: endX, y: -halfH + bob),
                   controlPoint1: CGPoint(x: midX, y: -halfH - waveDepth - bob),
                   controlPoint2: CGPoint(x: midX, y: -halfH - waveDepth - bob))
    }
    body.line(to: CGPoint(x: -halfW, y: 0))
    body.close()
    red.setFill(); body.fill()
    NSColor.black.withAlphaComponent(0.35).setStroke()
    body.lineWidth = 0.5 * scale; body.stroke()
    let eyeR: CGFloat = 2.0 * scale
    let pupilR: CGFloat = 1.0 * scale
    let eyeY: CGFloat = halfH * 0.35
    let eyeDx: CGFloat = 2.6 * scale
    let pupilOffset: CGFloat = 0.7 * scale
    let eyeShift: CGFloat = 1.0 * scale
    for sign in [-1.0, 1.0] {
        let cx = CGFloat(sign) * eyeDx + eyeShift
        let sclera = NSBezierPath(ovalIn: CGRect(x: cx - eyeR, y: eyeY - eyeR,
                                                 width: 2 * eyeR, height: 2 * eyeR))
        NSColor.white.setFill(); sclera.fill()
        let pupil = NSBezierPath(ovalIn: CGRect(x: cx - pupilR + pupilOffset, y: eyeY - pupilR,
                                                width: 2 * pupilR, height: 2 * pupilR))
        NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.95, alpha: 1.0).setFill()
        pupil.fill()
    }
}

#endif
