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

// MARK: - Ghost gaze (directional eyes, #12 Ph3)

/// Which way a Blinky ghost's eyes look — the four cardinals of its travel. The
/// UPRIGHT directional ghost (the line-pet no longer rotates with the lap tangent)
/// keeps its body fixed and only swivels the pupils. A small draw-side enum, NOT
/// the `Gesture.Direction` recogniser — `Effects` owns no gesture dependency, and
/// "which way the eyes point" is a render concern, not gesture recognition.
public enum GhostLook: Sendable, Hashable, CaseIterable {
    case up, right, down, left

    /// Snap a travel vector to the nearest cardinal gaze, in the line-pet's Y-UP
    /// frame (`drawLinePets` walks a NON-flipped rect, so +y = up): +x→right,
    /// −x→left, +y→up, −y→down. The dominant axis wins; an exact 45° tie breaks
    /// to HORIZONTAL so a diagonal tangent never flickers the eyes up↔down.
    public static func facing(dx: Double, dy: Double) -> GhostLook {
        if abs(dx) >= abs(dy) { return dx >= 0 ? .right : .left }
        return dy >= 0 ? .up : .down
    }
}

/// The two skirt poses of the ghost's leg shuffle — `Motion.frameStep` alternates
/// them for the 2-frame waddle.
public enum GhostFeet: Sendable, Hashable, CaseIterable { case a, b }

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

    /// 14×14 ghost (Blinky pose A): red dome, two 4-wide white eyes with blue
    /// pupils looking RIGHT (the Ph2 travel direction = +x), a waddling skirt.
    /// Built via `ghostSprite` so this literal and the Ph3 directional builder
    /// share ONE grid (no drift).
    public static let ghost = ghostSprite(feet: .a, look: .right)

    /// 14×14 ghost — skirt pose B (feet phase-shifted), the other half of the
    /// 2-frame waddle (`Motion.frameStep` alternates them in Ph2).
    public static let ghostAlt = ghostSprite(feet: .b, look: .right)

    /// The two RIGHT-looking skirt poses in waddle order — `Motion.frameStep`
    /// swaps between them for the 2-frame leg shuffle. The line-pet (Effects) and
    /// the prism static card drive the SAME poses from one place. For a ghost
    /// whose eyes track travel (the upright directional line-pet), use
    /// `ghostFrames(look:)`.
    public static let waddleFrames: [PixelSprite] = [ghost, ghostAlt]

    /// Complete ghost⇄ghostAlt cycles per second — deliberately SLOWER than the
    /// 5 Hz mouth (`chompMouthHz`): the legs waddle, they don't chatter. One
    /// pass takes 1/1.5 s; `frameStep` swaps the pose `1.5 · 2` = 3 times/sec.
    public static let waddleHz: Double = 1.5

    /// The 2-pose waddle for a ghost whose EYES face `look` (#12 Ph3). Same leg
    /// shuffle as `waddleFrames`, now look-aware — `Motion.frameStep` drives it.
    /// The upright directional line-pet picks `look` from its travel tangent via
    /// `GhostLook.facing`. The four pairs are CACHED statics (like `waddleFrames`)
    /// so the 60 Hz draw path reuses them instead of rebuilding sprites per frame.
    public static func ghostFrames(look: GhostLook) -> [PixelSprite] {
        switch look {
        case .up:    return upWaddle
        case .right: return waddleFrames     // the Ph2 right-look pair, already cached
        case .down:  return downWaddle
        case .left:  return leftWaddle
        }
    }
    private static let upWaddle   = [ghostSprite(feet: .a, look: .up),   ghostSprite(feet: .b, look: .up)]
    private static let downWaddle = [ghostSprite(feet: .a, look: .down), ghostSprite(feet: .b, look: .down)]
    private static let leftWaddle = [ghostSprite(feet: .a, look: .left), ghostSprite(feet: .b, look: .left)]

    /// Assemble a 14×14 Blinky for a gaze + skirt pose: `lookRows` is the head
    /// (rows 0–11) with the EYES translated toward `look`; `feetRows` appends the
    /// 2-pose shuffle (rows 12–13). The SINGLE source of truth for the ghost grid.
    public static func ghostSprite(feet: GhostFeet, look: GhostLook) -> PixelSprite {
        PixelSprite(rows: lookRows(look) + feetRows(feet), palette: ghostPalette)
    }

    private static let ghostPalette: [Character: UInt32] = [
        "r": SpriteColor.ghostRed,
        "w": SpriteColor.eyeWhite,
        "b": SpriteColor.pupilBlue,
    ]
    private static let feetA = ["rr.rrr..rrr.rr", "r...rr..rr...r"]
    private static let feetB = ["rrrr.rrrr.rrrr", ".rr...rr...rr."]
    private static func feetRows(_ feet: GhostFeet) -> [String] {
        switch feet { case .a: return feetA; case .b: return feetB }
    }

    /// The head (rows 0–11) per gaze, tuned with the user against the reference
    /// 目.gif (2026-06-22). The red head SILHOUETTE is identical across all four
    /// looks (the dome's round shape never changes — rows 3–5 are 12 wide, rows 6+
    /// the full 14); only the eye content moves. `left`/`right` sit the pupils at
    /// the eyes' outer edge, vertically centred (white ABOVE and BELOW, so the gaze
    /// reads horizontal, not diagonal); `up`/`down` are vertical mirrors — the
    /// pupils ride the white's top / bottom edge, white filling the other end.
    /// `right` is the canonical forward pose, so `ghost`/`ghostAlt` are its two
    /// skirt frames.
    private static func lookRows(_ look: GhostLook) -> [String] {
        switch look {
        case .right:                       // eyes mid-height, pupils at the right edge
            return [".....rrrr.....",
                    "...rrrrrrrr...",
                    "..rrrrrrrrrr..",
                    ".rrrwwrrrrwwr.",
                    ".rrwwwwrrwwww.",
                    ".rrwwbbrrwwbb.",
                    "rrrwwbbrrwwbbr",
                    "rrrwwwwrrwwwwr",
                    "rrrrwwrrrrwwrr",
                    "rrrrrrrrrrrrrr",
                    "rrrrrrrrrrrrrr",
                    "rrrrrrrrrrrrrr"]
        case .left:                        // mirror of right — pupils at the left edge
            return [".....rrrr.....",
                    "...rrrrrrrr...",
                    "..rrrrrrrrrr..",
                    ".rrrwwrrrrwwr.",
                    ".rrwwwwrrwwww.",
                    ".rrbbwwrrbbww.",
                    "rrrbbwwrrbbwwr",
                    "rrrwwwwrrwwwwr",
                    "rrrrwwrrrrwwrr",
                    "rrrrrrrrrrrrrr",
                    "rrrrrrrrrrrrrr",
                    "rrrrrrrrrrrrrr"]
        case .up:                          // pupils at the eye's top edge; head keeps its round silhouette
            return [".....rrrr.....",
                    "...rrrrrrrr...",
                    "..rrrrrrrrrr..",
                    ".rrrbbrrrrbbr.",
                    ".rrwbbwrrwbbw.",
                    ".rrwwwwrrwwww.",
                    "rrrwwwwrrwwwwr",
                    "rrrrwwrrrrwwrr",
                    "rrrrrrrrrrrrrr",
                    "rrrrrrrrrrrrrr",
                    "rrrrrrrrrrrrrr",
                    "rrrrrrrrrrrrrr"]
        case .down:                        // pupils low; eye bottom raised a row to meet them
            return [".....rrrr.....",
                    "...rrrrrrrr...",
                    "..rrrrrrrrrr..",
                    ".rrrwwrrrrwwr.",
                    ".rrwwwwrrwwww.",
                    ".rrwwwwrrwwww.",
                    "rrrwbbwrrwbbwr",
                    "rrrrbbrrrrbbrr",
                    "rrrrrrrrrrrrrr",
                    "rrrrrrrrrrrrrr",
                    "rrrrrrrrrrrrrr",
                    "rrrrrrrrrrrrrr"]
        }
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
