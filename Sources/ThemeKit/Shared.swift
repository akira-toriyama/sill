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
/// widgets had this exact block inline. (ThemeKitUI's popup machinery keeps its
/// own copy in `PopupPanel.swift` — it moved out at the #17b M5 retire.)
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

// MARK: - Outside-click monitor teardown

/// Remove an `NSEvent` monitor token safely from ANY thread — inline on main,
/// bounced to main otherwise. Used from a `nonisolated` `deinit` (`WindowShell`'s
/// dismiss monitor): the token is dead in the owner, so laundering it through
/// `nonisolated(unsafe)` has no real concurrent access, and the removal runs ON
/// main where the call is valid. (ThemeKitUI's popup machinery keeps its own copy
/// in `PopupPanel.swift`, which moved out of ThemeKit at the #17b M5 retire.)
func removeMonitorSafely(_ token: Any?) {
    guard let token else { return }
    // Launder the non-Sendable token through `nonisolated(unsafe)` BEFORE either
    // branch captures it into a `@MainActor` closure — it is dead in the owner, so
    // there is no real concurrent access.
    nonisolated(unsafe) let t = token
    if Thread.isMainThread {
        MainActor.assumeIsolated { NSEvent.removeMonitor(t) }
    } else {
        DispatchQueue.main.async { MainActor.assumeIsolated { NSEvent.removeMonitor(t) } }
    }
}

// MARK: - Control-height ladder

extension ThemedButton.Size {
    /// The composed-control height for this size — the MUI-derived ladder
    /// (small 30 / medium 36 / large 42) that `ThemedButton`, `ThemedButtonGroup`,
    /// and `ThemedToolBar` each had inlined verbatim (the group/toolbar copies were
    /// even commented "mirrors ThemedButton"). One source so the three can't drift.
    var controlHeight: CGFloat {
        switch self {
        case .small:  return 30
        case .medium: return 36
        case .large:  return 42
        }
    }
}

// MARK: - Shadow layer

@MainActor
extension CALayer {
    /// Push a resolved MUI elevation spec onto this layer's drop shadow. Four
    /// widgets pushed these same three properties by hand; the tuple shape is the
    /// one `ResolvedPalette.shadow(_:)` returns. (ThemedButton overrides `opacity`
    /// inline for its grouped-flat case before handing the tuple in.)
    func applyShadowSpec(_ e: (opacity: Float, radius: CGFloat, offsetY: CGFloat)) {
        shadowOpacity = e.opacity
        shadowRadius  = e.radius
        shadowOffset  = CGSize(width: 0, height: e.offsetY)
    }

    /// Seed a drop-shadow layer's fixed setup: never clip (the silhouette lives
    /// outside bounds), an opaque black shadow colour, device-pixel `scale`.
    /// Callers still add the layer and toggle `isHidden` themselves.
    func configureShadowLayer(scale: CGFloat) {
        masksToBounds = false
        shadowColor = NSColor.black.cgColor
        contentsScale = scale
    }
}

// MARK: - Themed text layer

@MainActor
extension CATextLayer {
    /// The four-property config every themed label layer shares: device-pixel
    /// `scale`, horizontal `alignment`, tail truncation, single line. Callers set
    /// `anchorPoint` and add the sublayer separately (those differ per widget).
    func configureThemedLabel(scale: CGFloat, alignment: CATextLayerAlignmentMode) {
        contentsScale = scale
        alignmentMode = alignment
        truncationMode = .end
        isWrapped = false
    }
}
