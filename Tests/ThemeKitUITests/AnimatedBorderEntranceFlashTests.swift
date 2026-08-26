// The entrance flash (t-e2bn). A host may bump its flash token in the SAME
// turn it creates the view (facet applies config + flashBorder together), so
// the border is BORN with a non-zero token — a change-only `onChange` never
// rolled that burst and grid/rail lost their entrance flash in the migration
// (the old AppKit BorderFX.flash was imperative and fired regardless). The fix
// pre-rolls the burst in `init` as the flash state's INITIAL value at epoch 0
// (an `onChange(initial:)` roll at attach is dropped — the `@State` write
// lands before storage installs; measured in the CLT dry-run of this file).
//
// Pinned at the RENDER level with `previewFrozen` — the frozen sample clock is
// `previewPhase × cycleSeconds`, a FIXED instant, so capture timing cannot race
// the ~167 ms burst. The entrance burst's epoch is exactly 0 (birth), so a
// sample at 0.12 s sits inside the [0, 5/30 s) burst deterministically; only
// (c)'s AFTER-birth roll is wall-clock-stamped, and it aims its own sample.
//   (a) born with token=1 ⇒ the frame shows the burst: differs from the token=0
//       twin (the flash's +1.5 width bump guarantees a pixel diff even if the
//       random blink colour lands near the steady hue);
//   (b) born with token=0 ⇒ NO spurious entrance roll: byte-identical to a
//       flash-less spec (a rolled burst would fatten the stroke);
//   (c) a bump AFTER birth still rolls (the pre-fix path stays alive).
// `cyclesColors = false` throughout so the resting colour is the phase-free
// steady hue — the cycle blend reads the flash PALETTE, which differs between
// (b)'s two specs. Width is pinned (`breathTo == lineWidth`) so the flash's
// width bump is the only width signal.
//
// (CI-first on a CLT-only machine — written WITHOUT @testable so the CLT
// dry-run derivation stays purely mechanical, as PreviewSeamFrontTests.)
import XCTest
import SwiftUI
import AppKit
import Palette
import PaletteKit
import Effects
import ThemeKitUI

@MainActor
final class AnimatedBorderEntranceFlashTests: XCTestCase {

    private let theme = resolve(Theme.dracula.spec)
    private let side: CGFloat = 120

    /// A frozen border sampling its clock at `sampleAt` seconds after birth.
    /// `cycleSeconds = 10` keeps `previewPhase` a small clean fraction.
    private func border(token: Int, effect: EffectSpec = .neon,
                        sampleAt: Double = 0.12) -> AnimatedBorderView<RoundedRectangle> {
        var v = AnimatedBorderView(
            palette: theme,
            effect: effect,
            effectsEnabled: true,
            lineWidth: 3,
            breathTo: 3,                   // no breathing — flash +1.5 is the width signal
            cycleSeconds: 10,
            glow: .none,
            flashToken: token,
            previewFrozen: true,
            previewPhase: CGFloat(sampleAt / 10))
        v.cyclesColors = false             // steady hue — phase-free resting colour
        return v
    }

