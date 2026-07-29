// `ResolvedPalette.with(...)` — the copy-with-override that replaced two
// hand-written 14-field copies (`applying(_:)` and `ThemedToolBar
// .buttonPalette()`), plus the `Equatable` conformance it is asserted through.
//
// The point of the exhaustive per-field sweep below is not paranoia about `??`.
// It is a DRIFT GUARD: `everyFieldSpelledOut` builds a palette through the
// memberwise `init` with all fourteen labels written out, so the day a 15th
// role lands this file stops COMPILING and whoever adds the role is forced to
// extend `with(...)` and this sweep in the same change. That is the whole
// reason `with(...)` had to precede any vocabulary growth.
//
// (CI-only: XCTest needs a full Xcode, which the CommandLineTools shell this is
// authored on does not have.)
import XCTest
import AppKit
@testable import Palette
@testable import PaletteKit

@MainActor
final class ResolvedPaletteWithTests: XCTestCase {

    // Distinctive, mutually-unequal probe colours: a field that silently copied
    // from the wrong source would still compare equal against a shared grey.
    private let probe = NSColor(srgbRed: 0.13, green: 0.79, blue: 0.31, alpha: 1)

    /// EVERY field spelled out through the memberwise init — the compile-time
    /// half of the gate. Do not replace this with `resolve(...)`: a resolver
    /// call would keep compiling when a field is added, and the guard would
    /// evaporate silently.
    private func everyFieldSpelledOut() -> ResolvedPalette {
        ResolvedPalette(
            background: NSColor(srgbRed: 0.02, green: 0.02, blue: 0.04, alpha: 1),
            foreground: NSColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1),
            muted: NSColor(srgbRed: 0.55, green: 0.56, blue: 0.62, alpha: 1),
            tertiary: NSColor(srgbRed: 0.38, green: 0.39, blue: 0.44, alpha: 1),
            primary: NSColor(srgbRed: 0.23, green: 0.51, blue: 0.96, alpha: 1),
            secondary: NSColor(srgbRed: 0.74, green: 0.58, blue: 0.98, alpha: 1),
            border: NSColor(srgbRed: 0.20, green: 0.21, blue: 0.25, alpha: 1),
            hover: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1),
            selection: NSColor(srgbRed: 0.12, green: 0.28, blue: 0.52, alpha: 1),
            error: NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 1),
            font: .system,
            backgroundAlpha: 0.92,
            vibrancyMaterial: .menu,
            forceDarkAqua: false)
    }

    func testEqualsItself() {
        XCTAssertEqual(everyFieldSpelledOut(), everyFieldSpelledOut())
    }

    func testNoArgumentCopyIsUnchanged() {
        let p = everyFieldSpelledOut()
        XCTAssertEqual(p.with(), p, "with() with no arguments must be the identity")
    }

    /// For each of the 14 fields: overriding it CHANGES the palette, lands the
    /// new value on the right field, and leaves the other 13 alone (proved by
    /// overriding back to the original and recovering equality).
    func testEachFieldOverridesIndependently() {
        let p = everyFieldSpelledOut()

        XCTAssertEqual(p.with(background: .some(probe)).background, probe)
        XCTAssertNotEqual(p.with(background: .some(probe)), p)
        XCTAssertEqual(p.with(background: .some(probe)).with(background: .some(p.background)), p)

        XCTAssertEqual(p.with(foreground: probe).foreground, probe)
        XCTAssertNotEqual(p.with(foreground: probe), p)
        XCTAssertEqual(p.with(foreground: probe).with(foreground: p.foreground), p)

        XCTAssertEqual(p.with(muted: probe).muted, probe)
        XCTAssertNotEqual(p.with(muted: probe), p)
        XCTAssertEqual(p.with(muted: probe).with(muted: p.muted), p)

        XCTAssertEqual(p.with(tertiary: probe).tertiary, probe)
        XCTAssertNotEqual(p.with(tertiary: probe), p)
        XCTAssertEqual(p.with(tertiary: probe).with(tertiary: p.tertiary), p)

        XCTAssertEqual(p.with(primary: probe).primary, probe)
        XCTAssertNotEqual(p.with(primary: probe), p)
        XCTAssertEqual(p.with(primary: probe).with(primary: p.primary), p)

        XCTAssertEqual(p.with(secondary: probe).secondary, probe)
        XCTAssertNotEqual(p.with(secondary: probe), p)
        XCTAssertEqual(p.with(secondary: probe).with(secondary: p.secondary), p)

        XCTAssertEqual(p.with(border: probe).border, probe)
        XCTAssertNotEqual(p.with(border: probe), p)
        XCTAssertEqual(p.with(border: probe).with(border: p.border), p)

        XCTAssertEqual(p.with(hover: probe).hover, probe)
        XCTAssertNotEqual(p.with(hover: probe), p)
        XCTAssertEqual(p.with(hover: probe).with(hover: p.hover), p)

        XCTAssertEqual(p.with(selection: probe).selection, probe)
        XCTAssertNotEqual(p.with(selection: probe), p)
        XCTAssertEqual(p.with(selection: probe).with(selection: p.selection), p)

        XCTAssertEqual(p.with(error: probe).error, probe)
        XCTAssertNotEqual(p.with(error: probe), p)
        XCTAssertEqual(p.with(error: probe).with(error: p.error), p)

        XCTAssertEqual(p.with(font: .mono).font, .mono)
        XCTAssertNotEqual(p.with(font: .mono), p)
        XCTAssertEqual(p.with(font: .mono).with(font: p.font), p)

        XCTAssertEqual(p.with(backgroundAlpha: .some(0.5)).backgroundAlpha, 0.5)
        XCTAssertNotEqual(p.with(backgroundAlpha: .some(0.5)), p)
        XCTAssertEqual(p.with(backgroundAlpha: .some(0.5))
                        .with(backgroundAlpha: .some(p.backgroundAlpha)), p)

        XCTAssertEqual(p.with(vibrancyMaterial: .some(.sidebar)).vibrancyMaterial, .sidebar)
        XCTAssertNotEqual(p.with(vibrancyMaterial: .some(.sidebar)), p)
        XCTAssertEqual(p.with(vibrancyMaterial: .some(.sidebar))
                        .with(vibrancyMaterial: .some(p.vibrancyMaterial)), p)

        XCTAssertEqual(p.with(forceDarkAqua: true).forceDarkAqua, true)
        XCTAssertNotEqual(p.with(forceDarkAqua: true), p)
        XCTAssertEqual(p.with(forceDarkAqua: true).with(forceDarkAqua: p.forceDarkAqua), p)
    }

    /// The one genuinely subtle part of the signature. On the three
    /// already-optional fields `nil` means "leave alone" and `.some(nil)` means
    /// "clear it" — get this backwards and `with()` would wipe the background of
    /// every palette it touched.
    func testBareNilLeavesOptionalFieldsAlone() {
        let p = everyFieldSpelledOut()
        XCTAssertEqual(p.with(background: nil), p)
        XCTAssertEqual(p.with(backgroundAlpha: nil), p)
        XCTAssertEqual(p.with(vibrancyMaterial: nil), p)
    }

    func testSomeNilClearsOptionalFields() {
        let p = everyFieldSpelledOut()
        XCTAssertNil(p.with(background: .some(nil)).background)
        XCTAssertNil(p.with(backgroundAlpha: .some(nil)).backgroundAlpha)
        XCTAssertNil(p.with(vibrancyMaterial: .some(nil)).vibrancyMaterial)
    }

    /// `applying(_:)` must still move exactly the accent trio and hold every
    /// other role steady — the property its docstring promises, now that it is
    /// three arguments instead of a restated fourteen.
    func testApplyingMovesOnlyTheAccentTrio() {
        let p = everyFieldSpelledOut()
        let moved = p.with(primary: probe, secondary: probe, selection: probe)
        XCTAssertEqual(moved.primary, probe)
        XCTAssertEqual(moved.secondary, probe)
        XCTAssertEqual(moved.selection, probe)
        XCTAssertEqual(moved.background, p.background)
        XCTAssertEqual(moved.foreground, p.foreground)
        XCTAssertEqual(moved.muted, p.muted)
        XCTAssertEqual(moved.tertiary, p.tertiary)
        XCTAssertEqual(moved.border, p.border)
        XCTAssertEqual(moved.hover, p.hover)
        XCTAssertEqual(moved.error, p.error)
        XCTAssertEqual(moved.font, p.font)
        XCTAssertEqual(moved.backgroundAlpha, p.backgroundAlpha)
        XCTAssertEqual(moved.vibrancyMaterial, p.vibrancyMaterial)
        XCTAssertEqual(moved.forceDarkAqua, p.forceDarkAqua)
    }
}
