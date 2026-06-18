// ThemeKit tests — ThemedBorder: the universal surface border. Asserts the two
// modes via the DEBUG `borderProbe` (no screenshot, no running clock): no effect →
// a flat `primary` stroke with no glow; a frozen effect → a cycled hue with the
// bloom glow; the master `effectsEnabled = false` → rest back to the primary
// stroke even with an effect set. (Headless = no window ⇒ never animating, which is
// itself the correct lifecycle assertion.)
//
// Scope of these probes: they assert the STATIC and FROZEN frames + the clock state.
// The LIVE 30 Hz cycle and reduce-motion gating only engage with a visible window, so
// they are verified live in prism (the maintainer hand-check), not here — headless,
// motionOK is always false, so `reduceMotionRespected` can't catch a real violation.
// The static-stroke colour assertions also assume a concrete-RGB `primary` (the themes
// used below), NOT a `usesSystemPrimary` (controlAccent) theme whose colour is dynamic.

import XCTest
import AppKit
@testable import ThemeKit
import Palette
import PaletteKit
import Effects

@MainActor
final class ThemedBorderTests: XCTestCase {

    private func srgb(_ c: CGColor?) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let c, let ns = NSColor(cgColor: c)?.usingColorSpace(.sRGB) else { return nil }
        return (ns.redComponent, ns.greenComponent, ns.blueComponent)
    }
    private func primarySRGB(_ p: ResolvedPalette) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let s = p.primary.usingColorSpace(.sRGB) ?? p.primary
        return (s.redComponent, s.greenComponent, s.blueComponent)
    }
    private func near(_ a: (r: CGFloat, g: CGFloat, b: CGFloat)?,
                      _ b: (r: CGFloat, g: CGFloat, b: CGFloat), _ acc: CGFloat = 0.02) -> Bool {
        guard let a else { return false }
        return abs(a.r - b.r) < acc && abs(a.g - b.g) < acc && abs(a.b - b.b) < acc
    }

    private func sized(_ b: ThemedBorder) {
        b.frame = NSRect(x: 0, y: 0, width: 120, height: 60)
        b.layoutSubtreeIfNeeded()
    }

    /// No effect → a flat `primary` stroke, no glow, no running clock.
    func testStaticIsPrimaryNoGlow() {
        let p = resolve(paletteFor("dracula"))
        let b = ThemedBorder(palette: p, effect: nil)
        sized(b)
        let probe = b.borderProbe
        XCTAssertFalse(probe.isAnimating)                 // no window + no effect
        XCTAssertFalse(probe.glows)
        XCTAssertTrue(near(srgb(probe.strokeColor), primarySRGB(p)))
        XCTAssertTrue(probe.reduceMotionRespected)
    }

    /// Effect + frozen → an effect hue with the bloom glow (the capture path).
    func testFrozenEffectGlowsAndDiffersFromPrimary() {
        let p = resolve(paletteFor("dracula"))
        let b = ThemedBorder(palette: p, effect: .rainbow)
        b.previewPhase = 0.35
        b.previewFrozen = true
        sized(b)
        let probe = b.borderProbe
        XCTAssertFalse(probe.isAnimating)                 // frozen ⇒ no clock
        XCTAssertTrue(probe.glows)                        // .bloom
        XCTAssertFalse(near(srgb(probe.strokeColor), primarySRGB(p)))   // a cycled hue
    }

    /// The master switch OFF rests to the static primary stroke even with an
    /// effect set — the 派手好き-ON / 静か-OFF contract.
    func testEffectsDisabledRestsToPrimary() {
        let p = resolve(paletteFor("rainbow"))
        let b = ThemedBorder(palette: p, effect: .rainbow)
        b.effectsEnabled = false
        sized(b)
        let probe = b.borderProbe
        XCTAssertFalse(probe.glows)
        XCTAssertFalse(probe.isAnimating)
        XCTAssertTrue(near(srgb(probe.strokeColor), primarySRGB(p)))
    }

    /// Re-theming swaps the static stroke to the new palette's primary.
    func testRethemeUpdatesStaticStroke() {
        let a = resolve(paletteFor("dracula"))
        let b = ThemedBorder(palette: a, effect: nil)
        sized(b)
        let other = resolve(paletteFor("github-light"))   // a real catalog theme, distinct primary
        b.palette = other
        sized(b)
        XCTAssertTrue(near(srgb(b.borderProbe.strokeColor), primarySRGB(other)))
    }
}
