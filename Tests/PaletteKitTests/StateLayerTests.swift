// `stateOverlay(_:on:)` / `restingStroke(of:)` / the disabled triple — the
// interaction tokens that replaced 15 hand-written literals across the widget
// kit, and the resolution of sill's disabled self-contradiction.
//
// These lock TWO different things, and the distinction matters:
//
//   1. BEHAVIOUR PRESERVATION. The refactor must be exactly what the inlined
//      literals were. Every expectation below is written as the literal the
//      widget used to contain, so if an accessor's value ever drifts the test
//      names the old number.
//   2. THE ONE DELIBERATE CHANGE. `ThemedListRow` used to resolve disabled to
//      `tertiary` while five themed controls resolved it to `muted`. That is
//      now one answer — `disabledInk` — and `testDisabledIsOneAnswer` is the
//      guard that keeps it one.
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import AppKit
@testable import Palette
@testable import PaletteKit

@MainActor
final class StateLayerTests: XCTestCase {

    /// Every FIXED preset — the system/vibrancy themes resolve their inks from
    /// the OS and have no stable value to pin.
    private var fixedThemes: [Theme] {
        Theme.allCases.filter { $0.spec.backgroundMode == .fixed }
    }

    private var pal: ResolvedPalette { resolve(Theme.dracula.spec) }

    // MARK: - The resolution table

    /// On an opaque role FILL the overlay is the contrast ink — MUI's "darker
    /// shade" as a Material-3 on-colour overlay, which is theme-robust in a way
    /// a fixed black/white wash is not.
    func testContainedOverlayIsTheContrastInk() {
        let p = pal
        let on = p.bestContrast(on: p.primary)
        XCTAssertEqual(p.stateOverlay(.pressed, on: .contrastInk(on: p.primary)),
                       on.withAlphaComponent(0.12))
        XCTAssertEqual(p.stateOverlay(.hover, on: .contrastInk(on: p.primary)),
                       on.withAlphaComponent(0.08))
    }

    /// A focused CONTAINED control shows focus through its ring and elevation,
    /// not by tinting its fill. This was the widgets' existing behaviour and is
    /// easy to "fix" by accident into a visible wash.
    func testContainedFocusPaintsNothing() {
        XCTAssertEqual(pal.stateOverlay(.focus, on: .contrastInk(on: pal.primary)), NSColor.clear)
    }

    /// On a transparent control the overlay is the role's own tint, at the
    /// alphas that are also `InkTier.subtle` / `.faint` — the equivalence
    /// ThemedButton's comments already noted ("≈ subtle tier", "≈ faint tier").
    func testTransparentOverlayIsTheRoleTint() {
        let p = pal
        XCTAssertEqual(p.stateOverlay(.pressed, on: .roleTint(p.primary)),
                       p.primary.withAlphaComponent(0.16))
        XCTAssertEqual(p.stateOverlay(.hover, on: .roleTint(p.primary)),
                       p.primary.withAlphaComponent(0.06))
        XCTAssertEqual(p.stateOverlay(.focus, on: .roleTint(p.primary)),
                       p.primary.withAlphaComponent(0.06))
    }

    /// The checkbox reached the same two values through `ink(.subtle/.faint)`.
    /// If these ever diverge, one widget's ripple silently stops matching the
    /// rest of the kit.
    func testTransparentOverlayAgreesWithTheInkTiers() {
        for theme in fixedThemes {
            let p = resolve(theme.spec)
            XCTAssertEqual(p.stateOverlay(.pressed, on: .roleTint(p.primary)),
                           p.ink(.subtle, of: .primary), "\(theme.rawValue)")
            XCTAssertEqual(p.stateOverlay(.hover, on: .roleTint(p.foreground)),
                           p.ink(.faint, of: .foreground), "\(theme.rawValue)")
        }
    }

    func testRestingStrokeIsHalfTheRole() {
        for theme in fixedThemes {
            let p = resolve(theme.spec)
            XCTAssertEqual(p.restingStroke(of: p.primary),
                           p.primary.withAlphaComponent(0.5), "\(theme.rawValue)")
        }
    }

    // MARK: - The contradiction being fixed

    /// THE point of this change. `ThemedButton`/`Chip`/`FAB`/`Checkbox`/
    /// `ButtonGroup` resolved disabled to `muted`; `ThemedListRow` resolved it
    /// to `tertiary`. Two greys for one state, visible whenever a disabled
    /// control and a disabled row share a surface.
    ///
    /// `muted` won because five of six already used it, and because `tertiary`
    /// means the third EMPHASIS tier — a different concept from unavailable.
    func testDisabledIsOneAnswer() {
        for theme in fixedThemes {
            let p = resolve(theme.spec)
            XCTAssertEqual(p.disabledInk, p.muted, "\(theme.rawValue): disabled ink is muted")
        }
    }

    /// Proves the change is REAL rather than a rename: `tertiary` and `muted`
    /// are genuinely different colours, so the list row's disabled text did
    /// move. (If this ever passes trivially, the two roles have collapsed and
    /// the fix has become vacuous.)
    func testDisabledInkActuallyDiffersFromTheOldTertiary() {
        for theme in fixedThemes {
            let p = resolve(theme.spec)
            XCTAssertNotEqual(p.disabledInk, p.tertiary,
                              "\(theme.rawValue): if these are equal the contradiction was cosmetic")
        }
    }

    /// The other two thirds of the disabled answer, pinned to what the widgets
    /// contained before the refactor.
    func testDisabledFillAndStrokeAreUnchanged() {
        for theme in fixedThemes {
            let p = resolve(theme.spec)
            XCTAssertEqual(p.disabledFill, p.ink(.subtle, of: .muted), "\(theme.rawValue)")
            XCTAssertEqual(p.disabledStroke, p.border, "\(theme.rawValue)")
        }
    }
}
