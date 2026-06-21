// Sprite tests — the canonical chomp arcade sprites + the AppKit blitter.
//
// The sprite GRIDS are pure data, so the dimension checks (every row the
// documented width, the documented row count) are the backstop `swift build`
// can't provide — a ragged row compiles fine but skews `cells()`, so CI catches
// it here (the maintainer's machine is CLT-only; `import XCTest` needs Xcode).
// The intrinsic-colour assertions lock the ThemeSpec.chomp reconciliation. The
// draw is a smoke test only — real visual proof is the prism live capture.

import XCTest
import AppKit
@testable import Palette
@testable import Effects
import PixelArt

@MainActor
final class SpriteTests: XCTestCase {

    // MARK: - Canonical sprite dimensions (the ragged-row backstop)

    func testCherryDimensions() {
        let c = CanonicalSprite.cherry
        XCTAssertEqual(c.height, 13)
        XCTAssertEqual(c.width, 12)
        XCTAssertTrue(c.rows.allSatisfy { $0.count == 12 }, "ragged cherry row: \(c.rows)")
    }

    func testGhostDimensions() {
        for ghost in [CanonicalSprite.ghost, CanonicalSprite.ghostAlt] {
            XCTAssertEqual(ghost.height, 14)
            XCTAssertEqual(ghost.width, 14)
            XCTAssertTrue(ghost.rows.allSatisfy { $0.count == 14 }, "ragged ghost row: \(ghost.rows)")
        }
    }

    func testGhostAltSharesBodyButDiffersInFeet() {
        let a = CanonicalSprite.ghost.rows
        let b = CanonicalSprite.ghostAlt.rows
        XCTAssertEqual(Array(a.prefix(12)), Array(b.prefix(12)))   // body identical
        XCTAssertNotEqual(Array(a.suffix(2)), Array(b.suffix(2)))  // skirt poses differ
    }

    func testGhostHasWhiteEyesAndBluePupils() {
        // The eye region produces both eye-white and pupil-blue cells.
        let colors = Set(CanonicalSprite.ghost.cells().map(\.color))
        XCTAssertTrue(colors.contains(SpriteColor.eyeWhite))
        XCTAssertTrue(colors.contains(SpriteColor.pupilBlue))
        XCTAssertTrue(colors.contains(SpriteColor.ghostRed))
    }

    // MARK: - Intrinsic colours (ThemeSpec.chomp reconciliation)

    func testArcadeColoursMatchChompRoles() {
        // Assert against the LIVE ThemeSpec.chomp roles (NOT baked literals) so a
        // future edit that drifts the theme from the sprites fails right here —
        // that is the whole point of this guard. (error/primary are non-optional;
        // secondary is HexColor? — the optional promotes for the comparison.)
        XCTAssertEqual(SpriteColor.pacYellow, ThemeSpec.chomp.primary.rgb)
        XCTAssertEqual(SpriteColor.ghostRed, ThemeSpec.chomp.error.rgb)
        XCTAssertEqual(SpriteColor.pupilBlue, ThemeSpec.chomp.secondary?.rgb)
    }

    // MARK: - AppKit draw (smoke — real visual proof is the prism live capture)

    func testDrawRunsIntoAContext() {
        let img = NSImage(size: NSSize(width: 120, height: 120))
        img.lockFocus()
        drawPixelSprite(CanonicalSprite.ghost, cell: 4, at: .zero)
        drawPixelSprite(CanonicalSprite.cherry, cell: 4, at: NSPoint(x: 60, y: 0),
                        color: SpriteColor.pacYellow)   // single-tint override path
        drawPacMan(diameterCells: 13, mouthHalfRad: mouthHalfRad(phase: 0.5),
                   cell: 3, at: NSPoint(x: 0, y: 60))
        img.unlockFocus()
    }
}
