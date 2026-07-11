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

    func testIsAnimatableTheme() {
        XCTAssertTrue(isAnimatableTheme("rainbow"))   // cycles
        XCTAssertTrue(isAnimatableTheme("chomp"))     // flashes
        XCTAssertFalse(isAnimatableTheme("terminal")) // static theme
        XCTAssertFalse(isAnimatableTheme("dracula"))  // static theme
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

    // --- Pure border resolve (reconciles halo+facet BorderFX.color/.width) ---

    func testResolveBorderOff() {
        // No effect → .off (the app paints its own pal.primary / baseColor),
        // fixed base width, not flashing.
        let f = resolveBorder(spec: nil, baseWidth: 3, minWidth: nil, maxWidth: nil,
                              cycleSeconds: 6, cycleColors: false, now: 1.23, flash: nil)
        XCTAssertEqual(f.color, .off)
        XCTAssertEqual(f.width, 3, accuracy: 1e-12)
        XCTAssertFalse(f.flashing)
    }

    func testResolveBorderSteady() {
        // neon, no cycle → steady hex as sRGB rgb.
        let h = HexColor(EffectSpec.neon.steady)
        let f = resolveBorder(spec: .neon, baseWidth: 2, minWidth: nil, maxWidth: nil,
                              cycleSeconds: 6, cycleColors: false, now: 0.4, flash: nil)
        XCTAssertEqual(f.color, .rgb(r: h.r, g: h.g, b: h.b))
    }

    func testResolveBorderRainbowIsBareHue() {
        // cycles → bare hue == phase (app builds NSColor(hue:) — calibrated).
        let cs = 1.0, now = 0.137
        let f = resolveBorder(spec: .rainbow, baseWidth: 2, minWidth: nil, maxWidth: nil,
                              cycleSeconds: cs, cycleColors: false, now: now, flash: nil)
        let phase = (now / cs).truncatingRemainder(dividingBy: 1)
        XCTAssertEqual(f.color, .rainbowHue(phase))
    }

    func testResolveBorderCycleColorsBlend() {
        // cycleColors → blendThrough(spec.flash, phase) as rgb.
        let cs = 1.0, now = 0.3
        let phase = (now / cs).truncatingRemainder(dividingBy: 1)
        let c = blendThrough(EffectSpec.cyber.flash, at: phase)
        let f = resolveBorder(spec: .cyber, baseWidth: 2, minWidth: nil, maxWidth: nil,
                              cycleSeconds: cs, cycleColors: true, now: now, flash: nil)
        XCTAssertEqual(f.color, .rgb(r: c.r, g: c.g, b: c.b))
    }

    func testResolveBorderBreathingRaisedCosine() {
        // width breathes lo↔hi over phase (raised cosine); +1.5 only on flash.
        // phase 0 → pulse 0 → lo; phase 0.5 → pulse 1 → hi.
        let lo = 1.0, hi = 5.0, cs = 1.0
        let at0 = resolveBorder(spec: .neon, baseWidth: 3, minWidth: lo, maxWidth: hi,
                                cycleSeconds: cs, cycleColors: false, now: 0.0, flash: nil)
        let atHalf = resolveBorder(spec: .neon, baseWidth: 3, minWidth: lo, maxWidth: hi,
                                   cycleSeconds: cs, cycleColors: false, now: 0.5, flash: nil)
        XCTAssertEqual(at0.width, lo, accuracy: 1e-9)
        XCTAssertEqual(atHalf.width, hi, accuracy: 1e-9)
    }

    func testResolveBorderNoBreathWhenBoundsInverted() {
        // hi <= lo → no breathing, fixed base width.
        let f = resolveBorder(spec: .neon, baseWidth: 3, minWidth: 5, maxWidth: 1,
                              cycleSeconds: 1, cycleColors: false, now: 0.5, flash: nil)
        XCTAssertEqual(f.width, 3, accuracy: 1e-12)
    }

    func testResolveBorderFlashWinsAndPopsWidth() {
        // Mid-burst: color is the blink, width gets the +1.5 pop, flashing true.
        let seq: [UInt32] = [0x00E5FF, 0xFF00FF, 0x39FF14, 0xFE019A, 0x04D9FF]
        let fs = FlashState(seq: seq, startedAt: 0)
        let now = (2.0 + 0.5) / 30.0                 // → index 2
        let f = resolveBorder(spec: .neon, baseWidth: 3, minWidth: nil, maxWidth: nil,
                              cycleSeconds: 1, cycleColors: false, now: now, flash: fs)
        let h = HexColor(seq[2])
        XCTAssertEqual(f.color, .rgb(r: h.r, g: h.g, b: h.b))
        XCTAssertEqual(f.width, 3 + 1.5, accuracy: 1e-12)
        XCTAssertTrue(f.flashing)
    }

    func testResolveBorderFlashSettlesToSteady() {
        // Past the 5-blink burst → falls back to steady, no width pop.
        let seq: [UInt32] = [0x00E5FF, 0xFF00FF]
        let fs = FlashState(seq: seq, startedAt: 0)
        let f = resolveBorder(spec: .neon, baseWidth: 3, minWidth: nil, maxWidth: nil,
                              cycleSeconds: 1, cycleColors: false, now: 10.0, flash: fs)
        let h = HexColor(EffectSpec.neon.steady)
        XCTAssertEqual(f.color, .rgb(r: h.r, g: h.g, b: h.b))
        XCTAssertEqual(f.width, 3, accuracy: 1e-12)
        XCTAssertFalse(f.flashing)
    }

    func testRollFlashShapeAndNoConsecutiveRepeat() {
        let palette: [UInt32] = [0x00E5FF, 0xFF00FF, 0x39FF14, 0xFE019A, 0x04D9FF]
        for _ in 0..<500 {
            guard let r = rollFlash(palette, now: 0) else { return XCTFail("nil on non-empty") }
            XCTAssertEqual(r.seq.count, 5)
            XCTAssertTrue(r.seq.allSatisfy { palette.contains($0) })
            for i in 1..<r.seq.count { XCTAssertNotEqual(r.seq[i], r.seq[i-1]) }
        }
    }

    func testRollFlashEmptyAndSingle() {
        XCTAssertNil(rollFlash([], now: 0))
        // single-color palette must not spin: 5 copies of the one color.
        XCTAssertEqual(rollFlash([0xABCDEF], now: 0)?.seq, Array(repeating: UInt32(0xABCDEF), count: 5))
    }

    func testFlashStateIndexDecay() {
        let d = FlashState(seq: [1, 2, 3, 4, 5], startedAt: 10)
        XCTAssertEqual(d.index(now: 10), 0)
        XCTAssertEqual(d.index(now: 10 + 4.9 / 30), 4)
        XCTAssertNil(d.index(now: 10 + 5.5 / 30))     // settled
        XCTAssertNil(d.index(now: 9))                 // before start
        XCTAssertTrue(d.isActive(now: 10))
        XCTAssertFalse(d.isActive(now: 11))
    }

    // --- Animated palette ---

    func testAnimatedFlashEffect() {
        // chomp at phase 0 = flash[0] = pellet yellow 0xFFEA00.
        let f = animatedPalette(theme: "chomp", at: 0.0)
        XCTAssertNotNil(f)
        let s = f!.primary.usingColorSpace(.sRGB)!
        XCTAssertEqual(s.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(s.greenComponent, CGFloat(0xEA) / 255, accuracy: 0.01)
        XCTAssertEqual(s.blueComponent, 0, accuracy: 0.01)
    }

    func testAnimatedCyclesEffectIsHueRotation() {
        // A cycling theme (rainbow) walks a FULL-SATURATION hue that ROTATES
        // with the phase — primary hue == frac(phase), secondary the opposite
        // half-turn, both at saturation 0.95 / brightness 1 (animatedPalette's
        // `fx.cycles` branch). Pins the actual HSB, not just non-nil: a swapped
        // rotation, a dropped phase-wrap, or a desaturated path now fails.
        func primaryHSB(_ p: CGFloat) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
            let c = animatedPalette(theme: "rainbow", at: p)!.primary
                .usingColorSpace(.sRGB)!
            return (c.hueComponent, c.saturationComponent, c.brightnessComponent)
        }
        // Hue TRACKS the phase (this is the rotation) — not a constant.
        XCTAssertEqual(primaryHSB(0.25).h, 0.25, accuracy: 0.02)
        XCTAssertEqual(primaryHSB(0.5).h,  0.5,  accuracy: 0.02)
        XCTAssertEqual(primaryHSB(0.75).h, 0.75, accuracy: 0.02)
        // Full-saturation, full-brightness (the "full-saturation hue" claim).
        XCTAssertEqual(primaryHSB(0.25).s, 0.95, accuracy: 0.03)
        XCTAssertEqual(primaryHSB(0.25).b, 1.0,  accuracy: 0.02)
        // Secondary sits a half-turn opposite on the wheel (h + 0.5 mod 1).
        let sec = animatedPalette(theme: "rainbow", at: 0.0)!.secondary
            .usingColorSpace(.sRGB)!
        XCTAssertEqual(sec.hueComponent, 0.5, accuracy: 0.02)
        // Phase wraps: 1.25 ≡ 0.25.
        XCTAssertEqual(primaryHSB(1.25).h, primaryHSB(0.25).h, accuracy: 0.001)
    }

    func testAnimatedReturnsNilForStaticTheme() {
        XCTAssertNil(animatedPalette(theme: "terminal", at: 0.5))
        XCTAssertNil(animatedPalette(theme: "off", at: 0.5))
    }

    /// The animated selection alpha must match the theme's static
    /// selection — 0.18 for chomp (authored), the authored 0.22 for
    /// rainbow — so the selected-row wash doesn't jump when animation
    /// engages, AND rainbow's explicit 0.22 is preserved.
    func testAnimatedSelectionHonorsAuthoredAlpha() {
        let chomp = animatedPalette(theme: "chomp", at: 0.3)!
        XCTAssertEqual(chomp.selection.usingColorSpace(.sRGB)!.alphaComponent,
                       0.18, accuracy: 0.001)
        let rainbow = animatedPalette(theme: "rainbow", at: 0.3)!
        XCTAssertEqual(rainbow.selection.usingColorSpace(.sRGB)!.alphaComponent,
                       0.22, accuracy: 0.001)
    }

    // --- Line-pets (pure identity) ---

    func testLinePetRawValues() {
        XCTAssertEqual(LinePet.chomp.rawValue, "chomp")
        XCTAssertEqual(LinePet.ghost.rawValue, "ghost")
    }

    func testLinePetParsesFromName() {
        XCTAssertEqual(LinePet(rawValue: "chomp"), .chomp)
        XCTAssertEqual(LinePet(rawValue: "ghost"), .ghost)
        XCTAssertNil(LinePet(rawValue: "pacman"))
    }

    func testCanonicalLinePetNames() {
        XCTAssertEqual(canonicalLinePetNames, ["chomp", "ghost"])
        XCTAssertEqual(LinePet.allCases.count, 2)
    }

    func testLinePetPositionWalksPerimeter() {
        // linePetPosition walks the rect perimeter top → right → bottom → left,
        // returning centre + travel-direction rotation. Pinned on a NON-origin
        // rect (10,20,100,40 ⇒ perim 280) so minX/minY handling is exercised.
        // rot per edge: top 0, right -π/2, bottom π, left π/2.
        let r = CGRect(x: 10, y: 20, width: 100, height: 40)
        func at(_ t: CGFloat) -> (x: CGFloat, y: CGFloat, rot: CGFloat) {
            linePetPosition(on: r, distance: t)
        }
        let acc: CGFloat = 1e-9
        // Top edge — y = maxY, moving +x, rot 0.
        XCTAssertEqual(at(0).x,  10, accuracy: acc); XCTAssertEqual(at(0).y,  60, accuracy: acc)
        XCTAssertEqual(at(0).rot, 0, accuracy: acc)
        XCTAssertEqual(at(50).x, 60, accuracy: acc); XCTAssertEqual(at(50).y, 60, accuracy: acc)
        // Right edge — x = maxX, moving -y, rot -π/2.
        XCTAssertEqual(at(100).x, 110, accuracy: acc); XCTAssertEqual(at(100).y, 60, accuracy: acc)
        XCTAssertEqual(at(100).rot, -.pi / 2, accuracy: acc)
        XCTAssertEqual(at(120).y, 40, accuracy: acc)
        // Bottom edge — y = minY, moving -x, rot π.
        XCTAssertEqual(at(140).x, 110, accuracy: acc); XCTAssertEqual(at(140).y, 20, accuracy: acc)
        XCTAssertEqual(at(140).rot, .pi, accuracy: acc)
        XCTAssertEqual(at(190).x, 60, accuracy: acc)
        // Left edge — x = minX, moving +y, rot π/2.
        XCTAssertEqual(at(240).x, 10, accuracy: acc); XCTAssertEqual(at(240).y, 20, accuracy: acc)
        XCTAssertEqual(at(240).rot, .pi / 2, accuracy: acc)
        XCTAssertEqual(at(260).y, 40, accuracy: acc)
    }
}
