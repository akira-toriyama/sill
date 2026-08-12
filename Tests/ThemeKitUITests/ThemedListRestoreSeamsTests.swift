// The three restoration seams (t-h3rv) a consuming app needs so a migration
// does not have to give a capability up:
//
//   1. `dragChunk(_:)`   — WHAT a lift carries. Returning [] for a header lifts
//                          it alone, which is the only way a header can aim
//                          `.onto` another row (a chunk is forced to
//                          `.reorderBetween` by `resolveDropTarget`).
//   2. `ListItem.isEmphasized` — WHICH row is the active one, in the accent, so
//                          a host stops gluing a mark onto the title STRING
//                          (where tail truncation eats it first).
//   3. `dropBand(_:)`    — WHICH rows a coarse-granularity drop really lands in,
//                          painted as an area instead of a 2pt line that
//                          promises a placement the commit cannot honour.
//
// Both drag paths are exercised through the same `package` seams the live
// gesture / keypress use, so what is asserted here is what ships. The render
// half rasterises via `NSHostingView` + `cacheDisplay` (windowless), matching
// FreezeSeamRenderTests — a logic-only proof would not catch a seam that
// resolves correctly and draws nothing.
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
import ListCore
@testable import Palette
@testable import PaletteKit
@testable import ThemeKitUI

@MainActor
final class ThemedListRestoreSeamsTests: XCTestCase {

    private let theme = resolve(Theme.dracula.spec)

    /// Two sections: header "A" with rows a1/a2, header "B" with rows b1/b2.
    /// String ids on purpose — an Int-keyed fixture can collide with the outer
    /// `ForEach(\.offset)` identity and hide a gap (t-8xqf, #177's guard test).
    private func sectioned() -> [ListItem<String>] {
        [ListItem<String>(id: "A", primary: "A", kind: .sectionHeader()),
         ListItem<String>(id: "a1", primary: "a1"),
         ListItem<String>(id: "a2", primary: "a2"),
         ListItem<String>(id: "B", primary: "B", kind: .sectionHeader()),
         ListItem<String>(id: "b1", primary: "b1"),
         ListItem<String>(id: "b2", primary: "b2")]
    }

    private func list(_ items: [ListItem<String>], mode: DragMode = .both) -> ThemedListView<String> {
        var style = ThemedListStyle()
        style.draggable = true
        style.dragMode = mode
        return ThemedListView<String>(items: items, style: style, palette: theme)
    }

    private func uniformGeom(_ n: Int, height: CGFloat = 24) -> [RowGeom] {
        (0..<n).map { RowGeom(yOffset: CGFloat($0) * height, height: height) }
    }

    // MARK: 1 — dragChunk

    func testDefaultHeaderCarriesItsSectionOnBothPaths() {
        let v = list(sectioned())
        XCTAssertEqual(v.chunkIDs(for: "A"), ["A", "a1", "a2"])
        XCTAssertEqual(v.kbChunk(for: "A"), ["A", "a1", "a2"])
    }

    func testDefaultPlainRowTravelsAlone() {
        let v = list(sectioned())
        XCTAssertEqual(v.chunkIDs(for: "a1"), [])
        XCTAssertEqual(v.kbChunk(for: "a1"), [])
    }

    /// The provider is consulted by BOTH resolution paths — the pointer's
    /// per-move lift and the keyboard lift. The two used to compute the chunk
    /// separately, which is exactly how a header could behave differently
    /// depending on which hand moved it.
    func testProviderOverridesBothPaths() {
        let v = list(sectioned()).dragChunk { $0 == "A" ? ["A", "a1"] : [] }
        XCTAssertEqual(v.chunkIDs(for: "A"), ["A", "a1"])
        XCTAssertEqual(v.kbChunk(for: "A"), ["A", "a1"])
        XCTAssertEqual(v.chunkIDs(for: "B"), [])
    }

