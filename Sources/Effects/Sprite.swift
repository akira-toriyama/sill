// Sprite — the AppKit blitter + canonical arcade sprites for the chomp
// (Pac-Man) look. The pure pixel mechanism lives in `PixelArt` (`PixelSprite`,
// `pacManCells`, `ScaleTier`); this is its draw side, next to the line-pets and
// the ink-splatter decal — same two-tier shape as the rest of Effects:
//
//   * pure tier — the INTRINSIC arcade colours + the canonical sprite grids
//     (cherry / ghost), authored as `PixelSprite` data. `Sendable`, no AppKit,
//     XCTest-able (dimensions assert against the documented grid).
//   * AppKit tier — `drawPixelSprite` / `drawPacMan` fill cell rects with
//     ANTIALIAS OFF for hard pixel edges (the spec's "sprites are not
//     anti-aliased"). Gated by `#if canImport(AppKit)`.
//
// COLOUR is intrinsic, NOT theme-driven: chomp is a self-contained arcade look
// (always yellow / blue / red / black), reconciled to `ThemeSpec.chomp`'s role
// hues where one exists (pac-yellow = primary, ghost-red = error, pupil-blue =
// secondary) and baked otherwise (white, cherry, brown). This is deliberate —
// it mirrors how `drawChompPet` / `drawGhostPet` already bake their hues.
//
// CLOCK is injected (`now: Double`) by the caller everywhere it animates; Ph1
// sprites are static (a fixed mouth phase), so nothing here reads a clock yet.

import Foundation
import Palette    // HexColor (also re-exported by Effects)
import PixelArt   // PixelSprite, pacManCells (the pure pixel mechanism)

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Intrinsic arcade colours (pure, 0xRRGGBB)

/// The baked colours for the canonical chomp sprites. Pure constants so XCTest
/// can lock them. Where a chomp role colour exists in `ThemeSpec.chomp` the
/// value MATCHES it (so the arcade look stays coherent with the theme); the
/// rest are baked arcade hues with no Palette home.
public enum SpriteColor {
    /// Pac-Man body — `= ThemeSpec.chomp.primary` (arcade yellow).
    public static let pacYellow: UInt32 = 0xFFEA00
    /// Ghost body — `= ThemeSpec.chomp.error` (arcade red, Blinky).
    public static let ghostRed:  UInt32 = 0xFF0000
    /// Ghost eye white — baked.
    public static let eyeWhite:  UInt32 = 0xFFFFFF
    /// Ghost pupil — `= ThemeSpec.chomp.secondary` (the wall blue).
    public static let pupilBlue: UInt32 = 0x2121FF
    /// Cherry body — baked (arcade cherry red).
    public static let cherryRed: UInt32 = 0xFF0000
    /// Cherry stem — baked saddle brown.
    public static let stemBrown: UInt32 = 0x8B5A2B
    /// Cherry leaf — baked green.
    public static let leafGreen: UInt32 = 0x3AA655
    /// Specular highlight — baked white.
    public static let highlight: UInt32 = 0xFFFFFF
}

// MARK: - Canonical sprites (pure PixelSprite grids)

/// The authored arcade decals for the chomp look. Pure grids — the draw side
/// scales (`ScaleTier`) + blits them. The Pac-Man FACE is geometry
/// (`pacManCells` / `drawPacMan`, so the mouth can open by phase), so only the
/// cherry + ghost are literal sprites here. Recognisable retro art, NOT a
/// pixel-perfect trace of wand's PNGs (the spec grants interpretation latitude).
public enum CanonicalSprite {

    /// 12×13 cherry: a pair of red orbs (white specular), brown stems meeting at
    /// a green leaf.
    public static let cherry = PixelSprite(rows: [
        ".......s....",
        "....gggs....",
        "...gg..s....",
        "......s.s...",
        ".....s...s..",
        "....s....s..",
        "...s.....s..",
        "..rrr...rrr.",
        ".rrrrr.rrrrr",
        ".rwrrr.rwrrr",
        ".rrrrr.rrrrr",
        ".rrrrr.rrrrr",
        "..rrr...rrr.",
    ], palette: [
        "r": SpriteColor.cherryRed,
        "w": SpriteColor.highlight,
        "s": SpriteColor.stemBrown,
        "g": SpriteColor.leafGreen,
    ])

    /// 14×14 ghost (Blinky pose A): red dome, two white eyes with blue pupils
    /// looking right (travel direction), a 4-point waddling skirt.
    public static let ghost = PixelSprite(rows: ghostRows(feet: feetA),
                                          palette: ghostPalette)

