// ThemedComboBoxView (SwiftUI-native) — REAL RENDER tests.
//
// The controller behind the view (`ThemedComboBox`) keeps its own coverage in
// `ThemedComboBoxTests`; these cases prove the VIEW side of the 2026-08-02
// migration: the view is a plain SwiftUI `View` whose only AppKit is the
// floor-1 `ThemedTextField` arriving through `FieldHostProxy` (glossary §6,
// *IME-adjacent composition*), the retained controller actually ADOPTED that
// field (disclosure caret, key seams, static config all wired), and the three
// theming tiers land on it. Each case hosts in an `NSHostingView`, forces
// layout, then reaches into the produced AppKit tree — the
// `PaletteEnvironmentTests` idiom, whose combo roll-call these cases replace.
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
final class ThemedComboBoxRenderTests: XCTestCase {

    private let dracula = resolve(Theme.dracula.spec)
    private let gruvbox = resolve(Theme.gruvbox.spec)
    private let cobalt  = resolve(Theme.cobalt2.spec)

    override func setUp() {
        super.setUp()
        // A known process default, so "fell through to pal" is distinguishable
        // from "picked up the wrong theme".
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

    private func hostedField<V: View>(_ view: V) -> ThemedTextField? {
        firstSubview(host(view), of: ThemedTextField.self)
    }

    // MARK: - the migration itself (the pin swift-bite demands)

    /// The one observable this migration changes at the TYPE level: the combo
    /// view no longer bridges AppKit itself. The hosted TREE is deliberately
    /// identical before/after (same field, same wiring — that is the point of
    /// the adoption seam), so this conformance check is what pins the change —
    /// and what fails if anyone ever hands the combo its own representable
    /// again instead of routing through the floor-1 `FieldHostProxy`.
    func testTheComboViewIsNotARepresentableAnymore() {
        // Typed through Any.Type so the check happens at RUNTIME on whichever
        // tree is under test (a direct `is` here is statically known and warns).
        let viewType: Any.Type = ThemedComboBoxView.self
        XCTAssertFalse(viewType is any NSViewRepresentable.Type,
                       "floor 1 covers the edit core, not view-layer bridging (glossary §6)")
    }

    // MARK: - the adoption wiring (the field is real AND controller-owned)

    func testTheFloorOneFieldIsHostedAndAdoptedByTheController() {
        guard let f = hostedField(ThemedComboBoxView(options: ["Apple", "Banana"])) else {
            XCTFail("no ThemedTextField under the combo view"); return
        }
        // The controller's `configureField` ran on THIS field: the disclosure
        // caret and every key seam are the combo's, not the bare field's nils.
        XCTAssertEqual(f.trailingSymbol, "caret-down",
                       "the disclosure caret proves the controller adopted the hosted field")
        XCTAssertNotNil(f.onChange, "type-to-filter is wired")
        XCTAssertNotNil(f.onReturn, "commit is wired")
        XCTAssertNotNil(f.onEscape, "close is wired")
        XCTAssertNotNil(f.onMoveUp, "arrow nav is wired")
        // Windowless, so no popup can open — but the combo still CONSUMES the
        // arrow (suppressing caret movement), which only the controller does.
        XCTAssertEqual(f.onMoveDown?(), true,
                       "ArrowDown is consumed by the adopted controller")
    }

    func testStaticConfigLandsOnTheHostedField() {
        let f = hostedField(ThemedComboBoxView(options: ["A"], label: "Fruit",
                                               placeholder: "type to filter…",
                                               leading: "tag"))
        XCTAssertEqual(f?.label, "Fruit")
        XCTAssertEqual(f?.placeholder, "type to filter…")
        XCTAssertEqual(f?.leadingSymbol, "tag")
    }

    // MARK: - the three theming tiers (replacing the PaletteEnvironmentTests
    // roll-call, spent by this migration)

    func testFallsBackToTheProcessDefault() {
        XCTAssertEqual(hostedField(ThemedComboBoxView(options: ["A", "B"]))?.palette,
                       cobalt, "no explicit argument and no ancestor theme ⇒ pal")
    }

    func testAmbientThemeBeatsTheProcessDefault() {
        XCTAssertEqual(hostedField(ThemedComboBoxView(options: ["A", "B"])
                                    .sillTheme(dracula))?.palette,
                       dracula)
    }

    func testExplicitArgumentBeatsTheAmbientTheme() {
        XCTAssertEqual(hostedField(ThemedComboBoxView(palette: gruvbox, options: ["A", "B"])
                                    .sillTheme(dracula))?.palette,
                       gruvbox)
    }
}
