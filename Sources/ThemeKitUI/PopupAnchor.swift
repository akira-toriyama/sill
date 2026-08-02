// ThemeKitUI — the ONE AppKit escape the popup family keeps OUTSIDE the panel
// shell (floor-2 plumbing, ruled 2026-08-02): SwiftUI has no window or screen
// coordinate space (`CoordinateSpace` is `.global/.local/.named` only — measured
// against the macOS 26.5 SDK), so a floor-2 popup controller that needs
// `present(from: NSView)` — the host window for PopupGlue's move/resize/close
// observation, the anchor's screen rect for `placePopup`, the `clickIsInside`
// anchor exemption, and the scroll-clip / `visibleRect` dismiss — anchors to
// THIS invisible, hit-test-transparent NSView, laid under a SwiftUI trigger via
// `.background` so it is coextensive with the trigger's frame. Every popup
// behavior (window-resize follow, scroll-out dismiss, outside-click exemption)
// keeps its existing NSView-based mechanism unchanged.
//
// This entry is PERMANENT in `scripts/appkit-floor.sh` — the target end state
// of the AppKit 床外し epic is three allow-list lines: the floor-1 IME edit
// core, the floor-3 rich-text draw core, and this proxy. Do not add further
// NSViewRepresentable structs for anchoring; route new popup consumers through
// this one.

import SwiftUI
import AppKit

/// The invisible anchor. Hit-test transparent so it can never intercept a
/// click aimed at the SwiftUI trigger drawn over it; hover is still observable
/// through an `NSTrackingArea` (tracking areas fire by geometry, not by
/// hit-test ownership — the `ThemedTooltip` mechanism).
final class PopupAnchorNSView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Bridges a SwiftUI trigger to a popup CONTROLLER that needs a real NSView
/// anchor. `attach` runs once with the freshly made anchor view and returns the
/// controller (the coordinator retains it — the ThemedTooltip/ThemedMenu
/// "caller MUST retain" contract); `update` re-drives the controller's value
/// inputs on every SwiftUI update; `detach` runs at dismantle for deterministic
/// teardown (`invalidate()`).
struct PopupAnchorProxy<Controller: AnyObject>: NSViewRepresentable {
    let attach: @MainActor (NSView) -> Controller
    let update: @MainActor (Controller) -> Void
    let detach: @MainActor (Controller) -> Void

    /// `dismantleNSView` is static, so the coordinator carries BOTH the retained
    /// controller and the `detach` closure that tears it down.
    final class Coordinator {
        var controller: Controller?
        var detach: (@MainActor (Controller) -> Void)?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PopupAnchorNSView {
        let v = PopupAnchorNSView()
        context.coordinator.controller = attach(v)
        context.coordinator.detach = detach
        return v
    }

    func updateNSView(_ v: PopupAnchorNSView, context: Context) {
        if let c = context.coordinator.controller { update(c) }
    }

    static func dismantleNSView(_ v: PopupAnchorNSView, coordinator: Coordinator) {
        if let c = coordinator.controller { coordinator.detach?(c) }
        coordinator.controller = nil
        coordinator.detach = nil
    }
}
