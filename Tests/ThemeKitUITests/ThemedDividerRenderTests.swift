// ThemedDividerView (SwiftUI-native) — REAL RENDER tests, not logic tests.
//
// The widget no longer produces an AppKit view to reach into, so the
// PaletteEnvironmentTests idiom (host, force layout, read the produced NSView)
// has no seam here. The equivalent evidence for a native view is the drawn
// side itself: rasterise through `ImageRenderer` and read pixels back —
// where the rule landed, that the variants inset it, and that the theming
// tiers pick the palette the pixels were actually painted with.
//
// The tier cases sample the LABEL GAP, not the rule: a derived `border` is
// neutral@0.10 (white on every dark theme — indistinguishable across themes),
// while the gap fills with the theme's opaque `background`, which does differ.
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
@testable import Palette
@testable import PaletteKit
@testable import ThemeKitUI

@MainActor
final class ThemedDividerRenderTests: XCTestCase {

    private let dracula = resolve(Theme.dracula.spec)
    private let gruvbox = resolve(Theme.gruvbox.spec)
    private let cobalt  = resolve(Theme.cobalt2.spec)

    override func setUp() {
        super.setUp()
        // Tier 3 — a known process default, so "fell through to pal" is
        // distinguishable from "picked up the wrong theme".
        setPalette(cobalt)
    }

    private let scale: CGFloat = 2

