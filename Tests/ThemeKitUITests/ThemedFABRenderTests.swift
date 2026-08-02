// ThemedFABView (SwiftUI-native) — REAL RENDER tests, not logic tests.
//
// The widget no longer produces an AppKit view to reach into (ThemedFAB's
// probe tests stay on the AppKit widget), so the evidence for the native view
// is the drawn side itself: rasterise through `ImageRenderer` and read pixels
// back — the fixed circular geometry, the role colours each state paints
// (role fill, `onPrimary`/`onSecondary` glyph ink, the `contrastInk`
// stateOverlay wash, `disabledFill`/`disabledInk`), the dp8→dp12 elevation
// shadow, the primary focus ring, and the theming tiers. Every case renders a
// STILL state (the `preview…` overrides), so no clock runs and a frame is
// deterministic. The shadow and the focus ring draw OUTSIDE the control's
// bounds, so those cases render inside a padded frame to keep the overdraw
// in the raster.
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
final class ThemedFABRenderTests: XCTestCase {

    private let dracula = resolve(Theme.dracula.spec)
    private let gruvbox = resolve(Theme.gruvbox.spec)
    private let cobalt  = resolve(Theme.cobalt2.spec)

    override func setUp() {
        super.setUp()
        // Tier 3 — a known process default, so "fell through to pal" is
        // distinguishable from "picked up the wrong theme".
        setPalette(cobalt)
    }

    // MARK: - raster helpers (the ThemedCheckboxRenderTests idiom)

    private let scale: CGFloat = 2

    /// Rasterise at the view's IDEAL size — so the raster dimensions themselves
    /// assert the intrinsic geometry (a bare large circular FAB must come out
    /// 56 × 56 pt).
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

    private struct Raster {
        let px: [UInt8]; let w: Int; let h: Int

        /// Unpremultiplied sRGB at a DEVICE-pixel coordinate.
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

    /// Source-over `over` on the opaque `on` — the expectation for a wash
    /// probed on top of the opaque role fill (the fill is opaque, so a probe
    /// there never hits the low-alpha 8-bit quantisation trap; no composite
    /// backdrop needed).
    private func blend(_ over: NSColor, on bg: NSColor) -> NSColor {
        let o = sRGB(over), b = sRGB(bg)
        return NSColor(srgbRed: o.r * o.a + b.r * (1 - o.a),
                       green: o.g * o.a + b.g * (1 - o.a),
                       blue: o.b * o.a + b.b * (1 - o.a), alpha: 1)
    }

    private func dpx(_ pt: CGFloat) -> Int { Int(pt * scale) }

    /// A fill probe clear of the icon: centre-x, 6 pt from the top — inside a
    /// large (Ø 56) circle (22 pt from centre < r 28) but above the 28 pt icon
    /// block (which spans 14…42 pt).
    private func fillProbe(_ r: Raster) -> (r: Double, g: Double, b: Double, a: Double) {
        r.at(dpx(28), dpx(6))
    }

    func testCircularIsItsFixedSquare() {
        let large = render(ThemedFABView(palette: dracula))
        XCTAssertEqual(large.w, dpx(56), "large circular = Ø 56")
        XCTAssertEqual(large.h, dpx(56))
        XCTAssertEqual(render(ThemedFABView(palette: dracula, size: .small)).w, dpx(40),
                       "small circular = Ø 40")
    }

    func testExtendedIsAPillOfTheSizeHeight() {
        let r = render(ThemedFABView(palette: dracula, variant: .extended, label: "Create"))
        XCTAssertEqual(r.h, dpx(48), "large extended height = 48")
        XCTAssertGreaterThan(r.w, dpx(48), "icon + label extend the pill past its min width")
        let bare = render(ThemedFABView(palette: dracula, variant: .extended, label: ""))
        XCTAssertLessThan(bare.w, r.w, "the label extends the intrinsic width")
    }

    func testPrimaryRolePaintsPrimaryFillAndOnPrimaryGlyph() {
        let r = render(ThemedFABView(palette: dracula))
        assertHue(fillProbe(r), is: dracula.primary, "the circular fill is the primary role")
        assertHue(r.at(dpx(28), dpx(28)), is: dracula.onPrimary(),
                  "the plus glyph crosses the centre in onPrimary ink")
    }

    func testSecondaryRolePaintsSecondaryFillAndOnSecondaryGlyph() {
        let r = render(ThemedFABView(palette: dracula, role: .secondary))
        assertHue(fillProbe(r), is: dracula.secondary, "the secondary role fill")
        assertHue(r.at(dpx(28), dpx(28)), is: dracula.onSecondary(),
                  "…with the onSecondary contrast ink")
    }

