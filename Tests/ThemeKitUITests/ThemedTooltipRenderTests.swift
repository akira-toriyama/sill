// ThemedTooltip's SwiftUI bubble content — REAL RENDER tests, plus the
// `.themedTooltip` modifier's anchor plumbing.
//
// The controller-side logic (placement flip, clamp, fade tokens, tracking-area
// lifecycle, AX help) stays covered by `ThemedTooltipTests` through the DEBUG
// probe; what THAT probe can no longer prove is the drawn side — since the
// 2026-08-02 migration the bubble is a SwiftUI `TooltipBubble` in an
// `NSHostingView` (floor-2 contents), so these cases rasterise the bubble
// through `ImageRenderer` and read pixels back: the inverted fill, the
// best-contrast ink, the arrow strip on the anchor-facing edge (and the y-flip
// of the cross axis on a horizontal side), and the rounded corner. The 0.92
// fill is asserted over an opaque backdrop (`renderOn`) — unpremultiplying a
// low-alpha wash off a transparent one is dominated by 8-bit rounding.
//
// The modifier case hosts a `.themedTooltip` view in an `NSHostingView` (the
// PaletteEnvironmentTests idiom) and reaches for the produced
// `PopupAnchorNSView`: it must exist, mirror the trigger's size, carry the
// hover tracking area + AX help, and stay hit-test transparent.
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
@testable import Palette
@testable import PaletteKit
@testable import ThemeKitUI

@MainActor
final class ThemedTooltipRenderTests: XCTestCase {

    /// A fixed opaque backdrop for the 0.92-alpha fill (see header).
    private let backdrop = NSColor(srgbRed: 0.15, green: 0.16, blue: 0.20, alpha: 1)

    private let dracula = resolve(Theme.dracula.spec)

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
        render(ZStack(alignment: .topLeading) { Color(nsColor: bg); view })
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

    /// Source-over `over` on the opaque `on`.
    private func blend(_ over: NSColor, on bg: NSColor) -> NSColor {
        let o = sRGB(over), b = sRGB(bg)
        return NSColor(srgbRed: o.r * o.a + b.r * (1 - o.a),
                       green: o.g * o.a + b.g * (1 - o.a),
                       blue: o.b * o.a + b.b * (1 - o.a), alpha: 1)
    }

    private func dpx(_ pt: CGFloat) -> Int { Int(pt * scale) }

    /// The pixel FURTHEST from `from` in a pt-space band — the ink probe over
    /// an opaque fill (the ThemedToolBarRenderTests idiom).
    private func mostDistinct(_ r: Raster, from: NSColor,
                              x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>)
        -> (r: Double, g: Double, b: Double, a: Double) {
        let f = sRGB(from)
        var best = (d: -1.0, c: (r: 0.0, g: 0.0, b: 0.0, a: 0.0))
        for py in max(0, dpx(y.lowerBound))..<min(r.h, dpx(y.upperBound)) {
            for px in max(0, dpx(x.lowerBound))..<min(r.w, dpx(x.upperBound)) {
                let c = r.at(px, py)
                let d = abs(c.r - f.r) + abs(c.g - f.g) + abs(c.b - f.b)
                if d > best.d { best = (d, c) }
            }
        }
        return best.c
    }

    // MARK: - the bubble model under test

    /// Metrics mirror the widget's: radius 4 (Radius.sm), pad 8×4, arrow 11/8.
    private func bubble(side: PopupSide, cross: CGFloat,
                        fillSize: CGSize = CGSize(width: 80, height: 22),
                        text: String = "Add item") -> TooltipBubble {
        TooltipBubble(text: text, font: dracula.uiFont(.tooltip),
                      fill: dracula.foreground.withAlphaComponent(0.92),
                      ink: dracula.bestContrast(on: dracula.foreground),
                      side: side, cross: cross, fillSize: fillSize,
                      cornerRadius: 4, hpad: 8, vpad: 4, arrowBase: 11, arrowLen: 8)
    }

    private var fillOnBackdrop: NSColor {
        blend(dracula.foreground.withAlphaComponent(0.92), on: backdrop)
    }

    // MARK: - fill + ink

    func testBubblePaintsTheInvertedSurfaceAndBestContrastInk() {
        // side .bottom: 8 pt arrow strip on top, fill spans y 8…30.
        let r = renderOn(backdrop, bubble(side: .bottom, cross: 40))
        assertHue(r.at(dpx(4), dpx(8 + 11)), is: fillOnBackdrop,
                  "the surface is foreground@0.92 over the host (inverted, theme-robust)")
        assertHue(mostDistinct(r, from: fillOnBackdrop, x: 8...72, y: 12...26),
                  is: dracula.bestContrast(on: dracula.foreground),
                  "the label inks best-contrast on the foreground")
    }

