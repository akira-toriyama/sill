// ThemedToolBarView (SwiftUI-native) — REAL RENDER tests, not logic tests.
//
// ThemedToolBar's `toolBarProbe` tests stay on the AppKit widget, which AppKit
// hosts and ThemedMenu's horizontal presentations still use, so the evidence
// for the native bar is the drawn side: rasterise through `ImageRenderer` and
// read pixels back. What matters is CHROME and ROW GEOMETRY — the per-density
// height, the flat bar's bottom hairline vs the elevated bar's shadow, the
// rounded-panel corner, the surface fills and the contrast re-ink they force on
// composed buttons, the gutters, the spacing that applies only between adjacent
// CONTENT items, an icon-only item collapsing to a SQUARE (below
// ThemedButtonView's 64 pt min-width floor), and `.flex` splitting the slack.
//
// The fixture leans on icon-only buttons, whose width is the control height and
// therefore font-independent. Regular density ⇒ minHeight 64, gutter 24,
// control 36, spacing 8.
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
final class ThemedToolBarRenderTests: XCTestCase {

    private let backdrop = NSColor(srgbRed: 0.15, green: 0.16, blue: 0.20, alpha: 1)

    private let dracula = resolve(Theme.dracula.spec)
    private let gruvbox = resolve(Theme.gruvbox.spec)
    private let cobalt  = resolve(Theme.cobalt2.spec)

    /// Two icon-only buttons — each a 36 pt square at regular density, so the
    /// row's geometry does not depend on font metrics. `"x"` is vendored;
    /// whether the glyph resolves does not change the item's width.
    private let twoIcons: [ThemedToolBarView.Item] = [
        .button(title: nil, symbol: "x"), .button(title: nil, symbol: "gear"),
    ]

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

    private func blend(_ over: NSColor, on bg: NSColor) -> NSColor {
        let o = sRGB(over), b = sRGB(bg)
        return NSColor(srgbRed: o.r * o.a + b.r * (1 - o.a),
                       green: o.g * o.a + b.g * (1 - o.a),
                       blue: o.b * o.a + b.b * (1 - o.a), alpha: 1)
    }

    private func dpx(_ pt: CGFloat) -> Int { Int(pt * scale) }

    /// The centre of icon item `i` in `twoIcons` at regular density: gutter 24,
    /// two 36 pt squares with 8 pt between them.
    private func iconCentre(_ i: Int) -> Int { dpx(24 + CGFloat(i) * (36 + 8) + 18) }

    /// A wash probe INSIDE icon item `i` but clear of its ~20 pt glyph: 3 pt in
    /// from the square's leading edge.
    private func iconWashProbe(_ i: Int) -> Int { dpx(24 + CGFloat(i) * (36 + 8) + 3) }

    /// The pixel in a pt-space band that is furthest from the bar's own surface
    /// — a hairline / glyph probe that does not depend on sub-pixel placement.
    private func mostDistinct(_ r: Raster, x: ClosedRange<CGFloat>,
                              y: ClosedRange<CGFloat>) -> (r: Double, g: Double, b: Double, a: Double) {
        let bar = sRGB(barSurface)
        var best = (d: -1.0, c: (r: 0.0, g: 0.0, b: 0.0, a: 0.0))
        for py in max(0, dpx(y.lowerBound)) ..< min(r.h, dpx(y.upperBound)) {
            for px in max(0, dpx(x.lowerBound)) ..< min(r.w, dpx(x.upperBound)) {
                let c = r.at(px, py)
                let d = abs(c.r - bar.r) + abs(c.g - bar.g) + abs(c.b - bar.b)
                if d > best.d { best = (d, c) }
            }
        }
        return best.c
    }

    /// The bar's OWN surface, composited over the test backdrop. Every item
    /// probe lands on this, not on the backdrop — a `.surface` bar fills with
    /// `palette.background` (honouring `backgroundAlpha`), so an expectation
    /// that skips it is wrong by exactly one layer.
    private var barSurface: NSColor {
        let base = dracula.background ?? .windowBackgroundColor
        let fill = dracula.backgroundAlpha.map { base.withAlphaComponent($0) } ?? base
        return blend(fill, on: backdrop)
    }

