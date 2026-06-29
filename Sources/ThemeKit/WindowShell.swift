// ThemeKit — public window-shell factory. The ONE parameterized AppKit "window
// shell" the family's five apps share (facet · wand · perch · glance · halo): a
// long-lived `NSPanel` whose key behavior, chrome, level, collection behavior and
// click-through are all knobs, plus the helpers a floating shell needs (fade,
// auto-size, screen-union, Esc / outside-click dismiss). The content is ALWAYS a
// SwiftUI view hosted through `NSHostingView` — this layer owns only the window
// SHELL (the AppKit floor policy's permitted "窓の殻"), never the contents.
//
// SEPARATE from the INTERNAL transient-popup machinery in `PopupPanel.swift`
// (`themedPopupPanel` / `placePopup` / `PopupFade`): those stay byte-identical for
// the tooltip / combo / menu. A transient popup is `.popUpMenu`-level, never-key,
// and lives for one hover/open; a shell is long-lived, can take key on demand, and
// can span displays. The two share only low-level primitives (`removeMonitorSafely`).
//
// Why a factory, not a controller: the existing transient widgets each COMPOSE the
// helpers their own way (tooltip ≠ combo ≠ menu), and the five apps' shells differ
// just as much (a click-through overlay ≠ a key-taking launcher ≠ a titled popover).
// So the shell ships as a factory + composable helpers; a higher-level controller, if
// a common shape emerges, is a follow-up the perch pilot (t-yc68) will inform.

import AppKit
import QuartzCore
import Motion

// MARK: - WindowShellSpec (the knobs)

/// The full configuration of a window shell — a value type the caller fills and
/// hands to `makeWindowShell`. Every field maps to one AppKit window property the
/// apps' chrome inventory (2026-06-29) showed they each need differently.
@MainActor
public struct WindowShellSpec {

    /// Whether — and when — the shell may become the key window.
    /// - `never`: `canBecomeKey == false` (the transient-popup discipline; a row
    ///   click must not resign the host's first responder). The default.
    /// - `onDemand`: key only when a subview actually needs it (a text field /
    ///   field editor), via `becomesKeyOnlyIfNeeded`. facet's KeyablePanel + IME
    ///   editing inside an otherwise-passive overlay.
    /// - `always`: a normal key-capable panel (an editable launcher window).
    public enum KeyMode { case never, onDemand, always }

    /// The window's frame chrome — its `styleMask` base, before `nonactivating`.
    /// `.titled`/`.resizable` have no consumer in the near-term pilots
    /// (perch/glance/wand are borderless overlays/launchers); they ship per the
    /// build-best-first policy and are isolated to this one enum case.
    public enum Chrome {
        /// No title bar (overlays, popovers, launchers). The transient default.
        case borderless
        /// A titled window, optionally user-`resizable` and `closable`.
        case titled(resizable: Bool, closable: Bool)
        /// A translucent system HUD panel (`.hudWindow`).
        case hud
    }

    public var keyMode: KeyMode
    public var chrome: Chrome
    /// `.nonactivatingPanel` — the shell floats in front WITHOUT activating the app
    /// or stealing focus. True for every overlay/popup; turn off only for a window
    /// meant to come fully forward.
    public var nonactivating: Bool
    public var level: NSWindow.Level
    public var collectionBehavior: NSWindow.CollectionBehavior
    /// `ignoresMouseEvents` — a pure pass-through overlay (halo's focus ring). The
    /// click-through helper this drives is shared with halo's raw `NSWindow` overlay.
    public var clickThrough: Bool
    public var hasShadow: Bool
    public var isOpaque: Bool
    public var backgroundColor: NSColor

    public init(keyMode: KeyMode = .never,
                chrome: Chrome = .borderless,
                nonactivating: Bool = true,
                level: NSWindow.Level = .floating,
                collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces,
                                                                   .stationary,
                                                                   .fullScreenAuxiliary],
                clickThrough: Bool = false,
                hasShadow: Bool = true,
                isOpaque: Bool = false,
                backgroundColor: NSColor = .clear) {
        self.keyMode = keyMode
        self.chrome = chrome
        self.nonactivating = nonactivating
        self.level = level
        self.collectionBehavior = collectionBehavior
        self.clickThrough = clickThrough
        self.hasShadow = hasShadow
        self.isOpaque = isOpaque
        self.backgroundColor = backgroundColor
    }

    /// The resolved `styleMask`: the chrome's base bits + `.nonactivatingPanel`
    /// when `nonactivating`. A HUD requires `.titled` + `.utilityWindow`.
    public var resolvedStyleMask: NSWindow.StyleMask {
        var mask: NSWindow.StyleMask
        switch chrome {
        case .borderless:
            mask = [.borderless]
        case let .titled(resizable, closable):
            mask = [.titled]
            if resizable { mask.insert(.resizable) }
            if closable { mask.insert(.closable) }
        case .hud:
            mask = [.hudWindow, .utilityWindow, .titled, .closable]
        }
        if nonactivating { mask.insert(.nonactivatingPanel) }
        return mask
    }
}

