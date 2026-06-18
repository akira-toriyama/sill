// ThemeKit / ThemedTooltip tests — DETERMINISTIC in headless CI (no Xcode
// locally → these first compile + run in CI). The bubble is driven via
// `previewVisible` (the force-show seam) and read through the DEBUG
// `tooltipProbe`; no synthetic mouse events. The live hover-show / fade /
// placement-flip 演出 is proven in prism, not here. Placement assertions need a
// screen — guarded with XCTSkip so a truly headless box doesn't hard-fail.

import XCTest
import AppKit
import Palette
import PaletteKit
@testable import ThemeKit   // for the DEBUG `tooltipProbe` + the internal `Side`

@MainActor
final class ThemedTooltipTests: XCTestCase {

    private func theme(_ name: String = "terminal") -> ResolvedPalette {
        resolve(paletteFor(name))
    }

    /// CGColor identity is fragile across resolve()/colour-space conversions —
    /// compare resolved sRGB components (incl. alpha) within tolerance.
    private func sameColor(_ a: CGColor?, _ b: NSColor, accuracy: CGFloat = 0.01,
                           _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
        guard let a, let an = NSColor(cgColor: a)?.usingColorSpace(.sRGB),
              let bn = b.usingColorSpace(.sRGB) else {
            return XCTFail("colour unconvertible: \(msg)", file: file, line: line)
        }
        XCTAssertEqual(an.redComponent,   bn.redComponent,   accuracy: accuracy, msg, file: file, line: line)
        XCTAssertEqual(an.greenComponent, bn.greenComponent, accuracy: accuracy, msg, file: file, line: line)
        XCTAssertEqual(an.blueComponent,  bn.blueComponent,  accuracy: accuracy, msg, file: file, line: line)
        XCTAssertEqual(an.alphaComponent, bn.alphaComponent, accuracy: accuracy, msg, file: file, line: line)
    }

    /// Best-contrast ink on a fill — mirrors the widget's local helper via the
    /// SAME pure Palette functions, so the expected value can't drift.
    private func contrastInk(on c: NSColor) -> NSColor {
        let s = c.usingColorSpace(.sRGB) ?? c
        let l = wcagRelativeLuminance(r: Double(s.redComponent),
                                      g: Double(s.greenComponent), b: Double(s.blueComponent))
        return prefersBlackForeground(fillRelLuminance: l) ? .black : .white
    }

    /// A borderless host window whose contentView IS the anchor, so the anchor's
    /// on-screen rect equals the window frame (no chrome). Returns the strong
    /// refs the caller must keep alive (the tooltip holds the anchor weakly).
    private func anchored(at frame: NSRect, text: String = "Add item",
                          _ p: ResolvedPalette? = nil,
                          placement: ThemedTooltip.Placement = .auto)
        -> (NSWindow, NSView, ThemedTooltip) {
        let win = NSWindow(contentRect: frame, styleMask: [.borderless],
                           backing: .buffered, defer: true)
        let anchor = NSView(frame: NSRect(origin: .zero, size: frame.size))
        win.contentView = anchor
        let tip = ThemedTooltip(anchor: anchor, text: text,
                                palette: p ?? theme(), placement: placement)
        return (win, anchor, tip)
    }

    // MARK: - Placement + flip

    func testFlipsAwayFromScreenEdges() throws {
        guard let vf = NSScreen.main?.visibleFrame else { throw XCTSkip("no screen") }
        let p = theme()

        // Bottom edge → a default .bottom bubble overflows below → flip to .top.
        let (w1, _, t1) = anchored(at: NSRect(x: vf.midX - 20, y: vf.minY + 1, width: 40, height: 24), p)
        t1.previewVisible = true
        let pr1 = t1.tooltipProbe
        XCTAssertEqual(pr1.resolvedSide, .top, "a bottom-edge anchor flips the bubble up")
        XCTAssertTrue(vf.contains(pr1.bubbleFrame), "the flipped bubble stays within the visible frame")
        _ = w1

        // Top edge + explicit .top preference → overflows above → flip to .bottom.
        let (w2, _, t2) = anchored(at: NSRect(x: vf.midX - 20, y: vf.maxY - 25, width: 40, height: 24),
                                   p, placement: .top)
        t2.previewVisible = true
        let pr2 = t2.tooltipProbe
        XCTAssertEqual(pr2.resolvedSide, .bottom, "a top-edge anchor flips a .top bubble down")
        XCTAssertTrue(vf.contains(pr2.bubbleFrame), "stays within the visible frame")
        _ = w2
    }

