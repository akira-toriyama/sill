// ThemedButtonView (SwiftUI-native) — REAL RENDER tests, not logic tests.
//
// The widget no longer produces an AppKit view to reach into (ThemedButton's
// probe tests stay on the AppKit widget, which ThemedButtonGroup still
// composes), so the evidence for the native view is the drawn side itself:
// rasterise through `ImageRenderer` and read pixels back — the 30/36/42
// height ladder and 64 pt min width, the per-variant colours each state
// paints (contained role fill + bestContrast ink, outlined resting-vs-active
// stroke, text/outlined roleTint wash vs contained contrastInk wash), the
// contained dp2→dp8 elevation, the primary focus ring, and the theming
// tiers. Every case renders a STILL state (the `preview…` overrides), so no
// clock runs and a frame is deterministic. The shadow and the focus ring
// draw OUTSIDE the control's bounds, so those cases render inside a padded
// frame. Ink is probed on a solid `plus` leading icon, not the thin glyph
// strokes of the title.
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
final class ThemedButtonRenderTests: XCTestCase {

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
    /// probed on top of the opaque contained fill.
    private func blend(_ over: NSColor, on bg: NSColor) -> NSColor {
        let o = sRGB(over), b = sRGB(bg)
        return NSColor(srgbRed: o.r * o.a + b.r * (1 - o.a),
                       green: o.g * o.a + b.g * (1 - o.a),
                       blue: o.b * o.a + b.b * (1 - o.a), alpha: 1)
    }

    private func dpx(_ pt: CGFloat) -> Int { Int(pt * scale) }

    /// A fill probe clear of the title: 10 pt in from the left edge at
    /// mid-height — inside the fill (medium contained hpad = 16, so the title
    /// block starts past 16 pt) and past the 4 pt corner radius.
    private func fillProbe(_ r: Raster) -> (r: Double, g: Double, b: Double, a: Double) {
        r.at(dpx(10), r.h / 2)
    }
    /// The text variant's hpad is 8, so at mid-height x = 10 pt hits the title
    /// glyphs — its fill/wash probes sit 4 pt from the top instead (above the
    /// centred text block, still past the 4 pt corner radius).
    private func washProbe(_ r: Raster) -> (r: Double, g: Double, b: Double, a: Double) {
        r.at(dpx(10), dpx(4))
    }
    /// The solid centre of a `plus` leading icon (medium: hpad 16 + outerAdj −4
    /// puts the 20 pt icon at x 12…32; mid-height) — the ink probe that doesn't
    /// depend on thin text strokes.
    private func iconProbe(_ r: Raster) -> (r: Double, g: Double, b: Double, a: Double) {
        r.at(dpx(22), r.h / 2)
    }

    func testHeightLadderAndMinWidth() {
        XCTAssertEqual(render(ThemedButtonView(palette: dracula, size: .small, title: "B")).h,
                       dpx(30), "small height = 30")
        let medium = render(ThemedButtonView(palette: dracula, title: ""))
        XCTAssertEqual(medium.h, dpx(36), "medium height = 36")
        XCTAssertEqual(medium.w, dpx(64), "an empty button floors at MUI's 64 pt min width")
        XCTAssertEqual(render(ThemedButtonView(palette: dracula, size: .large, title: "B")).h,
                       dpx(42), "large height = 42")
    }

    func testFullWidthTakesTheProposal() {
        let r = render(ThemedButtonView(palette: dracula, variant: .contained,
                                        title: "Full", fullWidth: true)
                        .frame(width: 200))
        XCTAssertEqual(r.w, dpx(200), "fullWidth stretches to the host's width")
    }

    func testContainedPaintsRoleFillAndBestContrastInk() {
        let r = render(ThemedButtonView(palette: dracula, variant: .contained,
                                        title: "Button", leading: "plus"))
        assertHue(fillProbe(r), is: dracula.primary, "the contained fill is the role colour")
        assertHue(iconProbe(r), is: dracula.bestContrast(on: dracula.primary),
                  "the icon (and title) ink is bestContrast on the actual fill")
    }

