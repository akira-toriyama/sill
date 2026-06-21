// PixelArt — pure, Sendable, AppKit-free ARCADE-DECAL geometry. The chomp
// (Pac-Man-style) look reinterpreted in sill's vocabulary: rigid INTEGER pixel
// grids the draw side scales (`ScaleTier`) + tints, plus the circle-minus-mouth
// wedge and a stable per-cell jitter. A pure atom alongside Palette / Gesture /
// CLIKit: zero AppKit, zero Palette (sprite-internal detail colours are
// INTRINSIC, baked on the draw side). Mechanism only — `PixelArt` owns no
// theming and no clock; rotation, colour, and timing are the caller's job.
//
// NOTE: `atan2` (and, for callers, `cos`/`sin`/`sqrt`) come from Foundation —
// `import Foundation` is LOAD-BEARING here even though this file declares no
// `Date`/`TimeInterval` (the #9d lesson: a missing Foundation import reddened
// CI). Do not drop it.
import Foundation

/// The filled cells of a Pac-Man face = "circle MINUS a mouth wedge", on a
/// `diameterCells × diameterCells` grid (origin top-left, row 0 = top). A cell
/// is FILLED unless it is either:
///   * outside the inscribed circle — `cx² + cy² > r²`, or
///   * inside the mouth wedge — `|atan2(cy, cx)| < mouthHalfRad`.
///
/// The mouth opens to the RIGHT (`+x`); the draw side rotates the context by the
/// travel tangent so the grid itself stays axis-aligned (a rigid rotation).
/// Cell centres are sampled at `(col + 0.5, row + 0.5)` relative to the grid
/// centre so the wedge is vertically symmetric. Returns row-major `(col, row)`
/// cells (no colour — the caller tints with pac-yellow). `[]` for `d <= 0`.
public func pacManCells(diameterCells d: Int, mouthHalfRad: Double)
    -> [(col: Int, row: Int)] {
    guard d > 0 else { return [] }
    let r = Double(d) / 2          // radius in cells
    var out: [(col: Int, row: Int)] = []
    for row in 0..<d {
        for col in 0..<d {
            let cx = Double(col) + 0.5 - r
            let cy = Double(row) + 0.5 - r
            if cx * cx + cy * cy > r * r { continue }          // outside circle
            if abs(atan2(cy, cx)) < mouthHalfRad { continue }  // inside mouth wedge
            out.append((col: col, row: row))
        }
    }
    return out
}

/// Mouth half-angle (radians) for a chomp `phase` in `0...1`: a 5° base opening
/// growing to 60° at full gape (`5° + 55°·phase`). The chomp animation steps
/// `phase` through `[0, 0.5, 1, 0.5]` at 5 Hz (a discrete sprite swap, Ph2); Ph1
/// passes a fixed phase for a static sprite. The formula lives here so the wedge
/// math has one home.
public func mouthHalfRad(phase: Double) -> Double {
    (5.0 + 55.0 * phase) * .pi / 180.0
}

/// The canonical chomp MOUTH animation, as pure data: the gape `phase` steps
/// through these four frames — closed → half → full → half — so the mouth opens
/// and closes once per cycle. A discrete sprite SWAP (drive it with
/// `Motion.frameStep`, NOT an interpolation), which is the retro "feel": the
/// mouth never smoothly tweens, it snaps between four poses. Named HERE — beside
/// `mouthHalfRad`, the wedge's one home — so the line-pet (Effects) and the
/// prism card read the SAME sequence with no drift. `PixelArt` owns no clock;
/// this is just the pattern, the `now` stays the caller's.
public let chompMouthFrames: [Double] = [0, 0.5, 1, 0.5]

/// Complete cycles through `chompMouthFrames` per second — the 5 Hz arcade
/// chomp (the spec's "口パク 5Hz"). One pass takes 1/5 s; `frameStep` advances
/// `chompMouthHz · chompMouthFrames.count` = 20 mouth-swaps per second.
public let chompMouthHz: Double = 5

/// Stable hash of an integer cell coordinate to `0..<1` — a deterministic
/// per-cell jitter source with NO RNG state, so a re-draw paints the same cell
/// the same way (a cherry stays a cherry). Knuth-multiplicative mix; overflow is
/// INTENTIONAL (wrapping `&*` / `^`), and `bitPattern` keeps it TOTAL on
/// negative coordinates (plain `UInt64(negativeInt)` would trap).
public func positionHash01(x: Int, y: Int) -> Double {
    let h = (UInt64(bitPattern: Int64(x)) &* 2_654_435_761)
          ^ (UInt64(bitPattern: Int64(y)) &* 40_503)
    return Double(h % 10_000) / 10_000
}