    /// Host in a real (borderless, unordered) window so appearance-driven
    /// wiring (`onChange(initial:)`) runs, exactly as it does in an app.
    private func host<V: View>(_ view: V) -> (NSWindow, NSHostingView<AnyView>) {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: AnyView(view.frame(width: side, height: side)))
        hosting.frame = NSRect(x: 0, y: 0, width: side, height: side)
        win.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (win, hosting)
    }

    /// Spin the main runloop so the appearance roll's `@State` write commits
    /// and the frozen canvas re-renders (its sample instant does not move).
    private func pump(_ seconds: TimeInterval = 0.2) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func snapshot(_ host: NSHostingView<AnyView>) -> [UInt8] {
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

    private func raster<V: View>(_ view: V) -> [UInt8] {
        let (win, hosting) = host(view)
        defer { win.orderOut(nil) }
        pump()
        return snapshot(hosting)
    }

    func testBornWithNonZeroTokenRollsTheEntranceFlash() {
        let flashed = raster(border(token: 1))
        let calm = raster(border(token: 0))
        XCTAssertFalse(flashed.isEmpty)
        XCTAssertNotEqual(flashed, calm,
                          "a view born with a non-zero flashToken must roll its entrance burst")
    }

    func testBornWithZeroTokenStaysCalm() {
        let couldFlash = raster(border(token: 0))
        let cannotFlash = raster(border(token: 0,
                                        effect: EffectSpec(steady: EffectSpec.neon.steady, flash: [])))
        XCTAssertFalse(couldFlash.isEmpty)
        XCTAssertEqual(couldFlash, cannotFlash,
                       "token 0 means never-flashed — no spurious entrance roll")
    }

    /// A live border whose clock races for real — the cold-summon pin needs
    /// the attach re-anchor, which the frozen clock deliberately ignores.
    private func liveBorder(token: Int) -> AnimatedBorderView<RoundedRectangle> {
        var v = AnimatedBorderView(
            palette: theme,
            effect: .neon,
            effectsEnabled: true,
            lineWidth: 3,
            breathTo: 3,                   // no breathing — flash +1.5 is the width signal
            cycleSeconds: 10,
            glow: .none,
            flashToken: token)
        v.cyclesColors = false             // steady hue — phase-free resting colour
        return v
    }

    // bite-exempt: discriminates only where the live TimelineView clock runs.
    // Measured on the dev machine's CLT dry-run: red against the pre-fix
    // source, green with the fix. The hosted runner renders the two twins
    // identically either way (its display pipeline does not advance the live
    // clock the same), so against the pre-fix source this test cannot fail
    // there — the local dry-run is where this pin bites.
    func testEntranceFlashSurvivesASlowAttach() {
        // Cold summon (t-5hx8): the host builds the view, then spends longer
        // than the whole ~167 ms burst before the first composited frame.
        // Anchored at struct init the entrance pre-roll expires invisibly;
        // anchored at attach it plays. LIVE views on purpose — the frozen
        // clock ignores the anchor — so the capture races the real burst; a
        // runner hiccup longer than the burst between attach and snapshot
        // blanks an attempt, so retry and pass on any observed difference.
        var sawFlash = false
        for _ in 1...3 where !sawFlash {
            let flashed = liveBorder(token: 1)
            let calm = liveBorder(token: 0)
            Thread.sleep(forTimeInterval: 0.25)      // the cold gap: > the burst

            let (winF, hostF) = host(flashed)
            pump(0.04)
            let flashedPixels = snapshot(hostF)
            winF.orderOut(nil)

            let (winC, hostC) = host(calm)
            pump(0.04)
            let calmPixels = snapshot(hostC)
            winC.orderOut(nil)

            sawFlash = !flashedPixels.isEmpty && flashedPixels != calmPixels
        }
        XCTAssertTrue(sawFlash,
                      "an entrance burst must survive a cold summon that outlives it before attach")
    }

    func testBumpAfterBirthStillRolls() {
        let birth = Date()                 // ≈ the view's own @State birth stamp
        let (win, hosting) = host(border(token: 0))
        defer { win.orderOut(nil) }
        pump()
        let before = snapshot(hosting)

        // Roll happens NOW — aim the frozen sample instant just past the roll's
        // own stamp (elapsed at the swap + slack inside the 167 ms burst).
        let elapsed = Date().timeIntervalSince(birth)
        hosting.rootView = AnyView(border(token: 1, sampleAt: elapsed + 0.05)
            .frame(width: side, height: side))
        pump()
        let after = snapshot(hosting)

        XCTAssertFalse(before.isEmpty)
        XCTAssertNotEqual(before, after,
                          "bumping flashToken after birth must still roll the burst")
    }
}
