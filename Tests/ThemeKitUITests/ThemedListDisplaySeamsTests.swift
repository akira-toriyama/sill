// The display restoration seams (t-q6ay, sill side):
//
//   1. `ListItem.isDimmed` / `dimmed(_:)` — a STANDING fade (facet's hidden
//      windows) that keeps everything `isDisabled` would take down: the row
//      stays selectable, liftable, hoverable, and out of the pure projection.
//   2. header KIND glyph — a section header now draws its `ListItem.image`
//      (facet: funnel = matched / tray = holding); the header branch used to
//      drop the image on the floor while the `.row` branch drew it.
//   3. `showsTitleTooltips` — hover tips carrying the full title +
//      secondary/sub-line, the read-the-whole-title affordance for a list
//      whose horizontal content scroll is off.
//
// Logic drives the internal rules directly (@testable); the render half
// rasterises via `NSHostingView` + `cacheDisplay` like FreezeSeamRenderTests.
// String ids on purpose (t-8xqf).
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
import ListCore
@testable import Palette
@testable import PaletteKit
@testable import ThemeKit
@testable import ThemeKitUI

@MainActor
final class ThemedListDisplaySeamsTests: XCTestCase {

    private let theme = resolve(Theme.dracula.spec)

    // MARK: 1 — isDimmed

    func testDimmedDefaultsOffAndCopyMethodSetsIt() {
        let plain = ListItem<String>(id: "x", primary: "x")
        XCTAssertFalse(plain.isDimmed)
        XCTAssertTrue(plain.dimmed().isDimmed)
        XCTAssertFalse(plain.dimmed().dimmed(false).isDimmed)
        // A statement ABOUT the row — the pure cores must never see it.
        XCTAssertEqual(plain.dimmed().asRow, plain.asRow)
    }

    func testDimmedKeepsTheRowLiftableAndLaidOutHeight() {
        let m = ListMetrics.forDensity(.comfortable)
        let row = ListItem<String>(id: "x", primary: "x")
        XCTAssertEqual(row.dimmed().laidOutHeight(m), row.laidOutHeight(m))

        var style = ThemedListStyle()
        style.draggable = true
        let v = ThemedListView<String>(items: [row.dimmed()], style: style, palette: theme)
        XCTAssertTrue(v.isDragSource(row.dimmed()),
                      "a dimmed row must stay a drag source — that is the whole point vs isDisabled")
    }

    func testDimmedFadesTheRowButKeepsTheSelectionVisible() {
        func shot(_ items: [ListItem<String>], selection: Set<String> = []) -> (px: [UInt8], w: Int, h: Int) {
            var style = ThemedListStyle()
            style.selectionMode = .single
            return raster(ThemedListView<String>(items: items, style: style, palette: theme,
                                                 preview: ListPreview(selection: selection)))
        }
        let items = [ListItem<String>(id: "a", primary: "First"),
                     ListItem<String>(id: "b", primary: "Second")]
        let dimmedItems = items.map { $0.id == "b" ? $0.dimmed() : $0 }

        XCTAssertGreaterThan(diff(shot(dimmedItems), shot(items)).count, 0,
                             "the dim must change the drawn row")
        // Selected + dimmed still shows the selection wash: it must differ from
        // the same dimmed list with NOTHING selected.
        XCTAssertGreaterThan(diff(shot(dimmedItems, selection: ["b"]), shot(dimmedItems)).count, 0,
                             "a dimmed row's selection must remain visible")
    }

    // MARK: 2 — header glyph

    private func header(_ image: NSImage?, emphasized: Bool = false) -> [ListItem<String>] {
        var h = ListItem<String>(id: "H", image: image, primary: "Matched",
                                 kind: .sectionHeader(subtitle: "2 windows"))
        h.isEmphasized = emphasized
        return [h, ListItem<String>(id: "r", primary: "row")]
    }

