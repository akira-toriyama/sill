// The keyboard cursor ring is drawn wherever the cursor can BE — the guard on
// the regression where a `.row`-only ring made the cursor invisible on section
// headers: it seeds on the first row (a header whenever the list has sections),
// a section jump parks on an empty group's header, and arrows walk through
// headers — so the cursor vanished mid-walk while Enter still acted on the
// invisible row (facet #448).
//
// These cases rasterise and compare, because "the ring is drawn" is a claim
// about pixels and XCTest proves logic, not SwiftUI render. Hosted in an
// `NSHostingView` — `ImageRenderer` draws nothing inside this widget's
// `ScrollView`/`LazyVStack` (measured in #175).
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
@testable import Palette
@testable import PaletteKit
@testable import ThemeKitUI

@MainActor
final class ThemedListCursorRingTests: XCTestCase {

    private let theme = resolve(Theme.dracula.spec)
    private let width: CGFloat = 300
    private let height: CGFloat = 260

    /// header(0) + three rows + a separator + a row — every cursor-stop kind.
    private var items: [ListItem<Int>] {
        [ListItem(id: 0, primary: "section", kind: .sectionHeader(subtitle: nil)),
         ListItem(id: 1, primary: "row one"),
         ListItem(id: 2, primary: "row two"),
         ListItem(id: 3, primary: "row three"),
         ListItem(id: 4, primary: "", kind: .separator),
         ListItem(id: 5, primary: "row four")]
    }

    private func render(highlight: Int?) -> (px: [UInt8], w: Int, h: Int) {
        var style = ThemedListStyle()
        style.highlightStyle = .outline
        let view = ThemedListView<Int>(items: items,
                                       highlight: .constant(highlight),
                                       style: style,
                                       palette: theme)
            .frame(width: width, height: height)
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        _ = host.fittingSize
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("no bitmap rep for the hosted list"); return ([], 0, 0)
        }
        host.cacheDisplay(in: host.bounds, to: rep)
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

    /// How many pixels differ between the two rasters on scanline `y` (points).
    private func differing(_ a: (px: [UInt8], w: Int, h: Int),
                           _ b: (px: [UInt8], w: Int, h: Int),
                           atPointRow y: CGFloat) -> Int {
        let scale = max(1, a.w / Int(width))
        let row = Int(y) * scale
        var n = 0
        for x in 0..<a.w {
            let i = (row * a.w + x) * 4
            if a.px[i] != b.px[i] || a.px[i+1] != b.px[i+1]
                || a.px[i+2] != b.px[i+2] || a.px[i+3] != b.px[i+3] { n += 1 }
        }
        return n
    }

    func testCursorRingIsVisibleOnASectionHeader() {
        let m = ListMetrics.forDensity(.comfortable)
        let plain = render(highlight: nil)
        let onHeader = render(highlight: 0)
        XCTAssertTrue(differing(plain, onHeader, atPointRow: m.header1 / 2) > 0,
                      "parking the cursor on a section header must draw the ring — "
                      + "an invisible cursor mid-walk is the shipped regression")
    }

    func testCursorRingStillDrawsOnAPlainRow() {
        let m = ListMetrics.forDensity(.comfortable)
        let plain = render(highlight: nil)
        let onRow = render(highlight: 1)
        XCTAssertTrue(differing(plain, onRow, atPointRow: m.header1 + m.singleRow / 2) > 0,
                      "widening the ring to headers must not lose it on rows")
    }
}
