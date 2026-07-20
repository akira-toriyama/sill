// ThemeKitUI / PopupPanel tests — the shared popup shell every themed popup
// (tooltip · combo dropdown · menu) is built from.
//
// The one behaviour worth pinning here is `hidesOnDeactivate`, because getting
// it wrong is SILENT: an `.accessory` (LSUIElement) host never becomes active,
// so `hidesOnDeactivate = true` makes AppKit order the panel out the instant it
// is shown — no error, no warning, the caller's own "presented" log line still
// fires, and the screen stays empty. wand shipped into exactly that as the
// family's first ThemedMenu adopter (t-cp90). A future "simplify" back to a
// constant `true` would silently re-break every accessory host, so the decision
// is pinned rather than left to the comment.

import XCTest
import AppKit
@testable import ThemeKitUI

@MainActor
final class PopupPanelTests: XCTestCase {

    // MARK: - The policy decision (pure)

    func testAccessoryHostNeverHidesOnDeactivate() {
        // The fatal case: an accessory app is never active, so hiding on
        // deactivate means never showing at all.
        XCTAssertFalse(popupHidesOnDeactivate(.accessory))
    }

    func testRegularHostHidesOnDeactivate() {
        // A borderless panel gets no free hide-on-deactivate, so a normal app
        // still wants it — switching away must not leave a popup floating.
        XCTAssertTrue(popupHidesOnDeactivate(.regular))
    }

    func testProhibitedHostHidesOnDeactivate() {
        // `.prohibited` has no UI at all; it can't be the odd one out — only
        // `.accessory` (the "runs without activating" policy) is special.
        XCTAssertTrue(popupHidesOnDeactivate(.prohibited))
    }

    // MARK: - The factory actually applies it

    /// Proves the wiring, not just the predicate: the panel the widgets are
    /// built from reads the LIVE host policy. Activation policy is global
    /// state, so each case restores it. `NSApplication.shared` (not `NSApp`)
    /// for the same reason the factory uses it — `NSApp` is nil until the
    /// singleton is first touched, which in a test bundle depends on which
    /// tests ran before this one.
    private func panelFlag(under policy: NSApplication.ActivationPolicy) -> Bool {
        let app = NSApplication.shared
        let saved = app.activationPolicy()
        app.setActivationPolicy(policy)
        defer { app.setActivationPolicy(saved) }
        return themedPopupPanel(interactive: true, role: .menu).hidesOnDeactivate
    }

    func testFactoryReadsAccessoryPolicy() {
        XCTAssertFalse(panelFlag(under: .accessory),
                       "an accessory host's popup must survive its permanently-inactive app")
    }

    func testFactoryReadsRegularPolicy() {
        XCTAssertTrue(panelFlag(under: .regular),
                      "a regular host keeps the hide-on-deactivate it needs")
    }
}
