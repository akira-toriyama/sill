// ThemedCheckboxView (SwiftUI-native) — REAL RENDER tests, not logic tests.
//
// The widget no longer produces an AppKit view to reach into (ThemedCheckbox's
// probe tests stay on the AppKit widget), so the evidence for the native view
// is the drawn side itself: rasterise through `ImageRenderer` and read pixels
// back — the box geometry, the role colours each state paints (`primary` fill,
// `bestContrast` glyph, `stateOverlay` circle, `disabledInk`), and the theming
// tiers. Every case renders a STILL state (the `preview…` overrides), so no
// clock runs and a frame is deterministic. Rendering over a TRANSPARENT
// backdrop lets alphas be asserted directly.
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
final class ThemedCheckboxRenderTests: XCTestCase {

    private let dracula = resolve(Theme.dracula.spec)
    private let gruvbox = resolve(Theme.gruvbox.spec)
    private let cobalt  = resolve(Theme.cobalt2.spec)

    override func setUp() {
        super.setUp()
        // Tier 3 — a known process default, so "fell through to pal" is
        // distinguishable from "picked up the wrong theme".
        setPalette(cobalt)
    }

    // MARK: - raster helpers (the ThemedDividerRenderTests idiom)

    private let scale: CGFloat = 2

    /// Rasterise at the view's IDEAL size — so the raster dimensions themselves
    /// assert the intrinsic geometry (a bare medium box must come out 42 × 42 pt).
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

    /// Composite over an opaque surface and hand-blend the expectation — the
    /// unpremultiplied hue of a LOW-alpha pixel (the ~0.08 hover circle) is
    /// dominated by 8-bit rounding over a transparent backdrop (one byte is
    /// ~12% of the channel), so state-circle hues are asserted this way.
    private func renderOn<V: View>(_ bg: NSColor, _ view: V) -> Raster {
        render(ZStack { Color(nsColor: bg); view })
    }
    private func blend(_ over: NSColor, on bg: NSColor) -> NSColor {
        let o = sRGB(over), b = sRGB(bg)
        return NSColor(srgbRed: o.r * o.a + b.r * (1 - o.a),
                       green: o.g * o.a + b.g * (1 - o.a),
                       blue: o.b * o.a + b.b * (1 - o.a), alpha: 1)
    }

    // MARK: - geometry probes (medium metrics: target 42, box 20 — box at
    // (11…31) pt inside the target square; device px = pt × 2)

    private func dpx(_ pt: CGFloat) -> Int { Int(pt * scale) }
    /// A point INSIDE the box, in box-fraction coordinates (0…1, y-down).
    private func boxProbe(_ r: Raster, _ fx: CGFloat, _ fy: CGFloat,
                          target: CGFloat = 42, box: CGFloat = 20)
        -> (r: Double, g: Double, b: Double, a: Double) {
        let origin = (target - box) / 2
        return r.at(dpx(origin + fx * box), dpx(origin + fy * box))
    }

    // MARK: - intrinsic geometry

    func testBareBoxIntrinsicSizeIsTheTargetSquare() {
        XCTAssertEqual(render(ThemedCheckboxView(palette: dracula)).w, dpx(42),
                       "medium bare box = the 42 pt hit target")
        XCTAssertEqual(render(ThemedCheckboxView(palette: dracula, size: .small)).w, dpx(38),
                       "small bare box = the 38 pt hit target (box glyph shrinks, target shrinks with it)")
    }

    func testLabelExtendsTheIntrinsicWidth() {
        let r = render(ThemedCheckboxView(palette: dracula, label: "Enable"))
        XCTAssertGreaterThan(r.w, dpx(42), "a label extends the width past the target square")
        XCTAssertEqual(r.h, dpx(42), "…the height stays the target")
    }

    // MARK: - glyph states

    func testUncheckedDrawsTheOutlineRingOnly() {
        let r = render(ThemedCheckboxView(palette: dracula, previewChecked: false))
        // The stroke ring: strokeBorder puts the 2 pt stroke fully inside the
        // box edge — probe half the stroke in from the box top, at centre x.
        assertHue(boxProbe(r, 0.5, 0.05), is: dracula.ink(.strong, of: .foreground),
                  "the outline paints foreground .strong ink")
        XCTAssertEqual(boxProbe(r, 0.5, 0.5).a, 0, accuracy: 0.02,
                       "an unchecked box has no fill")
    }

    func testCheckedFillsPrimaryAndDrawsTheCheck() {
        let r = render(ThemedCheckboxView(palette: dracula, previewChecked: true))
        assertHue(boxProbe(r, 0.85, 0.85), is: dracula.primary,
                  "a set box fills the primary role")
        assertHue(boxProbe(r, 0.42, 0.68), is: dracula.bestContrast(on: dracula.primary),
                  "the check elbow paints bestContrast-on-primary ink")
    }

