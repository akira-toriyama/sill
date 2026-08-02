// ThemedChipView (SwiftUI-native) — REAL RENDER tests, not logic tests.
//
// The widget no longer produces an AppKit view to reach into (ThemedChip's
// `chipProbe` tests stay on the AppKit widget, which AppKit hosts still use),
// so the evidence for the native view is the drawn side itself: rasterise
// through `ImageRenderer` and read pixels back — the 24/32 size ladder and the
// keycap square, the per-variant resting fills (neutral muted wash / opaque
// role / clear outlined / faint key face), the ink each fill demands
// (bestContrast on an opaque role, the bare role tint otherwise), the outlined
// resting-vs-active stroke, the two OPT-IN affordances (a wash only when
// clickable, a focus ring whenever EITHER affordance is live), and the theming
// tiers. Every case renders a STILL state (the `preview…` overrides), so no
// clock runs and a frame is deterministic. The focus ring draws OUTSIDE the
// chip's bounds, so those cases render inside a padded frame. Low-alpha fills
// are asserted over an opaque backdrop (`renderOn`) — unpremultiplying a 0.16
// wash off a transparent one is dominated by 8-bit rounding.
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
final class ThemedChipRenderTests: XCTestCase {

    /// A fixed opaque backdrop for the low-alpha washes. `ResolvedPalette`'s own
    /// `background` is OPTIONAL (a theme may leave it to the host), so a literal
    /// keeps every composited expectation unambiguous.
    private let backdrop = NSColor(srgbRed: 0.15, green: 0.16, blue: 0.20, alpha: 1)

    private let dracula = resolve(Theme.dracula.spec)
    private let gruvbox = resolve(Theme.gruvbox.spec)
    private let cobalt  = resolve(Theme.cobalt2.spec)

    override func setUp() {
        super.setUp()
        // Tier 3 — a known process default, so "fell through to pal" is
        // distinguishable from "picked up the wrong theme".
        setPalette(cobalt)
    }

    // MARK: - raster helpers (the ThemedButtonRenderTests idiom)

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

