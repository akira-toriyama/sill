// ThemedSkeletonView (SwiftUI-native) — REAL RENDER tests, not logic tests.
//
// The widget no longer produces an AppKit view to reach into (the
// ThemedSkeletonTests probe stays on the AppKit widget), so the evidence for
// the native view is the drawn side itself: rasterise through `ImageRenderer`
// and read pixels back — the wash is the `muted` `.subtle` ink, the variants
// clip their shapes, the frozen poses land on the AppKit widget's numbers, and
// the theming tiers pick the palette the pixels were painted with.
//
// Every case renders a STILL pose (`.none` / `previewFrozen`), so no clock
// runs and a frame is deterministic. The wash is translucent on purpose;
// rendering over a TRANSPARENT backdrop lets the alpha channel be asserted
// directly (unpremultiplied by the raster helper).
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
@testable import Palette
@testable import PaletteKit
@testable import ThemeKitUI

@MainActor
final class ThemedSkeletonRenderTests: XCTestCase {

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
    }

    private func sRGB(_ c: NSColor) -> (r: Double, g: Double, b: Double, a: Double) {
        let s = c.usingColorSpace(.sRGB)!
        return (Double(s.redComponent), Double(s.greenComponent),
                Double(s.blueComponent), Double(s.alphaComponent))
    }

    /// The wash a palette paints — `muted` at the `.subtle` ink tier.
    private func tint(_ p: ResolvedPalette) -> (r: Double, g: Double, b: Double, a: Double) {
        sRGB(p.ink(.subtle, of: .muted))
    }

    private func assertHue(_ got: (r: Double, g: Double, b: Double, a: Double),
                           is expected: (r: Double, g: Double, b: Double, a: Double),
                           _ message: String, tolerance: Double = 0.03,
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.r, expected.r, accuracy: tolerance, "\(message) (r)", file: file, line: line)
        XCTAssertEqual(got.g, expected.g, accuracy: tolerance, "\(message) (g)", file: file, line: line)
        XCTAssertEqual(got.b, expected.b, accuracy: tolerance, "\(message) (b)", file: file, line: line)
    }

    // MARK: - the wash is the canonical role, at the canonical tier

    func testWashPaintsTheMutedSubtleInk() {
        let r = render(ThemedSkeletonView(palette: dracula, variant: .rectangular,
                                          animation: .none), width: 120, height: 40)
        let e = tint(dracula)
        let got = r.at(r.w / 2, r.h / 2)
        assertHue(got, is: e, "wash hue = muted role")
        XCTAssertEqual(got.a, e.a, accuracy: 0.02, "wash alpha = the .subtle ink tier")
    }

    // MARK: - variant shapes

    func testRectangularFillsItsCorners() {
        let r = render(ThemedSkeletonView(palette: dracula, variant: .rectangular,
                                          animation: .none), width: 120, height: 40)
        XCTAssertGreaterThan(r.at(1, 1).a, 0.05, "a sharp block paints its corner")
    }

    func testRoundedClipsItsCorners() {
        let r = render(ThemedSkeletonView(palette: dracula, variant: .rounded,
                                          animation: .none), width: 120, height: 40)
        XCTAssertEqual(r.at(1, 1).a, 0, accuracy: 0.02, "a rounded block clips its corner")
        XCTAssertGreaterThan(r.at(r.w / 2, r.h / 2).a, 0.05, "…but paints its middle")
    }

    func testCircularClipsToACircle() {
        let r = render(ThemedSkeletonView(palette: dracula, variant: .circular,
                                          animation: .none), width: 40, height: 40)
        XCTAssertEqual(r.at(2, 2).a, 0, accuracy: 0.02, "outside the circle is empty")
        XCTAssertEqual(r.at(r.w - 3, r.h - 3).a, 0, accuracy: 0.02, "…all four corners")
        XCTAssertGreaterThan(r.at(r.w / 2, r.h / 2).a, 0.05, "the disc is painted")
    }

    // MARK: - frozen poses (the AppKit widget's numbers)

    func testFrozenPulseRestsOnTheMidDim() {
        let still = render(ThemedSkeletonView(palette: dracula, variant: .rectangular,
                                              animation: .none), width: 120, height: 40)
        let frozen = render(ThemedSkeletonView(palette: dracula, variant: .rectangular,
                                               previewFrozen: true), width: 120, height: 40)
        let full = still.at(still.w / 2, still.h / 2).a
        let dim = frozen.at(frozen.w / 2, frozen.h / 2).a
        // frozenPulseOpacity = 1 − (1 − 0.4) × 0.5 = 0.7 of the wash alpha.
        XCTAssertEqual(dim, full * 0.7, accuracy: 0.02,
                       "previewFrozen holds the pulse at the 0.7 mid-dim")
    }

    func testFrozenWaveCentresTheHighlight() {
        let r = render(ThemedSkeletonView(palette: dracula, variant: .rectangular,
                                          animation: .wave, previewFrozen: true),
                       width: 200, height: 24)
        let centre = r.at(r.w / 2, r.h / 2).a
        let edge = r.at(6, r.h / 2).a
        XCTAssertGreaterThan(centre, edge + 0.03,
                             "the frozen wave parks its highlight band mid-cell")
        XCTAssertEqual(edge, tint(dracula).a, accuracy: 0.03,
                       "clear of the band the wash is the plain tint")
    }

    // MARK: - the three theming tiers, read off the painted wash

    func testFallsBackToTheProcessDefault() {
        let r = render(ThemedSkeletonView(variant: .rectangular, animation: .none),
                       width: 120, height: 40)
        assertHue(r.at(r.w / 2, r.h / 2), is: tint(cobalt),
                  "no explicit argument and no ancestor theme ⇒ pal")
    }

    func testAmbientThemeBeatsTheProcessDefault() {
        let r = render(ThemedSkeletonView(variant: .rectangular, animation: .none)
                        .sillTheme(dracula), width: 120, height: 40)
        assertHue(r.at(r.w / 2, r.h / 2), is: tint(dracula),
                  "ambient .sillTheme wins over pal")
    }

    func testExplicitArgumentBeatsTheAmbientTheme() {
        let r = render(ThemedSkeletonView(palette: gruvbox, variant: .rectangular,
                                          animation: .none).sillTheme(dracula),
                       width: 120, height: 40)
        assertHue(r.at(r.w / 2, r.h / 2), is: tint(gruvbox),
                  "explicit palette wins over ambient")
    }
}