    // MARK: - density

    func testDensityLadderSetsTheBarHeight() {
        XCTAssertEqual(render(ThemedToolBarView(palette: dracula, items: twoIcons)).h,
                       dpx(64), "regular = MUI's 64")
        XCTAssertEqual(render(ThemedToolBarView(palette: dracula, items: twoIcons,
                                                variant: .dense)).h, dpx(48))
        XCTAssertEqual(render(ThemedToolBarView(palette: dracula, items: twoIcons,
                                                variant: .compact)).h, dpx(40))
    }

    /// gutter 24 + 36 + spacing 8 + 36 + gutter 24 = 128. The icon-only items
    /// are SQUARES at the control height — ThemedButtonView's 64 pt min-width
    /// floor must not apply, or the row would be 184.
    func testIconOnlyItemsCollapseToSquaresAndSetTheIntrinsicWidth() {
        let r = render(ThemedToolBarView(palette: dracula, items: twoIcons))
        XCTAssertEqual(r.w, dpx(128), "an icon button is MUI's <IconButton>, not a min-width <Button>")
    }

    func testGutterFollowsTheDensity() {
        // dense: gutter 16, control 30, spacing 8 ⇒ 16 + 30 + 8 + 30 + 16 = 100.
        XCTAssertEqual(render(ThemedToolBarView(palette: dracula, items: twoIcons,
                                                variant: .dense)).w, dpx(100))
        // compact: gutter 8 ⇒ 8 + 30 + 8 + 30 + 8 = 84.
        XCTAssertEqual(render(ThemedToolBarView(palette: dracula, items: twoIcons,
                                                variant: .compact)).w, dpx(84))
    }

    /// A space RESETS the content run, so no `itemSpacing` is added around it —
    /// the fixed gap is exactly what was asked for.
    func testAFixedSpaceReplacesTheItemSpacingRatherThanAddingToIt() {
        let items: [ThemedToolBarView.Item] = [
            .button(title: nil, symbol: "x"), .fixed(20), .button(title: nil, symbol: "gear"),
        ]
        XCTAssertEqual(render(ThemedToolBarView(palette: dracula, items: items)).w,
                       dpx(24 + 36 + 20 + 36 + 24), "24 + 36 + 20 + 36 + 24 = 140")
    }

    // MARK: - chrome

    func testFlatSquareBarDrawsABottomHairline() {
        let r = renderOn(backdrop, ThemedToolBarView(palette: dracula, items: twoIcons))
        assertHue(r.at(r.w / 2, r.h - 1), is: blend(dracula.border, on: barSurface),
                  "a flat square bar separates with a hairline, not a shadow")
        assertHue(r.at(r.w / 2, dpx(4)), is: barSurface, "…above which it is just the surface")
    }

    func testATransparentBarPaintsNeitherFillNorHairline() {
        let r = renderOn(backdrop, ThemedToolBarView(palette: dracula, items: twoIcons,
                                                     surface: .transparent))
        assertHue(r.at(r.w / 2, dpx(4)), is: backdrop, "a transparent surface paints no fill")
        assertHue(r.at(r.w / 2, r.h - 1), is: backdrop,
                  "…and gets no bottom rule either — there is no surface to separate")
    }

    func testRoundedPanelDropsTheHairline() {
        let r = renderOn(backdrop, ThemedToolBarView(palette: dracula, items: twoIcons,
                                                     surface: .transparent, corners: .rounded))
        assertHue(r.at(r.w / 2, r.h - 1), is: backdrop,
                  "a rounded panel is not a docked bar — no bottom rule")
    }

    func testSurfaceFillsPerRole() {
        for (surface, expected) in [(ThemedToolBar.Surface.primary, dracula.primary),
                                    (.secondary, dracula.secondary)] {
            let r = renderOn(backdrop, ThemedToolBarView(palette: dracula, items: twoIcons,
                                                         surface: surface))
            assertHue(r.at(dpx(4), r.h / 2), is: expected, "a \(surface) bar fills with its role")
        }
    }