    /// The restoration case: an empty chunk lets a HEADER resolve `.onto`
    /// another header (facet's workspace-content swap). With the kit's default
    /// rule the same drag can only ever be an insertion between rows.
    func testEmptyChunkLetsAHeaderAimOntoAnotherHeader() {
        let items = sectioned()
        let geom = uniformGeom(items.count)
        let swap = list(items).dragChunk { _ in [] }
        // Row 3 ("B") centre — the `.both` mode's onto band is the middle half.
        let target = swap.pointerDropTarget(atDocY: 24 * 3 + 12, source: "A", chunkIDs: [], geom: geom)
        XCTAssertEqual(target, DropTarget(placement: .onto(id: "B")))

        let aim = swap.kbDragAim(from: "A", chunkIDs: [])
        XCTAssertTrue(aim.contains(DropTarget(placement: .onto(id: "B"))),
                      "a header lifted alone must be able to aim onto another header")
    }

    /// The default is unchanged by the seam's existence: a chunked header still
    /// resolves to a gap, never onto a row.
    func testDefaultChunkStillResolvesToAGapNotOnto() {
        let items = sectioned()
        let v = list(items)
        let chunk = v.chunkIDs(for: "A")
        let target = v.pointerDropTarget(atDocY: 24 * 3 + 12, source: "A", chunkIDs: chunk,
                                         geom: uniformGeom(items.count))
        if case .onto = target?.placement {
            XCTFail("a chunk lift must not resolve onto a row")
        }
    }

    // MARK: 2 — isEmphasized

    func testEmphasisDefaultsOffAndCopyMethodSetsIt() {
        let plain = ListItem<String>(id: "x", primary: "x")
        XCTAssertFalse(plain.isEmphasized)
        XCTAssertTrue(plain.emphasized().isEmphasized)
        XCTAssertFalse(plain.emphasized().emphasized(false).isEmphasized)
        // The flag is a statement ABOUT the row, not a row state: it must not
        // leak into the pure projection every core reasons over.
        XCTAssertEqual(plain.emphasized().asRow, plain.asRow)
    }

    /// Emphasis must not reflow: it moves the WEIGHT, never the size, so a
    /// list's laid-out height (and every rect derived from it) is untouched.
    func testEmphasisDoesNotChangeLaidOutHeight() {
        let m = ListMetrics.forDensity(.comfortable)
        let row = ListItem<String>(id: "x", primary: "x")
        let header = ListItem<String>(id: "h", primary: "h", kind: .sectionHeader(subtitle: "s"))
        XCTAssertEqual(row.emphasized().laidOutHeight(m), row.laidOutHeight(m))
        XCTAssertEqual(header.emphasized().laidOutHeight(m), header.laidOutHeight(m))
    }

    func testEmphasizedHeaderDrawsInTheAccent() {
        let plain = raster(list(sectioned()))
        let hot = raster(list(sectioned().map { $0.id == "B" ? $0.emphasized() : $0 }))
        // The "B" header is the 4th of six 24-40pt rows; compare the whole
        // raster and require the difference to carry the accent.
        let d = diff(hot, plain, matches: theme.primary)
        XCTAssertGreaterThan(d.count, 0, "emphasis must change the drawn header")
        XCTAssertTrue(d.hitsColor, "an emphasized header must draw in `primary`")
    }

    // MARK: 3 — dropBand

    private func band(_ v: ThemedListView<String>) -> ThemedListView<String>.DropBand? { v.dropBand }

    func testNoBandProviderMeansNoBand() {
        let v = list(sectioned())
        XCTAssertNil(band(v))
    }

    func testBandEdgesFollowVisibleOrderNotTheHostArray() {
        // The host hands the members back-to-front on purpose.
        let v = ThemedListView<String>(items: sectioned(), style: ThemedListStyle(), palette: theme,
                                       preview: ListPreview(dropTarget: DropTarget(placement: .onto(id: "B"))))
            .dropBand { _ in ["b2", "B", "b1"] }
        guard let b = band(v) else { return XCTFail("expected a band") }
        XCTAssertEqual(b.first, "B")
        XCTAssertEqual(b.last, "b2")
        XCTAssertEqual(b.members, ["B", "b1", "b2"])
    }