    func testArrowPointsAtAnchorCentre() throws {
        guard let vf = NSScreen.main?.visibleFrame else { throw XCTSkip("no screen") }
        // Anchor centred at vf.midX, mid-screen → no cross clamp, no flip.
        let (w, _, t) = anchored(at: NSRect(x: vf.midX - 20, y: vf.midY, width: 40, height: 24))
        t.previewVisible = true
        let pr = t.tooltipProbe
        let apexX = pr.bubbleFrame.minX + pr.arrowCross   // top/bottom side: cross = x
        XCTAssertEqual(apexX, vf.midX, accuracy: 0.5,
                       "the arrow points at the anchor's horizontal centre")
        _ = w
    }

    func testLongTextWrapsWithinMaxWidth() throws {
        guard NSScreen.main != nil else { throw XCTSkip("no screen") }
        let p = theme()
        let long = "This is a fairly long tooltip hint that should wrap onto multiple lines rather than running off the screen forever and ever."
        let (w, _, t) = anchored(at: NSRect(x: 400, y: 400, width: 40, height: 24), text: long, p)
        t.previewVisible = true
        let tall = t.tooltipProbe.bubbleFrame
        XCTAssertLessThanOrEqual(tall.width, 300.5, "wraps within the 300pt max width")

        let (w2, _, t2) = anchored(at: NSRect(x: 400, y: 400, width: 40, height: 24), text: "Hi", p)
        t2.previewVisible = true
        XCTAssertGreaterThan(tall.height, t2.tooltipProbe.bubbleFrame.height,
                             "a long wrapped hint is taller than a one-word hint")
        _ = w; _ = w2
    }

    // MARK: - Inverted themed colours (light + dark presets)

    func testColoursMatchInvertedSurface() {
        for name in ["github-light", "dracula", "cyberpunk"] {
            let p = theme(name)
            let (w, _, t) = anchored(at: NSRect(x: 400, y: 400, width: 40, height: 24), p)
            t.previewVisible = true
            let pr = t.tooltipProbe
            sameColor(pr.fillColor, p.foreground.withAlphaComponent(0.92),
                      "fill = foreground@0.92 (\(name))")
            sameColor(pr.textColor, contrastInk(on: p.foreground),
                      "text = best-contrast on the foreground (\(name))")
            XCTAssertEqual(pr.cornerRadius, 4, accuracy: 0.01, "MUI corner radius (\(name))")
            _ = w
        }
    }

    // MARK: - Delays, AX, lifecycle

    func testDelayDefaults() {
        let (w, _, t) = anchored(at: NSRect(x: 300, y: 300, width: 40, height: 24))
        XCTAssertEqual(t.enterDelay, 0.5, accuracy: 0.0001, "macOS-feel enter delay")
        XCTAssertEqual(t.leaveDelay, 0.1, accuracy: 0.0001, "anti-flicker leave delay")
        _ = w
    }

    func testAccessibilityHelpMirrorsTextAndNoNativeTag() {
        let (w, anchor, t) = anchored(at: NSRect(x: 300, y: 300, width: 40, height: 24))
        XCTAssertEqual(anchor.accessibilityHelp(), "Add item", "AX help mirrors the text")
        XCTAssertNil(anchor.toolTip, "the native tooltip tag is cleared (no double-fire)")
        t.text = "Changed"
        XCTAssertEqual(anchor.accessibilityHelp(), "Changed", "AX help follows a text change")
        _ = w
    }

    func testShowHideTogglesVisibility() {
        let (w, _, t) = anchored(at: NSRect(x: 300, y: 300, width: 40, height: 24))
        XCTAssertFalse(t.tooltipProbe.isVisible, "starts hidden")
        t.show()
        XCTAssertTrue(t.tooltipProbe.isVisible, "show() presents the bubble")
        t.hide()
        XCTAssertFalse(t.tooltipProbe.isVisible, "hide() takes it down synchronously")
        _ = w
    }

