// ThemeKitUI — shared child-window popup foundation. The borderless, non-activating
// `NSPanel` plumbing that EVERY themed popup needs (the tooltip bubble, the combo
// dropdown, the menu): the panel subclass + its themed configuration, the
// visibleFrame placement math (screen-by-geometry · flip · clamp · invalidateShadow),
// the fade-token teardown, the host glue, and the outside-click monitor helper.
//
// This is the rule-of-three extraction: `ThemedTooltip` and `ThemedComboBox` each
// hand-copied this machinery (tooltip first, combo lifted it from tooltip), and
// `ThemedMenu` was the third consumer. The factory is a PURE refactor —
// every per-widget DIFFERENCE is preserved as an explicit parameter, NOT unified:
//   * `interactive` → `ignoresMouseEvents` (tooltip click-through, combo/menu live);
//   * `PopupFade(duration:)` keeps each widget's own fade (combo 0.12s, tooltip
//     0.16s) — a static screenshot can't catch a 20 ms delta, so unifying here
//     would falsely read green;
//   * placement is a per-case enum so the combo's 1-D below/above flip and the
//     tooltip's 4-side arrow placement each reproduce byte-for-byte.
//
// INTERNAL again (#17b M5): M3/M4 made this surface `public` only because the
// widgets crossed the ThemeKit→ThemeKitUI module edge ahead of it. At the M5
// retire the last consumers (tooltip + this file) moved up too, so the scaffold
// is module-private once more — apps consume the WIDGETS, never this. The window
// SHELL for long-lived panels is separate (`ThemeKit.WindowShell`, #17i); the two
// share only the tiny `removeMonitorSafely` idea (each module keeps its own copy).

import AppKit
import QuartzCore
import Motion

// MARK: - PopupPanel (never key — the non-activating discipline)

/// A borderless, non-activating panel that REFUSES to become key or main, so
/// ordering it in front cannot resign the host window's key state or its first
/// responder. Combo relies on this (a row click must not steal the field's first
/// responder); the tooltip never makes itself key anyway (it is click-through),
/// so the override is harmless there. Receives mouse events only when its owner
/// sets `ignoresMouseEvents = false` (see `themedPopupPanel(interactive:)`).
@MainActor
final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Build the shared themed popup panel: a borderless `.nonactivatingPanel` at
/// `.popUpMenu` level, clear + shadowed, joining all Spaces. These ~10 lines were
/// byte-identical across the tooltip and combo; the ONLY differences are exposed:
///   - `interactive`: false ⇒ click-through (`ignoresMouseEvents = true`, a passive
///     tooltip); true ⇒ receives clicks (an interactive list / menu).
///   - `role`: the panel's accessibility role (tooltip `.unknown` to stay out of
///     AX; combo `.list`; menu `.menu`).
/// The caller assigns `contentView` and (if interactive) marks it an AX element.
///
/// `hidesOnDeactivate` is the one line that can't be a constant — see
/// `popupHidesOnDeactivate`.

/// Should a popup panel hide when its host app deactivates?
///
/// A borderless panel gets no free hide-on-deactivate, so a `.regular` app
/// wants it: switch away from facet and its combo dropdown should not stay
/// floating over the app you switched TO.
///
/// An `.accessory` (LSUIElement) host is the opposite case, and `true` there is
/// not "slightly wrong" — it is fatal. Such an app NEVER becomes active, so
/// AppKit orders the panel out the instant it is shown: the popup simply never
/// appears, with no error and no warning. wand (a menu-bar-less daemon whose
/// whole UI is a non-activating panel) hit exactly this when it became the
/// family's first `ThemedMenu` adopter — its own "presented the menu" log line
/// fired while the screen stayed empty.
///
/// This is the same trap as the `.activeInActiveApp` NSTrackingArea default,
/// which resolves to "never" under an accessory host: any AppKit default keyed
/// on "is the app active" needs this gate.
@MainActor
func popupHidesOnDeactivate(_ policy: NSApplication.ActivationPolicy) -> Bool {
    policy != .accessory
}

