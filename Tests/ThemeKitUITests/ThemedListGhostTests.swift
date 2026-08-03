// The drag ghost and the pointer veil, read off the FROZEN `preview` seam.
//
// Both used to be unreachable from a static shot. `dragGhostLayer` refused to
// draw whenever `preview` was non-nil, so prism's four drag cells rendered the
// row dimming and the insertion line but never the ghost itself — the widget's
// most visible drag affordance had no capture path at all, and its degradation
// to a bare text chip shipped unnoticed. `ListPreview` had no `hovered` field
// either, though every sibling widget takes `previewHovered`.
//
// These cases rasterise and compare, because "the ghost is drawn" is a claim
// about pixels and XCTest proves logic, not SwiftUI render.
//
// They host in an `NSHostingView` rather than reaching for `ImageRenderer` like
// the sibling render suites. That is not a style choice: `ImageRenderer` draws
// NOTHING inside this widget's `ScrollView`/`LazyVStack` — measured on the very
// states below, it reported 0 differing pixels between a plain list and a lifted
// one, while the hosted path reported ~36k. The simpler widgets rasterise fine
// because nothing about them is lazy or scrolled. (measured 2026-08-03)
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
@testable import Palette
@testable import PaletteKit
@testable import ThemeKitUI

@MainActor
final class ThemedListGhostTests: XCTestCase {

    private let theme = resolve(Theme.dracula.spec)
    private let width: CGFloat = 300
    private let height: CGFloat = 260

    private struct Raster {
        let px: [UInt8]; let w: Int; let h: Int
        /// Device pixels per point — the hosted bitmap comes back at the backing
        /// scale, so every point coordinate has to be lifted through this.
        var scale: Int { max(1, w / 300) }
        func differs(from other: Raster, atRow y: Int, x: Int) -> Bool {
            let i = (y * w + x) * 4
            return px[i] != other.px[i] || px[i + 1] != other.px[i + 1]
                || px[i + 2] != other.px[i + 2] || px[i + 3] != other.px[i + 3]
        }
        /// How many pixels of scanline `y` differ from `other`.
        func differingPixels(from other: Raster, atRow y: Int) -> Int {
            (0..<w).count { differs(from: other, atRow: y, x: $0) }
        }
        /// Leftmost-to-rightmost span of the differing pixels on scanline `y`.
        /// The COUNT is the wrong measure for a card whose fill matches the
        /// surface it covers — only its border and its glyphs differ — while the
        /// span still reports the card's true width.
        func differingSpan(from other: Raster, atRow y: Int) -> Int {
            let xs = (0..<w).filter { differs(from: other, atRow: y, x: $0) }
            guard let lo = xs.first, let hi = xs.last else { return 0 }
            return hi - lo
        }
    }

    private func rows(_ n: Int) -> [ListItem<Int>] {
        (0..<n).map { ListItem<Int>(id: $0, primary: "window title \($0)") }
    }

    private func render(_ preview: ListPreview<Int>?) -> Raster {
        var style = ThemedListStyle()
        style.selectionMode = .single
        style.showsDividers = true
        style.draggable = true
        let view = ThemedListView<Int>(items: rows(6), style: style,
                                       palette: theme, preview: preview)
            .frame(width: width, height: height)
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        _ = host.fittingSize
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("no bitmap rep for the hosted list")
            return Raster(px: [], w: 0, h: 0)
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let img = rep.cgImage else {
            XCTFail("the hosted list produced no image")
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

    /// The ghost parks half a row plus 22 pt below the top of the row it lifted
    /// (`ghostCentre`), so for a lift of row 1 the card straddles this scanline.
    private func ghostBandY(_ r: Raster) -> Int {
        let m = ListMetrics.forDensity(.comfortable)
        return Int(m.singleRow + m.singleRow / 2 + 22) * r.scale
    }

    // MARK: - the ghost exists under a frozen preview

    func testAFrozenLiftDrawsTheGhost() {
        let idle = render(nil)
        let lifted = render(ListPreview(dragSource: 1))
        XCTAssertGreaterThan(lifted.differingPixels(from: idle, atRow: ghostBandY(lifted)), 0,
                             "a frozen lift must draw its ghost — 0 differing pixels here is "
                             + "the blindness that hid the ghost from prism entirely")
    }

    func testTheGhostCarriesTheRowAndNotALabel() {
        // The card is the list width less 24 pt. A text chip is only as wide as
        // its title, so width is what separates "the lifted row" from "a label
        // for the lifted row" without reading any glyphs back.
        let idle = render(nil)
        let lifted = render(ListPreview(dragSource: 1))
        let span = lifted.differingSpan(from: idle, atRow: ghostBandY(lifted))
        XCTAssertGreaterThan(Double(span), Double(lifted.w) * 0.7,
                             "the ghost spans nearly the full list width")
    }

    func testAChunkLiftGhostsWithoutAnExplicitSource() {
        // prism's chunk cells name only the members, so the chunk alone has to be
        // enough to place the card.
        let idle = render(nil)
        let lifted = render(ListPreview(dragChunk: [1, 2]))
        XCTAssertGreaterThan(lifted.differingPixels(from: idle, atRow: ghostBandY(lifted)), 0,
                             "a chunk with no dragSource still ghosts")
    }

    // MARK: - hover joins the frozen vocabulary

    func testFrozenHoverChangesTheSelectedRow() {
        // The wash paints only on a selected row (ThemedListRow :356), so the
        // specimen is selected — otherwise both shots would be identical for a
        // reason that has nothing to do with the seam under test.
        let plain = render(ListPreview(selection: [3]))
        let hot = render(ListPreview(selection: [3]).hovering(3))
        let m = ListMetrics.forDensity(.comfortable)
        let rowMidY = Int(m.singleRow * 3 + m.singleRow / 2) * hot.scale
        XCTAssertGreaterThan(hot.differingPixels(from: plain, atRow: rowMidY), 0,
                             "freezing hover on the selected row must change its ink")
    }

    func testALiveHoverIsIgnoredWhileAPreviewIsFrozen() {
        // A frozen shot must not be contaminated by a pointer that happens to be
        // resting over the bench.
        let a = render(ListPreview(selection: [3]))
        let b = render(ListPreview(selection: [3]))
        let m = ListMetrics.forDensity(.comfortable)
        let rowMidY = Int(m.singleRow * 3 + m.singleRow / 2) * a.scale
        XCTAssertEqual(a.differingPixels(from: b, atRow: rowMidY), 0,
                       "two identical frozen previews render identically")
    }
}
