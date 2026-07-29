// `composite(_:over:)` / `hueAngle(_:)` / `hueDistance(_:_:)` — the pure colour
// primitives the palette's derived roles need in order to be CHECKABLE at all.
//
// `contrastRatio` ignores alpha by design, and every derived role carries alpha
// (border neutral@0.10, hover neutral@0.05, selection primary@0.18, tertiary
// foreground@0.55, every ink()/surface() tier). So until now none of them could
// be swept, which is the structural reason legibility defects in that set have
// stayed invisible. `composite` is what makes them measurable; `hueDistance` is
// the independent axis contrast cannot express.
//
// Every expected value below was computed independently (in Python, from the
// WCAG formulae) BEFORE the Swift was written, and then re-confirmed against
// the built code — they are not transcriptions of what the implementation
// happened to return.
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
@testable import Palette

final class ColorMathTests: XCTestCase {

    func testFullAlphaReturnsTheInkUnchanged() {
        XCTAssertEqual(composite(HexColor(0xBD93F9, 1.0), over: HexColor(0x282A36)).rgb, 0xBD93F9)
    }

    func testZeroAlphaReturnsTheBaseUnchanged() {
        XCTAssertEqual(composite(HexColor(0xBD93F9, 0.0), over: HexColor(0x282A36)).rgb, 0x282A36)
    }

    func testResultIsAlwaysOpaque() {
        XCTAssertEqual(composite(HexColor(0xBD93F9, 0.18), over: HexColor(0x282A36)).alpha, 1.0)
    }

    /// Out-of-range alpha is clamped rather than producing a colour outside the
    /// gamut (a `HexColor` can be hand-built with any Double).
    func testAlphaIsClamped() {
        let base = HexColor(0x282A36), ink = HexColor(0xBD93F9)
        XCTAssertEqual(composite(HexColor(0xBD93F9, 2.0), over: base).rgb, ink.rgb)
        XCTAssertEqual(composite(HexColor(0xBD93F9, -1.0), over: base).rgb, base.rgb)
    }

    /// THE anchor case, and the reason this function exists: dracula's
    /// `selection` is `primary`@0.18, and a selected list row draws its
    /// secondary line in `muted` ON that wash. Flattened, the pair scores
    /// 2.1763 — under the 3:1 floor for supplementary text, and completely
    /// invisible to an alpha-ignoring contrast check.
    ///
    /// 2.1763 is the 8-BIT value (`HexColor` quantizes, and so does the
    /// framebuffer). The float-precision `PaletteKit.flatten` mirror scores
    /// 2.1796 on the same pair; both are correct, and a WCAG floor should be
    /// judged on the quantized one because that is the pixel shipped.
    func testDraculaSelectionWashAgainstMuted() {
        let flattened = composite(HexColor(0xBD93F9, 0.18), over: HexColor(0x282A36))
        XCTAssertEqual(flattened.rgb, 0x433D59, "the wash flattens to #433D59")
        XCTAssertEqual(contrastRatio(flattened, HexColor(0x6272A4)), 2.1763, accuracy: 0.001)
    }

    func testPrimaryHues() {
        XCTAssertEqual(hueAngle(HexColor(0xFF0000)), 0,   accuracy: 1e-9)
        XCTAssertEqual(hueAngle(HexColor(0x00FF00)), 120, accuracy: 1e-9)
        XCTAssertEqual(hueAngle(HexColor(0x0000FF)), 240, accuracy: 1e-9)
        XCTAssertEqual(hueAngle(HexColor(0x00FFFF)), 180, accuracy: 1e-9)
    }

    /// Greyscale has no hue. It must return 0 rather than dividing by a zero
    /// chroma — every neutral in the catalog goes through here.
    func testGreyscaleHueIsZeroAndDoesNotTrap() {
        for grey: UInt32 in [0x000000, 0x808080, 0xFFFFFF, 0x1A1A1A] {
            XCTAssertEqual(hueAngle(HexColor(grey)), 0)
        }
    }

    func testDistanceIsSymmetricAndTakesTheShortWayRound() {
        XCTAssertEqual(hueDistance(HexColor(0xFF0000), HexColor(0x00FF00)), 120, accuracy: 1e-9)
        XCTAssertEqual(hueDistance(HexColor(0x00FF00), HexColor(0xFF0000)), 120, accuracy: 1e-9)
        // red 0° vs blue 240° — the short way is 120°, not 240°.
        XCTAssertEqual(hueDistance(HexColor(0xFF0000), HexColor(0x0000FF)), 120, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(hueDistance(HexColor(0xFF0000), HexColor(0x0000FF)), 180)
    }

    func testDistanceToSelfIsZero() {
        XCTAssertEqual(hueDistance(HexColor(0x3B82F6), HexColor(0x3B82F6)), 0)
    }

    /// The case that proves contrast and hue are INDEPENDENT axes, and why a
    /// separation gate must use this one: solar-veil's `primary` (#FF5C7A) and
    /// `error` (#FF2D55) are 0.39° apart — the same colour as a signal — while
    /// scoring 1.23 on contrast, a number a WCAG-based check would happily read
    /// as "different enough".
    func testHueCatchesACollisionContrastCannotSee() {
        let primary = HexColor(0xFF5C7A), error = HexColor(0xFF2D55)
        XCTAssertEqual(hueDistance(primary, error), 0.3856, accuracy: 0.01)
        XCTAssertLessThan(contrastRatio(primary, error), 1.5,
                          "contrast alone rates this pair as nearly identical for the WRONG reason")
    }
}