// MARK: - ShellPanel (key behavior is the knob)

/// The shell's `NSPanel`. Unlike the transient `PopupPanel` (key forbidden), a
/// shell's key eligibility is driven by its `keyMode`, so the SAME class serves a
/// never-key click-through overlay and an always-key editable launcher. `canBecomeMain`
/// stays the `NSPanel` default (false) — a shell is auxiliary; the host stays main.
@MainActor
public final class ShellPanel: NSPanel {
    /// Set by `makeWindowShell` from the spec; gates `canBecomeKey`.
    public var keyMode: WindowShellSpec.KeyMode = .never
    public override var canBecomeKey: Bool { keyMode != .never }
}

/// Build a window shell from a spec. The returned panel has NO content — assign an
/// `NSHostingView` (SwiftUI) to `contentView` (the AppKit floor: shell here, all
/// content SwiftUI), then size + place + show it with the helpers below.
///
/// Mirrors `themedPopupPanel`'s always-on settings (`isFloatingPanel`, clear +
/// shadowed) but DIFFERS deliberately: `hidesOnDeactivate` is false (a shell
/// persists across app deactivation, where a transient popup auto-hides), and the
/// styleMask/level/collectionBehavior/key behavior all come from the spec.
@MainActor
public func makeWindowShell(_ spec: WindowShellSpec) -> ShellPanel {
    let p = ShellPanel(contentRect: .zero,
                       styleMask: spec.resolvedStyleMask,
                       backing: .buffered,
                       defer: false)
    p.keyMode = spec.keyMode
    p.isFloatingPanel = true
    p.becomesKeyOnlyIfNeeded = (spec.keyMode == .onDemand)
    p.hidesOnDeactivate = false           // long-lived: do NOT auto-hide on deactivate
    p.level = spec.level
    p.ignoresMouseEvents = spec.clickThrough
    p.hasShadow = spec.hasShadow
    p.isOpaque = spec.isOpaque
    p.backgroundColor = spec.backgroundColor
    p.collectionBehavior = spec.collectionBehavior
    return p
}

// MARK: - Screen union (a shell that spans every display)

/// The bounding rect spanning a set of screen frames, in the global screen space.
/// PURE over an injected frame list so the union math is unit-testable WITHOUT real
/// hardware (a single display ⇒ just that frame; an empty list ⇒ `.zero`). The live
/// `screenUnionFrame()` feeds this `NSScreen.screens`; the hardware-only part is the
/// hotplug RE-EVALUATION (`ScreenReconfigGlue`), not this geometry.
public func unionFrame(of frames: [CGRect]) -> CGRect {
    guard let first = frames.first else { return .zero }
    return frames.dropFirst().reduce(first) { $0.union($1) }
}

/// The union of all attached displays' frames — the contentRect for a shell that
/// must cover every Space/display (halo's all-Spaces overlay, a full-desktop scrim).
@MainActor
public func screenUnionFrame() -> CGRect {
    unionFrame(of: NSScreen.screens.map(\.frame))
}

/// Re-runs `onChange` whenever the display configuration changes (a monitor is
/// attached/detached/rearranged, resolution/arrangement edits), so a screen-spanning
/// shell can recompute `screenUnionFrame()` and re-`setFrame`. The union MATH is
/// covered by `unionFrame(of:)` tests; this live reflow needs real multi-display
/// hardware to exercise (single-display environments can't prove the reflow path).
@MainActor
public final class ScreenReconfigGlue {
    // `nonisolated(unsafe)`: read in the nonisolated `deinit` to remove the observer;
    // the token is dead in the owner by then, so there is no real concurrent access.
    nonisolated(unsafe) private var token: (any NSObjectProtocol)?

    public init() {}

    public func start(onChange: @escaping @MainActor () -> Void) {
        stop()
        token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onChange() }
            }
    }

    public func stop() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }

    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
}

// MARK: - Auto-size to content

