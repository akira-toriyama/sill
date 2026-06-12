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
    /// cross-app `chomp` theme; facet's tree, halo's ring, and wand's
    /// trail each draw their OWN signature motion over this shared spec.
    /// Not a `cycles` effect — it blinks a FIXED arcade palette rather
    /// than rotating the spectrum.
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
/// built-in each call (matches facet).
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

// MARK: - Line-pets (pure identity)

/// One of the small arcade "pets" that walk a surface's outline — a
/// shared decoration across facet's tree, halo's ring, and wand's cast /
/// tome cards. Multiple pets chase each other around the rim in array
/// order (first leads, the rest trail at a fixed gap). Theme-AGNOSTIC:
/// each pet's colours are baked into its silhouette, so it reads the
/// same under any theme. The drawing lives behind `#if canImport(AppKit)`
/// (`drawLinePets`); this identity enum is pure so configs can persist /
/// validate against it with no AppKit.
public enum LinePet: String, Sendable, Hashable, CaseIterable {
    /// Classic yellow chomping wedge.
    case chomp
    /// Red Blinky-style ghost — dome top, two eyes, scalloped skirt.
    case ghost
}

/// Canonical pet names accepted by a `line-pets` config list. Single
/// source of truth so a consumer can drop + report typos.
public let canonicalLinePetNames: [String] = LinePet.allCases.map(\.rawValue)

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

// MARK: - Line-pets (AppKit drawing)

/// Draw `pets` walking `rect`'s perimeter at wall-clock `now`, scaled by
/// `scale`, chasing each other at `speed` pt/s. The caller owns the view,
/// the redraw timer, and `rect` (in its own coordinate space — the walk
/// is coordinate-agnostic; pass a NON-flipped rect so "top" reads as
/// `maxY`). Generalizes wand's `drawCardLinePets` / `TomePetsView` into
/// ONE shared shape for every surface (facet tree, halo ring, wand cards).
/// Each pet's silhouette colours are baked in (theme-agnostic).
@MainActor
public func drawLinePets(_ pets: [LinePet], on rect: CGRect,
                         now: CFTimeInterval, scale: CGFloat = 1,
                         speed: CGFloat = 120) {
    guard rect.width > 0, rect.height > 0, !pets.isEmpty, speed > 0 else { return }
    let perim = 2 * (rect.width + rect.height)
    let leader = CGFloat(now).truncatingRemainder(dividingBy: perim / speed) * speed
    let chaseGap: CGFloat = 24 * scale   // ~2× ghost width
    for (i, pet) in pets.enumerated() {
        var pos = leader - CGFloat(i) * chaseGap
        pos = pos.truncatingRemainder(dividingBy: perim)
        if pos < 0 { pos += perim }
        let (px, py, rot) = linePetPosition(on: rect, distance: pos)
        NSGraphicsContext.saveGraphicsState()
        let tx = NSAffineTransform()
        tx.translateX(by: px, yBy: py)
        tx.rotate(byRadians: rot)
        tx.concat()
        switch pet {
        case .chomp: drawChompPet(now: now, scale: scale)
        case .ghost: drawGhostPet(now: now, scale: scale)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

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

/// Yellow chomp wedge with the mouth opening / closing on a ~0.25 s
/// cycle, centred on the current transform origin. `scale` keeps it
/// proportional to the host surface.
private func drawChompPet(now: CFTimeInterval, scale: CGFloat) {
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

/// Red Blinky-style ghost: dome + 3-wave skirt + eyes pointing along
/// travel direction, centred on the current transform origin.
private func drawGhostPet(now: CFTimeInterval, scale: CGFloat) {
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
