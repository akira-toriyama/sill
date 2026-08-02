// ThemedButtonGroupView (SwiftUI-native) — REAL RENDER tests, not logic tests.
//
// The widget no longer produces an AppKit view to reach into (ThemedButtonGroup's
// `groupProbe` tests stay on the AppKit widget, which AppKit hosts still use),
// so the evidence is the drawn side itself: rasterise through `ImageRenderer`
// and read pixels back. What matters here is JOINED geometry, which no colour
// probe can see — the seam stroked ONCE rather than twice, the outer corners
// rounded while the interior seam corners stay square, the 1 pt outlined
// overlap collapsing the intrinsic width, the focus ring following its own
// member's corner mask, and the segmented active tier landing on exactly one
// member.
//
// The fixture is `titles: ["", "", ""]`: every member floors at the 64 pt
// `minWidth`, so every coordinate below is font-independent. Horizontal
// outlined medium ⇒ 190 × 36 pt, members at x [0,64) [63,127) [126,190), and
// the surviving seam stroke is the LATER member's leading edge at x = 63.5.
// (All of those were measured against the AppKit widget before being written
// down — the two agree on all 12 configurations that were compared.)
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
@testable import Palette
@testable import PaletteKit
@testable import ThemeKit
@testable import ThemeKitUI

@MainActor
final class ThemedButtonGroupRenderTests: XCTestCase {

    /// A fixed opaque backdrop for the low-alpha strokes. `ResolvedPalette`'s own
    /// `background` is OPTIONAL, so a literal keeps every composited expectation
    /// unambiguous.
    private let backdrop = NSColor(srgbRed: 0.15, green: 0.16, blue: 0.20, alpha: 1)

    private let dracula = resolve(Theme.dracula.spec)
    private let gruvbox = resolve(Theme.gruvbox.spec)
    private let cobalt  = resolve(Theme.cobalt2.spec)

    /// Three members, every one floored at `minWidth`.
    private let empty3 = ["", "", ""]

    override func setUp() {
        super.setUp()
        setPalette(cobalt)
    }

    // MARK: - raster helpers (the ThemedChipRenderTests idiom)

    private let scale: CGFloat = 2