@MainActor
func themedPopupPanel(interactive: Bool, role: NSAccessibility.Role) -> PopupPanel {
    let p = PopupPanel(contentRect: .zero,
                       styleMask: [.borderless, .nonactivatingPanel],
                       backing: .buffered, defer: false)
    p.isFloatingPanel = true
    p.becomesKeyOnlyIfNeeded = true
    // `NSApplication.shared`, not `NSApp`: the latter is an implicitly
    // unwrapped global that stays nil until the singleton is first touched,
    // so reading it here would trap in any host that builds a popup before
    // that (a headless test bundle does exactly this). `.shared` vends the
    // instance instead.
    p.hidesOnDeactivate = popupHidesOnDeactivate(NSApplication.shared.activationPolicy())
    p.level = .popUpMenu                 // above .floating
    p.ignoresMouseEvents = !interactive  // tooltip click-through; combo/menu live
    p.hasShadow = true
    p.isOpaque = false
    p.backgroundColor = .clear
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                            .ignoresCycle, .stationary]
    p.setAccessibilityRole(role)
    return p
}

// MARK: - Placement

/// The concrete, post-flip side a popup sits on relative to its anchor (never an
/// `.auto`). Promoted out of `ThemedTooltip.Side` so the placement engine and the
/// future menu share one vocabulary.
enum PopupSide { case top, bottom, leading, trailing }

/// The corner of a popup pinned to its anchor / cursor — the Grow transform origin
/// (a menu scales OUT from this corner, MUI's transform-origin). Read in the panel
/// content's UN-FLIPPED y-up space: `.top*` = the upper edge (y = height),
/// `.bottom*` = the lower edge (y = 0); `*Leading` = x 0, `*Trailing` = x width.
enum PopupCorner: Equatable { case topLeading, topTrailing, bottomLeading, bottomTrailing }

/// A placement REQUEST. Each case carries exactly the inputs its geometry needs;
/// the engine shares only the screen-pick + clamp + `setFrame`/`invalidateShadow`
/// scaffold around the per-case origin/flip math (so the two existing layouts stay
/// byte-identical). New cases (`.anchorCorner`/`.point`) arrive with the menu.
enum PopupPlacement {
    /// Combo: width = the anchor's on-screen width, sits `gap` below the anchor,
    /// flips above only when below would underflow the visible frame.
    case anchorWidthBelow(gap: CGFloat, height: CGFloat)
    /// Tooltip: a `fillSize` bubble on `preferred` side (+ an `arrowLen` protrusion
    /// on the anchor-facing axis), `gap` from the anchor edge, edge-flipped to the
    /// opposite side on overflow.
    case sideRelative(preferred: PopupSide, fillSize: CGSize, gap: CGFloat, arrowLen: CGFloat)
    /// Menu drop-down from an anchor view: a `size` panel whose top-leading meets
    /// the anchor's bottom-leading, `gap` below; flips ABOVE on vertical underflow
    /// and RIGHT-aligns on horizontal overflow. Returns the pinned corner (the Grow
    /// origin).
    case anchorCorner(size: CGSize, gap: CGFloat)
    /// Context menu at a screen `point`: a `size` panel growing down-right from the
    /// point, flipping up / left on overflow. Returns the pinned corner.
    case point(_ point: CGPoint, size: CGSize)
    /// Submenu child beside its parent ROW (anchorRectOnScreen = the row's rect): the
    /// child's top-leading meets the row's top-trailing, `gap` to the right (so the
    /// first child row tops-align with the parent row); flips LEFT (top-trailing at
    /// the row's top-leading) on horizontal overflow and clamps vertically. Returns
    /// the pinned corner (the Grow origin).
    case submenu(size: CGSize, gap: CGFloat)
}

/// A placement RESULT — per case, never a god-tuple. The caller reads only the
/// fields meaningful to its layout (combo: did it flip; tooltip: which side).
enum PopupPlacementResult {
    case anchorWidthBelow(frame: CGRect, flippedAbove: Bool)
    case sideRelative(frame: CGRect, side: PopupSide)
    case anchorCorner(frame: CGRect, corner: PopupCorner)
    case point(frame: CGRect, corner: PopupCorner)
    case submenu(frame: CGRect, corner: PopupCorner)
}

