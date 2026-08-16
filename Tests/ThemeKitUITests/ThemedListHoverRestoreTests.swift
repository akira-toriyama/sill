// The hover restoration seams (t-ak5e, sill side):
//
//   1. `showsHoverFill`  — paint `hover` under ANY enabled hovered `.row`,
//                          not only a selected wash (the old facet tree lit
//                          every window row). A row already drawing a
//                          selection/highlight fill must render BYTE-IDENTICAL
//                          with the flag on or off.
//   2. header hover REPORT — `handleHover` used to gate report+veil+follow
//                          behind one `guard case .row`, so a standalone list
//                          could never report a header hover while the hosted
//                          path reports every kind. The report now covers
//                          headers; the veil and the menu-follow stay row-only.
//   3. pointer affordances — rows vend the link pointer, draggable headers
//                          the grab pointer (`ListPointerAffordance`), nothing
//                          for disabled rows/separators, all behind
//                          `showsPointerAffordances`.
//
// Logic drives the same `package` seams the live view uses (`handleHover`,
// `pointerAffordance(for:)`); the render half rasterises via `NSHostingView` +
// `cacheDisplay` like FreezeSeamRenderTests. String ids on purpose (t-8xqf).
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
final class ThemedListHoverRestoreTests: XCTestCase {

    private let theme = resolve(Theme.dracula.spec)

    private func rows() -> [ListItem<String>] {
        [ListItem<String>(id: "H", primary: "H", kind: .sectionHeader(subtitle: "sub")),
         ListItem<String>(id: "a", primary: "a"),
         ListItem<String>(id: "b", primary: "b"),
         ListItem<String>(id: "off", primary: "off", isDisabled: true),
         ListItem<String>(id: "sep", primary: "", kind: .separator)]
    }

    private func item(_ id: String) -> ListItem<String> {
        rows().first { $0.id == id }!
    }

    // MARK: 2 — the hover REPORT covers headers (standalone parity with hosted)

    func testHoverReportCoversRowsAndHeaders() {
        var seen: [String?] = []
        let v = ThemedListView<String>(items: rows(), style: ThemedListStyle(), palette: theme,
                                       onHover: { seen.append($0) })
        v.handleHover(item("a"), true)
        v.handleHover(item("H"), true)
        XCTAssertEqual(seen, ["a", "H"],
                       "a header hover must reach onHover — the hosted path always reported it")
    }

    func testHoverReportSkipsDisabledAndSeparators() {
        var seen: [String?] = []
        let v = ThemedListView<String>(items: rows(), style: ThemedListStyle(), palette: theme,
                                       onHover: { seen.append($0) })
        v.handleHover(item("off"), true)
        v.handleHover(item("sep"), true)
        XCTAssertTrue(seen.isEmpty, "disabled rows and separators must stay silent")
    }

    /// The menu-model follow must NOT move the cursor onto a header: hover
    /// reporting widened, the follow's row-only rule did not.
    func testHighlightFollowsHoverIgnoresHeaders() {
        var style = ThemedListStyle()
        style.highlightFollowsHover = true
        var highlight: String? = nil
        let binding = Binding<String?>(get: { highlight }, set: { highlight = $0 })
        let v = ThemedListView<String>(items: rows(), highlight: binding, style: style, palette: theme)
        v.handleHover(item("H"), true)
        XCTAssertNil(highlight, "a header hover must not drag the menu cursor onto the header")
        v.handleHover(item("a"), true)
        XCTAssertEqual(highlight, "a")
    }

    // MARK: 3 — pointer affordances

    func testPointerAffordancesDefaultOff() {
        let v = ThemedListView<String>(items: rows(), style: ThemedListStyle(), palette: theme)
        XCTAssertNil(v.pointerAffordance(for: item("a")))
        XCTAssertNil(v.pointerAffordance(for: item("H")))
    }

    func testPointerAffordanceMapping() {
        var style = ThemedListStyle()
        style.showsPointerAffordances = true
        let plain = ThemedListView<String>(items: rows(), style: style, palette: theme)
        XCTAssertEqual(plain.pointerAffordance(for: item("a")), .link)
        XCTAssertEqual(plain.pointerAffordance(for: item("H")), .link,
                       "a non-draggable header is a click target, not a drag handle")
        XCTAssertNil(plain.pointerAffordance(for: item("off")))
        XCTAssertNil(plain.pointerAffordance(for: item("sep")))

        style.draggable = true
        let draggable = ThemedListView<String>(items: rows(), style: style, palette: theme)
        XCTAssertEqual(draggable.pointerAffordance(for: item("H")), .grab,
                       "a draggable header is the chunk drag-handle — the grip's cursor twin")
        XCTAssertEqual(draggable.pointerAffordance(for: item("a")), .link)
    }

    // MARK: 1 — showsHoverFill (render)

    private func list(_ configure: (inout ThemedListStyle) -> Void = { _ in },
                      preview: ListPreview<String>) -> ThemedListView<String> {
        var style = ThemedListStyle()
        style.selectionMode = .single
        configure(&style)
        return ThemedListView<String>(items: rows(), style: style, palette: theme, preview: preview)
    }

    func testHoverFillLightsAnUnselectedRow() {
        let base = raster(list(preview: ListPreview(selection: ["a"])))
        let off = raster(list(preview: ListPreview(selection: ["a"]).hovering("b")))
        let on = raster(list({ $0.showsHoverFill = true },
                             preview: ListPreview(selection: ["a"]).hovering("b")))
        XCTAssertEqual(diff(off, base).count, 0,
                       "default: hovering an unselected row must draw nothing (the menu reading)")
        // `hover` is translucent on most presets — what lands on screen is the
        // role FLATTENED over the surface, so that composite is what the pixels
        // are matched against (the same resolve `ThemedListRow` uses for ink).
        let flat = theme.flatten(theme.hover, over: theme.background ?? .windowBackgroundColor)
        let d = diff(on, base, matches: flat)
        XCTAssertGreaterThan(d.count, 0, "showsHoverFill must light the hovered row")
        XCTAssertTrue(d.hitsColor, "the hover fill must paint in `hover` (flattened over the surface)")
    }

    /// A selected row keeps its wash+veil pixels exactly — the flag adds a
    /// layer only where no fill owns the row.
    func testHoverFillLeavesSelectedRowsByteIdentical() {
        let off = raster(list(preview: ListPreview(selection: ["a"]).hovering("a")))
        let on = raster(list({ $0.showsHoverFill = true },
                             preview: ListPreview(selection: ["a"]).hovering("a")))
        XCTAssertEqual(diff(on, off).count, 0)
    }

    func testHoverFillIgnoresDisabledRows() {
        let off = raster(list({ $0.showsHoverFill = true }, preview: ListPreview()))
        let hoveredOff = raster(list({ $0.showsHoverFill = true },
                                     preview: ListPreview().hovering("off")))
        XCTAssertEqual(diff(hoveredOff, off).count, 0, "a disabled row must not light")
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
