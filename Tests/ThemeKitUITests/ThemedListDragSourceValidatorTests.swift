// The dragSourceValidator seam (t-jzbf): a host's veto over BEGINNING a lift,
// distinct from `isDisabled` — which is the first flag `ListItem.tapOutcome`
// consults and so takes the row's click, hover and selection down with the
// drag (facet's holding rows are display-only for DnD but fully clickable).
//
// The logic half drives the same `package` gate the production gesture attach
// and keyboard Space lift consult (`isDragSource`), so the validator wired
// here is the validator the live paths use. The render half proves the frozen
// `preview` obeys the SAME gate: a bench cell pinning `dragSource` on a vetoed
// row must draw exactly the no-drag frame — no ghost, no dimming — or prism
// would show a state the widget cannot reach (the t-avbj mock, inverted).
//
// String ids on purpose — an Int-keyed fixture can collide with the outer
// `ForEach(\.offset)` identity and hide a gap (t-8xqf, #177's guard test).
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
final class ThemedListDragSourceValidatorTests: XCTestCase {

    private let theme = resolve(Theme.dracula.spec)

    /// One section: header "A" over a normal row, a vetoed row, and a disabled row.
    private func rows() -> [ListItem<String>] {
        [ListItem<String>(id: "A", primary: "A", kind: .sectionHeader()),
         ListItem<String>(id: "free", primary: "free"),
         ListItem<String>(id: "holding", primary: "holding"),
         ListItem<String>(id: "off", primary: "off", isDisabled: true),
         ListItem<String>(id: "sep", primary: "", kind: .separator)]
    }

    private func list(veto: Set<String> = [],
                      preview: ListPreview<String>? = nil) -> ThemedListView<String> {
        var style = ThemedListStyle()
        style.draggable = true
        style.dragMode = .both
        let v = ThemedListView<String>(items: rows(), style: style, palette: theme, preview: preview)
        guard !veto.isEmpty else { return v }
        return v.dragSourceValidator { !veto.contains($0) }
    }

    private func item(_ id: String) -> ListItem<String> {
        rows().first { $0.id == id }!
    }

    // MARK: the gate

    func testDefaultLetsEveryEnabledRowLift() {
        let v = list()
        XCTAssertTrue(v.isDragSource(item("free")))
        XCTAssertTrue(v.isDragSource(item("A")), "headers are liftable (they carry their chunk)")
        XCTAssertFalse(v.isDragSource(item("off")), "isDisabled still refuses the lift")
        XCTAssertFalse(v.isDragSource(item("sep")))
    }

    func testVetoRefusesExactlyTheNamedRow() {
        let v = list(veto: ["holding"])
        XCTAssertFalse(v.isDragSource(item("holding")))
        XCTAssertTrue(v.isDragSource(item("free")), "the veto must not leak onto other rows")
        XCTAssertTrue(v.isDragSource(item("A")))
    }

    /// The validator NARROWS the gate, never widens it: accepting a disabled
    /// row's id must not make it liftable, and draggable=false beats everything.
    func testValidatorCannotOverrideTheStructuralRefusals() {
        let accepting = list(veto: [])
        XCTAssertFalse(accepting.isDragSource(item("off")))
        var style = ThemedListStyle()
        style.draggable = false
        let inert = ThemedListView<String>(items: rows(), style: style, palette: theme)
            .dragSourceValidator { _ in true }
        XCTAssertFalse(inert.isDragSource(item("free")))
    }

    func testCopyMethodLeavesOriginalAccepting() {
        let original = list()
        let vetoing = original.dragSourceValidator { $0 != "free" }
        XCTAssertFalse(vetoing.isDragSource(item("free")))
        XCTAssertTrue(original.isDragSource(item("free")),
                      "dragSourceValidator(_:) must return a copy, not mutate the receiver")
    }

    // MARK: the frozen preview obeys the same gate

    func testVetoedFrozenLiftRendersTheNoDragFrame() {
        let control = list(veto: ["holding"], preview: ListPreview())
        let vetoedLift = list(veto: ["holding"],
                              preview: ListPreview(dragSource: "holding",
                                                   dropTarget: DropTarget(placement: .onto(id: "A"))))
        let d = diff(raster(vetoedLift), raster(control))
        XCTAssertEqual(d.count, 0,
                       "a frozen lift on a vetoed row must draw NOTHING of the drag — no ghost, no dim, no target")
    }

    func testSameFrozenLiftDrawsWhenNotVetoed() {
        let control = list(preview: ListPreview())
        let lift = list(preview: ListPreview(dragSource: "holding",
                                             dropTarget: DropTarget(placement: .onto(id: "A"))))
        let d = diff(raster(lift), raster(control), matches: theme.primary)
        XCTAssertGreaterThan(d.count, 0, "the reference lift must actually draw (else the veto test proves nothing)")
        XCTAssertTrue(d.hitsColor, "the un-vetoed lift must paint the `primary` target affordance")
    }

    /// A chunk-only preview names no source, so there is nothing to judge —
    /// the existing bench cells that freeze `dragChunk` alone keep rendering.
    func testChunkOnlyPreviewPassesTheGate() {
        let control = list(veto: ["holding"], preview: ListPreview())
        let chunk = list(veto: ["holding"], preview: ListPreview(dragChunk: ["A", "free", "holding"]))
        let d = diff(raster(chunk), raster(control))
        XCTAssertGreaterThan(d.count, 0, "a chunk-only preview must still dim its members + show the ghost")
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
