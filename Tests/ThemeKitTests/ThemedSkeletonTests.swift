// ThemeKit / ThemedSkeleton tests — DETERMINISTIC in headless CI (no Xcode
// locally → these first run in CI). The ambient pulse/wave only runs in a
// visible key window (which is flaky headless — see the Phase 0 learning), so
// these tests assert the GATED-OFF states, which ARE deterministic: frozen,
// animation == .none, no window, and the reduce-motion invariant — plus the
// static facts (tint role/alpha, theme re-tint, per-variant corner, text
// line-height). The live pulse/wave + the off-screen-teardown CPU drop are
// proven LIVE in still, not here.

import XCTest
import AppKit
import Palette
import PaletteKit
@testable import ThemeKit   // for the DEBUG `skeletonProbe`

@MainActor
final class ThemedSkeletonTests: XCTestCase {

    private func palette() -> ResolvedPalette { resolve(.terminal) }

    /// CGColor identity is fragile across `resolve()` calls / colour-space
    /// conversions, so compare resolved sRGB components (incl. alpha) within tol.
    private func sameColor(_ a: CGColor?, _ b: NSColor, accuracy: CGFloat = 0.002,
                           _ msg: String = "", file: StaticString = #filePath,
                           line: UInt = #line) {
        guard let a, let an = NSColor(cgColor: a)?.usingColorSpace(.sRGB),
              let bn = b.usingColorSpace(.sRGB) else {
            return XCTFail("colour unconvertible: \(msg)", file: file, line: line)
        }
        XCTAssertEqual(an.redComponent,   bn.redComponent,   accuracy: accuracy, msg, file: file, line: line)
        XCTAssertEqual(an.greenComponent, bn.greenComponent, accuracy: accuracy, msg, file: file, line: line)
        XCTAssertEqual(an.blueComponent,  bn.blueComponent,  accuracy: accuracy, msg, file: file, line: line)
        XCTAssertEqual(an.alphaComponent, bn.alphaComponent, accuracy: accuracy, msg, file: file, line: line)
    }

    private func laidOut(_ configure: (ThemedSkeleton) -> Void = { _ in },
                         width: CGFloat = 180, height: CGFloat = 40) -> ThemedSkeleton {
        let s = ThemedSkeleton(palette: palette())
        configure(s)
        s.frame = NSRect(x: 0, y: 0, width: width, height: height)
        s.layoutSubtreeIfNeeded()
        return s
    }

    /// `previewFrozen` holds a deterministic mid-cycle phase WITHOUT a running
    /// animation — the guarantee that makes a still screencapture reproducible.
    func testPreviewFrozenHoldsPhaseAndDoesNotAnimate() {
        let s = laidOut { $0.previewFrozen = true }
        XCTAssertTrue(s.skeletonProbe.frozen)
        XCTAssertEqual(s.skeletonProbe.phase, 0.5, accuracy: 0.0001, "frozen phase is mid-cycle")
        XCTAssertFalse(s.skeletonProbe.isAnimating, "frozen never attaches a live animation")
    }

    /// `animation == .none` never attaches an animation, regardless of window.
    func testAnimationNoneNeverAnimates() {
        let s = laidOut { $0.animation = .none }
        XCTAssertFalse(s.skeletonProbe.isAnimating)
    }

    /// An animated skeleton that never gained a (visible) window must not be
    /// animating — the off-screen-teardown gate (motion starts only with a
    /// visible window).
    func testNoAnimationWhenWindowless() {
        let s = ThemedSkeleton(palette: palette())
        s.animation = .pulse
        XCTAssertFalse(s.skeletonProbe.isAnimating,
                       "a windowless skeleton stays static until it has a visible window")
    }

    /// The wash is `muted` at the `.subtle` alpha tier (≈0.16) — a faint, low-
    /// contrast placeholder, not `primary`.
    func testTintIsMutedSubtleTier() {
        let p = palette()
        let s = ThemedSkeleton(palette: p)
        sameColor(s.skeletonProbe.tintColor, p.ink(.subtle, of: .muted),
                  "fill is muted @ .subtle alpha")
    }

