// ThemeKitUI — the AppKit shell (floor #2: non-key popup + its mouse routing) that hosts
// the SwiftUI `HostedThemedList` inside a combo/menu panel (#17b M3). It lives in
// ThemeKitUI (not ThemeKit) because ThemeKitUI→ThemeKit is the load-bearing wrap edge
// (the SwiftUI widget front wraps the AppKit widgets); the reverse would cycle. Per the
// AppKit policy the popup shell IS a ThemeKitUI floor. It exists for ONE reason SwiftUI
// can't do in a non-key panel: fire the row-click commit on the SAME runloop tick as
// `mouseUp` (a SwiftUI tap can slip a tick and lose to the field editor's async blur
// reconcile — the combo's `isCommitting`/`pointerInPopup` guards need the commit first).
// Hover is driven off a tracking area for the same non-key reason. All drawing / theming
// / data stay in the SwiftUI layer; this view only maps a pointer back to a row id.
import AppKit
import SwiftUI

@MainActor
public final class HostingListView<ID: Hashable & Sendable>: NSHostingView<HostedThemedList<ID>> {
    private weak var controller: ListController<ID>?
    private var tracking: NSTrackingArea?

    public init(controller: ListController<ID>, rootView: HostedThemedList<ID>) {
        self.controller = controller
        super.init(rootView: rootView)
    }
    @available(*, unavailable) public required init(rootView: HostedThemedList<ID>) { fatalError("use init(controller:rootView:)") }
    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    // The panel is non-key; take the first click without a focus round-trip so the
    // combo's "type, then click a row" never eats the first mouseUp (mirrors
    // ThemedList.acceptsFirstMouse). The list never becomes first responder.
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override var acceptsFirstResponder: Bool { false }

    /// Pointer in the SwiftUI viewport space (top-left origin, y-down) so it lines up
    /// with the `rowRects` reported via `RowRectPreference`. NSHostingView is normally
    /// flipped; guard the un-flipped case so hit-testing survives either way.
    private func viewportPoint(_ event: NSEvent) -> CGPoint {
        var p = convert(event.locationInWindow, from: nil)
        if !isFlipped { p.y = bounds.height - p.y }
        return p
    }

    public override func mouseUp(with event: NSEvent) {
        if let id = controller?.row(at: viewportPoint(event)) {
            controller?.fireActivate(id)          // SYNCHRONOUS — same tick as mouseUp
        } else {
            super.mouseUp(with: event)
        }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp],
                                owner: self, userInfo: nil)
        addTrackingArea(ta)
        tracking = ta
    }

    public override func mouseMoved(with event: NSEvent) {
        controller?.setHover(controller?.row(at: viewportPoint(event)))
    }
    public override func mouseExited(with event: NSEvent) { controller?.setHover(nil) }
}
