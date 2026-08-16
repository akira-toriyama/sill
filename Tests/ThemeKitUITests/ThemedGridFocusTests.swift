// The `takesKeyboardFocus` knob (t-267s): a HOST-DRIVEN grid (facet's overlay)
// must be able to opt out of the kit's focus entirely — no focus-on-click, no
// system focus ring, dormant key bindings. `.focusable(false)` carries all
// three, so what these cases pin is the SEAM's plumbing: the default stays
// focusable (shipped consumers unchanged) and the copy actually renders. The
// ring's absence is a live-window property a headless raster can't prove —
// that check rides the consumer's VM acceptance.
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
@testable import Palette
@testable import PaletteKit
@testable import ThemeKitUI

@MainActor
final class ThemedGridFocusTests: XCTestCase {

    private struct Item: Identifiable { let id: Int }
    private let theme = resolve(Theme.dracula.spec)

    private func grid(focus: Bool?) -> some View {
        var g = ThemedGridView([Item(id: 1), Item(id: 2)], id: \.id,
                               palette: theme) { item, _ in
            Text("\(item.id)")
        }
        if let focus { g = g.takesKeyboardFocus(focus) }
        return g.frame(width: 200, height: 120)
    }

    private func raster<V: View>(_ view: V) -> [UInt8] {
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 120)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("no bitmap rep"); return []
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let img = rep.cgImage, let data = img.dataProvider?.data else {
            XCTFail("no image"); return []
        }
        return [UInt8](data as Data)
    }

    /// The opt-out must not change what the unfocused grid DRAWS — it only
    /// removes focusability. Byte-identical rasters pin that the copy-method
    /// reaches the view without perturbing layout or chrome.
    func testOptOutRendersIdenticallyWhenUnfocused() {
        let a = raster(grid(focus: nil))
        let b = raster(grid(focus: false))
        XCTAssertFalse(a.isEmpty)
        XCTAssertEqual(a, b)
    }

    /// Explicitly re-enabling is the default (shipped behaviour unchanged).
    func testDefaultAndExplicitTrueAgree() {
        let a = raster(grid(focus: nil))
        let b = raster(grid(focus: true))
        XCTAssertEqual(a, b)
    }
}
