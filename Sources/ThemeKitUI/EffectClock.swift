// ThemeKitUI — the shared redraw tick for the live effect bridges.
//
// Every effect bridge (Particle/InkSplatter/PixelSprite/LinePets/PathPet/
// ChompCorridor) OWNS its redraw clock (sill's `f(now)` contract — the clock
// lives with the consumer, not the pure atom). They all want the SAME 60 Hz
// `needsDisplay` tick that stops when the view leaves its window or is frozen, so
// it lives here once (the prism benches' old `startRedrawTick`, promoted).

import AppKit

/// Start a 60 Hz `needsDisplay` timer on `view` while it is in a window, unless
/// `frozen`. Returns the timer so the caller can hold + invalidate it.
@MainActor
func startEffectTick(for view: NSView, frozen: Bool) -> Timer? {
    guard !frozen else { return nil }
    let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak view] _ in
        MainActor.assumeIsolated { view?.needsDisplay = true }
    }
    RunLoop.main.add(t, forMode: .common)
    return t
}
