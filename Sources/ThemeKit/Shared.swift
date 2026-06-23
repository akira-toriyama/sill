// Shared — small cross-widget helpers that several ThemeKit widgets had each
// re-implemented byte-for-byte (the #14a DRY pass). These touch QuartzCore /
// AppKit (CALayer, NSView, CATransaction), so they live in ThemeKit, never in
// the pure `Palette` layer. Behaviour is identical to the per-widget copies
// they replace — this file only removes duplication, it does not change values.

import AppKit
import QuartzCore
import Motion

// MARK: - Layer transaction

/// A snapped or eased CALayer mutation — the single `CATransaction` wrapper the
/// themed widgets share. `animated: true` eases over `duration` (default = the
/// standard enter step) with the system ease-out; `animated: false` disables
/// implicit actions so the change snaps (a theme switch must not smear). Nine
/// widgets had this exact block inline; the `duration` knob also folds
/// `PopupFade.transact`, which passes its own combo / tooltip fade length.
/// (ThemedBorder keeps its own snap-only variant — its animated branch is a
/// no-op, deliberately distinct from this one.)
@MainActor
func layerTxn(animated: Bool,
              duration: TimeInterval = ThemedTransition.Duration.enter,
              _ body: () -> Void) {
    CATransaction.begin()
    if animated {
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
    } else {
        CATransaction.setDisableActions(true)
    }
    body()
    CATransaction.commit()
}

// MARK: - Backing scale

@MainActor
extension NSView {
    /// The device-pixel scale to seed a CALayer's `contentsScale` with: the
    /// host window's scale, falling back to the main screen, then 2. Several
    /// widgets had this exact expression inline; this is the single source.
    /// (Controllers that must read a *specific* window — a popup panel ordered
    /// in late, an anchor view — read that window directly and don't use this.)
    var themeBackingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    /// Announce a COMMITTED value/selection change to assistive tech (VoiceOver).
    /// Call ONLY at firing-door sites (user-intent / `notifying:` setters) — NEVER
    /// on every transient highlight, hover, or keystroke (that floods VoiceOver).
    func postAXValueChanged() { NSAccessibility.post(element: self, notification: .valueChanged) }
}
