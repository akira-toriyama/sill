// Motion — the DISCRETE frame sampler (the companion to the continuous curves).
//
// Easing / Tween / lerp BLEND between values; `frameStep` STEPS between them —
// a sprite SWAP, not an interpolation. It is the one primitive the family's
// retro look needs and the rest of Motion lacks: a clock-driven index into a
// fixed list of frames (the chomp mouth `[0, 0.5, 1, 0.5]`, a 2-pose ghost
// waddle, a blinking caret, a marching-ants dash phase). Pure + Sendable —
// like everything in Motion, it owns no clock; the caller passes `now`.

import Foundation

public extension ThemedTransition {
    /// The frame to show at wall-clock `now`, cycling through `frames` `hz`
    /// COMPLETE times per second. A discrete swap (hard cut between frames),
    /// the counterpart to the continuous `Easing`/`Tween`: those interpolate,
    /// this snaps. The chomp mouth steps `[0, 0.5, 1, 0.5]` at `hz: 5`; a ghost
    /// waddles `[poseA, poseB]` at a slower `hz`.
    ///
    /// The index advances `hz · frames.count` times per second and WRAPS, so one
    /// full pass through `frames` takes `1 / hz` seconds. `now` may be negative
    /// (a floored, always-in-range modulo keeps the index total — no trap, no
    /// out-of-bounds). Generic over the frame type `T` (a `Double` phase, a
    /// sprite, anything). `frames` MUST be non-empty (a precondition — an empty
    /// frame list has no value to return).
    ///
    /// Determinism note (the #6 float-boundary lesson): a frame boundary lands
    /// where `now · hz · count` crosses an integer. Pick test `now` values that
    /// are EXACT binary fractions (e.g. `0.125`) so the floor lands cleanly and
    /// the asserted frame is not at the mercy of IEEE-754 rounding.
    static func frameStep<T>(now: Double, hz: Double, frames: [T]) -> T {
        let n = frames.count
        precondition(n > 0, "frameStep needs at least one frame")
        // Floor (not truncate-toward-zero) so a negative `now` steps backward
        // consistently; the doubled modulo then folds any sign into `0..<n`.
        let raw = Int(floor(now * hz * Double(n)))
        let idx = ((raw % n) + n) % n
        return frames[idx]
    }
}
