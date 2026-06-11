// Effects tests — the shared dynamic atom: EffectSpec catalog, pure
// blendThrough, and the AppKit animatedPalette. Pure parts need no
// AppKit; animatedPalette is @MainActor.

import XCTest
import AppKit
@testable import Palette
@testable import Effects

@MainActor
final class EffectsTests: XCTestCase {

    // --- Pure: EffectSpec catalog + borderEffectFor ---

    func testBuiltinEffectsResolve() {
        XCTAssertEqual(borderEffectFor("neon")?.steady, 0x7AA2F7)
        XCTAssertEqual(borderEffectFor("neon")?.flash.first, 0x00E5FF)
        XCTAssertEqual(borderEffectFor("chomp")?.steady, 0x2121FF)
        XCTAssertTrue(borderEffectFor("rainbow")?.cycles ?? false)
        XCTAssertFalse(borderEffectFor("neon")?.cycles ?? true)
        XCTAssertNil(borderEffectFor("off"))
        XCTAssertNil(borderEffectFor("nonexistent"))
    }

    func testChompInCanonicalEffectNames() {
        XCTAssertTrue(canonicalEffectNames.contains("chomp"))
    }

    // --- Pure: blendThrough ---

    func testBlendThroughEndpoints() {
        let red = blendThrough([0xFF0000, 0x00FF00], at: 0.0)
        XCTAssertEqual(red.r, 1, accuracy: 0.001)
        XCTAssertEqual(red.g, 0, accuracy: 0.001)
    }

    func testBlendThroughMidpoint() {
        // phase 0.25 of a 2-color loop = halfway red→green.
        let mid = blendThrough([0xFF0000, 0x00FF00], at: 0.25)
        XCTAssertEqual(mid.r, 0.5, accuracy: 0.02)
        XCTAssertEqual(mid.g, 0.5, accuracy: 0.02)
    }

    func testBlendThroughSingleColor() {
        let c = blendThrough([0x3366FF], at: 0.7)
        XCTAssertEqual(c.r, CGFloat(0x33) / 255, accuracy: 0.001)
        XCTAssertEqual(c.b, 1, accuracy: 0.001)
    }

    // --- Animated palette ---

    func testAnimatedFlashEffect() {
        // chomp at phase 0 = flash[0] = pellet yellow 0xFFEA00.
        let f = animatedPalette(theme: "chomp", at: 0.0)
        XCTAssertNotNil(f)
        let s = f!.accent.usingColorSpace(.sRGB)!
        XCTAssertEqual(s.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(s.greenComponent, CGFloat(0xEA) / 255, accuracy: 0.01)
        XCTAssertEqual(s.blueComponent, 0, accuracy: 0.01)
    }

    func testAnimatedCyclesEffectIsHueRotation() {
        // rainbow cycles ⇒ full-saturation hue at the phase.
        let f = animatedPalette(theme: "rainbow", at: 0.0)
        XCTAssertNotNil(f)
    }

    func testAnimatedReturnsNilForStaticTheme() {
        XCTAssertNil(animatedPalette(theme: "terminal", at: 0.5))
        XCTAssertNil(animatedPalette(theme: "off", at: 0.5))
    }

    /// GQ8: the animated selFill alpha must match the theme's static
    /// selFill — 0.18 for the derived themes (neon), the authored 0.22 for
    /// rainbow — so the selected-row wash doesn't jump when animation
    /// engages, AND rainbow's explicit 0.22 is preserved.
    func testAnimatedSelFillHonorsAuthoredAlpha() {
        let neon = animatedPalette(theme: "neon", at: 0.3)!
        XCTAssertEqual(neon.selFill.usingColorSpace(.sRGB)!.alphaComponent,
                       0.18, accuracy: 0.001)
        let rainbow = animatedPalette(theme: "rainbow", at: 0.3)!
        XCTAssertEqual(rainbow.selFill.usingColorSpace(.sRGB)!.alphaComponent,
                       0.22, accuracy: 0.001)
    }
}
