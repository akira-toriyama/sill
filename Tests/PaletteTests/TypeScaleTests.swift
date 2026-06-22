// TypeScale drift guards — the FIXED internal type scale (`TypeRole` →
// `TypeToken`) is the single source of the widget kit's text sizes +
// weights, replacing the per-widget hardcoded literals. These pin the
// table so a future edit can't silently regress it (e.g. the 9pt compact
// badge that #8 raised to the 10pt native floor) and lock the no-sub-10pt
// invariant. Pure — no AppKit.
import XCTest
import Palette

final class TypeScaleTests: XCTestCase {

    /// The fixed role → (pt, weight) table, grounded in MUI by role and
    /// macOS-native point sizes. A change here is deliberate, not drift.
    func testFixedTokenTable() {
        XCTAssertEqual(TypeRole.body.token,          TypeToken(13, .regular))
        XCTAssertEqual(TypeRole.secondaryBody.token, TypeToken(11, .medium))
        XCTAssertEqual(TypeRole.caption.token,       TypeToken(11, .regular))
        XCTAssertEqual(TypeRole.sectionHeader.token, TypeToken(11, .semibold))
        XCTAssertEqual(TypeRole.sectionTitle.token,  TypeToken(13, .medium))
        XCTAssertEqual(TypeRole.badge.token,         TypeToken(10, .medium))
        XCTAssertEqual(TypeRole.shortcut.token,      TypeToken(10, .medium))
        XCTAssertEqual(TypeRole.tooltip.token,       TypeToken(11, .medium))
    }

    /// The readability fix — secondary supporting text is MEDIUM (MUI's
    /// weight-emphasis: subtitle2 = 14px/500), not the old regular.
    func testSecondaryBodyIsMedium() {
        XCTAssertEqual(TypeRole.secondaryBody.token.weight, .medium)
    }

    /// No role dips below the macOS `labelFontSize` floor (10pt). Guards
    /// the old 9pt compact badge from creeping back.
    func testNoRoleBelowTenPoint() {
        for role in TypeRole.allCases {
            XCTAssertGreaterThanOrEqual(
                role.token.pt, 10,
                "TypeRole.\(role) dips below the 10pt native floor")
        }
    }

    /// Vocabulary completeness — the case counts are stable references; an
    /// addition extends them deliberately.
    func testVocabularyCounts() {
        XCTAssertEqual(TypeRole.allCases.count, 8)
        XCTAssertEqual(TypeWeight.allCases.count, 3)
    }
}
