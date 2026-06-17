// ThemeKit / ThemedFAB tests — DETERMINISTIC in headless CI (no Xcode locally →
// these first compile + run in CI). State is driven via the preview… overrides
// and read through the DEBUG `fabProbe` — no synthetic events. The live float /
// hover-press 演出 is proven in still, not here.

import XCTest
import AppKit
import Palette
import PaletteKit
@testable import ThemeKit   // for the DEBUG `fabProbe`

@MainActor
final class ThemedFABTests: XCTestCase {

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
    private func alpha(_ c: CGColor?) -> CGFloat {
        guard let c, let n = NSColor(cgColor: c)?.usingColorSpace(.sRGB) else { return -1 }
        return n.alphaComponent
    }
    /// Best-contrast ink on a fill — mirrors PaletteKit's onPrimary/onSecondary
    /// path via the SAME pure Palette helpers, so the expected value can't drift.
    private func contrastInk(on c: NSColor) -> NSColor {
        let s = c.usingColorSpace(.sRGB) ?? c
        let l = wcagRelativeLuminance(r: Double(s.redComponent),
                                      g: Double(s.greenComponent), b: Double(s.blueComponent))
        return prefersBlackForeground(fillRelLuminance: l) ? .black : .white
    }

    /// A FAB laid out at its own intrinsic size (square for circular, pill for
    /// extended), so `cornerRadius` / geometry reflect the real metrics.
    private func fab(_ palette: ResolvedPalette,
                     _ configure: (ThemedFAB) -> Void = { _ in }) -> ThemedFAB {
        let f = ThemedFAB(palette: palette)
        f.leadingSymbol = "plus"
        configure(f)
        f.frame = NSRect(origin: .zero, size: f.intrinsicContentSize)
        f.layoutSubtreeIfNeeded()
        return f
    }

