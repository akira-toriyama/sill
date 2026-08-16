// The `cyclesColors` knob (t-267s): a NON-`cycles` effect either loops its
// colour through its own flash palette (`true`, the shipped default) or rests
// on its STEADY hue (`false` — facet's `[border]` contract, where colour
// cycling is an explicit opt-in). Pinned at the RENDER level so the knob is
// proven to reach `resolveBorder`, not just to exist as a property:
//   (a) cyclesColors=false ⇒ frozen frames at two different phases are
//       byte-identical (the colour no longer depends on the phase);
//   (b) cyclesColors=true  ⇒ the same two phases differ (the cycle blend);
//   (c) the default is true (the pre-knob behaviour, unchanged consumers).
// Width is pinned (`breathTo == lineWidth`) so the phase can only ever show
// through the COLOUR — a breathing width would make (b) pass for the wrong
// reason and (a) fail for no colour reason at all.
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
@testable import Palette
@testable import PaletteKit
@testable import Effects
@testable import ThemeKitUI

@MainActor
final class AnimatedBorderCycleColorsTests: XCTestCase {

    private let theme = resolve(Theme.dracula.spec)
    private let side: CGFloat = 120

    /// A frozen border at `phase`, width pinned, bloom off (a flat stroke keeps
    /// the differing pixels on the rim itself).
    private func border(phase: CGFloat, cycles: Bool) -> AnimatedBorderView<RoundedRectangle> {
        var v = AnimatedBorderView(
            palette: theme,
            effect: .neon,                 // non-`cycles`, flash palette non-empty
            effectsEnabled: true,
            lineWidth: 3,
            breathTo: 3,                   // no breathing — colour is the only variable
            glow: .none,
            previewFrozen: true,
            previewPhase: phase)
        v.cyclesColors = cycles
        return v
    }

    private func raster<V: View>(_ view: V) -> [UInt8] {
        let host = NSHostingView(rootView: AnyView(view.frame(width: side, height: side)))
        host.frame = NSRect(x: 0, y: 0, width: side, height: side)
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

    func testSteadyColourIsPhaseIndependent() {
        let a = raster(border(phase: 0.2, cycles: false))
        let b = raster(border(phase: 0.7, cycles: false))
        XCTAssertFalse(a.isEmpty)
        XCTAssertEqual(a, b, "cyclesColors=false must rest on the steady hue — the phase leaked into the colour")
    }

    func testCyclingColourFollowsThePhase() {
        let a = raster(border(phase: 0.2, cycles: true))
        let b = raster(border(phase: 0.7, cycles: true))
        XCTAssertFalse(a.isEmpty)
        XCTAssertNotEqual(a, b, "cyclesColors=true must blend through the flash palette across phases")
    }

    func testDefaultStaysCycling() {
        XCTAssertTrue(AnimatedBorderView(palette: theme).cyclesColors,
                      "the default must keep the shipped continuously-cycling rim")
    }
}
