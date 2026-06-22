// Elevation resolver fidelity — `ResolvedPalette.shadow(_:)` is the AppKit
// side of #13's elevation scale (the analogue of `uiFont(_ role:)`): it wraps
// the pure `ElevationToken` Doubles to CALayer-ready `(opacity, radius,
// offsetY)` and applies the y-up sign flip so widgets stop hand-writing the
// minus. These lock that mapping + the negation. (CI-only: XCTest needs full
// Xcode; the resolver is otherwise live-verified in prism's TokenSpecimen.)
import XCTest
import AppKit
@testable import Palette
@testable import PaletteKit

@MainActor
final class ElevationResolveTests: XCTestCase {

    private var pal: ResolvedPalette {
        resolve(ThemeSpec(
            background: HexColor(0x101010), foreground: HexColor(0xEEEEEE),
            muted: HexColor(0x888888), primary: HexColor(0x3B82F6), font: .system))
    }

    func testFlatResolvesToNoShadow() {
        let s = pal.shadow(.flat)
        XCTAssertEqual(s.opacity, 0)
        XCTAssertEqual(s.radius, 0)
        XCTAssertEqual(s.offsetY, 0)
    }

    /// The token's positive-down `dy` is returned NEGATED for sill's y-up
    /// (`isFlipped == false`) layer space — the whole reason the accessor
    /// exists. opacity/radius pass straight through (typed to Float/CGFloat).
    func testOffsetYIsNegatedForYUp() {
        let s = pal.shadow(.dp8)   // token dy = 3 (positive down)
        XCTAssertEqual(s.opacity, 0.28, accuracy: 0.0001)
        XCTAssertEqual(s.radius, 8, accuracy: 0.0001)
        XCTAssertEqual(s.offsetY, -3, accuracy: 0.0001, "downward shadow must sit at −y")
    }

    /// Every level round-trips its token: opacity→Float, blur→radius,
    /// dy→−offsetY. A drift in the wrap would surface here.
    func testEveryLevelMatchesItsNegatedToken() {
        for level in Elevation.allCases {
            let t = level.token
            let s = pal.shadow(level)
            XCTAssertEqual(s.opacity, Float(t.opacity), accuracy: 0.0001, "\(level) opacity")
            XCTAssertEqual(s.radius, CGFloat(t.blur), accuracy: 0.0001, "\(level) radius")
            XCTAssertEqual(s.offsetY, CGFloat(-t.dy), accuracy: 0.0001, "\(level) offsetY")
        }
    }
}