    /// Render over an OPAQUE backdrop, so a low-alpha wash is asserted as the
    /// composited result instead of being unpremultiplied out of the noise.
    private func renderOn<V: View>(_ bg: NSColor, _ view: V) -> Raster {
        render(ZStack { Color(nsColor: bg); view })
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

    /// The most opaque pixel in a pt-space band — a glyph probe that does not
    /// depend on where exactly a Phosphor path puts its ink. Only meaningful
    /// where the band's background is CLEAR (an outlined / text-ish chip).
    private func strongest(_ r: Raster, x: ClosedRange<CGFloat>,
                           y: ClosedRange<CGFloat>) -> (r: Double, g: Double, b: Double, a: Double) {
        var best = (r: 0.0, g: 0.0, b: 0.0, a: -1.0)
        for py in max(0, dpx(y.lowerBound))..<min(r.h, dpx(y.upperBound)) {
            for px in max(0, dpx(x.lowerBound))..<min(r.w, dpx(x.upperBound)) {
                let c = r.at(px, py)
                if c.a > best.a { best = c }
            }
        }
        return best
    }

    // MARK: - geometry probes (medium metrics: height 32, hpad 12, pill radius
    // 16, gap 5, iconPt 16, outer icon margin −2)

    /// The fill, clear of the label: 4 pt in from the leading edge at
    /// mid-height, where the pill is at its widest and the title (which starts
    /// at hpad = 12) has not begun.
    private func fillProbe(_ r: Raster) -> (r: Double, g: Double, b: Double, a: Double) {
        r.at(dpx(4), r.h / 2)
    }
    /// The solid centre of a `plus` leading icon — leading pad 12 + outerAdj −2
    /// puts the 16 pt glyph at x 10…26, so its centre is x = 18, mid-height.
    private func iconProbe(_ r: Raster) -> (r: Double, g: Double, b: Double, a: Double) {
        r.at(dpx(18), r.h / 2)
    }
    /// The trailing × band — trailing pad 12 + outerAdj −2 puts the 16 pt glyph
    /// in the last 26…10 pt, inset vertically to clear the border strokes.
    private func deleteInk(_ r: Raster) -> (r: Double, g: Double, b: Double, a: Double) {
        let w = CGFloat(r.w) / scale
        return strongest(r, x: (w - 26)...(w - 10), y: 8...24)
    }

    // MARK: - metrics

    func testSizeLadderAndKeycapSquare() {
        XCTAssertEqual(render(ThemedChipView(palette: dracula, size: .small, title: "S")).h,
                       dpx(24), "small height = 24 (MUI Chip has no large)")
        XCTAssertEqual(render(ThemedChipView(palette: dracula, title: "M")).h,
                       dpx(32), "medium height = 32")
        let key = render(ThemedChipView(palette: dracula, variant: .keycap, title: ""))
        XCTAssertEqual(key.h, dpx(32), "the keycap keeps the size ladder height")
        XCTAssertEqual(key.w, dpx(32), "…and a 1-glyph key floors at a square (minWidth = height)")
    }

    func testTheDeleteAffordanceWidensTheChipByTheGlyphAndGap() {
        let plain = render(ThemedChipView(palette: dracula, title: "Tag"))
        let withX = render(ThemedChipView(palette: dracula, title: "Tag", deletable: true))
        // iconPt 16 + gap 5 + the −2 outer margin the × side now claims.
        XCTAssertEqual(withX.w - plain.w, dpx(16 + 5 - 2),
                       "the × adds its glyph, the row gap, and the negative outer margin")
    }

    // MARK: - resting fills, per variant

    func testFilledNeutralRestsOnTheMutedWash() {
        let r = renderOn(backdrop, ThemedChipView(palette: dracula, title: "Tag"))
        assertHue(fillProbe(r), is: blend(dracula.ink(.wash, of: .muted), on: backdrop),
                  "a neutral filled chip is the calm muted wash, not an opaque fill")
    }

    func testFilledRoleIsAnOpaqueRoleFillWithContrastInk() {
        let r = render(ThemedChipView(palette: dracula, role: .primary,
                                      title: "Tag", leading: "plus"))
        assertHue(fillProbe(r), is: dracula.primary, "a role filled chip is the opaque role")
        assertHue(iconProbe(r), is: dracula.onPrimary(),
                  "…so the ink is the contrast ink on primary")
    }

    func testFilledErrorInkIsBestContrastOnError() {
        let r = render(ThemedChipView(palette: dracula, role: .error,
                                      title: "Tag", leading: "plus"))
        assertHue(fillProbe(r), is: dracula.error, "the error role fills error")
        assertHue(iconProbe(r), is: dracula.bestContrast(on: dracula.error),
                  "…and the ink is bestContrast on the actual fill")
    }

    func testOutlinedRestsClearAndInksTheRoleTint() {
        let r = render(ThemedChipView(palette: dracula, variant: .outlined,
                                      role: .primary, title: "Tag", leading: "plus"))
        XCTAssertEqual(fillProbe(r).a, 0, accuracy: 0.02, "an unselected outlined chip has no fill")
        assertHue(iconProbe(r), is: dracula.primary,
                  "on a clear surface the ink is the bare role tint")
    }

    func testKeycapDrawsTheFaintKeyFaceAndTheBorderStroke() {
        let r = renderOn(backdrop,
                         ThemedChipView(palette: dracula, variant: .keycap, title: "⌘K"))
        // The keycap corner is Radius.sm (5), not the pill — probe past it.
        assertHue(r.at(dpx(6), r.h / 2), is: blend(dracula.ink(.faint, of: .foreground),
                                                  on: backdrop),
                  "the key face is the faint foreground wash")
        // The stroke composites ON the key face, not straight onto the backdrop.
        assertHue(r.at(r.w / 2, dpx(0.5)),
                  is: blend(dracula.border, on: blend(dracula.ink(.faint, of: .foreground),
                                                      on: backdrop)),
                  "…inside the neutral border stroke")
    }

    func testSelectedNeutralPaintsTheCanonicalSelection() {
        let r = renderOn(backdrop,
                         ThemedChipView(palette: dracula, variant: .outlined,
                                        title: "Tag", selected: true))
        assertHue(fillProbe(r), is: blend(dracula.selection, on: backdrop),
                  "a selected neutral chip fills with the canonical selection role")
    }

    func testSelectedRoleWashesTheRoleAtTheWashTier() {
        let r = renderOn(backdrop,
                         ThemedChipView(palette: dracula, variant: .outlined, role: .primary,
                                        title: "Tag", selected: true))
        let expected = dracula.primary.withAlphaComponent(ResolvedPalette.InkTier.wash.alpha)
        assertHue(fillProbe(r), is: blend(expected, on: backdrop),
                  "a selected role chip washes the role at the .wash tier")
    }

    /// Also the regression guard for the bug the migration fixed: the
    /// NSViewRepresentable bridge's `c.isEnabled = enabled` was overwritten by
    /// SwiftUI (which drives a hosted NSControl's `isEnabled` from
    /// `@Environment(\.isEnabled)` after `updateNSView`), so `enabled: false`
    /// used to render fully ENABLED — the role fill and the foreground ink.
    func testDisabledGreysTheFillAndInkRegardlessOfRole() {
        let r = renderOn(backdrop,
                         ThemedChipView(palette: dracula, role: .error, title: "Tag",
                                        leading: "plus", enabled: false))
        assertHue(fillProbe(r), is: blend(dracula.ink(.subtle, of: .muted), on: backdrop),
                  "the disabled fill is the neutral muted wash — the role drops out")
        assertHue(iconProbe(r), is: blend(dracula.muted, on: blend(dracula.ink(.subtle, of: .muted),
                                                                  on: backdrop)),
                  "…and the ink greys to muted")
    }

    // MARK: - the outlined stroke

    func testOutlinedRoleStrokeRestsAtHalfRoleAndSharpensOnInteraction() {
        // strokeBorder puts the 1 pt stroke fully inside the edge: probe half a
        // point in, at centre-x (clear of the pill caps).
        let rest = render(ThemedChipView(palette: dracula, variant: .outlined,
                                         role: .primary, title: "Tag", clickable: true))
        let edge = rest.at(rest.w / 2, dpx(0.5))
        assertHue(edge, is: dracula.primary, "the resting stroke hue is the role")
        XCTAssertEqual(edge.a, sRGB(dracula.restingStroke(of: dracula.primary)).a,
                       accuracy: 0.04, "…at MUI's resting 0.5 alpha")

        let hovered = render(ThemedChipView(palette: dracula, variant: .outlined,
                                            role: .primary, title: "Tag",
                                            previewHovered: true, clickable: true))
        XCTAssertGreaterThan(hovered.at(hovered.w / 2, dpx(0.5)).a, 0.9,
                             "interaction sharpens the stroke to full alpha")
    }

    func testOutlinedNeutralStrokesTheBorderRole() {
        let r = render(ThemedChipView(palette: dracula, variant: .outlined, title: "Tag"))
        assertHue(r.at(r.w / 2, dpx(0.5)), is: dracula.border,
                  "a neutral outline is the border role, not a half-strength foreground")
    }

    func testDisabledOutlineFallsBackToTheDisabledStroke() {
        let r = render(ThemedChipView(palette: dracula, variant: .outlined, role: .primary,
                                      title: "Tag", enabled: false))
        assertHue(r.at(r.w / 2, dpx(0.5)), is: dracula.disabledStroke,
                  "a disabled outline drops the role for the neutral disabled stroke")
    }

    // MARK: - the two OPT-IN affordances

    func testHoverWashesOnlyWhenTheBodyIsClickable() {
        let inert = renderOn(backdrop,
                             ThemedChipView(palette: dracula, title: "Tag", previewHovered: true))
        assertHue(fillProbe(inert), is: blend(dracula.ink(.wash, of: .muted), on: backdrop),
                  "a static chip never lights — appearanceGate is isClickable, not isEnabled")

        let live = renderOn(backdrop,
                            ThemedChipView(palette: dracula, title: "Tag",
                                           previewHovered: true, clickable: true))
        let wash = dracula.stateOverlay(.hover, on: .roleTint(dracula.foreground))
        assertHue(fillProbe(live),
                  is: blend(wash, on: blend(dracula.ink(.wash, of: .muted), on: backdrop)),
                  "a clickable chip washes the foreground tint over its resting fill")
    }

    func testPressWashesDeeperThanHover() {
        let hovered = renderOn(backdrop, ThemedChipView(palette: dracula, role: .primary, title: "Tag",
                                                  previewHovered: true, clickable: true))
        let pressed = renderOn(backdrop, ThemedChipView(palette: dracula, role: .primary, title: "Tag",
                                                  previewPressed: true, clickable: true))
        let onFill = dracula.primary
        assertHue(fillProbe(hovered),
                  is: blend(dracula.stateOverlay(.hover, on: .contrastInk(on: onFill)), on: onFill),
                  "hover washes contrastInk over the opaque role fill")
        assertHue(fillProbe(pressed),
                  is: blend(dracula.stateOverlay(.pressed, on: .contrastInk(on: onFill)), on: onFill),
                  "press washes the same ink at the deeper tier")
    }

    func testTheDeleteGlyphEmphasisesOnHoverWithoutLightingTheBody() {
        let chip = { [self] (hovered: Bool) in
            ThemedChipView(palette: dracula, variant: .outlined, title: "Tag",
                           previewHovered: hovered, deletable: true)
        }
        let rest = render(chip(false)), hot = render(chip(true))
        assertHue(deleteInk(rest), is: dracula.muted, "the × rests muted")
        assertHue(deleteInk(hot), is: dracula.foreground, "…and emphasises on hover")
        XCTAssertEqual(fillProbe(hot).a, 0, accuracy: 0.02,
                       "a delete-only chip's BODY still never washes (it is not clickable)")
    }

    func testTheErrorRoleTintsTheHoveredDeleteGlyphError() {
        let r = render(ThemedChipView(palette: dracula, variant: .outlined, role: .error,
                                      title: "Tag", previewHovered: true, deletable: true))
        assertHue(deleteInk(r), is: dracula.error, "an error chip's × goes error on hover")
    }

    // MARK: - the focus ring (gated by isInteractive, NOT by the body gate)

    private let pad: CGFloat = 16

    /// The ring is the box outset by 2 with a 2 pt stroke centred on it ⇒ the
    /// stroke spans 1…3 pt outside the rim; probe its middle at centre-x.
    private func ringProbe(_ r: Raster) -> (r: Double, g: Double, b: Double, a: Double) {
        r.at(r.w / 2, dpx(pad - 2))
    }

    func testFocusRingIsPaintedForAClickableChip() {
        let r = render(ThemedChipView(palette: dracula, title: "Tag",
                                      previewFocused: true, clickable: true).padding(pad))
        assertHue(ringProbe(r), is: dracula.primary, "the focus ring strokes the primary role")
    }

    func testFocusRingIsPaintedForADeleteOnlyChipToo() {
        // ThemedChip's `focusGate` is isInteractive: a delete-only chip stays
        // focusable so Backspace can reach its ×, even though its body is inert.
        let r = render(ThemedChipView(palette: dracula, title: "Tag",
                                      previewFocused: true, deletable: true).padding(pad))
        assertHue(ringProbe(r), is: dracula.primary,
                  "a delete-only chip still rings — the ring is gated by isInteractive")
    }

    func testAFullyStaticChipNeverRings() {
        let r = render(ThemedChipView(palette: dracula, title: "Tag",
                                      previewFocused: true).padding(pad))
        XCTAssertEqual(ringProbe(r).a, 0, accuracy: 0.02,
                       "no affordance ⇒ not focusable ⇒ no ring")
    }

    func testADisabledChipNeverRings() {
        let r = render(ThemedChipView(palette: dracula, title: "Tag", enabled: false,
                                      previewFocused: true, clickable: true,
                                      deletable: true).padding(pad))
        XCTAssertEqual(ringProbe(r).a, 0, accuracy: 0.02, "disabled drops out of isInteractive")
    }

    func testFocusWashesTheBodyOfAClickableChip() {
        // Unlike a contained button (ring + elevation only), the chip's clear /
        // translucent surface takes the hover-tier wash on focus too.
        let r = renderOn(backdrop,
                         ThemedChipView(palette: dracula, title: "Tag",
                                        previewFocused: true, clickable: true))
        let wash = dracula.stateOverlay(.hover, on: .roleTint(dracula.foreground))
        assertHue(fillProbe(r),
                  is: blend(wash, on: blend(dracula.ink(.wash, of: .muted), on: backdrop)),
                  "focus paints the hover-tier roleTint wash")
    }

    // MARK: - the three theming tiers, read off an opaque role fill

    func testFallsBackToTheProcessDefault() {
        assertHue(fillProbe(render(ThemedChipView(role: .primary, title: "T"))),
                  is: cobalt.primary, "no explicit argument and no ancestor theme ⇒ pal")
    }

    func testAmbientThemeBeatsTheProcessDefault() {
        assertHue(fillProbe(render(ThemedChipView(role: .primary, title: "T").sillTheme(dracula))),
                  is: dracula.primary, "ambient .sillTheme wins over pal")
    }

    func testExplicitArgumentBeatsTheAmbientTheme() {
        assertHue(fillProbe(render(ThemedChipView(palette: gruvbox, role: .primary, title: "T")
                                    .sillTheme(dracula))),
                  is: gruvbox.primary, "explicit palette wins over ambient")
    }
}