    /// 14×14 ghost — skirt pose B (feet phase-shifted), the other half of the
    /// 2-frame waddle (`Motion.frameStep` alternates them in Ph2).
    public static let ghostAlt = PixelSprite(rows: ghostRows(feet: feetB),
                                             palette: ghostPalette)

    /// The two skirt poses in waddle order — `Motion.frameStep` swaps between
    /// them for the 2-frame leg shuffle. Named so the line-pet (Effects) and the
    /// prism card drive the SAME poses from one place.
    public static let waddleFrames: [PixelSprite] = [ghost, ghostAlt]

    /// Complete ghost⇄ghostAlt cycles per second — deliberately SLOWER than the
    /// 5 Hz mouth (`chompMouthHz`): the legs waddle, they don't chatter. One
    /// pass takes 1/1.5 s; `frameStep` swaps the pose `1.5 · 2` = 3 times/sec.
    public static let waddleHz: Double = 1.5

    // The ghost is identical above the skirt; only the two foot rows differ, so
    // both poses share one body + palette (no drift between them).
    private static let ghostPalette: [Character: UInt32] = [
        "r": SpriteColor.ghostRed,
        "w": SpriteColor.eyeWhite,
        "b": SpriteColor.pupilBlue,
    ]
    // Canonical arcade Blinky, traced from the reference (全身.gif): a rounded
    // dome, BIG eyes (4-wide white with a 2×2 pupil offset toward the look
    // direction — here right/+x = travel), and the classic 2-pose foot shuffle.
    private static let feetA = ["rr.rrr..rrr.rr", "r...rr..rr...r"]
    private static let feetB = ["rrrr.rrrr.rrrr", ".rr...rr...rr."]
    private static func ghostRows(feet: [String]) -> [String] {
        [
            ".....rrrr.....",
            "...rrrrrrrr...",
            "..rrrrrrrrrr..",
            ".rrrwwrrrrwwr.",
            ".rrwwwwrrwwww.",
            ".rrwwbbrrwwbb.",
            "rrrwwbbrrwwbbr",
            "rrrrwwrrrrwwrr",
            "rrrrrrrrrrrrrr",
            "rrrrrrrrrrrrrr",
            "rrrrrrrrrrrrrr",
            "rrrrrrrrrrrrrr",
        ] + feet
    }
}

// MARK: - AppKit draw helpers (the drawInkSplatter / drawLinePets analog)

#if canImport(AppKit)

/// Blit a `PixelSprite` into the CURRENT `NSGraphicsContext`: each opaque cell
/// is a filled `cell × cell` rect with ANTIALIAS OFF (crisp pixel edges). The
/// sprite's top-left sits at `at`, and row 0 grows DOWNWARD — host in an
/// `isFlipped` view so the grid reads top-to-bottom (the `drawParticles` +y-down
/// convention). `color` (optional) OVERRIDES every cell's intrinsic colour
/// (single-tint mode); pass nil to honour each cell's own `0xRRGGBB`.
@MainActor
public func drawPixelSprite(_ sprite: PixelSprite, cell: CGFloat,
                            at origin: CGPoint, color: UInt32? = nil) {
    let ctx = NSGraphicsContext.current
    let savedAA = ctx?.shouldAntialias ?? true
    ctx?.shouldAntialias = false
    defer { ctx?.shouldAntialias = savedAA }
    for c in sprite.cells() {
        NSColor(HexColor(color ?? c.color)).setFill()
        NSRect(x: origin.x + CGFloat(c.col) * cell,
               y: origin.y + CGFloat(c.row) * cell,
               width: cell, height: cell).fill()
    }
}

/// Blit a Pac-Man face (circle-minus-mouth) straight from `pacManCells`, tinted
/// pac-yellow — a convenience over wrapping the geometry in a `PixelSprite`.
/// Same antialias-off crisp-cell rule as `drawPixelSprite`; the mouth opens to
/// the RIGHT, so rotate the context by the travel tangent before calling for a
/// face that follows a path. `at` is the grid's top-left in an `isFlipped` view.
@MainActor
public func drawPacMan(diameterCells d: Int, mouthHalfRad: Double,
                       cell: CGFloat, at origin: CGPoint,
                       color: UInt32 = SpriteColor.pacYellow) {
    let ctx = NSGraphicsContext.current
    let savedAA = ctx?.shouldAntialias ?? true
    ctx?.shouldAntialias = false
    defer { ctx?.shouldAntialias = savedAA }
    NSColor(HexColor(color)).setFill()
    for p in pacManCells(diameterCells: d, mouthHalfRad: mouthHalfRad) {
        NSRect(x: origin.x + CGFloat(p.col) * cell,
               y: origin.y + CGFloat(p.row) * cell,
               width: cell, height: cell).fill()
    }
}

#endif