    /// Rasterise `view` inside a fixed frame. The divider fixes its own thin
    /// axis; the outer frame centres it, so the rule lands at the image centre.
    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> Raster {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height))
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

        /// Max alpha over a short vertical band around `y` — the rule is 1–2
        /// device pixels thin and its exact row depends on the display scale
        /// the renderer hands the view, so probe a band, not a single row.
        func maxAlpha(x: Int, yBand y: Int, half: Int = 2) -> Double {
            (max(0, y - half)...min(h - 1, y + half)).map { at(x, $0).a }.max() ?? 0
        }
    }

    private func sRGB(_ c: NSColor) -> (r: Double, g: Double, b: Double) {
        let s = c.usingColorSpace(.sRGB)!
        return (Double(s.redComponent), Double(s.greenComponent), Double(s.blueComponent))
    }

    private func assertColor(_ got: (r: Double, g: Double, b: Double, a: Double),
                             is expected: NSColor, _ message: String,
                             tolerance: Double = 0.03,
                             file: StaticString = #filePath, line: UInt = #line) {
        let e = sRGB(expected)
        XCTAssertEqual(got.r, e.r, accuracy: tolerance, "\(message) (r)", file: file, line: line)
        XCTAssertEqual(got.g, e.g, accuracy: tolerance, "\(message) (g)", file: file, line: line)
        XCTAssertEqual(got.b, e.b, accuracy: tolerance, "\(message) (b)", file: file, line: line)
    }

    /// Device-pixel x for a point coordinate.
    private func dpx(_ pt: CGFloat) -> Int { Int(pt * scale) }

    // MARK: - geometry: the rule is where the AppKit widget put it

    func testHorizontalRuleSitsAtTheVerticalCentre() {
        let r = render(ThemedDividerView(palette: dracula), width: 320, height: 40)
        let midY = r.h / 2, midX = r.w / 2
        XCTAssertGreaterThan(r.maxAlpha(x: midX, yBand: midY), 0.05,
                             "a fullWidth rule paints the centre band")
        XCTAssertGreaterThan(r.maxAlpha(x: 2, yBand: midY), 0.05, "…flush to the leading edge")
        XCTAssertGreaterThan(r.maxAlpha(x: r.w - 3, yBand: midY), 0.05, "…and the trailing edge")
        XCTAssertEqual(r.maxAlpha(x: midX, yBand: midY - 8), 0, "nothing above the rule")
        XCTAssertEqual(r.maxAlpha(x: midX, yBand: midY + 8), 0, "nothing below the rule")
    }

    func testInsetVariantStartsAtTheGutter() {
        let r = render(ThemedDividerView(palette: dracula, variant: .inset),
                       width: 320, height: 40)
        let midY = r.h / 2
        XCTAssertEqual(r.maxAlpha(x: dpx(10), yBand: midY), 0,
                       "inside the 72 pt gutter the rule is absent")
        XCTAssertGreaterThan(r.maxAlpha(x: dpx(200), yBand: midY), 0.05,
                             "past the gutter the rule is present")
        XCTAssertGreaterThan(r.maxAlpha(x: r.w - 3, yBand: midY), 0.05,
                             "inset is leading-only")
    }

    func testMiddleVariantInsetsBothEnds() {
        let r = render(ThemedDividerView(palette: dracula, variant: .middle),
                       width: 320, height: 40)
        let midY = r.h / 2
        XCTAssertEqual(r.maxAlpha(x: dpx(8), yBand: midY), 0, "16 pt leading margin")
        XCTAssertEqual(r.maxAlpha(x: r.w - 1 - dpx(8), yBand: midY), 0, "16 pt trailing margin")
        XCTAssertGreaterThan(r.maxAlpha(x: r.w / 2, yBand: midY), 0.05, "rule between the margins")
    }

    func testVerticalRuleFillsTheHeight() {
        let r = render(ThemedDividerView(palette: dracula, orientation: .vertical),
                       width: 40, height: 120)
        let midX = r.w / 2
        for y in [2, r.h / 2, r.h - 3] {
            let band = (max(0, midX - 2)...min(r.w - 1, midX + 2)).map { r.at($0, y).a }.max() ?? 0
            XCTAssertGreaterThan(band, 0.05, "vertical rule paints the centre column at y=\(y)")
        }
        XCTAssertEqual(r.at(midX - 8, r.h / 2).a, 0, "nothing left of the rule")
        XCTAssertEqual(r.at(midX + 8, r.h / 2).a, 0, "nothing right of the rule")
    }

    func testRulePaintsTheBorderRoleOverTheSurface() {
        // Composite the divider over the theme background and check the rule
        // pixel equals background blended with border@alpha — i.e. the rule is
        // painted with the canonical `border` role, not some invented colour.
        let bg = dracula.background!
        let r = render(ZStack { Color(nsColor: bg); ThemedDividerView(palette: dracula) },
                       width: 320, height: 40)
        let midY = r.h / 2, midX = r.w / 2
        // The rule row: the band pixel that differs most from the background.
        let b = sRGB(bg)
        let ruleY = (midY - 2...midY + 2).max { a, c in
            let pa = r.at(midX, a), pc = r.at(midX, c)
            return abs(pa.r - b.r) + abs(pa.g - b.g) + abs(pa.b - b.b)
                 < abs(pc.r - b.r) + abs(pc.g - b.g) + abs(pc.b - b.b)
        }!
        let border = dracula.border.usingColorSpace(.sRGB)!
        let a = Double(border.alphaComponent)
        let e = sRGB(dracula.border)
        let expected = NSColor(srgbRed: e.r * a + b.r * (1 - a),
                               green: e.g * a + b.g * (1 - a),
                               blue: e.b * a + b.b * (1 - a), alpha: 1)
        assertColor(r.at(midX, ruleY), is: expected, "rule = border role over the surface")
    }

    // MARK: - the label gap (and the theming tiers, read through it)

    /// Sample inside the gap but clear of the glyph: label "x" is ~6 pt wide,
    /// the gap runs to half-width + 11 pt (pad 10 + the +2 measure margin), so
    /// +8 pt from centre is surface fill in every catalog font.
    private func gapProbe(_ r: Raster) -> (r: Double, g: Double, b: Double, a: Double) {
        r.at(r.w / 2 + dpx(8), r.h / 2)
    }

    func testLabelCutsAGapFilledWithTheSurface() {
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let r = render(ThemedDividerView(palette: dracula, label: "x", surface: red),
                       width: 320, height: 40)
        assertColor(gapProbe(r), is: red, "explicit surface fills the gap")
        XCTAssertGreaterThan(r.maxAlpha(x: dpx(40), yBand: r.h / 2), 0.05,
                             "the rule still runs outside the gap")
    }

    func testGapDefaultsToTheThemeBackground() {
        let r = render(ThemedDividerView(palette: dracula, label: "x"), width: 320, height: 40)
        assertColor(gapProbe(r), is: dracula.background!, "no surface ⇒ palette.background")
    }

    // The three theming tiers — the PaletteEnvironmentTests contract, read off
    // the actually-painted gap because there is no AppKit view to ask.

    func testFallsBackToTheProcessDefault() {
        let r = render(ThemedDividerView(label: "x"), width: 320, height: 40)
        assertColor(gapProbe(r), is: cobalt.background!,
                    "no explicit argument and no ancestor theme ⇒ pal")
    }

    func testAmbientThemeBeatsTheProcessDefault() {
        let r = render(ThemedDividerView(label: "x").sillTheme(dracula), width: 320, height: 40)
        assertColor(gapProbe(r), is: dracula.background!, "ambient .sillTheme wins over pal")
    }

    func testExplicitArgumentBeatsTheAmbientTheme() {
        let r = render(ThemedDividerView(palette: gruvbox, label: "x").sillTheme(dracula),
                       width: 320, height: 40)
        assertColor(gapProbe(r), is: gruvbox.background!, "explicit palette wins over ambient")
    }
}
