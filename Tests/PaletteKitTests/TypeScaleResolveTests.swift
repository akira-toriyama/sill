// Font-dispatch fidelity — the resolver honours ALL four FontKinds. The
// bug #8 fixed: ten per-widget `themedFont` helpers branched only `.mono`
// vs system and DROPPED `.rounded`/`.menu`, so the catalog's six rounded
// themes (and the menu preset) rendered the wrong family.
// `ResolvedPalette.uiFont` is now the single factory; these lock its
// dispatch + the role tokens. (CI-only: XCTest needs full Xcode.)
import XCTest
import AppKit
@testable import Palette
@testable import PaletteKit

@MainActor
final class TypeScaleResolveTests: XCTestCase {

    private func palette(_ font: FontKind) -> ResolvedPalette {
        resolve(ThemeSpec(
            background: HexColor(0x101010), foreground: HexColor(0xEEEEEE),
            muted: HexColor(0x888888), primary: HexColor(0x3B82F6), font: font))
    }

    /// The NSFontDescriptor weight trait (≈ 0.0 regular, 0.23 medium,
    /// 0.3 semibold) — the canonical way to read an applied weight.
    private func weightTrait(_ f: NSFont) -> CGFloat {
        let traits = f.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        return (traits?[.weight] as? CGFloat) ?? 0
    }

    // MARK: - family dispatch (the bug fix)

    func testMonoResolvesMonospaced() {
        let f = palette(.mono).uiFont(.body)
        XCTAssertEqual(f.pointSize, 13, accuracy: 0.01)
        XCTAssertTrue(f.isFixedPitch, "mono theme must resolve a monospaced font")
    }

    func testRoundedDiffersFromSystem() {
        // Before #8 both fell through to plain `systemFont`; the rounded
        // design must actually apply now.
        let rounded = palette(.rounded).uiFont(.body)
        let system  = palette(.system).uiFont(.body)
        XCTAssertEqual(rounded.pointSize, 13, accuracy: 0.01)
        XCTAssertNotEqual(rounded.fontName, system.fontName,
                          "rounded theme must not fall through to system font")
    }

    func testMenuResolvesMenuFont() {
        let f = palette(.menu).uiFont(.body)
        XCTAssertEqual(f.fontName, NSFont.menuFont(ofSize: 13).fontName)
    }

    func testSystemResolvesProportional() {
        let f = palette(.system).uiFont(.body)
        XCTAssertEqual(f.pointSize, 13, accuracy: 0.01)
        XCTAssertFalse(f.isFixedPitch)
    }

    // MARK: - role tokens

    func testSecondaryBodyIsElevenMedium() {
        let f = palette(.system).uiFont(.secondaryBody)
        XCTAssertEqual(f.pointSize, 11, accuracy: 0.01)
        XCTAssertGreaterThan(weightTrait(f), 0.1, "secondaryBody must be medium, not regular")
    }

    func testBadgeIsTenMedium() {
        let f = palette(.system).uiFont(.badge)
        XCTAssertEqual(f.pointSize, 10, accuracy: 0.01)
        XCTAssertGreaterThan(weightTrait(f), 0.1)
    }

    func testSectionHeaderIsElevenSemibold() {
        let f = palette(.system).uiFont(.sectionHeader)
        XCTAssertEqual(f.pointSize, 11, accuracy: 0.01)
        XCTAssertGreaterThan(weightTrait(f), 0.25, "sectionHeader must be semibold")
    }

    func testExplicitPtWeightOverload() {
        let f = palette(.system).uiFont(15, .semibold)
        XCTAssertEqual(f.pointSize, 15, accuracy: 0.01)
        XCTAssertGreaterThan(weightTrait(f), 0.25)
    }
}