    /// MUI `color="inherit"`: on a coloured bar a composed button inks with the
    /// BAR's contrast, not its own accent — which would vanish into the fill.
    func testAColouredBarReInksItsComposedButtons() {
        let r = render(ThemedToolBarView(palette: dracula,
                                         items: [.button(title: "Save", symbol: nil)],
                                         surface: .primary))
        // The label ink, probed on the busiest column of the text block: the
        // most-contrasting pixel against the fill.
        var best = (d: -1.0, hue: (r: 0.0, g: 0.0, b: 0.0, a: 0.0))
        let fill = sRGB(dracula.primary)
        for x in dpx(24) ..< dpx(90) {
            let c = r.at(x, r.h / 2)
            let d = abs(c.r - fill.r) + abs(c.g - fill.g) + abs(c.b - fill.b)
            if d > best.d { best = (d, c) }
        }
        assertHue(best.hue, is: dracula.onPrimary(),
                  "the composed button re-inks to the bar's contrast", tolerance: 0.06)
    }

    func testElevationReplacesTheHairlineWithAShadow() {
        let pad: CGFloat = 16
        let r = renderOn(.white, ThemedToolBarView(palette: dracula, items: twoIcons,
                                                   surface: .primary, elevation: 12)
                                    .padding(pad))
        // Below the bar's bottom rim the shadow darkens the white backdrop.
        let below = r.at(r.w / 2, dpx(pad + 64 + 2))
        XCTAssertLessThan(below.r, 0.99, "an elevated bar casts a shadow")

        let flat = renderOn(.white, ThemedToolBarView(palette: dracula, items: twoIcons,
                                                      surface: .primary, elevation: 0)
                                        .padding(pad))
        XCTAssertEqual(flat.at(flat.w / 2, dpx(pad + 64 + 2)).r, 1.0, accuracy: 0.01,
                       "a flat bar casts none")
    }

    // MARK: - items

    func testAFlexibleSpaceSplitsTheSlack() {
        let items: [ThemedToolBarView.Item] = [
            .button(title: nil, symbol: "x"), .flex, .button(title: nil, symbol: "gear"),
        ]
        let width: CGFloat = 300
        let r = renderOn(backdrop, ThemedToolBarView(palette: dracula, items: items,
                                                     previewHoveredItem: 2)
                                    .frame(width: width))
        XCTAssertEqual(r.w, dpx(width), "a flexible row takes the host's width")
        // The trailing item is pushed to the far end: its 36 pt square ends at
        // width − gutter, so its hover wash covers x ∈ [240, 276).
        let wash = blend(dracula.stateOverlay(.hover, on: .roleTint(dracula.primary)), on: barSurface)
        assertHue(r.at(dpx(width - 24 - 36 + 3), r.h / 2), is: wash,
                  "the flex spacer pushed the trailing item to the far gutter")
    }

    func testPreviewHoverLightsExactlyOneItem() {
        let r = renderOn(backdrop, ThemedToolBarView(palette: dracula, items: twoIcons,
                                                     previewHoveredItem: 1))
        let wash = blend(dracula.stateOverlay(.hover, on: .roleTint(dracula.primary)), on: barSurface)
        assertHue(r.at(iconWashProbe(1), r.h / 2), is: wash, "item 1 washes")
        assertHue(r.at(iconWashProbe(0), r.h / 2), is: barSurface, "item 0 stays bare")
    }