    func testDisabledPaintsDisabledFillAndIgnoresHover() {
        let r = render(ThemedFABView(palette: dracula, enabled: false, previewHovered: true))
        assertHue(fillProbe(r), is: dracula.disabledFill,
                  "a disabled FAB fills disabledFill — the role accent must drop out")
        assertHue(r.at(dpx(28), dpx(28)), is: dracula.disabledInk,
                  "…and the glyph greys to disabledInk")
    }

    /// The environment side of the family enabled rule: `enabled` is the
    /// argument ∧ `@Environment(\.isEnabled)`, so an ancestor `.disabled(true)`
    /// paints the SAME disabled pixels as `enabled: false` (stock-control parity).
    func testAncestorDisabledPaintsTheDisabledState() {
        let fab = { [self] (enabled: Bool) in
            ThemedFABView(palette: dracula, enabled: enabled)
        }
        let r = render(fab(true).disabled(true))
        assertHue(fillProbe(r), is: dracula.disabledFill,
                  "an ancestor .disabled(true) drops the role fill")
        XCTAssertEqual(r.px, render(fab(false)).px,
                       "…matching enabled: false byte-for-byte")
    }

    // MARK: - interaction states (forced via the preview overrides)

    func testHoverWashesContrastInkOverTheRoleFill() {
        let e = dracula.stateOverlay(.hover, on: .contrastInk(on: dracula.primary))
        let r = render(ThemedFABView(palette: dracula, previewHovered: true))
        assertHue(fillProbe(r), is: blend(e, on: dracula.primary),
                  "the hover wash is contrastInk-on-primary at the hover alpha")
    }

    func testPressedIsTheStrongerWash() {
        let e = dracula.stateOverlay(.pressed, on: .contrastInk(on: dracula.primary))
        let r = render(ThemedFABView(palette: dracula, previewPressed: true))
        assertHue(fillProbe(r), is: blend(e, on: dracula.primary),
                  "the pressed wash is the stronger tier on the same base")
    }

    // MARK: - elevation (the shadow draws OUTSIDE bounds ⇒ padded renders)

    func testRestingElevationCastsAShadowAndDisabledIsFlat() {
        let pad: CGFloat = 20
        let rest = render(ThemedFABView(palette: dracula).padding(pad))
        // dp8: blur 8, dy +3 — just below the capsule bottom (y = pad + 56) the
        // shadow must read. Probe 4 pt below the rim, past the edge AA.
        XCTAssertGreaterThan(rest.at(dpx(pad + 28), dpx(pad + 60)).a, 0.05,
                             "a resting FAB floats on the dp8 shadow")
        let disabled = render(ThemedFABView(palette: dracula, enabled: false).padding(pad))
        XCTAssertEqual(disabled.at(dpx(pad + 28), dpx(pad + 60)).a, 0, accuracy: 0.02,
                       "a disabled FAB sits flat — no shadow")
    }

    func testPressDeepensTheElevation() {
        let pad: CGFloat = 20
        // dp12 reaches farther down than dp8 (blur 12 > 8, dy 7 > 3): probe
        // 12 pt below the rim, where the dp8 tail has effectively faded.
        let below = dpx(20 + 56 + 12)
        let rest = render(ThemedFABView(palette: dracula).padding(pad))
        let pressed = render(ThemedFABView(palette: dracula, previewPressed: true).padding(pad))
        XCTAssertGreaterThan(pressed.at(dpx(20 + 28), below).a,
                             rest.at(dpx(20 + 28), below).a + 0.02,
                             "pressing deepens dp8 → dp12")
    }

    // MARK: - focus (ring only, no wash — unlike the checkbox)

    func testFocusStrokesThePrimaryRingOutsideThePill() {
        let pad: CGFloat = 20
        let r = render(ThemedFABView(palette: dracula, previewFocused: true).padding(pad))
        // Ring path = the capsule inset by −2, stroke 2 centred on it ⇒ the
        // stroke spans 1…3 pt outside the rim; probe its middle at centre-x.
        assertHue(r.at(dpx(pad + 28), dpx(pad - 2)), is: dracula.primary,
                  "the focus ring strokes the primary role")
        assertHue(fillProbe(render(ThemedFABView(palette: dracula, previewFocused: true))),
                  is: dracula.primary,
                  "focus paints NO wash — the fill stays the bare role colour")
    }

    // MARK: - the three theming tiers, read off the painted fill

    func testFallsBackToTheProcessDefault() {
        assertHue(fillProbe(render(ThemedFABView())), is: cobalt.primary,
                  "no explicit argument and no ancestor theme ⇒ pal")
    }

    func testAmbientThemeBeatsTheProcessDefault() {
        assertHue(fillProbe(render(ThemedFABView().sillTheme(dracula))), is: dracula.primary,
                  "ambient .sillTheme wins over pal")
    }

    func testExplicitArgumentBeatsTheAmbientTheme() {
        assertHue(fillProbe(render(ThemedFABView(palette: gruvbox).sillTheme(dracula))),
                  is: gruvbox.primary,
                  "explicit palette wins over ambient")
    }
}
