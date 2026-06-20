// Motion — the shared ONE-SHOT animation MATH atom for the swift app
// family (facet + perch + wand; halo/glance free to adopt). The cyclic,
// looping, color-over-time motion (border breathe/flash, rainbow cycle,
// line-pets) lives in `Effects`; the TRANSIENT, play-once motion — a panel
// pops open, a row slides to its new slot, a pill blooms in, a HUD badge
// scales up, a match flashes and decays — lives HERE, cleanly separated.
//
// The whole module is ONE pure, Sendable, AppKit-free namespace,
// `ThemedTransition`, the direct analog of MUI's `theme.transitions`:
//   * `Duration` — named time tokens (`TimeInterval`, seconds), so a call
//     site reads `.enter` / `.move`, never a bare `0.16`.
//   * `Easing`   — named curves, each a usable pure `f(t) -> value` (NOT a
//     CSS string the browser solves), incl. an exact cubic-bezier solver
//     so the Material curves are byte-faithful.
//   * `Tween`    — the (start, duration, delay, easing) value EVERY app
//     re-implements by hand (`p = min(elapsed/duration, 1)` then ease),
//     reduced to one struct sampled per frame.
//   * `progress`/`eased`/`lerp`/`spring`/`dampedSine`/`autoDuration` —
//     the per-frame primitives the three apps each hand-rolled.
//
// PHILOSOPHY — same as `Effects`: NO timer, NO mutable animation state, NO
// AppKit. Everything is a PURE function of a wall-clock `now` (the app owns
// the clock — its existing `CACurrentMediaTime()` redraw heartbeat — and
// samples these each frame). That keeps the layer graph honest: a headless
// or cross-platform consumer links `Motion` and gets ZERO AppKit. The only
// platform touch is a handful of `CGPoint`/`CGRect` `lerp` overloads behind
// `#if canImport(CoreGraphics)`, mirroring how `Effects` gates its AppKit
// animator — the Double math stays universal.
//
// CALIBRATION — the `Duration` token VALUES are this family's MEASURED band
// (~0.10–0.22 s), NOT MUI's web ladder (0.15–0.375 s). The apps run snappier
// than the web (sill's own widget timing is `0.16 s … NOT MUI's 250 ms`);
// we keep MUI's STRUCTURE (named role tokens, enter faster than exit, a
// height→duration heuristic) but the family's own taste for the numbers.

import Foundation

/// The family's shared one-shot animation vocabulary — durations, easing
/// curves, tweens, and per-frame interpolation. A caseless enum used as a
/// pure namespace (it is never instantiated), exactly as MUI ships
/// `theme.transitions` as a small declarative bundle. Pure + `Sendable`.
public enum ThemedTransition {}

// MARK: - Duration tokens

public extension ThemedTransition {
    /// Named transition durations in SECONDS (`TimeInterval`, the CA/AppKit
    /// convention — never milliseconds, so there is no `/1000` at call sites).
    ///
    /// Values are calibrated to the app family's OBSERVED timing band, not
    /// MUI's web durations: facet's slide/reorder/zoom (0.15–0.20 s), wand's
    /// panel pop (0.12–0.18 s), perch's match/unmatch (0.12–0.22 s) and sill's
    /// own widget house timing (0.16 s) all cluster here. The role NAMES are
    /// MUI's design language (enter < exit, a magnitude ladder); the numbers
    /// are the family's. Tune one knob → the whole system retimes.
    enum Duration {
        /// `0` — an instant snap (no animation); the "disable actions" case.
        public static let snap: TimeInterval = 0
        /// `0.12 s` — an element LEAVING (dismiss / fade-out). Deliberately
        /// faster than `enter`, like MUI's leavingScreen < enteringScreen, so
        /// dismissals feel crisp (wand fade-close, sill combo fade).
        public static let exit: TimeInterval = 0.12
        /// `0.16 s` — the DEFAULT. An element appearing / a widget state
        /// change (hover/press/focus). sill's house `layerTxn` timing; the
        /// fallback when no explicit duration is given.
        public static let enter: TimeInterval = 0.16
        /// `0.18 s` — repositioning on-screen: a slide / reorder / pop-open
        /// (facet rail-slide 0.17, grid reorder 0.15, wand pop 0.18).
        public static let move: TimeInterval = 0.18
        /// `0.22 s` — a richer, attention-drawing beat: a match explode, a
        /// particle burst, a commit-zoom (perch 0.22, facet 0.20).
        public static let emphasis: TimeInterval = 0.22
        /// `0.03 s` — the per-ITEM delay STEP for a staggered cascade (item
        /// `i` starts at `i * staggerStep`); perch's pill cascade spacing.
        public static let staggerStep: TimeInterval = 0.03
    }

    /// Scale a duration by a factor, never below 0. The shared form of perch's
    /// `[overlay.effect].duration-scale` knob (and any app's "animation speed"
    /// preference): `scaled(.move, by: cfg.durationScale)`. The factor stays
    /// APP-SIDE (a pure stateless atom owns no mutable speed setting); this is
    /// just the clamp + multiply every app would otherwise inline.
    static func scaled(_ duration: TimeInterval, by factor: Double) -> TimeInterval {
        max(0, duration * factor)
    }
}

// MARK: - Progress (the per-frame primitive)

public extension ThemedTransition {
    /// Linear progress `0…1` of a transition that began at `start` (a
    /// wall-clock stamp, e.g. `CACurrentMediaTime()`) and runs for `duration`,
    /// optionally after `delay`. Clamped to `0…1`. This is the single line
    /// every app re-implements — perch/facet/wand each write
    /// `min(elapsed / duration, 1)` in a dozen places. A non-positive
    /// `duration` snaps to `1` once `start + delay` is reached (a 0-second
    /// "transition" is just an instant set).
    static func progress(now: Double, start: Double,
                         duration: TimeInterval, delay: TimeInterval = 0) -> Double {
        guard duration > 0 else { return now >= start + delay ? 1 : 0 }
        return min(1, max(0, (now - start - delay) / duration))
    }

    /// `progress` run through `easing` — the eased `0…1` (or beyond, for an
    /// overshooting spring) the app multiplies into its from→to interpolation.
    /// The two-step `let p = …; let e = ease(p)` every site does, in one call.
    static func eased(now: Double, start: Double, duration: TimeInterval,
                      delay: TimeInterval = 0, easing: Easing) -> Double {
        easing(progress(now: now, start: start, duration: duration, delay: delay))
    }
}

// MARK: - Auto duration (size → time heuristic)

public extension ThemedTransition {
    /// A duration that grows SUBLINEARLY with a surface's size — MUI's
    /// `getAutoHeightDuration`, ported verbatim (its 4th-root term means a
    /// panel twice as tall animates only ~19% longer, so big and small
    /// collapses both feel right). Pass the changing extent in points (a
    /// height, a width, a travel distance); returns SECONDS. `extent <= 0`
    /// returns `0`.
    ///
    /// Use for an auto-sized expand/collapse (facet's grid reorder span, a
    /// list section open, wand's panel grow) where a fixed token would feel
    /// too fast for a tall surface and too slow for a short one. The literal
    /// constants are MUI's published formula
    /// (`(4 + 15·c^0.25 + c/5)·10` ms, `c = extent/36`).
    static func autoDuration(forExtent extent: Double) -> TimeInterval {
        guard extent > 0 else { return 0 }
        let c = extent / 36
        let ms = (4 + 15 * pow(c, 0.25) + c / 5) * 10
        return ms.rounded() / 1000
    }
}
