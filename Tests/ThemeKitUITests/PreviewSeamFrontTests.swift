// The t-avbj remaining slice — the popup family's preview seams surfaced on the
// SwiftUI front, and the REAL in-window bench content that replaced the
// hand-copied mocks.
//
// Two claims are pinned here:
//   (a) the front seams PASS THROUGH: `.previewOpen(_:)` on `ThemedComboBoxView`
//       and `previewVisible:` on `.themedTooltip` reach their controllers and
//       present the child-window panel — INCLUDING when the flag is set before
//       the hosting view ever lands in a window (the window-attach re-drive in
//       FieldHostProxy / PopupAnchorProxy; without it the first assertion here
//       deadlocks at "never presented", which is exactly the bug it guards).
//   (b) `ThemedTooltip.previewBubble` — the in-window bench surface — draws
//       deterministically (two rasters byte-identical), carries the inverted
//       fill, and actually changes with placement (the arrow edge moves).
//
// (CI-first on a CLT-only machine — but written WITHOUT @testable on purpose:
// the whole body compiles as a plain same-package executable, so the CLT
// dry-run derivation (strip XCTest, shim the asserts) stays purely mechanical.)
import XCTest
import SwiftUI
import AppKit
import Palette
import PaletteKit
import ThemeKitUI

@MainActor
final class PreviewSeamFrontTests: XCTestCase {

    private let theme = resolve(Theme.dracula.spec)

    /// Spin the main runloop so SwiftUI performs makeNSView/updateNSView and
    /// the popup fades (dismiss paths animate ~0.16 s) settle.
    private func pump(_ seconds: TimeInterval = 0.2) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// Host a SwiftUI root in a real (borderless, unordered) window — the field
    /// gets a window, so the popup can place itself against it.
    private func host<V: View>(_ view: V) -> (NSWindow, NSHostingView<AnyView>) {
        let win = NSWindow(contentRect: NSRect(x: 200, y: 400, width: 320, height: 120),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: AnyView(view.padding(20)))
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        win.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (win, hosting)
    }

    /// The popup family's `PopupPanel` is internal to ThemeKitUI — matched by
    /// class name so this file needs no `@testable` (see the header note).
    private func visiblePanels() -> [NSWindow] {
        NSApp.windows.filter { String(describing: type(of: $0)) == "PopupPanel" && $0.isVisible }
    }

    // MARK: - (a) combo front seam

    func testComboPreviewOpenOnFrontPresentsAndDismissesThePopup() {
        let before = visiblePanels().count
        let combo = ThemedComboBoxView(palette: theme,
                                       options: ["Apple", "Apricot", "Banana"],
                                       label: "Fruit")
        // The flag is set BEFORE the view has a window — the window-attach
        // re-drive must not lose it.
        let (win, hosting) = host(combo.previewOpen(true).previewHighlight(1))
        defer { win.orderOut(nil) }
        pump()
        XCTAssertEqual(visiblePanels().count, before + 1,
                       "previewOpen(true) on the SwiftUI front must present the popup panel")

        hosting.rootView = AnyView(combo.previewOpen(false).padding(20))
        pump(0.5)                                     // dismiss is animated:false, but be lenient
        XCTAssertEqual(visiblePanels().count, before,
                       "previewOpen(false) must dismiss it again")
    }

    // MARK: - (a) tooltip front seam

    func testTooltipPreviewVisibleOnFrontPresentsAndHidesTheBubble() {
        let before = visiblePanels().count
        let anchor = Color.clear.frame(width: 80, height: 24)
        let (win, hosting) = host(
            anchor.themedTooltip("A hint", palette: theme, placement: .bottom,
                                 previewVisible: true))
        defer { win.orderOut(nil) }
        pump()
        XCTAssertEqual(visiblePanels().count, before + 1,
                       "previewVisible: true on .themedTooltip must present the bubble panel")

        hosting.rootView = AnyView(
            anchor.themedTooltip("A hint", palette: theme, placement: .bottom,
                                 previewVisible: false).padding(20))
        pump(0.6)                                     // hide() fades ~0.16 s before orderOut
        XCTAssertEqual(visiblePanels().count, before,
                       "previewVisible: false must hide it again")
    }

    // MARK: - (b) previewBubble raster

    private func raster<V: View>(_ view: V, w: CGFloat = 200, h: CGFloat = 80) -> [UInt8] {
        let host = NSHostingView(rootView: AnyView(view.frame(width: w, height: h)))
        host.frame = NSRect(x: 0, y: 0, width: w, height: h)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("no bitmap rep"); return []
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let img = rep.cgImage else { XCTFail("no image"); return [] }
        var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: img.width, height: img.height,
                                bitsPerComponent: 8, bytesPerRow: img.width * 4, space: cs,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        }
        return buf
    }

    func testPreviewBubbleDrawsDeterministicallyWithTheInvertedFill() {
        let bubble = { ThemedTooltip.previewBubble(text: "Add item", palette: self.theme,
                                                   placement: .bottom) }
        let a = raster(bubble()), b = raster(bubble())
        XCTAssertFalse(a.isEmpty)
        XCTAssertEqual(a, b, "the bench surface must be deterministic — byte-identical rasters")

        // The inverted fill (foreground @ 0.92 over whatever the host draws)
        // must actually appear among the pixels.
        let f = theme.foreground.usingColorSpace(.sRGB)!
        let fr = Int(f.redComponent * 255)
        let fg = Int(f.greenComponent * 255)
        let fb = Int(f.blueComponent * 255)
        var hasFill = false
        for i in stride(from: 0, to: a.count, by: 4) where a[i + 3] > 200 {
            let dr = abs(Int(a[i]) - fr)
            let dg = abs(Int(a[i + 1]) - fg)
            let db = abs(Int(a[i + 2]) - fb)
            if dr <= 30 && dg <= 30 && db <= 30 { hasFill = true; break }
        }
        XCTAssertTrue(hasFill, "previewBubble must draw the foreground@0.92 fill")
    }

    func testPreviewBubblePlacementMovesTheArrowEdge() {
        let top = raster(ThemedTooltip.previewBubble(text: "Add item", palette: theme,
                                                     placement: .top))
        let bottom = raster(ThemedTooltip.previewBubble(text: "Add item", palette: theme,
                                                        placement: .bottom))
        XCTAssertNotEqual(top, bottom, "the arrow must sit on the anchor-facing edge")
    }
}
