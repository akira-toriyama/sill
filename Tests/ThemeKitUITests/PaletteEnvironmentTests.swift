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

    // MARK: - hosting helpers

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

    // MARK: - the three tiers

    func testFallsBackToTheProcessDefault() {
        let d = firstSubview(host(ThemedDividerView()), of: ThemedDivider.self)
        XCTAssertEqual(d?.palette, cobalt, "no explicit argument and no ancestor theme ⇒ pal")
    }

    func testAmbientThemeBeatsTheProcessDefault() {
        let d = firstSubview(host(ThemedDividerView().sillTheme(dracula)), of: ThemedDivider.self)
        XCTAssertEqual(d?.palette, dracula)
    }

    /// Tier 1 is kept deliberately: prism renders every catalog theme at once
    /// and needs per-widget override. If this ever regresses, the bench silently
    /// starts painting one theme everywhere.
    func testExplicitArgumentBeatsTheAmbientTheme() {
        let d = firstSubview(host(ThemedDividerView(palette: gruvbox).sillTheme(dracula)),
                             of: ThemedDivider.self)
        XCTAssertEqual(d?.palette, gruvbox)
    }

    func testInnerThemeOverridesOuterForItsSubtree() {
        let v = VStack { ThemedDividerView().sillTheme(gruvbox) }.sillTheme(dracula)
        XCTAssertEqual(firstSubview(host(v), of: ThemedDivider.self)?.palette, gruvbox)
    }

    func testThemeOverloadMatchesTheResolvedOverload() {
        let a = firstSubview(host(ThemedDividerView().sillTheme(Theme.dracula)), of: ThemedDivider.self)
        XCTAssertEqual(a?.palette, dracula)
    }

    // MARK: - the same contract across widget kinds

    /// Spot-checks widgets that reach AppKit by different routes — a plain
    /// bridge, a control with its own `ThemedControl` base, and the floor-1 IME
    /// field editor — so a per-widget wiring slip cannot hide behind the
    /// divider passing.
    func testEveryWidgetKindHonoursTheAmbientTheme() {
        XCTAssertEqual(
            firstSubview(host(ThemedButtonView(title: "OK").sillTheme(dracula)), of: ThemedButton.self)?.palette,
            dracula, "ThemedButtonView")
        XCTAssertEqual(
            firstSubview(host(ThemedCheckboxView(label: "x").sillTheme(dracula)), of: ThemedCheckbox.self)?.palette,
            dracula, "ThemedCheckboxView")
        XCTAssertEqual(
            firstSubview(host(ThemedTextFieldView().sillTheme(dracula)), of: ThemedTextField.self)?.palette,
            dracula, "ThemedTextFieldView")
    }

    func testEveryWidgetKindStillHonoursAnExplicitOverride() {
        XCTAssertEqual(
            firstSubview(host(ThemedButtonView(palette: gruvbox, title: "OK").sillTheme(dracula)),
                         of: ThemedButton.self)?.palette,
            gruvbox, "ThemedButtonView")
        XCTAssertEqual(
            firstSubview(host(ThemedCheckboxView(palette: gruvbox, label: "x").sillTheme(dracula)),
                         of: ThemedCheckbox.self)?.palette,
            gruvbox, "ThemedCheckboxView")
        XCTAssertEqual(
            firstSubview(host(ThemedTextFieldView(palette: gruvbox).sillTheme(dracula)),
                         of: ThemedTextField.self)?.palette,
            gruvbox, "ThemedTextFieldView")
    }

    // MARK: - the environment value itself

    func testEnvironmentDefaultsToNil() {
        XCTAssertNil(EnvironmentValues().sillPalette,
                     "nil is what tier 3 keys off — a non-nil default would hide 'nobody set a theme'")
    }
}