    func testContainedErrorRoleFillsError() {
        let r = render(ThemedButtonView(palette: dracula, variant: .contained,
                                        role: .error, title: "Delete"))
        assertHue(fillProbe(r), is: dracula.error, "the error role fills error")
    }

    func testContainedHoverWashesContrastInkAndFocusDoesNot() {
        let hovered = render(ThemedButtonView(palette: dracula, variant: .contained,
                                              title: "Button", previewHovered: true))
        let e = dracula.stateOverlay(.hover, on: .contrastInk(on: dracula.primary))
        assertHue(fillProbe(hovered), is: blend(e, on: dracula.primary),
                  "contained hover washes contrastInk over the fill")
        let focused = render(ThemedButtonView(palette: dracula, variant: .contained,
                                              title: "Button", previewFocused: true))
        assertHue(fillProbe(focused), is: dracula.primary,
                  "contained focus is ring + elevation only — NO wash")
    }

    func testContainedDisabledGreysRegardlessOfRole() {
        let r = render(ThemedButtonView(palette: dracula, variant: .contained,
                                        role: .error, title: "Button",
                                        leading: "plus", enabled: false))
        assertHue(fillProbe(r), is: dracula.ink(.subtle, of: .muted),
                  "the disabled fill is the neutral muted wash — the role drops out")
        assertHue(iconProbe(r), is: dracula.muted, "…and the ink greys to muted")
    }

    /// The environment side of the family enabled rule: `enabled` is the
    /// argument ∧ `@Environment(\.isEnabled)`, so an ancestor `.disabled(true)`
    /// paints the SAME disabled pixels as `enabled: false` (stock-control parity).
    func testAncestorDisabledPaintsTheDisabledState() {
        let button = { [self] (enabled: Bool) in
            ThemedButtonView(palette: dracula, variant: .contained, role: .error,
                             title: "Button", leading: "plus", enabled: enabled)
        }
        let r = render(button(true).disabled(true))
        assertHue(fillProbe(r), is: dracula.ink(.subtle, of: .muted),
                  "an ancestor .disabled(true) greys the fill — not just hit testing")
        XCTAssertEqual(r.px, render(button(false)).px,
                       "…matching enabled: false byte-for-byte")
    }

    func testOutlinedStrokeRestsAtHalfRoleAndSharpensOnHover() {
        let rest = render(ThemedButtonView(palette: dracula, variant: .outlined, title: "Button"))
        // strokeBorder puts the 1 pt stroke fully inside the edge: probe half
        // a point in, at centre-x (clear of the 4 pt corners).
        let edge = rest.at(rest.w / 2, dpx(0.5))
        assertHue(edge, is: dracula.primary, "the resting stroke hue is the role")
        XCTAssertEqual(edge.a, sRGB(dracula.restingStroke(of: dracula.primary)).a,
                       accuracy: 0.04, "…at MUI's resting 0.5 alpha")
        let hovered = render(ThemedButtonView(palette: dracula, variant: .outlined,
                                              title: "Button", previewHovered: true))
        assertHue(hovered.at(hovered.w / 2, dpx(0.5)), is: dracula.primary,
                  "interaction sharpens the stroke to the full role colour")
        XCTAssertGreaterThan(hovered.at(hovered.w / 2, dpx(0.5)).a, 0.9,
                             "…at full alpha")
    }

    func testOutlinedAndTextGetTheRoleTintWashOnFocusToo() {
        // Unlike contained, focus paints the hover-tier wash for these variants.
        let e = dracula.stateOverlay(.hover, on: .roleTint(dracula.primary))
        for variant in [ThemedButton.Variant.outlined, .text] {
            let r = render(ThemedButtonView(palette: dracula, variant: variant,
                                            title: "Button", previewFocused: true))
            XCTAssertEqual(washProbe(r).a, sRGB(e).a, accuracy: 0.02,
                           "\(variant) focus paints the roleTint hover-tier wash")
        }
    }

