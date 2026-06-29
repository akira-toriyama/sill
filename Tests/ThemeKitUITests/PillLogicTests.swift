// ThemeKitUI / ThemedPill PURE logic tests — deterministic, no window / no
// resolved palette. These first run in CI (XCTest is unavailable on the
// CLT-only host). The rendering itself is proven LIVE in prism, not here.

import XCTest
@testable import ThemeKitUI

final class PillLogicTests: XCTestCase {

    func test_splitLabel_clampsAndSplits() {
        XCTAssertEqual(PillLogic.splitLabel("ABC", typedCount: 0).prefix, "")
        XCTAssertEqual(PillLogic.splitLabel("ABC", typedCount: 0).suffix, "ABC")
        XCTAssertEqual(PillLogic.splitLabel("ABC", typedCount: 1).prefix, "A")
        XCTAssertEqual(PillLogic.splitLabel("ABC", typedCount: 1).suffix, "BC")
        XCTAssertEqual(PillLogic.splitLabel("ABC", typedCount: 3).suffix, "")
        XCTAssertEqual(PillLogic.splitLabel("ABC", typedCount: 9).prefix, "ABC")   // clamp high
        XCTAssertEqual(PillLogic.splitLabel("ABC", typedCount: -2).prefix, "")     // clamp low
        XCTAssertEqual(PillLogic.splitLabel("", typedCount: 1).prefix, "")         // empty
    }

    func test_circleEligibility_singleGlyphOnly() {
        XCTAssertTrue(PillLogic.isCircleEligible("A"))
        XCTAssertTrue(PillLogic.isCircleEligible(""))
        XCTAssertFalse(PillLogic.isCircleEligible("AB"))
    }

    func test_resolvedShape_circleFallsBackToPillWhenMultiChar() {
        XCTAssertEqual(PillLogic.resolvedShape(.circle, label: "A"), .circle)
        XCTAssertEqual(PillLogic.resolvedShape(.circle, label: "AB"), .pill)
        XCTAssertEqual(PillLogic.resolvedShape(.tag, label: "AB"), .tag)            // others unchanged
        XCTAssertEqual(PillLogic.resolvedShape(.underline, label: "AB"), .underline)
    }

    func test_prefixUsesError_onlyOnMiss() {
        XCTAssertTrue(PillLogic.prefixUsesError(.miss))
        XCTAssertFalse(PillLogic.prefixUsesError(.idle))
        XCTAssertFalse(PillLogic.prefixUsesError(.matched))
    }

    func test_showsEffectRim_idleAndMatchedButNeverMiss() {
        // No effect ⇒ never a rim, in any state (keeps the static tri-state border).
        XCTAssertFalse(PillLogic.showsEffectRim(hasEffect: false, state: .idle))
        XCTAssertFalse(PillLogic.showsEffectRim(hasEffect: false, state: .matched))
        XCTAssertFalse(PillLogic.showsEffectRim(hasEffect: false, state: .miss))
        // Effect set ⇒ rim on idle/matched; suppressed on miss so the red error
        // stroke wins.
        XCTAssertTrue(PillLogic.showsEffectRim(hasEffect: true, state: .idle))
        XCTAssertTrue(PillLogic.showsEffectRim(hasEffect: true, state: .matched))
        XCTAssertFalse(PillLogic.showsEffectRim(hasEffect: true, state: .miss))
    }
}