/// Resize a shell to fit its content view's fitting size, pinning the TOP-LEFT so
/// growth flows down/right (a menu/popover grows from its anchored corner). Clamped
/// to `max` when given. Invalidates the borderless panel's cached silhouette shadow
/// (stale the instant a resize changes it — the #1 child-window bug, also baked into
/// `placePopup`). Call after the content's SwiftUI layout settles.
@MainActor
public func sizeShellToContent(_ panel: NSPanel, max maxSize: CGSize? = nil) {
    guard let content = panel.contentView else { return }
    var size = content.fittingSize
    if size.width <= 0 || size.height <= 0 {
        // An NSHostingView always reports a positive fittingSize; this fallback is for
        // a bare NSView. `intrinsicContentSize` is `noIntrinsicMetric` (-1) on a plain
        // view, so use it ONLY when positive — never collapse the panel to a negative
        // or zero frame; otherwise leave the current size untouched.
        let intrinsic = content.intrinsicContentSize
        guard intrinsic.width > 0, intrinsic.height > 0 else { return }
        size = intrinsic
    }
    if let maxSize {
        size.width = min(size.width, maxSize.width)
        size.height = min(size.height, maxSize.height)
    }
    let topLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
    panel.setContentSize(size)
    panel.setFrameTopLeftPoint(topLeft)
    panel.invalidateShadow()
}

// MARK: - Fade (the shell's own; separate from transient PopupFade)

/// Order a shell in/out with a window-opacity fade. The shell fades the WHOLE window
/// (`animator().alphaValue`) — robust regardless of content layer-backing — where the
/// transient `PopupFade` fades a content LAYER inside a shared `CATransaction`. The
/// fade-out's deferred `orderOut` is gated by the caller's monotonic generation token
/// (`shouldOrderOut`) so a quick re-show inside the fade can't be clobbered by a stale
/// completion. Duration defaults to the family's standard enter step.
@MainActor
public struct ShellFade {
    public var duration: TimeInterval

    public init(duration: TimeInterval = ThemedTransition.Duration.enter) {
        self.duration = duration
    }

    /// Order `panel` front and bring it to full opacity. Uses `orderFrontRegardless`
    /// (a non-activating shell must appear without activating the app).
    public func fadeIn(_ panel: NSWindow, animated: Bool = true) {
        panel.alphaValue = animated ? 0 : 1
        panel.orderFrontRegardless()
        guard animated else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// Fade `panel` to transparent, then `orderOut` — but only if `shouldOrderOut()`
    /// still holds when the animation completes (same fade generation, still hidden).
    /// Resets `alphaValue` to 1 after ordering out so the next non-animated show is
    /// visible.
    public func fadeOut(_ panel: NSWindow, animated: Bool = true,
                        shouldOrderOut: @escaping @MainActor () -> Bool = { true }) {
        guard animated else {
            if shouldOrderOut() { panel.orderOut(nil); panel.alphaValue = 1 }
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                if shouldOrderOut() { panel.orderOut(nil); panel.alphaValue = 1 }
            }
        })
    }
}

// MARK: - Esc / outside-click dismiss

/// Watches the dismissal gestures a long-lived shell wants — Escape and a mouse-down
/// OUTSIDE the panel — and calls `dismiss`. Consolidates the local-`NSEvent`-monitor
/// boilerplate the transient combo/menu each hand-wrote, for SHELL use:
///   - Esc: a local `keyDown` monitor (key code 53), installed only when `onEscape`.
///   - outside-click: a local `mouseDown` monitor that dismisses when the click's
///     window is NOT the shell (a click in another window of THIS app). Cross-app /
///     desktop clicks (which resign the window's key state) are the caller's to wire
///     (observe `didResignKey`, or reuse `PopupGlue`), exactly as the combo/menu split it.
/// The monitor closures always RETURN the event (never swallow input). Teardown is
/// safe from any thread: `stop()` on main, and a `deinit` backstop via `removeMonitorSafely`.
@MainActor
public final class ShellDismissMonitor {
    // `nonisolated(unsafe)`: read in the nonisolated `deinit` via `removeMonitorSafely`
    // (the transient combo/menu monitors use this same pattern); dead in the owner by
    // then, so no real concurrent access.
    nonisolated(unsafe) private var keyMon: Any?
    nonisolated(unsafe) private var clickMon: Any?
    private weak var panel: NSWindow?

    public init() {}

    public func start(panel: NSWindow,
                      onEscape: Bool = true,
                      onOutsideClick: Bool = true,
                      dismiss: @escaping @MainActor () -> Void) {
        stop()
        self.panel = panel
        if onEscape {
            keyMon = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
                if ev.keyCode == 53 { dismiss(); return nil }   // 53 = Escape; swallow it
                return ev
            }
        }
        if onOutsideClick {
            clickMon = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]) { [weak self] ev in
                    guard let self else { return ev }
                    if ev.window !== self.panel { dismiss() }
                    return ev                                   // never swallow the click
                }
        }
    }

    public func stop() {
        if let keyMon { NSEvent.removeMonitor(keyMon) }
        if let clickMon { NSEvent.removeMonitor(clickMon) }
        keyMon = nil
        clickMon = nil
        panel = nil
    }

    deinit {
        removeMonitorSafely(keyMon)
        removeMonitorSafely(clickMon)
    }
}