/// Keep the popup this far inside the screen's visible frame (shared by both
/// layouts' clamp; the combo also uses it as its below→above flip threshold).
let popupScreenMargin: CGFloat = 4

/// Resolve + commit a popup's frame against its anchor. Shared scaffold:
///   1. pick the screen by GEOMETRY (the anchor's centre, NOT `window.screen`);
///   2. run the per-case origin + flip math;
///   3. clamp both axes into the visible frame;
///   4. `setFrame(display:)` + `invalidateShadow()` (a borderless panel caches its
///      silhouette shadow, which goes stale the instant a resize changes it — the
///      #1 bug in this widget class, so it is BAKED IN here).
/// Returns nil (without touching the panel) when no screen can be resolved — the
/// caller then leaves the popup where it was, exactly as the hand-written code did.
@MainActor
func placePopup(_ panel: NSPanel, anchorRectOnScreen onScreen: CGRect,
                _ placement: PopupPlacement) -> PopupPlacementResult? {
    let centre = CGPoint(x: onScreen.midX, y: onScreen.midY)
    let screen = NSScreen.screens.first { $0.frame.contains(centre) }
        ?? NSScreen.main ?? NSScreen.screens.first
    guard let vf = screen?.visibleFrame else { return nil }
    let m = popupScreenMargin

    switch placement {
    case let .anchorWidthBelow(gap, height):
        let width = onScreen.width
        var origin = CGPoint(x: onScreen.minX, y: onScreen.minY - gap - height)   // prefer below
        var flippedAbove = false
        if origin.y < vf.minY + m {
            origin.y = onScreen.maxY + gap                                         // flip above
            flippedAbove = true
        }
        let size = CGSize(width: width, height: height)
        origin = clampPopupOrigin(origin, size: size, into: vf, margin: m)
        let frame = CGRect(origin: origin, size: size)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
        return .anchorWidthBelow(frame: frame, flippedAbove: flippedAbove)

    case let .sideRelative(preferred, fillSize, gap, arrowLen):
        var side = preferred
        var size = popupPanelSize(side, fill: fillSize, arrowLen: arrowLen)
        var origin = popupOriginFor(side, onScreen: onScreen, size: size, gap: gap)
        switch side {                                  // edge-flip to the opposite side on overflow
        case .bottom:   if origin.y < vf.minY { side = .top }
        case .top:      if origin.y + size.height > vf.maxY { side = .bottom }
        case .leading:  if origin.x < vf.minX { side = .trailing }
        case .trailing: if origin.x + size.width > vf.maxX { side = .leading }
        }
        size = popupPanelSize(side, fill: fillSize, arrowLen: arrowLen)
        origin = popupOriginFor(side, onScreen: onScreen, size: size, gap: gap)
        origin = clampPopupOrigin(origin, size: size, into: vf, margin: m)
        let frame = CGRect(origin: origin, size: size)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
        return .sideRelative(frame: frame, side: side)

    case let .anchorCorner(size, gap):
        // Prefer the menu's top-leading at the anchor's bottom-leading (drop below,
        // left-aligned). Flip ABOVE on underflow, RIGHT-align on overflow; the Grow
        // origin corner follows the resolved position.
        var corner = PopupCorner.topLeading
        var x = onScreen.minX
        var y = onScreen.minY - gap - size.height
        if y < vf.minY + m {
            y = onScreen.maxY + gap
            corner = .bottomLeading
        }
        if x + size.width > vf.maxX - m {
            x = onScreen.maxX - size.width
            corner = (corner == .topLeading) ? .topTrailing : .bottomTrailing
        }
        let origin = clampPopupOrigin(CGPoint(x: x, y: y), size: size, into: vf, margin: m)
        let frame = CGRect(origin: origin, size: size)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
        return .anchorCorner(frame: frame, corner: corner)

    case let .point(p, size):
        // Grow down-right from the cursor; flip up / left on overflow.
        var corner = PopupCorner.topLeading
        var x = p.x
        var y = p.y - size.height
        if x + size.width > vf.maxX - m {
            x = p.x - size.width
            corner = .topTrailing
        }
        if y < vf.minY + m {
            y = p.y
            corner = (corner == .topLeading) ? .bottomLeading : .bottomTrailing
        }
        let origin = clampPopupOrigin(CGPoint(x: x, y: y), size: size, into: vf, margin: m)
        let frame = CGRect(origin: origin, size: size)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
        return .point(frame: frame, corner: corner)

    case let .submenu(size, gap):
        // Child to the RIGHT of the parent row, its top aligned with the row's top
        // (y-up: the row's top edge is onScreen.maxY). Flip LEFT on right-overflow;
        // clamp vertically so a tall child near the screen edge shifts into view.
        var corner = PopupCorner.topLeading
        var x = onScreen.maxX + gap
        let y = onScreen.maxY - size.height
        if x + size.width > vf.maxX - m {
            x = onScreen.minX - gap - size.width
            corner = .topTrailing
        }
        let origin = clampPopupOrigin(CGPoint(x: x, y: y), size: size, into: vf, margin: m)
        let frame = CGRect(origin: origin, size: size)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
        return .submenu(frame: frame, corner: corner)
    }
}