    func testEmptyTextNeverShows() {
        let (w, _, t) = anchored(at: NSRect(x: 300, y: 300, width: 40, height: 24))
        t.text = ""
        t.show()
        XCTAssertFalse(t.tooltipProbe.isVisible, "an empty tooltip never shows")
        _ = w
    }

    private func settle(_ seconds: TimeInterval = 0.30) {
        let e = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { e.fulfill() }
        wait(for: [e], timeout: 2.0)
    }

    /// Regression: a re-show inside the 0.16 s fade-out must supersede the
    /// pending `orderOut` completion — the bubble must NOT silently vanish when
    /// the fade finishes. (Before the fade-token fix the stale completion ordered
    /// the freshly re-shown panel out while `isShown` stayed true.)
    func testReshowSupersedesPendingFadeOut() {
        let (w, _, t) = anchored(at: NSRect(x: 300, y: 300, width: 40, height: 24))
        t.show()
        // Some headless hosts won't actually order a panel on screen; only then
        // is the window-level assertion meaningful (the logical state is checked
        // regardless).
        let canOrder = t.tooltipProbe.panelOrderedIn
        XCTAssertTrue(t.tooltipProbe.isVisible, "shown")
        t.hide()                               // starts the (animated) fade-out
        t.show()                               // re-show before it completes → supersede
        XCTAssertTrue(t.tooltipProbe.isVisible, "re-show keeps it logically visible")
        settle(0.30)                           // let the stale completion fire (and be ignored)
        let pr = t.tooltipProbe
        XCTAssertTrue(pr.isVisible, "state stays shown after the fade interval")
        if canOrder {
            XCTAssertTrue(pr.panelOrderedIn,
                          "the stale fade-out completion did NOT order the re-shown panel out")
        }
        _ = w
    }

    /// The preview / capture seam force-shows WITHOUT a fade — deterministic in
    /// CI regardless of the system reduce-motion setting (a previewed bubble must
    /// never attach an opacity animation, so a static screenshot is stable).
    func testPreviewVisibleSnapsWithoutAnimation() {
        let (w, _, t) = anchored(at: NSRect(x: 300, y: 300, width: 40, height: 24))
        t.previewVisible = true
        let pr = t.tooltipProbe
        XCTAssertFalse(pr.hasOpacityAnimation, "previewVisible snaps — no fade animation attached")
        XCTAssertTrue(pr.reduceMotionRespected, "and so it can never violate reduce-motion")
        _ = w
    }

    func testInvalidateTearsDown() {
        let (w, anchor, t) = anchored(at: NSRect(x: 300, y: 300, width: 40, height: 24))
        t.previewVisible = true
        XCTAssertTrue(t.tooltipProbe.isVisible, "shown")
        XCTAssertFalse(anchor.trackingAreas.isEmpty, "tracking area installed on the anchor")
        t.invalidate()
        XCTAssertFalse(t.tooltipProbe.isVisible, "hidden after invalidate()")
        XCTAssertTrue(anchor.trackingAreas.isEmpty, "tracking area removed after invalidate()")
        // Idempotent.
        t.invalidate()
        XCTAssertFalse(t.tooltipProbe.isVisible, "invalidate() is idempotent")
        _ = w
    }

    func testAttachReturnsRetainedController() {
        let (w, anchor, _) = anchored(at: NSRect(x: 300, y: 300, width: 40, height: 24))
        // A fresh anchor in the same window for the attach convenience.
        let a2 = NSView(frame: NSRect(x: 0, y: 0, width: 30, height: 20))
        anchor.addSubview(a2)
        let tip = ThemedTooltip.attach(to: a2, text: "Hi", palette: theme())
        XCTAssertEqual(a2.accessibilityHelp(), "Hi", "attach() wires the AX help")
        XCTAssertFalse(a2.trackingAreas.isEmpty, "attach() installs the hover tracking area")
        tip.invalidate()
        _ = w
    }
}