    /// A theme switch RE-TINTS the wash immediately (snap on its own keypath, so
    /// a running animation is undisturbed) — the regression applyTheme guards.
    func testThemeSwitchRetintsFill() {
        let s = laidOut()
        let dracula = resolve(.dracula)
        s.palette = dracula
        sameColor(s.skeletonProbe.tintColor, dracula.ink(.subtle, of: .muted),
                  "fill re-tints to the new theme on palette assign")
    }

    /// Corner radius per variant: sharp rectangle, soft rounded/text, full pill
    /// circle (= min(w,h)/2 at the laid-out size).
    func testCornerRadiusPerVariant() {
        XCTAssertEqual(laidOut({ $0.variant = .rectangular }, width: 40, height: 40)
                        .skeletonProbe.cornerRadius, 0, accuracy: 0.01)
        XCTAssertEqual(laidOut({ $0.variant = .rounded }, width: 40, height: 40)
                        .skeletonProbe.cornerRadius, 4, accuracy: 0.01)
        XCTAssertEqual(laidOut({ $0.variant = .text }, width: 40, height: 40)
                        .skeletonProbe.cornerRadius, 4, accuracy: 0.01)
        XCTAssertEqual(laidOut({ $0.variant = .circular }, width: 40, height: 40)
                        .skeletonProbe.cornerRadius, 20, accuracy: 0.01, "circular = min(w,h)/2")
    }

    /// `.text` derives its height from the themed font line (a squashed bar),
    /// and spans the explicit width.
    func testTextVariantIntrinsicHeightFromFont() {
        let s = ThemedSkeleton(palette: palette())
        s.variant = .text
        s.width = 180
        // Upper bound = a full line box of either candidate face at 13 pt.
        let fullLine = ceil(max(NSFont.systemFont(ofSize: 13).boundingRectForFont.height,
                                NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                                    .boundingRectForFont.height))
        XCTAssertEqual(s.intrinsicContentSize.width, 180, "spans the explicit width")
        XCTAssertGreaterThan(s.intrinsicContentSize.height, 0)
        XCTAssertLessThan(s.intrinsicContentSize.height, fullLine,
                          "text bar is a squashed fraction of the line box")
    }

    /// Circular derives a square diameter from height-or-width.
    func testCircularIsSquareFromHeight() {
        let s = ThemedSkeleton(palette: palette())
        s.variant = .circular
        s.height = 40
        XCTAssertEqual(s.intrinsicContentSize.width, 40)
        XCTAssertEqual(s.intrinsicContentSize.height, 40, "circular is square")
    }

    /// Probe invariant: never animating while reduce-motion is on. With
    /// `previewFrozen` forcing no animation, the invariant holds regardless of
    /// the CI machine's accessibility setting (we never toggle the OS setting).
    func testReduceMotionRespectedInvariant() {
        let s = laidOut { $0.previewFrozen = true }
        XCTAssertTrue(s.skeletonProbe.reduceMotionRespected)
    }

    /// A loading placeholder is AX-ignored (the host announces "Loading").
    func testAccessibilityIgnored() {
        XCTAssertFalse(ThemedSkeleton(palette: palette()).isAccessibilityElement())
    }

    /// The wave highlight rests OFF the left edge (phase 0) when not animating
    /// and not frozen — so a reduce-motion / off-screen skeleton shows a calm
    /// uniform wash, NOT a highlight band parked in the centre. `previewFrozen`
    /// is the one case that parks it centre (for a deterministic capture).
    func testWaveRestsOffscreenUnlessFrozen() {
        let resting = laidOut { $0.animation = .wave }   // windowless ⇒ not animating
        XCTAssertEqual(resting.skeletonProbe.wavePositionX, -resting.bounds.width / 2,
                       accuracy: 0.5, "non-frozen wave rests off the left edge (no centre band)")

        let frozen = laidOut { $0.animation = .wave; $0.previewFrozen = true }
        XCTAssertEqual(frozen.skeletonProbe.wavePositionX, frozen.bounds.width / 2,
                       accuracy: 0.5, "frozen wave parks the highlight centre for capture")
    }
}
