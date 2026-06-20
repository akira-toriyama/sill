// Motion — the Tween value.
//
// EVERY one-shot animation in the family is the same four facts: WHEN it
// started, HOW LONG it runs, an optional lead-in DELAY, and the EASING. The
// apps store those as loose locals (`t0`, `duration`, `+ pow(...)`) and
// re-derive progress inline at every draw. `Tween` bundles them into one
// `Sendable` value the app stores in its animation cell and samples each
// frame — `tween.value(at: now)` — with no re-derivation and no mutable
// engine. Pure: it holds no clock; the caller passes `now`.

import Foundation

public extension ThemedTransition {
    /// A one-shot transition: a start stamp, a duration, an optional delay,
    /// and an easing curve. Sample it each frame with a wall-clock `now`
    /// (`CACurrentMediaTime()`-style seconds, the SAME origin used for
    /// `start`). Holds no state of its own — re-sampling at the same `now`
    /// always yields the same value (replayable, testable).
    struct Tween: Sendable {
        /// Wall-clock stamp the transition began (seconds, app's clock).
        public var start: Double
        /// Run length in seconds (a non-positive duration snaps instantly).
        public var duration: TimeInterval
        /// Lead-in delay before motion begins — a per-item stagger offset.
        public var delay: TimeInterval
        /// The curve `progress` is run through.
        public var easing: Easing

        public init(start: Double, duration: TimeInterval,
                    delay: TimeInterval = 0, easing: Easing = .easeOutCubic) {
            self.start = start
            self.duration = duration
            self.delay = delay
            self.easing = easing
        }

        /// Linear progress `0…1` at `now` (clamped; after `delay`).
        public func rawProgress(at now: Double) -> Double {
            ThemedTransition.progress(now: now, start: start,
                                      duration: duration, delay: delay)
        }

        /// Eased value at `now` — `easing(rawProgress)`. May exceed 1 for a
        /// spring easing (the overshoot is intentional).
        public func value(at now: Double) -> Double {
            easing(rawProgress(at: now))
        }

        /// The eased value interpolated from `a` to `b` — the common case
        /// `from + (to - from) · eased`. Convenience over `value(at:)` + `lerp`.
        public func value(at now: Double, from a: Double, to b: Double) -> Double {
            ThemedTransition.lerp(a, b, value(at: now))
        }

        /// True once the run (including `delay`) has fully elapsed — the
        /// "stop the redraw clock / reset state" gate every app checks.
        public func isComplete(at now: Double) -> Bool {
            now - start >= delay + duration
        }
    }
}