    func testCornerRadiusLeavesTheCornerClear() {
        let r = renderOn(backdrop, bubble(side: .bottom, cross: 40))
        // Fill's top-left corner sits at (0, 8); half a point inside the corner
        // box is rounded away, while the mid-left edge is filled.
        assertHue(r.at(dpx(0.5), dpx(8.5)), is: backdrop,
                  "the rounded corner shows the host through")
        assertHue(r.at(dpx(0.5), dpx(8 + 11)), is: fillOnBackdrop,
                  "…while the mid-edge is filled")
    }

    // MARK: - the arrow strip

    // Arrow probes sit 2 pt from the triangle's BASE (where it is ~7 pt wide),
    // not at the apex — the tip is a sub-pixel sliver whose AA hue is dominated
    // by the backdrop.

    func testArrowPointsUpAtTheCrossForABottomBubble() {
        // Panel 80×38; the arrow strip is y 0…8, apex at (cross, 0), base at y 9.
        let r = renderOn(backdrop, bubble(side: .bottom, cross: 20))
        assertHue(r.at(dpx(20), dpx(6)), is: fillOnBackdrop,
                  "the cross column is filled inside the top arrow strip")
        assertHue(r.at(dpx(60), dpx(6)), is: backdrop,
                  "…and the strip away from the cross stays clear")
    }

    func testArrowSitsOnTheBottomEdgeForATopBubble() {
        // side .top: fill y 0…22, arrow strip y 22…30, apex at (cross, 30).
        let r = renderOn(backdrop, bubble(side: .top, cross: 20))
        assertHue(r.at(dpx(20), dpx(24)), is: fillOnBackdrop,
                  "the cross column is filled inside the bottom arrow strip")
        assertHue(r.at(dpx(60), dpx(24)), is: backdrop,
                  "…and the strip away from the cross stays clear")
    }

    func testHorizontalSideFlipsTheCrossAxis() {
        // side .trailing: arrow strip x 0…8 on the left; `cross` is a Y-UP
        // panel-local y, so apex y (y-down) = panelH − cross = 22 − 15 = 7.
        let r = renderOn(backdrop, bubble(side: .trailing, cross: 15))
        assertHue(r.at(dpx(6), dpx(22 - 15)), is: fillOnBackdrop,
                  "the y-up cross is flipped into view space (apex row at panelH − cross)")
        assertHue(r.at(dpx(6), dpx(15)), is: backdrop,
                  "…and the UN-flipped y stays clear (the flip is real, not identity)")
    }

    // MARK: - the modifier's anchor plumbing

    private func firstSubview<T: NSView>(_ v: NSView, of type: T.Type) -> T? {
        if let x = v as? T { return x }
        for s in v.subviews { if let x = firstSubview(s, of: type) { return x } }
        return nil
    }

    func testThemedTooltipModifierLaysAnInvisibleAnchorUnderTheTrigger() {
        let h = NSHostingView(rootView:
            Color.clear.frame(width: 120, height: 40)
                .themedTooltip("Hint", palette: dracula))
        h.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        h.layoutSubtreeIfNeeded()
        _ = h.fittingSize
        h.layoutSubtreeIfNeeded()

        guard let anchor = firstSubview(h, of: PopupAnchorNSView.self) else {
            XCTFail("no PopupAnchorNSView under the trigger"); return
        }
        XCTAssertEqual(anchor.frame.width, 120, accuracy: 0.5,
                       "the anchor is coextensive with the trigger (width)")
        XCTAssertEqual(anchor.frame.height, 40, accuracy: 0.5,
                       "the anchor is coextensive with the trigger (height)")
        XCTAssertFalse(anchor.trackingAreas.isEmpty,
                       "the tooltip controller installed its hover tracking area")
        XCTAssertEqual(anchor.accessibilityHelp(), "Hint",
                       "AX help mirrors the text (VoiceOver path)")
        XCTAssertNil(anchor.hitTest(NSPoint(x: anchor.frame.midX, y: anchor.frame.midY)),
                     "the anchor never intercepts a click aimed at the trigger")
    }

    func testAnchorViewIsSwiftUINativeOtherwise() {
        // The showcase anchor view itself must produce NO AppKit widget — its
        // only AppKit descendant is the invisible popup anchor (plus whatever
        // the hosting scaffold adds, which carries no NSControl).
        let h = NSHostingView(rootView:
            ThemedTooltipAnchorView(palette: dracula, text: "Hi", placement: .auto))
        h.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        h.layoutSubtreeIfNeeded()
        XCTAssertNil(firstSubview(h, of: NSControl.self),
                     "the trigger button is ThemedButtonView (SwiftUI), not an AppKit control")
        XCTAssertNotNil(firstSubview(h, of: PopupAnchorNSView.self),
                        "…and the tooltip is attached through the anchor proxy")
    }
}
