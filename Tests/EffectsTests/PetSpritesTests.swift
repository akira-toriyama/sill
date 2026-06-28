import XCTest
@testable import Effects
import PixelArt

final class PetSpritesTests: XCTestCase {
    // Pac mouth SNAPS through chompMouthFrames at chompMouthHz via frameStep, so
    // two `now` values landing in different frame buckets give different sprites.
    func testPacMouthSnapsBetweenPhases() {
        let closed = chompPacSprite(now: 0)                    // frame 0 (mouth 0)
        let open   = chompPacSprite(now: 2.0 / chompMouthHz / 4) // a later bucket
        XCTAssertEqual(closed.width, chompFaceCells)
        XCTAssertEqual(closed.height, chompFaceCells)
        XCTAssertNotEqual(closed.cells().count, open.cells().count,
                          "mouth wedge changes the filled-cell count across frames")
    }
    // Ghost waddle swaps poses at waddleHz; the look picks the gaze grid.
    func testGhostWaddleSwapsAndLookMatters() {
        let a = chompGhostSprite(now: 0, look: .right)
        let b = chompGhostSprite(now: 1.0 / CanonicalSprite.waddleHz / 2 + 1e-6, look: .right)
        XCTAssertNotEqual(a, b, "feet pose swaps across the waddle half-cycle")
        XCTAssertNotEqual(chompGhostSprite(now: 0, look: .left),
                          chompGhostSprite(now: 0, look: .right),
                          "gaze direction changes the sprite")
    }
    // Negative now folds forward (frameStep convention) — no crash, deterministic.
    func testNegativeNowIsStable() {
        XCTAssertEqual(chompPacSprite(now: -3.21), chompPacSprite(now: -3.21))
    }
}