/// Clamp an origin so a `size` box stays `margin` inside the visible frame
/// (the inner `max` keeps the lower bound winning on a too-small screen).
func clampPopupOrigin(_ o: CGPoint, size: CGSize, into vf: CGRect, margin m: CGFloat) -> CGPoint {
    CGPoint(x: min(max(o.x, vf.minX + m), max(vf.minX + m, vf.maxX - m - size.width)),
            y: min(max(o.y, vf.minY + m), max(vf.minY + m, vf.maxY - m - size.height)))
}

/// Panel size = the fill surface + the arrow protrusion on the anchor-facing axis.
func popupPanelSize(_ side: PopupSide, fill: CGSize, arrowLen: CGFloat) -> CGSize {
    switch side {
    case .top, .bottom:       return CGSize(width: fill.width, height: fill.height + arrowLen)
    case .leading, .trailing: return CGSize(width: fill.width + arrowLen, height: fill.height)
    }
}

/// Pre-flip / pre-clamp panel origin (Y-up), centred on the cross axis, `gap` from
/// the anchor edge to the arrow tip.
func popupOriginFor(_ side: PopupSide, onScreen: CGRect, size: CGSize, gap: CGFloat) -> CGPoint {
    switch side {
    case .bottom:   return CGPoint(x: onScreen.midX - size.width / 2, y: onScreen.minY - gap - size.height)
    case .top:      return CGPoint(x: onScreen.midX - size.width / 2, y: onScreen.maxY + gap)
    case .leading:  return CGPoint(x: onScreen.minX - gap - size.width, y: onScreen.midY - size.height / 2)
    case .trailing: return CGPoint(x: onScreen.maxX + gap, y: onScreen.midY - size.height / 2)
    }
}

// MARK: - Fade (monotonic-token discipline)

/// Order a panel in/out with an opacity fade. The fade-out's deferred `orderOut`
/// is gated by the caller's monotonic generation token (`shouldOrderOut`) so a
/// quick re-show inside the fade can't be clobbered by a stale completion — the
/// #1 child-window bug after invalidateShadow. Duration is a PARAM (combo 0.12s,
/// tooltip 0.16s) so this is behavior-neutral for both consumers.
@MainActor
struct PopupFade {
    let duration: TimeInterval

    init(duration: TimeInterval) { self.duration = duration }

    /// Bring `layer` to opacity 1. The caller orders the panel front BEFORE this
    /// (the two widgets do it at different points in their show flow).
    func fadeIn(_ layer: CALayer, animated: Bool) {
        if animated {
            layer.opacity = 0
            transact(animated: true) { layer.opacity = 1 }
        } else {
            transact(animated: false) { layer.opacity = 1 }
        }
    }

    /// Fade `layer` to 0, then `orderOut` the panel — but only if `shouldOrderOut()`
    /// still holds when the animation completes (same fade generation, still hidden).
    func fadeOut(_ layer: CALayer, panel: NSPanel, animated: Bool,
                 shouldOrderOut: @escaping @MainActor () -> Bool) {
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            CATransaction.setCompletionBlock {
                MainActor.assumeIsolated {
                    if shouldOrderOut() { panel.orderOut(nil) }
                }
            }
            layer.opacity = 0
            CATransaction.commit()
        } else {
            transact(animated: false) { layer.opacity = 0 }
            panel.orderOut(nil)
        }
    }

    /// A snapped (or `duration`-eased) layer mutation. Delegates to the shared
    /// `layerTxn`, passing this fade's own length (combo / tooltip) as the
    /// animated duration.
    func transact(animated: Bool, _ body: () -> Void) {
        layerTxn(animated: animated, duration: duration, body)
    }
}

