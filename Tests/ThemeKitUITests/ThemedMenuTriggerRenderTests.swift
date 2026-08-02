// ThemedMenuTriggerView (SwiftUI-native) — REAL RENDER tests.
//
// The controller behind the trigger (`ThemedMenu`) keeps its own coverage in
// `ThemedMenuTests`; these cases prove the TRIGGER side of the 2026-08-02
// migration: the view produces NO AppKit control (the button is
// `ThemedButtonView`), it lays the shared `PopupAnchorNSView` under itself for
// `present(from:)`, and it draws the outlined trigger chrome through the three
// theming tiers. Rasterised via `NSHostingView` + `cacheDisplay`, NOT
// `ImageRenderer`: ImageRenderer paints an NSViewRepresentable (here the
// invisible anchor proxy in `.background`) as an OPAQUE placeholder graphic,
// which bleeds through the outlined button's clear fill (measured 2026-08-02) —
// any proxy-bearing view must raster through a real hosting view.
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
@testable import Palette
@testable import PaletteKit
@testable import ThemeKitUI

@MainActor
final class ThemedMenuTriggerRenderTests: XCTestCase {

    private let dracula = resolve(Theme.dracula.spec)
    private let gruvbox = resolve(Theme.gruvbox.spec)
    private let cobalt  = resolve(Theme.cobalt2.spec)

    override func setUp() {
        super.setUp()
        setPalette(cobalt)
    }

    private let items: [ThemedMenu.MenuItem] = [
        ThemedMenu.MenuItem("New Window", shortcut: "⌘N"),
        ThemedMenu.MenuItem("Open…"),
    ]

    // MARK: - raster helpers (hosting + cacheDisplay — see header; 1x scale,
    // an offscreen view has no window to inherit a backing scale from)

    private let scale: CGFloat = 1

    private func render<V: View>(_ view: V) -> Raster {
        let h = NSHostingView(rootView: view.fixedSize())
        h.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        h.layoutSubtreeIfNeeded()
        let fit = h.fittingSize
        h.frame = NSRect(origin: .zero, size: fit)
        h.layoutSubtreeIfNeeded()
        guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else {
            XCTFail("no caching rep")
            return Raster(px: [], w: 0, h: 0)
        }
        h.cacheDisplay(in: h.bounds, to: rep)
        guard let img = rep.cgImage else {
            XCTFail("cacheDisplay produced no image")
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

    private struct Raster {
        let px: [UInt8]; let w: Int; let h: Int
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

    private func dpx(_ pt: CGFloat) -> Int { Int(pt * scale) }

    /// The outlined resting stroke: strokeBorder puts the 1 pt stroke fully
    /// inside the edge — at 1x that is the top pixel row, at centre-x.
    private func edge(_ r: Raster) -> (r: Double, g: Double, b: Double, a: Double) {
        r.at(r.w / 2, 0)
    }

    // MARK: - native-ness + the anchor plumbing

    private func firstSubview<T: NSView>(_ v: NSView, of type: T.Type) -> T? {
        if let x = v as? T { return x }
        for s in v.subviews { if let x = firstSubview(s, of: type) { return x } }
        return nil
    }

    func testTriggerIsSwiftUINativeWithAnAnchorUnderneath() {
        let h = NSHostingView(rootView:
            ThemedMenuTriggerView(palette: dracula, items: items).fixedSize())
        h.frame = NSRect(x: 0, y: 0, width: 240, height: 80)
        h.layoutSubtreeIfNeeded()
        _ = h.fittingSize
        h.layoutSubtreeIfNeeded()

        XCTAssertNil(firstSubview(h, of: NSControl.self),
                     "the trigger is ThemedButtonView (SwiftUI), not an AppKit control")
        guard let anchor = firstSubview(h, of: PopupAnchorNSView.self) else {
            XCTFail("no PopupAnchorNSView under the trigger"); return
        }
        XCTAssertGreaterThan(anchor.frame.width, 60,
                             "the anchor is coextensive with the trigger, not zero-sized")
        XCTAssertGreaterThan(anchor.frame.height, 20,
                             "…in both axes (present(from:) placement + click exemption need it)")
        XCTAssertNil(anchor.hitTest(NSPoint(x: anchor.frame.midX, y: anchor.frame.midY)),
                     "the anchor never intercepts the trigger's clicks")
    }

    // MARK: - the drawn trigger (outlined chrome, three theming tiers)

    func testTriggerDrawsTheOutlinedStroke() {
        let r = render(ThemedMenuTriggerView(palette: dracula, items: items))
        assertHue(edge(r), is: dracula.primary,
                  "the trigger rests as an outlined primary button")
    }

    func testFallsBackToTheProcessDefault() {
        assertHue(edge(render(ThemedMenuTriggerView(items: items))),
                  is: cobalt.primary, "no explicit argument and no ancestor theme ⇒ pal")
    }

    func testAmbientThemeBeatsTheProcessDefault() {
        assertHue(edge(render(ThemedMenuTriggerView(items: items).sillTheme(dracula))),
                  is: dracula.primary, "ambient .sillTheme wins over pal")
    }

    func testExplicitArgumentBeatsTheAmbientTheme() {
        assertHue(edge(render(ThemedMenuTriggerView(palette: gruvbox, items: items)
                                .sillTheme(dracula))),
                  is: gruvbox.primary, "explicit palette wins over ambient")
    }
}