    private func render<V: View>(_ view: V) -> Raster {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let img = renderer.cgImage else {
            XCTFail("ImageRenderer produced no image")
            return Raster(px: [], w: 0, h: 0)
        }
        var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: img.width, height: img.height,
                                bitsPerComponent: 8, bytesPerRow: img.width * 4, space: cs,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        }
        return Raster(px: buf, w: img.width, h: img.height)
    }

    private func renderOn<V: View>(_ bg: NSColor, _ view: V) -> Raster {
        render(ZStack { Color(nsColor: bg); view })
    }

    private struct Raster {
        let px: [UInt8]; let w: Int; let h: Int
        func at(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
            let i = (y * w + x) * 4
            let a = Double(px[i + 3]) / 255
            guard a > 0 else { return (0, 0, 0, 0) }
            return (Double(px[i]) / 255 / a, Double(px[i + 1]) / 255 / a,
                    Double(px[i + 2]) / 255 / a, a)
        }
    }

    private func sRGB(_ c: NSColor) -> (r: Double, g: Double, b: Double, a: Double) {
        let s = c.usingColorSpace(.sRGB)!
        return (Double(s.redComponent), Double(s.greenComponent),
                Double(s.blueComponent), Double(s.alphaComponent))
    }

    private func assertHue(_ got: (r: Double, g: Double, b: Double, a: Double),
                           is expected: NSColor, _ message: String,
                           tolerance: Double = 0.03,
                           file: StaticString = #filePath, line: UInt = #line) {
        let e = sRGB(expected)
        XCTAssertEqual(got.r, e.r, accuracy: tolerance, "\(message) (r)", file: file, line: line)
        XCTAssertEqual(got.g, e.g, accuracy: tolerance, "\(message) (g)", file: file, line: line)
        XCTAssertEqual(got.b, e.b, accuracy: tolerance, "\(message) (b)", file: file, line: line)
    }

    private func assertHueDiffers(_ got: (r: Double, g: Double, b: Double, a: Double),
                                  from unexpected: NSColor, _ message: String,
                                  tolerance: Double = 0.03,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let e = sRGB(unexpected)
        let same = abs(got.r - e.r) <= tolerance && abs(got.g - e.g) <= tolerance
            && abs(got.b - e.b) <= tolerance
        XCTAssertFalse(same, message, file: file, line: line)
    }

    private func blend(_ over: NSColor, on bg: NSColor) -> NSColor {
        let o = sRGB(over), b = sRGB(bg)
        return NSColor(srgbRed: o.r * o.a + b.r * (1 - o.a),
                       green: o.g * o.a + b.g * (1 - o.a),
                       blue: o.b * o.a + b.b * (1 - o.a), alpha: 1)
    }

    private func dpx(_ pt: CGFloat) -> Int { Int(pt * scale) }

    /// The centre of member `i` in the empty-title fixture: 64 pt members
    /// stepping by `64 − overlap`.
    private func memberCentre(_ i: Int, overlap: CGFloat = 1) -> Int {
        dpx(CGFloat(i) * (64 - overlap) + 32)
    }
    /// The surviving seam stroke between members `i` and `i+1`.
    private func seamX(_ i: Int, overlap: CGFloat = 1) -> Int {
        dpx(CGFloat(i + 1) * (64 - overlap) + (overlap > 0 ? 0.5 : -0.5))
    }

    private func group(_ titles: [String] = [], _ build: ([String]) -> ThemedButtonGroupView)
        -> ThemedButtonGroupView { build(titles.isEmpty ? empty3 : titles) }

    // MARK: - intrinsic geometry

    func testOutlinedIntrinsicCollapsesTheSeams() {
        let outlined = render(ThemedButtonGroupView(palette: dracula, titles: empty3))
        XCTAssertEqual(outlined.w, dpx(190), "3 × 64 minus two 1 pt overlaps")
        XCTAssertEqual(outlined.h, dpx(36), "medium height fans to every member")
        let text = render(ThemedButtonGroupView(palette: dracula, titles: empty3, variant: .text))
        XCTAssertEqual(text.w, dpx(192), "a text group does not overlap — 3 × 64")
    }

    func testSizeLadderFansToEveryMember() {
        XCTAssertEqual(render(ThemedButtonGroupView(palette: dracula, titles: empty3,
                                                    size: .small)).h, dpx(30))
        XCTAssertEqual(render(ThemedButtonGroupView(palette: dracula, titles: empty3,
                                                    size: .large)).h, dpx(42))
    }

    func testVerticalStacksWithTheSameOverlapRule() {
        let outlined = render(ThemedButtonGroupView(palette: dracula, titles: empty3,
                                                    orientation: .vertical))
        XCTAssertEqual(outlined.h, dpx(106), "3 × 36 minus two 1 pt overlaps")
        XCTAssertEqual(outlined.w, dpx(64), "…and every member shares the widest member's width")
        let text = render(ThemedButtonGroupView(palette: dracula, titles: empty3,
                                                orientation: .vertical, variant: .text))
        XCTAssertEqual(text.h, dpx(108), "a text column does not overlap")
    }

    func testFullWidthDividesTheHostWidthEqually() {
        // 301 is chosen so cw = (301 + 2 × 1) / 3 = 101 lands on whole points.
        let r = renderOn(backdrop, ThemedButtonGroupView(palette: dracula, titles: empty3,
                                                        fullWidth: true).frame(width: 301))
        XCTAssertEqual(r.w, dpx(301), "fullWidth takes the host's width")
        for (i, x) in [dpx(100.5), dpx(200.5)].enumerated() {
            assertHue(r.at(x, r.h / 2), is: blend(dracula.restingStroke(of: dracula.primary),
                                                  on: backdrop),
                      "fullWidth seam \(i) still strokes once at the shared edge")
        }
    }

    // MARK: - the joined chrome

    /// The flagship: two abutting outlined members must produce ONE hairline,
    /// not two stacked at half alpha each.
    func testOutlinedSeamIsStrokedOnceNotTwice() {
        let r = renderOn(backdrop, ThemedButtonGroupView(palette: dracula, titles: empty3))
        let once = blend(dracula.restingStroke(of: dracula.primary), on: backdrop)
        let twice = blend(dracula.restingStroke(of: dracula.primary), on: once)
        for i in 0 ..< 2 {
            let px = r.at(seamX(i), r.h / 2)
            assertHue(px, is: once, "seam \(i) is the single resting stroke")
            assertHueDiffers(px, from: twice, "seam \(i) is NOT two strokes stacked")
        }
    }

    func testOuterCornersRoundAndInteriorSeamCornersStaySquare() {
        let pad: CGFloat = 4
        let r = renderOn(backdrop, ThemedButtonGroupView(palette: dracula,
                                                         titles: empty3).padding(pad))
        // The group's own top-left is rounded at Radius.sm = 4, so the corner
        // pixel is bare backdrop.
        assertHue(r.at(dpx(pad), dpx(pad)), is: backdrop,
                  "the group's outer corner is rounded away")
        // The interior seam's top corner is squared, so the border reaches it.
        assertHue(r.at(dpx(pad + 63.5), dpx(pad + 0.5)),
                  is: blend(dracula.restingStroke(of: dracula.primary), on: backdrop),
                  "an interior seam corner is square — the stroke runs right into it")
    }

    func testTextGroupPaintsARestingStrokeHairlineAtEachSeam() {
        let r = renderOn(backdrop, ThemedButtonGroupView(palette: dracula, titles: empty3,
                                                         variant: .text))
        assertHue(r.at(seamX(0, overlap: 0), r.h / 2),
                  is: blend(dracula.restingStroke(of: dracula.primary), on: backdrop),
                  "a text group's seam is its own hairline — its members have no border")
    }

    /// The contained seam is drawn OVER the opaque member fill. The AppKit group
    /// computes the same colour but its hairline is occluded by the member
    /// layers, so nothing is visible there (measured 2026-08-02 against the raw
    /// widget); the native view paints what the code intends.
    func testContainedSeamIsPaintedOverTheMemberFill() {
        let r = render(ThemedButtonGroupView(palette: dracula, titles: empty3,
                                             variant: .contained))
        let seam = blend(dracula.bestContrast(on: dracula.primary).withAlphaComponent(0.25),
                         on: dracula.primary)
        assertHue(r.at(seamX(0, overlap: 0), r.h / 2), is: seam,
                  "the contained seam is the contrast ink at 0.25 over the role fill")
        assertHue(r.at(memberCentre(0, overlap: 0), r.h / 2), is: dracula.primary,
                  "…and the member fill itself is untouched")
    }

    // MARK: - selection / hover / focus land on exactly one member

    func testSegmentedHoldsExactlyOneMemberInThePressedTier() {
        let r = renderOn(backdrop, ThemedButtonGroupView(palette: dracula, titles: empty3,
                                                         mode: .segmented,
                                                         previewSelectedIndex: 1))
        let active = blend(dracula.stateOverlay(.pressed, on: .roleTint(dracula.primary)),
                           on: backdrop)
        assertHue(r.at(memberCentre(1), r.h / 2), is: active, "the selected member holds the pressed tier")
        for i in [0, 2] {
            assertHue(r.at(memberCentre(i), r.h / 2), is: backdrop, "member \(i) stays bare")
        }
    }

    func testActionsModeNeverPaintsASelection() {
        let r = renderOn(backdrop, ThemedButtonGroupView(palette: dracula, titles: empty3,
                                                         selectedIndex: 1))
        for i in 0 ..< 3 {
            assertHue(r.at(memberCentre(i), r.h / 2), is: backdrop,
                      "MUI's ButtonGroup carries no selection — member \(i) stays bare")
        }
    }

    func testHoverPaintsOnlyTheHoveredMember() {
        let r = renderOn(backdrop, ThemedButtonGroupView(palette: dracula, titles: empty3,
                                                         previewHoveredIndex: 1))
        assertHue(r.at(memberCentre(1), r.h / 2),
                  is: blend(dracula.stateOverlay(.hover, on: .roleTint(dracula.primary)), on: backdrop),
                  "the hovered member washes")
        assertHue(r.at(memberCentre(0), r.h / 2), is: backdrop, "its neighbour does not")
    }

    func testFocusRingFollowsThatMembersOwnCornerMask() {
        let pad: CGFloat = 16
        let r = renderOn(backdrop, ThemedButtonGroupView(palette: dracula, titles: empty3,
                                                         previewFocusedIndex: 0).padding(pad))
        // The ring is the member box outset by 2 with a 2 pt stroke, so its
        // middle sits 2 pt outside the rim — at centre-x of member 0.
        assertHue(r.at(dpx(pad + 32), dpx(pad - 2)), is: dracula.primary,
                  "the focused member rings in the primary role")
        // Member 0's trailing corners are SQUARE, so the ring reaches the seam
        // corner instead of curving away from it.
        assertHue(r.at(dpx(pad + 64 + 2 - 0.5), dpx(pad - 1)), is: dracula.primary,
                  "…and the ring is square where the member's seam corner is")
    }

    // MARK: - disabled

    func testDisabledGroupGreysEveryMember() {
        let r = renderOn(backdrop, ThemedButtonGroupView(palette: dracula, titles: empty3,
                                                         enabled: false))
        for i in 0 ..< 3 {
            assertHue(r.at(seamX(max(0, i - 1)), dpx(0.5)),
                      is: blend(dracula.disabledStroke, on: backdrop),
                      "member \(i) drops the role for the neutral disabled stroke")
        }
    }

    /// The environment side of the family enabled rule: `enabled` is the
    /// argument ∧ `@Environment(\.isEnabled)`, so an ancestor `.disabled(true)`
    /// paints the SAME disabled pixels as `enabled: false` (stock-control parity).
    func testAncestorDisabledGreysEveryMember() {
        let group = { [self] (enabled: Bool) in
            ThemedButtonGroupView(palette: dracula, titles: empty3, enabled: enabled)
        }
        let r = renderOn(backdrop, group(true).disabled(true))
        assertHue(r.at(seamX(0), dpx(0.5)), is: blend(dracula.disabledStroke, on: backdrop),
                  "an ancestor .disabled(true) drops the role stroke")
        XCTAssertEqual(r.px, renderOn(backdrop, group(false)).px,
                       "…matching enabled: false byte-for-byte")
    }

    func testPerSegmentDisableAndsWithTheGroup() {
        let r = renderOn(backdrop, ThemedButtonGroupView(palette: dracula, titles: empty3,
                                                         disabledMember: 1))
        // Member 2's leading edge is the seam it shares with the DISABLED
        // member 1 — member 1 dropped its trailing edge, so this stroke is
        // member 2's and stays live.
        assertHue(r.at(seamX(1), r.h / 2),
                  is: blend(dracula.restingStroke(of: dracula.primary), on: backdrop),
                  "an enabled neighbour keeps its role stroke")
        // Member 1's own leading edge is the seam at index 0 — disabled.
        assertHue(r.at(seamX(0), r.h / 2), is: blend(dracula.disabledStroke, on: backdrop),
                  "the disabled member's own stroke greys")
    }

    func testDisableElevationDropsTheContainedGroupShadow() {
        let pad: CGFloat = 12
        let white = NSColor.white
        func shadowAlpha(_ disable: Bool) -> Double {
            let r = renderOn(white, ThemedButtonGroupView(palette: dracula, titles: empty3,
                                                          variant: .contained,
                                                          disableElevation: disable).padding(pad))
            // Just below the group's bottom rim, at centre-x.
            let px = r.at(r.w / 2, dpx(pad + 36 + 1.5))
            return 1 - px.r        // darker ⇒ more shadow, on white
        }
        XCTAssertGreaterThan(shadowAlpha(false), shadowAlpha(true) + 0.01,
                             "a contained group rests on one dp2; disableElevation drops it")
    }

    // MARK: - the three theming tiers, read off a contained member fill

    func testFallsBackToTheProcessDefault() {
        assertHue(render(ThemedButtonGroupView(titles: empty3, variant: .contained))
                    .at(memberCentre(0, overlap: 0), dpx(18)),
                  is: cobalt.primary, "no explicit argument and no ancestor theme ⇒ pal")
    }

    func testAmbientThemeBeatsTheProcessDefault() {
        assertHue(render(ThemedButtonGroupView(titles: empty3, variant: .contained)
                            .sillTheme(dracula))
                    .at(memberCentre(0, overlap: 0), dpx(18)),
                  is: dracula.primary, "ambient .sillTheme wins over pal")
    }

    func testExplicitArgumentBeatsTheAmbientTheme() {
        assertHue(render(ThemedButtonGroupView(palette: gruvbox, titles: empty3,
                                               variant: .contained).sillTheme(dracula))
                    .at(memberCentre(0, overlap: 0), dpx(18)),
                  is: gruvbox.primary, "explicit palette wins over ambient")
    }
}
