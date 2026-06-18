// PaletteKit tests — the LIVE-accent composition (`ResolvedPalette.applying`
// and `.animated(forTheme:at:)`), which grafts an Effects `AnimatedFrame` onto
// a resolved palette: the frame's three accent atoms replace primary /
// secondary / selection while every other role is held byte-identical, and a
// non-animatable theme returns `self` unchanged. `AnimatedFrame` has no public
// initialiser, so the frames here come from the real `animatedPalette(theme:)`.

import XCTest
import AppKit
@testable import Palette
@testable import PaletteKit
import Effects

@MainActor
final class AnimatedPaletteTests: XCTestCase {

    private func comps(_ c: NSColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let s = c.usingColorSpace(.sRGB) ?? c
        return (s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent)
    }

    /// sRGB-component equality (NSColor `==` is colour-space-sensitive; the
    /// accent atoms come back in HSB/sRGB, so compare resolved components).
    private func sameColor(_ a: NSColor, _ b: NSColor, accuracy: CGFloat = 0.001) -> Bool {
        let x = comps(a), y = comps(b)
        return abs(x.r - y.r) < accuracy && abs(x.g - y.g) < accuracy
            && abs(x.b - y.b) < accuracy && abs(x.a - y.a) < accuracy
    }

    /// `applying` swaps EXACTLY the accent trio to the frame's atoms (same
    /// NSColor objects — a reference type) and holds every other role
    /// identity-stable.
    func testApplyingSwapsOnlyAccentTrio() {
        let base = resolve(paletteFor("dracula"))
        let frame = animatedPalette(theme: "rainbow", at: 0.3)!
        let lit = base.applying(frame)

        // accent trio is the frame's atoms (identical references)
        XCTAssertTrue(lit.primary === frame.primary)
        XCTAssertTrue(lit.secondary === frame.secondary)
        XCTAssertTrue(lit.selection === frame.selection)

        // everything else is the SAME object as the base — nothing recomputed
        XCTAssertTrue(lit.background === base.background)
        XCTAssertTrue(lit.foreground === base.foreground)
        XCTAssertTrue(lit.muted === base.muted)
        XCTAssertTrue(lit.tertiary === base.tertiary)
        XCTAssertTrue(lit.border === base.border)
        XCTAssertTrue(lit.hover === base.hover)
        XCTAssertTrue(lit.error === base.error)
        XCTAssertEqual(lit.font, base.font)
        XCTAssertEqual(lit.backgroundAlpha, base.backgroundAlpha)
        XCTAssertEqual(lit.vibrancyMaterial, base.vibrancyMaterial)
        XCTAssertEqual(lit.forceDarkAqua, base.forceDarkAqua)

        // and the accent genuinely changed (rainbow@0.3 ≠ dracula's accents)
        XCTAssertFalse(sameColor(lit.primary, base.primary))
        XCTAssertFalse(sameColor(lit.secondary, base.secondary))
    }

    /// A theme with no effect entry is a no-op: `animated` returns `self`, so a
    /// caller can drive it every frame without branching on animatability.
    func testAnimatedNonAnimatableReturnsSelf() {
        let base = resolve(paletteFor("dracula"))
        let still = base.animated(forTheme: "dracula", at: 0.42)
        XCTAssertTrue(still.primary === base.primary)
        XCTAssertTrue(still.secondary === base.secondary)
        XCTAssertTrue(still.selection === base.selection)
        XCTAssertTrue(still.foreground === base.foreground)
    }

    /// For an animatable theme, `animated` == `applying(animatedPalette(…))`,
    /// and the non-accent roles stay steady.
    func testAnimatedComposesFrame() {
        let base = resolve(paletteFor("github-light"))   // a light theme
        let phase: CGFloat = 0.42
        let lit = base.animated(forTheme: "rainbow", at: phase)
        let frame = animatedPalette(theme: "rainbow", at: phase)!

        XCTAssertTrue(sameColor(lit.primary, frame.primary))
        XCTAssertTrue(sameColor(lit.secondary, frame.secondary))
        XCTAssertTrue(sameColor(lit.selection, frame.selection))
        XCTAssertTrue(lit.foreground === base.foreground)   // steady
        XCTAssertTrue(lit.background === base.background)
        XCTAssertTrue(lit.border === base.border)

        // The animated selection alpha tracks the EFFECT theme's authored value
        // (rainbow = 0.22), matching its static resolve — so the selected-row
        // wash doesn't jump alpha the instant animation engages.
        let staticRainbowSelection = resolve(paletteFor("rainbow")).selection
        XCTAssertEqual(comps(lit.selection).a, comps(staticRainbowSelection).a, accuracy: 0.001)
    }

    /// Phase is taken modulo 1, so a whole-turn offset gives the same accent —
    /// what a wall-clock-driven caller relies on for no jump at the wrap.
    func testPhaseWrapsModuloOne() {
        let base = resolve(paletteFor("dracula"))
        let a = base.animated(forTheme: "chomp", at: 0.3)    // flash effect
        let b = base.animated(forTheme: "chomp", at: 1.3)
        XCTAssertTrue(sameColor(a.primary, b.primary))
        XCTAssertTrue(sameColor(a.secondary, b.secondary))
        XCTAssertTrue(sameColor(a.selection, b.selection))
    }
}
