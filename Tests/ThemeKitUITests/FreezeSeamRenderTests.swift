// The t-avbj freeze seams — every interactive state a static bench shot could
// never show now freezes, and these cases pin BOTH halves of that claim:
// (a) the frozen state actually DRAWS (raster differs from the unfrozen
// control, and the differing pixels carry the expected role), and (b) freezing
// is DETERMINISTIC (two captures of the same frozen value are byte-identical —
// the whole point; the shimmer was the state where every capture caught a
// different phase).
//
// Rasterised via `NSHostingView` + `cacheDisplay`, windowless — these are
// static poses, no scroll/animation machinery involved (`ImageRenderer` draws
// nothing inside the list's ScrollView/LazyVStack, measured in #175).
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
@testable import Palette
@testable import PaletteKit
@testable import ThemeKitUI

@MainActor
final class FreezeSeamRenderTests: XCTestCase {

    private let theme = resolve(Theme.dracula.spec)
    private let width: CGFloat = 320
    private let height: CGFloat = 200

    private func raster<V: View>(_ view: V) -> (px: [UInt8], w: Int, h: Int) {
        let host = NSHostingView(rootView: AnyView(view.frame(width: width, height: height)))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        _ = host.fittingSize
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("no bitmap rep"); return ([], 0, 0)
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let img = rep.cgImage else { XCTFail("no image"); return ([], 0, 0) }
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

    /// Differing pixel count inside a point-space rect, plus whether any
    /// differing pixel in `a` lands within `tol`/channel of `color`.
    private func diff(_ a: (px: [UInt8], w: Int, h: Int), _ b: (px: [UInt8], w: Int, h: Int),
                      in rect: CGRect, matches color: NSColor? = nil,
                      tol: Int = 40) -> (count: Int, hitsColor: Bool) {
        let scale = max(1, a.w / Int(width))
        var cr = 0, cg = 0, cb = 0
        if let c = color?.usingColorSpace(.sRGB) {
            cr = Int(c.redComponent * 255); cg = Int(c.greenComponent * 255); cb = Int(c.blueComponent * 255)
        }
        var n = 0, hit = false
        for y in Int(rect.minY) * scale ..< min(a.h, Int(rect.maxY) * scale) {
            for x in Int(rect.minX) * scale ..< min(a.w, Int(rect.maxX) * scale) {
                let i = (y * a.w + x) * 4
                guard a.px[i] != b.px[i] || a.px[i+1] != b.px[i+1]
                    || a.px[i+2] != b.px[i+2] || a.px[i+3] != b.px[i+3] else { continue }
                n += 1
                if color != nil, abs(Int(a.px[i]) - cr) <= tol && abs(Int(a.px[i+1]) - cg) <= tol
                    && abs(Int(a.px[i+2]) - cb) <= tol { hit = true }
            }
        }
        return (n, hit)
    }

    private var full: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    // MARK: - list: the frozen keyboard focus ring

    private func list(ring: Bool) -> some View {
        let items = (0..<4).map { ListItem<Int>(id: $0, primary: "row \($0)") }
        return ThemedListView<Int>(items: items, palette: theme,
                                   preview: ListPreview<Int>().showingFocusRing(ring))
    }

    func testListFocusRingFreezes() {
        let d = diff(raster(list(ring: true)), raster(list(ring: false)),
                     in: full, matches: theme.primary)
        XCTAssertGreaterThan(d.count, 0,
                             "showingFocusRing() must draw the list-level ring — it hung off "
                             + "a @FocusState no bench could reach")
        XCTAssertTrue(d.hitsColor, "the ring strokes in the primary role")
    }

    // MARK: - grid: hover veil + cursor ring freeze

    private func grid(_ preview: GridPreview<String>?) -> some View {
        let items = (0..<6).map { ThumbnailItem(id: "c\($0)", image: nil, label: "cell \($0)") }
        return ThemedThumbnailGridView(items, selection: .constant([]),
                                       layout: .fixed(columns: 3), aspectRatio: 1,
                                       palette: theme)
            .preview(preview)
            .previewShimmerPhase(0.5)          // park the sweep so ONLY the chrome differs
    }

    func testGridHoverFreezes() {
        let d = diff(raster(grid(GridPreview(hovered: "c1", focused: false))),
                     raster(grid(GridPreview(focused: false))), in: full)
        XCTAssertGreaterThan(d.count, 0,
                             "GridPreview.hovered must draw the hover veil — the grid had "
                             + "no preview seam at all before t-avbj")
    }

    func testGridCursorRingFreezes() {
        let d = diff(raster(grid(GridPreview(cursor: "c2"))),
                     raster(grid(GridPreview())), in: full, matches: theme.primary)
        XCTAssertGreaterThan(d.count, 0, "GridPreview.cursor + focused draws the cursor ring")
        XCTAssertTrue(d.hitsColor, "the cursor ring strokes in the primary role")
    }

    // MARK: - toolbar: frozen pressed / focused poses

    private func bar(pressed: Int? = nil, focusedItem: Int? = nil) -> some View {
        ThemedToolBarView(palette: theme, items: [
            .button(title: nil, symbol: "text-b"),
            .button(title: nil, symbol: "text-italic"),
            .button(title: nil, symbol: "text-underline"),
        ], surface: .transparent, variant: .compact)
            .previewPressed(pressed)
            .previewFocused(focusedItem)
    }

    func testToolBarPressedFreezes() {
        let d = diff(raster(bar(pressed: 1)), raster(bar()), in: full)
        XCTAssertGreaterThan(d.count, 0,
                             "previewPressed(i) must draw the pressed pose — hover was the "
                             + "only freezable toolbar state before t-avbj")
    }

    func testToolBarFocusFreezes() {
        let d = diff(raster(bar(focusedItem: 2)), raster(bar()), in: full)
        XCTAssertGreaterThan(d.count, 0, "previewFocused(i) must draw the focus pose")
    }

    // MARK: - shimmer: a frozen phase is DETERMINISTIC, and the phase moves the band

    func testFrozenShimmerIsDeterministic() {
        let a = raster(grid(GridPreview(focused: false)))
        let b = raster(grid(GridPreview(focused: false)))
        XCTAssertEqual(a.px, b.px,
                       "two captures of the same frozen shimmer phase must be byte-identical "
                       + "— per-capture phase drift is exactly what made theme comparison "
                       + "impossible (t-avbj)")
    }

    func testShimmerPhaseActuallyMoves() {
        let items = [ThumbnailItem(id: "l0", image: nil)]
        func cell(_ phase: CGFloat) -> some View {
            ThemedThumbnailGridView(items, selection: .constant([]),
                                    layout: .fixed(columns: 1), aspectRatio: 1, palette: theme)
                .preview(GridPreview(focused: false))
                .previewShimmerPhase(phase)
        }
        let d = diff(raster(cell(0.1)), raster(cell(0.9)), in: full)
        XCTAssertGreaterThan(d.count, 0, "different frozen phases park the band at different x")
    }

    // MARK: - the reorder grip draws (the catalog claimed it for a year; no code existed)

    private func gripList(shows: Bool) -> some View {
        var style = ThemedListStyle()
        style.draggable = true
        style.showsReorderGrip = shows
        let items: [ListItem<Int>] = [
            ListItem(id: 0, primary: "Section", kind: .sectionHeader(subtitle: nil)),
            ListItem(id: 1, primary: "row one"),
        ]
        return ThemedListView<Int>(items: items, style: style, palette: theme,
                                   preview: ListPreview<Int>())
    }

    func testReorderGripDrawsOnDraggableHeaders() {
        let m = ListMetrics.forDensity(.comfortable)
        // The grip sits at the header's trailing edge — scan that band only.
        let band = CGRect(x: width - 40, y: 0, width: 40, height: m.header1)
        let d = diff(raster(gripList(shows: true)), raster(gripList(shows: false)),
                     in: band, matches: theme.muted)
        XCTAssertGreaterThan(d.count, 0,
                             "showsReorderGrip=true must draw the 2×3 grip — the catalog "
                             + "claimed this while no draw code existed (t-avbj)")
        XCTAssertTrue(d.hitsColor, "the grip dots paint in the muted role")
    }
}