    func testTextVariantHasNoFillAtRest() {
        let r = render(ThemedButtonView(palette: dracula, variant: .text, title: "Button"))
        XCTAssertEqual(washProbe(r).a, 0, accuracy: 0.02, "a resting text button is bare ink")
    }

    func testTextInkIsTheRoleColour() {
        let r = render(ThemedButtonView(palette: dracula, variant: .text,
                                        title: "Button", leading: "plus"))
        // Text-variant medium: hpad 8 + outerAdj −4 puts the 20 pt icon at 4…24.
        assertHue(r.at(dpx(14), r.h / 2), is: dracula.primary,
                  "text/outlined ink is the bare role colour")
    }

    // MARK: - elevation (contained only; draws OUTSIDE bounds ⇒ padded renders)

    func testContainedRestsOnDp2AndTextIsFlat() {
        let pad: CGFloat = 16
        let contained = render(ThemedButtonView(palette: dracula, variant: .contained,
                                                title: "Button").padding(pad))
        // dp2: blur 3, dy +1 — probe 2 pt below the bottom rim, centre-x.
        XCTAssertGreaterThan(contained.at(contained.w / 2, contained.h - dpx(14)).a, 0.03,
                             "a contained button rests on the dp2 shadow")
        let text = render(ThemedButtonView(palette: dracula, variant: .text,
                                           title: "Button").padding(pad))
        XCTAssertEqual(text.at(text.w / 2, text.h - dpx(14)).a, 0, accuracy: 0.02,
                       "a text button casts no shadow")
    }

    func testPressDeepensTheElevation() {
        let pad: CGFloat = 16
        // dp8 reaches farther down than dp2: probe 8 pt below the rim, where
        // the dp2 tail (blur 3, dy 1) has effectively faded.
        let rest = render(ThemedButtonView(palette: dracula, variant: .contained,
                                           title: "Button").padding(pad))
        let pressed = render(ThemedButtonView(palette: dracula, variant: .contained,
                                              title: "Button", previewPressed: true).padding(pad))
        let y = rest.h - dpx(8)
        XCTAssertGreaterThan(pressed.at(pressed.w / 2, y).a, rest.at(rest.w / 2, y).a + 0.02,
                             "pressing deepens dp2 → dp8")
    }

    func testFocusStrokesThePrimaryRingOutsideTheBox() {
        let pad: CGFloat = 16
        let r = render(ThemedButtonView(palette: dracula, variant: .contained,
                                        title: "Button", previewFocused: true).padding(pad))
        // Ring rect = the box outset by 2, stroke 2 centred on it ⇒ the stroke
        // spans 1…3 pt outside the rim; probe its middle at centre-x.
        assertHue(r.at(r.w / 2, dpx(pad - 2)), is: dracula.primary,
                  "the focus ring strokes the primary role")
    }

    // MARK: - the three theming tiers, read off the contained fill

    func testFallsBackToTheProcessDefault() {
        assertHue(fillProbe(render(ThemedButtonView(variant: .contained, title: "B"))),
                  is: cobalt.primary, "no explicit argument and no ancestor theme ⇒ pal")
    }

    func testAmbientThemeBeatsTheProcessDefault() {
        assertHue(fillProbe(render(ThemedButtonView(variant: .contained, title: "B")
                                    .sillTheme(dracula))),
                  is: dracula.primary, "ambient .sillTheme wins over pal")
    }

    func testExplicitArgumentBeatsTheAmbientTheme() {
        assertHue(fillProbe(render(ThemedButtonView(palette: gruvbox, variant: .contained,
                                                    title: "B").sillTheme(dracula))),
                  is: gruvbox.primary, "explicit palette wins over ambient")
    }
}
