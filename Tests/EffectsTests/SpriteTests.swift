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

    // MARK: - Waddle animation data (#12 Ph2)

    func testWaddleFramesAreTheTwoPoses() {
        XCTAssertEqual(CanonicalSprite.waddleFrames, [CanonicalSprite.ghost, CanonicalSprite.ghostAlt])
    }

    func testLegsWaddleSlowerThanTheMouthChatters() {
        // The retro look: a fast 5 Hz mouth over a slower leg shuffle.
        XCTAssertGreaterThan(CanonicalSprite.waddleHz, 0)
        XCTAssertLessThan(CanonicalSprite.waddleHz, chompMouthHz)
    }

    // MARK: - Directional-eye upright ghost (#12 Ph3)

    func testGhostLookFacingSnapsToCardinals() {
        // y-up convention (drawLinePets passes a NON-flipped rect, "top" = maxY):
        // +x→right, −x→left, +y→up, −y→down. These four are the perimeter
        // tangents the loop walks (top/right/bottom/left edges).
        XCTAssertEqual(GhostLook.facing(dx: 1, dy: 0), .right)
        XCTAssertEqual(GhostLook.facing(dx: -1, dy: 0), .left)
        XCTAssertEqual(GhostLook.facing(dx: 0, dy: 1), .up)
        XCTAssertEqual(GhostLook.facing(dx: 0, dy: -1), .down)
    }

    func testGhostLookFacingBoundaryPrefersHorizontal() {
        // On the exact 45° diagonal (|dx| == |dy|) the dominant-axis tie breaks
        // to HORIZONTAL, so a perfectly diagonal tangent never flickers to up/down.
        XCTAssertEqual(GhostLook.facing(dx: 1, dy: 1), .right)
        XCTAssertEqual(GhostLook.facing(dx: -1, dy: -1), .left)
        // Just past the diagonal the vertical axis wins.
        XCTAssertEqual(GhostLook.facing(dx: 0.4, dy: 1), .up)
        XCTAssertEqual(GhostLook.facing(dx: 0.4, dy: -1), .down)
    }

    func testDirectionalGhostSpritesAre14x14() {
        for look in [GhostLook.up, .right, .down, .left] {
            let s = CanonicalSprite.ghostSprite(feet: .a, look: look)
            XCTAssertEqual(s.height, 14, "\(look)")
            XCTAssertEqual(s.width, 14, "\(look)")
            XCTAssertTrue(s.rows.allSatisfy { $0.count == 14 }, "ragged \(look) ghost: \(s.rows)")
            let colors = Set(s.cells().map(\.color))
            XCTAssertTrue(colors.contains(SpriteColor.eyeWhite), "\(look) missing eye white")
            XCTAssertTrue(colors.contains(SpriteColor.pupilBlue), "\(look) missing pupil")
            XCTAssertTrue(colors.contains(SpriteColor.ghostRed), "\(look) missing body")
        }
    }

    func testPupilShiftsWithLook() {
        // The blue 2×2 pupils sit TOWARD the look direction: left-look pupils are
        // at lower columns than right-look; up-look pupils at lower rows than down.
        func bluePupil(_ look: GhostLook) -> [(col: Int, row: Int)] {
            CanonicalSprite.ghostSprite(feet: .a, look: look).cells()
                .filter { $0.color == SpriteColor.pupilBlue }
                .map { (col: $0.col, row: $0.row) }
        }
        XCTAssertLessThan(bluePupil(.left).map(\.col).min()!,
                          bluePupil(.right).map(\.col).min()!)
        XCTAssertLessThan(bluePupil(.up).map(\.row).min()!,
                          bluePupil(.down).map(\.row).min()!)
    }

    func testGhostFramesShareBodyDifferInFeet() {
        for look in [GhostLook.up, .right, .down, .left] {
            let frames = CanonicalSprite.ghostFrames(look: look)
            XCTAssertEqual(frames.count, 2, "\(look)")
            XCTAssertEqual(Array(frames[0].rows.prefix(12)), Array(frames[1].rows.prefix(12)),
                           "\(look): body+eyes must match across the waddle")
            XCTAssertNotEqual(Array(frames[0].rows.suffix(2)), Array(frames[1].rows.suffix(2)),
                              "\(look): the two skirt poses must differ")
        }
    }

    func testCanonicalGhostIsRightLookPoseA() {
        // The Ph2 right-looking ghost/ghostAlt are now the builder's outputs, so
        // there is ONE source of truth for the grid (no drift between the literals
        // and the Ph3 directional builder).
        XCTAssertEqual(CanonicalSprite.ghost, CanonicalSprite.ghostSprite(feet: .a, look: .right))
        XCTAssertEqual(CanonicalSprite.ghostAlt, CanonicalSprite.ghostSprite(feet: .b, look: .right))
    }

    // MARK: - AppKit draw (smoke — real visual proof is the prism live capture)

    func testUnifiedPixelLinePetsDrawRuns() {
        // The #12 Ph2 unified line-pets: drawLinePets now blits the PIXEL chomp +
        // ghost (mouth-flap via frameStep, ghost waddle via ghost⇄ghostAlt, y-flip
        // for the dome-up orientation). Smoke only — real proof is the prism live
        // capture; this just exercises the frameStep + flip-transform path at a
        // couple of clock values so a crash/regression reddens CI.
        let img = NSImage(size: NSSize(width: 160, height: 120))
        img.lockFocus()
        for now in [0.0, 0.125, 0.4] {   // closed-ish, full-gape, a waddle swap
            drawLinePets([.chomp, .ghost],
                         on: CGRect(x: 10, y: 10, width: 140, height: 100),
                         now: now, scale: 1.5)
        }
        img.unlockFocus()
    }

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