/// A snapped or eased CALayer mutation — the single `CATransaction` wrapper the
/// popup widgets share (ThemeKitUI's copy of ThemeKit's internal helper, moved
/// here with this file at the #17b M5 retire; the M3/M4 per-widget inline snap
/// blocks fold back into it). `animated: true` eases over `duration` (default =
/// the standard enter step) with the system ease-out; `animated: false` disables
/// implicit actions so the change snaps (a theme switch must not smear).
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

// MARK: - Host glue (pin the popup to a moving / scrolling / closing host)

/// Keeps a shown popup glued to its host window: re-place on move/resize/scroll,
/// dismiss on close (and, opt-in, on the host resigning key — combo dismisses, the
/// tooltip does not). An `NSObject` so the notification targets are plain `@objc`
/// selectors (no per-host `@objc` method needed — that boilerplate lived on each
/// widget before); the widget owns one of these and feeds it closures. Removal is
/// SCOPED (per name/object), so a future host holding other observers is unharmed.
@MainActor
final class PopupGlue: NSObject {
    private weak var window: NSWindow?
    private weak var clip: NSClipView?
    private var onGeometryChange: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onResignKey: (() -> Void)?

    override init() { super.init() }

    /// Begin observing `window` (+ an optional enclosing scroll `clip`). `onResignKey`
    /// nil ⇒ the host resigning key is NOT observed (the tooltip's case).
    func start(window: NSWindow, clip: NSClipView?,
               onGeometryChange: @escaping () -> Void,
               onClose: @escaping () -> Void,
               onResignKey: (() -> Void)? = nil) {
        stop()
        self.window = window
        self.clip = clip
        self.onGeometryChange = onGeometryChange
        self.onClose = onClose
        self.onResignKey = onResignKey
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(geometryChanged),
                       name: NSWindow.didMoveNotification, object: window)
        nc.addObserver(self, selector: #selector(geometryChanged),
                       name: NSWindow.didResizeNotification, object: window)
        nc.addObserver(self, selector: #selector(closed),
                       name: NSWindow.willCloseNotification, object: window)
        if onResignKey != nil {
            nc.addObserver(self, selector: #selector(resignedKey),
                           name: NSWindow.didResignKeyNotification, object: window)
        }
        if let clip {
            clip.postsBoundsChangedNotifications = true
            nc.addObserver(self, selector: #selector(geometryChanged),
                           name: NSView.boundsDidChangeNotification, object: clip)
        }
    }

    /// Scoped teardown (NOT the blunt `removeObserver(self)`).
    func stop() {
        guard let window else { return }
        let nc = NotificationCenter.default
        nc.removeObserver(self, name: NSWindow.didMoveNotification, object: window)
        nc.removeObserver(self, name: NSWindow.didResizeNotification, object: window)
        nc.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        nc.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
        if let clip {                                // the CACHED clip (the scroll view may have changed)
            nc.removeObserver(self, name: NSView.boundsDidChangeNotification, object: clip)
        }
        self.window = nil
        self.clip = nil
        onGeometryChange = nil
        onClose = nil
        onResignKey = nil
    }

    @objc private func geometryChanged() { onGeometryChange?() }
    @objc private func closed() { onClose?() }
    @objc private func resignedKey() { onResignKey?() }

    deinit { NotificationCenter.default.removeObserver(self) }
}

// MARK: - Outside-click monitor teardown

/// Remove an `NSEvent` monitor token safely from ANY thread — inline on main,
/// bounced to main otherwise. Used from a `nonisolated` `deinit`: the token is
/// dead in the owner, so laundering it through `nonisolated(unsafe)` has no real
/// concurrent access, and the removal runs ON main where the call is valid.
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