    func testADividerItemIsAHairlineAtHalfTheBarHeight() {
        let items: [ThemedToolBarView.Item] = [
            .button(title: nil, symbol: "x"), .divider, .button(title: nil, symbol: "gear"),
        ]
        let r = renderOn(backdrop, ThemedToolBarView(palette: dracula, items: items))
        // gutter 24 + 36 + spacing 8 ⇒ the 1 pt rule starts at x = 68.
        XCTAssertEqual(r.w, dpx(24 + 36 + 8 + 1 + 8 + 36 + 24), "a divider costs 1 pt plus its spacing")
        // The rule sits in the 1 pt slot at x ∈ [68, 69).
        let seam = mostDistinct(r, x: 67...71, y: 30...34)
        let bar = sRGB(barSurface)
        XCTAssertGreaterThan(abs(seam.r - bar.r) + abs(seam.g - bar.g) + abs(seam.b - bar.b), 0.02,
                             "the divider is drawn at the seam")
        // dividerHeight = max(16, 64 × 0.5) = 32, centred ⇒ bare surface 4 pt down.
        assertHue(mostDistinct(r, x: 67...71, y: 2...6), is: barSurface,
                  "…and it is half the bar's height, not the full height")
    }

    /// The bar has no own `enabled:` argument — its buttons are ThemedButtonViews,
    /// which read `\.isEnabled`, so an ancestor `.disabled(true)` greys every item
    /// exactly like per-item `enabled: false` (the family rule, transitively).
    func testAncestorDisabledGreysEveryItem() {
        let bar = { [self] (itemsEnabled: Bool) in
            ThemedToolBarView(palette: dracula, items: [
                .button(title: "On", symbol: nil, enabled: itemsEnabled),
                .button(title: "Off", symbol: nil, enabled: itemsEnabled),
            ])
        }
        XCTAssertEqual(renderOn(backdrop, bar(true).disabled(true)).px,
                       renderOn(backdrop, bar(false)).px,
                       "ancestor .disabled(true) == per-item enabled: false, byte-for-byte")
    }

    func testADisabledItemGreysWhileItsNeighbourDoesNot() {
        let items: [ThemedToolBarView.Item] = [
            .button(title: "On", symbol: nil),
            .button(title: "Off", symbol: nil, enabled: false),
        ]
        let r = renderOn(backdrop, ThemedToolBarView(palette: dracula, items: items))
        // Both are min-width 64 text buttons: [24,88) and [96,160). The label
        // sits on the bar's own surface, so the ink is the pixel FURTHEST from
        // that surface, not the most opaque one.
        let bar = sRGB(barSurface)
        func strongestInk(_ from: Int, _ to: Int) -> (r: Double, g: Double, b: Double, a: Double) {
            var best = (d: -1.0, c: (r: 0.0, g: 0.0, b: 0.0, a: 0.0))
            for x in dpx(CGFloat(from)) ..< dpx(CGFloat(to)) {
                for y in dpx(26) ..< dpx(38) {
                    let c = r.at(x, y)
                    let d = abs(c.r - bar.r) + abs(c.g - bar.g) + abs(c.b - bar.b)
                    if d > best.d { best = (d, c) }
                }
            }
            return best.c
        }
        assertHue(strongestInk(24, 88), is: dracula.primary, "the live item inks with its role")
        assertHue(strongestInk(96, 160), is: dracula.muted, "the disabled item greys to muted")
    }

    // MARK: - the three theming tiers, read off a primary surface fill

    func testFallsBackToTheProcessDefault() {
        assertHue(render(ThemedToolBarView(items: twoIcons, surface: .primary)).at(dpx(4), dpx(32)),
                  is: cobalt.primary, "no explicit argument and no ancestor theme ⇒ pal")
    }

    func testAmbientThemeBeatsTheProcessDefault() {
        assertHue(render(ThemedToolBarView(items: twoIcons, surface: .primary)
                            .sillTheme(dracula)).at(dpx(4), dpx(32)),
                  is: dracula.primary, "ambient .sillTheme wins over pal")
    }

    func testExplicitArgumentBeatsTheAmbientTheme() {
        assertHue(render(ThemedToolBarView(palette: gruvbox, items: twoIcons, surface: .primary)
                            .sillTheme(dracula)).at(dpx(4), dpx(32)),
                  is: gruvbox.primary, "explicit palette wins over ambient")
    }
}