    private func spaceDown(isARepeat: Bool = false) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: " ",
            charactersIgnoringModifiers: " ", isARepeat: isARepeat, keyCode: 49)!
    }
    private func returnEvent(_ mods: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0,
            windowNumber: 0, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
    }
    private func settle(_ seconds: TimeInterval = 0.25) {
        let e = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { e.fulfill() }
        wait(for: [e], timeout: 1.0)
    }

    // MARK: - Geometry / the circle + pill invariant

    func testCircularIsSquareAndFullyRound() {
        let p = theme()
        for (sz, d): (ThemedFAB.Size, CGFloat) in [(.small, 40), (.medium, 48), (.large, 56)] {
            let f = fab(p) { $0.variant = .circular; $0.size = sz }
            XCTAssertEqual(f.frame.width,  d, "circular \(sz) diameter")
            XCTAssertEqual(f.frame.height, d, "circular \(sz) is square")
            XCTAssertEqual(f.fabProbe.cornerRadius, d / 2, accuracy: 0.5,
                           "cornerRadius = height/2 → a perfect circle when square")
        }
    }

    func testExtendedHeightAndPillRadius() {
        let p = theme()
        for (sz, h): (ThemedFAB.Size, CGFloat) in [(.small, 34), (.medium, 40), (.large, 48)] {
            let f = fab(p) { $0.variant = .extended; $0.size = sz; $0.label = "Create" }
            XCTAssertEqual(f.frame.height, h, "extended \(sz) height")
            XCTAssertEqual(f.fabProbe.cornerRadius, h / 2, accuracy: 0.5, "pill ends = height/2")
            XCTAssertGreaterThan(f.frame.width, h, "an extended FAB is wider than it is tall")
        }
    }

    /// `layout()` reads the radius from `min(bounds.w, bounds.h)/2`, NOT the
    /// metric — so a host that stretches the view can't deform the round end
    /// into a pill. (The showcase pins a square frame to avoid this; the widget
    /// itself stays safe if a host doesn't.)
    func testCornerRadiusTracksShorterSideWhenStretched() {
        let f = ThemedFAB(palette: theme())
        f.variant = .circular
        f.leadingSymbol = "plus"
        f.frame = NSRect(x: 0, y: 0, width: 56, height: 120)   // host stretches it tall
        f.layoutSubtreeIfNeeded()
        XCTAssertEqual(f.fabProbe.cornerRadius, 28, accuracy: 0.5,
                       "radius tracks the shorter side (56/2 = 28), not the taller (120) → no pill deform")
    }

    func testCircularIgnoresLabelWidth() {
        let p = theme()
        let bare    = fab(p) { $0.variant = .circular; $0.label = "" }
        let labeled = fab(p) { $0.variant = .circular; $0.label = "A very long label" }
        XCTAssertEqual(bare.intrinsicContentSize.width, labeled.intrinsicContentSize.width,
                       "circular width is the diameter, independent of the (AX-only) label")
        XCTAssertTrue(labeled.fabProbe.titleHidden, "circular never draws the label")
        let ext = fab(p) { $0.variant = .extended; $0.label = "Create" }
        XCTAssertFalse(ext.fabProbe.titleHidden, "extended draws the label")
        XCTAssertGreaterThan(ext.intrinsicContentSize.width,
                             fab(p) { $0.variant = .extended; $0.label = "Hi" }.intrinsicContentSize.width,
                             "a longer label widens an extended FAB")
    }

    // MARK: - Elevation (floats higher than a button; press deepens; no hover bump)

    func testElevationLadder() {
        let p = theme()
        let rest = fab(p) { $0.variant = .circular }.fabProbe
        XCTAssertEqual(rest.shadowOpacity, 0.30, accuracy: 0.001, "resting ≈ dp6")
        XCTAssertEqual(rest.shadowRadius, 8, accuracy: 0.01)
        // offsetY is NEGATIVE: isFlipped=false (y-up) so a downward shadow is −y.
        XCTAssertEqual(rest.shadowOffsetY, -3, accuracy: 0.01, "resting shadow points down (y-up)")

        let hover = fab(p) { $0.variant = .circular; $0.previewHovered = true }.fabProbe
        XCTAssertEqual(hover.shadowOpacity, 0.30, accuracy: 0.001, "hover does NOT bump a FAB's elevation")
        XCTAssertEqual(hover.shadowRadius, 8, accuracy: 0.01)
        XCTAssertEqual(hover.shadowOffsetY, -3, accuracy: 0.01, "hover keeps the resting offset")

        let focus = fab(p) { $0.variant = .circular; $0.previewFocused = true }.fabProbe
        XCTAssertEqual(focus.shadowOpacity, 0.30, accuracy: 0.001, "focus does NOT bump elevation")

        let press = fab(p) { $0.variant = .circular; $0.previewPressed = true }.fabProbe
        XCTAssertEqual(press.shadowOpacity, 0.34, accuracy: 0.001, "pressed ≈ dp12")
        XCTAssertEqual(press.shadowRadius, 12, accuracy: 0.01)
        XCTAssertEqual(press.shadowOffsetY, -7, accuracy: 0.01, "pressed shadow drops further (still −y)")

        let off = fab(p) { $0.variant = .circular; $0.isEnabled = false }.fabProbe
        XCTAssertEqual(off.shadowOpacity, 0, "disabled is flat (no float)")
        XCTAssertEqual(off.shadowOffsetY, 0, accuracy: 0.01, "disabled has no shadow offset")
    }

    // MARK: - Fill + ink by role, across themes (incl. neon + light)

    func testFillAndInkByRoleAcrossThemes() {
        for name in ["cyberpunk", "github-light", "terminal"] {
            let p = theme(name)
            let prim = fab(p) { $0.role = .primary }.fabProbe
            sameColor(prim.fillColor, p.primary, "primary fill (\(name))")
            sameColor(prim.inkColor, p.onPrimary(), "primary ink = onPrimary (\(name))")

            let sec = fab(p) { $0.role = .secondary }.fabProbe
            sameColor(sec.fillColor, p.secondary, "secondary fill (\(name))")
            sameColor(sec.inkColor, p.onSecondary(), "secondary ink = onSecondary (\(name))")
        }
    }

    func testDisabledFillAndInkMuted() {
        let p = theme()
        let f = fab(p) { $0.isEnabled = false }.fabProbe
        sameColor(f.fillColor, p.ink(.subtle, of: .muted), "disabled fill = a muted wash")
        sameColor(f.inkColor, p.muted, "disabled ink = muted")
    }

    // MARK: - State layer (overlay) + focus ring

    func testOverlayAlphas() {
        let p = theme()
        XCTAssertEqual(alpha(fab(p) { $0.variant = .circular }.fabProbe.overlayColor), 0,
                       accuracy: 0.001, "resting shows no state layer")
        XCTAssertEqual(alpha(fab(p) { $0.previewHovered = true }.fabProbe.overlayColor), 0.08,
                       accuracy: 0.001, "hover overlay = 0.08")
        XCTAssertEqual(alpha(fab(p) { $0.previewPressed = true }.fabProbe.overlayColor), 0.12,
                       accuracy: 0.001, "pressed overlay = 0.12")
        XCTAssertEqual(alpha(fab(p) { $0.previewFocused = true }.fabProbe.overlayColor), 0,
                       accuracy: 0.001, "focus shows the ring only, no wash")
    }

    func testFocusRingPrimaryBothRoles() {
        let p = theme()
        for role in [ThemedFAB.Role.primary, .secondary] {
            let f = fab(p) { $0.role = role; $0.previewFocused = true }.fabProbe
            XCTAssertEqual(f.focusRingOpacity, 1, "focus ring shown")
            sameColor(f.focusRingStroke, p.primary, "focus ring = primary regardless of role")
        }
        XCTAssertEqual(fab(p).fabProbe.focusRingOpacity, 0, "ring hidden when not focused")
    }

    func testDisabledSuppressesForcedHoverFocus() {
        let p = theme()
        let f = fab(p) { $0.isEnabled = false; $0.previewHovered = true; $0.previewFocused = true }.fabProbe
        XCTAssertEqual(alpha(f.overlayColor), 0, accuracy: 0.001, "disabled = no hover overlay")
        XCTAssertEqual(f.focusRingOpacity, 0, "disabled = no focus ring")
        XCTAssertEqual(f.shadowOpacity, 0, "disabled = no float")
    }

    // MARK: - PaletteKit onSecondary (the library change this FAB shipped)

    func testOnSecondaryAccessorIsBestContrast() {
        for name in ["cyberpunk", "github-light", "terminal", "dracula"] {
            let p = theme(name)
            sameColor(p.onSecondary().cgColor, contrastInk(on: p.secondary),
                      "onSecondary = best-contrast black/white on the secondary fill (\(name))")
            XCTAssertEqual(p.onSecondaryStroke.alphaComponent, 0.4, accuracy: 0.001,
                           "onSecondaryStroke = the contrast ink @ 0.4 (\(name))")
        }
    }

    // MARK: - Activation + accessibility

    /// Space on a focused FAB flashes then fires onTap (after the 0.12 s flash).
    func testSpaceActivatesOnTap() {
        let f = fab(theme())
        let exp = expectation(description: "space → onTap")
        f.onTap = { exp.fulfill() }
        f.keyDown(with: spaceDown())
        wait(for: [exp], timeout: 1.0)
    }

    func testDisabledIgnoresSpace() {
        let f = fab(theme()) { $0.isEnabled = false }
        var fired = false
        f.onTap = { fired = true }
        f.keyDown(with: spaceDown())
        settle()
        XCTAssertFalse(fired, "a disabled FAB does not activate on Space")
    }

    /// A held Space (auto-repeat) and a rapid second press inside the 0.12 s
    /// flash both collapse to ONE activation (the isFlashing + isARepeat guards).
    func testSpaceActivatesExactlyOncePerPress() {
        let f = fab(theme())
        var count = 0
        f.onTap = { count += 1 }
        f.keyDown(with: spaceDown())                 // press
        f.keyDown(with: spaceDown(isARepeat: true))  // auto-repeat — ignored
        f.keyDown(with: spaceDown())                 // 2nd press inside the flash — dropped
        settle()
        XCTAssertEqual(count, 1, "one activation per press; repeats/overlaps suppressed")
    }

    /// Disabling during the 0.12 s flash cancels the pending activation
    /// (activate() re-checks isEnabled).
    func testDisableDuringFlashCancelsActivation() {
        let f = fab(theme())
        var fired = false
        f.onTap = { fired = true }
        f.keyDown(with: spaceDown())   // schedules the flash
        f.isEnabled = false            // disable inside the 0.12 s window
        settle()
        XCTAssertFalse(fired, "an async disable mid-flash cancels the activation")
    }

    /// Return activates only a FAB that opted in (keyEquivalent "\r"); an unset
    /// FAB must NOT swallow Return.
    func testReturnDefaultGatedOnKeyEquivalent() {
        let plain = fab(theme())
        var plainFired = false
        plain.onTap = { plainFired = true }
        XCTAssertFalse(plain.performKeyEquivalent(with: returnEvent()),
                       "an unset FAB does not claim Return")
        settle()
        XCTAssertFalse(plainFired, "and never activates from it")

        let def = fab(theme()) { $0.keyEquivalent = "\r" }
        let exp = expectation(description: "default FAB fires on Return")
        def.onTap = { exp.fulfill() }
        XCTAssertTrue(def.performKeyEquivalent(with: returnEvent()),
                      "the opted-in FAB claims Return")
        wait(for: [exp], timeout: 1.0)
    }

    /// A modifier mismatch (⌘Return) does not trigger a plain-Return default.
    func testReturnKeyEquivalentRespectsModifierMask() {
        let def = fab(theme()) { $0.keyEquivalent = "\r" }
        var fired = false
        def.onTap = { fired = true }
        XCTAssertFalse(def.performKeyEquivalent(with: returnEvent(.command)),
                       "⌘Return does not match a no-modifier key equivalent")
        settle()
        XCTAssertFalse(fired)
    }

    func testTargetActionStorage() {
        final class Sink: NSObject { @objc func tap() {} }
        let f = fab(theme())
        let sink = Sink()
        f.target = sink
        f.action = #selector(Sink.tap)
        XCTAssertTrue(f.target === sink, "cell-less control stores target")
        XCTAssertEqual(f.action, #selector(Sink.tap), "cell-less control stores action")
    }

    func testAccessibility() {
        let f = fab(theme()) { $0.label = "Add item" }
        XCTAssertEqual(f.accessibilityRole(), .button)
        XCTAssertEqual(f.accessibilityLabel(), "Add item", "AX label keeps the original case")
        // A circular FAB draws no text but still exposes `label` for VoiceOver.
        let circ = fab(theme()) { $0.variant = .circular; $0.label = "Add" }
        XCTAssertEqual(circ.accessibilityLabel(), "Add",
                       "circular uses the (undrawn) label as its AX name")
    }
}
