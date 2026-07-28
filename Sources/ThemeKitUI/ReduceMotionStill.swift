import SwiftUI

/// The still frame the effect views rest on when the system asks for reduced
/// motion.
///
/// Every effect renderer here already had the mechanism to stop: a
/// `frozen: Double?` input that renders ONE deterministic frame, built so prism
/// can screenshot an effect mid-flight. Honouring Reduce Motion is therefore
/// not new rendering code — it is deciding WHICH still to rest on and saying it
/// in one place, so six views cannot drift to six different answers.
///
/// **`frozen:` does not mean the same thing in all six views**, which is why
/// there are two constants here and not one. Measured on the six files:
///
/// | view | `frozen:` unit |
/// |---|---|
/// | `InkSplatterView`, `ParticleBurstView` | a FRACTION (0…1) of `duration` |
/// | `ChompCorridorView`, `LinePetsView`, `PathPetView`, `PixelSpriteView` | an ABSOLUTE clock value in seconds |
///
/// One shared number would have been read as "the same still frame everywhere"
/// while actually meaning "half-way through the burst" in two views and "half a
/// second in" in four. The two constants below happen to hold the same value
/// today; they are separate so that changing one cannot silently change the
/// other. (The unit split itself is a public-API inconsistency worth resolving
/// on its own — it is not this file's job to paper over it.)
///
/// Internal on purpose. An app does not choose this; the system setting does.
/// An app that wants a specific frame already has the public `frozen:`
/// argument, and an explicit `frozen:` still wins over these (see each view's
/// `stillFrame`).
enum ReduceMotionStill {

    /// For views whose `frozen:` is a FRACTION (0…1) of the effect's duration.
    ///
    /// Mid-life, not `0`. A burst at t=0 has not emitted and a splatter has not
    /// landed: resting there does not read as "the effect, held still", it
    /// reads as "the effect, broken". Half-way is the frame that still shows
    /// what the effect IS, which is the point of leaving it on screen at all
    /// rather than hiding it.
    static let fraction: Double = 0.5

    /// For views whose `frozen:` is an ABSOLUTE clock value in seconds.
    ///
    /// Any fixed second is arbitrary here — a pet's position at 0.5s depends on
    /// its path length and speed, which a constant cannot know. What it must be
    /// is deterministic and past the degenerate opening moment, so the held
    /// frame shows a pet on its path and a sprite on a real animation frame
    /// (at the default 5 Hz, 0.5s lands on frame 2 of the cycle) rather than
    /// everything stacked at its origin.
    static let clock: TimeInterval = 0.5
}