    func testIndeterminateDrawsTheDash() {
        let r = render(ThemedCheckboxView(palette: dracula, previewIndeterminate: true))
        assertHue(boxProbe(r, 0.5, 0.5), is: dracula.bestContrast(on: dracula.primary),
                  "the dash crosses the box centre")
        assertHue(boxProbe(r, 0.5, 0.8), is: dracula.primary,
                  "below the dash is plain primary fill (no check legs)")
    }

    // MARK: - interaction states (forced via the preview overrides)

    func testHoverPaintsTheStateCircle() {
        let e = dracula.stateOverlay(.hover, on: .roleTint(dracula.foreground))
        // Alpha, over a transparent backdrop.
        let bare = render(ThemedCheckboxView(palette: dracula, previewHovered: true,
                                             previewChecked: false))
        XCTAssertEqual(bare.at(dpx(21), dpx(3)).a, sRGB(e).a, accuracy: 0.02,
                       "hover circle alpha")
        // Hue, composited over the theme surface (see renderOn). The circle
        // spans the whole 42 pt target; probe near its top, clear of the box.
        // Unchecked roots the overlay on `foreground`.
        let r = renderOn(dracula.background!,
                         ThemedCheckboxView(palette: dracula, previewHovered: true,
                                            previewChecked: false))
        assertHue(r.at(dpx(21), dpx(3)), is: blend(e, on: dracula.background!),
                  "hover circle hue over the surface")
    }

    func testPressedIsStrongerThanHoverAndRootsOnPrimaryWhenSet() {
        let hover = render(ThemedCheckboxView(palette: dracula, previewHovered: true,
                                              previewChecked: true))
        let pressed = render(ThemedCheckboxView(palette: dracula, previewPressed: true,
                                                previewChecked: true))
        let hoverA = hover.at(dpx(21), dpx(3)).a
        let pressedA = pressed.at(dpx(21), dpx(3)).a
        XCTAssertGreaterThan(pressedA, hoverA + 0.01,
                             "the pressed overlay is the stronger tier")
        let e = dracula.stateOverlay(.pressed, on: .roleTint(dracula.primary))
        let composited = renderOn(dracula.background!,
                                  ThemedCheckboxView(palette: dracula, previewPressed: true,
                                                     previewChecked: true))
        assertHue(composited.at(dpx(21), dpx(3)), is: blend(e, on: dracula.background!),
                  "a set box roots the circle on primary")
    }

    func testFocusRingIsThePrimaryOutsideTheBox() {
        let r = render(ThemedCheckboxView(palette: dracula, previewFocused: true,
                                          previewChecked: true))
        // Ring rect = box outset by 2, stroke 2 centred on it ⇒ the stroke
        // spans 8…10 pt above centre-x (box top = 11 pt). Probe its middle row.
        assertHue(r.at(dpx(21), dpx(9)), is: dracula.primary,
                  "the focus ring strokes the primary role")
        // …and focus also paints the hover-tier circle (fxFocused feeds it),
        // so a pixel outside the ring is the overlay, not empty.
        let outside = r.at(dpx(21), dpx(3))
        XCTAssertEqual(outside.a,
                       sRGB(dracula.stateOverlay(.hover, on: .roleTint(dracula.primary))).a,
                       accuracy: 0.02, "focus paints the hover-tier circle")
    }

    func testDisabledPaintsDisabledInkAndNoCircle() {
        let r = render(ThemedCheckboxView(palette: dracula, enabled: false,
                                          previewHovered: true, previewChecked: true))
        assertHue(boxProbe(r, 0.85, 0.85), is: dracula.disabledInk,
                  "a disabled set box fills disabledInk")
        XCTAssertEqual(r.at(dpx(21), dpx(3)).a, 0, accuracy: 0.02,
                       "disabled ignores previewHovered — no state circle")
    }

    // MARK: - the three theming tiers, read off the painted fill

    func testFallsBackToTheProcessDefault() {
        let r = render(ThemedCheckboxView(previewChecked: true))
        assertHue(boxProbe(r, 0.85, 0.85), is: cobalt.primary,
                  "no explicit argument and no ancestor theme ⇒ pal")
    }

    func testAmbientThemeBeatsTheProcessDefault() {
        let r = render(ThemedCheckboxView(previewChecked: true).sillTheme(dracula))
        assertHue(boxProbe(r, 0.85, 0.85), is: dracula.primary,
                  "ambient .sillTheme wins over pal")
    }

    func testExplicitArgumentBeatsTheAmbientTheme() {
        let r = render(ThemedCheckboxView(palette: gruvbox, previewChecked: true)
                        .sillTheme(dracula))
        assertHue(boxProbe(r, 0.85, 0.85), is: gruvbox.primary,
                  "explicit palette wins over ambient")
    }
}
