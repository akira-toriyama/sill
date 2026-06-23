// Pure pet-placement selectors (#17h): "now → the sprite to draw" for the
// pac / ghost line-pets, so the SwiftUI-native ThemeKitUI views and the AppKit
// `drawChompPet`/`drawGhostPet` share ONE frame-selection source of truth.
#if canImport(CoreGraphics)
import Foundation
import PixelArt
import Motion

/// The pac line-pet at `now`: a `chompFaceCells`-wide PixelSprite whose mouth
/// wedge SNAPS through `chompMouthFrames` at `chompMouthHz` (the retro swap).
/// Pac-yellow filled cells; every other cell transparent. The wedge opens
/// toward +x (travel) — the caller rotates by the lap tangent.
public func chompPacSprite(now: Double) -> PixelSprite {
    let phase = ThemedTransition.frameStep(now: now, hz: chompMouthHz, frames: chompMouthFrames)
    let cells = pacManCells(diameterCells: chompFaceCells, mouthHalfRad: mouthHalfRad(phase: phase))
    let filled = Set(cells.map { GridPoint(col: $0.col, row: $0.row) })
    let yellowChar: Character = "Y"
    var rows: [String] = []
    for r in 0..<chompFaceCells {
        var line = ""
        for c in 0..<chompFaceCells {
            line.append(filled.contains(GridPoint(col: c, row: r)) ? yellowChar : " ")
        }
        rows.append(line)
    }
    return PixelSprite(rows: rows, palette: [yellowChar: SpriteColor.pacYellow])
}

/// The waddling Blinky frame for `look` at `now` (poses swap at `waddleHz`).
public func chompGhostSprite(now: Double, look: GhostLook) -> PixelSprite {
    ThemedTransition.frameStep(now: now, hz: CanonicalSprite.waddleHz,
                               frames: CanonicalSprite.ghostFrames(look: look))
}

private struct GridPoint: Hashable { let col: Int; let row: Int }
#endif