    private func shot(_ items: [ListItem<String>]) -> (px: [UInt8], w: Int, h: Int) {
        raster(ThemedListView<String>(items: items, style: ThemedListStyle(), palette: theme,
                                      preview: ListPreview()))
    }

    func testHeaderDrawsItsGlyph() {
        let glyph = phosphorImage("funnel", pt: 14)
        XCTAssertNotNil(glyph)
        let d = diff(shot(header(glyph)), shot(header(nil)))
        XCTAssertGreaterThan(d.count, 0, "a header with an image must draw it — it used to be dropped")
    }

    func testEmphasizedHeaderGlyphRidesTheAccent() {
        let glyph = phosphorImage("funnel", pt: 14)
        let d = diff(shot(header(glyph, emphasized: true)), shot(header(nil, emphasized: true)),
                     matches: theme.primary)
        XCTAssertGreaterThan(d.count, 0)
        XCTAssertTrue(d.hitsColor, "an emphasized header's glyph must tint `primary` with the title")
    }

    // MARK: 3 — showsTitleTooltips

    private func rowFor(_ item: ListItem<String>, tooltips: Bool) -> ThemedListRow<String> {
        var style = ThemedListStyle()
        style.showsTitleTooltips = tooltips
        return ThemedListRow(item: item, metrics: .forDensity(.comfortable), style: style,
                             palette: theme, isSelected: false, isHighlighted: false)
    }

    func testHelpTextOffByDefault() {
        let item = ListItem<String>(id: "a", primary: "Title", secondary: "sub")
        XCTAssertNil(rowFor(item, tooltips: false).helpText)
    }

    func testHelpTextJoinsTitleAndSecondary() {
        let full = ListItem<String>(id: "a", primary: "Safari", secondary: "GitHub — PRs")
        XCTAssertEqual(rowFor(full, tooltips: true).helpText, "Safari — GitHub — PRs")
        let bare = ListItem<String>(id: "b", primary: "Notes")
        XCTAssertEqual(rowFor(bare, tooltips: true).helpText, "Notes")
        let header = ListItem<String>(id: "H", primary: "Workspace A",
                                      kind: .sectionHeader(subtitle: "3 windows"))
        XCTAssertEqual(rowFor(header, tooltips: true).helpText, "Workspace A — 3 windows")
        let sep = ListItem<String>(id: "s", primary: "", kind: .separator)
        XCTAssertNil(rowFor(sep, tooltips: true).helpText)
    }

    // MARK: raster helpers (mirrors ThemedListRestoreSeamsTests)

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

    /// Differing pixel count over the whole raster, plus whether any differing
    /// pixel in `a` lands within `tol`/channel of `color`.
    private func diff(_ a: (px: [UInt8], w: Int, h: Int), _ b: (px: [UInt8], w: Int, h: Int),
                      matches color: NSColor? = nil, tol: Int = 40) -> (count: Int, hitsColor: Bool) {
        guard a.w == b.w, a.h == b.h, !a.px.isEmpty else { return (0, false) }
        var cr = 0, cg = 0, cb = 0
        if let c = color?.usingColorSpace(.sRGB) {
            cr = Int(c.redComponent * 255); cg = Int(c.greenComponent * 255); cb = Int(c.blueComponent * 255)
        }
        var n = 0, hit = false
        for i in stride(from: 0, to: a.px.count, by: 4) {
            let dr = abs(Int(a.px[i]) - Int(b.px[i]))
            let dg = abs(Int(a.px[i + 1]) - Int(b.px[i + 1]))
            let db = abs(Int(a.px[i + 2]) - Int(b.px[i + 2]))
            guard dr + dg + db > 12 else { continue }
            n += 1
            if color != nil, abs(Int(a.px[i]) - cr) <= tol,
               abs(Int(a.px[i + 1]) - cg) <= tol, abs(Int(a.px[i + 2]) - cb) <= tol { hit = true }
        }
        return (n, hit)
    }
}
