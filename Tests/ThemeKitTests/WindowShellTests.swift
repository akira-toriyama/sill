// ThemeKit / WindowShell tests — DETERMINISTIC in headless CI (no Xcode locally →
// these first compile + run in CI). They pin the PURE / POLICY surface of the public
// window-shell factory: the screen-union geometry (verifiable WITHOUT a second
// display via injected frames), the spec → styleMask mapping, the spec → panel
// property propagation, the keyMode → key-eligibility semantics, auto-size clamping,
// and the screen-reconfig observer wiring. The LIVE window behaviors a shell adds
// (key-on-demand focus, click-through, the multi-display hotplug REFLOW, Esc /
// outside-click dismiss) need real hardware + focus and are proven LIVE in prism /
// the perch pilot, not asserted here.

import XCTest
import AppKit
@testable import ThemeKit

@MainActor
final class WindowShellTests: XCTestCase {

    // MARK: - Screen union (pure; single-display safe)

    func testUnionFrameEmptyIsZero() {
        XCTAssertEqual(unionFrame(of: []), .zero)
    }

    func testUnionFrameSingleIsThatFrame() {
        let f = CGRect(x: 10, y: 20, width: 300, height: 400)
        XCTAssertEqual(unionFrame(of: [f]), f)
    }

    func testUnionFrameSpansAllDisplays() {
        // A 1440-wide main display + a second display to its right, 100pt lower.
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 1440, y: -100, width: 1920, height: 1080)
        let u = unionFrame(of: [main, right])
        XCTAssertEqual(u.minX, 0)
        XCTAssertEqual(u.minY, -100)
        XCTAssertEqual(u.maxX, 1440 + 1920)
        XCTAssertEqual(u.maxY, 980)            // right's top wins: y=-100 + height 1080 = 980 > main's 900
        XCTAssertEqual(u.width, 3360)
        XCTAssertEqual(u.height, 1080)         // 980 − (−100)
    }

    func testUnionFrameHandlesNegativeOrigins() {
        let a = CGRect(x: -500, y: -300, width: 200, height: 200)
        let b = CGRect(x: 100, y: 100, width: 200, height: 200)
        let u = unionFrame(of: [a, b])
        XCTAssertEqual(u, CGRect(x: -500, y: -300, width: 800, height: 600))
    }

    // MARK: - Spec → styleMask mapping

    func testStyleMaskBorderlessNonactivatingByDefault() {
        let mask = WindowShellSpec().resolvedStyleMask
        XCTAssertTrue(mask.contains(.borderless))
        XCTAssertTrue(mask.contains(.nonactivatingPanel))
        XCTAssertFalse(mask.contains(.titled))
    }

    func testStyleMaskBorderlessWithoutNonactivating() {
        let mask = WindowShellSpec(chrome: .borderless, nonactivating: false).resolvedStyleMask
        XCTAssertTrue(mask.contains(.borderless))
        XCTAssertFalse(mask.contains(.nonactivatingPanel))
    }

    func testStyleMaskTitledResizableClosable() {
        let mask = WindowShellSpec(chrome: .titled(resizable: true, closable: true)).resolvedStyleMask
        XCTAssertTrue(mask.contains(.titled))
        XCTAssertTrue(mask.contains(.resizable))
        XCTAssertTrue(mask.contains(.closable))
    }

    func testStyleMaskTitledNonResizableNonClosable() {
        let mask = WindowShellSpec(chrome: .titled(resizable: false, closable: false)).resolvedStyleMask
        XCTAssertTrue(mask.contains(.titled))
        XCTAssertFalse(mask.contains(.resizable))
        XCTAssertFalse(mask.contains(.closable))
    }

    func testStyleMaskHUD() {
        let mask = WindowShellSpec(chrome: .hud).resolvedStyleMask
        XCTAssertTrue(mask.contains(.hudWindow))
        XCTAssertTrue(mask.contains(.utilityWindow))
        XCTAssertTrue(mask.contains(.titled))
    }

    // MARK: - Spec → panel property propagation

    func testFactoryPropagatesSpecToPanel() {
        let spec = WindowShellSpec(level: .popUpMenu,
                                   collectionBehavior: [.canJoinAllSpaces, .ignoresCycle],
                                   clickThrough: true,
                                   hasShadow: false,
                                   isOpaque: true)
        let p = makeWindowShell(spec)
        XCTAssertEqual(p.level, .popUpMenu)
        XCTAssertTrue(p.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(p.collectionBehavior.contains(.ignoresCycle))
        XCTAssertTrue(p.ignoresMouseEvents)
        XCTAssertFalse(p.hasShadow)
        XCTAssertTrue(p.isOpaque)
        XCTAssertTrue(p.isFloatingPanel)
        XCTAssertFalse(p.hidesOnDeactivate)        // long-lived: shells do NOT auto-hide
    }

    // MARK: - keyMode → key eligibility

    func testKeyModeNeverCannotBecomeKey() {
        let p = makeWindowShell(WindowShellSpec(keyMode: .never))
        XCTAssertFalse(p.canBecomeKey)
        XCTAssertFalse(p.becomesKeyOnlyIfNeeded)
    }

    func testKeyModeOnDemandIsKeyOnlyIfNeeded() {
        let p = makeWindowShell(WindowShellSpec(keyMode: .onDemand))
        XCTAssertTrue(p.canBecomeKey)
        XCTAssertTrue(p.becomesKeyOnlyIfNeeded)
    }

    func testKeyModeAlwaysCanBecomeKey() {
        let p = makeWindowShell(WindowShellSpec(keyMode: .always))
        XCTAssertTrue(p.canBecomeKey)
        XCTAssertFalse(p.becomesKeyOnlyIfNeeded)
    }

    // MARK: - Auto-size to content

    func testSizeShellToContentClampsAndPinsTopLeft() {
        let p = makeWindowShell(WindowShellSpec())
        p.setFrame(NSRect(x: 100, y: 200, width: 50, height: 40), display: false)
        let label = NSTextField(labelWithString: "A reasonably long label string")
        p.contentView = label
        let topBefore = p.frame.maxY

        sizeShellToContent(p)
        let fit = label.fittingSize
        XCTAssertGreaterThan(fit.width, 0)
        XCTAssertEqual(p.contentView!.frame.width, fit.width, accuracy: 0.5)
        XCTAssertEqual(p.frame.maxY, topBefore, accuracy: 0.5)   // top-left stays pinned

        sizeShellToContent(p, max: CGSize(width: 10, height: 8))
        XCTAssertLessThanOrEqual(p.contentView!.frame.width, 10.5)
        XCTAssertLessThanOrEqual(p.contentView!.frame.height, 8.5)
    }

    // MARK: - Screen-reconfig observer wiring

    func testScreenReconfigGlueFiresOnScreenParameterChange() {
        let glue = ScreenReconfigGlue()
        let exp = expectation(description: "screen reconfig callback")
        glue.start { exp.fulfill() }
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification,
                                        object: nil)
        wait(for: [exp], timeout: 2)
        glue.stop()
    }

    func testScreenReconfigGlueStopSilencesCallback() {
        let glue = ScreenReconfigGlue()
        var fired = false
        glue.start { fired = true }
        glue.stop()
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification,
                                        object: nil)
        // Drain the main queue so any (erroneously) still-registered block would run.
        let drain = expectation(description: "drain")
        DispatchQueue.main.async { drain.fulfill() }
        wait(for: [drain], timeout: 2)
        XCTAssertFalse(fired)
    }

    // MARK: - Dismiss monitor lifecycle (firing is hardware/focus — proven live)

    func testDismissMonitorStopIsIdempotent() {
        let monitor = ShellDismissMonitor()
        let p = makeWindowShell(WindowShellSpec())
        monitor.start(panel: p) { }
        monitor.stop()
        monitor.stop()                                   // idempotent, no crash
    }
}
