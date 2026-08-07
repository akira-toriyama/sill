// The themed scroll indicator (t-8649) — and the guard on the regression that
// motivated it: `ThemedListView` shipped with `.scrollIndicators(.hidden)`,
// which is a NO-OP on the AppKit-backed macOS `ScrollView` — the hosting
// scroll view kept a persistent, system-grey legacy `NSScroller` (measured
// with an `NSHostingView` probe, 2026-08-08). The fix is `.never`, which
// removes the `NSScroller` from the hierarchy, plus a SwiftUI-drawn `muted`
// pill; these cases pin both halves.
//
// The hierarchy case is a structural fact (an `NSScroller` exists or it does
// not). The knob cases rasterise and compare, because "the pill is drawn" is
// a render claim and XCTest proves logic, not SwiftUI render — hosted in an
// `NSHostingView` inside a real (never-shown) window and pumped, because the
// scroll geometry the knob is computed from lands on a scroll-geometry pass
// after layout (same machinery as ThemedListScrollFollowTests).
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
@testable import Palette
@testable import PaletteKit
@testable import ThemeKitUI

@MainActor
final class ThemedListScrollIndicatorTests: XCTestCase {

    private let theme = resolve(Theme.dracula.spec)
    private let width: CGFloat = 300
    private let height: CGFloat = 200

    private func rows(_ n: Int, wide: Bool = false) -> [ListItem<Int>] {
        (0..<n).map { ListItem<Int>(id: $0, primary: wide ? "a very wide row \($0) padded well past the viewport edge" : "row \($0)") }
    }

    /// Host `view` in a never-shown window and pump until the scroll-geometry
    /// pass has run, then hand back the live hosting view.
    private func host<V: View>(_ view: V) -> NSHostingView<AnyView> {
        let h = NSHostingView(rootView: AnyView(view))
        h.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let win = NSWindow(contentRect: h.frame, styleMask: [.borderless],
                           backing: .buffered, defer: false)
        win.contentView = h
        h.layoutSubtreeIfNeeded()
        _ = h.fittingSize
        h.layoutSubtreeIfNeeded()
        for _ in 0..<10 {
            h.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return h
    }

    private func raster(_ h: NSHostingView<AnyView>) -> (px: [UInt8], w: Int, h: Int) {
        guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else {
            XCTFail("no bitmap rep for the hosted list"); return ([], 0, 0)
        }
        h.cacheDisplay(in: h.bounds, to: rep)
        guard let img = rep.cgImage else {
            XCTFail("the hosted list produced no image"); return ([], 0, 0)
        }
        var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: img.width, height: img.height,
                                bitsPerComponent: 8, bytesPerRow: img.width * 4, space: cs,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        }
        return (buf, img.width, img.height)
    }

    private func scroller(in v: NSView) -> NSScroller? {
        if let s = v as? NSScroller { return s }
        for sub in v.subviews { if let s = scroller(in: sub) { return s } }
        return nil
    }

    /// Pixels differing between two rasters inside a point-space rect, and
    /// whether any differing pixel in `a` sits within `tol` per channel of
    /// `color` (the knob paint, allowing antialiased edges around it).
    private func diff(_ a: (px: [UInt8], w: Int, h: Int),
                      _ b: (px: [UInt8], w: Int, h: Int),
                      in rect: CGRect, matches color: NSColor,
                      tol: Int = 40) -> (count: Int, hitsColor: Bool) {
        let scale = max(1, a.w / Int(width))
        let c = color.usingColorSpace(.sRGB)!
        let (cr, cg, cb) = (Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        var n = 0, hit = false
        for y in Int(rect.minY) * scale ..< min(a.h, Int(rect.maxY) * scale) {
            for x in Int(rect.minX) * scale ..< min(a.w, Int(rect.maxX) * scale) {
                let i = (y * a.w + x) * 4
                guard a.px[i] != b.px[i] || a.px[i+1] != b.px[i+1]
                    || a.px[i+2] != b.px[i+2] || a.px[i+3] != b.px[i+3] else { continue }
                n += 1
                if abs(Int(a.px[i]) - cr) <= tol && abs(Int(a.px[i+1]) - cg) <= tol
                    && abs(Int(a.px[i+2]) - cb) <= tol { hit = true }
            }
        }
        return (n, hit)
    }

    // MARK: - the native scroller is GONE (the shipped regression)

    func testNoNativeScrollerInTheHierarchy() {
        var style = ThemedListStyle()
        style.showsScrollIndicators = false        // even with the themed pill off
        let h = host(ThemedListView<Int>(items: rows(60), style: style, palette: theme))
        XCTAssertNil(scroller(in: h),
                     "an overflowing list must host NO NSScroller — the persistent "
                     + "system-grey scroller that `.scrollIndicators(.hidden)` "
                     + "leaves behind is the shipped regression")
    }

    // MARK: - the themed pill draws (persistent under a pinned preview)

    private func list(indicators: Bool, preview: ListPreview<Int>?,
                      horizontal: Bool = false, wide: Bool = false) -> some View {
        var style = ThemedListStyle()
        style.showsScrollIndicators = indicators
        style.horizontalContentScroll = horizontal
        return ThemedListView<Int>(items: rows(60, wide: wide), style: style,
                                   palette: theme, preview: preview)
            .frame(width: width, height: height)
    }

    func testVerticalKnobDrawsInTheMutedRole() {
        let pinned = ListPreview<Int>(scrollY: 30)
        let on = raster(host(list(indicators: true, preview: pinned)))
        let off = raster(host(list(indicators: false, preview: pinned)))
        // The pill floats in the trailing 12pt band (thickness 6 + margin 3).
        let band = CGRect(x: width - 12, y: 0, width: 12, height: height)
        let d = diff(on, off, in: band, matches: theme.muted)
        XCTAssertGreaterThan(d.count, 0,
                             "a pinned-scroll preview must draw the vertical knob — "
                             + "prism's static capture can never show it otherwise")
        XCTAssertTrue(d.hitsColor, "the knob paints in the muted role, not system grey")
    }

    func testHorizontalKnobDrawsWhenContentScrollsSideways() {
        var pinned = ListPreview<Int>()
        pinned.scrollX = 40
        let on = raster(host(list(indicators: true, preview: pinned, horizontal: true, wide: true)))
        let off = raster(host(list(indicators: false, preview: pinned, horizontal: true, wide: true)))
        let band = CGRect(x: 0, y: height - 12, width: width, height: 12)
        let d = diff(on, off, in: band, matches: theme.muted)
        XCTAssertGreaterThan(d.count, 0, "the sideways-scrolling list draws the bottom knob")
        XCTAssertTrue(d.hitsColor, "the horizontal knob paints in the muted role")
    }
}
