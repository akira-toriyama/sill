// Ambient theming — `.sillTheme(_:)` + `@Environment(\.sillPalette)`.
//
// These are REAL RENDER tests, not logic tests. The `??` chain they check is
// trivially correct on its own; the thing that can actually break is whether
// SwiftUI populates `@Environment` inside an `NSViewRepresentable` at the
// moment `makeNSView` runs. So each case hosts the widget in an
// `NSHostingView`, forces layout, then reaches into the produced AppKit view
// and reads the palette it was actually themed with.
//
// That distinction matters here more than usual: CLAUDE.md's standing warning
// is that XCTest proves logic and NOT SwiftUI render (#17f shipped a markdown
// table whose parser tests were green while the rows drew blank). Hosting is
// how a render claim gets evidence without a screenshot.
//
// (CI-only: XCTest needs a full Xcode.)
import XCTest
import SwiftUI
import AppKit
@testable import Palette
@testable import PaletteKit
@testable import ThemeKit
@testable import ThemeKitUI

@MainActor
final class PaletteEnvironmentTests: XCTestCase {

    private let dracula = resolve(Theme.dracula.spec)
    private let gruvbox = resolve(Theme.gruvbox.spec)
    private let cobalt  = resolve(Theme.cobalt2.spec)

    override func setUp() {
        super.setUp()
        // Tier 3 — a known process default, so "fell through to pal" is
        // distinguishable from "picked up the wrong theme".
        setPalette(cobalt)
    }

    private func host<V: View>(_ view: V) -> NSView {
        let h = NSHostingView(rootView: view)
        h.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        h.layoutSubtreeIfNeeded()
        _ = h.fittingSize
        h.layoutSubtreeIfNeeded()
        return h
    }

    private func firstSubview<T: NSView>(_ v: NSView, of type: T.Type) -> T? {
        if let x = v as? T { return x }
        for s in v.subviews { if let x = firstSubview(s, of: type) { return x } }
        return nil
    }

    /// Enough of a tool bar to produce a real `ThemedToolBar`.
    private var toolBarItems: [ThemedToolBarView.Item] {
        [.button(title: "A", symbol: nil), .divider, .button(title: "B", symbol: nil)]
    }

    // The specimen is `ThemedTextFieldView` — deliberately the FLOOR-1 widget.
    // Every previous specimen (Chip, and before it FAB and Button) had to be
    // swapped out the moment it went SwiftUI-native, and each swap risked
    // silently weakening these cases (the assertion turns nil, not wrong). The
    // IME field editor is the one bridge the AppKit-floor policy says will
    // NEVER migrate, so the rotation stops here.

    func testFallsBackToTheProcessDefault() {
        let d = firstSubview(host(ThemedTextFieldView()), of: ThemedTextField.self)
        XCTAssertEqual(d?.palette, cobalt, "no explicit argument and no ancestor theme ⇒ pal")
    }

    func testAmbientThemeBeatsTheProcessDefault() {
        let d = firstSubview(host(ThemedTextFieldView().sillTheme(dracula)), of: ThemedTextField.self)
        XCTAssertEqual(d?.palette, dracula)
    }

    /// Tier 1 is kept deliberately: prism renders every catalog theme at once
    /// and needs per-widget override. If this ever regresses, the bench silently
    /// starts painting one theme everywhere.
    func testExplicitArgumentBeatsTheAmbientTheme() {
        let d = firstSubview(host(ThemedTextFieldView(palette: gruvbox).sillTheme(dracula)),
                             of: ThemedTextField.self)
        XCTAssertEqual(d?.palette, gruvbox)
    }

    func testInnerThemeOverridesOuterForItsSubtree() {
        let v = VStack { ThemedTextFieldView().sillTheme(gruvbox) }.sillTheme(dracula)
        XCTAssertEqual(firstSubview(host(v), of: ThemedTextField.self)?.palette, gruvbox)
    }

    func testThemeOverloadMatchesTheResolvedOverload() {
        let a = firstSubview(host(ThemedTextFieldView().sillTheme(Theme.dracula)),
                             of: ThemedTextField.self)
        XCTAssertEqual(a?.palette, dracula)
    }

    /// Spot-checks the OTHER routes into AppKit — a plain bridge (the menu
    /// trigger, hosting the AppKit `ThemedButton`) and a composite bridge (the
    /// tool bar, which builds its own item views) — so a per-widget wiring slip
    /// cannot hide behind the field passing. (ThemedFABView, ThemedButtonView,
    /// ThemedChipView and ThemedButtonGroupView each held a slot here until
    /// they went SwiftUI-native; their evidence now lives in the matching
    /// Themed…RenderTests.)
    func testEveryWidgetKindHonoursTheAmbientTheme() {
        XCTAssertEqual(
            firstSubview(host(ThemedMenuTriggerView(items: []).sillTheme(dracula)), of: ThemedButton.self)?.palette,
            dracula, "ThemedMenuTriggerView")
        XCTAssertEqual(
            firstSubview(host(ThemedToolBarView(items: toolBarItems).sillTheme(dracula)),
                         of: ThemedToolBar.self)?.palette,
            dracula, "ThemedToolBarView")
    }

    func testEveryWidgetKindStillHonoursAnExplicitOverride() {
        XCTAssertEqual(
            firstSubview(host(ThemedMenuTriggerView(palette: gruvbox, items: []).sillTheme(dracula)),
                         of: ThemedButton.self)?.palette,
            gruvbox, "ThemedMenuTriggerView")
        XCTAssertEqual(
            firstSubview(host(ThemedToolBarView(palette: gruvbox, items: toolBarItems).sillTheme(dracula)),
                         of: ThemedToolBar.self)?.palette,
            gruvbox, "ThemedToolBarView")
    }

    func testEnvironmentDefaultsToNil() {
        XCTAssertNil(EnvironmentValues().sillPalette,
                     "nil is what tier 3 keys off — a non-nil default would hide 'nobody set a theme'")
    }
}