    func testBandOwnsTheAffordanceForItsRowsAndNothingElse() {
        let v = ThemedListView<String>(items: sectioned(), style: ThemedListStyle(), palette: theme,
                                       preview: ListPreview(dropTarget: DropTarget(placement: .onto(id: "B"))))
            .dropBand { _ in ["B", "b1", "b2"] }
        let b = band(v)
        XCTAssertEqual(v.rowDrop("B", band: b), .bandTop)
        XCTAssertEqual(v.rowDrop("b1", band: b), .bandBody)
        XCTAssertEqual(v.rowDrop("b2", band: b), .bandBottom)
        // The `.onto` ring must NOT also draw on the target row — one drop, one
        // promise.
        XCTAssertNil(v.rowDrop("a1", band: b))
        XCTAssertNil(v.rowDrop("A", band: b))
    }

    func testOneRowBandClosesItsWholeOutline() {
        let v = ThemedListView<String>(items: sectioned(), style: ThemedListStyle(), palette: theme,
                                       preview: ListPreview(dropTarget: DropTarget(placement: .onto(id: "b1"))))
            .dropBand { _ in ["b1"] }
        XCTAssertEqual(v.rowDrop("b1", band: band(v)), .bandSolo)
    }

    func testEmptyBandFallsBackToTheNormalAffordance() {
        let v = ThemedListView<String>(items: sectioned(), style: ThemedListStyle(), palette: theme,
                                       preview: ListPreview(dropTarget: DropTarget(placement: .onto(id: "B"))))
            .dropBand { _ in [] }
        XCTAssertNil(band(v))
        XCTAssertEqual(v.rowDrop("B", band: nil), .onto)
    }

    func testBandDrawsAnAreaNotALine() {
        // Measured against the SAME list with no drop aimed at all, so each
        // affordance is scored by the pixels IT changes. (Counting "pixels near
        // the accent" instead scores the theme, not the affordance: on dracula
        // the untouched rows already sit within tolerance of `primary`, and the
        // band — which darkens them under its wash — reads as *less* accent.)
        let control = ThemedListView<String>(items: sectioned(), style: ThemedListStyle(), palette: theme,
                                             preview: ListPreview())
        let ontoOnly = ThemedListView<String>(items: sectioned(), style: ThemedListStyle(), palette: theme,
                                              preview: ListPreview(dropTarget: DropTarget(placement: .onto(id: "B"))))
        let banded = ontoOnly.dropBand { _ in ["B", "b1", "b2"] }

        let base = raster(control)
        let ring = diff(raster(ontoOnly), base, matches: theme.primary)
        let area = diff(raster(banded), base, matches: theme.primary)

        XCTAssertGreaterThan(ring.count, 0, "the control must actually differ from the ring shot")
        XCTAssertGreaterThan(area.count, 0, "the band must draw")
        XCTAssertTrue(area.hitsColor, "the band paints in `primary`")
        // An area, not a line: a three-row band has to change far more of the
        // shot than one row's ring does.
        XCTAssertGreaterThan(area.count, ring.count * 2,
                             "a three-row band must cover far more than one row's ring")
    }

    // MARK: 4 — badge cap (draw and measurement agree)

    func testBadgeCapIsPositiveAndDensityKeyed() {
        XCTAssertGreaterThan(ListMetrics.forDensity(.comfortable).badgeMaxText, 0)
        XCTAssertGreaterThan(ListMetrics.forDensity(.compact).badgeMaxText, 0)
    }

    /// The measurer must honour the same cap the label truncates at — otherwise
    /// the text budget is computed against a width the pill never occupies, and
    /// a host restoring readable words pays for space nothing uses.
    func testFittingWidthStopsGrowingPastTheBadgeCap() {
        func width(_ badge: String) -> CGFloat {
            let c = ListController<String>()
            c.items = [ListItem<String>(id: "r", primary: "Notes", badges: [Badge(badge)])]
            return c.fittingWidth(palette: theme)
        }
        let long = width(String(repeating: "n", count: 40))
        let absurd = width(String(repeating: "n", count: 400))
        XCTAssertEqual(long, absurd, "past the cap a longer label must not widen the row")
    }

    // MARK: raster helpers (mirrors FreezeSeamRenderTests)

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
